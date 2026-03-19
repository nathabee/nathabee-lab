#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./docker/scripts/bootstrap-django.sh ENV PROJECT_NAME \
    [--requirements requirements.txt] \
    [--seed-command seed_all] \
    [--collectstatic] \
    [--skip-sync] \
    [--no-start-service]

Examples:
  ./docker/scripts/bootstrap-django.sh dev demo_fullstack

  ./docker/scripts/bootstrap-django.sh \
    dev demo_fullstack \
    --seed-command seed_all

  ./docker/scripts/bootstrap-django.sh \
    dev demo_fullstack \
    --collectstatic \
    --seed-command seed_beefont
EOF
}

require_cmd() {
  local cmd="${1:-}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

require_file() {
  local file="${1:-}"
  if [[ -z "${file}" || ! -f "${file}" ]]; then
    echo "Missing file: ${file}" >&2
    exit 1
  fi
}

run_django_once() {
  local shell_cmd="${1:-}"
  if [[ -z "${shell_cmd}" ]]; then
    echo "Missing Django shell command." >&2
    exit 1
  fi

  "${COMPOSE_CMD[@]}" run --rm --no-deps -T "${DJANGO_SERVICE}" sh -lc "${shell_cmd}"
}

wait_for_postgres() {
  local tries=60

  echo "Waiting for PostgreSQL health..."
  for _ in $(seq 1 "${tries}"); do
    if "${COMPOSE_CMD[@]}" exec -T "${DJANGO_DB_SERVICE}" sh -lc 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1; then
      echo "PostgreSQL is ready."
      return 0
    fi
    sleep 2
  done

  echo "PostgreSQL did not become ready in time." >&2
  return 1
}

ENV_NAME="${1:-}"
PROJECT_NAME="${2:-}"

if [[ -z "${ENV_NAME}" || -z "${PROJECT_NAME}" ]]; then
  usage
  exit 1
fi

shift 2

REQUIREMENTS_FILE="requirements.txt"
SEED_COMMAND=""
COLLECTSTATIC="false"
SYNC_RUNTIME="true"
START_SERVICE="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --requirements)
      REQUIREMENTS_FILE="${2:-}"
      shift 2
      ;;
    --seed-command)
      SEED_COMMAND="${2:-}"
      shift 2
      ;;
    --collectstatic)
      COLLECTSTATIC="true"
      shift
      ;;
    --skip-sync)
      SYNC_RUNTIME="false"
      shift
      ;;
    --no-start-service)
      START_SERVICE="false"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "${ENV_NAME}" != "dev" && "${ENV_NAME}" != "prod" ]]; then
  echo "ENV must be dev or prod." >&2
  exit 1
fi

if [[ ! "${PROJECT_NAME}" =~ ^[a-z0-9_]+$ ]]; then
  echo "Invalid project name: ${PROJECT_NAME}" >&2
  exit 1
fi

require_cmd docker
require_cmd jq
require_cmd rsync

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${DOCKER_DIR}/.." && pwd)"

WORLD_FILE="${REPO_ROOT}/data/world-list.json"
COMPOSE_FILE="${DOCKER_DIR}/compose.yaml"
DATA_DJANGO_DIR="${REPO_ROOT}/data/${PROJECT_NAME}/django"
RUNTIME_DJANGO_DIR="${DOCKER_DIR}/runtime/${PROJECT_NAME}_django"

if [[ "${ENV_NAME}" == "dev" ]]; then
  ENV_FILE="${DOCKER_DIR}/.env.dev"
else
  ENV_FILE="${DOCKER_DIR}/.env.prod"
fi

require_file "${WORLD_FILE}"
require_file "${COMPOSE_FILE}"
require_file "${ENV_FILE}"

PROJECT_JSON="$(
  jq -e --arg name "${PROJECT_NAME}" '
    (.projects // .)[] | select((.projectname // .name) == $name)
  ' "${WORLD_FILE}"
)"

PROJECT_TYPE="$(printf '%s\n' "${PROJECT_JSON}" | jq -r '.projecttype // empty')"
if [[ "${PROJECT_TYPE}" != "fullstack" ]]; then
  echo "Project ${PROJECT_NAME} is not a fullstack project." >&2
  exit 1
fi

DJANGO_SERVICE="$(printf '%s\n' "${PROJECT_JSON}" | jq -r '.compose.django_service // empty')"
DJANGO_DB_SERVICE="$(printf '%s\n' "${PROJECT_JSON}" | jq -r '.compose.django_db_service // empty')"

if [[ -z "${DJANGO_SERVICE}" || -z "${DJANGO_DB_SERVICE}" ]]; then
  echo "Project ${PROJECT_NAME} is missing django_service or django_db_service in ${WORLD_FILE}." >&2
  exit 1
fi

if [[ ! -d "${DATA_DJANGO_DIR}" ]]; then
  echo "Missing Django source directory: ${DATA_DJANGO_DIR}" >&2
  echo "Put delivered Django code there before bootstrapping." >&2
  exit 1
fi

if [[ ! -f "${DATA_DJANGO_DIR}/manage.py" ]]; then
  echo "Missing ${DATA_DJANGO_DIR}/manage.py" >&2
  echo "Expected the contents of a compatible Django project in data/${PROJECT_NAME}/django/." >&2
  exit 1
fi

if [[ ! -f "${DATA_DJANGO_DIR}/${REQUIREMENTS_FILE}" ]]; then
  echo "Missing ${DATA_DJANGO_DIR}/${REQUIREMENTS_FILE}" >&2
  exit 1
fi

COMPOSE_CMD=(docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")

echo "Bootstrapping Django for project: ${PROJECT_NAME}"
echo "Environment: ${ENV_NAME}"
echo "Django DB service: ${DJANGO_DB_SERVICE}"
echo "Django service: ${DJANGO_SERVICE}"
echo "Data source: ${DATA_DJANGO_DIR}"
echo "Runtime target: ${RUNTIME_DJANGO_DIR}"

mkdir -p "${RUNTIME_DJANGO_DIR}"

if [[ "${SYNC_RUNTIME}" == "true" ]]; then
  echo "Stopping Django service before sync..."
  "${COMPOSE_CMD[@]}" stop "${DJANGO_SERVICE}" >/dev/null 2>&1 || true

  echo "Syncing data/${PROJECT_NAME}/django -> docker/runtime/${PROJECT_NAME}_django ..."
  rsync -av --delete \
    --exclude '.git/' \
    --exclude '.venv/' \
    --exclude '__pycache__/' \
    --exclude '.pytest_cache/' \
    --exclude '.coverage' \
    --exclude '*.pyc' \
    --exclude '*.pyo' \
    --exclude '*.pyd' \
    "${DATA_DJANGO_DIR}/" "${RUNTIME_DJANGO_DIR}/"
else
  echo "Skipping runtime sync."
fi

if [[ ! -f "${RUNTIME_DJANGO_DIR}/manage.py" ]]; then
  echo "Missing ${RUNTIME_DJANGO_DIR}/manage.py after sync." >&2
  exit 1
fi

echo "Starting Django database..."
"${COMPOSE_CMD[@]}" up -d "${DJANGO_DB_SERVICE}"

wait_for_postgres

echo "Checking Django project inside container..."
if ! run_django_once 'test -f /django/manage.py'; then
  echo "Missing /django/manage.py inside container." >&2
  exit 1
fi

if ! run_django_once "test -f /django/${REQUIREMENTS_FILE}"; then
  echo "Missing /django/${REQUIREMENTS_FILE} inside container." >&2
  exit 1
fi

echo "Creating/updating Django virtualenv..."
run_django_once "
  set -e
  cd /django
  python -m venv .venv
  ./.venv/bin/python -m pip install --upgrade pip
  ./.venv/bin/pip install -r ${REQUIREMENTS_FILE}
"

echo "Running Django migrations..."
run_django_once '
  set -e
  cd /django
  ./.venv/bin/python manage.py migrate
'

if [[ "${COLLECTSTATIC}" == "true" ]]; then
  echo "Running collectstatic..."
  run_django_once '
    set -e
    cd /django
    ./.venv/bin/python manage.py collectstatic --noinput
  '
fi

if [[ -n "${SEED_COMMAND}" ]]; then
  echo "Running seed command: ${SEED_COMMAND}"
  run_django_once "
    set -e
    cd /django
    ./.venv/bin/python manage.py ${SEED_COMMAND}
  "
fi

if [[ "${START_SERVICE}" == "true" ]]; then
  echo "Starting Django service..."
  "${COMPOSE_CMD[@]}" up -d "${DJANGO_SERVICE}"
else
  echo "Django service start skipped."
fi

echo
echo "Django bootstrap completed for ${PROJECT_NAME}."
echo "Requirements file: ${REQUIREMENTS_FILE}"
if [[ -n "${SEED_COMMAND}" ]]; then
  echo "Seed command executed: ${SEED_COMMAND}"
fi
if [[ "${COLLECTSTATIC}" == "true" ]]; then
  echo "collectstatic executed."
fi
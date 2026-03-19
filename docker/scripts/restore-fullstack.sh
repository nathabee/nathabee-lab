#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./docker/scripts/restore-fullstack.sh <dev|prod> <project> \
    [--requirements requirements.txt] \
    [--seed-command COMMAND] \
    [--collectstatic]

What it does:
  - restores the WordPress archive via restore-site.sh
  - prepares Django runtime via bootstrap-django.sh --no-start-service
  - imports the archived Django PostgreSQL dump
  - runs migrate
  - optionally runs collectstatic
  - optionally runs a seed command
  - starts the Django service

Important:
  The project must already exist in world-list.json and be active.
  If it was deleted before, run activate-project.sh first.
EOF
}

require_cmd() {
  local cmd="${1:-}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

resolve_env_value() {
  local key="${1:-}"

  if [[ -z "${key}" ]]; then
    echo "Missing env key in world-list.json" >&2
    exit 1
  fi

  if [[ -z "${!key-}" ]]; then
    echo "Env variable ${key} is not set in ${ENV_FILE}" >&2
    exit 1
  fi

  printf '%s\n' "${!key}"
}

wait_for_postgres() {
  local container_id
  container_id="$("${COMPOSE[@]}" ps -q "${DJANGO_DB_SERVICE}")"

  if [[ -z "${container_id}" ]]; then
    echo "Could not resolve container id for ${DJANGO_DB_SERVICE}" >&2
    exit 1
  fi

  until [[ "$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' "${container_id}")" == "healthy" ]]; do
    sleep 2
  done
}

run_django_once() {
  local shell_cmd="${1:-}"

  if [[ -z "${shell_cmd}" ]]; then
    echo "Missing Django shell command." >&2
    exit 1
  fi

  "${COMPOSE[@]}" run --rm --no-deps -T "${DJANGO_SERVICE}" sh -lc "${shell_cmd}"
}

MODE="${1:-}"
PROJECT_NAME="${2:-}"

if [[ -z "${MODE}" || -z "${PROJECT_NAME}" ]]; then
  usage
  exit 1
fi

shift 2

REQUIREMENTS_FILE="requirements.txt"
SEED_COMMAND=""
COLLECTSTATIC="false"

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

if [[ "${MODE}" != "dev" && "${MODE}" != "prod" ]]; then
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${STACK_DIR}/.." && pwd)"

ENV_FILE="${STACK_DIR}/.env.${MODE}"
WORLD_FILE="${REPO_ROOT}/data/world-list.json"
ARCHIVE_DIR="${REPO_ROOT}/data/${PROJECT_NAME}"
CONFIG_JSON="${ARCHIVE_DIR}/updateArchive.json"
DEFAULT_DJANGO_SQL_GZ="${ARCHIVE_DIR}/database/${PROJECT_NAME}_django.sql.gz"

require_cmd jq
require_cmd docker
require_cmd python3

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}" >&2
  exit 1
fi

if [[ ! -f "${WORLD_FILE}" ]]; then
  echo "Missing world list: ${WORLD_FILE}" >&2
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

PROJECT_JSON="$(
  jq -e --arg name "${PROJECT_NAME}" '
    (.projects // .)[] | select((.projectname // .name) == $name)
  ' "${WORLD_FILE}"
)"

ACTIVE="$(printf '%s\n' "${PROJECT_JSON}" | jq -r '.active // false')"
PROJECT_TYPE="$(printf '%s\n' "${PROJECT_JSON}" | jq -r '.projecttype // .type // empty')"

if [[ "${ACTIVE}" != "true" ]]; then
  echo "Project is inactive: ${PROJECT_NAME}" >&2
  echo "Run activate-project.sh ${PROJECT_NAME} first." >&2
  exit 1
fi

if [[ "${PROJECT_TYPE}" != "fullstack" ]]; then
  echo "Project ${PROJECT_NAME} is not a fullstack project." >&2
  exit 1
fi

DJANGO_SERVICE="$(printf '%s\n' "${PROJECT_JSON}" | jq -r '.compose.django_service // empty')"
DJANGO_DB_SERVICE="$(printf '%s\n' "${PROJECT_JSON}" | jq -r '.compose.django_db_service // empty')"
DJANGO_DB_NAME_KEY="$(printf '%s\n' "${PROJECT_JSON}" | jq -r '.env.django_db_name // empty')"
DJANGO_DB_USER_KEY="$(printf '%s\n' "${PROJECT_JSON}" | jq -r '.env.django_db_user // empty')"
DJANGO_DB_PASSWORD_KEY="$(printf '%s\n' "${PROJECT_JSON}" | jq -r '.env.django_db_password // empty')"

if [[ -z "${DJANGO_SERVICE}" || -z "${DJANGO_DB_SERVICE}" ]]; then
  echo "Project ${PROJECT_NAME} is missing Django service mapping in ${WORLD_FILE}." >&2
  exit 1
fi

DJANGO_DB_NAME="$(resolve_env_value "${DJANGO_DB_NAME_KEY}")"
DJANGO_DB_USER="$(resolve_env_value "${DJANGO_DB_USER_KEY}")"
DJANGO_DB_PASSWORD="$(resolve_env_value "${DJANGO_DB_PASSWORD_KEY}")"

DJANGO_SQL_GZ="${DEFAULT_DJANGO_SQL_GZ}"
if [[ -f "${CONFIG_JSON}" ]]; then
  META_DJANGO_DUMP="$(jq -r '.django_database_dump // empty' "${CONFIG_JSON}")"
  if [[ -n "${META_DJANGO_DUMP}" ]]; then
    DJANGO_SQL_GZ="${ARCHIVE_DIR}/${META_DJANGO_DUMP#./}"
  fi
fi

if [[ ! -f "${DJANGO_SQL_GZ}" ]]; then
  echo "Missing Django SQL dump: ${DJANGO_SQL_GZ}" >&2
  exit 1
fi

COMPOSE=(docker compose --env-file "${ENV_FILE}" -f "${STACK_DIR}/compose.yaml")

echo "Restoring fullstack project: ${PROJECT_NAME}"
echo "Environment: ${MODE}"

echo "Restoring WordPress portion..."
"${SCRIPT_DIR}/restore-site.sh" "${MODE}" "${PROJECT_NAME}"

echo "Preparing Django runtime..."
BOOTSTRAP_ARGS=(
  "${SCRIPT_DIR}/bootstrap-django.sh"
  "${MODE}"
  "${PROJECT_NAME}"
  --requirements "${REQUIREMENTS_FILE}"
  --no-start-service
)
"${BOOTSTRAP_ARGS[@]}"

wait_for_postgres

echo "Dropping existing Django schema..."
"${COMPOSE[@]}" exec -T "${DJANGO_DB_SERVICE}" sh -lc "
  set -e
  export PGPASSWORD='${DJANGO_DB_PASSWORD}'
  psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -U '${DJANGO_DB_USER}' -d '${DJANGO_DB_NAME}' <<SQL
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public AUTHORIZATION ${DJANGO_DB_USER};
GRANT ALL ON SCHEMA public TO ${DJANGO_DB_USER};
GRANT ALL ON SCHEMA public TO public;
SQL
"

echo "Importing Django database dump..."
gunzip -c "${DJANGO_SQL_GZ}" | "${COMPOSE[@]}" exec -T "${DJANGO_DB_SERVICE}" sh -lc "
  set -e
  export PGPASSWORD='${DJANGO_DB_PASSWORD}'
  psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -U '${DJANGO_DB_USER}' -d '${DJANGO_DB_NAME}'
"

echo "Running Django migrations after import..."
run_django_once '
  set -e
  cd /django
  if [ -x ./.venv/bin/python ]; then
    ./.venv/bin/python manage.py migrate
  else
    python manage.py migrate
  fi
'

if [[ "${COLLECTSTATIC}" == "true" ]]; then
  echo "Running collectstatic..."
  run_django_once '
    set -e
    cd /django
    if [ -x ./.venv/bin/python ]; then
      ./.venv/bin/python manage.py collectstatic --noinput
    else
      python manage.py collectstatic --noinput
    fi
  '
fi

if [[ -n "${SEED_COMMAND}" ]]; then
  echo "Running Django seed command: ${SEED_COMMAND}"
  run_django_once "
    set -e
    cd /django
    if [ -x ./.venv/bin/python ]; then
      ./.venv/bin/python manage.py ${SEED_COMMAND}
    else
      python manage.py ${SEED_COMMAND}
    fi
  "
fi

echo "Starting Django service..."
"${COMPOSE[@]}" up -d "${DJANGO_SERVICE}"

echo "Normalizing bind-mounted runtime permissions..."
"${SCRIPT_DIR}/mod-file-access.sh" "${MODE}" "${PROJECT_NAME}"

echo
echo "Fullstack restore complete: ${PROJECT_NAME}"

echo 
echo "WordPress restored."
echo "Django code restored from data/${PROJECT_NAME}/django."
echo "Django database restored from ${DJANGO_SQL_GZ}."
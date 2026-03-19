#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./docker/scripts/export-fullstack.sh <dev|prod> <project>

What it does:
  - exports the WordPress part via export-site.sh
  - syncs Django runtime code back into data/<project>/django
  - exports the Django PostgreSQL database to data/<project>/database/<project>_django.sql.gz
  - extends data/<project>/updateArchive.json with Django archive metadata
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

extract_mount_source() {
  local mount_value="${1:-}"

  if [[ -z "${mount_value}" ]]; then
    return 0
  fi

  printf '%s\n' "${mount_value%%:*}"
}

resolve_host_path() {
  local raw_path="${1:-}"

  if [[ -z "${raw_path}" ]]; then
    return 0
  fi

  case "${raw_path}" in
    /*)
      printf '%s\n' "${raw_path}"
      ;;
    ./*)
      printf '%s\n' "${STACK_DIR}/${raw_path#./}"
      ;;
    *)
      printf '%s\n' "${REPO_ROOT}/${raw_path}"
      ;;
  esac
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

MODE="${1:-}"
PROJECT_NAME="${2:-}"

if [[ -z "${MODE}" || -z "${PROJECT_NAME}" ]]; then
  usage
  exit 1
fi

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
DATA_DB_DIR="${ARCHIVE_DIR}/database"
DATA_DJANGO_DIR="${ARCHIVE_DIR}/django"
CONFIG_JSON="${ARCHIVE_DIR}/updateArchive.json"
DJANGO_SQL_GZ="${DATA_DB_DIR}/${PROJECT_NAME}_django.sql.gz"

require_cmd jq
require_cmd docker
require_cmd rsync
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
  exit 1
fi

if [[ "${PROJECT_TYPE}" != "fullstack" ]]; then
  echo "Project ${PROJECT_NAME} is not a fullstack project." >&2
  exit 1
fi

DJANGO_DB_SERVICE="$(printf '%s\n' "${PROJECT_JSON}" | jq -r '.compose.django_db_service // empty')"
DJANGO_CODE_MOUNT_KEY="$(printf '%s\n' "${PROJECT_JSON}" | jq -r '.env.django_code_mount // empty')"

if [[ -z "${DJANGO_DB_SERVICE}" || -z "${DJANGO_CODE_MOUNT_KEY}" ]]; then
  echo "Project ${PROJECT_NAME} is missing Django mapping in ${WORLD_FILE}." >&2
  exit 1
fi

DJANGO_CODE_MOUNT_VALUE="$(resolve_env_value "${DJANGO_CODE_MOUNT_KEY}")"
DJANGO_RUNTIME_DIR="$(resolve_host_path "$(extract_mount_source "${DJANGO_CODE_MOUNT_VALUE}")")"

if [[ -z "${DJANGO_RUNTIME_DIR}" || ! -d "${DJANGO_RUNTIME_DIR}" ]]; then
  echo "Missing Django runtime directory: ${DJANGO_RUNTIME_DIR}" >&2
  exit 1
fi

COMPOSE=(docker compose --env-file "${ENV_FILE}" -f "${STACK_DIR}/compose.yaml")

echo "Exporting fullstack project: ${PROJECT_NAME}"
echo "Environment: ${MODE}"

echo "Exporting WordPress portion..."
"${SCRIPT_DIR}/export-site.sh" "${MODE}" "${PROJECT_NAME}"

echo "Syncing Django runtime back to data/${PROJECT_NAME}/django ..."
mkdir -p "${DATA_DJANGO_DIR}"

rsync -av --delete \
  --exclude '.git/' \
  --exclude '.venv/' \
  --exclude '__pycache__/' \
  --exclude '.pytest_cache/' \
  --exclude '.coverage' \
  --exclude '.env' \
  --exclude '.env.dev' \
  --exclude '.env.prod' \
  --exclude '*.pyc' \
  --exclude '*.pyo' \
  --exclude '*.pyd' \
  "${DJANGO_RUNTIME_DIR}/" "${DATA_DJANGO_DIR}/"

mkdir -p "${DATA_DB_DIR}"

echo "Starting Django database service..."
"${COMPOSE[@]}" up -d "${DJANGO_DB_SERVICE}"

wait_for_postgres

echo "Exporting Django PostgreSQL database..."
rm -f "${DJANGO_SQL_GZ}"

"${COMPOSE[@]}" exec -T "${DJANGO_DB_SERVICE}" sh -lc '
  set -e
  export PGPASSWORD="$POSTGRES_PASSWORD"
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"
' | gzip -c > "${DJANGO_SQL_GZ}"

if [[ ! -s "${DJANGO_SQL_GZ}" ]]; then
  echo "Django SQL dump is empty: ${DJANGO_SQL_GZ}" >&2
  exit 1
fi

if ! gzip -t "${DJANGO_SQL_GZ}"; then
  echo "gzip verification failed for: ${DJANGO_SQL_GZ}" >&2
  exit 1
fi

if [[ ! -f "${CONFIG_JSON}" ]]; then
  echo "Missing WordPress archive metadata after export-site.sh: ${CONFIG_JSON}" >&2
  exit 1
fi

TMP_JSON="$(mktemp)"
jq \
  --arg projecttype "${PROJECT_TYPE}" \
  --arg django_database_dump "database/${PROJECT_NAME}_django.sql.gz" \
  --arg django_code_dir "django/" \
  --arg django_exported_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '.projecttype = $projecttype
   | .django_database_dump = $django_database_dump
   | .django_code_dir = $django_code_dir
   | .django_exported_at = $django_exported_at
   | .source_mode = "docker"' \
  "${CONFIG_JSON}" > "${TMP_JSON}"

mv "${TMP_JSON}" "${CONFIG_JSON}"

echo
echo "Fullstack export complete: ${PROJECT_NAME}"
echo "WordPress archive: data/${PROJECT_NAME}/wpfile + database/${PROJECT_NAME}.sql.gz"
echo "Django code:      data/${PROJECT_NAME}/django"
echo "Django database:  ${DJANGO_SQL_GZ}"
echo "Metadata:         ${CONFIG_JSON}"
#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
SITE="${2:-}"

usage() {
  echo "Usage: $0 <dev|prod> <site>"
}

if [[ "${MODE}" != "dev" && "${MODE}" != "prod" ]]; then
  usage
  exit 1
fi

if [[ -z "${SITE}" ]]; then
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${STACK_DIR}/.." && pwd)"
ENV_FILE="${STACK_DIR}/.env.${MODE}"
WORLD_FILE="${REPO_ROOT}/data/world-list.json"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1"
    exit 1
  fi
}

require_cmd jq
require_cmd docker

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}"
  exit 1
fi

if [[ ! -f "${WORLD_FILE}" ]]; then
  echo "Missing world list: ${WORLD_FILE}"
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

get_project_json() {
  jq -ec --arg site "$1" '
    (.projects // .)[] | select((.projectname // .name) == $site)
  ' "${WORLD_FILE}"
}

resolve_env_value() {
  local key="$1"

  if [[ -z "${key}" ]]; then
    echo "Missing env key in world-list.json"
    exit 1
  fi

  if [[ -z "${!key-}" ]]; then
    echo "Env variable ${key} is not set in ${ENV_FILE}"
    exit 1
  fi

  printf '%s' "${!key}"
}

PROJECT_JSON="$(get_project_json "${SITE}")" || {
  echo "Project not found in ${WORLD_FILE}: ${SITE}"
  exit 1
}

ACTIVE="$(jq -r '.active // false' <<< "${PROJECT_JSON}")"
PROJECT_TYPE="$(jq -r '.projecttype // .type // empty' <<< "${PROJECT_JSON}")"
PROJECT_NAME="$(jq -r '.projectname // .name // empty' <<< "${PROJECT_JSON}")"
STORAGE_MODE="$(jq -r '.storage_mode // "unknown"' <<< "${PROJECT_JSON}")"

if [[ "${ACTIVE}" != "true" ]]; then
  echo "Project is inactive: ${SITE}"
  exit 1
fi

if [[ "${PROJECT_TYPE}" != "wordpress" ]]; then
  echo "Project ${SITE} is not a wordpress project."
  exit 1
fi

DB_SERVICE="$(jq -r '.compose.db_service // empty' <<< "${PROJECT_JSON}")"
WP_SERVICE="$(jq -r '.compose.wp_service // empty' <<< "${PROJECT_JSON}")"
WPCLI_SERVICE="$(jq -r '.compose.wpcli_service // empty' <<< "${PROJECT_JSON}")"

DB_NAME_KEY="$(jq -r '.env.db_name // empty' <<< "${PROJECT_JSON}")"
DB_USER_KEY="$(jq -r '.env.db_user // empty' <<< "${PROJECT_JSON}")"
DB_PASSWORD_KEY="$(jq -r '.env.db_password // empty' <<< "${PROJECT_JSON}")"

if [[ -z "${DB_SERVICE}" || -z "${WP_SERVICE}" || -z "${WPCLI_SERVICE}" ]]; then
  echo "Project ${SITE} is missing compose service mapping in ${WORLD_FILE}"
  exit 1
fi

DB_NAME="$(resolve_env_value "${DB_NAME_KEY}")"
DB_USER="$(resolve_env_value "${DB_USER_KEY}")"
DB_PASSWORD="$(resolve_env_value "${DB_PASSWORD_KEY}")"

COMPOSE=(docker compose --env-file "${ENV_FILE}" -f "${STACK_DIR}/compose.yaml")
COMPOSE_CLI=(docker compose --profile cli --env-file "${ENV_FILE}" -f "${STACK_DIR}/compose.yaml")

ARCHIVE_DIR="${REPO_ROOT}/data/${PROJECT_NAME}"
DB_DIR="${ARCHIVE_DIR}/database"
WP_DIR="${ARCHIVE_DIR}/wpfile"
CONFIG_JSON="${ARCHIVE_DIR}/updateArchive.json"
SQL_GZ="${DB_DIR}/${PROJECT_NAME}.sql.gz"

wait_for_db_healthy() {
  local container_id
  container_id="$("${COMPOSE[@]}" ps -q "${DB_SERVICE}")"

  if [[ -z "${container_id}" ]]; then
    echo "Could not resolve container id for ${DB_SERVICE}"
    exit 1
  fi

  until [[ "$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' "${container_id}")" == "healthy" ]]; do
    sleep 2
  done
}

run_wpcli() {
  "${COMPOSE_CLI[@]}" run --rm -T --no-deps "${WPCLI_SERVICE}" wp --allow-root "$@"
}

run_wpcli_sh() {
  "${COMPOSE_CLI[@]}" run --rm -T --no-deps "${WPCLI_SERVICE}" sh -lc "$1"
}

echo "Exporting ${PROJECT_NAME}"
echo "Archive dir: ${ARCHIVE_DIR}"
echo "Storage mode: ${STORAGE_MODE}"

mkdir -p "${DB_DIR}"
rm -rf "${WP_DIR}"
mkdir -p "${WP_DIR}"
rm -f "${SQL_GZ}" "${CONFIG_JSON}"

echo "Starting database service..."
"${COMPOSE[@]}" up -d "${DB_SERVICE}"
wait_for_db_healthy
echo "Database container is healthy."

echo "Waiting for SQL connections as ${DB_USER}..."
until "${COMPOSE[@]}" exec -T "${DB_SERVICE}" mariadb \
  -h127.0.0.1 \
  -u"${DB_USER}" \
  -p"${DB_PASSWORD}" \
  -e "SELECT 1;" "${DB_NAME}" >/dev/null 2>&1; do
  sleep 2
done

echo "SQL connection is ready."

echo "Checking live WordPress files..."
run_wpcli_sh '[ -f /var/www/html/wp-config.php ] || { echo "Missing /var/www/html/wp-config.php"; exit 1; }'

echo "Extracting metadata..."
TABLE_PREFIX="$(run_wpcli db prefix | tr -d '\r')"
ORIGINAL_SITEURL="$(run_wpcli option get siteurl | tr -d '\r')"
ORIGINAL_HOME="$(run_wpcli option get home | tr -d '\r')"
HAS_BASIC_AUTH="$(run_wpcli_sh 'if [ -f /var/www/html/.htaccess ] && grep -Eq "^(AuthType|AuthName|AuthUserFile|Require)[[:space:]]" /var/www/html/.htaccess; then echo true; else echo false; fi' | tr -d '\r')"

if [[ -z "${TABLE_PREFIX}" ]]; then
  echo "Could not determine table prefix."
  exit 1
fi

echo "Exporting database dump..."
"${COMPOSE[@]}" exec -T "${DB_SERVICE}" mariadb-dump \
  -h127.0.0.1 \
  -u"${DB_USER}" \
  -p"${DB_PASSWORD}" \
  --single-transaction \
  --default-character-set=utf8mb4 \
  "${DB_NAME}" | gzip -c > "${SQL_GZ}"

echo "Exporting WordPress files..."
run_wpcli_sh 'cd /var/www/html && tar \
  --exclude=./wp-config.php \
  --exclude=./.htpasswd \
  --exclude=./.htaccess.restore.bak \
  -cf - .' | tar -xf - -C "${WP_DIR}"

echo "Writing updateArchive.json..."
jq -n \
  --arg projectname "${PROJECT_NAME}" \
  --arg projecttype "${PROJECT_TYPE}" \
  --arg mode "${MODE}" \
  --arg database_dump "database/${PROJECT_NAME}.sql.gz" \
  --arg table_prefix "${TABLE_PREFIX}" \
  --arg original_siteurl "${ORIGINAL_SITEURL}" \
  --arg original_home "${ORIGINAL_HOME}" \
  --arg exported_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg source_mode "docker" \
  --arg storage_mode "${STORAGE_MODE}" \
  --argjson has_basic_auth "${HAS_BASIC_AUTH}" \
  '{
    projectname: $projectname,
    projecttype: $projecttype,
    mode: $mode,
    database_dump: $database_dump,
    table_prefix: $table_prefix,
    original_siteurl: $original_siteurl,
    original_home: $original_home,
    has_basic_auth: $has_basic_auth,
    exported_at: $exported_at,
    source_mode: $source_mode,
    storage_mode: $storage_mode
  }' > "${CONFIG_JSON}"

echo "Export complete: ${PROJECT_NAME}"
echo "Database: ${SQL_GZ}"
echo "Files: ${WP_DIR}"
echo "Metadata: ${CONFIG_JSON}"

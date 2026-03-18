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
require_cmd python3
require_cmd rsync
require_cmd htpasswd

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
DB_HOST_RUNTIME="$(jq -r '.compose.db_host_runtime // empty' <<< "${PROJECT_JSON}")"

DB_NAME_KEY="$(jq -r '.env.db_name // empty' <<< "${PROJECT_JSON}")"
DB_USER_KEY="$(jq -r '.env.db_user // empty' <<< "${PROJECT_JSON}")"
DB_PASSWORD_KEY="$(jq -r '.env.db_password // empty' <<< "${PROJECT_JSON}")"
SITE_URL_KEY="$(jq -r '.env.site_url // empty' <<< "${PROJECT_JSON}")"

if [[ -z "${DB_SERVICE}" || -z "${WP_SERVICE}" || -z "${DB_HOST_RUNTIME}" ]]; then
  echo "Project ${SITE} is missing compose mapping in ${WORLD_FILE}"
  exit 1
fi

DB_NAME="$(resolve_env_value "${DB_NAME_KEY}")"
DB_USER="$(resolve_env_value "${DB_USER_KEY}")"
DB_PASSWORD="$(resolve_env_value "${DB_PASSWORD_KEY}")"
SITE_URL="$(resolve_env_value "${SITE_URL_KEY}")"

COMPOSE=(docker compose --env-file "${ENV_FILE}" -f "${STACK_DIR}/compose.yaml")

ARCHIVE_DIR="${REPO_ROOT}/data/${PROJECT_NAME}"
CONFIG_JSON="${ARCHIVE_DIR}/updateArchive.json"
WP_SOURCE_DIR="${ARCHIVE_DIR}/wpfile"
SQL_FILE="${ARCHIVE_DIR}/database/${PROJECT_NAME}.sql"
SQL_GZ="${SQL_FILE}.gz"

if [[ ! -d "${WP_SOURCE_DIR}" ]]; then
  echo "Missing archive directory: ${WP_SOURCE_DIR}"
  exit 1
fi

if [[ ! -f "${CONFIG_JSON}" ]]; then
  echo "Missing archive metadata: ${CONFIG_JSON}"
  exit 1
fi

if [[ ! -f "${SQL_FILE}" && ! -f "${SQL_GZ}" ]]; then
  echo "Missing SQL dump: ${SQL_FILE} or ${SQL_GZ}"
  exit 1
fi

TABLE_PREFIX="$(jq -r '.table_prefix // "wp_"' "${CONFIG_JSON}")"
ORIGINAL_SITEURL="$(jq -r '.original_siteurl // empty' "${CONFIG_JSON}")"
ORIGINAL_HOME="$(jq -r '.original_home // empty' "${CONFIG_JSON}")"
HAS_BASIC_AUTH="$(jq -r '.has_basic_auth // false' "${CONFIG_JSON}")"

TMP_RESTORE_DIR="$(mktemp -d "${STACK_DIR}/restore-${PROJECT_NAME}-XXXXXX")"
STAGED_WP_DIR="${TMP_RESTORE_DIR}/wp"
WP_CONFIG_RUNTIME="${STAGED_WP_DIR}/wp-config.php"
WP_CONFIG_SAMPLE="${STAGED_WP_DIR}/wp-config-sample.php"
HTACCESS_PATH="${STAGED_WP_DIR}/.htaccess"
HTPASSWD_PATH="${STAGED_WP_DIR}/.htpasswd"

cleanup() {
  rm -rf "${TMP_RESTORE_DIR}"
}
trap cleanup EXIT

echo "Restoring ${PROJECT_NAME}"
echo "Archive dir: ${ARCHIVE_DIR}"
echo "Storage mode: ${STORAGE_MODE}"
echo "Table prefix: ${TABLE_PREFIX}"
echo "Original siteurl: ${ORIGINAL_SITEURL}"
echo "Original home: ${ORIGINAL_HOME}"
echo "Target URL: ${SITE_URL}"
echo "Temporary staging dir: ${TMP_RESTORE_DIR}"

replace_wp_define() {
  local file="$1"
  local key="$2"
  local value="$3"

  python3 - "$file" "$key" "$value" <<'PY'
import re
import sys

path, key, value = sys.argv[1:4]

with open(path, "r", encoding="utf-8") as f:
    text = f.read()

safe_value = value.replace("\\", "\\\\").replace("'", "\\'")
replacement = f"define( '{key}', '{safe_value}' );"
pattern = re.compile(rf"define\(\s*['\"]{re.escape(key)}['\"]\s*,\s*['\"].*?['\"]\s*\);")

if pattern.search(text):
    text = pattern.sub(replacement, text, count=1)
else:
    if not text.endswith("\n"):
        text += "\n"
    text += replacement + "\n"

with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PY
}

replace_table_prefix() {
  local file="$1"
  local prefix="$2"

  python3 - "$file" "$prefix" <<'PY'
import re
import sys

path, prefix = sys.argv[1:3]

with open(path, "r", encoding="utf-8") as f:
    text = f.read()

replacement = f"$table_prefix = '{prefix}';"
pattern = re.compile(r"^\$table_prefix\s*=\s*'[^']*';", re.M)

if pattern.search(text):
    text = pattern.sub(replacement, text, count=1)
else:
    if not text.endswith("\n"):
        text += "\n"
    text += replacement + "\n"

with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PY
}

generate_wp_salts() {
  local file="$1"

  python3 - "$file" <<'PY'
import secrets
import string
import re
import sys

path = sys.argv[1]

keys = [
    "AUTH_KEY",
    "SECURE_AUTH_KEY",
    "LOGGED_IN_KEY",
    "NONCE_KEY",
    "AUTH_SALT",
    "SECURE_AUTH_SALT",
    "LOGGED_IN_SALT",
    "NONCE_SALT",
]

alphabet = string.ascii_letters + string.digits + string.punctuation

def make_secret(length=64):
    safe = alphabet.replace("\\", "").replace("'", "")
    return "".join(secrets.choice(safe) for _ in range(length))

with open(path, "r", encoding="utf-8") as f:
    text = f.read()

for key in keys:
    value = make_secret()
    replacement = f"define( '{key}', '{value}' );"
    pattern = re.compile(rf"define\(\s*['\"]{re.escape(key)}['\"]\s*,\s*['\"].*?['\"]\s*\);")
    if pattern.search(text):
        text = pattern.sub(replacement, text, count=1)
    else:
        if not text.endswith("\n"):
            text += "\n"
        text += replacement + "\n"

with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PY
}

prompt_basic_auth_credentials() {
  local site="$1"
  local pw1=""
  local pw2=""

  if [[ -n "${BASIC_AUTH_USER:-}" && -n "${BASIC_AUTH_PASSWORD:-}" ]]; then
    return 0
  fi

  if [[ ! -t 0 ]]; then
    echo "Basic Auth is required for ${site}, but no interactive terminal is available."
    echo "Set BASIC_AUTH_USER and BASIC_AUTH_PASSWORD, or run the restore interactively."
    exit 1
  fi

  while true; do
    read -r -p "Basic Auth username for ${site}: " BASIC_AUTH_USER
    if [[ -z "${BASIC_AUTH_USER}" ]]; then
      echo "Username must not be empty."
      continue
    fi

    read -r -s -p "Basic Auth password for ${site}: " pw1
    echo
    read -r -s -p "Confirm Basic Auth password for ${site}: " pw2
    echo

    if [[ -z "${pw1}" ]]; then
      echo "Password must not be empty."
      continue
    fi

    if [[ "${pw1}" != "${pw2}" ]]; then
      echo "Passwords do not match. Try again."
      continue
    fi

    BASIC_AUTH_PASSWORD="${pw1}"
    return 0
  done
}

write_basic_auth_file() {
  local file="$1"
  local user="$2"
  local password="$3"

  umask 077
  printf '%s\n' "${password}" | htpasswd -niB "${user}" > "${file}"
}

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

wait_for_wp_running() {
  local container_id
  container_id="$("${COMPOSE[@]}" ps -q "${WP_SERVICE}")"

  if [[ -z "${container_id}" ]]; then
    echo "Could not resolve container id for ${WP_SERVICE}"
    exit 1
  fi

  until [[ "$(docker inspect -f '{{.State.Status}}' "${container_id}")" == "running" ]]; do
    sleep 2
  done
}

echo "Preparing staged WordPress files..."
mkdir -p "${STAGED_WP_DIR}"

rsync -rltD --delete --no-owner --no-group \
  --exclude='wp-config.php' \
  --exclude='.htpasswd' \
  "${WP_SOURCE_DIR}/" "${STAGED_WP_DIR}/"

if [[ ! -f "${WP_CONFIG_SAMPLE}" ]]; then
  echo "Missing wp-config-sample.php in staged copy: ${WP_CONFIG_SAMPLE}"
  exit 1
fi

cp "${WP_CONFIG_SAMPLE}" "${WP_CONFIG_RUNTIME}"

echo "Creating wp-config.php from wp-config-sample.php..."
replace_wp_define "${WP_CONFIG_RUNTIME}" "DB_NAME" "${DB_NAME}"
replace_wp_define "${WP_CONFIG_RUNTIME}" "DB_USER" "${DB_USER}"
replace_wp_define "${WP_CONFIG_RUNTIME}" "DB_PASSWORD" "${DB_PASSWORD}"
replace_wp_define "${WP_CONFIG_RUNTIME}" "DB_HOST" "${DB_HOST_RUNTIME}"
replace_table_prefix "${WP_CONFIG_RUNTIME}" "${TABLE_PREFIX}"

echo "Generating fresh WordPress salts..."
generate_wp_salts "${WP_CONFIG_RUNTIME}"

if [[ -f "${HTACCESS_PATH}" ]]; then
  echo "Normalizing .htaccess for Docker runtime..."
  cp "${HTACCESS_PATH}" "${HTACCESS_PATH}.restore.bak"

  sed -i 's#^RewriteBase .*#RewriteBase /#' "${HTACCESS_PATH}" || true
  sed -i 's#^RewriteRule . /.*index\.php \[L\]#RewriteRule . /index.php [L]#' "${HTACCESS_PATH}" || true

  if grep -qE '^(AuthType|AuthName|AuthUserFile|Require)[[:space:]]' "${HTACCESS_PATH}"; then
    if [[ "${MODE}" == "dev" ]]; then
      echo "Disabling legacy Apache Basic Auth in dev restore..."
      sed -i -E '/^(AuthType|AuthName|AuthUserFile|Require)[[:space:]]/d' "${HTACCESS_PATH}"
      rm -f "${HTPASSWD_PATH}"
    else
      echo "Keeping Apache Basic Auth directives for prod restore..."
      sed -i 's#^AuthUserFile .*#AuthUserFile /var/www/html/.htpasswd#' "${HTACCESS_PATH}" || true

      prompt_basic_auth_credentials "${PROJECT_NAME}"
      write_basic_auth_file "${HTPASSWD_PATH}" "${BASIC_AUTH_USER}" "${BASIC_AUTH_PASSWORD}"
      echo "Created fresh .htpasswd for prod restore."
    fi
  fi
fi

if [[ "${MODE}" == "prod" && "${HAS_BASIC_AUTH}" == "true" && ! -f "${HTACCESS_PATH}" ]]; then
  echo "Archive metadata says basic auth existed, but no .htaccess was found in the staged files."
  echo "Recreate prod basic auth manually if this site still needs it."
fi

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

EXISTING_TABLES="$("${COMPOSE[@]}" exec -T "${DB_SERVICE}" mariadb \
  -h127.0.0.1 \
  -u"${DB_USER}" \
  -p"${DB_PASSWORD}" \
  -Nse "SHOW TABLES;" "${DB_NAME}" 2>/dev/null || true)"

if [[ -n "${EXISTING_TABLES}" ]]; then
  echo "Dropping existing tables in ${DB_NAME}..."
  DROP_SQL="SET FOREIGN_KEY_CHECKS=0;"
  while IFS= read -r TABLE_NAME; do
    [[ -n "${TABLE_NAME}" ]] && DROP_SQL+="DROP TABLE IF EXISTS \`${TABLE_NAME}\`;"
  done <<< "${EXISTING_TABLES}"
  DROP_SQL+="SET FOREIGN_KEY_CHECKS=1;"

  printf '%s\n' "${DROP_SQL}" | "${COMPOSE[@]}" exec -T "${DB_SERVICE}" mariadb \
    -h127.0.0.1 \
    -u"${DB_USER}" \
    -p"${DB_PASSWORD}" \
    "${DB_NAME}"
fi

echo "Importing database dump..."
if [[ -f "${SQL_GZ}" ]]; then
  gunzip -c "${SQL_GZ}" | "${COMPOSE[@]}" exec -T "${DB_SERVICE}" mariadb \
    -h127.0.0.1 \
    -u"${DB_USER}" \
    -p"${DB_PASSWORD}" \
    "${DB_NAME}"
else
  "${COMPOSE[@]}" exec -T "${DB_SERVICE}" mariadb \
    -h127.0.0.1 \
    -u"${DB_USER}" \
    -p"${DB_PASSWORD}" \
    "${DB_NAME}" < "${SQL_FILE}"
fi

echo "Updating siteurl and home..."
"${COMPOSE[@]}" exec -T "${DB_SERVICE}" mariadb \
  -h127.0.0.1 \
  -u"${DB_USER}" \
  -p"${DB_PASSWORD}" \
  "${DB_NAME}" <<SQL
UPDATE ${TABLE_PREFIX}options SET option_value='${SITE_URL}' WHERE option_name='siteurl';
UPDATE ${TABLE_PREFIX}options SET option_value='${SITE_URL}' WHERE option_name='home';
SQL

echo "Starting WordPress service..."
"${COMPOSE[@]}" up -d "${WP_SERVICE}"

wait_for_wp_running
echo "WordPress container is running."

echo "Clearing existing WordPress files inside mounted runtime..."
"${COMPOSE[@]}" exec -T "${WP_SERVICE}" sh -lc '
  set -eu
  find /var/www/html -mindepth 1 -maxdepth 1 -exec rm -rf {} +
'

echo "Copying staged WordPress files into mounted runtime..."
tar -C "${STAGED_WP_DIR}" -cf - . | "${COMPOSE[@]}" exec -T "${WP_SERVICE}" sh -lc '
  set -eu
  tar -xf - -C /var/www/html
'

echo "Fixing ownership inside container..."
"${COMPOSE[@]}" exec -T "${WP_SERVICE}" sh -lc '
  set -eu
  chown -R www-data:www-data /var/www/html
'

echo "Restarting WordPress service..."
"${COMPOSE[@]}" restart "${WP_SERVICE}"

echo "Restore complete: ${PROJECT_NAME}"
echo "URL: ${SITE_URL}"

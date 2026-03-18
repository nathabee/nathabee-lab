#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./docker/scripts/create-project.sh \
    --name PROJECT_NAME \
    --description "Human description" \
    --code ENV_CODE \
    --storage bind|volume \
    --dev-port 8084 \
    --prod-port 18084 \
    [--dev-url URL] \
    [--prod-url URL] \
    [--db-name DB_NAME] \
    [--db-user DB_USER] \
    [--bind-path ./runtime/PROJECT_NAME] \
    [--active true|false]

Examples:
  ./docker/scripts/create-project.sh \
    --name beeschool \
    --description "Bee School WordPress" \
    --code BEESCHOOL \
    --storage bind \
    --dev-port 8084 \
    --prod-port 18084 \
    --dev-url http://localhost:8084/ \
    --prod-url https://beeschool.nathabee.de/

  ./docker/scripts/create-project.sh \
    --name myclient \
    --description "Client site" \
    --code MYCLIENT \
    --storage volume \
    --dev-port 8085 \
    --prod-port 18085
EOF
}

require_cmd() {
  local cmd="${1:-}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}"
    exit 1
  fi
}

append_env_block_if_missing() {
  local file="$1"
  local key_check="$2"
  local block="$3"

  if [[ ! -f "${file}" ]]; then
    return 0
  fi

  if grep -q "^${key_check}=" "${file}"; then
    echo "Skipping ${file}: ${key_check} already exists."
    return 0
  fi

  {
    printf '\n'
    printf '%s\n' "${block}"
  } >> "${file}"
}

NAME=""
DESCRIPTION=""
CODE=""
STORAGE=""
DEV_PORT=""
PROD_PORT=""
DEV_URL=""
PROD_URL=""
DB_NAME=""
DB_USER=""
BIND_PATH=""
ACTIVE="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      NAME="${2:-}"
      shift 2
      ;;
    --description)
      DESCRIPTION="${2:-}"
      shift 2
      ;;
    --code)
      CODE="${2:-}"
      shift 2
      ;;
    --storage)
      STORAGE="${2:-}"
      shift 2
      ;;
    --dev-port)
      DEV_PORT="${2:-}"
      shift 2
      ;;
    --prod-port)
      PROD_PORT="${2:-}"
      shift 2
      ;;
    --dev-url)
      DEV_URL="${2:-}"
      shift 2
      ;;
    --prod-url)
      PROD_URL="${2:-}"
      shift 2
      ;;
    --db-name)
      DB_NAME="${2:-}"
      shift 2
      ;;
    --db-user)
      DB_USER="${2:-}"
      shift 2
      ;;
    --bind-path)
      BIND_PATH="${2:-}"
      shift 2
      ;;
    --active)
      ACTIVE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${NAME}" || -z "${DESCRIPTION}" || -z "${CODE}" || -z "${STORAGE}" || -z "${DEV_PORT}" || -z "${PROD_PORT}" ]]; then
  usage
  exit 1
fi

if [[ ! "${NAME}" =~ ^[a-z0-9_]+$ ]]; then
  echo "Invalid --name. Use lowercase letters, digits, underscore only."
  exit 1
fi

if [[ ! "${CODE}" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
  echo "Invalid --code. Use uppercase letters, digits, underscore only, starting with a letter."
  exit 1
fi

if [[ "${STORAGE}" != "bind" && "${STORAGE}" != "volume" ]]; then
  echo "Invalid --storage. Allowed: bind or volume."
  exit 1
fi

if [[ "${ACTIVE}" != "true" && "${ACTIVE}" != "false" ]]; then
  echo "Invalid --active. Allowed: true or false."
  exit 1
fi

if [[ ! "${DEV_PORT}" =~ ^[0-9]+$ || ! "${PROD_PORT}" =~ ^[0-9]+$ ]]; then
  echo "Ports must be numeric."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${DOCKER_DIR}/.." && pwd)"

WORLD_FILE="${REPO_ROOT}/data/world-list.json"
ROOT_COMPOSE_FILE="${DOCKER_DIR}/compose.yaml"
SITE_DIR="${DOCKER_DIR}/sites/${NAME}"
SITE_COMPOSE_FILE="${SITE_DIR}/compose.yaml"
DATA_SITE_DIR="${REPO_ROOT}/data/${NAME}"
DATA_DB_DIR="${DATA_SITE_DIR}/database"
DATA_WP_DIR="${DATA_SITE_DIR}/wpfile"
RUNTIME_DIR="${DOCKER_DIR}/runtime/${NAME}"

ENV_DEV_EXAMPLE="${DOCKER_DIR}/env.dev.example"
ENV_PROD_EXAMPLE="${DOCKER_DIR}/env.prod.example"
ENV_DEV_LOCAL="${DOCKER_DIR}/.env.dev"
ENV_PROD_LOCAL="${DOCKER_DIR}/.env.prod"

require_cmd jq
require_cmd python3

if [[ ! -f "${WORLD_FILE}" ]]; then
  echo "Missing world list: ${WORLD_FILE}"
  exit 1
fi

if [[ ! -f "${ENV_DEV_EXAMPLE}" ]]; then
  echo "Missing env example: ${ENV_DEV_EXAMPLE}"
  exit 1
fi

if [[ ! -f "${ENV_PROD_EXAMPLE}" ]]; then
  echo "Missing env example: ${ENV_PROD_EXAMPLE}"
  exit 1
fi

if jq -e --arg name "${NAME}" '
  (.projects // .)[] | select((.projectname // .name) == $name)
' "${WORLD_FILE}" >/dev/null 2>&1; then
  echo "Project already exists in world-list.json: ${NAME}"
  exit 1
fi

if grep -q "^${CODE}_PORT=" "${ENV_DEV_EXAMPLE}" || grep -q "^${CODE}_PORT=" "${ENV_PROD_EXAMPLE}"; then
  echo "Env code already exists in env examples: ${CODE}"
  exit 1
fi

if [[ -d "${SITE_DIR}" || -d "${DATA_SITE_DIR}" ]]; then
  echo "Project directories already exist for ${NAME}."
  exit 1
fi

if [[ -z "${DB_NAME}" ]]; then
  DB_NAME="${NAME}"
fi

if [[ -z "${DB_USER}" ]]; then
  DB_USER="${NAME}_user"
fi

if [[ -z "${DEV_URL}" ]]; then
  DEV_URL="http://localhost:${DEV_PORT}/"
fi

if [[ -z "${PROD_URL}" ]]; then
  PROD_URL="https://${NAME}.example.com/"
fi

if [[ -z "${BIND_PATH}" ]]; then
  BIND_PATH="./runtime/${NAME}"
fi

DB_SERVICE="db_${NAME}"
WP_SERVICE="wp_${NAME}"
WPCLI_SERVICE="wpcli_${NAME}"
DB_HOST_RUNTIME="${DB_SERVICE}:3306"
NETWORK_NAME="net_${NAME}"
DB_VOLUME="db_${NAME}"
WP_VOLUME="wp_${NAME}_data"

PORT_KEY="${CODE}_PORT"
SITE_URL_KEY="${CODE}_SITE_URL"
DB_NAME_KEY="${CODE}_DB_NAME"
DB_USER_KEY="${CODE}_DB_USER"
DB_PASSWORD_KEY="${CODE}_DB_PASSWORD"
DB_ROOT_PASSWORD_KEY="${CODE}_DB_ROOT_PASSWORD"
WP_FILES_MOUNT_KEY="${CODE}_WP_FILES_MOUNT"

DEV_DB_PASSWORD="change_me_dev_${NAME}_db_password"
DEV_DB_ROOT_PASSWORD="change_me_dev_${NAME}_root_password"
PROD_DB_PASSWORD="change_me_prod_${NAME}_db_password"
PROD_DB_ROOT_PASSWORD="change_me_prod_${NAME}_root_password"

if [[ "${STORAGE}" == "bind" ]]; then
  DEV_WP_MOUNT="${BIND_PATH}:/var/www/html"
  PROD_WP_MOUNT="${BIND_PATH}:/var/www/html"
else
  DEV_WP_MOUNT="${WP_VOLUME}:/var/www/html"
  PROD_WP_MOUNT="${WP_VOLUME}:/var/www/html"
fi

mkdir -p "${SITE_DIR}"
mkdir -p "${DATA_DB_DIR}" "${DATA_WP_DIR}"

if [[ "${STORAGE}" == "bind" ]]; then
  mkdir -p "${RUNTIME_DIR}"
fi

if [[ "${STORAGE}" == "bind" ]]; then
  cat > "${SITE_COMPOSE_FILE}" <<EOF
services:
  ${DB_SERVICE}:
    image: \${MARIADB_IMAGE}
    restart: unless-stopped
    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
    environment:
      MARIADB_ROOT_PASSWORD: \${${DB_ROOT_PASSWORD_KEY}}
      MARIADB_ROOT_HOST: localhost
      MARIADB_DATABASE: \${${DB_NAME_KEY}}
      MARIADB_USER: \${${DB_USER_KEY}}
      MARIADB_PASSWORD: \${${DB_PASSWORD_KEY}}
      MARIADB_AUTO_UPGRADE: "1"
    volumes:
      - ${DB_VOLUME}:/var/lib/mysql
    healthcheck:
      test: ["CMD-SHELL", "mariadb-admin ping -h 127.0.0.1 -uroot -p\$\$MARIADB_ROOT_PASSWORD || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s
    networks:
      - ${NETWORK_NAME}
    security_opt:
      - no-new-privileges:true

  ${WP_SERVICE}:
    image: \${WORDPRESS_IMAGE}
    restart: unless-stopped
    depends_on:
      ${DB_SERVICE}:
        condition: service_healthy
    ports:
      - "127.0.0.1:\${${PORT_KEY}}:80"
    environment:
      WORDPRESS_DB_HOST: ${DB_SERVICE}:3306
      WORDPRESS_DB_USER: \${${DB_USER_KEY}}
      WORDPRESS_DB_PASSWORD: \${${DB_PASSWORD_KEY}}
      WORDPRESS_DB_NAME: \${${DB_NAME_KEY}}
      WORDPRESS_DEBUG: \${WP_DEBUG}
      WORDPRESS_CONFIG_EXTRA: |
        define('FS_METHOD', 'direct');
    volumes:
      - \${${WP_FILES_MOUNT_KEY}}
    networks:
      - ${NETWORK_NAME}
    security_opt:
      - no-new-privileges:true

  ${WPCLI_SERVICE}:
    image: \${WORDPRESS_CLI_IMAGE}
    profiles: ["cli"]
    depends_on:
      ${DB_SERVICE}:
        condition: service_healthy
    environment:
      WORDPRESS_DB_HOST: ${DB_SERVICE}:3306
      WORDPRESS_DB_USER: \${${DB_USER_KEY}}
      WORDPRESS_DB_PASSWORD: \${${DB_PASSWORD_KEY}}
      WORDPRESS_DB_NAME: \${${DB_NAME_KEY}}
      WORDPRESS_CONFIG_EXTRA: |
        define('FS_METHOD', 'direct');
    volumes:
      - \${${WP_FILES_MOUNT_KEY}}
    working_dir: /var/www/html
    networks:
      - ${NETWORK_NAME}

volumes:
  ${DB_VOLUME}:

networks:
  ${NETWORK_NAME}:
EOF
else
  cat > "${SITE_COMPOSE_FILE}" <<EOF
services:
  ${DB_SERVICE}:
    image: \${MARIADB_IMAGE}
    restart: unless-stopped
    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
    environment:
      MARIADB_ROOT_PASSWORD: \${${DB_ROOT_PASSWORD_KEY}}
      MARIADB_ROOT_HOST: localhost
      MARIADB_DATABASE: \${${DB_NAME_KEY}}
      MARIADB_USER: \${${DB_USER_KEY}}
      MARIADB_PASSWORD: \${${DB_PASSWORD_KEY}}
      MARIADB_AUTO_UPGRADE: "1"
    volumes:
      - ${DB_VOLUME}:/var/lib/mysql
    healthcheck:
      test: ["CMD-SHELL", "mariadb-admin ping -h 127.0.0.1 -uroot -p\$\$MARIADB_ROOT_PASSWORD || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s
    networks:
      - ${NETWORK_NAME}
    security_opt:
      - no-new-privileges:true

  ${WP_SERVICE}:
    image: \${WORDPRESS_IMAGE}
    restart: unless-stopped
    depends_on:
      ${DB_SERVICE}:
        condition: service_healthy
    ports:
      - "127.0.0.1:\${${PORT_KEY}}:80"
    environment:
      WORDPRESS_DB_HOST: ${DB_SERVICE}:3306
      WORDPRESS_DB_USER: \${${DB_USER_KEY}}
      WORDPRESS_DB_PASSWORD: \${${DB_PASSWORD_KEY}}
      WORDPRESS_DB_NAME: \${${DB_NAME_KEY}}
      WORDPRESS_DEBUG: \${WP_DEBUG}
      WORDPRESS_CONFIG_EXTRA: |
        define('FS_METHOD', 'direct');
    volumes:
      - \${${WP_FILES_MOUNT_KEY}}
    networks:
      - ${NETWORK_NAME}
    security_opt:
      - no-new-privileges:true

  ${WPCLI_SERVICE}:
    image: \${WORDPRESS_CLI_IMAGE}
    profiles: ["cli"]
    depends_on:
      ${DB_SERVICE}:
        condition: service_healthy
    environment:
      WORDPRESS_DB_HOST: ${DB_SERVICE}:3306
      WORDPRESS_DB_USER: \${${DB_USER_KEY}}
      WORDPRESS_DB_PASSWORD: \${${DB_PASSWORD_KEY}}
      WORDPRESS_DB_NAME: \${${DB_NAME_KEY}}
      WORDPRESS_CONFIG_EXTRA: |
        define('FS_METHOD', 'direct');
    volumes:
      - \${${WP_FILES_MOUNT_KEY}}
    working_dir: /var/www/html
    networks:
      - ${NETWORK_NAME}

volumes:
  ${DB_VOLUME}:
  ${WP_VOLUME}:

networks:
  ${NETWORK_NAME}:
EOF
fi

if [[ ! -f "${ROOT_COMPOSE_FILE}" ]]; then
  cat > "${ROOT_COMPOSE_FILE}" <<EOF
include:
  - path: ./sites/${NAME}/compose.yaml
    project_directory: .
EOF
else
  if ! grep -Fq "./sites/${NAME}/compose.yaml" "${ROOT_COMPOSE_FILE}"; then
    cat >> "${ROOT_COMPOSE_FILE}" <<EOF
  - path: ./sites/${NAME}/compose.yaml
    project_directory: .
EOF
  fi
fi

NEW_PROJECT_JSON="$(
  jq -n \
    --arg projectname "${NAME}" \
    --arg projecttype "wordpress" \
    --argjson active "${ACTIVE}" \
    --arg description "${DESCRIPTION}" \
    --arg datecreation "$(date +%Y-%m-%d)" \
    --arg storage_mode "${STORAGE}" \
    --arg db_service "${DB_SERVICE}" \
    --arg wp_service "${WP_SERVICE}" \
    --arg wpcli_service "${WPCLI_SERVICE}" \
    --arg db_host_runtime "${DB_HOST_RUNTIME}" \
    --arg db_name_key "${DB_NAME_KEY}" \
    --arg db_user_key "${DB_USER_KEY}" \
    --arg db_password_key "${DB_PASSWORD_KEY}" \
    --arg site_url_key "${SITE_URL_KEY}" \
    '{
      projectname: $projectname,
      projecttype: $projecttype,
      active: $active,
      description: $description,
      datecreation: $datecreation,
      storage_mode: $storage_mode,
      compose: {
        db_service: $db_service,
        wp_service: $wp_service,
        wpcli_service: $wpcli_service,
        db_host_runtime: $db_host_runtime
      },
      env: {
        db_name: $db_name_key,
        db_user: $db_user_key,
        db_password: $db_password_key,
        site_url: $site_url_key
      }
    }'
)"

TMP_WORLD="$(mktemp)"
jq --argjson new_project "${NEW_PROJECT_JSON}" '
  .projects += [$new_project]
' "${WORLD_FILE}" > "${TMP_WORLD}"
mv "${TMP_WORLD}" "${WORLD_FILE}"

DEV_ENV_BLOCK="$(cat <<EOF
${PORT_KEY}=${DEV_PORT}
${SITE_URL_KEY}=${DEV_URL}
${DB_NAME_KEY}=${DB_NAME}
${DB_USER_KEY}=${DB_USER}
${DB_PASSWORD_KEY}=${DEV_DB_PASSWORD}
${DB_ROOT_PASSWORD_KEY}=${DEV_DB_ROOT_PASSWORD}
${WP_FILES_MOUNT_KEY}=${DEV_WP_MOUNT}
EOF
)"

PROD_ENV_BLOCK="$(cat <<EOF
${PORT_KEY}=${PROD_PORT}
${SITE_URL_KEY}=${PROD_URL}
${DB_NAME_KEY}=${DB_NAME}
${DB_USER_KEY}=${DB_USER}
${DB_PASSWORD_KEY}=${PROD_DB_PASSWORD}
${DB_ROOT_PASSWORD_KEY}=${PROD_DB_ROOT_PASSWORD}
${WP_FILES_MOUNT_KEY}=${PROD_WP_MOUNT}
EOF
)"

append_env_block_if_missing "${ENV_DEV_EXAMPLE}" "${PORT_KEY}" "${DEV_ENV_BLOCK}"
append_env_block_if_missing "${ENV_PROD_EXAMPLE}" "${PORT_KEY}" "${PROD_ENV_BLOCK}"
append_env_block_if_missing "${ENV_DEV_LOCAL}" "${PORT_KEY}" "${DEV_ENV_BLOCK}"
append_env_block_if_missing "${ENV_PROD_LOCAL}" "${PORT_KEY}" "${PROD_ENV_BLOCK}"

echo "Created project: ${NAME}"
echo "Description: ${DESCRIPTION}"
echo "Storage mode: ${STORAGE}"
echo "Site compose: ${SITE_COMPOSE_FILE}"
echo "World entry added: ${WORLD_FILE}"
echo "Env blocks added to examples and existing local env files if present."
echo
echo "Next checks:"
echo "  docker compose --env-file docker/.env.dev -f docker/compose.yaml config --services"
echo "  ./docker/scripts/up.sh dev"
echo
echo "Note:"
echo "  This script registers the project and creates Docker structure."
echo "  It does not install WordPress yet."

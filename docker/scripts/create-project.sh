#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./docker/scripts/create-project.sh \
    --type wordpress|fullstack \
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
    [--active true|false] \
    [--django-dev-port 8094] \
    [--django-prod-port 18094] \
    [--django-db-name DJANGO_DB_NAME] \
    [--django-db-user DJANGO_DB_USER] \
    [--django-bind-path ./runtime/PROJECT_NAME_django]

Examples:

  WordPress:
    ./docker/scripts/create-project.sh \
      --type wordpress \
      --name demo_wordpress \
      --description "Demo WordPress" \
      --code DEMOWP \
      --storage bind \
      --dev-port 8081 \
      --prod-port 18081 \
      --dev-url http://localhost:8081/ \
      --prod-url https://demo-wordpress.example.test/

  Fullstack:
    ./docker/scripts/create-project.sh \
      --type fullstack \
      --name demo_fullstack \
      --description "Demo fullstack project" \
      --code DEMOFS \
      --storage volume \
      --dev-port 8083 \
      --prod-port 18083 \
      --django-dev-port 8093 \
      --django-prod-port 18093 \
      --dev-url http://localhost:8083/ \
      --prod-url https://demo-fullstack.example.test/
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

write_root_compose_include_if_missing() {
  if [[ ! -f "${ROOT_COMPOSE_FILE}" ]]; then
    cat > "${ROOT_COMPOSE_FILE}" <<EOF
include:
  - path: ./sites/${NAME}/compose.yaml
    project_directory: .
EOF
    return 0
  fi

  if ! grep -Fq "./sites/${NAME}/compose.yaml" "${ROOT_COMPOSE_FILE}"; then
    cat >> "${ROOT_COMPOSE_FILE}" <<EOF
  - path: ./sites/${NAME}/compose.yaml
    project_directory: .
EOF
  fi
}

write_wordpress_compose() {
  local wp_volume_block=""

  if [[ "${STORAGE}" == "volume" ]]; then
    wp_volume_block="  ${WP_VOLUME}:"
  fi

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
${wp_volume_block}

networks:
  ${NETWORK_NAME}:
EOF
}

write_fullstack_compose() {
  local wp_volume_block=""

  if [[ "${STORAGE}" == "volume" ]]; then
    wp_volume_block="  ${WP_VOLUME}:"
  fi

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
      - "127.0.0.1:\${${WP_PORT_KEY}}:80"
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

  ${DJANGO_DB_SERVICE}:
    image: \${POSTGRES_IMAGE}
    restart: unless-stopped
    environment:
      POSTGRES_DB: \${${DJANGO_DB_NAME_KEY}}
      POSTGRES_USER: \${${DJANGO_DB_USER_KEY}}
      POSTGRES_PASSWORD: \${${DJANGO_DB_PASSWORD_KEY}}
    volumes:
      - ${DJANGO_DB_VOLUME}:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \$\$POSTGRES_USER -d \$\$POSTGRES_DB"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s
    networks:
      - ${NETWORK_NAME}
    security_opt:
      - no-new-privileges:true

  ${DJANGO_SERVICE}:
    image: \${PYTHON_IMAGE}
    restart: unless-stopped
    depends_on:
      ${DJANGO_DB_SERVICE}:
        condition: service_healthy
    env_file:
      - \${${DJANGO_ENV_FILE_KEY}}
    ports:
      - "127.0.0.1:\${${DJANGO_PORT_KEY}}:8000"
    working_dir: /django
    command: >
      sh -lc "if [ -x /django/.venv/bin/python ]; then exec /django/.venv/bin/python manage.py runserver 0.0.0.0:8000; else exec python manage.py runserver 0.0.0.0:8000; fi"
    environment:
      DJANGO_SETTINGS_MODULE: \${${DJANGO_SETTINGS_MODULE_KEY}}
      DJANGO_SECRET_KEY: \${${DJANGO_SECRET_KEY_KEY}}
      DATABASE_HOST: ${DJANGO_DB_SERVICE}
      DATABASE_PORT: 5432
      DATABASE_NAME: \${${DJANGO_DB_NAME_KEY}}
      DATABASE_USER: \${${DJANGO_DB_USER_KEY}}
      DATABASE_PASSWORD: \${${DJANGO_DB_PASSWORD_KEY}}
    volumes:
      - \${${DJANGO_CODE_MOUNT_KEY}}
    networks:
      - ${NETWORK_NAME}
    security_opt:
      - no-new-privileges:true

volumes:
  ${DB_VOLUME}:
${wp_volume_block}
  ${DJANGO_DB_VOLUME}:

networks:
  ${NETWORK_NAME}:
EOF
}

build_wordpress_project_json() {
  jq -n \
    --arg projectname "${NAME}" \
    --arg projecttype "${TYPE}" \
    --argjson active "${ACTIVE}" \
    --arg description "${DESCRIPTION}" \
    --arg datecreation "$(date +%Y-%m-%d)" \
    --arg storage_mode "${STORAGE}" \
    --arg db_service "${DB_SERVICE}" \
    --arg wp_service "${WP_SERVICE}" \
    --arg wpcli_service "${WPCLI_SERVICE}" \
    --arg db_host_runtime "${DB_HOST_RUNTIME}" \
    --arg port_key "${PORT_KEY}" \
    --arg site_url_key "${SITE_URL_KEY}" \
    --arg db_name_key "${DB_NAME_KEY}" \
    --arg db_user_key "${DB_USER_KEY}" \
    --arg db_password_key "${DB_PASSWORD_KEY}" \
    --arg db_root_password_key "${DB_ROOT_PASSWORD_KEY}" \
    --arg wp_files_mount_key "${WP_FILES_MOUNT_KEY}" \
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
        port: $port_key,
        site_url: $site_url_key,
        db_name: $db_name_key,
        db_user: $db_user_key,
        db_password: $db_password_key,
        db_root_password: $db_root_password_key,
        wp_files_mount: $wp_files_mount_key
      }
    }'
}

build_fullstack_project_json() {
  jq -n \
    --arg projectname "${NAME}" \
    --arg projecttype "${TYPE}" \
    --argjson active "${ACTIVE}" \
    --arg description "${DESCRIPTION}" \
    --arg datecreation "$(date +%Y-%m-%d)" \
    --arg storage_mode "${STORAGE}" \
    --arg db_service "${DB_SERVICE}" \
    --arg wp_service "${WP_SERVICE}" \
    --arg wpcli_service "${WPCLI_SERVICE}" \
    --arg db_host_runtime "${DB_HOST_RUNTIME}" \
    --arg django_db_service "${DJANGO_DB_SERVICE}" \
    --arg django_service "${DJANGO_SERVICE}" \
    --arg django_db_host_runtime "${DJANGO_DB_HOST_RUNTIME}" \
    --arg wp_port_key "${WP_PORT_KEY}" \
    --arg site_url_key "${SITE_URL_KEY}" \
    --arg db_name_key "${DB_NAME_KEY}" \
    --arg db_user_key "${DB_USER_KEY}" \
    --arg db_password_key "${DB_PASSWORD_KEY}" \
    --arg db_root_password_key "${DB_ROOT_PASSWORD_KEY}" \
    --arg wp_files_mount_key "${WP_FILES_MOUNT_KEY}" \
    --arg django_port_key "${DJANGO_PORT_KEY}" \
    --arg django_code_mount_key "${DJANGO_CODE_MOUNT_KEY}" \
    --arg django_env_file_key "${DJANGO_ENV_FILE_KEY}" \
    --arg django_db_name_key "${DJANGO_DB_NAME_KEY}" \
    --arg django_db_user_key "${DJANGO_DB_USER_KEY}" \
    --arg django_db_password_key "${DJANGO_DB_PASSWORD_KEY}" \
    --arg django_settings_module_key "${DJANGO_SETTINGS_MODULE_KEY}" \
    --arg django_secret_key_key "${DJANGO_SECRET_KEY_KEY}" \
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
        db_host_runtime: $db_host_runtime,
        django_db_service: $django_db_service,
        django_service: $django_service,
        django_db_host_runtime: $django_db_host_runtime
      },
      env: {
        wp_port: $wp_port_key,
        site_url: $site_url_key,
        db_name: $db_name_key,
        db_user: $db_user_key,
        db_password: $db_password_key,
        db_root_password: $db_root_password_key,
        wp_files_mount: $wp_files_mount_key,
        django_port: $django_port_key,
        django_code_mount: $django_code_mount_key,
        django_env_file: $django_env_file_key,
        django_db_name: $django_db_name_key,
        django_db_user: $django_db_user_key,
        django_db_password: $django_db_password_key,
        django_settings_module: $django_settings_module_key,
        django_secret_key: $django_secret_key_key
      }
    }'
}

TYPE=""
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

DJANGO_DEV_PORT=""
DJANGO_PROD_PORT=""
DJANGO_DB_NAME=""
DJANGO_DB_USER=""
DJANGO_BIND_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)
      TYPE="${2:-}"
      shift 2
      ;;
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
    --django-dev-port)
      DJANGO_DEV_PORT="${2:-}"
      shift 2
      ;;
    --django-prod-port)
      DJANGO_PROD_PORT="${2:-}"
      shift 2
      ;;
    --django-db-name)
      DJANGO_DB_NAME="${2:-}"
      shift 2
      ;;
    --django-db-user)
      DJANGO_DB_USER="${2:-}"
      shift 2
      ;;
    --django-bind-path)
      DJANGO_BIND_PATH="${2:-}"
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

if [[ -z "${TYPE}" || -z "${NAME}" || -z "${DESCRIPTION}" || -z "${CODE}" || -z "${STORAGE}" || -z "${DEV_PORT}" || -z "${PROD_PORT}" ]]; then
  usage
  exit 1
fi

if [[ "${TYPE}" != "wordpress" && "${TYPE}" != "fullstack" ]]; then
  echo "Invalid --type. Allowed: wordpress or fullstack."
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

if [[ "${TYPE}" == "fullstack" ]]; then
  if [[ -z "${DJANGO_DEV_PORT}" || -z "${DJANGO_PROD_PORT}" ]]; then
    echo "Fullstack projects require --django-dev-port and --django-prod-port."
    exit 1
  fi

  if [[ ! "${DJANGO_DEV_PORT}" =~ ^[0-9]+$ || ! "${DJANGO_PROD_PORT}" =~ ^[0-9]+$ ]]; then
    echo "Django ports must be numeric."
    exit 1
  fi
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
DATA_DJANGO_DIR="${DATA_SITE_DIR}/django"
RUNTIME_DIR="${DOCKER_DIR}/runtime/${NAME}"
DJANGO_RUNTIME_DIR="${DOCKER_DIR}/runtime/${NAME}_django"

ENV_DEV_EXAMPLE="${DOCKER_DIR}/env.dev.example"
ENV_PROD_EXAMPLE="${DOCKER_DIR}/env.prod.example"
ENV_DEV_LOCAL="${DOCKER_DIR}/.env.dev"
ENV_PROD_LOCAL="${DOCKER_DIR}/.env.prod"

require_cmd jq

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

if grep -Eq "^${CODE}_" "${ENV_DEV_EXAMPLE}" || grep -Eq "^${CODE}_" "${ENV_PROD_EXAMPLE}"; then
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

if [[ "${TYPE}" == "wordpress" ]]; then
  PORT_KEY="${CODE}_PORT"
else
  WP_PORT_KEY="${CODE}_WP_PORT"

  DJANGO_PORT_KEY="${CODE}_DJANGO_PORT"
  DJANGO_DB_SERVICE="djangodb_${NAME}"
  DJANGO_SERVICE="django_${NAME}"
  DJANGO_DB_HOST_RUNTIME="${DJANGO_DB_SERVICE}:5432"
  DJANGO_DB_VOLUME="djangodb_${NAME}"

  DJANGO_DB_NAME_KEY="${CODE}_DJANGO_DB_NAME"
  DJANGO_DB_USER_KEY="${CODE}_DJANGO_DB_USER"
  DJANGO_DB_PASSWORD_KEY="${CODE}_DJANGO_DB_PASSWORD"
  DJANGO_CODE_MOUNT_KEY="${CODE}_DJANGO_CODE_MOUNT"
  DJANGO_ENV_FILE_KEY="${CODE}_DJANGO_ENV_FILE"
  DJANGO_SETTINGS_MODULE_KEY="${CODE}_DJANGO_SETTINGS_MODULE"
  DJANGO_SECRET_KEY_KEY="${CODE}_DJANGO_SECRET_KEY"

  if [[ -z "${DJANGO_DB_NAME}" ]]; then
    DJANGO_DB_NAME="${NAME}_django"
  fi

  if [[ -z "${DJANGO_DB_USER}" ]]; then
    DJANGO_DB_USER="${NAME}_django_user"
  fi

  if [[ -z "${DJANGO_BIND_PATH}" ]]; then
    DJANGO_BIND_PATH="./runtime/${NAME}_django"
  fi

  DEV_DJANGO_DB_PASSWORD="change_me_dev_${NAME}_django_db_password"
  PROD_DJANGO_DB_PASSWORD="change_me_prod_${NAME}_django_db_password"
  DEV_DJANGO_ENV_FILE="${DJANGO_BIND_PATH}/.env.dev"
  PROD_DJANGO_ENV_FILE="${DJANGO_BIND_PATH}/.env.prod"
  DEV_DJANGO_SETTINGS_MODULE="config.settings"
  PROD_DJANGO_SETTINGS_MODULE="config.settings"
  DEV_DJANGO_SECRET_KEY="change_me_dev_${NAME}_django_secret"
  PROD_DJANGO_SECRET_KEY="change_me_prod_${NAME}_django_secret"
fi

if [[ "${STORAGE}" == "bind" ]]; then
  DEV_WP_MOUNT="${BIND_PATH}:/var/www/html"
  PROD_WP_MOUNT="${BIND_PATH}:/var/www/html"
else
  DEV_WP_MOUNT="${WP_VOLUME}:/var/www/html"
  PROD_WP_MOUNT="${WP_VOLUME}:/var/www/html"
fi

mkdir -p "${SITE_DIR}"
mkdir -p "${DATA_DB_DIR}" "${DATA_WP_DIR}"

if [[ "${TYPE}" == "fullstack" ]]; then
  mkdir -p "${DATA_DJANGO_DIR}"
fi

if [[ "${STORAGE}" == "bind" ]]; then
  mkdir -p "${RUNTIME_DIR}"
fi

if [[ "${TYPE}" == "fullstack" ]]; then
  mkdir -p "${DJANGO_RUNTIME_DIR}"
  DEV_DJANGO_CODE_MOUNT="${DJANGO_BIND_PATH}:/django"
  PROD_DJANGO_CODE_MOUNT="${DJANGO_BIND_PATH}:/django"
fi

if [[ "${TYPE}" == "wordpress" ]]; then
  write_wordpress_compose
else
  write_fullstack_compose
fi

write_root_compose_include_if_missing

if [[ "${TYPE}" == "wordpress" ]]; then
  NEW_PROJECT_JSON="$(build_wordpress_project_json)"
else
  NEW_PROJECT_JSON="$(build_fullstack_project_json)"
fi

TMP_WORLD="$(mktemp)"
jq --argjson new_project "${NEW_PROJECT_JSON}" '
  if has("projects") then
    .projects += [$new_project]
  else
    . + {projects: [$new_project]}
  end
' "${WORLD_FILE}" > "${TMP_WORLD}"
mv "${TMP_WORLD}" "${WORLD_FILE}"

if [[ "${TYPE}" == "wordpress" ]]; then
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

  KEY_CHECK="${PORT_KEY}"
else
  DEV_ENV_BLOCK="$(cat <<EOF
${WP_PORT_KEY}=${DEV_PORT}
${SITE_URL_KEY}=${DEV_URL}
${DB_NAME_KEY}=${DB_NAME}
${DB_USER_KEY}=${DB_USER}
${DB_PASSWORD_KEY}=${DEV_DB_PASSWORD}
${DB_ROOT_PASSWORD_KEY}=${DEV_DB_ROOT_PASSWORD}
${WP_FILES_MOUNT_KEY}=${DEV_WP_MOUNT}
${DJANGO_PORT_KEY}=${DJANGO_DEV_PORT}
${DJANGO_CODE_MOUNT_KEY}=${DEV_DJANGO_CODE_MOUNT}
${DJANGO_ENV_FILE_KEY}=${DEV_DJANGO_ENV_FILE}
${DJANGO_DB_NAME_KEY}=${DJANGO_DB_NAME}
${DJANGO_DB_USER_KEY}=${DJANGO_DB_USER}
${DJANGO_DB_PASSWORD_KEY}=${DEV_DJANGO_DB_PASSWORD}
${DJANGO_SETTINGS_MODULE_KEY}=${DEV_DJANGO_SETTINGS_MODULE}
${DJANGO_SECRET_KEY_KEY}=${DEV_DJANGO_SECRET_KEY}
EOF
)"

  PROD_ENV_BLOCK="$(cat <<EOF
${WP_PORT_KEY}=${PROD_PORT}
${SITE_URL_KEY}=${PROD_URL}
${DB_NAME_KEY}=${DB_NAME}
${DB_USER_KEY}=${DB_USER}
${DB_PASSWORD_KEY}=${PROD_DB_PASSWORD}
${DB_ROOT_PASSWORD_KEY}=${PROD_DB_ROOT_PASSWORD}
${WP_FILES_MOUNT_KEY}=${PROD_WP_MOUNT}
${DJANGO_PORT_KEY}=${DJANGO_PROD_PORT}
${DJANGO_CODE_MOUNT_KEY}=${PROD_DJANGO_CODE_MOUNT}
${DJANGO_ENV_FILE_KEY}=${PROD_DJANGO_ENV_FILE}
${DJANGO_DB_NAME_KEY}=${DJANGO_DB_NAME}
${DJANGO_DB_USER_KEY}=${DJANGO_DB_USER}
${DJANGO_DB_PASSWORD_KEY}=${PROD_DJANGO_DB_PASSWORD}
${DJANGO_SETTINGS_MODULE_KEY}=${PROD_DJANGO_SETTINGS_MODULE}
${DJANGO_SECRET_KEY_KEY}=${PROD_DJANGO_SECRET_KEY}
EOF
)"

  KEY_CHECK="${WP_PORT_KEY}"
fi

append_env_block_if_missing "${ENV_DEV_EXAMPLE}" "${KEY_CHECK}" "${DEV_ENV_BLOCK}"
append_env_block_if_missing "${ENV_PROD_EXAMPLE}" "${KEY_CHECK}" "${PROD_ENV_BLOCK}"
append_env_block_if_missing "${ENV_DEV_LOCAL}" "${KEY_CHECK}" "${DEV_ENV_BLOCK}"
append_env_block_if_missing "${ENV_PROD_LOCAL}" "${KEY_CHECK}" "${PROD_ENV_BLOCK}"

echo "Created project: ${NAME}"
echo "Project type: ${TYPE}"
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
echo "  It does not bootstrap WordPress or Django."
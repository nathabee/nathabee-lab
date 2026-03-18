#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./docker/scripts/bootstrap-wordpress.sh \
    <dev|prod> <site> \
    --title "Site Title" \
    --admin-user ADMIN_LOGIN \
    --admin-email ADMIN_EMAIL \
    [--admin-password PASSWORD] \
    [--locale en_US] \
    [--table-prefix wp_]

Examples:
  ./docker/scripts/bootstrap-wordpress.sh \
    dev beeschool \
    --title "Bee School" \
    --admin-user nathabee \
    --admin-email you@example.com

  ./docker/scripts/bootstrap-wordpress.sh \
    prod beeschool \
    --title "Bee School" \
    --admin-user admin \
    --admin-email admin@example.com \
    --admin-password 'change-me-now'
EOF
}

require_cmd() {
  local cmd="${1:-}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}"
    exit 1
  fi
}

generate_password() {
  python3 - <<'PY'
import secrets
import string

alphabet = string.ascii_letters + string.digits + "-_!@#%^&*"
print("".join(secrets.choice(alphabet) for _ in range(24)))
PY
}

MODE="${1:-}"
SITE="${2:-}"

if [[ "${MODE}" != "dev" && "${MODE}" != "prod" ]]; then
  usage
  exit 1
fi

if [[ -z "${SITE}" ]]; then
  usage
  exit 1
fi

shift 2 || true

TITLE=""
ADMIN_USER=""
ADMIN_EMAIL=""
ADMIN_PASSWORD=""
LOCALE="en_US"
TABLE_PREFIX="wp_"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --admin-user)
      ADMIN_USER="${2:-}"
      shift 2
      ;;
    --admin-email)
      ADMIN_EMAIL="${2:-}"
      shift 2
      ;;
    --admin-password)
      ADMIN_PASSWORD="${2:-}"
      shift 2
      ;;
    --locale)
      LOCALE="${2:-}"
      shift 2
      ;;
    --table-prefix)
      TABLE_PREFIX="${2:-}"
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

if [[ -z "${TITLE}" || -z "${ADMIN_USER}" || -z "${ADMIN_EMAIL}" ]]; then
  usage
  exit 1
fi

if [[ -z "${ADMIN_PASSWORD}" ]]; then
  ADMIN_PASSWORD="$(generate_password)"
  GENERATED_PASSWORD="true"
else
  GENERATED_PASSWORD="false"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${STACK_DIR}/.." && pwd)"
ENV_FILE="${STACK_DIR}/.env.${MODE}"
WORLD_FILE="${REPO_ROOT}/data/world-list.json"

require_cmd jq
require_cmd docker
require_cmd python3

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
    (.projects // .)[]
    | select((.projecttype // .type // "") == "wordpress")
    | select((.projectname // .name) == $site)
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

PROJECT_NAME="$(jq -r '.projectname // .name // empty' <<< "${PROJECT_JSON}")"
PROJECT_TYPE="$(jq -r '.projecttype // .type // empty' <<< "${PROJECT_JSON}")"
DB_SERVICE="$(jq -r '.compose.db_service // empty' <<< "${PROJECT_JSON}")"
WP_SERVICE="$(jq -r '.compose.wp_service // empty' <<< "${PROJECT_JSON}")"
WPCLI_SERVICE="$(jq -r '.compose.wpcli_service // empty' <<< "${PROJECT_JSON}")"

DB_NAME_KEY="$(jq -r '.env.db_name // empty' <<< "${PROJECT_JSON}")"
DB_USER_KEY="$(jq -r '.env.db_user // empty' <<< "${PROJECT_JSON}")"
DB_PASSWORD_KEY="$(jq -r '.env.db_password // empty' <<< "${PROJECT_JSON}")"
SITE_URL_KEY="$(jq -r '.env.site_url // empty' <<< "${PROJECT_JSON}")"

if [[ "${PROJECT_TYPE}" != "wordpress" ]]; then
  echo "Project ${SITE} is not a wordpress project."
  exit 1
fi

if [[ -z "${DB_SERVICE}" || -z "${WP_SERVICE}" || -z "${WPCLI_SERVICE}" ]]; then
  echo "Project ${SITE} is missing compose service mapping in ${WORLD_FILE}"
  exit 1
fi

DB_NAME="$(resolve_env_value "${DB_NAME_KEY}")"
DB_USER="$(resolve_env_value "${DB_USER_KEY}")"
DB_PASSWORD="$(resolve_env_value "${DB_PASSWORD_KEY}")"
SITE_URL="$(resolve_env_value "${SITE_URL_KEY}")"

COMPOSE=(docker compose --env-file "${ENV_FILE}" -f "${STACK_DIR}/compose.yaml")
COMPOSE_CLI=(docker compose --profile cli --env-file "${ENV_FILE}" -f "${STACK_DIR}/compose.yaml")

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

wait_for_wp_files() {
  until "${COMPOSE[@]}" exec -T "${WP_SERVICE}" sh -lc '
    [ -f /var/www/html/index.php ] &&
    [ -f /var/www/html/wp-config.php ] &&
    [ -f /var/www/html/wp-settings.php ]
  ' >/dev/null 2>&1; do
    sleep 2
  done
}

wait_for_db_login() {
  until "${COMPOSE[@]}" exec -T "${DB_SERVICE}" mariadb \
    -h127.0.0.1 \
    -u"${DB_USER}" \
    -p"${DB_PASSWORD}" \
    -e "SELECT 1;" "${DB_NAME}" >/dev/null 2>&1; do
    sleep 2
  done
}

run_wpcli() {
  "${COMPOSE_CLI[@]}" run --rm -T --no-deps "${WPCLI_SERVICE}" wp --allow-root "$@"
}

run_wpcli_sh() {
  "${COMPOSE_CLI[@]}" run --rm -T --no-deps "${WPCLI_SERVICE}" sh -lc "$1"
}

run_wp_sh() {
  "${COMPOSE[@]}" exec -T "${WP_SERVICE}" sh -lc "$1"
}

normalize_runtime_permissions() {
  run_wp_sh '
    set -eu
    chown -R www-data:www-data /var/www/html
    find /var/www/html -type d -exec chmod 755 {} +
    find /var/www/html -type f -exec chmod 644 {} +
    mkdir -p /var/www/html/wp-content/uploads
    chown -R www-data:www-data /var/www/html/wp-content
  '
}

replace_table_prefix_in_wp_config() {
  if [[ ! "${TABLE_PREFIX}" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "Invalid table prefix: ${TABLE_PREFIX}"
    exit 1
  fi

  run_wp_sh "set -eu
file='/var/www/html/wp-config.php'

if grep -q '^[[:space:]]*\\\$table_prefix[[:space:]]*=' \"\$file\"; then
  sed -i \"s#^[[:space:]]*\\\$table_prefix[[:space:]]*=.*;#\\\$table_prefix = '${TABLE_PREFIX}';#\" \"\$file\"
else
  printf '\n\\\$table_prefix = '\\''${TABLE_PREFIX}'\\'';\n' >> \"\$file\"
fi
"
}

echo "Bootstrapping ${PROJECT_NAME}"
echo "Mode: ${MODE}"
echo "URL: ${SITE_URL}"
echo "Title: ${TITLE}"
echo "Admin user: ${ADMIN_USER}"
echo "Admin email: ${ADMIN_EMAIL}"
echo "Locale: ${LOCALE}"
echo "Table prefix: ${TABLE_PREFIX}"

echo "Starting database and WordPress services..."
"${COMPOSE[@]}" up -d "${DB_SERVICE}" "${WP_SERVICE}"

echo "Waiting for database health..."
wait_for_db_healthy
echo "Database container is healthy."

echo "Waiting for SQL login as ${DB_USER}..."
wait_for_db_login
echo "Database login is ready."

echo "Waiting for WordPress container..."
wait_for_wp_running
echo "WordPress container is running."

echo "Waiting for WordPress core files and wp-config.php..."
wait_for_wp_files
echo "WordPress runtime files are ready."

echo "Normalizing runtime ownership and permissions..."
normalize_runtime_permissions

echo "Checking WordPress installation status..."
if run_wpcli core is-installed >/dev/null 2>&1; then
  echo "WordPress is already installed for ${PROJECT_NAME}."
  echo "URL: ${SITE_URL}"
  exit 0
fi

echo "Checking runtime directory contents..."
run_wp_sh '[ -f /var/www/html/wp-config.php ] || { echo "Missing /var/www/html/wp-config.php"; exit 1; }'

echo "Applying table prefix in wp-config.php..."
replace_table_prefix_in_wp_config

echo "Running wp core install..."
run_wpcli core install \
  --url="${SITE_URL}" \
  --title="${TITLE}" \
  --admin_user="${ADMIN_USER}" \
  --admin_password="${ADMIN_PASSWORD}" \
  --admin_email="${ADMIN_EMAIL}" \
  --skip-email

echo "Writing standard WordPress .htaccess ..."
run_wp_sh "cat > /var/www/html/.htaccess <<'EOF'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
EOF
chown www-data:www-data /var/www/html/.htaccess
chmod 644 /var/www/html/.htaccess
"

echo "Initializing permalink structure and rewrite rules..."
run_wpcli rewrite structure '/%postname%/' --hard


echo "Setting siteurl and home explicitly..."
run_wpcli option update siteurl "${SITE_URL}"
run_wpcli option update home "${SITE_URL}"

echo "Bootstrap complete: ${PROJECT_NAME}"
echo "URL: ${SITE_URL}"
echo "Admin user: ${ADMIN_USER}"

if [[ "${GENERATED_PASSWORD}" == "true" ]]; then
  echo "Generated admin password: ${ADMIN_PASSWORD}"
else
  echo "Admin password: [user-supplied]"
fi

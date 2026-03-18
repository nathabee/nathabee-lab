#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <dev|prod> <site> [permalink_structure]"
  echo "Example: $0 dev beeschool '/%postname%/'"
}

MODE="${1:-}"
SITE="${2:-}"
PERMALINK_STRUCTURE="${3:-/%postname%/}"

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

get_project_json() {
  jq -ec --arg site "$1" '
    (.projects // .)[]
    | select((.projecttype // .type // "") == "wordpress")
    | select((.projectname // .name) == $site)
  ' "${WORLD_FILE}"
}

PROJECT_JSON="$(get_project_json "${SITE}")" || {
  echo "Project not found in ${WORLD_FILE}: ${SITE}"
  exit 1
}

WP_SERVICE="$(jq -r '.compose.wp_service // empty' <<< "${PROJECT_JSON}")"
WPCLI_SERVICE="$(jq -r '.compose.wpcli_service // empty' <<< "${PROJECT_JSON}")"

if [[ -z "${WP_SERVICE}" || -z "${WPCLI_SERVICE}" ]]; then
  echo "Project ${SITE} is missing compose service mapping in ${WORLD_FILE}"
  exit 1
fi

COMPOSE=(docker compose --env-file "${ENV_FILE}" -f "${STACK_DIR}/compose.yaml")
COMPOSE_CLI=(docker compose --profile cli --env-file "${ENV_FILE}" -f "${STACK_DIR}/compose.yaml")

echo "Starting services for ${SITE}..."
"${COMPOSE[@]}" up -d "${WP_SERVICE}"

echo "Writing standard WordPress .htaccess ..."
"${COMPOSE[@]}" exec -T "${WP_SERVICE}" sh -lc "cat > /var/www/html/.htaccess <<'EOF'
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

echo "Setting permalink structure to ${PERMALINK_STRUCTURE} ..."
"${COMPOSE_CLI[@]}" run --rm -T --no-deps "${WPCLI_SERVICE}" \
  wp --allow-root rewrite structure "${PERMALINK_STRUCTURE}" --hard

echo "Current .htaccess:"
"${COMPOSE[@]}" exec -T "${WP_SERVICE}" sh -lc 'cat /var/www/html/.htaccess'

echo
echo "Test this now:"
echo "  curl -i http://localhost:<port>/wp-json/"
echo
echo "Done for ${SITE}."

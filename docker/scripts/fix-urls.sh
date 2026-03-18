#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
SITE="${2:-}"

usage() {
  echo "Usage: $0 <dev|prod> <site> [old_url ...]"
}

if [[ "${MODE}" != "dev" && "${MODE}" != "prod" ]]; then
  usage
  exit 1
fi

if [[ -z "${SITE}" ]]; then
  usage
  exit 1
fi

shift 2 || true

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
DB_SERVICE="$(jq -r '.compose.db_service // empty' <<< "${PROJECT_JSON}")"
WP_SERVICE="$(jq -r '.compose.wp_service // empty' <<< "${PROJECT_JSON}")"
CLI_SERVICE="$(jq -r '.compose.wpcli_service // empty' <<< "${PROJECT_JSON}")"
SITE_URL_KEY="$(jq -r '.env.site_url // empty' <<< "${PROJECT_JSON}")"
NEW_URL="$(resolve_env_value "${SITE_URL_KEY}")"

if [[ -z "${DB_SERVICE}" || -z "${WP_SERVICE}" || -z "${CLI_SERVICE}" ]]; then
  echo "Project ${SITE} is missing compose service mapping in ${WORLD_FILE}"
  exit 1
fi

CONFIG_JSON="${REPO_ROOT}/data/${PROJECT_NAME}/updateArchive.json"

if [[ ! -f "${CONFIG_JSON}" ]]; then
  echo "Missing archive metadata: ${CONFIG_JSON}"
  exit 1
fi

COMPOSE=(docker compose --env-file "${ENV_FILE}" -f "${STACK_DIR}/compose.yaml")
COMPOSE_CLI=(docker compose --profile cli --env-file "${ENV_FILE}" -f "${STACK_DIR}/compose.yaml")

if [[ $# -eq 0 ]]; then
  ORIGINAL_SITEURL="$(jq -r '.original_siteurl // empty' "${CONFIG_JSON}")"
  ORIGINAL_HOME="$(jq -r '.original_home // empty' "${CONFIG_JSON}")"

  OLD_URLS=()

  if [[ -n "${ORIGINAL_SITEURL}" ]]; then
    OLD_URLS+=("${ORIGINAL_SITEURL}")
  fi

  if [[ -n "${ORIGINAL_HOME}" && "${ORIGINAL_HOME}" != "${ORIGINAL_SITEURL}" ]]; then
    OLD_URLS+=("${ORIGINAL_HOME}")
  fi

  if [[ ${#OLD_URLS[@]} -eq 0 ]]; then
    echo "No old URL provided and no original_siteurl/original_home found in ${CONFIG_JSON}"
    exit 1
  fi
else
  OLD_URLS=("$@")
fi

"${COMPOSE[@]}" up -d "${DB_SERVICE}" "${WP_SERVICE}"

for OLD_URL in "${OLD_URLS[@]}"; do
  echo "Replacing:"
  echo "  ${OLD_URL}"
  echo "  -> ${NEW_URL}"

  "${COMPOSE_CLI[@]}" run --rm -T --no-deps "${CLI_SERVICE}" \
    wp --allow-root search-replace "${OLD_URL}" "${NEW_URL}" \
    --skip-columns=guid \
    --all-tables-with-prefix \
    --precise \
    --report-changed-only
done

echo "Current values:"
"${COMPOSE_CLI[@]}" run --rm -T --no-deps "${CLI_SERVICE}" wp --allow-root option get siteurl
"${COMPOSE_CLI[@]}" run --rm -T --no-deps "${CLI_SERVICE}" wp --allow-root option get home

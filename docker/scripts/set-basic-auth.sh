#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
SITE="${2:-}"
BASIC_USER="${3:-}"

usage() {
  echo "Usage: $0 <dev|prod> <site> [username]"
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
require_cmd htpasswd
require_cmd mktemp

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
    | select((.projectname // .name) == $site)
  ' "${WORLD_FILE}"
}

PROJECT_JSON="$(get_project_json "${SITE}")" || {
  echo "Project not found in ${WORLD_FILE}: ${SITE}"
  exit 1
}

WP_SERVICE="$(jq -r '.compose.wp_service // empty' <<< "${PROJECT_JSON}")"

if [[ -z "${WP_SERVICE}" ]]; then
  echo "Project ${SITE} is missing compose wp_service in ${WORLD_FILE}"
  exit 1
fi

if [[ -z "${BASIC_USER}" ]]; then
  read -r -p "Basic Auth username for ${SITE}: " BASIC_USER
fi

if [[ -z "${BASIC_USER}" ]]; then
  echo "Username must not be empty."
  exit 1
fi

read -r -s -p "Basic Auth password for ${SITE}: " PW1
echo
read -r -s -p "Confirm Basic Auth password for ${SITE}: " PW2
echo

if [[ -z "${PW1}" ]]; then
  echo "Password must not be empty."
  exit 1
fi

if [[ "${PW1}" != "${PW2}" ]]; then
  echo "Passwords do not match."
  exit 1
fi

COMPOSE=(docker compose --env-file "${ENV_FILE}" -f "${STACK_DIR}/compose.yaml")

TMP_FILE="$(mktemp)"
cleanup() {
  rm -f "${TMP_FILE}"
}
trap cleanup EXIT

umask 077
printf '%s\n' "${PW1}" | htpasswd -niB "${BASIC_USER}" > "${TMP_FILE}"

"${COMPOSE[@]}" up -d "${WP_SERVICE}" >/dev/null

cat "${TMP_FILE}" | "${COMPOSE[@]}" exec -T "${WP_SERVICE}" sh -lc '
  set -eu
  cat > /var/www/html/.htpasswd
  chown www-data:www-data /var/www/html/.htpasswd
  chmod 640 /var/www/html/.htpasswd
'

echo "Updated /var/www/html/.htpasswd for ${SITE}"

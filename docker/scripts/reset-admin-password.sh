#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
SITE="${2:-}"
USER_LOGIN="${3:-}"

usage() {
  echo "Usage: $0 <dev|prod> <site> <user_login>"
}

if [[ "${MODE}" != "dev" && "${MODE}" != "prod" ]]; then
  usage
  exit 1
fi

if [[ -z "${SITE}" || -z "${USER_LOGIN}" ]]; then
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

CLI_SERVICE="$(jq -r '.compose.wpcli_service // empty' <<< "${PROJECT_JSON}")"

if [[ -z "${CLI_SERVICE}" ]]; then
  echo "Project ${SITE} is missing .compose.wpcli_service in ${WORLD_FILE}"
  exit 1
fi

COMPOSE_CLI=(docker compose --profile cli --env-file "${ENV_FILE}" -f "${STACK_DIR}/compose.yaml")

"${COMPOSE_CLI[@]}" run --rm -T --no-deps "${CLI_SERVICE}" \
  wp --allow-root user reset-password "${USER_LOGIN}" --skip-email --show-password

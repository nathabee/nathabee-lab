#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./docker/scripts/down.sh <dev|prod> [project_name]

Examples:
  ./docker/scripts/down.sh dev
  ./docker/scripts/down.sh prod
  ./docker/scripts/down.sh dev demo_fullstack
  ./docker/scripts/down.sh prod demo_wordpress
EOF
}

MODE="${1:-}"
PROJECT_NAME="${2:-}"

if [[ "${MODE}" != "dev" && "${MODE}" != "prod" ]]; then
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${STACK_DIR}/.env.${MODE}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}"
  exit 1
fi

if [[ -z "${PROJECT_NAME}" ]]; then
  echo "Stopping full stack for mode: ${MODE}"
  docker compose \
    --env-file "${ENV_FILE}" \
    -f "${STACK_DIR}/compose.yaml" \
    down --remove-orphans
  exit 0
fi

PROJECT_COMPOSE_FILE="${STACK_DIR}/sites/${PROJECT_NAME}/compose.yaml"

if [[ ! -f "${PROJECT_COMPOSE_FILE}" ]]; then
  echo "Missing project compose file: ${PROJECT_COMPOSE_FILE}"
  exit 1
fi

echo "Stopping only project: ${PROJECT_NAME} (${MODE})"
docker compose \
  --env-file "${ENV_FILE}" \
  --project-directory "${STACK_DIR}" \
  -f "${PROJECT_COMPOSE_FILE}" \
  down
#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-dev}"

if [[ "${MODE}" != "dev" && "${MODE}" != "prod" ]]; then
  echo "Usage: $0 <dev|prod> [SERVICE ...]"
  exit 1
fi

shift || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${STACK_DIR}/.env.${MODE}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}"
  exit 1
fi

if [[ $# -eq 0 ]]; then
  docker compose --env-file "${ENV_FILE}" -f "${STACK_DIR}/compose.yaml" up -d
else
  docker compose --env-file "${ENV_FILE}" -f "${STACK_DIR}/compose.yaml" up -d "$@"
fi

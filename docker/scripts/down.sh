#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-dev}"

if [[ "${MODE}" != "dev" && "${MODE}" != "prod" ]]; then
  echo "Usage: $0 <dev|prod>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${STACK_DIR}/.env.${MODE}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}"
  exit 1
fi

docker compose --env-file "${ENV_FILE}" -f "${STACK_DIR}/compose.yaml" down --remove-orphans

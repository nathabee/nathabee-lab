#!/bin/bash

set -euo pipefail

ENV_NAME="${1:-}"

ALLOWED_ENVS=("nathabee_wordpress" "orthopedagogie" "orthopedagogiedutregor")

if [[ -z "${ENV_NAME}" ]]; then
  echo "Usage: $0 <environment_name>"
  echo "Allowed values: ${ALLOWED_ENVS[*]}"
  exit 1
fi

if [[ ! " ${ALLOWED_ENVS[*]} " =~ " ${ENV_NAME} " ]]; then
  echo "Error: Unknown environment '${ENV_NAME}'"
  echo "Allowed values: ${ALLOWED_ENVS[*]}"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${PROJECT_ROOT}/data"
ARCHIVE_PATH="${DATA_DIR}/${ENV_NAME}"

if [[ -d "$ARCHIVE_PATH" ]]; then
  echo "Deleting archive directory: $ARCHIVE_PATH"
  rm -rf "$ARCHIVE_PATH"
  echo "Archive deleted: $ENV_NAME"
else
  echo "Archive directory does not exist: $ARCHIVE_PATH"
fi

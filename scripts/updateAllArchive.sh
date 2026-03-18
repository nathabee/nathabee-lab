#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOWED_ENVS=("nathabee_wordpress" "orthopedagogie" "orthopedagogiedutregor")

if [[ $# -eq 0 ]]; then
  ENVS=("${ALLOWED_ENVS[@]}")
else
  ENVS=("$@")
fi

for ENV_NAME in "${ENVS[@]}"; do
  if [[ ! " ${ALLOWED_ENVS[*]} " =~ " ${ENV_NAME} " ]]; then
    echo "Error: Unknown environment '${ENV_NAME}'"
    echo "Allowed values: ${ALLOWED_ENVS[*]}"
    exit 1
  fi
done

for ENV_NAME in "${ENVS[@]}"; do
  echo "----------------------------------------"
  echo "Updating archive: ${ENV_NAME}"
  "${SCRIPT_DIR}/updateArchive.sh" "${ENV_NAME}"
done

echo "----------------------------------------"
echo "All requested archives updated successfully"

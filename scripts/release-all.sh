#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_PROJECT_SCRIPT="${SCRIPT_DIR}/release-project.sh"

ALLOWED_ENVS=("nathabee_wordpress" "orthopedagogie" "orthopedagogiedutregor")

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [--local-only] [environment ...]

If no environment is given, all are released.

Allowed environments:
  ${ALLOWED_ENVS[*]}

Examples:
  $(basename "$0")
  $(basename "$0") orthopedagogie
  $(basename "$0") --local-only nathabee_wordpress orthopedagogiedutregor
EOF
}

is_allowed_env() {
  local candidate="$1"
  local allowed

  for allowed in "${ALLOWED_ENVS[@]}"; do
    if [[ "${allowed}" == "${candidate}" ]]; then
      return 0
    fi
  done

  return 1
}

LOCAL_ONLY=0
REQUESTED_ENVS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local-only)
      LOCAL_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      REQUESTED_ENVS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#REQUESTED_ENVS[@]} -eq 0 ]]; then
  ENVS=("${ALLOWED_ENVS[@]}")
else
  ENVS=("${REQUESTED_ENVS[@]}")
fi

for ENV_NAME in "${ENVS[@]}"; do
  if ! is_allowed_env "${ENV_NAME}"; then
    echo "Error: unknown environment '${ENV_NAME}'" >&2
    echo "Allowed values: ${ALLOWED_ENVS[*]}" >&2
    exit 1
  fi
done

if [[ ! -x "${RELEASE_PROJECT_SCRIPT}" ]]; then
  echo "Error: missing or non-executable script: ${RELEASE_PROJECT_SCRIPT}" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"

for ENV_NAME in "${ENVS[@]}"; do
  echo
  echo "============================================================"
  echo "Releasing ${ENV_NAME} with batch stamp ${STAMP}"
  echo "============================================================"

  CMD=("${RELEASE_PROJECT_SCRIPT}" "--stamp" "${STAMP}")

  if [[ "${LOCAL_ONLY}" -eq 1 ]]; then
    CMD+=("--local-only")
  fi

  CMD+=("${ENV_NAME}")

  "${CMD[@]}"
done

echo
echo "All requested releases completed with stamp ${STAMP}."

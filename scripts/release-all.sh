#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${PROJECT_ROOT}/data"
WORLD_FILE="${DATA_DIR}/world-list.json"
RELEASE_PROJECT_SCRIPT="${SCRIPT_DIR}/release-project.sh"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [--local-only] [project ...]

If no project is given, all projects from world-list.json that have a data directory are released.

Examples:
  $(basename "$0")
  $(basename "$0") demo_wordpress
  $(basename "$0") --local-only demo_fullstack demo_wordpress
EOF
}

require_cmd() {
  local cmd="$1"

  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Error: required command not found: ${cmd}" >&2
    exit 1
  fi
}

LOCAL_ONLY=0
REQUESTED_PROJECTS=()

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
      REQUESTED_PROJECTS+=("$1")
      shift
      ;;
  esac
done

require_cmd jq

if [[ ! -f "${WORLD_FILE}" ]]; then
  echo "Error: missing world list: ${WORLD_FILE}" >&2
  exit 1
fi

if [[ ! -x "${RELEASE_PROJECT_SCRIPT}" ]]; then
  echo "Error: missing or non-executable script: ${RELEASE_PROJECT_SCRIPT}" >&2
  exit 1
fi

if [[ ${#REQUESTED_PROJECTS[@]} -eq 0 ]]; then
  mapfile -t PROJECTS < <(
    jq -r '
      (.projects // .)[]
      | (.projectname // .name // empty)
    ' "${WORLD_FILE}" | while read -r name; do
      [[ -n "${name}" && -d "${DATA_DIR}/${name}" ]] && printf '%s\n' "${name}"
    done
  )
else
  PROJECTS=("${REQUESTED_PROJECTS[@]}")
fi

if [[ ${#PROJECTS[@]} -eq 0 ]]; then
  echo "Error: no releasable projects found." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"

for PROJECT_NAME in "${PROJECTS[@]}"; do
  echo
  echo "============================================================"
  echo "Releasing ${PROJECT_NAME} with batch stamp ${STAMP}"
  echo "============================================================"

  CMD=("${RELEASE_PROJECT_SCRIPT}" "--stamp" "${STAMP}")

  if [[ "${LOCAL_ONLY}" -eq 1 ]]; then
    CMD+=("--local-only")
  fi

  CMD+=("${PROJECT_NAME}")

  "${CMD[@]}"
done

echo
echo "All requested releases completed with stamp ${STAMP}."
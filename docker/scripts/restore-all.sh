#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"

if [[ "${MODE}" != "dev" && "${MODE}" != "prod" ]]; then
  echo "Usage: $0 <dev|prod>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${STACK_DIR}/.." && pwd)"
WORLD_FILE="${REPO_ROOT}/data/world-list.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "Missing required command: jq"
  exit 1
fi

if [[ ! -f "${WORLD_FILE}" ]]; then
  echo "Missing world list: ${WORLD_FILE}"
  exit 1
fi

mapfile -t PROJECT_LINES < <(
  jq -r '
    (.projects // .)[]
    | select((.active // false) == true)
    | select((.projecttype // .type // "") == "wordpress" or (.projecttype // .type // "") == "fullstack")
    | "\((.projectname // .name))|\((.projecttype // .type))"
  ' "${WORLD_FILE}"
)

if [[ "${#PROJECT_LINES[@]}" -eq 0 ]]; then
  echo "No active wordpress/fullstack projects found in ${WORLD_FILE}"
  exit 1
fi

for LINE in "${PROJECT_LINES[@]}"; do
  IFS='|' read -r PROJECT_NAME PROJECT_TYPE <<< "${LINE}"

  echo
  echo "============================================================"
  echo "Restoring ${PROJECT_NAME} (${PROJECT_TYPE})"
  echo "============================================================"

  if [[ "${PROJECT_TYPE}" == "fullstack" ]]; then
    "${SCRIPT_DIR}/restore-fullstack.sh" "${MODE}" "${PROJECT_NAME}"
  else
    "${SCRIPT_DIR}/restore-site.sh" "${MODE}" "${PROJECT_NAME}"
  fi
done

echo
echo "All restores completed."
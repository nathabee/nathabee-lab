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

mapfile -t SITES < <(
  jq -r '
    (.projects // .)[]
    | select((.active // false) == true)
    | select((.projecttype // .type // "") == "wordpress")
    | (.projectname // .name // empty)
  ' "${WORLD_FILE}"
)

if [[ "${#SITES[@]}" -eq 0 ]]; then
  echo "No active wordpress projects found in ${WORLD_FILE}"
  exit 1
fi

for SITE in "${SITES[@]}"; do
  echo
  echo "============================================================"
  echo "Exporting ${SITE}"
  echo "============================================================"
  "${SCRIPT_DIR}/export-site.sh" "${MODE}" "${SITE}"
done

echo
echo "All WordPress site exports completed."

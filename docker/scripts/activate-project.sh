#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./docker/scripts/activate-project.sh <project_name>

What it does:
  - sets active=true in data/world-list.json
  - uncomments the matching include block in docker/compose.yaml

What it does NOT do:
  - it does not restore runtime data
  - it does not recreate deleted Docker volumes
  - it does not bootstrap WordPress or Django
EOF
}

require_cmd() {
  local cmd="${1:-}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}"
    exit 1
  fi
}

PROJECT_NAME="${1:-}"

if [[ -z "${PROJECT_NAME}" ]]; then
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${DOCKER_DIR}/.." && pwd)"

WORLD_FILE="${REPO_ROOT}/data/world-list.json"
ROOT_COMPOSE_FILE="${DOCKER_DIR}/compose.yaml"
PROJECT_COMPOSE_FILE="${DOCKER_DIR}/sites/${PROJECT_NAME}/compose.yaml"

require_cmd jq
require_cmd python3

if [[ ! -f "${WORLD_FILE}" ]]; then
  echo "Missing world list: ${WORLD_FILE}"
  exit 1
fi

if [[ ! -f "${ROOT_COMPOSE_FILE}" ]]; then
  echo "Missing root compose file: ${ROOT_COMPOSE_FILE}"
  exit 1
fi

if [[ ! -f "${PROJECT_COMPOSE_FILE}" ]]; then
  echo "Missing project compose file: ${PROJECT_COMPOSE_FILE}"
  exit 1
fi

if ! jq -e --arg project "${PROJECT_NAME}" '
  (.projects // .)[]
  | select((.projectname // .name) == $project)
' "${WORLD_FILE}" >/dev/null 2>&1; then
  echo "Project not found in ${WORLD_FILE}: ${PROJECT_NAME}"
  exit 1
fi

mark_project_active() {
  local tmp_file
  tmp_file="$(mktemp)"

  jq --arg project "${PROJECT_NAME}" '
    if has("projects") then
      .projects |= map(
        if ((.projectname // .name) == $project) then
          .active = true
        else
          .
        end
      )
    else
      map(
        if ((.projectname // .name) == $project) then
          .active = true
        else
          .
        end
      )
    end
  ' "${WORLD_FILE}" > "${tmp_file}"

  mv "${tmp_file}" "${WORLD_FILE}"
  echo "Marked active in ${WORLD_FILE}"
}

uncomment_root_include() {
  python3 - "${ROOT_COMPOSE_FILE}" "${PROJECT_NAME}" <<'PY'
import sys
from pathlib import Path

compose_path = Path(sys.argv[1])
project_name = sys.argv[2]
needle = f"./sites/{project_name}/compose.yaml"

lines = compose_path.read_text(encoding="utf-8").splitlines(keepends=True)

out = []
i = 0
changed = False

while i < len(lines):
    line = lines[i]

    stripped = line.lstrip()
    indent = len(line) - len(stripped)

    if needle in line and stripped.startswith("#"):
        uncommented = stripped[1:]
        if uncommented.startswith(" "):
            uncommented = uncommented[1:]
        out.append(" " * indent + uncommented)
        changed = True
        i += 1

        while i < len(lines):
            nxt = lines[i]
            nxt_stripped = nxt.lstrip()
            nxt_indent = len(nxt) - len(nxt_stripped)

            if nxt.strip() == "":
                out.append(nxt)
                i += 1
                break

            if nxt_indent > indent and nxt_stripped.startswith("#"):
                uncommented_child = nxt_stripped[1:]
                if uncommented_child.startswith(" "):
                    uncommented_child = uncommented_child[1:]
                out.append(" " * nxt_indent + uncommented_child)
                changed = True
                i += 1
            else:
                break

        continue

    out.append(line)
    i += 1

if changed:
    compose_path.write_text("".join(out), encoding="utf-8")
    print(f"Uncommented include block in {compose_path}")
else:
    print(f"No commented include block found for {project_name} in {compose_path}")
PY
}

mark_project_active
uncomment_root_include

echo
echo "Project activated: ${PROJECT_NAME}"
echo
echo "Next step depends on what you want:"
echo "  - restore archived WordPress data: ./docker/scripts/restore-site.sh dev ${PROJECT_NAME}"
echo "  - fresh WordPress install:       ./docker/scripts/bootstrap-wordpress.sh dev ${PROJECT_NAME} ..."
echo "  - fullstack Django setup:        ./docker/scripts/bootstrap-django.sh dev ${PROJECT_NAME}"
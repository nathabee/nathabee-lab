#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./docker/scripts/delete-project.sh <dev|prod> <project_name> [--yes] [--no-export]

What it does:
  - optionally exports the live WordPress site back into data/<project> first
  - runs docker compose down -v ONLY for docker/sites/<project>/compose.yaml
  - sets active=false in data/world-list.json
  - comments out the matching include block in docker/compose.yaml
  - deletes bind-mounted runtime directories for that project

What it does NOT delete:
  - data/<project>
  - docker/sites/<project>
  - env entries in docker/.env.dev or docker/.env.prod

Notes:
  - This is a project data purge + deactivate, not a project definition delete.
  - For wordpress projects, you can refresh the archive before deletion.
  - For fullstack projects, automatic Django export is not implemented here.

Options:
  --yes        skip confirmation prompt
  --no-export  do not offer/export WordPress runtime before deletion
EOF
}

require_cmd() {
  local cmd="${1:-}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}"
    exit 1
  fi
}

resolve_env_value() {
  local key="${1:-}"

  if [[ -z "${key}" ]]; then
    return 0
  fi

  if [[ -z "${!key-}" ]]; then
    echo "Env variable ${key} is not set in ${ENV_FILE}"
    exit 1
  fi

  printf '%s\n' "${!key}"
}

extract_mount_source() {
  local mount_value="${1:-}"

  if [[ -z "${mount_value}" ]]; then
    return 0
  fi

  printf '%s\n' "${mount_value%%:*}"
}

is_bind_source() {
  local source="${1:-}"

  if [[ -z "${source}" ]]; then
    return 1
  fi

  case "${source}" in
    /*|./*|../*)
      return 0
      ;;
    *)
      ;;
  esac

  if [[ "${source}" == *"/"* ]]; then
    return 0
  fi

  return 1
}

resolve_compose_relative_path() {
  local raw_path="${1:-}"

  if [[ -z "${raw_path}" ]]; then
    return 0
  fi

  case "${raw_path}" in
    /*)
      printf '%s\n' "${raw_path}"
      ;;
    *)
      printf '%s\n' "${DOCKER_DIR}/${raw_path#./}"
      ;;
  esac
}

get_project_json() {
  jq -ec --arg site "${PROJECT_NAME}" '
    (.projects // .)[]
    | select((.projectname // .name) == $site)
  ' "${WORLD_FILE}"
}

append_delete_path_if_bind() {
  local mount_value="${1:-}"
  local source=""
  local host_path=""
  local existing=""

  source="$(extract_mount_source "${mount_value}")"
  if ! is_bind_source "${source}"; then
    return 0
  fi

  host_path="$(resolve_compose_relative_path "${source}")"
  if [[ -z "${host_path}" ]]; then
    return 0
  fi

  for existing in "${DELETE_PATHS[@]}"; do
    if [[ "${existing}" == "${host_path}" ]]; then
      return 0
    fi
  done

  DELETE_PATHS+=("${host_path}")
}

offer_wordpress_export() {
  if [[ "${NO_EXPORT}" == "true" ]]; then
    return 0
  fi

  if [[ "${PROJECT_TYPE}" != "wordpress" ]]; then
    if [[ "${PROJECT_TYPE}" == "fullstack" ]]; then
      echo
      echo "Warning:"
      echo "  ${PROJECT_NAME} is a fullstack project."
      echo "  Automatic Django export/update back to data/ is not implemented here."
      echo "  WordPress-only export-site.sh is not enough for fullstack backup."
      echo
    fi
    return 0
  fi

  if [[ "${ASSUME_YES}" == "true" ]]; then
    return 0
  fi

  echo
  read -r -p "Export live WordPress runtime back into data/${PROJECT_NAME} before delete? [y/N] " answer

  case "${answer}" in
    y|Y|yes|YES)
      "${SCRIPT_DIR}/export-site.sh" "${MODE}" "${PROJECT_NAME}"
      ;;
    *)
      ;;
  esac
}

confirm_delete() {
  local path=""

  if [[ "${ASSUME_YES}" == "true" ]]; then
    return 0
  fi

  echo
  echo "You are about to delete runtime data for project: ${PROJECT_NAME}"
  echo "Mode: ${MODE}"
  echo
  echo "This will:"
  echo "  - docker compose down -v for docker/sites/${PROJECT_NAME}/compose.yaml"
  echo "  - set active=false in data/world-list.json"
  echo "  - comment out the include in docker/compose.yaml"

  if [[ "${#DELETE_PATHS[@]}" -gt 0 ]]; then
    echo "  - delete bind-mounted runtime path(s):"
    for path in "${DELETE_PATHS[@]}"; do
      echo "      ${path}"
    done
  else
    echo "  - no bind-mounted runtime paths detected for deletion"
  fi

  echo
  echo "This will NOT delete:"
  echo "  - ${REPO_ROOT}/data/${PROJECT_NAME}"
  echo "  - ${DOCKER_DIR}/sites/${PROJECT_NAME}"
  echo "  - docker/.env.dev or docker/.env.prod entries"
  echo
  read -r -p "Type the exact project name to confirm: " typed_name

  if [[ "${typed_name}" != "${PROJECT_NAME}" ]]; then
    echo "Confirmation failed. Aborting."
    exit 1
  fi
}

down_project() {
  if [[ ! -f "${PROJECT_COMPOSE_FILE}" ]]; then
    echo "Missing project compose file: ${PROJECT_COMPOSE_FILE}"
    exit 1
  fi

  echo "Stopping and removing containers/volumes for ${PROJECT_NAME}..."

  docker compose \
    --env-file "${ENV_FILE}" \
    --project-directory "${DOCKER_DIR}" \
    -f "${PROJECT_COMPOSE_FILE}" \
    down -v --remove-orphans
}

mark_project_inactive() {
  local tmp_file
  tmp_file="$(mktemp)"

  jq --arg project "${PROJECT_NAME}" '
    if has("projects") then
      .projects |= map(
        if ((.projectname // .name) == $project) then
          .active = false
        else
          .
        end
      )
    else
      map(
        if ((.projectname // .name) == $project) then
          .active = false
        else
          .
        end
      )
    end
  ' "${WORLD_FILE}" > "${tmp_file}"

  mv "${tmp_file}" "${WORLD_FILE}"
  echo "Marked inactive in ${WORLD_FILE}"
}

comment_root_include() {
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

    if needle in line and not line.lstrip().startswith("#"):
        item_indent = len(line) - len(line.lstrip(" "))
        out.append(" " * item_indent + "# " + line[item_indent:])
        changed = True
        i += 1

        while i < len(lines):
            nxt = lines[i]

            if nxt.strip() == "":
                out.append(nxt)
                i += 1
                break

            nxt_indent = len(nxt) - len(nxt.lstrip(" "))

            if nxt_indent > item_indent:
                if nxt.lstrip().startswith("#"):
                    out.append(nxt)
                else:
                    out.append(" " * nxt_indent + "# " + nxt[nxt_indent:])
                i += 1
            else:
                break

        continue

    out.append(line)
    i += 1

if changed:
    compose_path.write_text("".join(out), encoding="utf-8")
    print(f"Commented include block in {compose_path}")
else:
    print(f"No uncommented include block found for {project_name} in {compose_path}")
PY
}

delete_runtime_paths() {
  local path=""

  if [[ "${#DELETE_PATHS[@]}" -eq 0 ]]; then
    echo "No bind-mounted runtime paths to delete."
    return 0
  fi

  for path in "${DELETE_PATHS[@]}"; do
    if [[ -e "${path}" ]]; then
      rm -rf "${path}"
      echo "Deleted runtime path: ${path}"
    else
      echo "Runtime path not found, skipped: ${path}"
    fi
  done
}

MODE="${1:-}"
PROJECT_NAME="${2:-}"

if [[ -z "${MODE}" || -z "${PROJECT_NAME}" ]]; then
  usage
  exit 1
fi

shift 2 || true

ASSUME_YES="false"
NO_EXPORT="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)
      ASSUME_YES="true"
      shift
      ;;
    --no-export)
      NO_EXPORT="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ "${MODE}" != "dev" && "${MODE}" != "prod" ]]; then
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${DOCKER_DIR}/.." && pwd)"

ENV_FILE="${DOCKER_DIR}/.env.${MODE}"
WORLD_FILE="${REPO_ROOT}/data/world-list.json"
ROOT_COMPOSE_FILE="${DOCKER_DIR}/compose.yaml"
PROJECT_COMPOSE_FILE="${DOCKER_DIR}/sites/${PROJECT_NAME}/compose.yaml"

require_cmd jq
require_cmd docker
require_cmd python3

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}"
  exit 1
fi

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

set -a
source "${ENV_FILE}"
set +a

PROJECT_JSON="$(get_project_json)" || {
  echo "Project not found in ${WORLD_FILE}: ${PROJECT_NAME}"
  exit 1
}

PROJECT_TYPE="$(jq -r '.projecttype // .type // empty' <<< "${PROJECT_JSON}")"

WP_FILES_MOUNT_KEY="$(jq -r '.env.wp_files_mount // empty' <<< "${PROJECT_JSON}")"
DJANGO_CODE_MOUNT_KEY="$(jq -r '.env.django_code_mount // empty' <<< "${PROJECT_JSON}")"

WP_FILES_MOUNT_VALUE=""
DJANGO_CODE_MOUNT_VALUE=""

if [[ -n "${WP_FILES_MOUNT_KEY}" ]]; then
  WP_FILES_MOUNT_VALUE="$(resolve_env_value "${WP_FILES_MOUNT_KEY}")"
fi

if [[ -n "${DJANGO_CODE_MOUNT_KEY}" ]]; then
  DJANGO_CODE_MOUNT_VALUE="$(resolve_env_value "${DJANGO_CODE_MOUNT_KEY}")"
fi

DELETE_PATHS=()
append_delete_path_if_bind "${WP_FILES_MOUNT_VALUE}"
append_delete_path_if_bind "${DJANGO_CODE_MOUNT_VALUE}"

offer_wordpress_export
confirm_delete
down_project
mark_project_inactive
comment_root_include
delete_runtime_paths

echo
echo "Delete complete for ${PROJECT_NAME}"
echo "Kept:"
echo "  - data/${PROJECT_NAME}"
echo "  - docker/sites/${PROJECT_NAME}"
echo "  - env definitions"
echo
echo "Next time do NOT run create-project.sh again."
echo "Reactivate first, then restore/bootstrap as needed."
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./docker/scripts/mod-file-access.sh <dev|prod> <project_name>

What it does:
  - detects bind-mounted runtime paths for the project
  - ensures the relevant service is running
  - normalizes ownership and permissions through the container

Target permissions:
  - owner/group: www-data:www-data
  - directories: 2775
  - executable files: 775
  - non-executable files: 664

Notes:
  - this is intended for bind-mounted runtime paths
  - it is safe to run after restore, bootstrap, uploads, or before delete
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

resolve_host_path() {
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

django_runtime_env_exists() {
  local env_file_value="${1:-}"
  local env_file_host=""

  if [[ -z "${env_file_value}" ]]; then
    return 1
  fi

  env_file_host="$(resolve_host_path "${env_file_value}")"
  [[ -n "${env_file_host}" && -f "${env_file_host}" ]]
}

get_project_json() {
  jq -ec --arg site "${PROJECT_NAME}" '
    (.projects // .)[]
    | select((.projectname // .name) == $site)
  ' "${WORLD_FILE}"
}

service_is_running() {
  local service="${1:-}"
  local container_id=""

  container_id="$("${COMPOSE[@]}" ps -q "${service}" 2>/dev/null || true)"
  if [[ -z "${container_id}" ]]; then
    return 1
  fi

  [[ "$(docker inspect -f '{{.State.Status}}' "${container_id}" 2>/dev/null || true)" == "running" ]]
}

ensure_service_running() {
  local service="${1:-}"

  if service_is_running "${service}"; then
    return 0
  fi

  echo "Starting service ${service} ..."
  "${COMPOSE[@]}" up -d "${service}"
}

normalize_service_path() {
  local service="${1:-}"
  local container_path="${2:-}"
  local host_path="${3:-}"
  local label="${4:-runtime}"

  if [[ -z "${service}" || -z "${container_path}" ]]; then
    echo "Missing service or container path for permission normalization."
    exit 1
  fi

  ensure_service_running "${service}"

  echo "Normalizing ${label}:"
  echo "  service: ${service}"
  echo "  host:    ${host_path}"
  echo "  inside:  ${container_path}"

  "${COMPOSE[@]}" exec -T --user root "${service}" sh -lc "
    set -eu

    if [ ! -e '${container_path}' ]; then
      echo 'Path not found inside container: ${container_path}' >&2
      exit 1
    fi

    chown -R www-data:www-data '${container_path}'
    find '${container_path}' -type d -exec chmod 2775 {} +
    find '${container_path}' -type f -perm /111 -exec chmod 775 {} +
    find '${container_path}' -type f ! -perm /111 -exec chmod 664 {} +

    if [ -f '${container_path}/.htpasswd' ]; then
      chmod 640 '${container_path}/.htpasswd'
    fi
  "
}

MODE="${1:-}"
PROJECT_NAME="${2:-}"

if [[ -z "${MODE}" || -z "${PROJECT_NAME}" ]]; then
  usage
  exit 1
fi

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

require_cmd jq
require_cmd docker

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

set -a
source "${ENV_FILE}"
set +a

COMPOSE=(docker compose --env-file "${ENV_FILE}" -f "${ROOT_COMPOSE_FILE}")

PROJECT_JSON="$(get_project_json)" || {
  echo "Project not found in ${WORLD_FILE}: ${PROJECT_NAME}"
  exit 1
}

PROJECT_TYPE="$(jq -r '.projecttype // .type // empty' <<< "${PROJECT_JSON}")"
WP_SERVICE="$(jq -r '.compose.wp_service // empty' <<< "${PROJECT_JSON}")"
DJANGO_SERVICE="$(jq -r '.compose.django_service // empty' <<< "${PROJECT_JSON}")"

WP_FILES_MOUNT_KEY="$(jq -r '.env.wp_files_mount // empty' <<< "${PROJECT_JSON}")"
DJANGO_CODE_MOUNT_KEY="$(jq -r '.env.django_code_mount // empty' <<< "${PROJECT_JSON}")"
DJANGO_ENV_FILE_KEY="$(jq -r '.env.django_env_file // empty' <<< "${PROJECT_JSON}")"

WP_FILES_MOUNT_VALUE=""
DJANGO_CODE_MOUNT_VALUE=""
DJANGO_ENV_FILE_VALUE=""
NORMALIZED_COUNT=0

if [[ -n "${WP_FILES_MOUNT_KEY}" ]]; then
  WP_FILES_MOUNT_VALUE="$(resolve_env_value "${WP_FILES_MOUNT_KEY}")"
fi

if [[ -n "${DJANGO_CODE_MOUNT_KEY}" ]]; then
  DJANGO_CODE_MOUNT_VALUE="$(resolve_env_value "${DJANGO_CODE_MOUNT_KEY}")"
fi

if [[ -n "${DJANGO_ENV_FILE_KEY}" ]]; then
  DJANGO_ENV_FILE_VALUE="$(resolve_env_value "${DJANGO_ENV_FILE_KEY}")"
fi

WP_SOURCE="$(extract_mount_source "${WP_FILES_MOUNT_VALUE}")"
if is_bind_source "${WP_SOURCE}"; then
  WP_HOST_PATH="$(resolve_host_path "${WP_SOURCE}")"
  normalize_service_path "${WP_SERVICE}" "/var/www/html" "${WP_HOST_PATH}" "wordpress runtime"
  NORMALIZED_COUNT=$((NORMALIZED_COUNT + 1))
fi

DJANGO_SOURCE="$(extract_mount_source "${DJANGO_CODE_MOUNT_VALUE}")"
if is_bind_source "${DJANGO_SOURCE}"; then
  if django_runtime_env_exists "${DJANGO_ENV_FILE_VALUE}"; then
    DJANGO_HOST_PATH="$(resolve_host_path "${DJANGO_SOURCE}")"
    normalize_service_path "${DJANGO_SERVICE}" "/django" "${DJANGO_HOST_PATH}" "django runtime"
    NORMALIZED_COUNT=$((NORMALIZED_COUNT + 1))
  else
    echo "Skipping django runtime normalization for ${PROJECT_NAME}:"
    echo "  Django runtime env file does not exist yet."
    echo "  Expected after bootstrap-django: $(resolve_host_path "${DJANGO_ENV_FILE_VALUE}")"
  fi
fi

if [[ "${NORMALIZED_COUNT}" -eq 0 ]]; then
  echo "No bind-mounted runtime paths detected for ${PROJECT_NAME}."
  exit 0
fi

echo
echo "Permission normalization complete for ${PROJECT_NAME}."
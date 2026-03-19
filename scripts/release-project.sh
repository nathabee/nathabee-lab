#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${PROJECT_ROOT}/data"
WORLD_FILE="${DATA_DIR}/world-list.json"
BUILD_DIR="${PROJECT_ROOT}/build/releases"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [--local-only] [--stamp YYYYMMDD-HHMMSS] <project>

Examples:
  $(basename "$0") demo_wordpress
  $(basename "$0") --local-only demo_fullstack
  $(basename "$0") --stamp 20260315-101530 demo_fullstack
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
STAMP=""
PROJECT_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local-only)
      LOCAL_ONLY=1
      shift
      ;;
    --stamp)
      if [[ $# -lt 2 ]]; then
        echo "Error: --stamp requires a value" >&2
        exit 1
      fi
      STAMP="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -n "${PROJECT_NAME}" ]]; then
        echo "Error: only one project can be released at a time" >&2
        usage
        exit 1
      fi
      PROJECT_NAME="$1"
      shift
      ;;
  esac
done

if [[ -z "${PROJECT_NAME}" ]]; then
  echo "Error: missing project name" >&2
  usage
  exit 1
fi

require_cmd git
require_cmd jq

if [[ ! -f "${WORLD_FILE}" ]]; then
  echo "Error: missing world list: ${WORLD_FILE}" >&2
  exit 1
fi

PROJECT_JSON="$(
  jq -e --arg name "${PROJECT_NAME}" '
    (.projects // .)[]
    | select((.projectname // .name) == $name)
  ' "${WORLD_FILE}"
)" || {
  echo "Error: project not found in ${WORLD_FILE}: ${PROJECT_NAME}" >&2
  exit 1
}

PROJECT_TYPE="$(printf '%s\n' "${PROJECT_JSON}" | jq -r '.projecttype // .type // empty')"

if [[ "${PROJECT_TYPE}" != "wordpress" && "${PROJECT_TYPE}" != "fullstack" ]]; then
  echo "Error: unsupported project type for ${PROJECT_NAME}: ${PROJECT_TYPE}" >&2
  exit 1
fi

if [[ -z "${STAMP}" ]]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
fi

TAG="data-${PROJECT_NAME}-${STAMP}"
ARCHIVE_NAME="${TAG}.tar.gz"
ARCHIVE_PATH="${BUILD_DIR}/${ARCHIVE_NAME}"
PROJECT_DATA_DIR="${DATA_DIR}/${PROJECT_NAME}"
CONFIG_JSON="${PROJECT_DATA_DIR}/updateArchive.json"

if [[ ! -d "${PROJECT_DATA_DIR}" ]]; then
  echo "Error: missing data directory: ${PROJECT_DATA_DIR}" >&2
  exit 1
fi

if [[ ! -f "${CONFIG_JSON}" ]]; then
  echo "Error: missing file: ${CONFIG_JSON}" >&2
  echo "Run the appropriate export first." >&2
  exit 1
fi

if [[ ! -d "${PROJECT_DATA_DIR}/database" ]]; then
  echo "Error: missing database directory: ${PROJECT_DATA_DIR}/database" >&2
  exit 1
fi

if [[ ! -d "${PROJECT_DATA_DIR}/wpfile" ]]; then
  echo "Error: missing wpfile directory: ${PROJECT_DATA_DIR}/wpfile" >&2
  exit 1
fi

WP_DUMP_REL="$(jq -r '.database_dump // empty' "${CONFIG_JSON}")"
if [[ -z "${WP_DUMP_REL}" ]]; then
  echo "Error: updateArchive.json is missing .database_dump" >&2
  exit 1
fi

WP_DUMP_PATH="${PROJECT_DATA_DIR}/${WP_DUMP_REL}"
if [[ ! -f "${WP_DUMP_PATH}" ]]; then
  echo "Error: missing WordPress DB dump: ${WP_DUMP_PATH}" >&2
  exit 1
fi

if [[ "${PROJECT_TYPE}" == "fullstack" ]]; then
  if [[ ! -d "${PROJECT_DATA_DIR}/django" ]]; then
    echo "Error: missing django directory: ${PROJECT_DATA_DIR}/django" >&2
    echo "Run ./docker/scripts/export-fullstack.sh first." >&2
    exit 1
  fi

  DJANGO_DUMP_REL="$(jq -r '.django_database_dump // empty' "${CONFIG_JSON}")"
  if [[ -z "${DJANGO_DUMP_REL}" ]]; then
    echo "Error: updateArchive.json is missing .django_database_dump for fullstack project" >&2
    echo "Run ./docker/scripts/export-fullstack.sh first." >&2
    exit 1
  fi

  DJANGO_DUMP_PATH="${PROJECT_DATA_DIR}/${DJANGO_DUMP_REL}"
  if [[ ! -f "${DJANGO_DUMP_PATH}" ]]; then
    echo "Error: missing Django DB dump: ${DJANGO_DUMP_PATH}" >&2
    exit 1
  fi
fi

if ! git -C "${PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: ${PROJECT_ROOT} is not a git repository" >&2
  exit 1
fi

if ! git -C "${PROJECT_ROOT}" diff --quiet || ! git -C "${PROJECT_ROOT}" diff --cached --quiet; then
  echo "Error: working tree is not clean. Commit or stash changes first." >&2
  exit 1
fi

if [[ "${LOCAL_ONLY}" -eq 0 ]]; then
  require_cmd gh

  if ! git -C "${PROJECT_ROOT}" remote get-url origin >/dev/null 2>&1; then
    echo "Error: git remote 'origin' is not configured" >&2
    exit 1
  fi

  if ! gh auth status >/dev/null 2>&1; then
    echo "Error: gh is not authenticated. Run: gh auth login" >&2
    exit 1
  fi
fi

mkdir -p "${BUILD_DIR}"
rm -f "${ARCHIVE_PATH}"

echo "Creating archive: ${ARCHIVE_PATH}"
tar -C "${DATA_DIR}" -czf "${ARCHIVE_PATH}" "${PROJECT_NAME}"

HEAD_COMMIT="$(git -C "${PROJECT_ROOT}" rev-parse HEAD)"

if git -C "${PROJECT_ROOT}" rev-parse -q --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
  TAG_COMMIT="$(git -C "${PROJECT_ROOT}" rev-list -n 1 "${TAG}")"
  if [[ "${TAG_COMMIT}" != "${HEAD_COMMIT}" ]]; then
    echo "Error: local tag ${TAG} already exists on another commit" >&2
    exit 1
  fi
  echo "Reusing existing local tag: ${TAG}"
else
  echo "Creating local tag: ${TAG}"
  git -C "${PROJECT_ROOT}" tag -a "${TAG}" -m "Data release for ${PROJECT_NAME} (${STAMP})"
fi

if [[ "${LOCAL_ONLY}" -eq 1 ]]; then
  echo
  echo "Local-only mode complete."
  echo "Archive: ${ARCHIVE_PATH}"
  echo "Tag:     ${TAG}"
  exit 0
fi

if git -C "${PROJECT_ROOT}" ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
  echo "Remote tag already exists: ${TAG}"
else
  echo "Pushing tag to origin: ${TAG}"
  git -C "${PROJECT_ROOT}" push origin "${TAG}"
fi

if (cd "${PROJECT_ROOT}" && gh release view "${TAG}" >/dev/null 2>&1); then
  echo "GitHub release already exists. Uploading asset with --clobber."
  (cd "${PROJECT_ROOT}" && gh release upload "${TAG}" "${ARCHIVE_PATH}" --clobber)
else
  echo "Creating GitHub release: ${TAG}"
  (
    cd "${PROJECT_ROOT}" && \
    gh release create "${TAG}" "${ARCHIVE_PATH}" \
      --title "${TAG}" \
      --notes "Data release for ${PROJECT_NAME} generated on ${STAMP}."
  )
fi

echo
echo "Release complete."
echo "Project: ${PROJECT_NAME}"
echo "Type:    ${PROJECT_TYPE}"
echo "Archive: ${ARCHIVE_PATH}"
echo "Tag:     ${TAG}"
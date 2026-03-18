#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${PROJECT_ROOT}/data"
BUILD_DIR="${PROJECT_ROOT}/build/releases"

ALLOWED_ENVS=("nathabee_wordpress" "orthopedagogie" "orthopedagogiedutregor")

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [--local-only] [--stamp YYYYMMDD-HHMMSS] <environment>

Allowed environments:
  ${ALLOWED_ENVS[*]}

Examples:
  $(basename "$0") orthopedagogie
  $(basename "$0") --local-only nathabee_wordpress
  $(basename "$0") --stamp 20260315-101530 orthopedagogiedutregor
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

require_cmd() {
  local cmd="$1"

  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Error: required command not found: ${cmd}" >&2
    exit 1
  fi
}

LOCAL_ONLY=0
STAMP=""
ENV_NAME=""

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
      if [[ -n "${ENV_NAME}" ]]; then
        echo "Error: only one environment can be released at a time" >&2
        usage
        exit 1
      fi
      ENV_NAME="$1"
      shift
      ;;
  esac
done

if [[ -z "${ENV_NAME}" ]]; then
  echo "Error: missing environment name" >&2
  usage
  exit 1
fi

if ! is_allowed_env "${ENV_NAME}"; then
  echo "Error: unknown environment '${ENV_NAME}'" >&2
  echo "Allowed values: ${ALLOWED_ENVS[*]}" >&2
  exit 1
fi

if [[ -z "${STAMP}" ]]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
fi

TAG="data-${ENV_NAME}-${STAMP}"
ARCHIVE_NAME="${TAG}.tar.gz"
ARCHIVE_PATH="${BUILD_DIR}/${ARCHIVE_NAME}"
ENV_DIR="${DATA_DIR}/${ENV_NAME}"

require_cmd git

if [[ ! -d "${ENV_DIR}" ]]; then
  echo "Error: missing data directory: ${ENV_DIR}" >&2
  exit 1
fi

if [[ ! -d "${ENV_DIR}/database" ]]; then
  echo "Error: missing database directory: ${ENV_DIR}/database" >&2
  exit 1
fi

if [[ ! -d "${ENV_DIR}/wpfile" ]]; then
  echo "Error: missing wpfile directory: ${ENV_DIR}/wpfile" >&2
  exit 1
fi

if [[ ! -f "${ENV_DIR}/updateArchive.json" ]]; then
  echo "Error: missing file: ${ENV_DIR}/updateArchive.json" >&2
  exit 1
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
tar -C "${DATA_DIR}" -czf "${ARCHIVE_PATH}" "${ENV_NAME}"

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
  git -C "${PROJECT_ROOT}" tag -a "${TAG}" -m "Data release for ${ENV_NAME} (${STAMP})"
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
      --notes "Data release for ${ENV_NAME} generated on ${STAMP}."
  )
fi

echo
echo "Release complete."
echo "Archive: ${ARCHIVE_PATH}"
echo "Tag:     ${TAG}"

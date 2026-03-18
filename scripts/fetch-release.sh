#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${PROJECT_ROOT}/data"
DOWNLOAD_DIR="${PROJECT_ROOT}/build/releases"

ALLOWED_ENVS=("demo_fullstack" "orthopedagogie" "demo_fullstack")
ENV_REGEX='demo_fullstack|orthopedagogie|demo_fullstack'

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [--repo owner/name] <YYYYMMDD-HHMMSS> [environment ...]
  $(basename "$0") [--repo owner/name] --list <YYYYMMDD-HHMMSS> [environment ...]
  $(basename "$0") [--repo owner/name] --recent [count]
  $(basename "$0") [--repo owner/name] --recent-stamps [count]

Description:
  Download one or more GitHub release assets matching a shared release stamp
  and extract them into ./data.

Release tag pattern:
  data-<environment>-<YYYYMMDD-HHMMSS>

Known environments:
  ${ALLOWED_ENVS[*]}

Examples:
  $(basename "$0") 20260315-101530
  $(basename "$0") 20260315-101530 orthopedagogie
  $(basename "$0") --list 20260315-101530
  $(basename "$0") --recent
  $(basename "$0") --recent 12
  $(basename "$0") --recent-stamps
  $(basename "$0") --recent-stamps 10
  $(basename "$0") --repo nathabee/nathabee-lab --recent
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Error: required command not found: ${cmd}" >&2
    exit 1
  fi
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

derive_repo_from_git_remote() {
  local remote_url
  remote_url="$(git -C "${PROJECT_ROOT}" remote get-url origin 2>/dev/null || true)"

  if [[ -z "${remote_url}" ]]; then
    echo "Error: could not determine GitHub repo from git remote 'origin'" >&2
    echo "Use: $(basename "$0") --repo owner/name <stamp>" >&2
    exit 1
  fi

  case "${remote_url}" in
    git@github.com:*.git)
      echo "${remote_url#git@github.com:}" | sed 's/\.git$//'
      ;;
    git@github.com:*)
      echo "${remote_url#git@github.com:}"
      ;;
    https://github.com/*.git)
      echo "${remote_url#https://github.com/}" | sed 's/\.git$//'
      ;;
    https://github.com/*)
      echo "${remote_url#https://github.com/}"
      ;;
    *)
      echo "Error: unsupported Git remote format: ${remote_url}" >&2
      echo "Use: $(basename "$0") --repo owner/name <stamp>" >&2
      exit 1
      ;;
  esac
}

validate_stamp() {
  local stamp="$1"
  if [[ ! "${stamp}" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
    echo "Error: invalid stamp format '${stamp}'" >&2
    echo "Expected format: YYYYMMDD-HHMMSS" >&2
    exit 1
  fi
}

resolve_envs() {
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
}

ensure_repo_and_auth() {
  require_cmd gh
  require_cmd git

  if ! gh auth status >/dev/null 2>&1; then
    echo "Error: gh is not authenticated. Run: gh auth login" >&2
    exit 1
  fi

  if [[ -z "${REPO}" ]]; then
    REPO="$(derive_repo_from_git_remote)"
  fi
}

list_matching_releases() {
  local found_count=0

  echo "Repository: ${REPO}"
  echo "Stamp:      ${STAMP}"
  echo

  for ENV_NAME in "${ENVS[@]}"; do
    local tag="data-${ENV_NAME}-${STAMP}"

    if gh release view "${tag}" --repo "${REPO}" >/dev/null 2>&1; then
      echo "[FOUND]   ${tag}"
      found_count=$((found_count + 1))
    else
      echo "[MISSING] ${tag}"
    fi
  done

  echo
  echo "Found ${found_count} matching release(s)."

  if [[ "${found_count}" -eq 0 ]]; then
    exit 1
  fi
}

list_recent_releases() {
  local api_limit
  api_limit="${RECENT_COUNT}"

  if [[ "${api_limit}" -lt 1 ]]; then
    api_limit=10
  fi
  if [[ "${api_limit}" -gt 100 ]]; then
    api_limit=100
  fi

  require_cmd jq

  echo "Repository: ${REPO}"
  echo "Latest matching release tags:"
  echo

  gh api "repos/${REPO}/releases?per_page=${api_limit}" | jq -r \
    --arg env_regex "${ENV_REGEX}" \
    '
      .[]
      | {
          tag: (.tag_name // ""),
          published: (.published_at // .created_at // "")
        }
      | select(.tag | test("^data-(" + $env_regex + ")-[0-9]{8}-[0-9]{6}$"))
      | . + (
          .tag
          | capture("^data-(?<env>(" + $env_regex + "))-(?<stamp>[0-9]{8}-[0-9]{6})$")
        )
      | "\(.published)\t\(.env)\t\(.stamp)\t\(.tag)"
    ' | awk 'BEGIN {
        printf "%-22s %-24s %-18s %s\n", "published_at", "environment", "stamp", "tag";
        printf "%-22s %-24s %-18s %s\n", "----------------------", "------------------------", "------------------", "----------------------------------------------";
      }
      {
        printf "%-22s %-24s %-18s %s\n", $1, $2, $3, $4;
      }'
}

list_recent_stamps() {
  local api_limit
  api_limit=$((RECENT_COUNT * 3))

  if [[ "${api_limit}" -lt 10 ]]; then
    api_limit=30
  fi
  if [[ "${api_limit}" -gt 100 ]]; then
    api_limit=100
  fi

  require_cmd jq

  echo "Repository: ${REPO}"
  echo "Latest batch stamps:"
  echo

  gh api "repos/${REPO}/releases?per_page=${api_limit}" | jq -r \
    --arg env_regex "${ENV_REGEX}" \
    --argjson wanted "${RECENT_COUNT}" \
    '
      [
        .[]
        | {
            tag: (.tag_name // ""),
            published: (.published_at // .created_at // "")
          }
        | select(.tag | test("^data-(" + $env_regex + ")-[0-9]{8}-[0-9]{6}$"))
        | . + (
            .tag
            | capture("^data-(?<env>(" + $env_regex + "))-(?<stamp>[0-9]{8}-[0-9]{6})$")
          )
      ]
      | sort_by(.published)
      | reverse
      | group_by(.stamp)
      | map({
          stamp: .[0].stamp,
          latest_published: (map(.published) | max),
          envs: (map(.env) | unique | join(", ")),
          tags: (map(.tag) | unique | join(" | "))
        })
      | sort_by(.latest_published)
      | reverse
      | .[:$wanted]
      | .[]
      | "\(.latest_published)\t\(.stamp)\t\(.envs)\t\(.tags)"
    ' | awk 'BEGIN {
        printf "%-22s %-18s %-50s %s\n", "latest_published", "stamp", "environments", "tags";
        printf "%-22s %-18s %-50s %s\n", "----------------------", "------------------", "--------------------------------------------------", "----------------------------------------------";
      }
      {
        first=$1;
        second=$2;
        $1=""; $2="";
        sub(/^  */, "", $0);

        split($0, parts, "\t");
        envs=parts[1];
        tags=parts[2];

        printf "%-22s %-18s %-50s %s\n", first, second, envs, tags;
      }'
}

REPO=""
STAMP=""
LIST_ONLY=0
LIST_RECENT=0
LIST_RECENT_STAMPS=0
RECENT_COUNT=10
REQUESTED_ENVS=()
ENVS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      if [[ $# -lt 2 ]]; then
        echo "Error: --repo requires a value like owner/name" >&2
        exit 1
      fi
      REPO="$2"
      shift 2
      ;;
    --list)
      LIST_ONLY=1
      shift
      ;;
    --recent)
      LIST_RECENT=1
      if [[ $# -gt 1 && "$2" =~ ^[0-9]+$ ]]; then
        RECENT_COUNT="$2"
        shift 2
      else
        shift
      fi
      ;;
    --recent-stamps)
      LIST_RECENT_STAMPS=1
      if [[ $# -gt 1 && "$2" =~ ^[0-9]+$ ]]; then
        RECENT_COUNT="$2"
        shift 2
      else
        shift
      fi
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "${STAMP}" ]]; then
        STAMP="$1"
      else
        REQUESTED_ENVS+=("$1")
      fi
      shift
      ;;
  esac
done

MODE_COUNT=$((LIST_ONLY + LIST_RECENT + LIST_RECENT_STAMPS))
if [[ "${MODE_COUNT}" -gt 1 ]]; then
  echo "Error: use only one of --list, --recent, or --recent-stamps" >&2
  exit 1
fi

ensure_repo_and_auth

if [[ "${LIST_RECENT}" -eq 1 ]]; then
  list_recent_releases
  exit 0
fi

if [[ "${LIST_RECENT_STAMPS}" -eq 1 ]]; then
  list_recent_stamps
  exit 0
fi

if [[ -z "${STAMP}" ]]; then
  echo "Error: missing release stamp" >&2
  usage
  exit 1
fi

validate_stamp "${STAMP}"
resolve_envs

if [[ "${LIST_ONLY}" -eq 1 ]]; then
  list_matching_releases
  exit 0
fi

require_cmd tar

mkdir -p "${DATA_DIR}" "${DOWNLOAD_DIR}"

FOUND_COUNT=0
DOWNLOADED_TAGS=()
MISSING_TAGS=()

for ENV_NAME in "${ENVS[@]}"; do
  TAG="data-${ENV_NAME}-${STAMP}"
  ASSET="${TAG}.tar.gz"
  ASSET_PATH="${DOWNLOAD_DIR}/${ASSET}"
  TARGET_ENV_DIR="${DATA_DIR}/${ENV_NAME}"

  if gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
    echo "Found release: ${TAG}"
    echo "Downloading asset: ${ASSET}"
    gh release download "${TAG}" \
      --repo "${REPO}" \
      --pattern "${ASSET}" \
      --dir "${DOWNLOAD_DIR}" \
      --clobber

    if [[ -d "${TARGET_ENV_DIR}" ]]; then
      echo "Removing existing local data directory: ${TARGET_ENV_DIR}"
      rm -rf "${TARGET_ENV_DIR}"
    fi

    echo "Extracting ${ASSET} into ${DATA_DIR}"
    tar -xzf "${ASSET_PATH}" -C "${DATA_DIR}"

    if [[ ! -f "${TARGET_ENV_DIR}/updateArchive.json" ]]; then
      echo "Error: extracted archive for ${ENV_NAME} is incomplete" >&2
      exit 1
    fi

    DOWNLOADED_TAGS+=("${TAG}")
    FOUND_COUNT=$((FOUND_COUNT + 1))
  else
    echo "Release not found: ${TAG}"
    MISSING_TAGS+=("${TAG}")
  fi
done

if [[ "${FOUND_COUNT}" -eq 0 ]]; then
  echo "Error: no matching releases found for stamp ${STAMP} in ${REPO}" >&2
  exit 1
fi

echo
echo "Fetch complete."
echo "Repository: ${REPO}"
echo "Stamp:      ${STAMP}"
echo "Fetched:    ${FOUND_COUNT}"

for TAG in "${DOWNLOADED_TAGS[@]}"; do
  echo "  - ${TAG}"
done

if [[ ${#MISSING_TAGS[@]} -gt 0 ]]; then
  echo
  echo "Not found:"
  for TAG in "${MISSING_TAGS[@]}"; do
    echo "  - ${TAG}"
  done
fi

#!/usr/bin/env bash
# docker/scripts/alias.sh
# Usage:
#   source docker/scripts/alias.sh [dev|prod] [site]
#
# Examples:
#   source docker/scripts/alias.sh dev
#   source docker/scripts/alias.sh dev demo_fullstack
#   nwenv prod
#   nwsite demo_fullstack
#   nwup
#   nwwpls
#   nwwp option get home
#   nwexportsite demo_fullstack

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "This file must be sourced, not executed."
  echo "Use: source docker/scripts/alias.sh [dev|prod] [site]"
  exit 1
fi

_DEMOWP_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
_DEMOWP_STACK_DIR="${_DEMOWP_ROOT}/docker"
_DEMOWP_WORLD_FILE="${_DEMOWP_ROOT}/data/world-list.json"

_nw_validate_env() {
  case "${1:-}" in
    dev|prod) return 0 ;;
    *)
      echo "Environment must be 'dev' or 'prod'."
      return 1
      ;;
  esac
}

_nw_require_file() {
  local file="${1:-}"
  if [[ -z "${file}" || ! -f "${file}" ]]; then
    echo "Missing file: ${file}"
    return 1
  fi
}

_nw_require_cmd() {
  local cmd="${1:-}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}"
    return 1
  fi
}

_nw_get_sites() {
  jq -r '
    (.projects // .)[]
    | select((.projecttype // .type // "") == "wordpress")
    | (.projectname // .name // empty)
  ' "${_DEMOWP_WORLD_FILE}"
}

_nw_get_active_sites() {
  jq -r '
    (.projects // .)[]
    | select((.projecttype // .type // "") == "wordpress")
    | select((.active // false) == true)
    | (.projectname // .name // empty)
  ' "${_DEMOWP_WORLD_FILE}"
}

_nw_default_site() {
  local site
  site="$(_nw_get_active_sites | head -n 1)"
  if [[ -n "${site}" ]]; then
    printf '%s\n' "${site}"
    return 0
  fi

  site="$(_nw_get_sites | head -n 1)"
  if [[ -n "${site}" ]]; then
    printf '%s\n' "${site}"
    return 0
  fi

  echo "No wordpress projects found in ${_DEMOWP_WORLD_FILE}" >&2
  return 1
}

_nw_validate_site() {
  local site="${1:-}"

  if [[ -z "${site}" ]]; then
    echo "Site must not be empty."
    return 1
  fi

  if jq -e --arg site "${site}" '
    (.projects // .)[]
    | select((.projecttype // .type // "") == "wordpress")
    | select((.projectname // .name) == $site)
  ' "${_DEMOWP_WORLD_FILE}" >/dev/null 2>&1; then
    return 0
  fi

  echo "Unknown wordpress site: ${site}"
  echo "Defined in world-list.json:"
  _nw_get_sites | sed 's/^/  - /'
  return 1
}

_nw_get_project_json() {
  local site="${1:-}"
  jq -ec --arg site "${site}" '
    (.projects // .)[]
    | select((.projecttype // .type // "") == "wordpress")
    | select((.projectname // .name) == $site)
  ' "${_DEMOWP_WORLD_FILE}"
}

_nw_read_compose_project_name() {
  local env_file="${1:-}"
  local line

  line="$(grep -E '^[[:space:]]*COMPOSE_PROJECT_NAME=' "${env_file}" | tail -n 1 || true)"
  if [[ -z "${line}" ]]; then
    return 0
  fi

  line="${line#*=}"
  line="${line%\"}"
  line="${line#\"}"
  line="${line%\'}"
  line="${line#\'}"

  printf '%s\n' "${line}"
}

_nw_set_env() {
  local env="${1:-dev}"

  _nw_require_cmd jq || return 1
  _nw_validate_env "${env}" || return 1
  _nw_require_file "${_DEMOWP_WORLD_FILE}" || return 1

  export DEMOWP_ENV="${env}"
  export DEMOWP_ENV_FILE="${_DEMOWP_STACK_DIR}/.env.${env}"
  export DEMOWP_COMPOSE_FILE="${_DEMOWP_STACK_DIR}/compose.yaml"

  _nw_require_file "${DEMOWP_ENV_FILE}" || return 1
  _nw_require_file "${DEMOWP_COMPOSE_FILE}" || return 1

  export DEMOWP_COMPOSE_PROJECT_NAME="$(_nw_read_compose_project_name "${DEMOWP_ENV_FILE}")"
}

_nw_set_site() {
  local site="${1:-}"

  if [[ -z "${site}" ]]; then
    site="$(_nw_default_site)" || return 1
  fi

  _nw_validate_site "${site}" || return 1

  local project_json
  project_json="$(_nw_get_project_json "${site}")" || return 1

  export DEMOWP_SITE="${site}"
  export DEMOWP_WP_SERVICE
  export DEMOWP_WPCLI_SERVICE
  export DEMOWP_DB_SERVICE

  DEMOWP_WP_SERVICE="$(jq -r '.compose.wp_service // empty' <<< "${project_json}")"
  DEMOWP_WPCLI_SERVICE="$(jq -r '.compose.wpcli_service // empty' <<< "${project_json}")"
  DEMOWP_DB_SERVICE="$(jq -r '.compose.db_service // empty' <<< "${project_json}")"

  if [[ -z "${DEMOWP_WP_SERVICE}" || -z "${DEMOWP_WPCLI_SERVICE}" || -z "${DEMOWP_DB_SERVICE}" ]]; then
    echo "Project ${site} is missing compose service mapping in ${_DEMOWP_WORLD_FILE}"
    return 1
  fi
}

_nw_set_env "${1:-dev}" || return 1
_nw_set_site "${2:-}" || return 1

nwenv() {
  _nw_set_env "${1:-dev}" || return 1
  echo "nathabee-lab env -> ${DEMOWP_ENV}"
}

nwsite() {
  _nw_set_site "${1:-}" || return 1
  echo "nathabee-lab site -> ${DEMOWP_SITE}"
}

nwdc() {
  (
    cd "${_DEMOWP_ROOT}" && \
    docker compose \
      --env-file "${DEMOWP_ENV_FILE}" \
      -f "${DEMOWP_COMPOSE_FILE}" \
      "$@"
  )
}

nwdccli() {
  (
    cd "${_DEMOWP_ROOT}" && \
    docker compose \
      --profile cli \
      --env-file "${DEMOWP_ENV_FILE}" \
      -f "${DEMOWP_COMPOSE_FILE}" \
      "$@"
  )
}

nwup() {
  nwdc up -d "$@"
}

nwdown() {
  nwdc down --remove-orphans "$@"
}

nwstop() {
  nwdc stop "$@"
}

nwps() {
  nwdc ps "$@"
}

nwlogs() {
  nwdc logs -f "$@"
}

nwbuild() {
  nwdc build "$@"
}

_nw_exec() {
  local service="${1:-}"
  shift || true

  if [[ -z "${service}" ]]; then
    echo "Usage: _nw_exec SERVICE CMD..."
    return 1
  fi

  if [[ -t 0 && -t 1 ]]; then
    nwdc exec "${service}" "$@"
  else
    nwdc exec -T "${service}" "$@"
  fi
}

_nw_cli_run() {
  local service="${1:-}"
  shift || true

  if [[ -z "${service}" ]]; then
    echo "Usage: _nw_cli_run SERVICE CMD..."
    return 1
  fi

  if [[ -t 0 && -t 1 ]]; then
    nwdccli run --rm --no-deps "${service}" "$@"
  else
    nwdccli run --rm -T --no-deps "${service}" "$@"
  fi
}

nwwpexec() {
  _nw_exec "${DEMOWP_WP_SERVICE}" "$@"
}

nwwpcliexec() {
  _nw_cli_run "${DEMOWP_WPCLI_SERVICE}" "$@"
}

nwdbexec() {
  _nw_exec "${DEMOWP_DB_SERVICE}" "$@"
}

nwwpls() {
  local path="${1:-/var/www/html}"
  nwwpexec sh -lc "ls -lah '${path}'"
}

nwwptree() {
  local path="${1:-/var/www/html}"
  nwwpexec sh -lc "
    if command -v tree >/dev/null 2>&1; then
      tree -a -L 3 '${path}'
    else
      find '${path}' -maxdepth 3 | sort
    fi
  "
}

nwwpcat() {
  local file="${1:-}"
  if [[ -z "${file}" ]]; then
    echo "Usage: nwwpcat /var/www/html/path/to/file"
    return 1
  fi
  nwwpexec sh -lc "cat '${file}'"
}

nwwpread() {
  local file="${1:-}"
  if [[ -z "${file}" ]]; then
    echo "Usage: nwwpread /var/www/html/path/to/file"
    return 1
  fi
  nwwpexec sh -lc "sed -n '1,220p' '${file}'"
}

nwwpshell() {
  nwwpexec bash
}

nwwpclishell() {
  nwwpcliexec bash
}

nwwp() {
  nwwpcliexec wp --allow-root "$@"
}

nwwpurl() {
  nwwp option get home
}

nwwpplugins() {
  nwwp plugin list
}

nwwpthemes() {
  nwwp theme list
}

nwwpusers() {
  nwwp user list
}

nwdbtables() {
  nwwp db tables
}

nwvolumes() {
  if [[ -n "${DEMOWP_COMPOSE_PROJECT_NAME:-}" ]]; then
    docker volume ls | grep -F "${DEMOWP_COMPOSE_PROJECT_NAME}" || true
  else
    docker volume ls
  fi
}

nwinspectvolume() {
  local volume="${1:-}"
  if [[ -z "${volume}" ]]; then
    echo "Usage: nwinspectvolume VOLUME_NAME"
    return 1
  fi
  docker volume inspect "${volume}"
}

nwexportfiles() {
  local site="${1:-${DEMOWP_SITE}}"
  _nw_validate_site "${site}" || return 1

  local service
  local dest
  local project_json

  project_json="$(_nw_get_project_json "${site}")" || return 1
  service="$(jq -r '.compose.wp_service // empty' <<< "${project_json}")"
  dest="${2:-${_DEMOWP_ROOT}/data/${site}/wpfile}"

  if [[ -z "${service}" ]]; then
    echo "Project ${site} is missing .compose.wp_service in ${_DEMOWP_WORLD_FILE}"
    return 1
  fi

  rm -rf "${dest}"
  mkdir -p "${dest}"

  echo "Exporting WordPress files from ${service} to ${dest} ..."

  nwdc exec -T "${service}" sh -lc \
    "cd /var/www/html && tar --exclude='./wp-config.php' --exclude='./.htpasswd' --exclude='./.htaccess.restore.bak' -cf - ." \
    | tar -xf - -C "${dest}"

  echo "Done: ${dest}"
}

nwexportdb() {
  local site="${1:-${DEMOWP_SITE}}"
  _nw_validate_site "${site}" || return 1

  local service
  local out_dir
  local out_file
  local project_json

  project_json="$(_nw_get_project_json "${site}")" || return 1
  service="$(jq -r '.compose.wpcli_service // empty' <<< "${project_json}")"
  out_dir="${_DEMOWP_ROOT}/data/${site}/database"
  out_file="${2:-${out_dir}/${site}.sql.gz}"

  if [[ -z "${service}" ]]; then
    echo "Project ${site} is missing .compose.wpcli_service in ${_DEMOWP_WORLD_FILE}"
    return 1
  fi

  mkdir -p "${out_dir}"

  echo "Exporting database from ${service} to ${out_file} ..."

  nwdccli run --rm -T --no-deps "${service}" sh -lc "
    tmp='/tmp/${site}.sql'
    rm -f \"\$tmp\"
    wp db export \"\$tmp\" --allow-root >/dev/null
    cat \"\$tmp\"
    rm -f \"\$tmp\"
  " | gzip -c > "${out_file}"

  echo "Done: ${out_file}"
}

nwexportsite() {
  local site="${1:-${DEMOWP_SITE}}"
  _nw_validate_site "${site}" || return 1
  "${_DEMOWP_STACK_DIR}/scripts/export-site.sh" "${DEMOWP_ENV}" "${site}"
}

nwbasicauthset() {
  local site="${1:-${DEMOWP_SITE}}"
  local user="${2:-}"

  _nw_validate_site "${site}" || return 1
  "${_DEMOWP_STACK_DIR}/scripts/set-basic-auth.sh" "${DEMOWP_ENV}" "${site}" "${user}"
}

nwhelp() {
  cat <<EOF
nathabee-lab aliases

Environment and site
  nwenv dev|prod
  nwsite <wordpress-project-from-data/world-list.json>

Compose
  nwup
  nwdown
  nwstop [SERVICE]
  nwps
  nwlogs [SERVICE]
  nwbuild [SERVICE]

Exec
  nwwpexec CMD...
  nwwpcliexec CMD...
  nwdbexec CMD...

WordPress CLI
  nwwp option get home
  nwwp plugin list
  nwwp theme list
  nwwp user list
  nwdbtables

Read files inside container
  nwwpls [PATH]
  nwwptree [PATH]
  nwwpcat /var/www/html/wp-config.php
  nwwpread /var/www/html/.htaccess

Shells
  nwwpshell
  nwwpclishell

Export from runtime back to host data/
  nwexportfiles [SITE]
  nwexportdb [SITE]
  nwexportsite [SITE]

Misc
  nwvolumes
  nwinspectvolume VOLUME_NAME
  nwbasicauthset [SITE] [USERNAME]

Defined wordpress sites
$(_nw_get_sites | sed 's/^/  - /')
EOF
}

echo "nathabee-lab aliases loaded -> env=${DEMOWP_ENV} site=${DEMOWP_SITE}"
if [[ -n "${DEMOWP_COMPOSE_PROJECT_NAME:-}" ]]; then
  echo "Compose project -> ${DEMOWP_COMPOSE_PROJECT_NAME}"
fi
echo "Use nwhelp to list commands."

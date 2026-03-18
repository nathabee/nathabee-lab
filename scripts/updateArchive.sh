#!/bin/bash

set -euo pipefail

ENV_NAME="${1:-}"

ALLOWED_ENVS=("demo_fullstack" "orthopedagogie" "demo_fullstack")

if [[ -z "${ENV_NAME}" ]]; then
  echo "Usage: $0 <environment_name>"
  echo "Allowed values: ${ALLOWED_ENVS[*]}"
  exit 1
fi

if [[ ! " ${ALLOWED_ENVS[*]} " =~ " ${ENV_NAME} " ]]; then
  echo "Error: Unknown environment '${ENV_NAME}'"
  echo "Allowed values: ${ALLOWED_ENVS[*]}"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${PROJECT_ROOT}/data"
DATE="$(date +"%Y%m%d")"

WP_DIR="/var/www/html/${ENV_NAME}"
ARCHIVE_DIR="${DATA_DIR}/${ENV_NAME}"
DB_DIR="${ARCHIVE_DIR}/database"
WPFILE_DIR="${ARCHIVE_DIR}/wpfile"

DB_FILE="${DB_DIR}/${ENV_NAME}.sql"
DB_FILE_GZ="${DB_FILE}.gz"
CONFIG_FILE="${ARCHIVE_DIR}/updateArchive.json"
WP_CONFIG="${WP_DIR}/wp-config.php"

if [[ ! -d "$WP_DIR" ]]; then
  echo "Error: Source WordPress directory does not exist: $WP_DIR"
  exit 1
fi

if [[ ! -f "$WP_CONFIG" ]]; then
  echo "Error: wp-config.php not found in $WP_DIR"
  exit 1
fi

DB_NAME=$(grep DB_NAME "$WP_CONFIG" | cut -d \' -f 4)
DB_USER=$(grep DB_USER "$WP_CONFIG" | cut -d \' -f 4)
DB_PASS=$(grep DB_PASSWORD "$WP_CONFIG" | cut -d \' -f 4)
DB_HOST=$(grep DB_HOST "$WP_CONFIG" | cut -d \' -f 4)
TABLE_PREFIX=$(grep '^\$table_prefix' "$WP_CONFIG" | cut -d \' -f 2)
TABLE_PREFIX="${TABLE_PREFIX:-wp_}"

SITEURL=$(sudo mysql -u"$DB_USER" -p"$DB_PASS" -h"$DB_HOST" "$DB_NAME" -Nse \
  "SELECT option_value FROM ${TABLE_PREFIX}options WHERE option_name='siteurl' LIMIT 1;" 2>/dev/null || true)

HOMEURL=$(sudo mysql -u"$DB_USER" -p"$DB_PASS" -h"$DB_HOST" "$DB_NAME" -Nse \
  "SELECT option_value FROM ${TABLE_PREFIX}options WHERE option_name='home' LIMIT 1;" 2>/dev/null || true)

HAS_BASIC_AUTH="false"
if [[ -f "$WP_DIR/.htaccess" ]] && grep -q '^AuthUserFile ' "$WP_DIR/.htaccess"; then
  HAS_BASIC_AUTH="true"
fi

mkdir -p "$ARCHIVE_DIR"
rm -rf "$DB_DIR" "$WPFILE_DIR"
mkdir -p "$DB_DIR" "$WPFILE_DIR"

echo "Exporting database '${DB_NAME}'..."
mysqldump --no-tablespaces -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$DB_FILE"

if [[ ! -s "$DB_FILE" ]]; then
  echo "Error: SQL dump was created but is empty: $DB_FILE"
  exit 1
fi

echo "Compressing database dump..."
rm -f "$DB_FILE_GZ"
gzip -9 -c "$DB_FILE" > "$DB_FILE_GZ"

if [[ ! -s "$DB_FILE_GZ" ]]; then
  echo "Error: Compressed dump is empty: $DB_FILE_GZ"
  echo "Raw SQL kept at: $DB_FILE"
  exit 1
fi

if ! gzip -t "$DB_FILE_GZ"; then
  echo "Error: gzip verification failed for: $DB_FILE_GZ"
  echo "Raw SQL kept at: $DB_FILE"
  exit 1
fi

rm -f "$DB_FILE"
echo "Compressed dump ready: $DB_FILE_GZ"

echo "Copying WordPress files..."
rsync -av \
  --exclude='wp-config.php' \
  --exclude='.htpasswd' \
  --exclude='wp-content/cache' \
  --exclude='wp-content/upgrade' \
  "$WP_DIR/" "$WPFILE_DIR/"

cat <<EOF > "$CONFIG_FILE"
{
  "project": "${ENV_NAME}",
  "last_backup": "${DATE}",
  "database_dump": "database/${ENV_NAME}.sql.gz",
  "wpfiles": "wpfile/",
  "source_path": "${WP_DIR}",
  "db_name": "${DB_NAME}",
  "db_user": "${DB_USER}",
  "table_prefix": "${TABLE_PREFIX}",
  "original_siteurl": "${SITEURL}",
  "original_home": "${HOMEURL}",
  "has_basic_auth": ${HAS_BASIC_AUTH}
}
EOF

echo "Archive complete for ${ENV_NAME}"
echo "Database: ${DB_FILE_GZ}"
echo "Files: ${WPFILE_DIR}"
echo "No wp-config.php stored in archive."

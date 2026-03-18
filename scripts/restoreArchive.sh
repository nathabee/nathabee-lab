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
ARCHIVE_DIR="${DATA_DIR}/${ENV_NAME}"
CONFIG_FILE="${ARCHIVE_DIR}/updateArchive.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: No config file found for '${ENV_NAME}'"
  exit 1
fi

DB_FILE=$(jq -r .database_dump "$CONFIG_FILE")

echo "Enter name for NEW environment (e.g. orthopedagogie_test):"
read -r NEW_ENV

NEW_WP_DIR="/var/www/html/${NEW_ENV}"
NEW_DB="${NEW_ENV}"

if [[ -d "$NEW_WP_DIR" ]]; then
  echo "Error: Directory $NEW_WP_DIR already exists. Aborting."
  exit 1
fi

if sudo mysql -uroot -e "USE ${NEW_DB}" 2>/dev/null; then
  echo "Error: Database ${NEW_DB} already exists. Aborting."
  exit 1
fi

echo "Creating target WordPress folder..."
sudo mkdir -p "$NEW_WP_DIR"
sudo rsync -av "${ARCHIVE_DIR}/wpfile/" "${NEW_WP_DIR}/"

WP_CONFIG="${NEW_WP_DIR}/wp-config.php"
if [[ ! -f "$WP_CONFIG" ]]; then
  echo "Error: wp-config.php not found in ${NEW_WP_DIR}. Aborting."
  exit 1
fi

echo "Updating DB_NAME in wp-config.php to '${NEW_DB}'..."
sudo sed -i "s/define( *'DB_NAME'.*/define( 'DB_NAME', '${NEW_DB}' );/" "$WP_CONFIG"

echo "Enter the domain name for this site (e.g. nathabee.de):"
read -r WP_BASE_DOMAIN

echo "Extracting DB credentials from updated wp-config.php..."
DB_USER=$(grep DB_USER "$WP_CONFIG" | cut -d\' -f4)
DB_PASS=$(grep DB_PASSWORD "$WP_CONFIG" | cut -d\' -f4)
DB_HOST=$(grep DB_HOST "$WP_CONFIG" | cut -d\' -f4)
TABLE_PREFIX=$(grep '^\$table_prefix' "$WP_CONFIG" | cut -d\' -f2)

echo "Creating new database: ${NEW_DB}"
sudo mysql -uroot -e "CREATE DATABASE \`${NEW_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci"

echo "Granting privileges to '${DB_USER}'@'${DB_HOST}'"
sudo mysql -uroot -e "GRANT ALL PRIVILEGES ON \`${NEW_DB}\`.* TO '${DB_USER}'@'${DB_HOST}'; FLUSH PRIVILEGES;"

echo "Importing database dump..."
if [[ "${DB_FILE}" == *.gz ]]; then
  gunzip -c "${ARCHIVE_DIR}/${DB_FILE}" | sudo mysql -u"${DB_USER}" -p"${DB_PASS}" "${NEW_DB}"
else
  sudo mysql -u"${DB_USER}" -p"${DB_PASS}" "${NEW_DB}" < "${ARCHIVE_DIR}/${DB_FILE}"
fi

sudo mysql -u"${DB_USER}" -p"${DB_PASS}" "${NEW_DB}" <<EOF
UPDATE ${TABLE_PREFIX}options SET option_value = 'https://${WP_BASE_DOMAIN}/${NEW_ENV}' WHERE option_name = 'siteurl';
UPDATE ${TABLE_PREFIX}options SET option_value = 'https://${WP_BASE_DOMAIN}/${NEW_ENV}' WHERE option_name = 'home';
EOF

echo "Setting permissions..."
sudo chown -R www-data:www-data "$NEW_WP_DIR"
sudo find "$NEW_WP_DIR" -type d -exec chmod 755 {} \;
sudo find "$NEW_WP_DIR" -type f -exec chmod 644 {} \;

HTACCESS_PATH="${NEW_WP_DIR}/.htaccess"
HTPASSWD_PATH="${NEW_WP_DIR}/.htpasswd"

if [[ -f "$HTACCESS_PATH" ]]; then
  echo "Updating .htaccess for environment '${NEW_ENV}'..."
  sudo sed -i "s#^AuthUserFile .*#AuthUserFile /var/www/html/${NEW_ENV}/.htpasswd#" "$HTACCESS_PATH"
  sudo sed -i "s#^RewriteBase .*#RewriteBase /${NEW_ENV}/#" "$HTACCESS_PATH"
  sudo sed -i "s#^RewriteRule . /.*index\.php \[L\]#RewriteRule . /${NEW_ENV}/index.php [L]#" "$HTACCESS_PATH"
else
  echo "No .htaccess found. Skipping rewrite updates."
fi

if grep -q "AuthUserFile" "$HTACCESS_PATH" 2>/dev/null; then
  echo "Detected HTTP auth in .htaccess. Recreating .htpasswd..."
  echo "Enter username for HTTP auth:"
  read -r HTUSER
  echo "Enter password for user $HTUSER:"
  read -rs HTPASS
  echo
  sudo htpasswd -cb "$HTPASSWD_PATH" "$HTUSER" "$HTPASS"
  sudo chown www-data:www-data "$HTPASSWD_PATH"
  sudo chmod 640 "$HTPASSWD_PATH"
fi

echo "Restarting Apache..."
sudo a2dismod cache || true
sudo a2dismod cache_disk || true
sudo systemctl restart apache2

echo "Restore complete"
echo "Visit: http://${WP_BASE_DOMAIN}/${NEW_ENV}/"
echo "Admin: http://${WP_BASE_DOMAIN}/${NEW_ENV}/wp-admin/"

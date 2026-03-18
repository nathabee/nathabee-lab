#!/bin/bash

# === Input ===
ENV_NAME="$1"
if [ -z "$ENV_NAME" ]; then
    echo "❌ Usage: $0 <environment_name>"
    exit 1
fi

read -p "🌐 Enter the base domain (e.g. nathabee.de), or leave blank for localhost: " WP_BASE_DOMAIN
if [ -z "$WP_BASE_DOMAIN" ]; then
  SITE_URL="http://localhost/${ENV_NAME}"
else
  SITE_URL="https://${WP_BASE_DOMAIN}/${ENV_NAME}"
fi

# === Credentials ===
DB_NAME="${ENV_NAME}"
DB_USER="${ENV_NAME}_admin"
# Generate the password
DB_PASS=$(< /dev/urandom tr -dc 'A-Za-z0-9_@%+=!#$*' | head -c 20)


WP_DIR="/var/www/html/${ENV_NAME}"
# WP_ARCHIVE="latest.tar.gz"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/downloads"
mkdir -p "$BUILD_DIR"

WP_ARCHIVE="${BUILD_DIR}/wordpress-latest.tar.gz"


# === Check environment existence ===
if [ -d "$WP_DIR" ]; then
    echo "❌ Environment folder already exists: $WP_DIR"
    exit 1
fi

DB_EXISTS=$(sudo mysql -uroot -sse "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${DB_NAME}'")
if [ "$DB_EXISTS" == "$DB_NAME" ]; then
    echo "❌ MySQL database already exists: $DB_NAME"
    exit 1
fi

# === Handle WordPress archive ===
if [ -f "$WP_ARCHIVE" ]; then
    echo "📦 Found existing archive: $WP_ARCHIVE"
    ls -lh "$WP_ARCHIVE"
    read -p "♻️  Reuse this archive? [Y/n]: " REUSE
    if [[ "$REUSE" =~ ^[nN]$ ]]; then
        echo "🌐 Downloading new WordPress..."
        rm -f "$WP_ARCHIVE"
        wget https://wordpress.org/latest.tar.gz
    else
        echo "✅ Reusing existing archive."
    fi
else
    echo "🌐 Downloading WordPress..."
    wget https://wordpress.org/latest.tar.gz
fi

# === Extract WordPress ===
echo "📂 Extracting WordPress to $WP_DIR..."
mkdir -p "$WP_DIR"
tar -xzf "$WP_ARCHIVE" -C "$WP_DIR" --strip-components=1

# === Create MySQL DB ===
echo "🛠️  Creating MySQL database: $DB_NAME"
sudo mysql -uroot -e "CREATE DATABASE \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"

# === Create MySQL user ===
echo "🔐 Creating MySQL user: $DB_USER"
USER_EXISTS=$(sudo mysql -uroot -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = '${DB_USER}');")
if [ "$USER_EXISTS" -eq 1 ]; then
    echo "⚠️  MySQL user already exists: $DB_USER — dropping it..."
    sudo mysql -uroot -e "DROP USER '${DB_USER}'@'localhost';"
fi

# Create the user (note the single quotes around the password)
sudo mysql -uroot -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"

sudo mysql -uroot -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"
sudo mysql -uroot -e "FLUSH PRIVILEGES;"

# === Configure wp-config.php ===
echo "⚙️  Generating wp-config.php..."
cd "$WP_DIR"
cp wp-config-sample.php wp-config.php
sed -i "s/database_name_here/${DB_NAME}/" wp-config.php
sed -i "s/username_here/${DB_USER}/" wp-config.php
sed -i "s/password_here/${DB_PASS}/" wp-config.php

# === Set folder permissions ===
echo "🔐 Setting ownership to www-data..."
sudo chown -R www-data:www-data "$WP_DIR"

# === Install WordPress ===
echo "⚙️  Installing WordPress site via wp-cli..."
sudo -u www-data wp core install \
  --url="${SITE_URL}" \
  --title="${ENV_NAME} Site" \
  --admin_user="${DB_USER}" \
  --admin_password="${DB_PASS}" \
  --admin_email="admin@${WP_BASE_DOMAIN}" \
  --path="$WP_DIR" \
  --skip-email

echo "✅ WordPress environment '$ENV_NAME' created and ready!"
echo "🌐 Access it at: ${SITE_URL}"
echo "🗝️  Admin login: ${DB_USER} / ${DB_PASS}"


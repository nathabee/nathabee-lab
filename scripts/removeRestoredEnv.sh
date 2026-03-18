#!/bin/bash

ALLOWED_ARCHIVES=("nathabee_wordpress" "orthopedagogie" "orthopedagogiedutregor")

echo "💬 Enter the name of the RESTORED ENVIRONMENT to delete (e.g., restored, orthopedagogie_test):"
read -r ENV_NAME

# Prevent deletion of reference environments
if [[ " ${ALLOWED_ARCHIVES[@]} " =~ " ${ENV_NAME} " ]]; then
    echo "❌ Error: '$ENV_NAME' is a protected archive name. Cannot delete."
    exit 1
fi

# Delete WordPress directory
WP_DIR="/var/www/html/${ENV_NAME}"
if [ -d "$WP_DIR" ]; then
    echo "🧹 Deleting WordPress directory: $WP_DIR"
    sudo rm -rf "$WP_DIR"
else
    echo "ℹ️ WordPress directory does not exist: $WP_DIR"
fi

# Confirm and drop MySQL DB
echo "⚠️ WARNING: This will permanently delete the MySQL database '${ENV_NAME}'."
read -p "Are you sure you want to proceed? [y/N]: " CONFIRM
if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
    echo "🧨 Dropping MySQL database: ${ENV_NAME}"
    sudo mysql -uroot -e "DROP DATABASE IF EXISTS \`${ENV_NAME}\`;"
    echo "✅ Database deleted: ${ENV_NAME}"
else
    echo "❌ Cancelled database deletion."
fi

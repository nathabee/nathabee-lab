#!/bin/bash

curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp

sudo apt install php8.2 php8.2-mysql
sudo a2dismod php8.4
sudo a2enmod php8.2
sudo update-alternatives --set php /usr/bin/php8.2
sudo systemctl restart apache2

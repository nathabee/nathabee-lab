# restore-apache.md

# prod only

## target urls

- `https://nathabee.de/` -> `127.0.0.1:18081`
- `https://orthopedagogie.nathabee.de/` -> `127.0.0.1:18082`
- `https://orthopedagogiedutregor.nathabee.de/` -> `127.0.0.1:18083`

## DNS in Hetzner

### IPv4
- `A  @                      -> VPS_IPV4`
- `A  orthopedagogie         -> VPS_IPV4`
- `A  orthopedagogiedutregor -> VPS_IPV4`

### IPv6
- `AAAA  @                      -> VPS_IPV6`
- `AAAA  orthopedagogie         -> VPS_IPV6`
- `AAAA  orthopedagogiedutregor -> VPS_IPV6`

## Hetzner Cloud Firewall

### inbound allow
- `22/tcp`
- `80/tcp`
- `443/tcp`

### outbound
- allow all
- or allow at least:
  - `53/udp`
  - `53/tcp`
  - `80/tcp`
  - `443/tcp`

## prod docker env


```bash
# check if .env is correct, normally this step is done during docker install
cd ~/nathabee-world-prod
cp docker/env.prod.example docker/.env.prod
nano docker/.env.prod
````
 
## install apache + certbot

```bash
sudo apt update
sudo apt install -y apache2 certbot
sudo a2enmod ssl proxy proxy_http headers rewrite
sudo systemctl enable --now apache2
sudo apache2ctl configtest
```

## backend ports check

```bash
sudo ss -tulpn | grep -E '127\.0\.0\.1:(18081|18082|18083)'
curl -I http://127.0.0.1:18081/
curl -I http://127.0.0.1:18082/
curl -I http://127.0.0.1:18083/
```

## ACME webroot

```bash
sudo mkdir -p /var/www/certbot/.well-known/acme-challenge
sudo chown -R www-data:www-data /var/www/certbot
```

## http vhost

```bash
sudo tee /etc/apache2/sites-available/00-acme-redirects.conf >/dev/null <<'APACHE'
<VirtualHost *:80>
    ServerName nathabee.de
    ServerAlias orthopedagogie.nathabee.de orthopedagogiedutregor.nathabee.de

    Alias /.well-known/acme-challenge/ /var/www/certbot/.well-known/acme-challenge/
    <Directory "/var/www/certbot/.well-known/acme-challenge/">
        Options None
        AllowOverride None
        Require all granted
    </Directory>

    RewriteEngine On
    RewriteCond %{REQUEST_URI} !^/\.well-known/acme-challenge/
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]

    ErrorLog  ${APACHE_LOG_DIR}/http-error.log
    CustomLog ${APACHE_LOG_DIR}/http-access.log combined
</VirtualHost>
APACHE
```

```bash
sudo a2ensite 00-acme-redirects.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

## certbot

```bash
sudo certbot certonly --webroot -w /var/www/certbot -d nathabee.de -m admin@nathabee.de --agree-tos --no-eff-email
sudo certbot certonly --webroot -w /var/www/certbot -d orthopedagogie.nathabee.de -m admin@nathabee.de --agree-tos --no-eff-email
sudo certbot certonly --webroot -w /var/www/certbot -d orthopedagogiedutregor.nathabee.de -m admin@nathabee.de --agree-tos --no-eff-email
```

## apache ssl vhosts

```bash
sudo tee /etc/apache2/sites-available/nathabee-ssl.conf >/dev/null <<'APACHE'
<VirtualHost *:443>
    ServerName nathabee.de

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/nathabee.de/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/nathabee.de/privkey.pem
    Include /etc/letsencrypt/options-ssl-apache.conf

    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port  "443"

    ProxyPass        / http://127.0.0.1:18081/ connectiontimeout=5 timeout=60
    ProxyPassReverse / http://127.0.0.1:18081/

    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"

    ErrorLog  ${APACHE_LOG_DIR}/nathabee-ssl-error.log
    CustomLog ${APACHE_LOG_DIR}/nathabee-ssl-access.log combined
</VirtualHost>
APACHE
```

```bash
sudo tee /etc/apache2/sites-available/orthopedagogie-ssl.conf >/dev/null <<'APACHE'
<VirtualHost *:443>
    ServerName orthopedagogie.nathabee.de

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/orthopedagogie.nathabee.de/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/orthopedagogie.nathabee.de/privkey.pem
    Include /etc/letsencrypt/options-ssl-apache.conf

    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port  "443"

    ProxyPass        / http://127.0.0.1:18082/ connectiontimeout=5 timeout=60
    ProxyPassReverse / http://127.0.0.1:18082/

    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"

    ErrorLog  ${APACHE_LOG_DIR}/orthopedagogie-ssl-error.log
    CustomLog ${APACHE_LOG_DIR}/orthopedagogie-ssl-access.log combined
</VirtualHost>
APACHE
```

```bash
sudo tee /etc/apache2/sites-available/orthopedagogiedutregor-ssl.conf >/dev/null <<'APACHE'
<VirtualHost *:443>
    ServerName orthopedagogiedutregor.nathabee.de

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/orthopedagogiedutregor.nathabee.de/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/orthopedagogiedutregor.nathabee.de/privkey.pem
    Include /etc/letsencrypt/options-ssl-apache.conf

    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port  "443"

    ProxyPass        / http://127.0.0.1:18083/ connectiontimeout=5 timeout=60
    ProxyPassReverse / http://127.0.0.1:18083/

    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"

    ErrorLog  ${APACHE_LOG_DIR}/orthopedagogiedutregor-ssl-error.log
    CustomLog ${APACHE_LOG_DIR}/orthopedagogiedutregor-ssl-access.log combined
</VirtualHost>
APACHE
```

## enable sites

```bash
sudo a2dissite 000-default.conf 2>/dev/null || true
sudo a2dissite default-ssl.conf 2>/dev/null || true

sudo a2ensite 00-acme-redirects.conf
sudo a2ensite nathabee-ssl.conf
sudo a2ensite orthopedagogie-ssl.conf
sudo a2ensite orthopedagogiedutregor-ssl.conf

sudo apache2ctl configtest
sudo systemctl reload apache2
```

## cert renew apache reload hook

```bash
sudo install -d /etc/letsencrypt/renewal-hooks/deploy
sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-apache.sh >/dev/null <<'SH'
#!/usr/bin/env bash
systemctl reload apache2
SH
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-apache.sh
```

## checks

```bash
curl -I https://nathabee.de/
curl -I https://orthopedagogie.nathabee.de/
curl -I https://orthopedagogiedutregor.nathabee.de/
```

```bash
sudo apache2ctl configtest
sudo systemctl status apache2 --no-pager
```

```bash
sudo tail -n 100 /var/log/apache2/http-error.log
sudo tail -n 100 /var/log/apache2/nathabee-ssl-error.log
sudo tail -n 100 /var/log/apache2/orthopedagogie-ssl-error.log
sudo tail -n 100 /var/log/apache2/orthopedagogiedutregor-ssl-error.log
```



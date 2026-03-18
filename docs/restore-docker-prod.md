# Docker prod restore

This document describes how to restore archived site data into the Docker **prod** environment.

It is compatible with both Docker storage modes:

- **bind-mount mode**: WordPress files are mounted from the host filesystem
- **named-volume mode**: WordPress files live in Docker-managed storage

The procedure is the same in both cases because the Docker restore scripts work through the container path `/var/www/html` and do not require direct host access to live WordPress files.

## Goal

Restore one or more archived sites into the Docker prod stack and expose them behind the production Apache reverse proxy.

Expected backend ports are:

- `127.0.0.1:18081`
- `127.0.0.1:18082`
- `127.0.0.1:18083`

The public URLs are handled separately by Apache and DNS.

## Supported site names

The currently supported site names are:

- `nathabee_wordpress`
- `orthopedagogie`
- `orthopedagogiedutregor`

## Before you start

You need:

- a fresh or prepared server
- Apache + DNS configured first
- Docker and Docker Compose installed
- a local clone of this repository
- a valid `docker/.env.prod`
- archive data fetched into local `data/`

## Apache and DNS first

Do Apache reverse proxy and DNS setup before restoring the sites.

See:

- `docs/restore-apache.md`

## Install Docker

```bash
sudo apt update
sudo apt install -y ca-certificates curl

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

docker compose version
docker ps
````

## Clone the project

```bash id="7pp0ae"
cd ~
git clone git@github.com:nathabee/nathabee-world.git nathabee-world-prod
cd nathabee-world-prod
```

## Fetch archive data from GitHub releases

Before restore, fetch the wanted archive batch into local `data/`.

```bash id="iiopss"
./scripts/fetch-release.sh --recent
# then fetch the wanted batch:
./scripts/fetch-release.sh <timestamp>

# check fetched archive data
ls -ltr data/*
```

## Create the prod environment file

```bash id="eqf56s"
cp docker/env.prod.example docker/.env.prod

# change passwords, users, ports and final prod URLs
nano docker/.env.prod

chmod 600 docker/.env.prod
chmod +x docker/scripts/*.sh

docker compose --env-file docker/.env.prod -f docker/compose.yaml config >/dev/null
```

## Start the prod stack

```bash id="v7ousr"
./docker/scripts/up.sh prod
```

## Full restore into prod

Restore each site from the fetched archive data.

### Root site

```bash id="fsf1fx"
./docker/scripts/restore-site.sh prod nathabee_wordpress
./docker/scripts/reset-admin-password.sh prod nathabee_wordpress nathabee
```

### Orthopedagogie

```bash id="t9zq9n"
./docker/scripts/restore-site.sh prod orthopedagogie
./docker/scripts/fix-urls.sh prod orthopedagogie
./docker/scripts/reset-admin-password.sh prod orthopedagogie nathabee
```

### Orthopedagogiedutregor

```bash id="lzcrgt"
./docker/scripts/restore-site.sh prod orthopedagogiedutregor
./docker/scripts/fix-urls.sh prod orthopedagogiedutregor
./docker/scripts/reset-admin-password.sh prod orthopedagogiedutregor nathabee
```

## Full restore with one batch command

If you want to restore all three sites in one pass:

```bash id="pbug4j"
cd ~/nathabee-world-prod

./docker/scripts/restore-all.sh prod

./docker/scripts/fix-urls.sh prod orthopedagogie
./docker/scripts/fix-urls.sh prod orthopedagogiedutregor
```

Then reset passwords as needed:

```bash id="tuj6iz"
./docker/scripts/reset-admin-password.sh prod nathabee_wordpress nathabee
./docker/scripts/reset-admin-password.sh prod orthopedagogie nathabee
./docker/scripts/reset-admin-password.sh prod orthopedagogiedutregor nathabee
```

## Refresh only one site in prod

Use this when the prod Docker stack already exists and you only want to refresh one site from a newer archive.

This works for both bind-mount mode and named-volume mode.

### Example: refresh `orthopedagogie`

```bash id="b56h3i"
cd ~/nathabee-world-prod

docker compose --env-file docker/.env.prod -f docker/compose.yaml config >/dev/null

# fetch updated archive data if needed
./scripts/fetch-release.sh <timestamp> orthopedagogie

chmod +x docker/scripts/*.sh

./docker/scripts/restore-site.sh prod orthopedagogie
./docker/scripts/fix-urls.sh prod orthopedagogie
./docker/scripts/reset-admin-password.sh prod orthopedagogie nathabee
```

### Example: refresh `nathabee_wordpress`

```bash id="u4lswr"
cd ~/nathabee-world-prod

docker compose --env-file docker/.env.prod -f docker/compose.yaml config >/dev/null

./scripts/fetch-release.sh <timestamp> nathabee_wordpress

chmod +x docker/scripts/*.sh

./docker/scripts/restore-site.sh prod nathabee_wordpress
./docker/scripts/reset-admin-password.sh prod nathabee_wordpress nathabee
```

### Example: refresh `orthopedagogiedutregor`

```bash id="bb9jlx"
cd ~/nathabee-world-prod

docker compose --env-file docker/.env.prod -f docker/compose.yaml config >/dev/null

./scripts/fetch-release.sh <timestamp> orthopedagogiedutregor

chmod +x docker/scripts/*.sh

./docker/scripts/restore-site.sh prod orthopedagogiedutregor
./docker/scripts/fix-urls.sh prod orthopedagogiedutregor
./docker/scripts/reset-admin-password.sh prod orthopedagogiedutregor nathabee
```

## Why no manual deletion of `docker/runtime/` or Docker volumes is needed

Do not manually delete:

* `docker/runtime/...`
* bind-mounted WordPress directories
* hardcoded Docker volume names

The current Docker restore flow already handles the refresh internally:

* it stages archive files locally
* it starts the required database and WordPress services
* it clears `/var/www/html` through the container path
* it copies the restored files into the live Docker site
* it drops and reimports database tables

That keeps the same workflow valid for both bind mounts and named volumes.

## URL fix step

After restore:

* `nathabee_wordpress` normally does **not** need `fix-urls.sh`
* `orthopedagogie` should run `fix-urls.sh`
* `orthopedagogiedutregor` should run `fix-urls.sh`

Reason: the two sub-sites often still contain old path-based URLs inside content or metadata.

## Basic Auth note for prod

Some old production archives may contain `.htaccess` rules for Apache Basic Auth.

In prod mode, `restore-site.sh` keeps that protection logic if the archive metadata says it existed.

Because `.htpasswd` is intentionally excluded from the archive, the restore script may ask you to create a new `.htpasswd` during restore.

That is expected.

If the archive used Basic Auth and you choose not to recreate it, the prod restore should not continue with incomplete authentication configuration.

## Check backend ports

```bash id="qarfyv"
curl -I http://127.0.0.1:18081/
curl -I http://127.0.0.1:18082/
curl -I http://127.0.0.1:18083/
```

These are backend checks only. Public access still depends on Apache reverse proxy and DNS.

## List users

Use WP-CLI to inspect existing users before resetting passwords if you are not sure which login exists.

```bash id="psuzj8"
docker compose --profile cli --env-file docker/.env.prod -f docker/compose.yaml run --rm --no-deps wpcli_nathabee_wordpress \
  wp --allow-root user list --fields=ID,user_login,user_email,roles

docker compose --profile cli --env-file docker/.env.prod -f docker/compose.yaml run --rm --no-deps wpcli_orthopedagogie \
  wp --allow-root user list --fields=ID,user_login,user_email,roles

docker compose --profile cli --env-file docker/.env.prod -f docker/compose.yaml run --rm --no-deps wpcli_orthopedagogiedutregor \
  wp --allow-root user list --fields=ID,user_login,user_email,roles
```

## Check logs

```bash id="mdrjwm"
docker compose --env-file docker/.env.prod -f docker/compose.yaml logs --tail 100 db_nathabee_wordpress
docker compose --env-file docker/.env.prod -f docker/compose.yaml logs --tail 100 wp_nathabee_wordpress

docker compose --env-file docker/.env.prod -f docker/compose.yaml logs --tail 100 db_orthopedagogie
docker compose --env-file docker/.env.prod -f docker/compose.yaml logs --tail 100 wp_orthopedagogie

docker compose --env-file docker/.env.prod -f docker/compose.yaml logs --tail 100 db_orthopedagogiedutregor
docker compose --env-file docker/.env.prod -f docker/compose.yaml logs --tail 100 wp_orthopedagogiedutregor
```

## Stop the prod environment

```bash id="g0f8jv"
cd ~/nathabee-world-prod
docker compose --env-file docker/.env.prod -f docker/compose.yaml down
```

## Full cleanup of the prod environment

Use this only when you want to completely remove the local Docker prod environment and start again from zero.

```bash id="8owes0"
cd ~/nathabee-world-prod
docker compose --env-file docker/.env.prod -f docker/compose.yaml down --volumes --rmi local
cd ..
rm -rf nathabee-world-prod
```

## Notes

* `data/` must already contain fetched archive content before restore
* `restore-site.sh` is Docker-only and works through the container path
* the same restore procedure is valid for bind-mount mode and named-volume mode
* `wp-config.php` and `.htpasswd` are not part of the archive and are handled separately
* public production access depends on Apache reverse proxy and DNS, not only on Docker backend ports

## Related documentation

* `docs/archive-data.md`
* `docs/archive-data-from-host.md`
* `docs/archive-data-from-docker.md`
* `docs/restore-apache.md`
* `docs/restore-docker-dev.md`
 

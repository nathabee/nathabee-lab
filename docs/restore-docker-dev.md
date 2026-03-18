# Docker dev restore

This document describes how to restore archived production data into the Docker **dev** environment.

It is compatible with both Docker storage modes:

- **bind-mount mode**: WordPress files are mounted from the host filesystem
- **named-volume mode**: WordPress files live in Docker-managed storage

The procedure is the same in both cases because the Docker restore scripts work through the container path `/var/www/html` and do not require direct host access to live WordPress files.

## Goal

Restore one or more archived sites into the local Docker dev stack and make them available on:

- `http://localhost:8081/`
- `http://localhost:8082/`
- `http://localhost:8083/`

## Supported site names

The currently supported site names are:

- `demo_fullstack`
- `orthopedagogie`
- `demo_fullstack`

## Before you start

You need:

- a local clone of this repository
- a valid `docker/.env.dev`
- archive data fetched into local `data/`
- Docker and Docker Compose available

## Full restore into a fresh dev environment

Use this when you want a clean rebuild of the whole Docker dev setup.

```bash
# if env already installed
cd ~/coding/project/docker/test-nathabee-lab
docker compose --env-file docker/.env.dev -f docker/compose.yaml down --volumes --rmi local
cd ..
rm -rf test-nathabee-lab

cd ~/coding/project/docker
git clone git@github.com:nathabee/nathabee-lab.git test-nathabee-lab
cd test-nathabee-lab

./scripts/fetch-release.sh --recent
# EXAMPLE:
# Repository: nathabee/nathabee-lab
# Latest matching release tags:
#
# published_at           environment              stamp              tag
# ---------------------- ------------------------ ------------------ ----------------------------------------------
# 2026-03-15T14:27:58Z   demo_fullstack   20260315-141901    data-demo_fullstack-20260315-141901
# 2026-03-15T14:27:36Z   orthopedagogie           20260315-141901    data-orthopedagogie-20260315-141901
# 2026-03-15T14:27:04Z   demo_fullstack       20260315-141901    data-demo_fullstack-20260315-141901

# fetch one full batch by timestamp
./scripts/fetch-release.sh <timestamp>

# check fetched archive data
ls -ltr data/*

cp docker/env.dev.example docker/.env.dev

# change passwords and users if needed
nano docker/.env.dev

chmod 600 docker/.env.dev
chmod +x docker/scripts/*.sh

docker compose --env-file docker/.env.dev -f docker/compose.yaml config >/dev/null

./docker/scripts/up.sh dev

./docker/scripts/restore-site.sh dev demo_fullstack
./docker/scripts/fix-urls.sh dev demo_fullstack
./docker/scripts/reset-admin-password.sh dev demo_fullstack nathabee

./docker/scripts/restore-site.sh dev orthopedagogie
./docker/scripts/fix-urls.sh dev orthopedagogie
./docker/scripts/reset-admin-password.sh dev orthopedagogie nathabee

./docker/scripts/restore-site.sh dev demo_fullstack
./docker/scripts/fix-urls.sh dev demo_fullstack
./docker/scripts/reset-admin-password.sh dev demo_fullstack nathabee
````

## Full restore into dev with one batch command

If you want to restore all three sites in one pass, you can use:

```bash
cd ~/coding/project/docker/test-nathabee-lab

./docker/scripts/restore-all.sh dev

./docker/scripts/fix-urls.sh dev orthopedagogie
./docker/scripts/fix-urls.sh dev demo_fullstack
```

Then reset passwords as needed:

```bash
./docker/scripts/reset-admin-password.sh dev demo_fullstack nathabee
./docker/scripts/reset-admin-password.sh dev orthopedagogie nathabee
./docker/scripts/reset-admin-password.sh dev demo_fullstack nathabee
```

## Refresh only one site in dev

Use this when the Docker dev stack already exists and you only want to refresh one site from a newer archive.

This works for both bind-mount mode and named-volume mode.

### Example: refresh `orthopedagogie`

```bash
cd ~/coding/project/docker/test-nathabee-lab

docker compose --env-file docker/.env.dev -f docker/compose.yaml config >/dev/null

# fetch updated archive data if needed
./scripts/fetch-release.sh <timestamp> orthopedagogie

chmod +x docker/scripts/*.sh

./docker/scripts/restore-site.sh dev orthopedagogie
./docker/scripts/fix-urls.sh dev orthopedagogie
./docker/scripts/reset-admin-password.sh dev orthopedagogie nathabee
```

### Example: refresh `demo_fullstack`

```bash
cd ~/coding/project/docker/test-nathabee-lab

docker compose --env-file docker/.env.dev -f docker/compose.yaml config >/dev/null

./scripts/fetch-release.sh <timestamp> demo_fullstack

chmod +x docker/scripts/*.sh

./docker/scripts/restore-site.sh dev demo_fullstack
./docker/scripts/reset-admin-password.sh dev demo_fullstack nathabee
```

### Example: refresh `demo_fullstack`

```bash
cd ~/coding/project/docker/test-nathabee-lab

docker compose --env-file docker/.env.dev -f docker/compose.yaml config >/dev/null

./scripts/fetch-release.sh <timestamp> demo_fullstack

chmod +x docker/scripts/*.sh

./docker/scripts/restore-site.sh dev demo_fullstack
./docker/scripts/fix-urls.sh dev demo_fullstack
./docker/scripts/reset-admin-password.sh dev demo_fullstack nathabee
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

* `demo_fullstack` normally does **not** need `fix-urls.sh`
* `orthopedagogie` should run `fix-urls.sh`
* `demo_fullstack` should run `fix-urls.sh`

Reason: the two sub-sites often still contain old path-based URLs inside content or metadata.

## Check backend ports

```bash
curl -I http://127.0.0.1:8081/
curl -I http://127.0.0.1:8082/
curl -I http://127.0.0.1:8083/
```

Expected result is an HTTP response from each local site.

## List users

Use WP-CLI to inspect existing users before resetting passwords if you are not sure which login exists.

```bash
docker compose --profile cli --env-file docker/.env.dev -f docker/compose.yaml run --rm --no-deps wpcli_demo_fullstack \
  wp --allow-root user list --fields=ID,user_login,user_email,roles

docker compose --profile cli --env-file docker/.env.dev -f docker/compose.yaml run --rm --no-deps wpcli_orthopedagogie \
  wp --allow-root user list --fields=ID,user_login,user_email,roles

docker compose --profile cli --env-file docker/.env.dev -f docker/compose.yaml run --rm --no-deps wpcli_demo_fullstack \
  wp --allow-root user list --fields=ID,user_login,user_email,roles
```

## Stop the dev environment

```bash
cd ~/coding/project/docker/test-nathabee-lab
docker compose --env-file docker/.env.dev -f docker/compose.yaml down
```

## Full cleanup of the dev environment

Use this only when you want to completely remove the local Docker dev environment and start again from zero.

```bash
cd ~/coding/project/docker/test-nathabee-lab
docker compose --env-file docker/.env.dev -f docker/compose.yaml down --volumes --rmi local
cd ..
rm -rf test-nathabee-lab
```

## Notes

* `data/` must already contain fetched archive content before restore
* `restore-site.sh` is Docker-only and works through the container path
* the same restore procedure is valid for bind-mount mode and named-volume mode
* `wp-config.php` and `.htpasswd` are not part of the archive and are handled separately
* in dev mode, legacy Apache Basic Auth from old production archives is disabled during restore

## Related documentation

* `docs/archive-data.md`
* `docs/archive-data-from-host.md`
* `docs/archive-data-from-docker.md`
* `docs/restore-docker-prod.md`



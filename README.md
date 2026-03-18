# nathabee-world

Private infrastructure repository for Nathabee WordPress archive, release, restore, and Docker migration workflows.

This repository contains the project code, documentation, and operational scripts used to:

- export archives from existing host-installed WordPress sites
- export archives from running Docker-based WordPress sites
- package archive data as GitHub release assets
- fetch archive data back from GitHub releases
- restore sites into Docker-based environments
- prepare the migration from legacy Apache host installs to Dockerized production

## Current status

The project is in a migration phase between two architectures.

At the moment:

- production export from the old host-based Apache layout is still supported
- Docker-based restore workflows are in use for dev and future production
- Docker-based archive export is supported
- archive data is no longer meant to live in Git history
- archive data is intended to be packaged and published as GitHub release assets
- the Docker stack is split into one Compose file per site
- site inventory is described in `data/world-list.json`

## Repository structure

```text
.
├── README.md
├── TODO.md
├── .gitignore
├── data/
│   ├── world-list.json
│   ├── nathabee_wordpress/
│   ├── orthopedagogie/
│   └── orthopedagogiedutregor/
├── docs/
│   ├── archive-data-from-docker.md
│   ├── archive-data-from-host.md
│   ├── archive-data.md
│   ├── docker-cmd.md
│   ├── password-dev.md
│   ├── prerequise.md
│   ├── restore-apache.md
│   ├── restore-docker-dev.md
│   └── restore-docker-prod.md
├── scripts/
│   ├── createEmptyEnv.sh
│   ├── fetch-release.sh
│   ├── installWpCli.sh
│   ├── release-all.sh
│   ├── release-project.sh
│   ├── removeRestoredEnv.sh
│   ├── resetArchive.sh
│   ├── restoreArchive.sh
│   ├── updateAllArchive.sh
│   └── updateArchive.sh
└── docker/
    ├── README.md
    ├── compose.yaml
    ├── env.dev.example
    ├── env.prod.example
    ├── runtime/
    ├── sites/
    │   ├── nathabee_wordpress/
    │   │   └── compose.yaml
    │   ├── orthopedagogie/
    │   │   └── compose.yaml
    │   └── orthopedagogiedutregor/
    │       └── compose.yaml
    └── scripts/
        ├── alias.sh
        ├── down.sh
        ├── export-all.sh
        ├── export-site.sh
        ├── fix-urls.sh
        ├── reset-admin-password.sh
        ├── restore-all.sh
        ├── restore-site.sh
        └── up.sh
````

## Directory roles

### `data/`

Local working directory for generated archive content such as:

* database dumps
* exported WordPress files
* archive metadata

This directory also contains `world-list.json`, which describes the known projects handled by the Docker scripts.

Generated archive content should not be committed to Git.

### `data/world-list.json`

Project inventory used by the Docker project-aware scripts.

This file describes:

* project name
* project type
* whether the project is active
* storage mode
* Docker service names
* env variable names used by the scripts

The goal is to avoid hardcoding project names in the Docker management scripts.

### `scripts/`

Host-oriented archive and release tooling.

These scripts are used for:

* legacy host-based archive export
* release packaging
* release fetching
* legacy host restore helpers

### `docker/`

Docker stack and Docker-specific tooling used for:

* Docker startup and shutdown
* Docker archive export
* Docker archive restore
* WordPress management inside Docker

### `docker/sites/`

Per-project Docker Compose files.

Each WordPress project has its own Compose file under:

```text
docker/sites/<project>/compose.yaml
```

The root `docker/compose.yaml` includes those project files.

### `docs/`

Project documentation for:

* archive workflow
* host export workflow
* Docker export workflow
* Apache restore notes
* Docker dev and prod restore workflows

## Docker architecture

The Docker stack is split into:

* one root Compose file: `docker/compose.yaml`
* one Compose file per site: `docker/sites/<project>/compose.yaml`

This keeps each project isolated and prepares the repository for cleaner future project creation.

The root Compose file remains the standard entrypoint for commands such as:

```bash
docker compose --env-file docker/.env.dev -f docker/compose.yaml config
docker compose --env-file docker/.env.dev -f docker/compose.yaml up -d
```

## Storage model

Docker WordPress projects may use different file storage modes at the same time.

Supported modes are:

* bind mounts
* named Docker volumes

This means one site may use a bind-mounted runtime directory while another uses a named volume.

The Docker archive export and restore scripts are designed to work with both modes, as long as:

* the `wp_*` service and the matching `wpcli_*` service mount the same `/var/www/html`
* the project metadata in `world-list.json` matches the Compose service names

## Environment files

Example environment files are provided here:

* `docker/env.dev.example`
* `docker/env.prod.example`

Typical setup:

```bash
cp docker/env.dev.example docker/.env.dev
cp docker/env.prod.example docker/.env.prod
chmod 600 docker/.env.dev docker/.env.prod
```

The environment files define:

* ports
* site URLs
* database names and credentials
* image names
* WordPress file mount definitions such as `*_WP_FILES_MOUNT`

## Archive format

Both host-based export and Docker-based export must produce the same archive structure:

```text
data/<site>/
├── database/
│   └── <site>.sql.gz
├── wpfile/
└── updateArchive.json
```

Notes:

* `wp-config.php` is intentionally excluded
* `.htpasswd` is intentionally excluded
* `updateArchive.json` stores export metadata such as table prefix, original URLs, and Basic Auth detection

## Workflow overview

The project supports two export sources and one common release transport layer.

### 1. Export from host-based WordPress

Used while production or legacy environments still run directly on Apache and `/var/www/html/...`.

Typical commands:

```bash
./scripts/updateArchive.sh orthopedagogie
./scripts/updateAllArchive.sh
```

See:

* `docs/archive-data-from-host.md`

### 2. Export from Docker-based WordPress

Used when WordPress sites run in Docker.

Typical commands:

```bash
./docker/scripts/export-site.sh dev orthopedagogie
./docker/scripts/export-all.sh dev
```

Or via sourced aliases:

```bash
source docker/scripts/alias.sh dev
nwexportsite orthopedagogie
```

See:

* `docs/archive-data-from-docker.md`

### 3. Package archive data as GitHub release assets

Archive data is packaged from local `data/` and published as GitHub release assets.

Typical commands:

```bash
./scripts/release-project.sh orthopedagogie
./scripts/release-all.sh
```

### 4. Fetch archive data back from GitHub releases

To restore on another machine, archive data must first be fetched back into local `data/`.

Typical commands:

```bash
./scripts/fetch-release.sh --recent-stamps
./scripts/fetch-release.sh 20260315-101530
./scripts/fetch-release.sh 20260315-101530 orthopedagogie
```

### 5. Restore into Docker

Once archive data has been fetched into local `data/`, it can be restored into Docker dev or prod environments.

Typical commands:

```bash
./docker/scripts/restore-site.sh dev orthopedagogie
./docker/scripts/restore-all.sh dev
```

See:

* `docs/restore-docker-dev.md`
* `docs/restore-docker-prod.md`

## Host export scripts

These scripts are for classic host-installed WordPress environments.

### `scripts/updateArchive.sh`

Create or refresh one local archive from an existing host-installed WordPress environment.

Example:

```bash
./scripts/updateArchive.sh orthopedagogie
```

### `scripts/updateAllArchive.sh`

Refresh all known local archives in one run.

Example:

```bash
./scripts/updateAllArchive.sh
```

## Docker export scripts

These scripts are for Docker-based WordPress environments.

They should work regardless of whether Docker stores WordPress files using:

* bind mounts
* named Docker volumes

### `docker/scripts/export-site.sh`

Export one Docker-based site into local `data/<site>/`.

The project is resolved through `data/world-list.json`.

Example:

```bash
./docker/scripts/export-site.sh dev orthopedagogie
```

### `docker/scripts/export-all.sh`

Export all active WordPress projects listed in `data/world-list.json`.

Example:

```bash
./docker/scripts/export-all.sh dev
```

## Release scripts

### `scripts/release-project.sh`

Package one site archive from `data/<site>/` and publish it as a GitHub release asset.

Example:

```bash
./scripts/release-project.sh orthopedagogie
```

### `scripts/release-all.sh`

Package all known site archives using one shared batch timestamp.

Example:

```bash
./scripts/release-all.sh
```

## Docker restore scripts

### `docker/scripts/restore-site.sh`

Restore one fetched archive from local `data/<site>/` into the selected Docker environment.

The project is resolved through `data/world-list.json`.

Example:

```bash
./docker/scripts/restore-site.sh dev orthopedagogie
```

### `docker/scripts/restore-all.sh`

Restore all active WordPress projects listed in `data/world-list.json` into the selected Docker environment.

Example:

```bash
./docker/scripts/restore-all.sh dev
```

## Docker helper scripts

### `docker/scripts/up.sh`

Start the Docker stack for the selected environment.

Example:

```bash
./docker/scripts/up.sh dev
```

### `docker/scripts/down.sh`

Stop the Docker stack for the selected environment.

Example:

```bash
./docker/scripts/down.sh dev
```

### `docker/scripts/fix-urls.sh`

Run WordPress search-replace inside one Docker project to rewrite old archive URLs to the target environment URL.

Example:

```bash
./docker/scripts/fix-urls.sh dev orthopedagogie
```

### `docker/scripts/reset-admin-password.sh`

Reset a WordPress user password in one Docker project.

Example:

```bash
./docker/scripts/reset-admin-password.sh dev orthopedagogie nathabee
```

### `docker/scripts/alias.sh`

Load helper aliases for Docker project management.

Example:

```bash
source docker/scripts/alias.sh dev
nwhelp
```

## Current migration direction

The migration path is:

1. keep host export support while legacy production still exists
2. package archives as GitHub release assets
3. fetch those archives into another machine or environment
4. restore into Docker for dev and future production
5. later use Docker-native export as the standard archive source

## Documentation

### Archive workflow

* `docs/archive-data.md`
* `docs/archive-data-from-host.md`
* `docs/archive-data-from-docker.md`

### Restore workflow

* `docs/restore-apache.md`
* `docs/restore-docker-dev.md`
* `docs/restore-docker-prod.md`

### Docker helper notes

* `docs/docker-cmd.md`
* `docs/password-dev.md`

## GitHub SSH setup on this server

This server uses GitHub SSH over port `443`.

### Create a key

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
cat ~/.ssh/id_ed25519.pub
```

Add the public key in GitHub:

* Settings
* SSH and GPG keys
* New SSH key

### Force GitHub SSH over port 443

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh

cat > ~/.ssh/config <<'EOF'
Host github.com
    Hostname ssh.github.com
    Port 443
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
EOF

chmod 600 ~/.ssh/config
```

### Test SSH

```bash
ssh -T git@github.com
```

Expected result:

```text
Hi <github-user>! You've successfully authenticated, but GitHub does not provide shell access.
```

### Set repo remote to SSH

```bash
git remote set-url origin git@github.com:nathabee/nathabee-world.git
git remote -v
```

## Git commands

### Clone

```bash
git clone git@github.com:nathabee/nathabee-world.git
cd nathabee-world
```

### Pull

```bash
git pull origin main
```

### Push

```bash
git add .
git commit -m "Describe your change"
git push origin main
```

## Important notes

* `data/` is local working storage, not tracked source content
* generated SQL dumps and copied WordPress files should stay out of Git history
* release archives are the intended transport format for site data
* host export and Docker export must both produce the same archive structure
* Docker file storage may use either bind mounts or named volumes, but the archive format must remain identical
* Docker project-aware scripts now use `data/world-list.json` instead of hardcoded project names

## TODO

See `TODO.md`.

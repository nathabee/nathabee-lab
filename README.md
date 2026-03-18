# nathabee-lab

Public lab repository for generic WordPress and fullstack Docker workflows.

This repository contains code, scripts, and documentation used to:

- create and manage Docker-based WordPress projects
- restore project data from GitHub release assets
- export project data from running environments
- package project data as GitHub release assets
- support migration from legacy host installs to Docker
- provide public demo examples such as `demo-wordpress` and `demo-fullstack`

## Current status

The project is in transition from a private migration setup to a public generic lab.

At the moment:

- legacy host export support still exists
- Docker-based restore workflows are supported
- Docker-based archive export is supported
- archive data is not meant to live in Git history
- archive data is intended to be transported through GitHub release assets
- project inventory is described in `data/world-list.json`
- code and docs stay generic
- release examples may contain demo content, but are not source of truth for the repository code

## Repository structure

```text
.
├── README.md
├── TODO.md
├── .gitignore
├── data/
│   ├── world-list.json
│   └── .gitkeep
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
│   ├── fetch-release.sh 
│   ├── release-all.sh
│   ├── release-project.sh  
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
    │   └── <project>/
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

Local working directory for generated project data such as:

* database dumps
* exported WordPress files
* archive metadata

This directory also contains `world-list.json`, which describes the known projects handled by the Docker scripts.

Generated project data should not be committed to Git.

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

Each project has its own Compose file under:

```text
docker/sites/<project>/compose.yaml
```

The root `docker/compose.yaml` includes those project files.

### `docs/`

Project documentation for:

* archive workflow
* host export workflow
* Docker export workflow
* Docker restore workflows
* Apache migration notes

## Docker architecture

The Docker stack is split into:

* one root Compose file: `docker/compose.yaml`
* one Compose file per project: `docker/sites/<project>/compose.yaml`

This keeps each project isolated and prepares the repository for cleaner future project creation.

Typical commands:

```bash
docker compose --env-file docker/.env.dev -f docker/compose.yaml config
docker compose --env-file docker/.env.dev -f docker/compose.yaml up -d
```

## Storage model

Docker WordPress projects may use different file storage modes at the same time.

Supported modes are:

* bind mounts
* named Docker volumes

The Docker export and restore scripts are designed to work with both modes, as long as:

* the `wp_*` service and matching `wpcli_*` service mount the same `/var/www/html`
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

The environment files define values such as:

* ports
* site URLs
* database names and credentials
* image names
* WordPress file mount definitions

## Archive format

Both host-based export and Docker-based export should produce the same archive structure:

```text
data/<project>/
├── database/
│   └── <project>.sql.gz
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

Used for legacy environments that still run directly on Apache and `/var/www/html/...`.

Typical commands:

```bash
./scripts/updateArchive.sh <project>
./scripts/updateAllArchive.sh
```

### 2. Export from Docker-based WordPress

Used when WordPress sites run in Docker.

Typical commands:

```bash
./docker/scripts/export-site.sh dev <project>
./docker/scripts/export-all.sh dev
```

Or via sourced aliases:

```bash
source docker/scripts/alias.sh dev
nwexportsite <project>
```

### 3. Package archive data as GitHub release assets

Archive data is packaged from local `data/` and published as GitHub release assets.

Typical commands:

```bash
./scripts/release-project.sh <project>
./scripts/release-all.sh
```

### 4. Fetch archive data back from GitHub releases

To restore on another machine, archive data must first be fetched back into local `data/`.

Typical commands:

```bash
./scripts/fetch-release.sh --recent-stamps
./scripts/fetch-release.sh <stamp>
./scripts/fetch-release.sh <stamp> <project>
```

### 5. Restore into Docker

Once archive data has been fetched into local `data/`, it can be restored into Docker dev or prod environments.

Typical commands:

```bash
./docker/scripts/restore-site.sh dev <project>
./docker/scripts/restore-all.sh dev
```

## Demo release examples

The repository may ship or document public demo release examples such as:

* `demo-wordpress`
* `demo-fullstack`

These examples are only example payloads for restore and workflow testing.

They are not source of truth for the repository code or scripts.

## Git commands

### Clone

```bash
git clone git@github.com:nathabee/nathabee-lab.git
cd nathabee-lab
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
* release archives are the intended transport format for project data
* host export and Docker export should produce the same archive structure
* Docker file storage may use either bind mounts or named volumes
* Docker project-aware scripts use `data/world-list.json` instead of hardcoded project names
* code and docs remain generic even when release examples contain demo content

## Documentation

See `docs/` and `TODO.md`.
 
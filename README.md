# nathabee-lab

Public lab repository for generic Docker workflows around WordPress and WordPress + Django projects.

This repository is the script and documentation layer for:

- creating Docker-based projects
- bootstrapping WordPress and Django runtimes
- exporting live runtime data back into `data/`
- packaging project archives as release assets
- fetching release archives back into local working data
- restoring projects into Docker environments
- keeping project definitions generic and project-aware

The active direction of the repository is Docker-native workflow. Legacy host-mode scripts still exist for older environments, but they are no longer the main path.

---

## What this repository manages

`nathabee-lab` is built around one central idea:

- runtime data lives in Docker
- archive data lives in `data/<project>/`
- release packages are built from `data/<project>/`
- project definitions are driven by metadata instead of hardcoded project names

The repository supports two project types:

- `wordpress`
- `fullstack`

A fullstack project means:

- WordPress
- Django application code
- Django database export / restore

---

## Current capabilities

The repository currently supports:

- project registration with per-project Compose generation
- WordPress bootstrap
- Django bootstrap
- Docker stack start / stop
- export of WordPress-only projects
- export of fullstack projects
- restore of WordPress-only projects
- restore of fullstack projects
- project deletion / deactivation
- project reactivation
- release packaging from local archive data
- release fetching back into local archive data

Status at a glance:

- core Docker workflow exists
- project creation is usable
- WordPress bootstrap is usable
- Django bootstrap is usable
- export / restore flows exist for both WordPress and fullstack projects
- some multi-project and fullstack scenarios still need more real-world validation

---

## Repository structure

```text
.
├── README.md
├── TODO.md
├── build/
│   └── releases/
├── data/
│   ├── <project>/
│   │   ├── database/
│   │   ├── django/            # fullstack only
│   │   ├── updateArchive.json
│   │   └── wpfile/
│   └── world-list.json
├── docker/
│   ├── compose.yaml
│   ├── env.dev.example
│   ├── env.prod.example
│   ├── README.md
│   ├── runtime/
│   ├── scripts/
│   └── sites/
│       └── <project>/
│           └── compose.yaml
├── docs/
│   ├── archive-data-from-docker.md
│   ├── archive-data-from-host.md
│   ├── archive-data.md
│   ├── create-new-wordpress-project.md
│   ├── operating-manual.md
│   ├── password-dev.md
│   ├── prerequise.md
│   ├── restore-apache.md
│   ├── restore-docker-dev.md
│   └── restore-docker-prod.md
└── scripts/
    ├── fetch-release.sh
    ├── release-all.sh
    ├── release-project.sh 
```

---

## Core concepts

### 1. Project inventory

The repository uses `data/world-list.json` as project inventory.

That file is the central metadata source for project-aware scripts. It describes things such as:

* project name
* project type
* active / inactive status
* storage mode
* service naming
* generated environment variable prefixes

The goal is to keep automation generic and avoid hardcoding project-specific behavior into the scripts.

### 2. Runtime, archive, and release are different things

There are three distinct layers:

#### Runtime

Live files and databases used by Docker containers.

Examples:

* `docker/runtime/<project>/` for bind-mounted WordPress
* `docker/runtime/<project>_django/` for Django runtime
* Docker named volumes for volume-based WordPress storage
* container databases

#### Archive

Portable project data stored in `data/<project>/`.

This is the canonical export / restore format used by the repository.

#### Release package

A tarball built from `data/<project>/` and stored under `build/releases/` before publication or transport.

The correct lifecycle is:

1. export runtime into `data/`
2. package `data/` as a release artifact
3. fetch / unpack when needed
4. restore from `data/` back into Docker

### 3. Storage modes for WordPress

WordPress projects can use either:

* `bind`
* `volume`

#### Bind mode

WordPress files are stored in a host directory such as:

```text
docker/runtime/<project>/
```

This is convenient for development and direct inspection.

#### Volume mode

WordPress files are stored in a Docker-managed named volume.

This is cleaner from the host filesystem point of view and still exports to the same archive format.

Important: storage mode affects runtime implementation, but it must not change the archive structure in `data/<project>/`.

### 4. Fullstack model

A fullstack project extends the WordPress archive model with Django code and Django database export.

Expected fullstack archive shape:

```text
data/<project>/
├── database/
│   ├── <project>.sql.gz
│   └── <project>_django.sql.gz
├── django/
├── updateArchive.json
└── wpfile/
```

---

## Important directories

### `data/`

Local working directory for project archive data.

It contains:

* WordPress files
* database dumps
* Django code snapshots for fullstack projects
* archive metadata
* project inventory in `world-list.json`

Generated project data should stay out of Git history.

### `docker/`

Docker stack, generated project Compose includes, runtime directories, and Docker-oriented helper scripts.

### `docker/sites/<project>/compose.yaml`

Per-project Compose definition generated by project creation.

The root `docker/compose.yaml` includes these project files.

### `docker/runtime/`

Local runtime tree used for bind-mounted projects and Django runtime staging.

This is runtime state, not source of truth.

### `scripts/`

Repository-level release and fetch tooling.

This is where release packaging and release retrieval live.


---

## Main scripts

### Project creation and bootstrap

```bash
./docker/scripts/create-project.sh
./docker/scripts/bootstrap-wordpress.sh
./docker/scripts/bootstrap-django.sh
```

### Docker lifecycle

```bash
./docker/scripts/up.sh
./docker/scripts/down.sh
./docker/scripts/activate-project.sh
./docker/scripts/delete-project.sh
```

### Export / archive

```bash
./docker/scripts/export-site.sh
./docker/scripts/export-fullstack.sh
./docker/scripts/export-all.sh
```

### Restore

```bash
./docker/scripts/restore-site.sh
./docker/scripts/restore-fullstack.sh
./docker/scripts/restore-all.sh
```

### Release transport

```bash
./scripts/release-project.sh
./scripts/release-all.sh
./scripts/fetch-release.sh
```

---

## Quick start

Clone the repository:

```bash
git clone git@github.com:nathabee/nathabee-lab.git
cd nathabee-lab
```

Create local environment files:

```bash
cp docker/env.dev.example docker/.env.dev
cp docker/env.prod.example docker/.env.prod
chmod 600 docker/.env.dev docker/.env.prod
chmod +x docker/scripts/*.sh
chmod +x scripts/*.sh
```

Validate the Compose configuration:

```bash
docker compose --env-file docker/.env.dev -f docker/compose.yaml config --services
```

Start the development stack:

```bash
./docker/scripts/up.sh dev
```

---

## Typical workflows

## Create a new project

Register the project structure first, then bootstrap the runtime.

Example:

```bash
./docker/scripts/create-project.sh \
  --type wordpress \
  --name demo_wordpress \
  --description "Demo WordPress" \
  --code DEMOWP \
  --storage bind \
  --dev-port 8085 \
  --prod-port 18085 \
  --dev-url http://localhost:8085/ \
  --prod-url https://demo-wordpress.example.test/
```

Then bootstrap WordPress:

```bash
./docker/scripts/bootstrap-wordpress.sh \
  dev demo_wordpress \
  --title "Demo WordPress" \
  --admin-user beelab \
  --admin-email you@example.com \
  --table-prefix demowp_
```

For fullstack projects, bootstrap Django separately after the project definition and Django code are in place.

## Export a live project back into archive data

WordPress-only:

```bash
./docker/scripts/export-site.sh dev demo_wordpress
```

Fullstack:

```bash
./docker/scripts/export-fullstack.sh dev demo_fullstack
```

This updates `data/<project>/` from the live Docker runtime.

## Package a release

```bash
./scripts/release-project.sh demo_fullstack
```

or:

```bash
./scripts/release-all.sh
```

Release packaging always works from `data/<project>/`, not directly from live runtime.

## Fetch and restore a release

Fetch archive data back into local `data/`:

```bash
./scripts/fetch-release.sh --recent
```

Then restore it into Docker:

```bash
./docker/scripts/restore-site.sh dev demo_wordpress
```

or:

```bash
./docker/scripts/restore-fullstack.sh dev demo_fullstack
```

## Delete and later reactivate a project

Delete / deactivate:

```bash
./docker/scripts/delete-project.sh dev demo_fullstack
```

Reactivate and restore later:

```bash
./docker/scripts/activate-project.sh demo_fullstack
./docker/scripts/restore-fullstack.sh dev demo_fullstack
```

---

## Archive format

WordPress archive format:

```text
data/<project>/
├── database/
│   └── <project>.sql.gz
├── updateArchive.json
└── wpfile/
```

Fullstack archive format:

```text
data/<project>/
├── database/
│   ├── <project>.sql.gz
│   └── <project>_django.sql.gz
├── django/
├── updateArchive.json
└── wpfile/
```

Notes:

* `wp-config.php` should not be treated as portable archive content
* `.htpasswd` should not be treated as portable archive content
* `updateArchive.json` stores archive metadata used by export / restore logic

---

## Documentation map

Start here depending on the task:

* `docs/operating-manual.md`
  Full Docker workflow for create, export, restore, delete, and release packaging

* `docs/create-new-wordpress-project.md`
  Project creation and bootstrap flow

* `docs/restore-docker-dev.md`
  Restore into Docker development environment

* `docs/restore-docker-prod.md`
  Restore into Docker production environment

* `docs/archive-data-from-docker.md`
  Docker-based export model

* `docs/archive-data-from-host.md`
  Legacy host-based export model

* `docker/README.md`
  Docker-specific notes

---

## Current boundaries

This repository is not a generic PaaS and not a full deployment platform.

It is currently a script-driven lab for:

* project-aware Docker management
* archive export / restore
* release-based transport of project data
* repeatable WordPress and Django bootstrap workflows

It is intentionally built around explicit scripts and explicit archive formats.

---


## Planned direction

The next logical layer is automation around the existing scripts, not replacement of them.

That means any future orchestration layer should call the repository workflows rather than redefine them.

The source of truth should remain:

* the repository scripts
* the project inventory
* the archive format
* the documentation


---
## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
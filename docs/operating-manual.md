# Operating Manual

This document describes the current Docker workflow for project creation, export, restore, deletion, and release packaging.

This guide is still new and not fully tested in all scenarios.

## Related guides

### Create and initialize a project

For creating a new WordPress or fullstack project, see:

- [create-new-wordpress-project.md]

### Restore a project from an archive

If you already have an archive stored in a release, see:

- [restore-docker-dev.md]
- [restore-docker-prod.md]

---

## Project structure

### WordPress project

For a project named `<myproject>`, you need:

- an entry in `data/world-list.json`
- the project set as active when it should be included in Docker
- `data/<myproject>/wpfile`
- `data/<myproject>/database`

When restoring, the site data is sent either:

- into `docker/runtime/...` when the project uses bind mounts
- or into Docker-managed volumes when the project uses `volume` storage

### Fullstack project

A fullstack project needs the same WordPress archive structure, plus:

- `data/<myproject>/django`

That Django directory should contain the delivered Django project, for example:

- `manage.py`
- application packages
- config
- requirements files

For a fullstack archive to be complete, the Django database must also be exported.

---

## Create a project

Project creation and bootstrap currently use:

```bash
./docker/scripts/create-project.sh
./docker/scripts/bootstrap-wordpress.sh
./docker/scripts/bootstrap-django.sh
````

These scripts create the project definition and initialize the runtime.

Status:

* project creation: tested
* WordPress bootstrap: tested
* Django bootstrap: tested

---

## Start and stop the Docker stack

After sourcing aliases:

```bash
source docker/scripts/alias.sh dev
```

Use:

```bash
./docker/scripts/up.sh dev
./docker/scripts/down.sh dev
```

or for production:

```bash
./docker/scripts/up.sh prod
./docker/scripts/down.sh prod
```

Notes:

* these scripts operate on the active projects included in `docker/compose.yaml`
* multi-compose behavior still needs more testing
* fullstack behavior still needs more testing

---

## Delete a Docker project

Example:

```bash
source docker/scripts/alias.sh dev

./docker/scripts/delete-project.sh dev demo_fullstack
```

Without export prompt:

```bash
./docker/scripts/delete-project.sh prod demo_fullstack --yes --no-export
```

What `delete-project.sh` does:

* optionally exports the current WordPress runtime back into `data/<project>` first
* stops only that project
* removes that project’s Docker volumes
* removes that project’s bind-mounted runtime directories
* marks the project inactive in `data/world-list.json`
* comments out that project include in `docker/compose.yaml`

What it does **not** delete:

* `data/<project>`
* `docker/sites/<project>`
* env definitions already created for that project

Important:

* for fullstack projects, the Django database must be exported before deletion if you want a complete backup
* WordPress export is integrated
* Django archive/restore must be handled with the fullstack scripts

Status:

* not fully tested yet

---

## Export / archive a project

### Export all active projects

```bash
./docker/scripts/export-all.sh dev
```

or:

```bash
./docker/scripts/export-all.sh prod
```

### Export a WordPress-only project

```bash
./docker/scripts/export-site.sh dev demo_wordpress
```

### Export a fullstack project

```bash
./docker/scripts/export-fullstack.sh dev demo_fullstack
```

What the export scripts do:

### `export-site.sh`

Exports:

* WordPress files into `data/<project>/wpfile`
* WordPress database into `data/<project>/database/<project>.sql.gz`
* archive metadata into `data/<project>/updateArchive.json`

### `export-fullstack.sh`

Exports:

* the WordPress part using `export-site.sh`
* Django runtime code back into `data/<project>/django`
* Django PostgreSQL database into `data/<project>/database/<project>_django.sql.gz`
* Django archive metadata into `data/<project>/updateArchive.json`

A fullstack archive is only complete if it contains:

```text
data/<project>/
├── database/
│   ├── <project>.sql.gz
│   └── <project>_django.sql.gz
├── django/
├── updateArchive.json
└── wpfile/
```

Status:

* WordPress export: available
* fullstack export: available
* still needs more testing in real multi-project usage

---

## Create a project release

Release packaging works from the contents of `data/<project>`.

### Release one project

```bash
./scripts/release-project.sh demo_fullstack
```

### Release all releasable projects

```bash
./scripts/release-all.sh
```

Notes:

* the release tarball contains the whole `data/<project>` directory
* for fullstack projects, no extra release logic is needed as long as `data/<project>` already contains:

  * WordPress files
  * WordPress DB dump
  * Django code
  * Django DB dump
  * `updateArchive.json`

So the correct order is:

1. export the live project into `data/`
2. create the release from `data/`

---

## Fetch a project release

Example:

```bash
./scripts/fetch-release.sh --recent
```

Then choose the project name and release timestamp as required by the fetch script.

Status:

* not fully tested yet
* fullstack fetch/restore workflow still needs more validation

---

## Restore flows

## Case 1 — Restore a WordPress-only project from archive

Use this when the project already exists in Docker and is active.

```bash
./docker/scripts/restore-site.sh dev demo_wordpress
```

Typical full flow:

```bash
./docker/scripts/export-site.sh dev demo_wordpress
./scripts/release-project.sh demo_wordpress

# later: fetch/unpack release

./docker/scripts/restore-site.sh dev demo_wordpress
```

---

## Case 2 — Restore a fullstack project from archive

```bash
./docker/scripts/export-fullstack.sh dev demo_fullstack
./scripts/release-project.sh demo_fullstack

# later: fetch/unpack release

./docker/scripts/restore-fullstack.sh dev demo_fullstack
```

---

## Case 3 — Restore after a project was deleted

This covers the case a was deleted with :
```bash
source docker/scripts/alias.sh dev
./docker/scripts/delete-project.sh dev demo_fullstack


``` 
If the project definition still exists in:

* `docker/sites/<project>`
* `data/world-list.json`
* env files

then reactivate it first, then restore it.

Example for fullstack:

```bash
./docker/scripts/activate-project.sh demo_fullstack
./docker/scripts/restore-fullstack.sh dev demo_fullstack
```

Example for WordPress-only:

```bash
./docker/scripts/activate-project.sh demo_wordpress
./docker/scripts/restore-site.sh dev demo_wordpress
```

---

## Case 4 — Fresh rebuild instead of restore

Use this when you want a clean new install instead of restoring archived data.

Example for fullstack:

```bash
./docker/scripts/activate-project.sh demo_fullstack
./docker/scripts/bootstrap-wordpress.sh dev demo_fullstack \
  --title "Demo" \
  --admin-user nathabee \
  --admin-email you@example.com

./docker/scripts/bootstrap-django.sh dev demo_fullstack
```

Example for WordPress-only:

```bash
./docker/scripts/activate-project.sh demo_wordpress
./docker/scripts/bootstrap-wordpress.sh dev demo_wordpress \
  --title "Demo WordPress" \
  --admin-user nathabee \
  --admin-email you@example.com
```

---

## Practical release workflow

### WordPress-only

```bash
./docker/scripts/export-site.sh dev demo_wordpress
./scripts/release-project.sh demo_wordpress

# later: fetch/unpack release

./docker/scripts/restore-site.sh dev demo_wordpress
```

### Fullstack

```bash
./docker/scripts/export-fullstack.sh dev demo_fullstack
./scripts/release-project.sh demo_fullstack

# later: fetch/unpack release

./docker/scripts/activate-project.sh demo_fullstack
./docker/scripts/restore-fullstack.sh dev demo_fullstack
```

---

## Command list

After sourcing:

```bash
source docker/scripts/alias.sh dev
```

### Switch site

```bash
nwsite orthopedagogie
```

### List files inside the container runtime

```bash
nwwpls
nwwptree /var/www/html/wp-content
```

### Read a file

```bash
nwwpread /var/www/html/.htaccess
```

### Run WP-CLI

```bash
nwwp option get home
nwwp plugin list
```

### Export the live Docker WordPress site back into `data/`

```bash
nwexportsite orthopedagogie
```

This is the bridge between runtime and archive:

* files live inside Docker
* you can inspect them
* you can export them back into `data/<site>/...`
* then `release-all.sh` or `release-project.sh` can publish those updated assets again

---

## Legacy scripts

The old host-mode scripts such as:

* `updateArchive.sh`
* `updateAllArchive.sh`
* `restoreArchive.sh`

are now considered legacy / obsolete for the Docker workflow.

They may still be useful for older host-based environments, but they are no longer the main path for Docker projects.

The current Docker-native workflow should use:

* `export-site.sh`
* `export-fullstack.sh`
* `restore-site.sh`
* `restore-fullstack.sh`
* `release-project.sh`
* `release-all.sh`
 
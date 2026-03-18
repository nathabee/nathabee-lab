# Archive data workflow

This project separates:

- source code and documentation in Git
- generated WordPress archive data in local `data/`
- published archive packages in GitHub release assets

The goal is simple:

- export a WordPress site into a stable archive format
- keep that archive out of Git history
- publish it as a GitHub release asset
- fetch it later for restore into another environment

## Purpose of `data/`

The `data/` directory is local working storage for generated archive content.

It is not the source of truth for project code and should not be committed as normal project content.

Typical uses:

- store a fresh database dump
- store copied WordPress files
- store archive metadata before packaging a release
- receive fetched release data before restore

Typical structure:

```text
data/
├── .gitkeep
├── demo_fullstack/
├── orthopedagogie/
└── demo_fullstack/
````

## Supported archive names

The currently supported site archive names are:

* `demo_fullstack`
* `orthopedagogie`
* `demo_fullstack`

## Archive structure

Each local site archive uses the same structure:

```text
data/<site>/
├── database/
│   └── <site>.sql.gz
├── wpfile/
└── updateArchive.json
```

Notes:

* the final stored database dump is `.sql.gz`
* raw `.sql` files are temporary working files only
* `wp-config.php` is intentionally excluded
* `.htpasswd` is intentionally excluded
* `updateArchive.json` stores export metadata

## What is excluded

The archive intentionally does not include some machine-specific or sensitive files.

Excluded files include:

* `wp-config.php`
* `.htpasswd`

Reason:

* `wp-config.php` contains environment-specific database credentials and runtime configuration
* `.htpasswd` contains access control data that should not be transported as normal archive content

These files must be recreated or handled separately during restore.

## Metadata purpose

Each archive contains an `updateArchive.json` file.

This file stores export metadata such as:

* archive environment name
* database dump path
* table prefix
* original `siteurl`
* original `home`
* whether Apache Basic Auth was detected

This metadata helps restore scripts adapt the archive correctly for the target environment.

## Release workflow

Archive data is no longer meant to live in Git history.

Instead, the workflow is:

1. generate local archive data in `data/`
2. package that archive data into release assets
3. publish those assets as GitHub releases
4. later fetch those assets back into local `data/` when needed

The release scripts are:

* `scripts/release-project.sh`
* `scripts/release-all.sh`

### `scripts/release-project.sh`

Package one site archive from `data/<site>/` and publish it as a GitHub release asset.

Example:

```bash
./scripts/release-project.sh orthopedagogie
```

This creates:

* a tag like `data-orthopedagogie-YYYYMMDD-HHMMSS`
* a release asset like `data-orthopedagogie-YYYYMMDD-HHMMSS.tar.gz`

### `scripts/release-all.sh`

Package all known site archives using one shared batch timestamp.

Example:

```bash
./scripts/release-all.sh
```

This typically creates up to three release tags:

* `data-demo_fullstack-YYYYMMDD-HHMMSS`
* `data-orthopedagogie-YYYYMMDD-HHMMSS`
* `data-demo_fullstack-YYYYMMDD-HHMMSS`

## Fetch workflow

To restore on another machine, archive data must first be fetched back from GitHub releases.

The fetch script is:

* `scripts/fetch-release.sh`

Examples:

```bash
./scripts/fetch-release.sh --recent-stamps
./scripts/fetch-release.sh --list 20260315-101530
./scripts/fetch-release.sh 20260315-101530
./scripts/fetch-release.sh 20260315-101530 orthopedagogie
```

Typical use:

1. inspect recent release batches
2. choose a batch timestamp
3. fetch matching archive data into local `data/`
4. continue with the appropriate restore workflow

## Related documentation

This document is intentionally high-level.

For archive generation details, see:

* `docs/archive-data-from-host.md`
* `docs/archive-data-from-docker.md`

For restore workflows, see:

* `docs/restore-docker-dev.md`
* `docs/restore-docker-prod.md`



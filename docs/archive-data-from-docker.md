# Archive data export from Docker-based WordPress

This document describes archive export from WordPress sites running in Docker.

The goal is the same as host-based export:

- rebuild the standard archive structure in local `data/`
- keep generated archive data out of Git history
- package and publish the archive with the release scripts

## Purpose

Docker export must always produce the same archive structure:

```text
data/<site>/
├── database/
│   └── <site>.sql.gz
├── wpfile/
└── updateArchive.json
````

That is true regardless of how WordPress files are stored inside Docker.

## Supported scripts

Docker export uses:

* `docker/scripts/export-site.sh`
* `docker/scripts/export-all.sh`

These scripts are the Docker-native counterpart of the legacy host export scripts.

## Supported site names

The currently supported archive names are:

* `nathabee_wordpress`
* `orthopedagogie`
* `orthopedagogiedutregor`

## Docker storage modes

Docker WordPress files can be stored in two ways.

### Named-volume mode

Recommended default.

Example:

```yaml
volumes:
  - wp_nathabee_wordpress_data:/var/www/html
```

In this mode, WordPress files live inside Docker-managed storage and are not directly exposed as normal host files.

### Bind-mount mode

Optional development mode.

Example:

```yaml
volumes:
  - ./runtime/nathabee_wordpress/wp:/var/www/html
```

In this mode, WordPress files are visible directly on the host filesystem.

## Important rule

Both storage modes are still Docker deployments.

The Docker export commands should support both modes and must produce the same archive format in `data/<site>/`.

The difference is internal implementation only. The export result must stay identical.

## `docker/scripts/export-site.sh`

Export one Docker-based WordPress site into local archive data.

Example:

```bash
./docker/scripts/export-site.sh dev orthopedagogie
```

Typical responsibilities:

* read the live WordPress files from the Docker site
* export the database from the Docker database service or WP-CLI container
* write the compressed SQL dump to `data/<site>/database/<site>.sql.gz`
* copy WordPress files to `data/<site>/wpfile/`
* exclude `wp-config.php`
* exclude `.htpasswd`
* write `data/<site>/updateArchive.json`

The script should work whether the site uses:

* a bind mount
* a named Docker volume

## `docker/scripts/export-all.sh`

Export all supported Docker-based sites in one run.

Example:

```bash
./docker/scripts/export-all.sh dev
```

This is the batch equivalent of `export-site.sh`.

## Typical Docker export workflow

From the project root:

```bash
source docker/scripts/alias.sh dev

nwexportsite nathabee_wordpress
nwexportsite orthopedagogie
nwexportsite orthopedagogiedutregor
```

Or with dedicated export scripts:

```bash
./docker/scripts/export-site.sh dev nathabee_wordpress
./docker/scripts/export-site.sh dev orthopedagogie
./docker/scripts/export-site.sh dev orthopedagogiedutregor
```

Then package and publish:

```bash
./scripts/release-all.sh
```

## Expected result

After export, each site should have:

```text
data/<site>/
├── database/
│   └── <site>.sql.gz
├── wpfile/
└── updateArchive.json
```

## Notes about implementation

The archive format must stay stable even if Docker storage changes.

That means:

* bind-mount mode and named-volume mode should not change the structure of `data/<site>/`
* release packaging should not care how Docker stored the files
* restore workflows should consume the same archive format either way

## Related documentation

* `docs/archive-data.md`
* `docs/archive-data-from-host.md`
* `docs/restore-docker-dev.md`
* `docs/restore-docker-prod.md`

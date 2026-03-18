# Archive data export from host-based WordPress

This document describes archive export from a classic host-installed WordPress environment.

This is the legacy export workflow used when WordPress files live directly on the server filesystem and MySQL is available on the host.

Typical assumptions for this mode:

- WordPress files live on the host in `/var/www/html/<env>`
- MySQL is available on the host
- Apache is managed on the host

This is different from Docker-based export.

## Purpose

The host export scripts generate local archive data in:

```text
data/<site>/
├── database/
│   └── <site>.sql.gz
├── wpfile/
└── updateArchive.json
````

That local archive can then be packaged and published as a GitHub release asset.

## Supported scripts

Host export uses:

* `scripts/updateArchive.sh`
* `scripts/updateAllArchive.sh`

## Supported site names

The currently supported archive names are:

* `nathabee_wordpress`
* `orthopedagogie`
* `orthopedagogiedutregor`

## `scripts/updateArchive.sh`

Create or refresh one local archive from an existing host-installed WordPress environment.

Example:

```bash
./scripts/updateArchive.sh orthopedagogie
```

This script typically does the following:

* reads database credentials from `/var/www/html/<env>/wp-config.php`
* exports the database
* compresses the SQL dump to `.sql.gz`
* copies WordPress files into `data/<env>/wpfile/`
* excludes `wp-config.php`
* excludes `.htpasswd`
* detects whether Apache Basic Auth is used
* writes `data/<env>/updateArchive.json`

The result is one refreshed local archive in `data/<env>/`.

## `scripts/updateAllArchive.sh`

Refresh all known local archives in one run.

Example:

```bash
./scripts/updateAllArchive.sh
```

This is the normal batch command when all host-installed sites should be archived together.

## Typical host export workflow

From the project root:

```bash
./scripts/updateAllArchive.sh
./scripts/release-all.sh
```

Or for one site only:

```bash
./scripts/updateArchive.sh orthopedagogie
./scripts/release-project.sh orthopedagogie
```

## Output

After a successful run, the expected result is:

```text
data/<site>/
├── database/
│   └── <site>.sql.gz
├── wpfile/
└── updateArchive.json
```

## Important notes

* these scripts are for host-installed WordPress only
* they assume direct host filesystem access
* they assume host MySQL access
* they are not the correct scripts for Docker-based export

For Docker-based export, use the Docker archive workflow instead.

## Related documentation

* `docs/archive-data.md`
* `docs/archive-data-from-docker.md`

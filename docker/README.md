# docker

Docker stack used to restore and test archived WordPress sites from `../data`.

## Goal

This Docker setup is used to:

- recreate archived WordPress sites safely for testing
- keep dev and prod close to each other
- restore from `../data/<site>`
- validate the archives before final production setup

## Directory structure

```text
docker/
├── README.md
├── compose.yaml
├── env.dev.example
├── env.prod.example
├── runtime/
└── scripts/
````

## Environment files

Create local env files from the examples:

```bash
cp docker/env.dev.example docker/.env.dev
cp docker/env.prod.example docker/.env.prod
chmod 600 docker/.env.dev docker/.env.prod
```

## Start the stack

### Dev

```bash
./docker/scripts/up.sh dev
```

### Prod

```bash
./docker/scripts/up.sh prod
```

## Stop the stack

### Dev

```bash
./docker/scripts/down.sh dev
```

### Prod

```bash
./docker/scripts/down.sh prod
```

## Restore one site from `../data`

Examples:

```bash
./docker/scripts/restore-site.sh dev nathabee_wordpress
./docker/scripts/restore-site.sh dev orthopedagogie
./docker/scripts/restore-site.sh dev orthopedagogiedutregor
```

## Restore all sites

### Dev

```bash
./docker/scripts/restore-all.sh dev
```

### Prod

```bash
./docker/scripts/restore-all.sh prod
```

## Data source

The Docker restore scripts read from:

* `../data/<site>/wpfile/`
* `../data/<site>/database/<site>.sql`
* or `../data/<site>/database/<site>.sql.gz`

## Important note about SQL dumps

If only `.sql.gz` exists, the restore script should support importing it directly.

If not, recreate the raw SQL first:

```bash
gunzip -k data/nathabee_wordpress/database/nathabee_wordpress.sql.gz
```

## Runtime data

Restored container runtime files are placed in:

```text
docker/runtime/
```

This directory is ignored by Git.

## Security baseline

This Docker stack should be treated as a controlled restore/test environment, not as a magic security barrier.

Important points:

* a container is not automatically isolated from the outside world
* published ports are reachable according to Docker port bindings
* containers usually still have outbound network access unless restricted
* databases should not publish ports publicly
* WordPress should ideally be exposed only through localhost or a reverse proxy

## Current status

This Docker part is the active direction of the project.

The older scripts in `../data/` still target host-installed WordPress.

## Planned next step

Add Docker-native archive update/export scripts so archives can later be refreshed directly from containerized WordPress environments.


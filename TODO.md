## Migration roadmap for `nathabee-world`

### DONE: Phase 1 — Export from the current production architecture

Current production is still the old layout:

* `https://nathabee.de/`
* `https://nathabee.de/orthopedagogie`
* likely also the old path-based `orthopedagogiedutregor` setup

This means the archive/export scripts must still work against the current non-Docker production install.

Tasks:

* fix all archive scripts after the move from `data/*.sh` to `scripts/*.sh`
* keep export logic compatible with old path-based production URLs
* verify export from old Apache/`/var/www/html/...` layout
* confirm database dumps are valid and compressed
* confirm `wp-config.php` is excluded
* confirm `.htpasswd` is excluded
* detect whether each site uses Apache Basic Auth and store that info in `updateArchive.json`
* verify exported `siteurl` and `home` values are captured correctly from the old production sites

### DONE : Phase 2 — Publish archive data as GitHub release assets

Data should no longer live in Git history.

Tasks:

* finalize `scripts/release-project.sh`
* finalize `scripts/release-all.sh`
* package each project from `data/<project>/`
* create one release tag per project and timestamp
* upload archives as GitHub release assets
* verify local build artifacts stay ignored from Git
* document the release workflow in `docs/archive-data.md`

### DONE : Phase 3 — Restore from GitHub releases into Docker

This replaces the old “restore from tracked `data/`” flow.

Tasks:

* create script to download a release asset from GitHub
* extract release archive into working area
* restore database into Dockerized WordPress/MariaDB environment
* restore WordPress files into Docker volume/container
* adapt restore logic from old path-based URLs to new Docker/subdomain architecture
* handle URL rewriting during restore
* handle optional Basic Auth recreation if archive metadata says it was used
* document the full restore process for Docker production

### TO BE TESTED Phase 4 — Switch production to Dockerized architecture

After export and restore workflow are stable, production can move.

Tasks:

* prepare Docker production environment
* prepare reverse proxy / Apache mapping for:

  * `https://nathabee.de/`
  * `https://orthopedagogie.nathabee.de/`
  * `https://orthopedagogiedutregor.nathabee.de/`
* restore sites into Docker
* verify login, media, permalinks, plugins, and themes
* add useful shell aliases for production Docker management
* document start/stop/update/backup commands
* plan cutover and rollback procedure

### TO BE TESTED Phase 5 — Export back out of running Docker containers

Once Docker is the source of truth, export must no longer assume direct filesystem access.

Tasks:

* create scripts to export archives from running Docker WordPress containers
* extract WordPress files via `docker compose exec` / `docker cp` / tar streaming
* export database dumps from containerized DB service
* rebuild `data/<project>/database` and `data/<project>/wpfile`
* continue excluding `wp-config.php` and `.htpasswd`
* verify whether any site uses `.htpasswd` / Apache Basic Auth
* update `updateArchive.json` from Docker-based sources
* verify resulting archive structure stays identical to release packaging expectations

### TO BE TESTED Phase 6 - mix container and mounted bind in docker, define ins world-list.json 

 
### TO DO Phase 7 - create empty docker wordpress automatically

* add inside the world-list.json
* create an empty wordpress


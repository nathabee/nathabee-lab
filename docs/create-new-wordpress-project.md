# Create a New Docker WordPress Project

This document explains how to create a new empty WordPress project in the `nathabee-lab` Docker architecture.

A new project is created in two phases:

1. register the project structure and Docker configuration
2. bootstrap WordPress inside the new Docker project

This separation is intentional:

- `create-project.sh` prepares the project definition and Docker structure
- `bootstrap-wordpress.sh` installs WordPress into that new project
- `bootstrap-django.sh` installs django into that new project



## Preconditions

Before creating a new project, make sure:

- the repository is cloned
- Docker is installed and working


## create a project : init env and yaml

### Example of a "Wordpress" project creation

Create a new project named `demo_wordpress`:
 
```bash
rm docker/sites/demo_wordpress/compose.yaml

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

check the env (prod dev  ), data/world-list.json and new site/*/compose.yaml


### Example of a "fullstack" project creation

 

Create a new project named `demo_fullstack`:
 
```bash
rm docker/sites/demo_fullstack/compose.yaml
./docker/scripts/create-project.sh \
  --type fullstack \
  --name demo_fullstack \
  --description "Demo fullstack project" \
  --code DEMOFS \
  --storage volume \
  --dev-port 8086 \
  --prod-port 18086 \
  --django-dev-port 8096 \
  --django-prod-port 18096 \
  --dev-url http://localhost:8086/ \
  --prod-url https://demo-fullstack.example.test/


```

### create yaml

after the project creation 
- the Docker env example files exist
- the current split Compose structure is already in place

Typical setup:

```bash

docker compose --profile cli --env-file docker/.env.dev -f docker/compose.yaml config --services

cp docker/env.dev.example docker/.env.dev
cp docker/env.prod.example docker/.env.prod
chmod 600 docker/.env.dev docker/.env.prod
chmod +x docker/scripts/*.sh
```
 

check the env (prod dev  ), data/world-list.json and new site/*/compose.yaml

## init a project with empty data

in case you want to start with a new project total empty 

### init wordpress in a <myproject> project
Then bootstrap WordPress in the dev environment:


if  <myproject>  = demo_wordpress

```bash
./docker/scripts/bootstrap-wordpress.sh \
  dev demo_wordpress \
  --title "Demo WordPress" \
  --admin-user beelab \
  --admin-email you@example.com \
  --table-prefix demowp_
```
Note the password of administrator admin-user , in the example user beelab
Check :
http://localhost:8085/ 
in prod create apache configuration

   
  Same was we bootsrap wordpress if the project  <myproject>  is fullstack: 
Then bootstrap WordPress in the dev environment:

if  <myproject>  = demo_fullstack

```bash
./docker/scripts/bootstrap-wordpress.sh \
  dev demo_fullstack \
  --title "Demo Fullstack WordPress" \
  --admin-user beelab \
  --admin-email you@example.com \
  --table-prefix demofs_
```

### init django in a <myproject> project
Then bootstrap Django in the dev environment:
```bash
./docker/scripts/bootstrap-django.sh \
....to be defined script does not exist 
```
Note the password of administrator admin-user , in the example user beelab
Check :
http://localhost:8084/ 
in prod create apache configuration


## initialise a project with data 

if we want to init a project with data

## wordpress

### you can add use the UI
to add
- plugin
- theme

### if project in in bind mount mode, do in runtime the change you want

### restore 
use restore-site.sh and the doc




install the file from another repository inside ""

copy the django data inside the project




## restore a project from backup

when a project has a backup and is restored, we will use the documentation "restore-docker-*.md"
To DO


## fullstack project creation with github ref

example creating the fullstack beefont project (wordpress plugin + django backend)

### create the yaml and updated env

```bash
rm docker/sites/beefont/compose.yaml
./docker/scripts/create-project.sh \
  --type fullstack \
  --name beefont \
  --description "Beefont project" \
  --code BEEFONT \
  --storage bind \
  --dev-port 8087 \
  --prod-port 18087 \
  --django-dev-port 8097 \
  --django-prod-port 18097 \
  --dev-url http://localhost:8087/ \
  --prod-url https://demo-fullstack.example.test/

# Note check the .env.eaymple files before copying, do not delete active .env

cp docker/env.dev.example docker/.env.dev
cp docker/env.prod.example docker/.env.prod
chmod 600 docker/.env.dev docker/.env.prod
chmod +x docker/scripts/*.sh


docker compose --profile cli --env-file docker/.env.dev -f docker/compose.yaml config --services


./docker/scripts/bootstrap-wordpress.sh \
  dev demo_beefont \
  --title "Beefont WordPress" \
  --admin-user beelab \
  --admin-email you@example.com \
  --table-prefix beefont_

# note login and password at the end of the shell
``` 
### add the plugin

open http://localhost:8087/wp-admin  (login and password before)
create a template fullsize
add beefont to this template
change the beefont setting to be http://localhost:8096/api/

normally beefont appears in the menu on top of the page
if you click the link it opens the beefont page with sidebar menu and login, and the home page
clicking on the login still does not work because you still have not installed the django backend

### add the django code

let say we want to initialise the demo_fullsstack project with django code from beefont

```bash
cd ~/coding/github/nathabee-lab

mkdir -p data/delivery
git clone git@github.com:nathabee/beefont.git data/delivery/beefont

mkdir -p data/demo_fullstack/django
rsync -av --delete data/delivery/beefont/django/ data/demo_fullstack/django/



mkdir -p docker/runtime/demo_fullstack_django
rsync -av --delete data/demo_fullstack/django/ docker/runtime/demo_fullstack_django/


./docker/scripts/bootstrap-django.sh dev demo_fullstack --seed-command seed_beefont
docker compose --env-file docker/.env.dev -f docker/compose.yaml exec django_demo_fullstack \
  /django/.venv/bin/python manage.py loaddata BeeFontCore/fixtures/initial_beefont_languages.json

docker compose --env-file docker/.env.dev -f docker/compose.yaml exec django_demo_fullstack \
  /django/.venv/bin/python manage.py loaddata BeeFontCore/fixtures/initial_beefont_templates.json

docker compose --env-file docker/.env.dev -f docker/compose.yaml exec django_demo_fullstack \
  /django/.venv/bin/python manage.py seed_beefont --mode=copy
docker compose --env-file docker/.env.dev -f docker/compose.yaml exec django_demo_fullstack \
  /django/.venv/bin/python manage.py loaddata BeeFontCore/fixtures/initial_beefont_palettes.json

``` 


```bash
#DEBUG IN DEV ONLY...this is just for my test env 
rsync -av --delete ~/coding/github/beefont/django/ data/demo_fullstack/django/
sudo rm -rf docker/runtime/demo_fullstack_django
mkdir -p docker/runtime/demo_fullstack_django
rsync -av --delete data/demo_fullstack/django/ docker/runtime/demo_fullstack_django/
# prov solution : add a .env.dev + yaml with env var that read it
cp docker/.env.dev.fullstack_django_tmp data/demo_fullstack/django/.env.dev


./docker/scripts/bootstrap-django.sh dev demo_fullstack  --seed-command seed_beefont

docker compose --env-file docker/.env.dev -f docker/compose.yaml exec django_demo_fullstack \
  /django/.venv/bin/python manage.py loaddata BeeFontCore/fixtures/initial_beefont_languages.json

docker compose --env-file docker/.env.dev -f docker/compose.yaml exec django_demo_fullstack \
  /django/.venv/bin/python manage.py loaddata BeeFontCore/fixtures/initial_beefont_templates.json

docker compose --env-file docker/.env.dev -f docker/compose.yaml exec django_demo_fullstack \
  /django/.venv/bin/python manage.py seed_beefont --mode=copy

docker compose --env-file docker/.env.dev -f docker/compose.yaml exec django_demo_fullstack \
  /django/.venv/bin/python manage.py loaddata BeeFontCore/fixtures/initial_beefont_palettes.json

# END
``` 



## scripts presentation
### What `create-project.sh` does

This script registers a new Docker WordPress project in the repository.

It will:

* create the project entry in `data/world-list.json`
* create `docker/sites/<project>/compose.yaml`
* append the new site include to `docker/compose.yaml`
* append env placeholders to:

  * `docker/env.dev.example`
  * `docker/env.prod.example`
  * `docker/.env.dev` if it already exists
  * `docker/.env.prod` if it already exists
* create:

  * `data/<project>/database/`
  * `data/<project>/wpfile/`
* create `docker/runtime/<project>/` only for bind-mounted projects

It does **not** install WordPress.

That is handled by `bootstrap-wordpress.sh`.

### What `bootstrap-wordpress.sh` does

This script bootstraps WordPress inside the already-registered Docker project.

It will:

* start `db_<project>` and `wp_<project>`
* wait until the database is healthy
* wait until WordPress runtime files exist
* check whether WordPress is already installed
* apply the chosen table prefix to `wp-config.php`
* run `wp core install`
* create the admin user
* force `siteurl` and `home` to the target environment URL

If WordPress is already installed, the script stops cleanly without reinstalling it.

### What `bootstrap-django.sh` does

This script bootstraps Django inside the already-registered Docker project.

It will: 

1. read project config from `world-list.json`
2. verify project is `fullstack`
3. verify `data/<project>/django/manage.py` exists
4. prepare `docker/runtime/<project>_django/`
5. copy or sync `data/<project>/django/` -> `docker/runtime/<project>_django/`
6. start Django DB service
7. wait for PostgreSQL
8. verify `/django/manage.py` in container
9. create `.venv`
10. install requirements
11. run migrations
12. optionally run seed command
13. start Django service

### Storage

### Data
The django model is:
* `data/<project>/django` = delivered snapshot/package
* `docker/runtime/<project>_django` = working runtime tree used by container
* `bootstrap-django.sh` = copy from data to runtime, then initialize Django


The wordpress modele depend on the storage mode.
data contains the exported data or the data to be restored
 * `data/<project>/database` == delivered snapshot/package
 * `data/<project>/wpfile` == delivered snapshot/package
 
 data are stored depending on the storage mode:
 `docker/runtime/<project>` or in docker datafile

### Storage modes

A new WORDPRESS project can use either of these storage modes:

* `bind`
* `volume`

note : this parameter is ignored for django (files are alwysa bindmounted and db is named volume)

#### Bind-mounted project

Use:

```bash
--storage bind
```

This creates a runtime directory such as:

```text
docker/runtime/beeschool/
```

and stores WordPress files there through a bind mount.

#### Named-volume project

Use:

```bash
--storage volume
```

This uses a Docker named volume for WordPress files and does not create a local runtime directory.

## Important arguments

### `create-project.sh`

Required arguments:

* `--name`
* `--description`
* `--code`
* `--storage`
* `--dev-port`
* `--prod-port`

Optional arguments:

* `--dev-url`
* `--prod-url`
* `--db-name`
* `--db-user`
* `--bind-path`
* `--active`

### `bootstrap-wordpress.sh`

Required arguments:

* environment: `dev` or `prod`
* project name
* `--title`
* `--admin-user`
* `--admin-email`

Optional arguments:

* `--admin-password`
* `--locale`
* `--table-prefix`

## Naming rules

### Project name

The project name must use only:

* lowercase letters
* digits
* underscore

Example:

```text
beeschool
my_client_site
```

### Env code

The env code must use only:

* uppercase letters
* digits
* underscore

Example:

```text
BEESCHOOL
MYCLIENT
```

This code is used to generate env variable names such as:

```text
BEESCHOOL_PORT
BEESCHOOL_SITE_URL
BEESCHOOL_DB_NAME
BEESCHOOL_DB_USER
BEESCHOOL_DB_PASSWORD
BEESCHOOL_DB_ROOT_PASSWORD
BEESCHOOL_WP_FILES_MOUNT
```

## Resulting files

For the example project `beeschool`, the first script creates:

```text
docker/sites/beeschool/compose.yaml
data/beeschool/database/
data/beeschool/wpfile/
docker/runtime/beeschool/        # only for bind mode
```

It also updates:

```text
data/world-list.json
docker/compose.yaml
docker/env.dev.example
docker/env.prod.example
docker/.env.dev                  # if present
docker/.env.prod                 # if present
```

## Recommended test flow in dev

After creating the project, run these checks:

### 1. Validate Docker Compose

```bash
docker compose --env-file docker/.env.dev -f docker/compose.yaml config --services
```

Make sure the new services appear:

```text
db_beeschool
wp_beeschool
wpcli_beeschool
```

### 2. Start the dev stack

```bash
./docker/scripts/up.sh dev
```

### 3. Bootstrap WordPress

```bash
./docker/scripts/bootstrap-wordpress.sh \
  dev beeschool \
  --title "Bee School" \
  --admin-user nathabee \
  --admin-email you@example.com \
  --table-prefix beeschool_
```

### 4. Open the site

For the example above:

```text
http://localhost:8084/
```

## Example with a named volume

```bash
./docker/scripts/create-project.sh \
  --name myclient \
  --description "Client WordPress" \
  --code MYCLIENT \
  --storage volume \
  --dev-port 8085 \
  --prod-port 18085 \
  --dev-url http://localhost:8085/ \
  --prod-url https://myclient.example.com/
```

Then:

```bash
./docker/scripts/bootstrap-wordpress.sh \
  dev myclient \
  --title "My Client" \
  --admin-user admin \
  --admin-email admin@example.com \
  --table-prefix myclient_
```

## Notes

* `create-project.sh` prepares the repository and Docker structure
* `bootstrap-wordpress.sh` performs the actual WordPress installation
* archive export and restore are separate workflows and are not part of project creation
* bind-mounted and named-volume projects can coexist in the same Docker stack
* the project inventory is driven by `data/world-list.json`

## Scripts used

### `docker/scripts/create-project.sh`

Purpose:

* register a new Docker WordPress project
* generate the Compose site file
* update env files
* update project inventory
* create initial project directories

### `docker/scripts/bootstrap-wordpress.sh`

Purpose:

* start the new project services
* wait for readiness
* install WordPress
* create the admin account
* finalize site configuration
 

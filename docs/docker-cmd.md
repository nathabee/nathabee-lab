
## 3. How you use it

After sourcing:

```bash
source docker/scripts/alias.sh dev
```

Switch site:

```bash
nwsite orthopedagogie
```

List files inside the container volume:

```bash
nwwpls
nwwptree /var/www/html/wp-content
```

Read a file:

```bash
nwwpread /var/www/html/.htaccess
```

Run WP-CLI:

```bash
nwwp option get home
nwwp plugin list
```

Export the live Docker site back into `data/`:

```bash
nwexportsite orthopedagogie
```

That is the bridge you asked for:

* files live inside Docker
* you can still inspect them
* you can still export them back to `data/<site>/...`
* then `release-all.sh` can publish new assets again

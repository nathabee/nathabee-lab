## map nathabee-lab

key rules : 

``` 
Code and docs stay generic.
Only release examples may contain demo content.
No external project becomes source of truth for `nathabee-lab`.
```


### stage 1 — clean rename and public cleanup

- rename visible `nathabee-world` references to `nathabee-lab`
- remove references to the private repository
- keep `WORLD_FILE` and `world-list.json`
- remove tracked private site names from yaml, docs, examples, and inventory
- keep the repo generic and public-safe

### stage 2 — create `demo-wordpress`

- add scripts to create a new WordPress project
- add scripts to restore a release into `demo-wordpress`
- keep code generic: no hardcoded external project names
- allow a release example to include plugin/demo content
- make a first public release package named `demo-wordpress`

### stage 3 — create `demo-fullstack`

- add scripts to create a new fullstack project
- add scripts to restore a WordPress + Django release into `demo-fullstack`
- keep code generic: no hardcoded external project names
- allow a release example to include app/demo content
- make a first public release package named `demo-fullstack`

### stage 4 — docs and validation

- explain how to create a new WordPress project from scratch
- explain how to create a new fullstack project from scratch
- explain how to restore a release
- explain how to add more plugins to a WordPress project
- explain how to add more Django apps to a fullstack project
- test all steps on a clean setup
```

 
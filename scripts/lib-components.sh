#!/usr/bin/env bash
# shellcheck disable=SC2034
# Gedeelde definities voor snapshot.sh, reset.sh en save-work.sh
# Compose-project heet 'jit', dus volumes heten jit_<naam>.
declare -A SERVICES=(
  [authentik]="authentik-server authentik-worker authentik-db"
  [midpoint]="midpoint midpoint-db"
  [corteza]="corteza corteza-db"
)
declare -A VOLUMES=(
  [authentik]="jit_authentik_db jit_authentik_data"
  [midpoint]="jit_midpoint_db jit_midpoint_home"
  [corteza]="jit_corteza_db jit_corteza_data"
)
COMPONENTS="authentik midpoint corteza"
COMPOSE="docker compose --project-directory compose -f compose/docker-compose.yml"

backup_volume() {  # $1 volume, $2 doelmap
  docker run --rm -v "$1":/v:ro -v "$(realpath "$2")":/b alpine tar czf "/b/$1.tgz" -C /v .
}
restore_volume() { # $1 volume, $2 bronmap
  docker run --rm -v "$1":/v -v "$(realpath "$2")":/b:ro alpine sh -c "rm -rf /v/..?* /v/.[!.]* /v/* ; tar xzf /b/$1.tgz -C /v"
}

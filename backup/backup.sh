#!/bin/bash
#
# Simple backup script for mastodon.
# This script will generate timestamped backup files of a mastodon instance.
#
# See https://docs.joinmastodon.org/admin/backups/ for more information

set -e

ts="$(date --rfc-3339=seconds | sed -e 's/ /_/' -e 's/:/-/g' -e 's/+.*//')"

# mastodon directory (input) and backup directory and files (output)
mastdir=/opt/mastodon

outputdir=/var/backup
sql_out="${ts}-mastodon-db.xz"
data_out="${ts}-mastodon-data.txz"

# files and subdirectories to include in backup
backup=( "mastodon-data/elasticsearch" "mastodon-data/redis" "mastodon-data/public" "docker-compose.yaml" "mastodon.env.production" )

# Backup creation

cd "${mastdir}"

# Back up database and data
docker-compose exec db pg_dump -U postgres | xz - > "${outputdir}/${sql_out}"
tar cJf "${outputdir}/${data_out}" ${backup[*]} 

echo "Backup of '${mastdir}' - '${sql_out}' and '${data_out}' - created in '${outputdir}'".

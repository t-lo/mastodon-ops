#!/bin/bash
#
# Simple restore script to work with archives created by backup.sh
#
# See https://docs.joinmastodon.org/admin/migrating/ for more information

set -e

if [ 3 -ne $# ] ; then
    echo
    echo "$0 restores a mastodon backup created with backup.sh to <destination dir>"
    echo "Usage: $0 <sql archive> <data archive> <destination dir>"
    echo
fi

sql_in="$(realpath "${1}")"
data_in="$(realpath "${2}")"
dest_dir="$(realpath "${3}")"

mkdir -p "${dest_dir}"
chown mastodon:mastodon "${dest_dir}"
cd "${dest_dir}"

# Extract archives and set ownership

# mastodon_db.sql is mounted into the postgres container's initdb entry point, see "db" service in docker-compose.yaml 
xz -d -c "${sql_in}" > mastodon_db.sql
tar xJf "${data_in}"

chown 991:991 mastodon.env.production
chown -R 991:991 mastodon-data/public
chmod g+rwx mastodon-data/elasticsearch
chgrp 0 mastodon-data/elasticsearch

chown mastodon:mastodon docker-compose.yaml

# Initialise mastodon
docker-compose run --rm -v $(pwd)/mastodon.env.production:/opt/mastodon/.env.production -e RAILS_ENV=production mastodon_web bundle exec rails assets:precompile
docker-compose run --rm -v $(pwd)/mastodon.env.production:/opt/mastodon/.env.production -e RAILS_ENV=production mastodon_web /opt/mastodon/bin/tootctl feeds build

# Make sure all services are stopped
docker-compose down

echo "Restore successful. Run 'docker-compose up' in '${dest_dir}' to launch your instance."

#!/bin/bash
#
# Mastodon image cache cleaner.

docker-compose run --rm -v $(pwd)/mastodon.env.production:/opt/mastodon/.env.production -e RAILS_ENV=production mastodon_web /opt/mastodon/bin/tootctl media remove
docker-compose run --rm -v $(pwd)/mastodon.env.production:/opt/mastodon/.env.production -e RAILS_ENV=production mastodon_web /opt/mastodon/bin/tootctl preview_cards remove

# Mastodon Ops

Mastodon is a distributed micro-blogging service with user-driven federation between nodes. Learn more at https://www.joinmastodon.org/ .
This repository contains a guide as well as docker-compose and auxiliary files (Apache httpd configuration, systemd unit files) for setting up your own mastodon node.

The manual set-up instructions below are rather detailed which may make this look like a daunting task, but it actually won't take long, promise! 
(If you like to supply automation e.g. using Terraform or Ansible or Chef, patches / PRs are always welcome)

## Prerequisites

1. A server with a public IP. This can be a cloud server or a home server with an internet-reachable IP.
   The server requires docker / docker-compose and httpd installed, as well as systemd for services orchestration.
   Lastly, letsencrypt must be installed for requesting and managing certificates.
2. A domain name pointing to the above IP address.
   The domain will be referred to as `{DOMAIN}` in this repo.
3. SMTP access to an existing mail server for 2 mail accounts.
   (While this guide will not cover setting up your own mailserver, patches / PRs are always welcome if you'd like to add it.)
   The guide uses `{MAILSERVER}` as a placeholder for the actual mailserver.
   We'll require 2 mail accounts for this quide:
   - `mastodon-webmaster@{MAILSERVER}` which the web server will use as the mastodon site's web admin.
   - `mastodon-notifications@{MAILSERVER}` for your mastodon instance to send notifications, password resets, email confirmations and the like.
     Mastodon will require the SMTP settings and the password for this account during initial set-up.

## Resources in this repository

1. A docker-compose file which uses the official mastodon dockerhub image as well as the services mastodon depends on
   (except httpd, which will run on the host).
2. A httpd configuration. Apache httpd will act as our https / tls terminator and will proxy incoming connections.
3. A systemd unit file so the service is started at boot time, and restarted should it encounter issues.
4. A very simple backup script and a discussion on how to restore the instance from a backup (as the saying goes, "no one wants backup but eventually, everybody  wants restore").

# Installing

The installation will first discuss setting up the web server, generating letsencryp certificates, and adding a mastodon system user.
Then we are ready  to set up mastodon.
When we have mastodon up and running we'll briefly cover backup (and restore).

## Host set-up: web server, certificates, and a system user to run mastodon on

1. Set up the webserver configuration.
   1. Copy the mastodon httpd config from this repo's `httpd/mastodon.conf` to where your apache httpd configurations reside.
      E.g. on Fedora, it's `/etc/httpd/conf.d/`.
      On Debian / Ubuntu it's `/etc/apache2/sites-available/` and a soft-link from there to `/etc/apache2/sites-enabled/`
      After the file is in place, edit it and replace `{DOMAIN}` with your actual domain name, and `{MAILSERVER}` with the DNS name of your mailserver.
   2. Create `/var/www/{DOMAIN}` (replacing `{DOMAIN}` with your actual domain name) and make sure the web server has access to the path.
      ```shell
      $ mkdir /var/www/{DOMAIN} 
      ```
   3. Create a htdigest file at `/var/www/.htdigest-{DOMAIN}-ops` to add extra security to sensitive URLs (beyond what mastodon provides).
      You can skip this step if you think it's unnecessary; make sure to remove the `<Location> ...</Location>` section from the httpd config then.
      Otherwise, make up a user name an a password and run the belo and ender the password when prompted.
      Remember to replace `{DOMAIN}` with your actual mastodon domain name.
      ```shell
      $ cd /var/www
      $ htdigest -c /var/www/.htdigest-{DOMAIN}-ops {DOMAIN} {Username-you-made-up}
      Adding password for {Username-you-made-up} in realm {DOMAIN}
      New password:
      Re-type new password:
      ```
    4. Restart the web server to make the configuration apply.
       Note that the name of apache httpd's service file is distribution dependent.
       On Fedora:
       ```shell
       $ systemctl restart httpd
       ```
       On Debian / Ubuntu:
       ```shell
       $ systemctl restart apache2
       ```
2. Now we will request letsencrypt certificates for your domain.
   When editing the web server configuration you might have noticed that you mastodon domain is currently served on port 80, and SSL is disabled.
   This is required because we don't have SSL certificates for your mastodon domain yet, and we need a web server so we can request these.
   To request certificates, run the command below.
   When prompted how to authenticate to ACME, chose option "2: Place files in webroot directory (webroot)", ad provide `/var/www/{DOMAIN}` as the webroot to use.
   ```shell
   $ certbot certonly {DOMAIN}
   [...]
   How would you like to authenticate with the ACME CA?
   - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   1: Spin up a temporary webserver (standalone)
   2: Place files in webroot directory (webroot)
   - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Select the appropriate number [1-2] then [enter] (press 'c' to cancel): 2
   [...]
   Requesting a certificate for {DOMAIN}
   Input the webroot for {DOMAIN}: (Enter 'c' to cancel): /var/www/{DOMAIN}
   ...
   ```
3. That's it! We can now update your web server config to use SSL.
   Edit the configuration and remove the comments ('#') from the `SSL...` lines and from `<VirtualHost *:443>`.
   Comment out or remove the line `<VirtualHost *:80>`.
   Lastly, restart httpd one last time; e.g. on Fedora:
   ```shell
   $ systemctl restart httpd
   ```

## Set up mastodon

Now we're going to set up mastodon!
Mastodon and all required dependency services will run in docker containers, which helps us separating data from code, easing operations and backup.
The guide uses `/opt/mastodon` as mastodon's installation directory; if you like to use a different location please make sure you update the path in the systemd service file.

4. Create a mastodon user account and add it to the docker group so the user can launch containers.
   ```shell
   $ adduser --system mastodon
   [...]
   $ usermod -a -G docker mastodon
   ```
5. Create mastodon directories
   ```shell
   $ mkdir /opt/mastodon
   $ cd /opt/mastodon
   $ touch mastodon.env.production
   $ chown 991:991 mastodon.env.production
   $ mkdir -p mastodon-data/public
   $ chown -R 991:991 mastodon-data/public
   $ mkdir -p mastodon-data/elasticsearch
   $ chown -R mastodon:mastodon /opt/mastodon
   $ chmod g+rwx mastodon-data/elasticsearch
   $ chgrp 0 mastodon-data/elasticsearch
   ```
6. Copy this repo's `docker-compose.yaml` to `/opt/mastodon/`.
   We'll now run mastodon's interactive first-time setup.
   Please keep the following information ready:
   1. `{DOMAIN}`
   2. `mastodon-notifications@{MAILSERVER}` account information (SMTP user and password, `{MAILSERVER}` and SMTP port)
      During setup you will have the opportunity to send a test email.
      This is a great way to validate that astodon can send emails, which is vital for user registration and password reset.
   Lastly, you will have the opportunity to set up an Admin user.
   To start the setup, run
   ```shell
   $ cd /opt/mastodon
   $ docker-compose run --rm -v $(pwd)/mastodon.env.production:/opt/mastodon/.env.production -e RUBYOPT=-W0 mastodon_web bundle exec rake mastodon:setup
   ```
   The setup procedure will record most data to `mastodon.env.production`.
   **That's it!** You can now test launch your mastodon instance:
   ```shell
   $ docker-compose up
   ```
   Point a browser to `https://{DOMAIN}` and you'll be greeted by your very own mastodon instance.
   Log in using the admin user you've created during setup.
   Have a look around, check out the server settings (gear icon -> Administration) - specifically the "Sidekiq" and "PgHero" sections.
   (You will need the apache httpd ops username and password we set up at 1.3. above).
   Make sure to watch the `docker-compose up` output for errors and stack traces.
   If everything works finewe can wrap things up and install the systemd service.
   Stop the instance by pressing `CTRL+C` in the terminal where you started `docker-compose up`.
7. Copy this repo's systemd service file to `/etc/systemd/sustem/` and run 
   ```shell
   $ systemctl daemon-reload
   $ systemctl enable --now mastodon
   ```

Congratulations, you're now running your very own mastodon node.

# Backup and restore

Two simple scripts are provided to create a full backup of your mastodon instance and to restore a backup, respectively.

**NOTE** that httpd configuration, letsencrypt certificates, and systemd service file are not included in the backup - only mastodon data is.

The `backup.sh` script does not take any parameters and simply creates a full backup from the instance in `/opt/mastodon`.
Two archives are created per backup - one for the database (SQL dump) and one for the instance's files.
The archives are created in `/var/backup`, the archive filenames include timestamps.
Filenames follow the pattern `YYYY-MM-DD-HH-mm-ss-<type>`, with type being `db` for the SQL dump and `data` for the user data archive.
(e.g. `2022-04-29_16-02-12-mastodon-data.txz` and `2022-04-29_16-02-12-mastodon-db.xz` for a backup made on the 29th of April, 2022).

The `restore.sh` script uses the two archive files created by `backup.sh` and will create a complete, launchable instance from the archives.
The script takes 3 input arguments:
1. SQL archive file
2. data archive file
3. destination directory to create the instance

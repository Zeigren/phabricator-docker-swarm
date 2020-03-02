[![Docker Hub](https://img.shields.io/docker/cloud/build/zeigren/phabricator)](https://hub.docker.com/repository/docker/zeigren/phabricator)
[![](https://images.microbadger.com/badges/image/zeigren/phabricator.svg)](https://microbadger.com/images/zeigren/phabricator)
[![](https://images.microbadger.com/badges/version/zeigren/phabricator.svg)](https://microbadger.com/images/zeigren/phabricator)
[![](https://images.microbadger.com/badges/commit/zeigren/phabricator.svg)](https://microbadger.com/images/zeigren/phabricator)

## Docker Stack For [Phabricator](https://www.phacility.com/phabricator/)

## Tags

Tag labels are based on the container image version.

## Stack

- PHP 7.4-fpm-alpine - Phabricator Stable Branch
- Nginx Alpine
- MariaDB 10.4/latest

## Links

### [Docker Hub](https://hub.docker.com/r/zeigren/phabricator)

### [GitHub](https://github.com/Zeigren/phabricator-docker-swarm)

### [Main Repository](https://projects.zeigren.com/diffusion/40/)

### [Project](https://projects.zeigren.com/project/view/45/)

## Configuration

This is designed to be run under [Docker Swarm](https://docs.docker.com/engine/swarm/) mode, don't know why you can't use secrets with just compose but it is what it is.

I like using [Portainer](https://www.portainer.io/) since it makes all the swarm configuration and tinkering easier, but it's not necessary.

I personally use this with [Traefik](https://traefik.io/) as a reverse proxy, but also not necessary.

You'll need to create these [Docker Secrets](https://docs.docker.com/engine/swarm/secrets/):

- yourdomain.com.crt = The SSL certificate for your domain (you'll need to create/copy this)
- yourdomain.com.key = The SSL key for your domain (you'll need to create/copy this)
- dhparam.pem = Diffie-Hellman parameter (you'll need to create/copy this)
- phabricatorsql_root_password = Root password for your SQL database

You'll also need to create these [Docker Configs](https://docs.docker.com/engine/swarm/configs/):

- phabricator_vhost = The nginx vhost file for BookStack (template included, simply replace all instances of `yourdomain`)
- phabricator_mariadb = Example provided no changes necessary
- mailers.json = Configure your [email provider](https://secure.phabricator.com/book/phabricator/article/configuring_outbound_email/), template provided
- git-sudo = Example provided no changes necessary
- sshd_config.phabricator = Example provided no changes necessary

Make whatever changes you need to docker-stack.yml (replace all instances of `yourdomain`). See `docker-php-entrypoint.sh` for all Phabricator configuration options.

Run with `docker stack deploy --compose-file docker-stack.yml phabricator`

On first start you'll need to add an authentication provider, otherwise you won't be able to login or create new users.

## Volumes

- **/var/www/html**: phabricator files and local config
- **/etc/ssh**: holds sshd-config for diffusion and key files (if keys are not on a volume, the fingerprint of the server will be regenerated on each start)
- **/var/repo**: storage for the git repositories

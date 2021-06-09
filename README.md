# Docker Stack For [Phabricator](https://www.phacility.com/phabricator/)

![Docker Image Size (latest)](https://img.shields.io/docker/image-size/zeigren/phabricator/latest)
![Docker Pulls](https://img.shields.io/docker/pulls/zeigren/phabricator)

## Tags

- latest
- 1.0.2
- 1.0.1
- 1.0.0

Tag labels are based on the container image version

## Stack

- PHP 7.4-fpm-alpine - Phabricator Stable Branch
- Nginx Alpine
- MariaDB

## Links

### [Docker Hub](https://hub.docker.com/r/zeigren/phabricator)

### [GitHub](https://github.com/Zeigren/phabricator-docker-swarm)

### [Main Repository](https://phabricator.kairohm.dev/diffusion/40/)

### [Project](https://phabricator.kairohm.dev/project/view/45/)

## Usage

Use [Docker Compose](https://docs.docker.com/compose/) or [Docker Swarm](https://docs.docker.com/engine/swarm/) to deploy. There are examples for using NGINX or Traefik for SSL termination, or don't use SSL at all.

## Configuration

Configuration primarily consists of environment variables in the `.yml` and `.conf` files.

- phabricator_nginx.conf = NGINX config file (needs to be modified if you're using NGINX for SSL termination or not using HTTPS at all)
- Make whatever changes you need to the appropriate `.yml`. All environment variables for Phabricator can be found in `docker-entrypoint.sh`
- phabricator_mailers.json = Configure your [email provider](https://secure.phabricator.com/book/phabricator/article/configuring_outbound_email/) if you're using one

On first start you'll need to add an [authentication provider](https://secure.phabricator.com/book/phabricator/article/configuring_accounts_and_registration/), otherwise you won't be able to login or create new users.

### Using NGINX for SSL Termination

- yourdomain.test.crt = The SSL certificate for your domain (you'll need to create/copy this)
- yourdomain.test.key = The SSL key for your domain (you'll need to create/copy this)

### [Docker Swarm](https://docs.docker.com/engine/swarm/)

I personally use this with [Traefik](https://traefik.io/) as a reverse proxy, I've included an example `traefik.yml` but it's not necessary.

You'll need to create the appropriate [Docker Secrets](https://docs.docker.com/engine/swarm/secrets/) and [Docker Configs](https://docs.docker.com/engine/swarm/configs/).

Run with `docker stack deploy --compose-file docker-swarm.yml phabricator`

### [Docker Compose](https://docs.docker.com/compose/)

You'll need to create a `config` folder and put `phabricator_nginx.conf`,  `phabricator_mailers.json`, and `phabricator_mariadb.cnf` in it. If you're using NGINX for SSL also put your SSL certificate and SSL key in it.

Run with `docker-compose up -d`. View using `127.0.0.1:9080`.

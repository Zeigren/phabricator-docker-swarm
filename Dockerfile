FROM php:7.4-fpm-alpine

# install alpine packages
RUN apk add --no-cache bash openssh-server openssh-keygen git git-daemon subversion freetype libpng libjpeg-turbo libzip freetype-dev libpng-dev libjpeg-turbo-dev libzip-dev py-pygments sudo sed procps zlib\
 && apk add --virtual .phpize-deps \
    $PHPIZE_DEPS

# add php modules
RUN docker-php-ext-configure gd --enable-gd --with-freetype --with-jpeg \
 && docker-php-ext-install gd \
 && docker-php-ext-configure opcache --enable-opcache \
 && docker-php-ext-install opcache \
 && docker-php-ext-install mysqli \
 && docker-php-ext-install pcntl \
 && docker-php-ext-install zip \
 && pecl install apcu \
 && docker-php-ext-enable apcu \
 && apk del --no-cache freetype-dev libpng-dev libjpeg-turbo-dev libzip-dev

# configure php for production
RUN mv $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini

# user management
ENV PHAB_PHD_USER=${PHAB_PHD_USER:-phduser}
ENV PHAB_DIFFUSION_SSH_PORT=${PHAB_DIFFUSION_SSH_PORT:-2530}
ENV PHAB_DIFFUSION_SSH_USER=${PHAB_DIFFUSION_SSH_USER:-git}

# add account git for diffusion
 RUN adduser -D ${PHAB_DIFFUSION_SSH_USER} \
# enable account git and unlock it with passwd -u
 && passwd -u ${PHAB_DIFFUSION_SSH_USER} \
# add account phduser for phabricator daemons
 && adduser -D ${PHAB_PHD_USER}

# link php, otherwise ssh with git won't work
RUN ln -s /usr/local/bin/php /bin/php

#link git-daemon
RUN ln -s /usr/libexec/git-core/git-http-backend /usr/bin/git-http-backend

# create temp for phab config directory
RUN mkdir -p /usr/src/docker-phab/

# copy ssh hook
COPY ./phabricator-ssh-hook.sh /usr/src/docker-phab/

RUN ["chmod", "+x", "/usr/src/docker-phab/phabricator-ssh-hook.sh"]

COPY ./env_secrets_expand.sh /usr/local/bin/

RUN ["chmod", "+x", "/usr/local/bin/env_secrets_expand.sh"]

COPY ./docker-php-entrypoint.sh /usr/local/bin/

RUN ["chmod", "+x", "/usr/local/bin/docker-php-entrypoint.sh"]

ENTRYPOINT ["/usr/local/bin/docker-php-entrypoint.sh"]

CMD ["php-fpm", "-F"]

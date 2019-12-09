#!/bin/sh

source /usr/local/bin/env_secrets_expand.sh

set -e
set -x

ROOT=/var/www/html
CONFIG_BIN=${ROOT}/phabricator/bin/config
REPO_USER=$(stat -c '%U' /var/repo)

# create php config files
if [ ! -e "/usr/local/etc/php/conf.d/date.ini" ]; then
  cat > "/usr/local/etc/php/conf.d/date.ini" <<EOF
[Date]
date.timezone = ${date_timezone:-America/Los_Angeles}
EOF
fi

if [ ! -e "/usr/local/etc/php/conf.d/mysql.ini" ]; then
  cat > "/usr/local/etc/php/conf.d/mysql.ini" <<EOF
[mysqli]
mysqli.allow_local_infile = ${mysqli_allow_local_infile:-0}
EOF
fi

if [ ! -e "/usr/local/etc/php/conf.d/opcache.ini" ]; then
  cat > "/usr/local/etc/php/conf.d/opcache.ini" <<EOF
opcache.memory_consumption=${opcache_memory_consumption:-128}
opcache.interned_strings_buffer=${opcache_interned_strings_buffer:-8}
opcache.max_accelerated_files=${opcache_max_accelerated_files:-4000}
opcache.revalidate_freq=${opcache_revalidate_freq:-60}
opcache.fast_shutdown=${opcache_fast_shutdown:-1}
opcache.enable_cli=${opcache_enable_cli:-1}
opcache.validate_timestamps=${opcache_validate_timestamps:-0}
EOF
fi

if [ ! -e "/usr/local/etc/php/conf.d/php-phab.ini" ]; then
  cat > "/usr/local/etc/php/conf.d/php-phab.ini" <<EOF
[PHP]
post_max_size = ${post_max_size:-128M}
upload_max_filesize = ${upload_max_filesize:-128M}
memory_limit = ${memory_limit:-1028M}
expose_php = ${expose_php:-off}
cgi.fix_pathinfo = ${cgifix_pathinfo:-0}
EOF
fi

# if nothing on the volume, do a full install by cloning repos
if [ ! -d "${ROOT}/libphutil" ]; then
   sudo -n -u www-data git clone --single-branch --branch stable --depth 1 --shallow-submodules https://github.com/phacility/libphutil.git
fi

if [ ! -d "${ROOT}/arcanist" ]; then
   sudo -n -u www-data git clone --single-branch --branch stable --depth 1 --shallow-submodules https://github.com/phacility/arcanist.git
fi

if [ ! -d "${ROOT}/phabricator" ]; then
   sudo -n -u www-data git clone --single-branch --branch stable --depth 1 --shallow-submodules https://github.com/phacility/phabricator.git
fi

# upgrade repos
if [ "${UPGRADE_ON_RESTART}" = "true" ]; then
  
   cd $ROOT/libphutil
   sudo -n -u www-data git pull

   cd $ROOT/arcanist
   sudo -n -u www-data git pull

   cd $ROOT/phabricator
   sudo -n -u www-data git pull
fi

# start configuration of phabricator with docker environment variables
if [ "${PHAB_PHD_USER}" != "" ]
then
    sudo -n -u www-data ${CONFIG_BIN} set phd.user ${PHAB_PHD_USER}
fi

if [ "${PHAB_DIFFUSION_SSH_PORT}" != "" ]
then
    sudo -n -u www-data ${CONFIG_BIN} set diffusion.ssh-port ${PHAB_DIFFUSION_SSH_PORT}
fi

if [ "${PHAB_DIFFUSION_SSH_USER}" != "" ]
then
    sudo -n -u www-data ${CONFIG_BIN} set diffusion.ssh-user ${PHAB_DIFFUSION_SSH_USER}
fi

if [ "${PHAB_PHABRICATOR_BASE_URI}" != "" ]
then
    sudo -n -u www-data ${CONFIG_BIN} set phabricator.base-uri ${PHAB_PHABRICATOR_BASE_URI}
fi

if [ "${PHAB_MYSQL_PASS}" != "" ]
then
    sudo -n -u www-data ${CONFIG_BIN} set mysql.pass ${PHAB_MYSQL_PASS}
fi

if [ "${PHAB_MYSQL_USER}" != "" ]
then
    sudo -n -u www-data ${CONFIG_BIN} set mysql.user ${PHAB_MYSQL_USER}
fi

if [ "${PHAB_MYSQL_HOST}" != "" ]
then
    sudo -n -u www-data ${CONFIG_BIN} set mysql.host ${PHAB_MYSQL_HOST}
fi

if [ "${PHAB_STORAGE_MYSQL_ENGINE_MAX_SIZE}" != "" ]
then
    sudo -n -u www-data ${CONFIG_BIN} set storage.mysql-engine.max-size ${PHAB_STORAGE_MYSQL_ENGINE_MAX_SIZE}
fi

if [ "${PHAB_METAMTA_DEFAULT_ADDRESS}" != "" ]
then
    sudo -n -u www-data ${CONFIG_BIN} set metamta.default-address ${PHAB_METAMTA_DEFAULT_ADDRESS}
fi

if [ "${PHAB_CLUSTER_MAILERS}" = "true" ]
then
    sudo -n -u www-data ${CONFIG_BIN} set --stdin cluster.mailers < /usr/src/docker-phab/mailers.json
fi

# storage upgrade
if [ "${UPGRADE_ON_RESTART}" = "true" ]; then
  # wait until database is available
  # replace with actual database check
   sleep 30
   $ROOT/phabricator/bin/storage upgrade --force
fi

# copy sshd config for phabricator
if [ ! -e /etc/ssh/sshd_config.phabricator ]
then
    sed 's/PHAB_DIFFUSION_SSH_PORT/'"${PHAB_DIFFUSION_SSH_PORT}"'/g; s/PHAB_DIFFUSION_SSH_USER/'"${PHAB_DIFFUSION_SSH_USER}"'/g' /usr/src/docker-phab/sshd_config.phabricator > /etc/ssh/sshd_config.phabricator
fi

# copy ssh hook
if [ ! -e /usr/libexec/phabricator-ssh-hook.sh ]
then
    sed 's/PHAB_DIFFUSION_SSH_PORT/'"${PHAB_DIFFUSION_SSH_PORT}"'/g; s/PHAB_DIFFUSION_SSH_USER/'"${PHAB_DIFFUSION_SSH_USER}"'/g' /usr/src/docker-phab/phabricator-ssh-hook.sh > /usr/libexec/phabricator-ssh-hook.sh
    chown root /usr/libexec/phabricator-ssh-hook.sh
    chmod 755 /usr/libexec/phabricator-ssh-hook.sh
fi

# check sudo for git usage
if [ ! -e /etc/sudoers.d/${PHAB_DIFFUSION_SSH_USER}-sudo ]
then
    sed 's/PHAB_PHD_USER/'"${PHAB_PHD_USER}"'/g; s/PHAB_DIFFUSION_SSH_USER/'"${PHAB_DIFFUSION_SSH_USER}"'/g' /usr/src/docker-phab/git-sudo > /etc/sudoers.d/${PHAB_DIFFUSION_SSH_USER}-sudo
    chmod 440 /etc/sudoers.d/${PHAB_DIFFUSION_SSH_USER}-sudo
fi

# generate key if necessary (i.e. new docker image)
if [ ! -e /etc/ssh/ssh_host_dsa_key ] || [ ! -e /etc/ssh/ssh_host_rsa_key ] || [ ! -e /etc/ssh/ssh_host_ecdsa_key ] || [ ! -e /etc/ssh/ssh_host_ed25519_key ]
then
   ssh-keygen -A
fi

# change owner of repo directory
if [ "${REPO_USER}" != "${PHAB_PHD_USER}" ]; then
  chown -R phduser /var/repo/
fi

# start sshd for git
/usr/sbin/sshd -e -f /etc/ssh/sshd_config.phabricator

# start phabricator tasks
sudo -E -n -u phduser /var/www/html/phabricator/bin/phd start

# first arg is `-f` or `--some-option`
if [ "${1#-}" != "$1" ]; then
	set -- php "$@"
fi

exec "$@"
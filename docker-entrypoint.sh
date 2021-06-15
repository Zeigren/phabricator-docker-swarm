#!/bin/sh

source /usr/local/bin/env_secrets_expand.sh

set -e

ROOT=/var/www/html
CONFIG_BIN=${ROOT}/phabricator/bin/config
REPO_USER=$(stat -c '%U' /var/repo)

# create PHP config files
echo "creating PHP config files"

cat > "/usr/local/etc/php/conf.d/date.ini" <<EOF
[Date]
date.timezone = ${DATE_TIMEZONE:-America/Los_Angeles}
EOF

cat > "/usr/local/etc/php/conf.d/mysql.ini" <<EOF
[mysqli]
mysqli.allow_local_infile = ${MYSQLI_ALLOW_LOCAL_INFILE:-0}
EOF

cat > "/usr/local/etc/php/conf.d/opcache.ini" <<EOF
opcache.memory_consumption=${OPCACHE_MEMORY_CONSUMPTION:-128}
opcache.interned_strings_buffer=${OPCACHE_INTERNED_STRINGS_BUFFER:-8}
opcache.max_accelerated_files=${OPCACHE_MAX_ACCELERATED_FILES:-4000}
opcache.revalidate_freq=${OPCACHE_REVALIDATE_FREQ:-60}
opcache.fast_shutdown=${OPCACHE_FAST_SHUTDOWN:-1}
opcache.enable_cli=${OPCACHE_ENABLE_CLI:-1}
opcache.validate_timestamps=${OPCACHE_VALIDATE_TIMESTAMPS:-0}
EOF

cat > "/usr/local/etc/php/conf.d/php-phab.ini" <<EOF
[PHP]
post_max_size = ${POST_MAX_SIZE:-128M}
upload_max_filesize = ${UPLOAD_MAX_FILESIZE:-128M}
memory_limit = ${MEMORY_LIMIT:-1028M}
expose_php = ${EXPOSE_PHP:-off}
cgi.fix_pathinfo = ${CGIFIX_PATHINFO:-0}
EOF

# Set PHP-FPM conf
sed -i "s/pm =.*/pm = ${FPM_PM:-dynamic}/" /usr/local/etc/php-fpm.d/www.conf
sed -i "s/pm.max_children =.*/pm.max_children = ${FPM_MAX_CHILDREN:-5}/" /usr/local/etc/php-fpm.d/www.conf
sed -i "s/pm.start_servers =.*/pm.start_servers = ${FPM_START_SERVERS:-2}/" /usr/local/etc/php-fpm.d/www.conf
sed -i "s/pm.min_spare_servers =.*/pm.min_spare_servers = ${FPM_MIN_SPARE:-1}/" /usr/local/etc/php-fpm.d/www.conf
sed -i "s/pm.max_spare_servers =.*/pm.max_spare_servers = ${FPM_MAX_SPARE:-3}/" /usr/local/etc/php-fpm.d/www.conf

echo "creating other config files"

# create sudo config
cat > "/etc/sudoers.d/git-sudo" <<EOF
git ALL=(phduser) SETENV: NOPASSWD: /usr/bin/git, /usr/bin/git-upload-pack, /usr/bin/git-receive-pack, /usr/bin/svnserve
www-data ALL=(phduser) SETENV: NOPASSWD: /usr/bin/git, /usr/bin/git-http-backend
EOF

# create sshd config
cat > "/etc/ssh/sshd_config.phabricator" <<EOF
AuthorizedKeysCommand /usr/libexec/phabricator-ssh-hook.sh
AuthorizedKeysCommandUser git
AllowUsers git

HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

Port ${PHAB_DIFFUSION_SSH_PORT:-2530}
Protocol 2
PermitRootLogin no
AllowAgentForwarding no
AllowTcpForwarding no
PrintMotd no
PasswordAuthentication no
ChallengeResponseAuthentication no
AuthorizedKeysFile none

PidFile /var/run/sshd-phabricator.pid
EOF

# create ssh hook
cat > "/usr/libexec/phabricator-ssh-hook.sh" <<'EOF'
#!/bin/sh

VCSUSER="git"

ROOT="/var/www/html/phabricator"

if [ "$1" != "$VCSUSER" ];
then
  exit 1
fi

exec "$ROOT/bin/ssh-auth" $@
EOF

# if nothing on the volume, do a full install by cloning repos
if [ ! -d "${ROOT}/libphutil" ]; then
   echo "cloning libphutil"
   sudo -n -u www-data git clone --single-branch --branch stable --depth 1 --shallow-submodules https://github.com/phacility/libphutil.git
fi

if [ ! -d "${ROOT}/arcanist" ]; then
   echo "cloning arcanist"
   sudo -n -u www-data git clone --single-branch --branch stable --depth 1 --shallow-submodules https://github.com/phacility/arcanist.git
fi

if [ ! -d "${ROOT}/phabricator" ]; then
   echo "cloning phabricator"
   sudo -n -u www-data git clone --single-branch --branch stable --depth 1 --shallow-submodules https://github.com/phacility/phabricator.git
fi

# upgrade repos
if [ "${UPGRADE_ON_RESTART}" = "true" ]; then
   echo "updating libphutil, arcanist, and phabricator"
  
   cd $ROOT/libphutil
   sudo -n -u www-data git pull

   cd $ROOT/arcanist
   sudo -n -u www-data git pull

   cd $ROOT/phabricator
   sudo -n -u www-data git pull
fi

echo "configuring phabricator"

# start configuration of phabricator with docker environment variables
sudo -n -u www-data ${CONFIG_BIN} set phd.user phduser

sudo -n -u www-data ${CONFIG_BIN} set diffusion.ssh-port ${PHAB_DIFFUSION_SSH_PORT:-2530}

sudo -n -u www-data ${CONFIG_BIN} set diffusion.ssh-user git

sudo -n -u www-data ${CONFIG_BIN} set phabricator.base-uri ${PHAB_PHABRICATOR_BASE_URI:-https://phabricator.yourdomain.test}

sudo -n -u www-data ${CONFIG_BIN} set mysql.pass ${PHAB_MYSQL_PASS:-CHANGEME}

sudo -n -u www-data ${CONFIG_BIN} set mysql.user ${PHAB_MYSQL_USER:-root}

sudo -n -u www-data ${CONFIG_BIN} set mysql.host ${PHAB_MYSQL_HOST:-mariadb}

sudo -n -u www-data ${CONFIG_BIN} set storage.mysql-engine.max-size ${PHAB_STORAGE_MYSQL_ENGINE_MAX_SIZE:-8388608}

if [ "${PHAB_METAMTA_DEFAULT_ADDRESS}" != "" ]
then
    sudo -n -u www-data ${CONFIG_BIN} set metamta.default-address ${PHAB_METAMTA_DEFAULT_ADDRESS}
fi

if [ "${PHAB_CLUSTER_MAILERS}" = "true" ]
then
    sudo -n -u www-data ${CONFIG_BIN} set --stdin cluster.mailers < /usr/src/docker-phab/mailers.json
fi

# set permissions for ssh hook
chown root /usr/libexec/phabricator-ssh-hook.sh
chmod 755 /usr/libexec/phabricator-ssh-hook.sh

# set permissions for sudo
chmod 440 /etc/sudoers.d/git-sudo

# storage upgrade
if [ "${UPGRADE_ON_RESTART}" = "true" ]
then
    echo "updating ${PHAB_MYSQL_HOST:-mariadb}"
    echo "waiting for ${PHAB_MYSQL_HOST:-mariadb}:3306"
    /usr/local/bin/wait-for.sh ${PHAB_MYSQL_HOST:-mariadb}:3306 -- echo 'success'
    echo "let ${PHAB_MYSQL_HOST:-mariadb} warm up"
    sleep 10s
   $ROOT/phabricator/bin/storage upgrade --force
fi

# generate ssh keys if needed
if [ ! -e /etc/ssh/ssh_host_dsa_key ] || [ ! -e /etc/ssh/ssh_host_rsa_key ] || [ ! -e /etc/ssh/ssh_host_ecdsa_key ] || [ ! -e /etc/ssh/ssh_host_ed25519_key ]
then
   ssh-keygen -A
fi

# change owner of repo directory
if [ "${REPO_USER}" != "phduser" ]; then
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

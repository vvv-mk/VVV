#!/bin/bash
#
# provision.sh
#
# This file is specified in Vagrantfile and is loaded by Vagrant as the primary
# provisioning script whenever the commands `vagrant up`, `vagrant provision`,
# or `vagrant reload` are used. It provides all of the default packages and
# configurations included with Varying Vagrant Vagrants.

source provision-network-functions.sh

# By storing the date now, we can calculate the duration of provisioning at the
# end of this script.
start_seconds="$(date +%s)"

# PACKAGE INSTALLATION
#
# Build a bash array to pass all of the packages we want to install to a single
# apt-get command. This avoids doing all the leg work each time a package is
# set to install. It also allows us to easily comment out or add single
# packages.
apt_package_install_list=(
  # Please avoid apostrophes in these comments - they break vim syntax
  # highlighting.
  # 
  software-properties-common

  # PHP7
  #
  # Our base packages for php7.2. As long as php7.2-fpm and php7.2-cli are
  # installed, there is no need to install the general php7.2 package, which
  # can sometimes install apache as a requirement.
  php7.2-fpm
  php7.2-cli

  # Common and dev packages for php
  php7.2-common
  php7.2-dev

  # Extra PHP modules that we find useful
  php-pear
  php-imagick
  php-memcache
  php-memcached
  php-ssh2
  php-xdebug
  php7.2-bcmath
  php7.2-curl
  php7.2-gd
  php7.2-mbstring
  php7.2-mysql
  php7.2-imap
  php7.2-json
  php7.2-soap
  php7.2-xml
  php7.2-zip

  # nginx is installed as the default web server
  nginx

  # memcached is made available for object caching
  memcached

  # mariadb (drop-in replacement on mysql) is the default database
  mariadb-server

  # other packages that come in handy
  imagemagick
  subversion
  git
  git-lfs
  zip
  unzip
  ngrep
  curl
  make
  vim
  colordiff
  postfix
  python-pip

  # ntp service to keep clock current
  ntp

  # Required for i18n tools
  gettext

  # Required for Webgrind
  graphviz

  # dos2unix
  # Allows conversion of DOS style line endings to something less troublesome
  # in Linux.
  dos2unix

  # nodejs for use by grunt
  g++
  nodejs
)

### FUNCTIONS

git_ppa_check() {
  # git
  #
  # apt-get does not have latest version of git,
  # so let's the use ppa repository instead.
  #
  # Install prerequisites.
  sudo apt-get install -y python-software-properties software-properties-common &>/dev/null
  # Add ppa repo.
  echo "Adding ppa:git-core/ppa repository"
  sudo add-apt-repository -y ppa:git-core/ppa &>/dev/null
  # Update apt-get info.
  sudo apt-get update &>/dev/null
}

noroot() {
  sudo -EH -u "vagrant" "$@";
}

cleanup_terminal_splash() {
  # Dastardly Ubuntu tries to be helpful and suggest users update packages
  # themselves, but this can break things
  if [[ -f /etc/update-motd.d/00-header ]]; then
    rm /etc/update-motd.d/00-header
  fi
  if [[ -f /etc/update-motd.d/10-help-text ]]; then
    rm /etc/update-motd.d/10-help-text
  fi
  if [[ -f /etc/update-motd.d/51-cloudguest ]]; then
    rm /etc/update-motd.d/51-cloudguest
  fi
  if [[ -f /etc/update-motd.d/50-landscape-sysinfo ]]; then
    rm /etc/update-motd.d/50-landscape-sysinfo
  fi
  if [[ -f /etc/update-motd.d/90-updates-available ]]; then
    rm /etc/update-motd.d/90-updates-available
  fi
  if [[ -f /etc/update-motd.d/91-release-upgrade ]]; then
    rm /etc/update-motd.d/91-release-upgrade
  fi
  if [[ -f /etc/update-motd.d/95-hwe-eol ]]; then
    rm /etc/update-motd.d/95-hwe-eol
  fi
  if [[ -f /etc/update-motd.d/98-cloudguest ]]; then
    rm /etc/update-motd.d/98-cloudguest
  fi
  cp "/srv/config/update-motd.d/00-vvv-bash-splash" "/etc/update-motd.d/00-vvv-bash-splash"
  chmod +x /etc/update-motd.d/00-vvv-bash-splash
}

profile_setup() {
  # Copy custom dotfiles and bin file for the vagrant user from local
  cp "/srv/config/bash_profile" "/home/vagrant/.bash_profile"
  cp "/srv/config/bash_aliases" "/home/vagrant/.bash_aliases"
  cp "/srv/config/vimrc" "/home/vagrant/.vimrc"

  if [[ ! -d "/home/vagrant/.subversion" ]]; then
    mkdir "/home/vagrant/.subversion"
  fi

  cp "/srv/config/subversion-servers" "/home/vagrant/.subversion/servers"
  cp "/srv/config/subversion-config" "/home/vagrant/.subversion/config"

  echo " * Copied /srv/config/bash_profile                      to /home/vagrant/.bash_profile"
  echo " * Copied /srv/config/bash_aliases                      to /home/vagrant/.bash_aliases"
  echo " * Copied /srv/config/vimrc                             to /home/vagrant/.vimrc"
  echo " * Copied /srv/config/subversion-servers                to /home/vagrant/.subversion/servers"
  echo " * Copied /srv/config/subversion-config                 to /home/vagrant/.subversion/config"

  # If a bash_prompt file exists in the VVV config/ directory, copy to the VM.
  if [[ -f "/srv/config/bash_prompt" ]]; then
    cp "/srv/config/bash_prompt" "/home/vagrant/.bash_prompt"
    echo " * Copied /srv/config/bash_prompt to /home/vagrant/.bash_prompt"
  fi
}

not_installed() {
  dpkg -s "$1" 2>&1 | grep -q 'Version:'
  if [[ "$?" -eq 0 ]]; then
    apt-cache policy "$1" | grep 'Installed: (none)'
    return "$?"
  else
    return 0
  fi
}

print_pkg_info() {
  local pkg="$1"
  local pkg_version="$2"
  local space_count
  local pack_space_count
  local real_space

  space_count="$(( 20 - ${#pkg} ))" #11
  pack_space_count="$(( 30 - ${#pkg_version} ))"
  real_space="$(( space_count + pack_space_count + ${#pkg_version} ))"
  printf " * $pkg %${real_space}.${#pkg_version}s ${pkg_version}\n"
}

package_install() {

  # MariaDB/MySQL
  #
  # Use debconf-set-selections to specify the default password for the root MariaDB
  # account. This runs on every provision, even if MariaDB has been installed. If
  # MariaDB is already installed, it will not affect anything.
  echo mariadb-server-10.1 mysql-server/root_password password "root" | debconf-set-selections
  echo mariadb-server-10.1 mysql-server/root_password_again password "root" | debconf-set-selections

  # Postfix
  #
  # Use debconf-set-selections to specify the selections in the postfix setup. Set
  # up as an 'Internet Site' with the host name 'vvv'. Note that if your current
  # Internet connection does not allow communication over port 25, you will not be
  # able to send mail, even with postfix installed.
  echo postfix postfix/main_mailer_type select Internet Site | debconf-set-selections
  echo postfix postfix/mailname string vvv | debconf-set-selections

  # Provide our custom apt sources before running `apt-get update`
  ln -sf /srv/config/apt-source-append.list /etc/apt/sources.list.d/vvv-sources.list
  echo "Linked custom apt sources"

  if [[ ! $( apt-key list | grep 'NodeSource') ]]; then
    # Retrieve the NodeJS signing key from nodesource.com
    echo "Applying NodeSource NodeJS signing key..."
    apt-key add /vagrant/config/apt-keys/nodesource.gpg.key
  fi

  # Before running `apt-get update`, we should add the public keys for
  # the packages that we are installing from non standard sources via
  # our appended apt source.list
  if [[ ! $( apt-key list | grep 'nginx') ]]; then
    # Retrieve the Nginx signing key from nginx.org
    echo "Applying Nginx signing key..."
    apt-key add /vagrant/config/apt-keys/nginx_signing.key
  fi

  if [[ ! $( apt-key list | grep 'Ondřej') ]]; then
    # Apply the PHP signing key
    echo "Applying the PHP signing key..."
    apt-key add /vagrant/config/apt-keys/keyserver_ubuntu.key
  fi

  if [[ ! $( apt-key list | grep 'MariaDB') ]]; then
    # Apply the MariaDB signing key
    echo "Applying the MariaDB signing key..."
    apt-key add /vagrant/config/apt-keys/mariadb.key
  fi

  if [[ ! $( apt-key list | grep 'packagecloud ops') ]]; then
    # Apply the PackageCloud signing key which signs git lfs
    echo "Applying the PackageCloud signing key..."
    apt-key add /vagrant/config/apt-keys/git-lfs.key
  fi

  # Update all of the package references before installing anything
  echo "Running apt-get update..."
  apt-get -y update

  # Install required packages
  echo "Installing apt-get packages..."
  if ! apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confnew install --fix-missing --fix-broken ${apt_package_install_list[@]}; then
    apt-get clean
    return 1
  fi

  # Remove unnecessary packages
  echo "Removing unnecessary packages..."
  apt-get autoremove -y

  # Clean up apt caches
  apt-get clean
  
  return 0
}

# taken from <https://gist.github.com/lukechilds/a83e1d7127b78fef38c2914c4ececc3c>
latest_github_release() {
    local LATEST_RELEASE=$(curl --silent "https://api.github.com/repos/$1/releases/latest") # Get latest release from GitHub api
    local GITHUB_RELEASE_REGEXP="\"tag_name\": \"([^\"]+)\""

    if [[ $LATEST_RELEASE =~ $GITHUB_RELEASE_REGEXP ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

tools_install() {
  # Disable xdebug before any composer provisioning.
  sh /vagrant/config/homebin/xdebug_off

  local LATEST_NVM=$(latest_github_release "creationix/nvm")

  # nvm
  mkdir -p "/srv/config/nvm" &&
      curl -so- https://raw.githubusercontent.com/creationix/nvm/$LATEST_NVM/install.sh |
          METHOD=script NVM_DIR=/srv/config/nvm bash

  source /srv/config/nvm/nvm.sh

  # npm
  #
  # Make sure we have the latest npm version and the update checker module
  echo "Installing/updating npm..."
  npm install -g npm
  echo "Installing/updating npm-check-updates..."
  npm install -g npm-check-updates

  # ack-grep
  #
  # Install ack-rep directory from the version hosted at beyondgrep.com as the
  # PPAs for Ubuntu Precise are not available yet.
  if [[ -f /usr/bin/ack ]]; then
    echo "ack-grep already installed"
  else
    echo "Installing ack-grep as ack"
    curl -s https://beyondgrep.com/ack-2.16-single-file > "/usr/bin/ack" && chmod +x "/usr/bin/ack"
  fi

  # Make sure the composer cache is not owned by root
  mkdir -p /usr/local/src/composer
  mkdir -p /usr/local/src/composer/cache
  chown -R vagrant:www-data /usr/local/src/composer
  chown -R vagrant:www-data /usr/local/bin

  # COMPOSER
  #
  # Install Composer if it is not yet available.
  if [[ ! -n "$(noroot composer --version --no-ansi | grep 'Composer version')" ]]; then
    echo "Installing Composer..."
    curl -sS "https://getcomposer.org/installer" | php
    chmod +x "composer.phar"
    mv "composer.phar" "/usr/local/bin/composer"
  fi

  if [[ -f /vagrant/provision/github.token ]]; then
    ghtoken=`cat /vagrant/provision/github.token`
    noroot composer config --global github-oauth.github.com $ghtoken
    echo "Your personal GitHub token is set for Composer."
  fi

  # Update both Composer and any global packages. Updates to Composer are direct from
  # the master branch on its GitHub repository.
  if [[ -n "$(noroot composer --version --no-ansi | grep 'Composer version')" ]]; then
    echo "Updating Composer..."
    COMPOSER_HOME=/usr/local/src/composer noroot composer --no-ansi self-update --no-progress --no-interaction
    COMPOSER_HOME=/usr/local/src/composer noroot composer --no-ansi global require --no-update --no-progress --no-interaction phpunit/phpunit:6.* phpunit/php-invoker:1.1.* mockery/mockery:0.9.* d11wtq/boris:v1.0.8
    COMPOSER_HOME=/usr/local/src/composer noroot composer --no-ansi global config bin-dir /usr/local/bin
    COMPOSER_HOME=/usr/local/src/composer noroot composer --no-ansi global update --no-progress --no-interaction
  fi

  # Grunt
  #
  # Install or Update Grunt based on current state.  Updates are direct
  # from NPM
  function hack_avoid_gyp_errors() {
    # Without this, we get a bunch of errors when installing `grunt-sass`:
    # > node scripts/install.js
    # Unable to save binary /usr/lib/node_modules/.../node-sass/.../linux-x64-48 :
    # { Error: EACCES: permission denied, mkdir '/usr/lib/node_modules/... }
    # Then, node-gyp generates tons of errors like:
    # WARN EACCES user "root" does not have permission to access the dev dir
    # "/usr/lib/node_modules/grunt-sass/node_modules/node-sass/.node-gyp/6.11.2"
    # TODO: Why do child processes of `npm` run as `nobody`?
    while [ ! -f /tmp/stop_gyp_hack ]; do
      if [ -d /usr/lib/node_modules/grunt-sass/ ]; then
        chown -R nobody:vagrant /usr/lib/node_modules/grunt-sass/
      fi
      sleep .2
    done
    rm /tmp/stop_gyp_hack
  }
  if [[ "$(grunt --version)" ]]; then
    echo "Updating Grunt CLI"
    npm update -g grunt-cli
    hack_avoid_gyp_errors & npm update -g grunt-sass; touch /tmp/stop_gyp_hack
    npm update -g grunt-cssjanus
    npm update -g grunt-rtlcss
  else
    echo "Installing Grunt CLI"
    npm install -g grunt-cli
    hack_avoid_gyp_errors & npm install -g grunt-sass; touch /tmp/stop_gyp_hack
    npm install -g grunt-cssjanus
    npm install -g grunt-rtlcss
  fi
  chown -R vagrant:vagrant /usr/lib/node_modules/

  # Graphviz
  #
  # Set up a symlink between the Graphviz path defined in the default Webgrind
  # config and actual path.
  echo "Adding graphviz symlink for Webgrind..."
  ln -sf "/usr/bin/dot" "/usr/local/bin/dot"

  # Shyaml
  #
  # Used for passing custom parameters to the bash provisioning scripts
  echo "Installing Shyaml for bash provisioning.."
  sudo pip install shyaml
}

nginx_setup() {
  # Create an SSL key and certificate for HTTPS support.
  if [[ ! -e /etc/nginx/server-2.1.0.key ]]; then
    echo "Generating Nginx server private key..."
    vvvgenrsa="$(openssl genrsa -out /etc/nginx/server-2.1.0.key 2048 2>&1)"
    echo "$vvvgenrsa"
  fi
  if [[ ! -e /etc/nginx/server-2.1.0.crt ]]; then
    echo "Sign the certificate using the above private key..."
    vvvsigncert="$(openssl req -new -x509 \
            -key /etc/nginx/server-2.1.0.key \
            -out /etc/nginx/server-2.1.0.crt \
            -days 3650 \
            -subj /CN=*.wordpress-develop.test/CN=*.wordpress.test/CN=*.wordpress-develop.dev/CN=*.wordpress.dev/CN=*.vvv.dev/CN=*.vvv.local/CN=*.vvv.localhost/CN=*.vvv.test 2>&1)"
    echo "$vvvsigncert"
  fi

  echo -e "\nSetup configuration files..."

  # Used to ensure proper services are started on `vagrant up`
  cp "/srv/config/init/vvv-start.conf" "/etc/init/vvv-start.conf"
  echo " * Copied /srv/config/init/vvv-start.conf               to /etc/init/vvv-start.conf"

  # Copy nginx configuration from local
  cp "/srv/config/nginx-config/nginx.conf" "/etc/nginx/nginx.conf"
  cp "/srv/config/nginx-config/nginx-wp-common.conf" "/etc/nginx/nginx-wp-common.conf"

  if [[ ! -d "/etc/nginx/upstreams" ]]; then
    mkdir "/etc/nginx/upstreams/"
  fi
  cp "/srv/config/nginx-config/php7.2-upstream.conf" "/etc/nginx/upstreams/php72.conf"

  if [[ ! -d "/etc/nginx/custom-sites" ]]; then
    mkdir "/etc/nginx/custom-sites/"
  fi
  rsync -rvzh --delete "/srv/config/nginx-config/sites/" "/etc/nginx/custom-sites/"
  
  if [[ ! -d "/etc/nginx/custom-utilities" ]]; then
    mkdir "/etc/nginx/custom-utilities/"
  fi

  if [[ ! -d "/etc/nginx/custom-dashboard-extensions" ]]; then
    mkdir "/etc/nginx/custom-dashboard-extensions/"
  fi

  rm -rf /etc/nginx/custom-{dashboard-extensions,utilities}/*

  echo " * Copied /srv/config/nginx-config/nginx.conf           to /etc/nginx/nginx.conf"
  echo " * Copied /srv/config/nginx-config/nginx-wp-common.conf to /etc/nginx/nginx-wp-common.conf"
  echo " * Rsync'd /srv/config/nginx-config/sites/              to /etc/nginx/custom-sites"
  mkdir -p /var/log/nginx/
  touch /var/log/nginx/error.log
  touch /var/log/nginx/access.log
}

phpfpm_setup() {
  # Copy php-fpm configuration from local
  cp "/srv/config/php-config/php7.2-fpm.conf" "/etc/php/7.2/fpm/php-fpm.conf"
  cp "/srv/config/php-config/php7.2-www.conf" "/etc/php/7.2/fpm/pool.d/www.conf"
  cp "/srv/config/php-config/php7.2-custom.ini" "/etc/php/7.2/fpm/conf.d/php-custom.ini"
  cp "/srv/config/php-config/opcache.ini" "/etc/php/7.2/fpm/conf.d/opcache.ini"
  cp "/srv/config/php-config/xdebug.ini" "/etc/php/7.2/mods-available/xdebug.ini"
  cp "/srv/config/php-config/mailhog.ini" "/etc/php/7.2/mods-available/mailhog.ini"

  echo " * Copied /srv/config/php-config/php7.2-fpm.conf   to /etc/php/7.2/fpm/php-fpm.conf"
  echo " * Copied /srv/config/php-config/php7.2-www.conf   to /etc/php/7.2/fpm/pool.d/www.conf"
  echo " * Copied /srv/config/php-config/php7.2-custom.ini to /etc/php/7.2/fpm/conf.d/php-custom.ini"
  echo " * Copied /srv/config/php-config/opcache.ini       to /etc/php/7.2/fpm/conf.d/opcache.ini"
  echo " * Copied /srv/config/php-config/xdebug.ini        to /etc/php/7.2/mods-available/xdebug.ini"
  echo " * Copied /srv/config/php-config/mailhog.ini       to /etc/php/7.2/mods-available/mailhog.ini"

  if [[ -f "/etc/php/7.2/mods-available/mailcatcher.ini" ]]; then
    echo " * Cleaning up mailcatcher.ini from a previous install"
    rm -f /etc/php/7.2/mods-available/mailcatcher.ini
  fi

  # Copy memcached configuration from local
  cp "/srv/config/memcached-config/memcached.conf" "/etc/memcached.conf"
  cp "/srv/config/memcached-config/memcached.conf" "/etc/memcached_default.conf"

  echo " * Copied /srv/config/memcached-config/memcached.conf to /etc/memcached.conf and /etc/memcached_default.conf"
}

go_setup() {
  if [[ ! -e /usr/local/go/bin/go ]]; then
      echo " * Installing GoLang 1.10.3"
      curl -so- https://dl.google.com/go/go1.10.3.linux-amd64.tar.gz | tar zxvf -
      mv go /usr/local
      export PATH="$PATH:/usr/local/go/bin"
      export GOPATH=/home/vagrant/gocode
  fi
}

mailhog_setup() {

  if [[ -f "/etc/init/mailcatcher.conf" ]]; then
    echo " * Cleaning up old mailcatcher.conf"
    rm -f /etc/init/mailcatcher.conf
  fi

  if [[ ! -e /usr/local/bin/mailhog ]]; then
    export GOPATH=/home/vagrant/gocode
    
    echo " * Fetching MailHog and MHSendmail"
    
    noroot mkdir -p /home/vagrant/gocode
    noroot /usr/local/go/bin/go get github.com/mailhog/MailHog
    noroot /usr/local/go/bin/go get github.com/mailhog/mhsendmail

    cp /home/vagrant/gocode/bin/MailHog /usr/local/bin/mailhog
    cp /home/vagrant/gocode/bin/mhsendmail /usr/local/bin/mhsendmail

    # Make it start on reboot
    tee /etc/init/mailhog.conf <<EOL
description "MailHog"
start on runlevel [2345]
stop on runlevel [!2345]
respawn
pre-start script
    exec su - vagrant -c "/usr/bin/env /usr/local/bin/mailhog > /dev/null 2>&1 &"
end script
EOL
  fi
  if [[ -e /etc/init/mailcatcher.conf ]]; then
    echo " * Cleaning up old MailCatcher startup file"
    rm /etc/init/mailcatcher.conf
  fi
  echo " * Starting MailHog"
  service mailhog start
}

mysql_setup() {
  # If MariaDB/MySQL is installed, go through the various imports and service tasks.
  local exists_mysql

  exists_mysql="$(service mysql status)"
  if [[ "mysql: unrecognized service" != "${exists_mysql}" ]]; then
    echo -e "\nSetup MySQL configuration file links..."

    # Copy mysql configuration from local
    cp "/srv/config/mysql-config/my.cnf" "/etc/mysql/my.cnf"
    cp "/srv/config/mysql-config/root-my.cnf" "/home/vagrant/.my.cnf"

    echo " * Copied /srv/config/mysql-config/my.cnf               to /etc/mysql/my.cnf"
    echo " * Copied /srv/config/mysql-config/root-my.cnf          to /home/vagrant/.my.cnf"

    # MySQL gives us an error if we restart a non running service, which
    # happens after a `vagrant halt`. Check to see if it's running before
    # deciding whether to start or restart.
    if [[ "mysql stop/waiting" == "${exists_mysql}" ]]; then
      echo "service mysql start"
      service mysql start
      else
      echo "service mysql restart"
      service mysql restart
    fi

    # IMPORT SQL
    #
    # Create the databases (unique to system) that will be imported with
    # the mysqldump files located in database/backups/
    if [[ -f "/srv/database/init-custom.sql" ]]; then
      mysql -u "root" -p"root" < "/srv/database/init-custom.sql"
      echo -e "\nInitial custom MySQL scripting..."
    else
      echo -e "\nNo custom MySQL scripting found in database/init-custom.sql, skipping..."
    fi

    # Setup MySQL by importing an init file that creates necessary
    # users and databases that our vagrant setup relies on.
    mysql -u "root" -p"root" < "/srv/database/init.sql"
    echo "Initial MySQL prep..."

    # Process each mysqldump SQL file in database/backups to import
    # an initial data set for MySQL.
    "/srv/database/import-sql.sh"
  else
    echo -e "\nMySQL is not installed. No databases imported."
  fi
}

services_restart() {
  # RESTART SERVICES
  #
  # Make sure the services we expect to be running are running.
  echo -e "\nRestart services..."
  service nginx restart
  service memcached restart
  service mailhog restart

  # Disable PHP Xdebug module by default
  phpdismod xdebug

  # Enable PHP mailcatcher sendmail settings by default
  phpenmod mailhog

  # Restart all php-fpm versions
  find /etc/init.d/ -name "php*-fpm" -exec bash -c 'sudo service "$(basename "$0")" restart' {} \;

  # Add the vagrant user to the www-data group so that it has better access
  # to PHP and Nginx related files.
  usermod -a -G www-data vagrant
}

wp_cli() {
  # WP-CLI Install
  local exists_wpcli

  # Remove old wp-cli symlink, if it exists.
  if [[ -L "/usr/local/bin/wp" ]]; then
    echo "\nRemoving old wp-cli"
    rm -f /usr/local/bin/wp
  fi

  exists_wpcli="$(which wp)"
  if [[ "/usr/local/bin/wp" != "${exists_wpcli}" ]]; then
    echo -e "\nDownloading wp-cli, see http://wp-cli.org"
    curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli-nightly.phar
    chmod +x wp-cli-nightly.phar
    sudo mv wp-cli-nightly.phar /usr/local/bin/wp

    # Install bash completions
    curl -s https://raw.githubusercontent.com/wp-cli/wp-cli/master/utils/wp-completion.bash -o /srv/config/wp-cli/wp-completion.bash
  else
    echo -e "\nUpdating wp-cli..."
    wp --allow-root cli update --nightly --yes
  fi
}

php_codesniff() {
  # PHP_CodeSniffer (for running WordPress-Coding-Standards)
  # Sniffs WordPress Coding Standards
  echo -e "\nInstall/Update PHP_CodeSniffer (phpcs), see https://github.com/squizlabs/PHP_CodeSniffer"
  echo -e "\nInstall/Update WordPress-Coding-Standards, sniffs for PHP_CodeSniffer, see https://github.com/WordPress-Coding-Standards/WordPress-Coding-Standards"
  cd /vagrant/provision/phpcs
  noroot composer update --no-ansi --no-autoloader

  # Link `phpcbf` and `phpcs` to the `/usr/local/bin` directory
  ln -sf "/srv/www/phpcs/bin/phpcbf" "/usr/local/bin/phpcbf"
  ln -sf "/srv/www/phpcs/bin/phpcs" "/usr/local/bin/phpcs"

  # Install the standards in PHPCS
  phpcs --config-set installed_paths ./CodeSniffer/Standards/WordPress/,./CodeSniffer/Standards/VIP-Coding-Standards/,./CodeSniffer/Standards/PHPCompatibility/
  phpcs --config-set default_standard WordPress-Core
  phpcs -i
}

wpsvn_check() {
  # Get all SVN repos.
  svn_repos=$(find /srv/www -maxdepth 5 -type d -name '.svn');

  # Do we have any?
  if [[ -n $svn_repos ]]; then
    for repo in $svn_repos; do
      # Test to see if an svn upgrade is needed on this repo.
      svn_test=$( svn status -u "$repo" 2>&1 );

      if [[ "$svn_test" == *"svn upgrade"* ]]; then
        # If it is needed do it!
        svn upgrade "${repo/%\.svn/}"
      fi;
    done
  fi;
}

cleanup_vvv(){
  # Kill previously symlinked Nginx configs
  find /etc/nginx/custom-sites -name 'vvv-auto-*.conf' -exec rm {} \;

  # Cleanup the hosts file
  echo "Cleaning the virtual machine's /etc/hosts file..."
  sed -n '/# vvv-auto$/!p' /etc/hosts > /tmp/hosts
  echo "127.0.0.1 vvv.dev # vvv-auto" >> "/etc/hosts"
  echo "127.0.0.1 vvv.local # vvv-auto" >> "/etc/hosts"
  echo "127.0.0.1 vvv.localhost # vvv-auto" >> "/etc/hosts"
  echo "127.0.0.1 vvv.test # vvv-auto" >> "/etc/hosts"
  mv /tmp/hosts /etc/hosts
}

### SCRIPT
#set -xv

network_check
# Profile_setup
echo "Bash profile setup and directories."
cleanup_terminal_splash
profile_setup

network_check
# Package and Tools Install
echo " "
echo "Main packages check and install."
git_ppa_check
if ! package_install; then
  echo "Main packages check and install failed, halting provision"
  exit 1
fi

tools_install
nginx_setup
go_setup
mailhog_setup

phpfpm_setup
services_restart
mysql_setup

network_check
# WP-CLI and debugging tools
echo " "
echo "Installing/updating wp-cli and debugging tools"

wp_cli
php_codesniff

network_check
# Time for WordPress!
echo " "

wpsvn_check

# VVV custom site import
echo " "
cleanup_vvv

#set +xv
# And it's done
end_seconds="$(date +%s)"
echo "-----------------------------"
echo "Provisioning complete in "$(( end_seconds - start_seconds ))" seconds"
echo "For further setup instructions, visit http://vvv.test"

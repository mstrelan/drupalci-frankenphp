FROM drupalci/php-8.3-apache:production as drupalci

FROM dunglas/frankenphp:1-php8.3

# Prevent serving on HTTPS.
# Alternatively can set to http://localhost but this fails validation.
ENV SERVER_NAME=:80

RUN install-php-extensions \
    apcu \
    bcmath \
    gd \
    opcache \
    pcntl \
    pdo_mysql \
    yaml \
    zip

COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=drupalci /usr/local/etc/php/php.ini /usr/local/etc/php/php.ini
COPY --from=drupalci /usr/local/etc/php/php-cli.ini /usr/local/etc/php/php-cli.ini

# These are enabled in php.ini from drupalci, don't enable twice.
RUN rm \
  /usr/local/etc/php/conf.d/docker-php-ext-apcu.ini \
  /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini \
  /usr/local/etc/php/conf.d/docker-php-ext-yaml.ini

# @todo why does gettext not work?
RUN sed -i 's/extension="gettext.so"/;extension="gettext.so"/g' /usr/local/etc/php/php.ini
RUN sed -i 's/extension="gettext.so"/;extension="gettext.so"/g' /usr/local/etc/php/php-cli.ini

RUN set -xe &&\
    echo 'APT::Install-Recommends "0";' >/etc/apt/apt.conf.d/99norecommends &&\
    runDeps=" \
        bzip2 \
        curl ca-certificates gnupg2 \
        default-mysql-client postgresql-client sudo git sqlite3 \
        rsync \
        unzip \
        xz-utils \
    " &&\
    apt-get update && \
    apt-get install -y --no-install-recommends $runDeps &&\
    rm -rf /var/lib/apt/lists/*

# Install Composer, Drush
RUN curl -sSLo /tmp/composer-setup.php https://getcomposer.org/installer &&\
    curl -sSLo /tmp/composer-setup.sig https://composer.github.io/installer.sig &&\
    php -r "if (hash('SHA384', file_get_contents('/tmp/composer-setup.php')) !== trim(file_get_contents('/tmp/composer-setup.sig'))) { unlink('/tmp/composer-setup.php'); echo 'Invalid installer' . PHP_EOL; exit(1); }" &&\
    php /tmp/composer-setup.php --filename composer --install-dir /usr/local/bin &&\
    curl -sSLo /usr/local/bin/drush https://github.com/drush-ops/drush/releases/download/8.3.5/drush.phar &&\
    chmod +x /usr/local/bin/drush &&\
    /usr/local/bin/drush --version

# Install nodejs and yarn
RUN curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/nodesource.gpg &&\
    echo 'deb [signed-by=/etc/apt/trusted.gpg.d/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main' | tee /etc/apt/sources.list.d/nodesource.list &&\
    curl -sSLo /etc/apt/trusted.gpg.d/yarn.gpg.asc https://dl.yarnpkg.com/debian/pubkey.gpg &&\
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list &&\
    apt-get update &&\
    apt-get install -qy nodejs yarn &&\
    rm -rf /var/lib/apt/lists/*

# Install phantomjs, supervisor
RUN _file=phantomjs-2.1.1-linux-x86_64 &&\
    curl -sSLo /$_file.tar.bz2 https://bitbucket.org/ariya/phantomjs/downloads/$_file.tar.bz2 &&\
    tar -jxf /$_file.tar.bz2 -C / &&\
    mv /$_file/bin/phantomjs /usr/bin/phantomjs &&\
    rm -f /$_file.tar.bz2 &&\
    rm -rf /$_file &&\
    chmod 755 /usr/bin/phantomjs &&\
    apt-get update &&\
    apt-get install -y supervisor fontconfig &&\
    rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html
EXPOSE 80

ARG USER=www-data

RUN \
	# Add additional capability to bind to port 80 and 443
	setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp; \
	# Give write access to /data/caddy and /config/caddy
	chown -R ${USER}:${USER} /data/caddy && chown -R ${USER}:${USER} /config/caddy;

USER ${USER}
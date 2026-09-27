#!/bin/sh
set -e

# Prepare VIP reply routing before starting any services.
/usr/local/sbin/configure-vip-routing.sh || exit 1

PUID=${PUID:-1000}
PGID=${PGID:-1000}

if getent group nginx >/dev/null; then
    if [ "$(id -g nginx)" -ne "$PGID" ]; then
        groupmod -o -g "$PGID" nginx
    fi
else
    addgroup -S -g "$PGID" nginx
fi

if getent passwd nginx >/dev/null; then
    if [ "$(id -u nginx)" -ne "$PUID" ] || [ "$(id -g nginx)" -ne "$PGID" ]; then
        usermod -o -u "$PUID" -g "$PGID" nginx
    fi
else
    adduser -S -u "$PUID" -G nginx -H -D nginx
fi

# Create necessary directories
mkdir -p /data/custom_ssl /data/logs /data/access /data/nginx /data/letsencrypt-acme-challenge /data/nginx/default_host /data/nginx/default_www /data/nginx/proxy_host /data/nginx/redirection_host /data/nginx/stream /data/nginx/dead_host /data/nginx/temp
mkdir -p /etc/letsencrypt /run/nginx /tmp/nginx/body /var/log/nginx /var/lib/nginx/cache/public /var/lib/nginx/cache/private /var/cache/nginx/proxy_temp
mkdir -p /var/run

# Set proper permissions
chown -R "$PUID:$PGID" /data
chown -R "$PUID:$PGID" /etc/letsencrypt
chown -R "$PUID:$PGID" /run/nginx
chown -R "$PUID:$PGID" /tmp/nginx
chown -R "$PUID:$PGID" /var/cache/nginx
chown -R "$PUID:$PGID" /var/lib/nginx
chown -R "$PUID:$PGID" /var/log/nginx

spawn-fcgi -s /var/run/fcgiwrap.socket -M 766 /usr/bin/fcgiwrap &
exec "$@"

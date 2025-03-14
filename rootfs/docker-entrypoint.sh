#!/bin/sh
set -e

# Create necessary directories
mkdir -p /data/custom_ssl /data/logs /data/access /data/nginx /data/letsencrypt-acme-challenge /data/nginx/default_host /data/nginx/default_www /data/nginx/proxy_host /data/nginx/redirection_host /data/nginx/stream /data/nginx/dead_host /data/nginx/temp
mkdir -p /etc/letsencrypt /run/nginx /tmp/nginx/body /var/log/nginx /var/lib/nginx/cache/public /var/lib/nginx/cache/private /var/cache/nginx/proxy_temp
mkdir -p /var/run

# Set proper permissions
chown -R ${PUID:-1000}:${PGID:-1000} /data
chown -R ${PUID:-1000}:${PGID:-1000} /etc/letsencrypt
chown -R ${PUID:-1000}:${PGID:-1000} /run/nginx
chown -R ${PUID:-1000}:${PGID:-1000} /tmp/nginx
chown -R ${PUID:-1000}:${PGID:-1000} /var/cache/nginx
chown -R ${PUID:-1000}:${PGID:-1000} /var/lib/nginx
chown -R ${PUID:-1000}:${PGID:-1000} /var/log/nginx
chown -R ${PUID:-1000}:${PGID:-1000} /var/run

spawn-fcgi -s /var/run/fcgiwrap.socket -M 766 /usr/bin/fcgiwrap &
exec "$@"

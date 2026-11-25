# Hosting sites in the php jail

The `php` jail runs nginx and PHP-FPM 8.5 for any number of sites. haproxy
terminates TLS and passes plain HTTP to nginx on port 80 of the jail.

Everything a site needs lives in the jail's data directory, so reprovisioning
the jail keeps all sites:

| In the jail                     | On the host                         | What                          |
| ------------------------------- | ----------------------------------- | ----------------------------- |
| `/data/etc/nginx/server.d/*.conf` | `/data/php/etc/nginx/server.d/`   | one nginx vhost per site      |
| `/data/etc/php-fpm.d/*.conf`    | `/data/php/etc/php-fpm.d/`          | one PHP-FPM pool per site     |
| `/data/www/<site>`              | `/data/php/www/<site>`              | the site's files (docroot)    |
| `/data/log/<site>.*`            | `/data/php/log/`                    | the site's logs               |
| `/data/etc/nginx/fastcgi_site.conf` | `/data/php/etc/nginx/fastcgi_site.conf` | shared FastCGI settings |

The examples below add `www.example.com`. Run the commands as root on the
host. Replace the name wherever it appears.

Steps 3 and 4 copy the samples in `/data/php/etc`, whose comments explain
their settings. They end in `.sample`, so nothing loads them.

## 1. DNS

Point `www.example.com` (A and, if the toaster has one, AAAA) at the toaster's
public address, the one haproxy listens on.

## 2. The site's files

Give each site a uid:gid that no account uses in the jail or on the host:
2001 here, 2002 for the next site.

```sh
mkdir -p /data/php/www/www.example.com
chown -R 2001:2001 /data/php/www/www.example.com
```

Put the site's files there, for example by extracting an archive or with
`composer` inside the jail (`jexec php composer ...`).

## 3. A PHP-FPM pool

A pool of its own keeps a site's processes, user, `open_basedir`, resource
limits and logs apart from the other sites.

```sh
cd /data/php/etc
cp php-fpm.d/example.conf.sample php-fpm.d/www.example.com.conf
cp newsyslog.conf.d/example.conf.sample newsyslog.conf.d/www.example.com.conf
touch /data/php/log/www.example.com.php-error.log
chown 2001:2001 /data/php/log/www.example.com.php-error.log
```

In both copies, replace `example.org`, the pool's `example` name and socket,
and `2001` with the site's.

A site can share the default pool instead: skip this step and use
`fastcgi_pass php;` in the vhost. The `php` upstream is the default socket,
`/tmp/php-cgi.socket`. That pool runs as `www`, shared with every other site
that uses it, so its files are `chown 80:80`.

## 4. An nginx vhost

```sh
cd /data/php/etc/nginx
cp example.conf.sample server.d/www.example.com.conf
```

Replace `example.org` with the site's names, and the socket with its pool's.

## 5. Check and load the configuration

```sh
jexec php php-fpm -t
jexec php nginx -t -c /data/etc/nginx/nginx.conf

jexec php service php_fpm restart
jexec php service nginx reload
```

A mistake in a pool file stops PHP-FPM from restarting, for every site. Run
`php-fpm -t` first.

The site now answers on the jail's address, whatever haproxy does. This asks
the jail directly (replace the address with the jail's):

```sh
curl -sI -H 'Host: www.example.com' http://172.16.15.24/
```

A host name no vhost serves gets the default server's `404`.

## 6. Route it in haproxy

haproxy sends a request to the right jail by its host name. Add to
`/data/haproxy/etc/haproxy.conf`, in `frontend http-in` next to the other
`acl` and `use_backend` lines:

```
	acl www_example_com hdr(host) -i www.example.com example.com
	use_backend www_php if www_example_com
```

and, once, a backend for the php jail:

```
	backend www_php
	server php 172.16.15.24:80
```

Then:

```sh
jexec haproxy haproxy -c -f /data/etc/haproxy.conf
jexec haproxy service haproxy reload
```

Other sites on the same jail need only their own `acl` and `use_backend` line.

## 7. A certificate

haproxy loads every certificate in `/data/etc/tls.d`. With the Let's Encrypt
setup from `provision/letsencrypt.sh` (acme.sh on the host), issue and deploy:

```sh
acme.sh --issue -d www.example.com -d example.com -w /data/webmail/htdocs
acme.sh --deploy -d www.example.com --deploy-hook haproxy
```

The deploy hook writes `www.example.com.pem` to haproxy's certificate
directory and reloads haproxy. Renewals deploy the same way.

The webroot is the webmail jail's, because haproxy sends
`/.well-known/acme-challenge/` there. Use `--dns dns_<provider>` instead if
the name cannot be reached over HTTP.

## 8. Try it

```sh
curl -sI https://www.example.com/
```

To see what PHP is told, put this in the docroot, request it, and delete it:

```php
<?php var_dump($_SERVER['HTTPS'], $_SERVER['REMOTE_ADDR']);
```

`HTTPS` should be `"on"`.

## Logs

A site's logs are in `/data/php/log/`, under the names its vhost and pool give
them. The jail's `/etc/newsyslog.conf.d/php-sites.conf` rotates them.

## Mail from a site

The jail hands mail to the toaster's mail server (`TOASTER_MSA`, Haraka) with
`dma`, so PHP's `mail()` and applications that run `sendmail` work.

dma sends as `php@<TOASTER_MAIL_DOMAIN>` unless the application sets another
From address. Bounces for that sender go to a mailbox that does not exist, so
alias it, on the vpopmail jail (replace the domain and the destination):

```sh
jexec vpopmail /usr/local/vpopmail/bin/valias -i you@example.com php@example.com
```

SPF, DKIM and DMARC are the sending domain's: a site that sends as
`noreply@example.org` needs those records for `example.org`, whichever jail it
runs in.

## A database

The jails do not create databases for sites. On the mysql jail, as the
`root` user from `/root/.my.cnf`:

```sh
jexec mysql mysql -e "CREATE DATABASE example; \
  CREATE USER 'example'@'172.16.15.24' IDENTIFIED BY 'a-long-password'; \
  GRANT ALL ON example.* TO 'example'@'172.16.15.24';"
```

(use `mariadb` for MariaDB) and have the site connect to the host name `mysql`.

## Removing a site

Remove the vhost, the pool and the haproxy lines, reload the three services as
above, then the site's files, logs and certificate:

```sh
rm /data/php/etc/nginx/server.d/www.example.com.conf
rm /data/php/etc/php-fpm.d/www.example.com.conf
rm /data/php/etc/newsyslog.conf.d/www.example.com.conf
jexec php service php_fpm restart
jexec php service nginx reload
rm -r /data/php/www/www.example.com
rm /data/php/log/www.example.com.*
```

## Reprovisioning

`provision/php.sh` builds a new jail and keeps everything under `/data`, so the
sites above come back unchanged. It does not touch your vhosts, pools or
docroots. It rewrites `fastcgi_site.conf`, the default server and the
newsyslog file only while you have not edited them.

The php jail takes the address of the php7 jail. On a host that has one, stop
it before provisioning php (`service jail stop php7`), then reprovision the
dns jail so the address resolves to `php`.

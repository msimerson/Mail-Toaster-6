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

Two sample files, `/data/php/etc/nginx/example.conf.sample` and
`/data/php/etc/php-fpm.d/example.conf.sample`, hold the same configuration
with `example.org`. They end in `.sample`, so nothing loads them.

## 1. DNS

Point `www.example.com` (A and, if the toaster has one, AAAA) at the toaster's
public address, the one haproxy listens on.

## 2. The site's files

```sh
mkdir -p /data/php/www/www.example.com
# the PHP-FPM pool below runs as www (uid 80 in the jail)
chown -R 80:80 /data/php/www/www.example.com
```

Put the site's files there, for example by extracting an archive or with
`composer` inside the jail (`jexec php composer ...`).

## 3. A PHP-FPM pool

A pool of its own keeps a site's processes, user, `open_basedir`, resource
limits and logs apart from the other sites.

```sh
cat > /data/php/etc/php-fpm.d/www.example.com.conf <<'EOF'
[www_example_com]
user = www
group = www

listen = /tmp/php-www.example.com.socket
listen.owner = www
listen.group = www
listen.mode = 0660

pm = ondemand
pm.max_children = 8
pm.process_idle_timeout = 30s

access.log = /data/log/www.example.com.fpm-access.log
slowlog = /data/log/www.example.com.fpm-slow.log
request_slowlog_timeout = 10s
php_admin_flag[log_errors] = on
php_admin_value[error_log] = /data/log/www.example.com.php-error.log

php_admin_value[open_basedir] = /data/www/www.example.com:/tmp
EOF

# PHP writes this one as the pool's user, so the file has to be theirs...
touch /data/php/log/www.example.com.php-error.log
chown 80:80 /data/php/log/www.example.com.php-error.log

# ...and newsyslog has to recreate it as that user when it rotates it
cat > /data/php/etc/newsyslog.conf.d/www.example.com.conf <<'EOF'
/data/log/www.example.com.php-error.log	80:80	644	7	*	@T00	BCX	/var/run/php-fpm.pid	30
EOF
```

`80:80` is `www`, the pool's `user`. For a pool that runs as another user, say
`rss` (uid 1029), use that user's uid and gid in the `chown`, in the
newsyslog line, and as `user`/`group` in the pool. Without the line, the
file would be recreated as `www` after the first rotation and PHP could no
longer write its errors.

The section name (`[www_example_com]`) must be unique among all pools, and
the `listen` socket must be too.

If a site needs nothing special, it can share the default pool instead: skip
this step and use `fastcgi_pass php;` in the vhost. The `php` upstream is the
default socket, `/tmp/php-cgi.socket`.

## 4. An nginx vhost

```sh
cat > /data/php/etc/nginx/server.d/www.example.com.conf <<'EOF'
server {
	listen       80;
	server_name  www.example.com example.com;

	access_log  /data/log/www.example.com.access.log;
	error_log   /data/log/www.example.com.error.log;

	root   /data/www/www.example.com;
	index  index.php index.html;

	location / {
		try_files $uri $uri/ /index.php?$args;
	}

	location ~ \.php$ {
		include        /data/etc/nginx/fastcgi_site.conf;
		fastcgi_pass   unix:/tmp/php-www.example.com.socket;
	}

	location ~ /\.ht {
		deny  all;
	}
}
EOF
```

The jail has no IPv6 address unless the toaster does. If it has one, add
`listen [::]:80;` as well.

`fastcgi_site.conf` includes the stock FastCGI parameters and sets
`HTTPS=on` when haproxy passed `X-Forwarded-Proto: https`, so PHP applications
know they were reached over TLS. Always include it in a PHP location.

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

Each site has its own logs in `/data/php/log/`, next to the jail's default
ones:

| File                              | Written by                     |
| --------------------------------- | ------------------------------ |
| `<site>.access.log`, `<site>.error.log` | nginx                    |
| `<site>.fpm-access.log`           | the site's PHP-FPM pool        |
| `<site>.fpm-slow.log`             | the pool, for slow requests    |
| `<site>.php-error.log`            | PHP, as the pool's user, errors and warnings |
| `access_log`, `error_log`         | nginx, for hosts no site claims |
| `php-fpm.log`                     | PHP-FPM itself                 |

newsyslog rotates the site files nightly and keeps 7. Patterns in
`/etc/newsyslog.conf.d/php-sites.conf` catch `*.access.log`, `*.error.log`,
`*.fpm-access.log` and `*.fpm-slow.log`, so a new site's logs of these kinds
are picked up without more configuration, as long as they use these names.

`<site>.php-error.log` is different: PHP writes it as the pool's user, and
newsyslog recreates a rotated file as the owner named in its line. Each site
has a line of its own in `/data/php/etc/newsyslog.conf.d/<site>.conf` (step 3),
which the jail's newsyslog includes. The sample,
`/data/php/etc/newsyslog.conf.d/example.conf.sample`, shows it.

## Mail from a site

The jail hands mail to the toaster's mail server (`TOASTER_MSA`, Haraka) with
`dma`, so PHP's `mail()` and applications that run `sendmail` work. Two things
decide whether it is accepted:

- **Relay.** Haraka accepts mail for outside recipients only from clients it
  has been told about. `provision/haraka.sh` allows the addresses (IPv4 and
  IPv6) of the jails in `HARAKA_RELAY_JAILS`, by default `php wordpress`, in
  `/data/haraka/config/relay_acl_allow`. Reprovision haraka after adding the
  jail, or add the two addresses there and restart Haraka. The limit plugin
  caps what a hacked site can send.
- **The sender and its bounces.** dma sends as `php@<TOASTER_MAIL_DOMAIN>`
  unless the application sets another From address. Bounces for that sender
  go to a mailbox that does not exist, so create one, on the vpopmail jail
  (replace the domain and the destination):

  ```sh
  jexec vpopmail /usr/local/vpopmail/bin/valias -i you@example.com php@example.com
  ```

  Known problem: on a domain delivered by LMTP to Dovecot, qmail-deliverable
  gives an alias the LMTP next hop and Dovecot answers `550 5.1.1`, since no
  mailbox has the alias's name. The bounces dma generates itself hit this.
  Until that is fixed, a mailbox named `php` (`vadduser`) works where the
  alias does not (not tested).

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

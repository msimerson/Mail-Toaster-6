
## FUTURE

refer to [https://github.com/msimerson/Mail-Toaster-6/commits/master](https://github.com/msimerson/Mail-Toaster-6/commits/master)

## 2022-05

- ngnix: add configure_nginx_server_d()
- nginx: move nginx configs into /data/etc/nginx/
- nginx: put server declarations in etc/nginx/server.d
- bsd_cache: add local cache for pkg and freebsd-update
    + speed++ when managing many jails
- mt: skip fetching latest provision files when running from git
    + dev feature, easier to test feature branches
- haproxy: add send-proxy to nagios backend
- horde: broken, no more PHP 7.4, needs attention
- host: support git updates for /usr/ports
- rainloop: update PHP to 8.1
- roundcube: install plugins: contextmenu html5_notifier larry
- mediawiki: bump ver to 1.39, PHP version to 8.2

## 2021-q3

- rename vim-console -> vim
- unifi: install v5 -> v6
- unifi: preinstall snappyjava (dep) (#485)


## 2021-q2

- dovecot: improve grep regex that detects SQL conversion (#484)
- Disable redundant backups in jails (#480)
- Fix jail.conf updating for common-prefixed jail names (#479)
+ clamav: if installing nrpe, also configure it
+ knot: install knot v3, add NRPE install
+ php7: v7.2 -> v7.4
- rspamd: add env.RSPAMD_SYSLOG to control log dest (#477)


## 2021-q1

- Fix timezone detection (#472)
- Fixed roundcube php.ini customizations (#473)
- Fix service nginx restart to run in staged jail (#475)
- Fix php_fpm restart to run in staged jail (#474)
- wp: create link within stage jail (#470)
- cannot create outside it as the path does not exist
* mt: mysql defaults to enabled #468
* rainloop: update PHP to 7.3, add simplexml
* roundcube: update PHP to 7.4
* test: update runner to FreeBSD 12.2
* squirrelmail: php73 -> 7.4
* dovecot: handle quota value of NOQUOTA
* gitlab: re-enable sqwebmail build
* lighttpd: fixup state_dir
* spamassassin: install sample .cf files
* mysql: use .mysql_secret file to detect (re)install
* rainloop: fix include add when version has patch suffix
* spama: default RELAY_COUNTRY to off unless MM License
* base: fix cron job logic
* es: fix typo in path


## 2020-q4

- dovecot: passdb/userdb switch from vpopmail -> sql (#467)
- es: install beats for cluster monitoring (#466)
- vpopmail: fix ipv6 config for lighttpd (#465)
- clamav-unofficial: update to 7.2.1, nsd default config (#464)
+ whmcs: fix typo, update PHP to 7.4 #463
+ clamav: update unofficial to 7.2
+ nsd: install default nsd.conf when staging
+ haraka: update node 10 -> 12
- dns: add local-zone: typetransparent declaration (#460)
- mongo: enable sysvipc #462
- GitHub actions replace travis #461
- port mongodb.conf is now suffixed with sample #459
- mongo: check & set vm.max_wired if needed #457
* consistent use of `_j`


## 2020-q3

- gitlab: remove geoip build (now requires account creds)
- vim: change default theme to be more readable (#454)
* roundcube: curl needs to send init request with proxy proto #453
* base: add libxml2 to auto-security-update packages
* vmware: update version to 12.1p2
* host: enable pkg audit in jails
* mt: run pkg audit on host for newly provisioned jails
* base: auto-upgrades, move list into variable, so it can be more easily updated with CLI tools

- haproxy: replace deprecated reqirep with http-request (#450)
* haraka: install haraka-plugin-dmarc-perl
* mongodb: install version 4.2 (was 3.4) #449

## 2020-q2

- rspamd: bind to IPv4 and IPv6
+ rainloop: fix version detection #443
+ squirrelcart: fix image location
+ wordpress: php 7.2 -> 7.4
+ elastic: version 6 -> v7
- change rspamd worker bind socket to ipv4 (#442)
- wp: add php-json module (#441)

## 2020-03

- clamav: install gtar, for unofficial
- borg: use python 37

## 2020-02

- haproxy/nginx: use proxy protocol (was x-forwarded-for) (#394)
- haproxy: support building against openssl 1.1.1 (adds TLS 1.3 support)
- nginx: update newsyslog path to nginx logs (#440)
+ mysql: better "already installed" detection
- geoip: prompt for license key
- geoip: add support for geoipupdate
- mysql: remove extra quotes (#438)
- clamav: update unofficial to 7.0.1 (#436)
- Rspamd: disable syslog logging (broken upstream) (#435)
+ rspamd: disable syslog until unbroken upstream
+ base: add pkg & sudo to list of ports to autoupgrade
- Mariadb upgrade to 10.4 #434


## 2020-01

- raise mt6-update to keep in scope (#431)
* mysql: quote the password, JIC
* whmcs: create basic location config if missing

- mysql provision with root password (#430)
+ mysql: on new provision, store and set root password
* mysql: use include/mysql functions everywhere
* remove unnecessary quotes
* dspam: test on port 2424 where dpsam now listens
* roundcube: if smtp_port is 587, update to 465
* spamassassin: SQL fixes
* mt.sh: change perms to 600 on m-t.conf
* mysql: prefer .my.cnf and .mylogin.cnf over CLI password
- geoip: install node 12 (was 8)


## 2019-12

- mt: when enabled, add automount config for ports and/or pkg cache (#428)
- dcc: update for new path (port change) (#427)
- add MT version check (#426)
- postfix + dkim improvements (#424)
- postfix: add default config for dkim (#423)
- Update issue templates
- promote postfix to VM list (#421)
* get_jail_ip(6) will try DNS now, for local/custom build scripts
* add TOASTER_MSA, to choose a local MSA other than haraka
- add nagios & borg provision scripts #420
* clamav: update unofficial to 6.1.1 #419
* haraka: improve avg provision logic
* test: update freebsd VM version
* shellcheck: add .shellcheckrc


## 2019-11

- sqwebmail: remove pkg install (no longer built)
- add build scripts for Ghost & Jekyll (#418)
- dmarc: use correct path for rc.local (#417)
- base: update renamed periodic.conf setting (#416)
- tinydns: provision IPv6 tinydns/axfrdns servers (#415)
- add DEVELOP.md #414


## 2019-10

- spamassassin: set port build options
- dcc: set the port build options #411
- rename provision-* files provision/*.sh #410
- rename provision files with - to _ #409
- grafana: install v6 (was v5) #409


## 2019-09

- ES: updates for v6 install #408
- move provision files into provision dir #406
- dmarc: add periodic receive task #405
- mediawiki: remove php suffix from port name #405
- mysql: add mysql_optfile to /etc/rc.conf #405
- rainloop: fail build if port install fails #405
- roundcube: if mysql connect fails, warn and proceed #405
- rspamd: update dcc plugin config syntax #405
- squirrelmail: create missing /data/pref directory #405
- whmcs: update PHP to v7.2 #405
- wordpress: fail build if port install fails #405


## 2019-08

- haraka: install node 10 (was 8) #404
- haraka: only enable AVG if the jail is running #404
- clamav: update unofficial version  5.6.2 -> 6.1.0 #404
- mysql: install when any MYSQL option enabled #404
- spamassassin: remove dcc package install #404
- dcc: port install (was pkg), path to dcc_conf #404
- unifi: update to mongo 3.6 #402

## 2019-07

- fix: python not found during compilation #400

## 2019-05

- haraka: install node 10 (was 8) #399
- haraka: only enable AVG if the jail is running #399
- elastic: make upgrading smoother #399

## 2019-04

- haraka: install python2 (required by nan) #398
- add Mail::Dmarc service #397

## 2019-03

- haraka: enable spf [relay]context=myself #396
- dovecot: update comments in config #395
- rainloop & roundcube: use port 465 for submission #393

## 2019-02

- squirrelmail: use /data/pref for pref storage (same as migration docs, other uses) #392
- spamassassin: install p5-GeoIP2 (was p5-Geo-IP) #391
- horde: update to PHP 7.2 #385

## 2018-12

- nictool: skip SQL setup on upgrade #384
- update mysql version 5.6 -> 5.7 #383
- influx: give some more time to start #382
- haraka: update plugin names of geoip, p0f, qmail-deliv #381
- clamav: update unofficial 5.4.1 -> 5.6.2 #374
- haproxy: add grafana support #374
- roundcube: apply customizations to php.ini (needs testing) #374
- webmail: show/hide services based on availability, fixes #261 #374
- webmail: back up index.html and install new one #374
- webmail: remove recursive checks #374
- haproxy: add rule for vqadmin #374
- rainloop: chown after last file installed #374
- Create folder for sphinx and use mariadb client for vpopmail #373

## 2018-11

- host: check that timezone is set #370
- update wordpress using recipes #367
- influx: only create dirs when missing #366
- unifi: specify mongodb version (port renamed) #366

## 2018-10

- use ipinfo.io instead of freegeoip (deprecated) #365

## 2018-09

- mediawiki: update to 1.31 #363

## 2018-08

- when enabled, install qmHandle in vpopmail jail #362
- haproxy: remove -devel (1.8 is released now) #361
- roundcube: update path to nginx mime.types file #361
- nginx: enable gzip compression #361
- roundcube: add ROUNDCUBE_DEFAULT_HOST option #359
- vpopmail: quota_report: update company name #359
- vpopmail: quota_report: send to users by default #359
- vpopmail: remove -v option (only log errors) #359
- rspamd: store redis settings in redis.conf #358
- mariadb: Upgrade to current stable 10.3 #357
- dhcp: update to version 4.4 #356
- grafana: fix typo mdkir #356
- perl ports build fix #356

## 2018-07

- squirrelmail: php 72 mcrypt -> pecl-mcrypt #355

## 2018-06

- update roundcube & squirrelmail due to -phpVV rename #354
- roundcube: enable managesieve plugin #352
- create /etc/ssl/private when missing #353
- dovecot: update config for 2.3 #351
- fix sed match to enable newsyslog #350
- haproxy: fix for OCSP stapling #349
- shellcheck: disable 2038 #348
- fix PHP timezone setting #347

## 2018-04

- Fix for new naming of pear and pecl packages #341
- grafana: install v5 #343
- narrow IP6 host mask #340

## 2018-03

- es: add v6 support #337
- Mariadb update to 10.2 #334

## 2018-02

- Fix vimrc path and overwrite default vimrc #335
- recipes for influxdb, statsd, telegraf #330
- install just grafana #329
- spamassassin: disable sought rules #328
- Haraka: store git co of Haraka to /root (vs /tmp) #327
- vpopmail: more reliably add vpopmail settings when missing #326
- postfix: preserve /etc/aliases #326

## 2018-01

- smf: add PHP filter module #325
- haraka: assure bash is installed (if not in base) #323
- port rename vim-lite -> vim-console #321
- geoip: work around npm attempts to be clever #321
- mediawiki: working php7 install support #321
- smf: update smf version to 2.0.15 #321
- squirrelcart: php 7.2 -> 7.1, for now #321
- squirrelcart: preserve store logo #321
- nsd: newly added #321
- knot: preserve sys users & start sshd #321
- nictool: preserve system users #321
- es: update where mem settings are set #321
- haproxy: install -devel with HTTP2 support #321
- mt.sh: consistently quote strings in case statement #321
- monitor: configure nrpe3 now #321
- postfix + opendkim #320
- haraka: Helo checks error in logging #317

## 2017-12

- Nrpe3 and PHP 7.2 updates #316
- use PHP 7.2 where supported #313
- fix unbound TXT record quoting syntax #311
- letsencrypt: update htdocs dir to match nginx config #310
- haraka: enable newsyslog (log rotation) #309
- geoip: install npm3 (and node 6) to get node LTS #308
- haproxy: fix condition that chooses libressl option #308
- haraka: install python meta port #308
- roundcube: fix sed command for updating smtp_server #308
- tinydns: test with TOASTER_HOSTNAME if example.com not in data file #308
- dovecot: if sieve not in local.conf, do not try compiling sieve #308
- haraka: skip LMTP attempts, until Haraka outbound is fixed #308
- geoip,haraka: install using npm-node8 #308
- geoip: restrict to npm 4 since 5 is unstable #307
- rspamd: only enable phishing when RAM > 4GB #305

## 2017-11

- mysql ipv6 grants #299
- generate TLS certs needed for sha256 password #297
- dns: extend SPF policy to local nets #296
- enable config for PUBLIC_IP4 and PUBLIC_IP6 #295
- show URL for FreeBSD package when downloading #295
- base: create dhparam.pem if missing (for upgrades) #295
- vpopmail: do not leave .bak file in periodic dir #295
- qmail: add comment when updating control/me #294
- dns: configure private DNS for TOASTER_HOSTNAME #294
- haraka: if config/me does not exist, write TOASTER_HOSTNAME to it #294
- dns: add SPF records #294

## 2017-10

- Curl not installed and curl logging reduction #293
- configure nginx proxy for ipv6 #291
- net mgmt: make use of NRPE/munin config settings #289
- syslogd: allow from ${JAIL_IP6}/64 #286
- monitor: preserve munin data files, munin.conf #281
- monitor: use CGI method for lighttpd (reduce load) #281
- dovecot: compile dovecot pigeonhole so they are not out of sync #281

## 2017-09

- nginx: add lets encrypt rule #273
- dovecot: add trash plugin to protocol imap #273
- haraka: install from git #268
- letsencrypt: install socat, the next version of acme.sh requires it #267
- haraka: skip installing dev deps #267
- install sshguard w/pf config #266


## 2017-08

- improve elasticsearch 5 install reliability
- IPv6 support #257
    - assign random IPv6 network when installing
    - add IPv6 address to all jails when created
    - add forward and reverse DNS for IPv6 addrs to local DNS
    - update /etc/pf.conf when no IPv6 rules
    - update jails to listen on IPv6: clamav, dovecot, nginx, haproxy, haraka, lighttpd (webmail, qmailadmin, sqwebmail
- add TOASTER_ORG_NAME setting
- add DCC jail (#259)
    - can be run by spamassassin, rspamd, and Haraka
    - add config for rspamd and update config for spamassassin
- add_pf_portmap: dynamically add PF rules when jails installed
- dovecot:
    - enable LMTP service
    - add sieve learning scripts for rspamd & spamassassin
- rspamd:
    - add config for dcc
    - enable phishing
    - set a randomly generated rspamd password
- mailfilter: save to Junk (was Spam), adopt RFC behavior
- mail-toaster.sh: use addr family to narrow ifconfig output
- beef up TLS security in dovecot & haproxy #245
- add knot dns build #247
- add gitlab worker and master #246, #248
- update elasticsearch from v2 -> v5 #243


## 2017-06

- add jails to startup list when created #241
- add mongodb #232
- configure lighttpd to log real IP (trust haproxy) #230
- add unifi jail #227


## 2017-02

- add grafana jail #211
- enable innodb file per table #208
- provision Horde Groupware #203
- after successful LE cert install, update haproxy ssl crt dir #199
- update rspamd to use of our Redis server #192


## 2017-01

- add provision-squirrelcart #184
- add Ntimed support #183
- add provision-whmcs #182
- vpopmail: consolidate build into include/vpopmail #181
- add provision-smf #170
- reduce redundant PHP & nginx code with include #168
- add provision-mediawiki #167


## 2016-12

- use geoiplookup to set SSL cert default location #164
- zsh shell and vimrc #158
- base: add decent configs for csh shells #157
- add rainloop webmail #144
- add letsencrypt support #135
- add tinydns support #142


## 2016-11

- now every jail has a data FS #134
- haraka: enable haraka.log rotation #126
- add dhcp support #110
- install and enable toaster-quota-report #103
- mysql: disable innodb double writes (redundant on ZFS) #101
- update clamav unofficial to 5.4.1 #100
- install haraka plugins on data fs #95
- spamassassin: add data fs #92


## 2016-10

- dovecot: add /data dir
- nictool: add provision script
- sqwebmail: add provision script
- enable haraka-plugin-log-reader
- avg: preserve signatures across deployments #89


## 2016-09

- make config persistent in mail-toaster.conf
- haraka: persistent data dir
- provision-memcached
- provision-sphinxsearch
- mysql: add option for MariaDB
- provision-php7
- provision-elasticsearch


## 2016-02

- haproxy: add data dir


## 2016-01

- add provision-nginx, minecraft, joomla
- mysql: preserve my.cnf across provisions
- base: update it


## 2015-12-29

- ssmtp: forward cron/root emails to vpopmail jail
- dovecot: raise TLS encryption requirements
- haproxy: remove RC4 ciphers from cipher list
- vpopmail: configure qmail local aliases
- base
    - install periodic.conf
    - disable adjkerntz & atrun
    - disable passwordless root account
- haraka: add limit plugin


## 2015-12-21

- add clamav data fs (so downloaded dbs persist)
- provisioning jails share pkg cache with host
- calc 4th IP octet based on start
- optionally install nrpe agent


## 2015-12-13

- provision scripts for redis & geoip


## 2015-12-07

- switch to lo1 for jail networking (was lo0)
- switch from 127.* IPs to 172.16.* IPs.


## 2015-12-05

- provision script for host
- data fs for webmail


## 2015-12-02

- provision scripts for vpopmail, dovecot, and persistent data filesystems


## 2015-11-29

- provision scripts for haproxy, webmail, squirrelmail, roundcube, haraka
- provision scripts for spamassassin, avg


## 2015-11-28 - GitHub Project

- consolidating the instructions into functions
- mail-toaster.sh, config loading & shared functions
- provision scripts for base, dns, mysql, clamav, rspamd jails


## 2014-02-16 - Birth

Born as a set of instructions on the TNPI wiki

## 2017-09

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
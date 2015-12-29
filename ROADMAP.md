# Build support

- [x] clamav unofficial
- [ ] set rspamd password (to what? prompt?)
- [ ] IPv6 support
- [ ] when MYSQL=1, configure
    - [ ] spamassassin mysql user prefs
    - [ ] squirrelmail SASQL plugin
    - [ ] roundcube [sauserprefs](https://plugins.roundcube.net/packages/johndoh/sauserprefs)
- [ ] dovecot sieve
    - [ ] [roundcube plugin sieverules](https://plugins.roundcube.net/packages/johndoh/sieverules)

# index page login

* After successful login with postmaster@`local_domain`, enable additional privileges.

# Logs

* Smarter log handling ideas:
    * centralized logging via syslog on host
    * feed logs into elasticsearch

# Reduced footprint

- [ ] disable cron in jails where not beneficial


# simpler mail routing

- [ ] LMTP delivery directly to dovecot
    - [ ] deprecate qmail
    - [ ] sieverules instead of maildrop + filter
    - [ ] 

# add firewall rules with the jails they serve

- [ ] host adds NAT for all jails
- [ ] haraka jail adds ports 25, 464, & 587
- [ ] webjail jail adds ports 80, 443
- [ ] dovecot jail adds ports 110, 143, 993, 995

# Upgrade handling
 
- [ ] run mysql_upgrade as new jails are deployed
- [ ] 

#!/usr/local/bin/perl

# check_portaudit Nagios plugin for monitoring FreeBSD ports
# Copyright (c) 2014 by Matt Simerson
# Copyright (c) 2007 by Nathan Butcher

# Install like this:
# fetch -o /usr/local/libexec/nagios/check_portaudit http://www.tnpi.net/computing/freebsd/check_portaudit.pl

# Released under the GNU Public License
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# Version: 0.6.0
# History:
#   Jun 07, 2007 - 0.5.1 - Authored by Nathan
#   Jan 11, 2014 - 0.6.0 - added PKGNG support, Matt
#                        - refactored into subs, easier to maintain
#   Jul 11, 2014 - 0.6.1 - raised default DB age 7 -> 14

# Usage:   check_portaudit <command> <display> <database age limit (days)>
# Example: check_portaudit security show 3
#
# COMMANDS:-
# security - runs 'pkg audit' and displays vulnerable packages
# updates - run 'pkg version' and lists packages which could be updated
#
# You can choose whether to show or not show vulnerable/old packages by name
# The message line may be incredibly huge if you have a lot of old/vulnerable
# packages
#
# DISPLAY:-
# show - shows all packages by name when WARNING
# hide - do not show package names. Simply display number of packages
#
# The database age limit option will produce CRITICAL errors by default if
# either the portaudit database or the ports tree is older than a certain
# number of days. If this argument is not specified, the default is 14 days.
#
# WARNINGS will be delivered should old/vulnerable packages be discovered
# otherwise you will get an OK result.
#
# It is STRONGLY recommended that you update the portaudit database and portsdb
# regularly from crontab. This will prevent the databases from ever going
# out of date. This plugin cannot do this job because doing so would require
# super-user privileges.

use strict;
use warnings;

my %ERRORS=('DEPENDENT'=>4,'UNKNOWN'=>3,'OK'=>0,'WARNING'=>1,'CRITICAL'=>2);
my $state="UNKNOWN";
my $msg="FAILURE";
my $perfdata="";

#################LOCATION OF IMPORTANT FILES#######################
# pkg (PKGNG)
my $pkg='/usr/local/sbin/pkg';  # prefer the (likely) newer port
$pkg = '/usr/sbin/pkg' if (!-x $pkg && -x '/usr/sbin/pkg');
my $pkgauditloc="/var/db/pkg/vuln.xml";

# legacy portaudit
my $portaudit="/usr/local/sbin/portaudit";
my $portauditdb="/var/db/portaudit/auditfile.tbz";
my $portversion="/usr/local/sbin/portversion";
my $portsdb="/usr/ports/" . `ls /usr/ports | grep .db | head -n1`;
chomp $portsdb;
###################################################################

my $pkgng = -x $pkg ? 1 : 0;

if ($^O ne 'freebsd') {
    print "This plugin is designed for FreeBSD\n";
    exit $ERRORS{$state};
}

if ($#ARGV+1 !=2 && $#ARGV+1 != 3) {
    print "Usage: $0 <security/updates> <show/hide> <db age limit>\n";
    exit $ERRORS{$state};
}

my $command=$ARGV[0];
if ($command ne "security" && $command ne "updates") {
    print "Commands are : security, updates\n";
    exit $ERRORS{$state};
}

my $show_pkgs=$ARGV[1];
if ($show_pkgs !~ /(show|hide|noshow)/i) {
    print "Display commands are : show, hide\n";
    exit $ERRORS{$state};
}

my $dbage= $ARGV[2] || 14;

###common variable declaration
my $msglist='';
my $packcount=0;
my $pkgtype= $command eq 'updates' ? 'obsolete' : 'vulnerable';

### security or updates

if ( $pkgng ) {
    check_ng_vuln_age();
    $command eq 'updates' ? get_pkg_version() : get_pkg_audit();
}
else {
    check_db_age();
    $command eq 'updates' ? get_portversion() : get_portaudit();
};

### prepare to report vulnerable packages
if ($packcount == 0) {
    $state = 'OK';        # no old/bad packages
}
else {
    $state = 'WARNING';   # old/bad packages detected

    ### to display or not display packages, that is the question
    if ($show_pkgs eq 'show') {
        $msglist = "- {$msglist } ";
    } else {
        $msglist='';
    }
}

### take this message to Nagios
$msg = sprintf "%s : %s %s %s", $command, $packcount, $pkgtype, $msglist;
$perfdata = sprintf "%s=%d;1;;0;", $pkgtype, $packcount;
print $state, " ", $msg, "|", $perfdata,"\n";
exit ($ERRORS{$state});


sub check_ng_vuln_age {
    my $vuln_stat;
    # newest version of 'pkg audit' use this
    if ( -f '/var/db/pkg/vuln.xml' ) {
        $vuln_stat = (stat('/var/db/pkg/vuln.xml'))[9];
    }
    elsif ( -f '/var/db/pkg/auditfile' ) {
        # the first versions of 'pkg audit' used this one
        $vuln_stat = (stat('/var/db/pkg/auditfile'))[9];
    };

    if (($dbage*86400) < (time - $vuln_stat)) {
        $state="CRITICAL";    ### report if database is old
        print "$state Vulnerability list is out of date! Update with 'pkg audit -F'\n";
        exit $ERRORS{$state};
    };
};

sub check_db_age {
    my $dbloc = $command eq "security" ? $portauditdb : $portsdb;

    ### sanity check and check timestamp of portaudit database
    my $dbstat = (stat("$dbloc"))[9];
    unless ( $dbstat ) {
        print "$dbloc database does not exist! Please update database\n";
        exit $ERRORS{$state};
    }

    my $db_max_days = $dbage * 86400;
    my $db_age_days = time - $dbstat;

    ### calculate the age of the database and error report an old one
    if ($db_max_days < $db_age_days) {
        $state="CRITICAL";    ### report if database is old
        print "$state Database is out of date! Please update database\n";
        exit $ERRORS{$state};
    };
};

sub get_pkg_audit {
    if (! open STAT, "$pkg audit| grep vulnerable|") {
        print ("$state '$pkg' command returns no result!\n");
        exit $ERRORS{$state};
    }

    my %seen = ();
    while(<STAT>) {
        chomp;
        my ($pack) = /^(\S+)\s/;
        next if $seen{$pack}; # only add to the list once
        $msglist .= " $pack";
        $seen{$pack}=1;
        $packcount=$packcount+1;
    }
    close (STAT);
};

sub get_pkg_version {
    if (! open STAT, "$pkg version -v | grep needs|") {
        print ("$state '$pkg' command returns no result!\n");
        exit $ERRORS{$state};
    }

    my %seen = ();
    while(<STAT>) {
        chomp;
        my ($pack) = /^(\S*?)\s/;
        next if $seen{$pack}; # only add to the list once
        $msglist .= " $pack";
        $seen{$pack}=1;
        $packcount=$packcount+1;
    }
    close (STAT);
};

sub get_portaudit {

    ### sanity check existence of binary
    unless ((stat("$portaudit"))[9]) {
        print "$portaudit executable not found! Please install\n";
        exit $ERRORS{$state};
    }

    ### run portaudit
    if (! open STAT, "$portaudit | grep Affected|") {
        print ("$state '$portaudit' command returns no result!\n");
        exit $ERRORS{$state};
    }

    my %seen = ();
    while(<STAT>) {
        chomp;
        my ($pack) = (/^Affected package\:\s+(\S+)/);
        next if $seen{$pack}; # only add to the list once
        $msglist.= " $pack";
        $seen{$pack}=1;
        $packcount=$packcount+1;
    }
    close (STAT);
};

sub get_portversion {

    ### sanity check existence of binary
    unless ((stat("$portversion"))[9]) {
        print "$portversion executable not found! Please install\n";
        exit $ERRORS{$state};
    }

    ### run portaudit
    my $cmd = "$portversion -v | grep needs";
    if (! open STAT, "$cmd|") {
        print ("$state '$cmd' command returns no result!\n");
        exit $ERRORS{$state};
    }

    my %seen = ();
    while(<STAT>) {
        chomp;
        my ($pack) = (/^(\S+)\s+/);
        next if $seen{$pack}; # only add to the list once
        $msglist .= " $pack";
        $seen{$pack}=1;
        $packcount=$packcount+1;
    }
    close (STAT);
};
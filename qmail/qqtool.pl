#!/usr/local/bin/perl
use strict;
use warnings;

use vars qw/ $opt_a $opt_h $opt_q $opt_s $opt_v $remotes $locals /;

use English;
use File::Basename;
use Getopt::Std;
use Pod::Usage;

getopts('a:h:q:s:v');

print "           Qmail Queue Tool   v6.0.0\n\n";
print "Only the root user has permission to read the queue.
You are not root, goodbye!\n"
and exit 0 if $UID != 0;

pod2usage() if ! $opt_a;

# Make sure the qmail queue directory is set correctly
my $qdir = '/var/qmail/queue';
exit 0 unless -d $qdir;

# if a queue is specified, only check it.
print "$0, getting list of messages in delivery queues..." if $opt_v;
if ($opt_q) {
    $opt_q eq "remote" ? $remotes = messages_get("remote")
  : $opt_q eq "local"  ? $locals  = messages_get("local")
  : die "invalid queue selected!";
}
else {
    # otherwise, check both queues
    $remotes = messages_get("remote");
    $locals  = messages_get("local");
    print "\n";
}

print "done.\n" if $opt_v;

  $opt_a eq "list"   ? messages_list  ( $remotes, $locals )
: $opt_a eq "delete" ? messages_delete( $remotes, $locals )
: $opt_a eq "expire" ? messages_expire( $remotes, $locals )
: pod2usage()
;

exit 0;

# -----------------------------------------------------------------------------
#       Subroutines. No user servicable parts below this line!                #
# -----------------------------------------------------------------------------

sub message_delete {
    my ( $tree, $id ) = @_;

    print "Deleting message $id...";

    # for each message id, check each of the queues and remove it.
    if ( -f "$qdir/local/$tree/$id" ) {
        print "\t deleting file $qdir/local/$tree/$id\n" if ($opt_v);
        unlink "$qdir/local/$tree/$id" or die "couldn't delete: $!";
    }

    if ( -f "$qdir/remote/$tree/$id" ) {
        print "\t deleting file $qdir/remote/$tree/$id\n" if ($opt_v);
        unlink "$qdir/remote/$tree/$id" or die "couldn't delete: $!";
    }

    if ( -f "$qdir/info/$tree/$id" ) {
        print "\t deleting file $qdir/info/$tree/$id\n" if ($opt_v);
        unlink "$qdir/info/$tree/$id" or die "couldn't delete: $!";
    }

    if ( -f "$qdir/mess/$tree/$id" ) {
        print "\t deleting file $qdir/mess/$tree/$id\n" if ($opt_v);
        unlink "$qdir/mess/$tree/$id" or die "couldn't delete: $!";
    }

    if ( -f "$qdir/bounce/$id" ) {
        print "\t deleting file $qdir/bounce/$id\n" if ($opt_v);
        unlink "$qdir/bounce/$id" or die "couldn't delete: $!";
    }

    print "done.\n";
}

sub messages_delete {

    my $svc_dir = '/var/qmail/control/qmail-smtpd';
    if ( ! -d $svc_dir ) {
        warn "The service directory does not exist: $svc_dir";
        return;
    }
    warn "checking control dir $svc_dir, ok";

    my $r = send_signal('-d');
    die "qmail-send wouldn't die!\n" if ($r);

    # we'll get passed an array of the local, remote, or both queues
    foreach my $q (@_) {
        foreach my $hash (@$q) {
            my $header = headers_get( $hash->{'tree'}, $hash->{'num'} );

            unless ($opt_s) {
                message_delete( $hash->{'tree'}, $hash->{'num'} );
                next;
            }

            if ($opt_h) {
                if ( $header->{$opt_h} =~ /$opt_s/ ) {
                    message_delete( $hash->{'tree'}, $hash->{'num'} );
                }
            }
            else {
                foreach my $key ( keys %$header ) {
                    if ( $header->{$key} =~ /$opt_s/ ) {
                        message_delete( $hash->{'tree'}, $hash->{'num'} );
                    }
                }
            }
        }
    }

    send_signal('-u');
}

sub message_expire {
    my ($file) = @_;

    # set $ago to 8 days old.
    my $ago = time - 8 * 24 * 60 * 60;

    # alter the timestamp of the file to 8 days ago.
    utime $ago, $ago, $file;
    print "Expired $file\n";
}

sub messages_expire {

    foreach my $q (@_) {
        foreach my $hash (@$q) {
            my $header = headers_get( $hash->{'tree'}, $hash->{'num'} );
            my $id     = "$hash->{'tree'}/$hash->{'num'}";

            unless ($opt_s) {
                message_expire("$qdir/info/$id");
                next;
            }

            if ($opt_h) {
                if ( $header->{$opt_h} =~ /$opt_s/ ) {
                    message_expire("$qdir/info/$id");
                }
            }
            else {
                foreach my $key ( keys %$header ) {
                    if ( $header->{$key} =~ /$opt_s/ ) {
                        message_expire("$qdir/info/$id");
                    }
                }
            }
        }
    }

    system "qmailctl doqueue";

    print "NOTICE: Expiring the messages does not remove them from the queue.
	It merely alters their expiration time. The messages will be removed from
	the queue after qmail attempts to deliver them one more time.
	
	I've already told qmail to start that process so be patient while qmail
	is processing the queue. This might be a good time to check the value of
	/var/qmail/control/concurrencyremote and verify its value is reasonable
	for your site.\n\n";

=head2	Message Expiration

Expiring messages does not remove them from the queue.  It merely alters their expiration time. The messages will be removed from the queue after qmail attempts to deliver them one last time.

=cut

}

sub messages_list {

    QUEUE:
    foreach my $queue (@_) {

        # skip to the next queue if it's empty
        next QUEUE if ! $_[0];

        #print "message $queue starting\n";
        foreach my $hash (@$queue) {

            #use Data::Dumper; print Dumper($hash);
            my $header = headers_get( $hash->{'tree'}, $hash->{'num'} );
            my $id = "$hash->{'tree'}/$hash->{'num'}";
            print "id: $id\n";

            unless ($opt_s) {
                message_print( $id, $header );
                next;
            }

            if ($opt_h) {
                message_print( $id, $header )
                  if ( $header->{$opt_h} =~ /$opt_s/ );
            }
            else {
                foreach my $key ( keys %$header ) {
                    if ( $header->{$key} =~ /$opt_s/ ) {
                        message_print( $id, $header );
                        exit;
                    }
                }
            }
        }
    }
}

sub message_print {

    my ( $id, $header ) = @_;

    print "message # $id ";
    print "To:       $header->{'To'}\n";
    print "From:     $header->{'From'}\n";
    print "Subject:  $header->{'Subject'}\n";

    if ($opt_v) {
        if ( $header->{'CC'} ) {
            print "CC:        $header->{'CC'}\n";
        }
        print "Date:      $header->{'Date'}\n";
        my $rp = `head -n1 "$qdir/info/$id"`;
        print "Return Path: $rp\n";
    }

    print "\n";
}

sub headers_get {

    my ( $tree, $id ) = @_;
    my %hash;

    my ($FILE, $header);

    # a better way to read in the headers
    # from http://perl.plover.com/lp/Spam.html
    if ( open $FILE, '<', "$qdir/mess/$tree/$id" )
    {
        local $/ = "";     # enable localized slurp mode
    	$header = <$FILE>; # read in the message headers
    	undef $/;          # reset it back to normal
    	#$body = <STDIN>;
    };

    foreach my $line ( split /\n/, $header ) {
        #print "$line\n"; sleep 1;
        if ( $line =~ /^([a-zA-Z\-]*):\s+(.*?)$/ ) {
            print "header: $line\n" if $opt_v;
            $hash{$1} = $2;
        }
        else {
            print "body: $line\n" if $opt_v;
        }
    }
    return \%hash;
}

sub messages_get {

    my ($qsubdir) = @_;
    my $queue = "$qdir/$qsubdir";    # /var/qmail/queue/[local|remote]

    my ( @messages, $up1dir, $id, $bucket, $queu );

    unless ( -e $queue ) {
        print "ERROR: queue $queue does not exist!\n";
        return 0;
    }
    unless ( -d $queue ) {
        print "ERROR: queue $queue is not a directory!\n";
        return 0;
    }

    unless ( -r $queue ) {
        print "ERROR: queue $queue is not readable by you!\n";
        return 0;
    }

    # eache queue has "buckets" within it that we need to iterate over
    foreach my $queue_buckets ( get_dir_files( $queue ) ) {

        # within each bucket is files that contain the email address we
        # are trying to deliver to.

        foreach my $file ( get_dir_files( $queue_buckets ) ) {

            # id is the message id
            ($id, $up1dir)      = fileparse($file); chop $up1dir;
            ($bucket, $up1dir)  = fileparse($up1dir); chop $up1dir;
            ($queu,   $up1dir)  = fileparse($up1dir);

            print "messages_get: id: $id\n" if ($opt_v);

            my %message_details = (
                num  => $id,
                file => $file,
                tree => $bucket,
                queu => $queu
            );
            push @messages, \%message_details;

            print "messages_get: file   : $file\n" if ($opt_v);
        }
    }
    my $count = @messages;
    print "$qsubdir has $count messages\n";

    return \@messages;
}

sub send_signal {
    my $signal = shift;

    my $svc    = '/usr/local/bin/svc';
    my $svstat = '/usr/local/bin/svstat';

    my $qcontrol = '/var/qmail/supervise/qmail-send';

    if ( ! $qcontrol) {
        warn "the service directory $qcontrol is missing! Giving up.";
        return;
    }

    if ($UID != 0) {
        warn "Only root can control supervised daemons, and you aren't root!";
        return;
    };

    # send qmail-send a TERM signal
    system "$svc $signal $qcontrol";

    # loop up to a hundred seconds waiting for qmail-send to exit
    foreach my $i ( 1 .. 100 ) {
        my $r = `$svstat $qcontrol`;
        chomp $r;
        if ( $r =~ /^.*:\sdown\s[0-9]*\sseconds/ ) {
            print "Yay, we're down!\n";
            return;
        }
        elsif ( $r =~ /supervise not running/ ) {
            print "Yay, we're down!\n";
            return;
        }
        else {

            # if more than 10 seconds passes, lets kill off the qmail-remote
            # processes that are forcing us to wait.

            if ( $i > 10 ) {
                system "killall qmail-remote qmail-send";
            }
        }
        sleep 1;
    }
    return 1;
}

sub get_dir_files {
	my $dir = shift;
	my @files;

    opendir D, $dir or do {
        warn "couldn't open $dir: $!";
        return;
    };

    while ( defined( my $f = readdir(D) ) ) {
        next if $f =~ /^\.\.?$/;
        push @files, "$dir/$f";
    }

    closedir(D);

    return @files;
}

1;
__END__
sub {}

=head1 NAME

qqtool.pl - A tool for viewing and purging messages from a qmail queue


=head1 SYNOPSIS

	-a  action (delete, expire, list)
	-h  header to match (From, To, Subject, Date)
	-q  queue to search (local/remote)
	-s  search  (pattern to search for)
	-v  verbose
	
	If no -h is specified, then the pattern is searched for in any header.
	If no -q is specified, then both queues are searched.

	To list messages in queue from matt:
	qqtool.pl -a list -s matt -h From

	To list messages in queue with string \"foo\" in the headers:
	qqtool.pl -a list -s foo	


=head1 DESCRIPTION

Qmail Queue Tool (qqtool.pl)

This program will allow you to search and view messages in your qmail queue. It will also allow you to remove them, via expiration or deletion. It was written by Matt Simerson for the toaster users on mail-toaster@simerson.net

ChangeLog - http://www.tnpi.net/internet/mail/qqtool/changelog.shtml


=head1 INSTALL

Download Mail::Toaster from http://mail-toaster.org/Mail-Toaster.tar.gz

   fetch Mail-Toaster.tar.gz
   tar -xzf Mail-Toaster.tar.gz
   cd Mail-Toaster-x.xx
   perl Makefile.PL
   make install
   rehash

Run the script without any parameters and it will show you a menu of options.

   qqtool.pl

=head2 Sample Output

 # qqtool.pl
          Qmail Queue Tool   v 1.9

   -a  action (delete, expire, list)
   -h  header to match (From, To, Subject, Date)
   -q  queue to search (local/remote)
   -s  search  (pattern to search for)
   -v  verbose

If no -h is specified, then the pattern is searched for in any header. If no -q is specified, then both queues are searched.

To list messages in queue from matt:

   ./Mail-Toaster/qqtool.pl -a list -s matt -h From

To list messages in queue with string "foo" in the headers:

   ./Mail-Toaster/qqtool.pl -a list -s foo


=head2  User Preferences

There is one settings you can alter:

  $qdir is the path to your qmail queue

If you aren't using the default (/var/qmail/queue), edit qqtool.pl and adjust it.



=head1 AUTHOR

Matt Simerson <matt@tnpi.net>


=head1 CREDITS

Idea based on mailRemove.py by Dru Nelson <dru@redwoodsoft.com>, ideas borrowed from qmHandle by Michele Beltrame <mick@io.com>

Community funding was contributed by the following mail-toaster@simerson.net mailing list subscribers:

 erik erik at microcontroller.nl (organizer)
 Rick Romero  rick at valeoinc.com
 Chris Eaton  Chris.Eaton at med.ge.com
 Marius Kirschner marius at agoron.com
 J. Vicente Carrasco carvay at teleline.es
 Chris Odell  chris at redstarnetworks.net
 Pat Hayes pat at pathayes.net
 Dixon Cole dixon at levee.net
 Randy Meyer rjmeyer at humbleguys.net
 kristian kristian at waveit.com
 Michael Andreasen michael at subwire.dk (beer)
 Nathan Nieblas nnieblas at microtosh.net
 Randy Jordan ctech at pcwarp.com


=head1 BUGS

Report to author. Patches welcome.


=head1 TODO

In list mode, when showing messages in the queue, show which addresses delivery has failed for, so you know exactly why a message is still in the queue (useful for mailing lists with many recipients)

Interactive mode - step through messages offering to delete/expire/skip each

Clean mode - Leave qmail down after stopping it, useful for multiple invocations

Write the messages into a "inactive" queue before deleting them.

Ability to restore messages from "inactive" to the real queue.


=head1 SEE ALSO

http://www.mail-toaster.org/


=head1 COPYRIGHT

Copyright 2003-2013, The Network People, Inc. All Rights Reserved.

=cut

#!/usr/bin/perl

use Time::Local;
use Getopt::Long;

GetOptions ("help"    => \$help,
	    "quiet"   => \$quiet,
    	    "verbose" => \$verbose );

if ($help)
{
    &Usage;
}

if (! $quiet)
{
    $summary = 1;
}

$processgen = "/bin/ps --no-headers -eo user,pid,lstart,cmd";
%ignoreuser =
    ( "root", 0,
      "avahi", 0,
      "chrony", 0,
      "colord", 0,
      "dbus", 0,
      "dnsmasq", 0,
      "gdm", 0,
      "libstor+", 0,
      "nagios", 0,
      "nobody", 0,
      "ntp", 0,
      "polkitd", 0,
      "postfix", 0,
      "rpc", 0,
      "rpcuser", 0,
      "rtkit", 0,
      "setroub+", 0,
      "sshd", 0,
      "smmsp", 0,
      "unbound", 0,
    );
%months =
    ( "Jan", 0,
      "Feb", 1,
      "Mar", 2,
      "Apr", 3,
      "May", 4,
      "Jun", 5,
      "Jul", 6,
      "Aug", 7,
      "Sep", 8,
      "Oct", 9,
      "Nov", 10,
      "Dec", 11,
    );
$daysec = 24 * 60 * 60;
$now = time();
$yesterday = $now - $daysec;

if (! open (PS, "$processgen |"))
{
    print "$0: Could not execute $processgen: $!\n";
    exit (1);
}
while ($line = <PS>)
{
    chomp ($line);
    if ($line !~ /(\S+)\s+(\d+)\s+\S+\s+(\S+)+\s+(\S+)+\s+(\d\d):(\d\d):(\d\d)\s+(\S+)\s+(.*)$/)
    {
	print "$processgen\n";
	print "produced a line that doesn't match the regular expression:\n";
	print "$line\n";
	print "Exiting, please correct regexp.\n";
	exit (1);
    }
    $user = $1;
    $pid = $2;
    $month = $3;
    $day = $4;
    $hour = $5;
    $minute = $6;
    $second = $7;
    $year = $8;
    $proc = $9;
    $year = $year - 1900;
    $time = timelocal ($second, $minute, $hour, $day, $months{$month}, $year);

    # Skip known system UIDs.
    if (exists ($ignoreuser{$user}))
    {
	$ignoreduser{$user} = 1;
	next;
    }
    # Skip any UID that doesn't look like a UTLN.
    if ($user !~ /^[a-z]{2,6}\d\d$/)
    {
	$unrecognized{$user} = 1;
	next;
    }

    # Conditions for a pkill:
    # * Any vscode-server process (or derivate process) running with
    #   no sshd
    # * Any sshd @notty with nothing else
    # * Any process set that is entirely older than 24 hours,
    #   discounting any "sleep 180" processes.
    #
    # Conditions precluding a pkill:
    # * Any non-@notty ssh process

    # Undying processes derived from VSCode
    if ($proc =~ /\/\.vscode-server\// ||
	$proc =~ /\/\.vscode-server-insiders\// ||
	$proc eq "tcsh -c bash" ||
	$proc eq "bash" ||
	$proc eq "-bin/tcsh" ||
	$proc =~ /^valgrind / ||
	$proc =~ /\/a\.out/ ||
	$proc eq "sleep 180" ||
	$proc =~ /\<defunct\>/ )
    {
	$users{$user}{"vscode"} = 1;
    }
    # Undying processes that Red Hat itself can leave behind.
    # Not VSCode, but also not anything else, count them with VSCode.
    elsif ($proc eq "/usr/lib/systemd/systemd --user" ||
	   $proc eq "(sd-pam)" ||
	   $proc =~ /^\/usr\/bin\/dbus-daemon / ||
	   $proc =~ /^\/usr\/bin\/gnome-keyring-daemon / ||
	   $proc =~ /^\/usr\/bin\/pulseaudio / ||
	   $proc eq "/usr/bin/pipewire" ||
	   $proc =~ /^exec pipewire-media-session -d / ||
	   $proc =~ /^gio monitor -f \/run\/systemd\/sessions\//)
    {
	$users{$user}{"vscode"} = 1;
    }
    elsif ($proc =~ /^sshd: /)
    {
	if ($proc =~ /\@notty/)
	{
	    $users{$user}{"sshnotty"} = 1;
	}
	else
	{
	    $users{$user}{"ssh"} = 1;
	}
    }
    else
    {
	$users{$user}{"other"} = 1;
    }
    # Separately from all the process names...
    if ($time > $yesterday)
    {
	$users{$user}{"new"} = 1;
    }

    $users{$user}{"procs"}{$pid} = "$time $proc";
}
close (PS);

foreach $user (sort (keys (%users)))
{
    if (exists ($users{$user}{"ssh"}))
    {
	if ($verbose)
	{
	    print "User $user has an sshd with a PTY, skipping\n";
	    &DumpProcs (\%users, $user);
	}
	$sshdpty{$user} = 1;
	next;
    }
    if (exists ($users{$user}{"vscode"}) &&
	! exists ($users{$user}{"sshnotty"}))
    {
	if (exists ($users{$user}{"other"}))
	{
	    if ($verbose)
	    {
		print "User $user has something random running, skipping\n";
		&DumpProcs (\%users, $user);
	    }
	    $nonvscode{$user} = 1;
	}
	else
	{
	    if ($verbose)
	    {
		print "Muahahahaha, killing $user\n";
		&DumpProcs (\%users, $user);
	    }
	    &KillProcs (\%users, $user);
	    $killed{$user} = $1;
	}
    }
    else
    {
	if ($verbose)
	{
	    print "User $user looks active, leaving alone\n";
	    &DumpProcs (\%users, $user);
	}
	$activeuser{$user} = 1;
    }
}

if (! $summary && ! $verbose)
{
    exit (0);
}
if ($verbose)
{
    print "\n\n\n";
}

print "Ignored users:\n";
print "   Known system accounts:\n";
print "      ".join (", ", (sort (keys (%ignoreduser))));
print "\n";
print "   Non-UTLN UIDs:\n";
print "      ".join (", ", (sort (keys (%unrecognized))));
print "\n\n";
print "Surviving UTLN UIDs:\n";
print "   SSHD with PTY:\n";
print "      ".join (", ", (sort (keys (%sshdpty))));
print "\n";
print "   SSHD without PTY, but with other processes:\n";
print "      ".join (", ", (sort (keys (%activeuser))));
print "\n";
print "   No SSHD, but VSCode + unrecognized processes:\n";
print "      ".join (", ", (sort (keys (%nonvscode))));
print "\n\n";
print "Killed UTLN UIDs:\n";
print "   No SSHD and only VSCode processes:\n";
print "      ".join (", ", (sort (keys (%killed))));
print "\n";


sub DumpProcs
{
    my ($users, $user) = @_;
    my ($pid);

    foreach $pid (sort {$a <=> $b} (keys (%{$users->{$user}{"procs"}})))
    {
	print "$user\t$pid\t".$users->{$user}{"procs"}{$pid}."\n";
    }
    print "\n";
}

sub KillProcs
{
    my ($users, $user) = @_;
    my ($pid);

    # Kill twice -- at least the 'gio' process won't die with ordinary
    # signal 15.  Use signal 9 on the second pass to avoid leaving a
    # coredump behind.

    # First kill round.  Be nice: give things a chance to clean up
    # after themselves before exiting.
    foreach $pid (sort {$a <=> $b} (keys (%{$users->{$user}{"procs"}})))
    {
	kill 15, $pid;
    }
    # Wait a bit for all the cleanup before going for The Big Hammer.
    sleep (1);
    # The Big Hammer.
    foreach $pid (sort {$a <=> $b} (keys (%{$users->{$user}{"procs"}})))
    {
	kill 9, $pid;
    }
}

sub Usage
{
    print "$0 [-h] [-q] [-v]\n";
    print "\n";
    print "-h Help, produce this message.\n";
    print "-q Quiet, run with no output other than fatal errors.\n";
    print "-v Verbose, run with noisy output detailing all user processes.\n";
    print "\n";
    print "Finds orphaned VSCode server-side processes left over from\n";
    print "a messy exit or disconnection from the client-side editor,\n";
    print "and kills them.  By default produces a summary of its\n";
    print "operation when it is done.  Necessary because VSCode\n";
    print "extension writers are slobs and people want to use VSCode.\n";
    print "\n";
    print "Must be run as root, otherwise it will report that it is\n";
    print "killing processes but will actually fail to do so.  It does\n";
    print "not test what user it is running as.\n";
    exit (0);
}

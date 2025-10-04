#!/usr/bin/perl

use strict;
use warnings;
use POSIX qw(strftime);

# self-escalate with sudo if necessary
if ($> != 0) {
    exec('sudo', $^X, $0, @ARGV) or die "Failed to escalate via sudo: $!";
}

sub run {
    my ($cmd, $die_on_fail) = @_;
    print "+ $cmd\n";
    my $rc = system($cmd);
    if ($rc != 0) {
        warn "Command failed (rc=$rc): $cmd\n";
        if ($die_on_fail) {
            die "Aborting due to failed command: $cmd\n";
        }
    }
    return $rc;
}

# retry wrapper for apt update
sub apt_update_retry {
    my $tries = 5;
    for my $i (1..$tries) {
        print "apt update (attempt $i/$tries)...\n";
        my $rc = system('apt-get update -y >/dev/null 2>&1');
        return 0 if $rc == 0;
        warn "apt-get update failed (rc=$rc). Sleeping 3 s then retrying...\n";
        sleep 3;
    }
    warn "apt-get update failed after $tries attempts — continuing but results may be stale.\n";
    return 1;
}

$ENV{DEBIAN_FRONTEND} = 'noninteractive';

print "Starting SSH bootstrap at " . strftime("%Y-%m-%d %H:%M:%S", localtime) . "\n";

apt_update_retry();

# Install openssh-server
print "Installing openssh-server (if not present)...\n";
run("apt-get install -y openssh-server", 1);

# Enable and start ssh service
print "Enabling and starting ssh service...\n";
run("systemctl enable ssh --now", 1);

# ssh service check
print "Checking ssh service status:\n";
run("systemctl is-active --quiet ssh && echo 'ssh: active' || echo 'ssh: not active'");

# get hostname and IPv4 address
chomp(my $hostname = `hostname 2>/dev/null`);
$hostname ||= 'unknown-host';

chomp(my $ips_raw = `ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}/\\d+'` || '');
$ips_raw =~ s/^\s+|\s+$//g;
$ips_raw ||= "no IPv4 address found";

my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
my $line = "$timestamp - $hostname - $ips_raw\n";

print "\n=== Host information ===\n";
print $line;
print "========================\n";

# optionally append to Samba file
my $samba_file = $ENV{SAMBA_FILE} // '/mnt/samba/hosts_ips.txt';

if (-d '/mnt/samba' && -w '/mnt/samba') {
    if (open my $fh, '>>', $samba_file) {
        print $fh $line;
        close $fh;
        print "Wrote host info to $samba_file\n";
    } else {
        warn "Unable to open $samba_file for append: $!\n";
    }
} elsif (defined $ENV{SAMBA_FILE}) {
    if (open my $fh, '>>', $samba_file) {
        print $fh $line;
        close $fh;
        print "Wrote host info to $samba_file\n";
    } else {
        warn "SAMBA_FILE is set to '$samba_file' but cannot be written: $!\n";
    }
} else {
    print "No writable Samba mount detected at /mnt/samba and SAMBA_FILE not set — skipping remote write.\n";
}

print "Bootstrap complete.\n";
exit 0;

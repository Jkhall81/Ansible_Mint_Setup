#!/usr/bin/perl

use strict;
use warnings;
use POSIX qw(strftime);
use Getopt::Long;

# ==========================================
# Configurable settings
# ==========================================
my $samba_share = '//192.168.11.68/mintshare';
my $mount_point = '/mnt/samba';
my $samba_opts  = 'guest,vers=3.0';
my $role;

GetOptions("role=s" => \$role);

if (!$role) {
    die "Usage: sudo perl machine_setup.pl --role [agent|training|manager]\n";
}

# ==========================================
# Self-escalate with sudo if necessary
# ==========================================
if ($> != 0) {
    exec('sudo', $^X, $0, @ARGV) or die "Failed to escalate via sudo: $!";
}

# ==========================================
# Utility subroutines
# ==========================================
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

sub apt_update_retry {
    my $tries = 5;
    for my $i (1..$tries) {
        print "apt update (attempt $i/$tries)...\n";
        my $rc = system('apt-get update -y >/dev/null 2>&1');
        return 0 if $rc == 0;
        warn "apt-get update failed (rc=$rc). Sleeping 3s then retrying...\n";
        sleep 3;
    }
    warn "apt-get update failed after $tries attempts — continuing but results may be stale.\n";
    return 1;
}

sub ensure_mounted {
    my ($share, $mount, $opts) = @_;
    unless (-d $mount) {
        print "Creating mount point at $mount...\n";
        mkdir $mount or die "Failed to create $mount: $!";
    }

    my $mounted = `mount | grep '$mount'`;
    if ($mounted) {
        print "Samba share already mounted at $mount.\n";
        return;
    }

    print "Mounting Samba share $share -> $mount...\n";
    my $rc = system("mount -t cifs $share $mount -o $opts");
    if ($rc != 0) {
        die "Failed to mount Samba share $share: $!";
    }
}

sub unmount_samba {
    my $mount = shift;
    my $mounted = `mount | grep '$mount'`;
    if ($mounted) {
        print "Unmounting $mount...\n";
        system("umount $mount");
    } else {
        print "No active mount at $mount.\n";
    }
}

# ==========================================
# Main execution
# ==========================================
print "Starting SSH bootstrap at " . strftime("%Y-%m-%d %H:%M:%S", localtime) . "\n";
print "Role: $role\n";

apt_update_retry();

# Mount Samba
ensure_mounted($samba_share, $mount_point, $samba_opts);

# Install openssh-server
print "Installing openssh-server (if not present)...\n";
run("apt-get install -y openssh-server", 1);

# Enable and start ssh service
print "Enabling and starting ssh service...\n";
run("systemctl enable ssh --now", 1);

# ssh service check
print "Checking ssh service status:\n";
run("systemctl is-active --quiet ssh && echo 'ssh: active' || echo 'ssh: not active'");

# Get hostname and IPv4 address
chomp(my $hostname = `hostname 2>/dev/null`);
$hostname ||= 'unknown-host';

chomp(my $ips_raw = `ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}/\\d+'` || '');
$ips_raw =~ s/^\s+|\s+$//g;
$ips_raw ||= "no IPv4 address found";

my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
my $line = "$timestamp - $hostname - $ips_raw - role=$role\n";

print "\n=== Host information ===\n";
print $line;
print "========================\n";

# Write host info to Samba file
my $samba_file = "$mount_point/hosts_ips.txt";

if (-d $mount_point && -w $mount_point) {
    if (open my $fh, '>>', $samba_file) {
        print $fh $line;
        close $fh;
        print "Wrote host info to $samba_file\n";
    } else {
        warn "Unable to open $samba_file for append: $!\n";
    }
} else {
    warn "No writable Samba mount at $mount_point — skipping remote write.\n";
}

# Unmount
unmount_samba($mount_point);

print "Bootstrap complete.\n";
exit 0;

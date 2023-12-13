#!/usr/bin/perl

# hookscript-driverctl.pl - bind GPU to vfio-pci for VMs
#
# Version: 20220423-1
#
# NOTES: 
#    * Still working after upgrading Proxmox VE 7.4 > 8.1.3
#
# Purpose:
#   * Scans VM conf file for any PCI passthrough devices
#   * On VM start, those devices to 'vfio-pci'
#       + VM will fail to start (with a descriptive message) if:
#          - fail to read VM config
#          - `driverctl list-overrides` reports PCI devices needed are overridden
#          - `driverctl set-override` fails
#   * On VM stop, unset overrides (if device used for terminal framebuffer it should reappear)
#
# Usage:
#   * Enable on a VM via: `qm set <vmid> -hookscript local:snippets/hookscript-driverctl.pl`
#   * Disable via: `qm set <vmid> --delete hookscript`
#
# Details:
#   * https://github.com/Jahfry/Miscellaneous/blob/main/proxmoxVE71/05.ProxmoxGPUPassthrough.md
#   * Based on /usr/share/pve-docs/examples/guest-example-hookscript.pl
#   * If no PCI passthrough devices found, nothing happens and VM allowed to start

$|=1; # auto flush, otherwise 'die' can print before the last 'print'
use strict;
use warnings;
use File::Basename;

my ($hookscript_name) = basename($0);
my $hookscript_dir = '/var/lib/vz/snippets/';

# Verify arguments, show user how to run from shell if needed
if ((@ARGV && $ARGV[0] !~ m/[0-9]{1,}/) || ! $ARGV[1] || grep( /^--help$/,@ARGV ) ) {
    print <<EOM;

${hookscript_name}:

This script is meant to be run by the qemu system as a hookscript.

See comments in ${hookscript_dir}${hookscript_name} for usage.

To debug from command line, use this syntax:
    ${hookscript_name} <vmid> <phase>
      ... <vmid> = # of the VM you're testing (can be started but save anything active)
      ... <phase> = [pre-start|post-start|pre-stop|post-stop]
    EXAMPLE: `${hookscript_dir}${hookscript_name} 100 pre-start`

EOM
    exit(1);
}

my $vmid = shift;  # First argument is the vmid
my $phase = shift; # Second argument is the phase

# SUB: explain why then die
sub hookscript_die {
  print "--Unable to start VM ${vmid}--\n";
  die "$_[0]";
}

# Start of output
print "VM ${vmid} GUEST HOOK ($0): " . join(' ', @ARGV). "\n";

# Array for holding passthrough PCI devices from config file
my @pci_devices = ();
# `driverctl` command installed via: `apt install driverctl`
my $driverctl = "/usr/sbin/driverctl";
my $driverctl_cmd_listoverrides = "${driverctl} list-overrides 2>&1";
# PVE config file for the VM
my $config_file;
my $config_file_device;

# Read in the VM configuration to see what PCI devices are passed through
# Examples
# ... individual PCI device:
# hostpci0: 0000:0b:00.0,pcie=1
# ... all PCI devices ie "All Functions" checked in UI
# hostpci0: 0000:0b:00,pcie=1
if ($vmid) {
  $config_file = "/etc/pve/qemu-server/" . $vmid . ".conf";
  if (-r $config_file) {
    print "VM ${vmid} config file: ${config_file}\n";
    open ( _CF, $config_file ) or hookscript_die("ERROR: Failed to open ${config_file}.");
    while ( <_CF> ) {
      if (m/^hostpci[0-9]{1,}:[\s]([^\,]*)/) {
        # check to see if this is an individual device or if UI selected "All Functions"
        $config_file_device = $1;
        if ($config_file_device =~ m/^([^\.]{1,})(\.[0-9]{1,})$/) {
        # single device
          push(@pci_devices,$config_file_device);
        } else {
        # "All Functions" checked, need to determine all on root device
          my @lspci_devices = qx(lspci -s $1);
          for (@lspci_devices) {
            m/^([^\s]*)/;
            push(@pci_devices,"0000:" . $1);
          }
        }
      }
    }
  } else {
    hookscript_die("ERROR: failed to read ${config_file}.");
  }
}

if (! -e $driverctl) {
  hookscript_die("ERROR: ${driverctl} does not exist (try `apt install driverctl`).");
} elsif (! -x $driverctl) {
  hookscript_die("ERROR: ${driverctl} is not executable");
}

if ($phase eq 'pre-start') {

  # First phase 'pre-start' will be executed before the guest
  # is started. Exiting with a code != 0 will abort the start
  # On Proxmox output here goes to "Tasks" in UI, /var/log/syslog on Debian

  print "VM ${vmid} 'pre-start' ... preparing to start.\n";

  my @driverctl_overrides = qx($driverctl_cmd_listoverrides);
  my @pci_devices_conflicts;

  # check if any @pci_devices are in @driverctl_overrides
  # Example output of driverctl list-overrides
  # 0000:0b:00.0 vfio-pci

  my $pci_device;
  for (@pci_devices) {
    $pci_device = $_;
    for (@driverctl_overrides) {
      if ($_ =~ m/^${pci_device} /) {
       push(@pci_devices_conflicts,$pci_device);
      }
    }
    $pci_device = "";
  }

  if (@pci_devices_conflicts) {
    for (@pci_devices_conflicts) {
      print "ERROR: $_ ... override currently active.\n";
    }
    hookscript_die("");
  }

  # No conflicting overrides, so override them now if needed:
  if (@pci_devices) {
    for (@pci_devices) {
      my $driverctl_cmd_setoverride = "${driverctl} --nosave set-override $_ vfio-pci";
      my $exit_code_setoverride = system($driverctl_cmd_setoverride);
      if ($exit_code_setoverride != 0) {
        hookscript_die("`${driverctl_cmd_setoverride}`: Failed (exit code ${exit_code_setoverride}).");
      } else {
        print "`${driverctl_cmd_setoverride}`: Success.\n";
      }
    }
  }

  print "Starting VM ${vmid}.\n"

} elsif ($phase eq 'post-start') {

  # Second phase 'post-start' will be executed after the guest
  # successfully started.
  # On Proxmox output here goes to "Tasks" in UI, /var/log/syslog on Debian

  print "VM ${vmid} 'post-start' ... VM started successfully.\n";

  # commands to run after VM startup

} elsif ($phase eq 'pre-stop') {

  # Third phase 'pre-stop' will be executed before stopping the guest
  # via the API. Will not be executed if the guest is stopped from
  # within e.g., with a 'poweroff'
  # On Proxmox output here goes to "Tasks" in UI, /var/log/syslog on Debian

  print "VM ${vmid} 'pre-stop' ... VM will be stopped.\n(see /var/log/syslog for 'post-stop' output)\n";

  # commands to run before sending the stop

} elsif ($phase eq 'post-stop') {

  # Last phase 'post-stop' will be executed after the guest stopped.
  # This should execute even if guest crashed or stopped unexpectedly.
  # NOTE: Output for this phase goes to /var/log/syslog ('qmeventd')
  #       even on Proxmox (UI "Tasks" won't capture this phase)

  print "VM ${vmid} 'post-stop'. VM stopped, doing cleanup.\n";

  if (@pci_devices) {
    for (@pci_devices) {
      my $driverctl_cmd_unsetoverride = "${driverctl} --nosave unset-override $_";
      my $exit_code_unsetoverride = system($driverctl_cmd_unsetoverride);
      if ($exit_code_unsetoverride != 0) {
        print "`${driverctl_cmd_unsetoverride}`: FAILED. Exit code: ${exit_code_unsetoverride}  (continuing ... this may not matter)\n";
      } else {
        print "`${driverctl_cmd_unsetoverride}`: Success\n";
      }
    }
  }

  # final report, if no overrides shown, all ok
  my $override_check = qx($driverctl_cmd_listoverrides);
  print "`driverctl` overrides active: ";
  if ($override_check =~ m/No overridable devices found/) {
    # driverctl 'Kernel too old?' is a bad message to return, we know it is fine
    print "None (all PCI devices available for passthrough)\n";
  } else {
    print "$override_check\n";
  }

} else {

  # phase didn't match a known case
  hookscript_die("Unknown phase: ${phase} (--help for more information).");

}

exit(0);

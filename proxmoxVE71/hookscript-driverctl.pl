#!/usr/bin/perl

# hookscript to bind GPU to vfio-pci for VMs
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
#   * Enable on a VM via: `qm set <vmid> -hookscript local:snippets/driverctl.pl`
#   * Disable via: `qm set <vmid> --delete hookscript`
#
# Details:
#   * https://github.com/Jahfry/Miscellaneous/blob/main/proxmoxVE71/05.ProxmoxGPUPassthrough.md
#   * Based on /usr/share/pve-docs/examples/guest-example-hookscript.pl
#   * If no PCI passthrough devices found, nothing happens and VM allowed to start
#   * Note: this was my first time touching Perl in many years, look for bugs

use strict;
use warnings;

print "GUEST HOOK: " . join(' ', @ARGV). "\n";

# First argument is the vmid
my $vmid = shift;
# Second argument is the phase
my $phase = shift;

# PVE config file for the VM
my $config_file = "/etc/pve/nodes/gyges/qemu-server/" . $vmid . ".conf";
# Array holding any passthrough PCI devices from the config file above
my @pci_devices = ();
# `driverctl` installed via: `apt get driverctl`
my $driverctl = "/usr/sbin/driverctl";
my $driverctl_cmd_listoverrides = "${driverctl} list-overrides 2>&1";

if (! -e $driverctl) {
  print "\nERROR: $driverctl does not exist.\nUnable to start VM.\n";
  exit 1;
} elsif (! -x $driverctl) {
  print "\nERROR: $driverctl is not executable\nUnable to start VM.\n";
  exit 1;
}

# Read in the VM configuration to see what PCI devices are passed through
# Example line from /etc/pve/nodes/guges/qemu-server/100.conf
# hostpci0: 0000:0b:00.0,pcie=1
if (-r $config_file) {
  print "config file: $config_file\n";
  open ( _CF, $config_file ) or die "Unable to open config file: $config_file\n";
  while ( <_CF> ) {
    if (m/^hostpci[0-9]{1,}:[\s]([^\,]*)/) {
      push(@pci_devices,$1);
    }
  }
} else {
  print "\nERROR: failed to read $config_file.\nUnable to start VM.\n";
  exit 1;
}

if ($phase eq 'pre-start') {

  # First phase 'pre-start' will be executed before the guest
  # is started. Exiting with a code != 0 will abort the start

  print "$vmid is starting, doing preparations.\n\n";

  my @driverctl_overrides = qx($driverctl_cmd_listoverrides);
  my @pci_devices_conflicts;

  # check if any @pci_devices are in @driverctl_overrides
  # Example output of driverctl list-overrides
  # 0000:0b:00.0 vfio-pci
  for (@pci_devices) {
    if ( grep( /^$_$/, @driverctl_overrides ) ) {
      push(@pci_devices_conflicts,$_);
    }
  }
  if (@pci_devices_conflicts) {
    print "\nERRORS:\n";
    for (@pci_devices_conflicts) {
      print "    $_ ... override currently active.\n";
    }
    print "\nNOTE: `driverctl list-overrides` to see this list again.\nUnable to start VM.\n";
    exit 1;
  }

  # No conflicting overrides, so override them now if needed:
  if (@pci_devices) {
    for (@pci_devices) {
      my $driverctl_cmd_setoverride = "${driverctl} --nosave set-override $_ vfio-pci";
      print "Trying to override " . $_ . " to vfio-pci\n    Command: `$driverctl_cmd_setoverride`:\n";
      my $exit_code = system($driverctl_cmd_setoverride);
      if ($exit_code != 0) {
        print "    Failed with exit code: $exit_code\nUnable to start VM.\n";
        exit 1;
      } else {
        print "    SUCCESS\n";
      }
    }
  }
  print "\nStarting VM now.\n"

} elsif ($phase eq 'post-start') {

  # Second phase 'post-start' will be executed after the guest
  # successfully started.

  print "$vmid started successfully.\n";

} elsif ($phase eq 'pre-stop') {

  # Third phase 'pre-stop' will be executed before stopping the guest
  # via the API. Will not be executed if the guest is stopped from
  # within e.g., with a 'poweroff'

  print "$vmid will be stopped.\n";

} elsif ($phase eq 'post-stop') {

  # Last phase 'post-stop' will be executed after the guest stopped.
  # This should even be executed in case the guest crashes or stopped
  # unexpectedly.

  print "$vmid stopped. Doing cleanup.\n\n";

  # IMPORTANT:
  # Output from the 'post-stop' phase will not show up normally whether the VM is
  # shut down via the UI or via:
  # `qm stop <vmid> post-stop` (where <vmid> is the VM number, example: `qm stop 100 post-stop`)
  # If you want to see the results, you can run this manually in a shell like this:
  # `/var/lib/vz/snippets/hookscript-driverctl.pl <vmid> post-stop` (replace <vmid>)
  # filed issue ... https://bugzilla.proxmox.com/show_bug.cgi?id=4009
  
  if (@pci_devices) {
    for (@pci_devices) {
      my $driverctl_cmd = "${driverctl} --nosave unset-override $_";
      print "Trying to override " . $_ . " to vfio-pci\n    Command: `$driverctl_cmd`:\n";
      my $exit_code = system($driverctl_cmd);
      if ($exit_code != 0) {
        print "    Exit code: $exit_code ... continuing (this may not matter)\n";
      } else {
        print "    SUCCESS\n";
      }
    }

  my $override_check = qx($driverctl_cmd_listoverrides); # do a final report, if no overrides shown, all ok
  print "Current Overrides:\n";
  if ($override_check =~ m/No overridable devices found/) {
    # 'Kernel too old?' is a bad message to pass back as we know it is fine
    print "None, all PCI devices available for passthrough\n";
  } else {
    print "$override_check\n";
  }

  }

} else {
    die "got unknown phase '$phase'\n";
}

exit(0);

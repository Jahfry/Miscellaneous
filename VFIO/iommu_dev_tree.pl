#!/usr/bin/perl
# dev_tree.pl - show system device tree (default sort by IOMMU Group)
#
# `dev_tree.pl --manual` to display POD doc
#
# Notes:
#   * Requires: (see '=head1 REQUIRES' below)
#   * IMPORTANT: If a device is bound to module vfio-pci, won't show in output
#   * Tested: Proxmox VE / Debian Bullseye (should work on any if 'Requires:' met)
#   * Information added when parsing devices:
#     ... 'children'    = hash of devices below current device
#     ... 'type'        ... examples: IOMMU_Group, PCI_slot,     USB_device, etc
#     ... 'id'          ... examples: 1,           0000:00:00.0, 1-1,        etc
#     ... 'parent_id'   = ID of the parent    (need for tree output)
#     ... 'parent_type' = name of parent hash    ^   ^   ^     ^
#
# Versions/Changes:
#   * 2022.05.20-0.4-alpha ... fancy tree output
#   * 2022.05.11-0.3-alpha ... output other tree views (by PCI, only USB/Net/Block)
#   * 2022.05.09-0.2-alpha ... Net/Block devices added (block formatting incomplete)
#   * 2022.05.07-0.1-alpha ... initial version with PCI/USB devices
#
# Planned:
#   * 0.9-beta ... get external feedback for cleanup/fixes
#
# License: Unlicense (freely released with no warranty) - https://unlicense.org
#

# TODO:
## Get Net working with multiple buses
## Add experimental Thunderbolt support
## Allow USB4 to attach to TBT devices?
## we have IOMMU support if /sys/class/iommu/ is populated
# color?
# add experimental tbt (can USB attach to tbt? ugh)
#   https://github.com/intel/thunderbolt-software-user-space/issues/24
#   https://funnelfiasco.com/blog/2018/06/29/thinkpad-thunderbolt-dock-fedora/
#   ... /sys/devices/pci0000:00/0000:00:1d.0/0000:05:00.0/0000:06:00.0/0000:07:00.0/domain0/0-0/0-1
#   ... /sys/bus/thunderbolt/devices/domain0/0-0/0-1/0-301
#   https://gitlab.freedesktop.org/bolt/bolt/-/issues/179
#   ... domain1
# https://mjmwired.net/kernel/Documentation/ABI/testing/sysfs-bus-thunderbolt
# /sys/bus/thunderbolt/devices/usb4_portX
# /sys/bus/thunderbolt/devices/<device>:<port>.<index>
# /sys/bus/thunderbolt/devices/<device>:<port>.<index>/device
# https://www.reddit.com/r/VFIO/comments/uj9pft/thunderbolt_4_controller_passthrough/
# /sys/bus/thunderbolt/devices/usb4_portX/link
#
# https://wiki.archlinux.org/title/Thunderbolt
#
# answer https://unix.stackexchange.com/questions/654022/matching-pci-and-thunderbolt-devices
# post to MetaCPAN like https://metacpan.org/dist/App-lsiommu/view/bin/lsiommu


#
# POD (usage/documentation):

=head1

=head1 DESCRIPTION

Show hierarchy of iommu > bus > devices, multiple format options.

=head1 USAGE


 -d, --display <type>  ... display from this hierarchy point
 -f, --format <format> ... output format
 -h, --help            ... Help (this section)
 -m, --manual          ... Full help
 -q, --quiet           ... ONLY errors/warnings/additions (debug)

Format of output

 --format <format> (DEFAULT: '--format abbreviated'):
   a, abbrev  ... Abbreviate w/tree (for humans)
   f, full    ... Simple indents    (full values, parseable)
   g, generic ... Shows structure   (ALL data, multiple lines)
   J, JSON    ... JSON for humans   (ALL data, long)
   j, json    ... JSON minified     (ALL data)
   p, perl    ... Perl Data::Dumper (ALL data, very long)

Display hierarchy: IOMMU Group > PCI Bus (> Serial bus) > Devices

 --display <tree>: (DEFAULT: '--display iommu'):
   b,block        ... Bus > block devices (except 'virtual')
   i,iommu        ... *ALL* by IOMMU Group#
   n,net          ... Bus > network devices
   p,pci          ... PCI bus (> Serial bus) > devices
   t,thunderbolt  ... Thunderbolt bus > devices (EXPERIMENTAL_
   u,usb          ... USB bus > devices

=head1 ... REQUIRES

  * Linux Kernel with 'sysfs' (kernel 2.6.39+, August 16, 2011)
  * Perl version 5.8.0+ (July 18, 2002)
  * Perl modules: Getop::Long, Pod::Usage, File::Basename, Cwd,
                  Scalar::Util, Data::Dumper, JSON, utf8
                  (use CPAN to install missing modules, all are common)
  * Commands: `lspci -Dqmm`, `lsusb`, `lsblk -J` (JSON)

=head1 ... OUTPUT

=head2 NOTE: For details about specific devices based on following output:

  * PCI Device    = `lspci -v -s [PCI_slot] -d [vendor:device]`
  * USB Device    = `lsusb -v -d [idVendor:idProduct]`
  * Block Device  = `lsblk /dev/<device>`
  * Net Interface = `ip link show <device>`

=head2 Abstract:

  IOMMU:
  └── IOMMU_Group: #
      └── PCI_slot <class> "Description" (vendor_name) [vendor:device]
          └── BusID <class> "Desc." (module) [idVendor:idProduct] {busnum:devnum}
              └── HubID <class> "Desc." [idVendor:idProduct] {busnum:devnum}
                  └── DevID <class> "Desc." [idVendor:idProduct] {busnum:devnum}
                      └── DevID <dev type>
                          └── DiskID <fstype> "label|type" (model) [serial]
                              └── PartitionID <fstype> "label|type"

=head2 Example (default):

  IOMMU:
  └── IOMMU_Group: 1
      └── 00:01.0 <USB> "USB 3.0 Host" (Intel) [1021:148c]
          └── usb1 <usb> "xHCI Host Controller" (Linux kernel) [1a6b:1002] {1:1}
              └── 1-1 <usb> "USB3.0 Hub" [05f3:1608] {1:2}
                  ├── 1-1.1 <usb> "Sandisk" [13fa:1a00] {1:3}
                  │   └── 1-1.1:1.0 <usb-storage>
                  │       └── disk: sde <iso9660> "label=ISOIMAGE" (Sandisk) [17850BB106E3]
                  │           └── part: sde2 <vfat> "type=EFI System"
                  └── 1-2.1 <usb> "NETGEAR AC1900 Wi-Fi" [13ee:1f10] {1:4}
                      └── 1-2:1.0 <usb>
                          └── interface: wlp1s0 <rt188x2bu> [a4:2e:89:3d:cd:16]
                              └── bridge: vmbr0

=head2 Example (--format full):

  IOMMU:
   IOMMU_Group: 1
    PCI_slot: 0000:00:01.0 <USB Controller> "USB 3.0 Host" (Intel Corp.) [0x1021:0x148c]
     USB_root: usb1 <usb> "xHCI Host Controller" (Linux 5.3.9 xhci-hcd) [1a6b:1002] {1:1}
      USB_hub: 1-1 <usb> "USB3.0 Hub" [05f3:1608] {1:2}
       USB_device: 1-1.1 <usb> "Sandisk" [13fa:1a00] {1:3}
        USB_device: 1-1.1:1.0 <usb-storage>
         BLK_disk: sde <iso9660> "label=ISOIMAGE" (Sandisk) [17850BB106E3]
          BLK_part: sde2 <vfat> "type=EFI System"
       USB_device: 1-2.1 <usb> "NETGEAR AC1900 Wi-Fi" [13ee:1f10] {1:4}
        USB_device: 1-2:1.0 <usb>
         NET_interface: wlp1s0 <rt188x2bu> [a4:2e:89:3d:cd:16]
          NET_bridge: vmbr0

=head1 ... REPO

  https://github.com/Jahfry/Miscellaneous/blob/main/VFIO/dev_tree.pl
  (For versions / changelog / plans see comments top of script)

=cut

# MAIN::
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use File::Basename;
use Cwd qw(abs_path);
use Scalar::Util qw(looks_like_number);
use Data::Dumper qw(Dumper);
use JSON;
use utf8;
binmode *STDOUT, ':encoding(UTF-8)';
$|=1; # auto flush, otherwise 'die' can print before the last 'print'

# OPTIONS:: parse command line ... https://metacpan.org/pod/Getopt::Long
#  ... note: "--manual" not using '-verbose 2' in case perl-doc not installed
my %opt;
GetOptions (
  'format=s'  => \($opt{'format'} = 'abbrev'),
  'display=s' => \($opt{'display'} = 'iommu'),
  'help|?'    => \$opt{'help'},
  'manual'    => \$opt{'manual'},
  'quiet'     => \$opt{'quiet'},
) or pod2usage(-verbose => 0);
pod2usage(-verbose => 0) if $opt{'usage'};
pod2usage(-verbose => 1) if $opt{'help'};
pod2usage(-verbose => 99,-sections => "DESCRIPTION|USAGE|OUTPUT|REQUIRES|REPO") if $opt{'manual'};
my @opts_check = ('display','format');
my %opts_valid;
$opts_valid{'display'} = ['block','iommu','net','pci','thunderbolt','usb','b','i','n','p','t','u'];
$opts_valid{'format'} = ['abbrev','full','generic','JSON','json','perl','a','f','g','J','j','p'];
for my $check (@opts_check) {
  if ($opt{$check}) { # default is iommu if not set in options
    my @opts_valid = $opts_valid{$check};
    if (! grep(/^$opt{$check}$/,@{$opts_valid{$check}})) {
      print "ERROR: Unrecognized: '--$check $opt{$check}'\n\n";
      pod2usage(-verbose => 0);
    } else {
      $opt{$check} =~ m/^(.).*$/; # only keep first char for later processing
      $opt{$check} = $1;
    }
  }
}

# pattern used to pull PCI endpoint from symlinks for multiple SUBs
my $pci_id_match = qr/[\dA-Fa-f]{4}:[\dA-Fa-f]{2}:[\dA-Fa-f]{2}\.[\dA-Fa-f]{1}/;

# SUBS called in MAIN area (OUTPUT SUBs are at end of file)
# SUB::system2array() - returns output of a system command as a chomped hash
#  ... called by: MAIN:lsusb, MAIN:lspci
sub system2array {
  my ($command_name,$command_args) = @_ or die "system2array(): first argument must be a command name: $!";
  $command_name = `which $command_name` or die "system2array: Couldn't find `$command_name`, not installed? ... ";
  chomp($command_name);
  my $command_full = $command_name;
  if ($command_args) { $command_full = "${command_name} ${command_args}"; }
  my @command_output = qx($command_full 2>&1) or die "system2array: Couldn't exec $command_name: $!";
  chomp(@command_output);
  return @command_output;
}
# SUB::dir2array("directory") - return array of files/dirs/links (skips . / ..)
#  ... called by: MAIN::USB, SUB::usbfiles2hash, MAIN::IOMMU
sub dir2array {
  my $sub_dir = $_[0] or die "dir2array() first argument must be a directory: $!";
  my @sub_return;
  opendir(sub_DIR,$sub_dir) or die "dir2array() failed to readdir $sub_dir: $!";
  for my $sub_entry (readdir sub_DIR) {
    # skip '.' and '..' entries
    if ($sub_entry !~ /^[\.]{1,2}$/) {
      push(@sub_return,$sub_entry);
    }
  }
  closedir(sub_DIR);
  return @sub_return;
}
# SUB::file2string("filename") - return first line of a file as a variable
# ... called by: SUB::usbfiles2hash, MAIN::IOMMU
sub file2string {
  my $file_name = $_[0] or die "file2string() ... first argument must be a file: $!";
  my $var_string = ' ';
  if (-r ${file_name}) {
    open(file2string, '<', "${file_name}");
    chomp($var_string = <file2string>);
    close(file2string);
    $var_string =~ s/^[\s]*$//;
  }
  return $var_string;
}

# MAIN::lsusb - get USB device description from `lsusb`, associated by idVendor:idProduct
my @list_lsusb = system2array("lsusb");
my %lsusb;
for (@list_lsusb) {
  # $1=bus $2=device $3=vendor_id $4=product_id $5=device_name
  m/^Bus ([0-9]{3}) Device ([0-9]{3}): ID ([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4}) (.*)$/;
  $lsusb{"${3}:${4}"} = {'bus',$1,'device',$2,'description',$5};
}
# MAIN::lspci - get PCI device description from `lspci`, associated by PCI id
my @list_lspci = system2array("lspci","-Dqmm");
my %lspci;
for (@list_lspci) {
  # $1=pci_id $2=class $3=vendor_name $5=description
  m/^([^ ]*) "([^"]*)" "([^"]*)" "([^"]*)" (.*)$/;
  $lspci{"${1}"} = {'class',$2,'vendor_name',$3,'description',$4};
}
# MAIN::lsblk - get disk information using `lsblk -J` for JSON decoding
my $json_lsblk = qx(lsblk -J -I 8,259 -o NAME,TYPE,FSTYPE,PARTTYPENAME,LABEL,SIZE,FSUSE%,MODEL,SERIAL 2>&1);
$json_lsblk =~ s/\"name\"/\"id\"/g;
$json_lsblk =~ s/\"type\":\"/\"type\"\:\"BLK_/g;
my $lsblk = decode_json $json_lsblk;
# MAIN::Block - Build "%block_devices" ... a tree of 'PCI_slot' > 'BLOCK_dev'
#  ... lsblk JSON has all needed info except PCI_slot/USB_device
#      (must come before MAIN::USB and MAIN::PCI)
#  ... assumption made: only 1 level of children possible (sda > sda1)
my %block_devices;
my %block_device = ();
my $dir_block_devices = '/sys/block';
my @block_buses;
for my $block_device (dir2array($dir_block_devices)) {
  my $block_device_path = abs_path("${dir_block_devices}/${block_device}");
  my @bus_device = path2bus_device("$block_device_path");
  if ($bus_device[0] && ! grep($bus_device[0],@block_buses)) {
    $block_devices{$bus_device[0]}{'type'} = 'Bus';
    $block_devices{$bus_device[0]}{'id'}   = $bus_device[0];
  }
  if ($bus_device[1]) {
    for my $lsblk_device (@{$lsblk->{'blockdevices'}}) {
      my $lsblk_matched = 0;
      if (ref $lsblk_device->{'children'} eq 'ARRAY') {
        my %children = ();
        my $children = $lsblk_device->{'children'};
        for (@$children) {
          $_->{'parent_id'} = $lsblk_device->{'id'};
## dynamic?
          $_->{'parent_type'} = 'blk';
          $children{$_->{'id'}} = $_;
        }
        $lsblk_device->{'children'} = \%children;
      }
      if ($lsblk_device->{'id'} eq $block_device) {
        $lsblk_device->{'parent_id'} = $bus_device[1];
        $lsblk_device->{'parent_type'} = $bus_device[0];
        $block_devices{$bus_device[0]}{'children'}{$bus_device[1]}{'children'}{$block_device} = \%$lsblk_device;
        $block_devices{$bus_device[0]}{'children'}{$bus_device[1]}{'id'} = $lsblk_device->{'parent_id'};
        $block_devices{$bus_device[0]}{'children'}{$bus_device[1]}{'type'} = $lsblk_device->{'parent_type'};
        $block_devices{$bus_device[0]}{'children'}{$bus_device[1]}{'parent_id'} = $bus_device[0];
        $block_devices{$bus_device[0]}{'children'}{$bus_device[1]}{'parent_type'} = 'Bus';
        last;
      }
      last if ($lsblk_matched);
    }
#    $block_devices{'devices_total'} = $devices_total;
  } # else { wtf? }
}

#print Dumper \%block_devices; exit;

# pci: ... /devices/pci0000:00/0000:00:01.2/0000:01:00.0/0000:02:01.0/0000:03:00.0/
# usb: ... /devices/pci0000:00/0000:00:01.2/0000:01:00.0/0000:02:08.0/0000:08:00.1/
#           usb1/1-6/1-6.1/1-6.1:1.0/host12/target12:0:0/12:0:0:0/block/sdk/
# tbt:  ... /devices/pci0000:00/0000:00:1d.0/0000:05:00.0/0000:06:00.0/0000:07:00.0/domain0/0-0/0-1
#      ... domain1

# SUB::path2bus_device() ... determine the bus of a device from symlink
#  ... called by MAIN::Block, MAIN::Net
## (need to call for MAIN::USB? for tbt)
sub path2bus_device {
  my $path = $_[0] or die "ERROR: no path given to determine bus type: $!";
  my @return = ();
  my @matches = ();
  if (@matches = $path =~ m/^(.*)\/(${pci_id_match})\/([^\/]*)(.*)/) {
    if ($matches[2] =~ m/^usb[0-9]{1,}/i) {
      @return = ($matches[3] =~ m/^[^A-Za-z]*\/([0-9]{1,}-[0-9:\-\.]{1,})\//g) ? ('usb',$1) : '';
    } elsif ($matches[2] =~ m/^domain[0-9]{1,}/i) {
      # thunderbolt EXPERIMENTAL, I don't have a thunderbolt board to test
      # final device pattern here is same as for USB above ... but
      #   ... test changing '[0-9\:\-\.]{1,}' below to '[0-9\-]{1,}'
      # should work for USB4 format (I don't know if USB4 goes under /usb or /thunderbolt)
      @return = ($matches[3] =~ m/^[^A-Za-z]*\/([0-9]{1,}-[0-9:\-\.]{1,})\//g) ? ('tbt',$1) : '';
    } else {
      @return = ($matches[1]) ? ('pci',$matches[1]) : '';
    }
  }
  return (@return) ? @return : 0;
}

# MAIN::Net - Build "%net_devices" ... a tree of 'PCI_slot' > 'Network_Interface' (can be multiple)
## ? only handles PCI, needs multi-bus via path2bus() ?
my %net_devices;
my $dir_net_devices = '/sys/class/net';

# fake, keep next line
# for (dir2array($dir_net_devices)) {
my @dir2array = dir2array($dir_net_devices);
push @dir2array,'fake';
for (@dir2array) {
  # build tree if symlink points to a PCIe root, ignore others, no recursion needed

# fake:
my $net_device_path;
if ($_ eq 'fake') {
  $net_device_path = '/sys/devices/pci0000:00/0000:00:01.2/0000:20:00.0/0000:21:08.0/0000:2a:00.1/usb1/1-5/1-5:1.0/net/enp42s0f1u5/';
} else {
  $net_device_path = abs_path("${dir_net_devices}/$_");
#  my $net_device_path = abs_path("${dir_net_devices}/$_");
} #end fake, only keep last line above
  my @device_by_bus = path2bus_device("$net_device_path");
#print ">>> @device_by_bus\n\n";
  if ($net_device_path =~ m/($pci_id_match)\/net\/(.*)$/) { # $1 = PCI device, $2 = net device
#    my $parent_type = 'NET_interface';
    my $pci = $1;
    my $id = $2;
    my %net_device = ();
    $net_device{'id'} = $id;
    $net_device{'type'} = 'NET_interface';
    $net_device{'address'} = (-r "${dir_net_devices}/$id/address")   ? file2string("${dir_net_devices}/$id/address") : '';
    $net_device{'driver'}  = (-l "${dir_net_devices}/$id/device/driver") ? basename(readlink("${dir_net_devices}/$id/device/driver")) : '';
    $net_device{'parent_id'} = $pci; ## buses
    $net_device{'parent_type'} = 'pci'; ## buses
    if (-l "${dir_net_devices}/$id/master") { # this should be how linux bridges attach
      my $bridge = basename(readlink("${dir_net_devices}/$id/master"));
      $net_device{'children'}{$bridge} = {'type','NET_bridge','id',$bridge,'parent_id',$net_device{'id'},'parent_type',$net_device{'type'}};
    }
    $net_devices{'pci'}{'children'}{$pci}{'children'}{$net_device{'id'}} = \%net_device;
    $net_devices{'pci'}{'children'}{$pci}{'type'} = 'PCI_slot';
    $net_devices{'pci'}{'children'}{$pci}{'id'} = $pci;
    $net_devices{'pci'}{'children'}{$pci}{'parent_id'} = 'pci';
    $net_devices{'pci'}{'children'}{$pci}{'parent_type'} = 'Bus';
  }
  $net_devices{'pci'}{'type'} = 'BUS';
  $net_devices{'pci'}{'id'} = 'PCI';
}


# MAIN::USB - Build "%usb_devices" ... a tree of 'PCI_slot' > 'USB_dev' (can be multiple)
#### add Block/Net USB devs
#### move usbfiles2hash here with an "inner"? (or keep sep for tbt?)
#### re-use for Thunderbolt?
##### do we need to worry about PCI -> TBT -> USB or just PCI -> TBT?
my %usb_devices;
my $usb_tree_level = 0;
my $dir_usb_devices = '/sys/bus/usb/devices';
for (dir2array($dir_usb_devices)) {
  # build tree if 'usb#' (ie, 'usb1', etc), ignore others, they are collected recursively
  if (m/^(usb[^\s]*)/i) {
    my $usb_root = $1;
    my %usb_device = usbfiles2hash('__none__',"${dir_usb_devices}/${usb_root}"); # sub recurses
    my $usb_device_path = abs_path("${dir_usb_devices}/${usb_root}");

###
#    my @bus_device = path2bus_device("$usb_device_path");
#    if ($bus_device[1]) {
#print ">>>>> bus=$bus_device[0] device=$bus_device[1]\n\n\n\n";

    my @returned = $usb_device_path =~ m/^.*\/(${pci_id_match})\/([^\/]*)(.*)/;
    $usb_devices{'pci'}{'children'}{${returned}[0]}{'children'}{$usb_device{'id'}} = \%usb_device;
#    $usb_devices{'pci'}{'children'}{$pci}{'type'} = 'PCI_slot';
#    $usb_devices{'pci'}{'children'}{$pci}{'id'} = $pci;
#    $usb_devices{'pci'}{'children'}{$pci}{'parent_id'} = 'pci';
#    $usb_devices{'pci'}{'children'}{$pci}{'parent_type'} = 'Bus';
  }
}

# SUB: usbfiles2hash("dirname") - read files with USB properties and return hash
#  ... recurses, called by: MAIN::USB
sub usbfiles2hash {
  my $parent = $_[0] or die "usbfile2hash() first argument must be the parent's id";
  my $usb_dir = $_[1] or die "usbfile2hash() second argument must be a directory: $!";
  $usb_tree_level++;
  my %usb_device;
  my $skip_device = 0;
  my $id = basename($usb_dir);
  # @usb_vars = which files we care about parsing
  my @usb_vars = ('idProduct','idVendor','busnum','devnum','manufacturer','product');
  for (dir2array("$usb_dir")) {
    if (m/^[0-9]{1,}-[0-9:\.\-]{1,}$/) {
      my %usb_device_attached = usbfiles2hash("$id","${usb_dir}/${_}"); # recursion
      if (%usb_device_attached) {
        $usb_device{'children'}{$usb_device_attached{'id'}} = \%usb_device_attached;
      }
    }
    if ($parent ne '__none__') {
      $usb_device{'parent_id'} = $parent;
      $usb_device{'parent_type'} = 'usb';
    } else {
## tbt? put in that function instead
      $usb_device{'parent_type'} = 'pci'; # an assumption but pretty safe in 2022
    }
    for my $key (@usb_vars) {
      $usb_device{'id'} = $id;
      if (-r "${usb_dir}/${key}") {
        $usb_device{"$key"} = file2string("${usb_dir}/${key}");
      }
      $usb_device{'driver'} = (-l "${usb_dir}/driver") ? basename(readlink("${usb_dir}/driver")) : '';
      $usb_device{'type'} = "USB_device";
      if ($usb_device{'driver'} eq 'usb' && $usb_tree_level == 1) {
        $usb_device{'type'} = "USB_root";
      } elsif ($usb_device{'product'}) {
        if ($usb_device{'product'} =~ /[^\S]*hub[^\S]*/i) {
          $usb_device{'type'} = "USB_hub"; # not ACTUALLY driver=hub, but this allows condensing list
        }
      } else {
        $usb_device{'type'} = "USB_device";
        if ($usb_device{'driver'} eq 'hub') { # actual hub device is empty aside from 'driver', skipped
          $skip_device = 1;
        }
      }
    }
  }
  $usb_tree_level--;
  my %subdevices = ('net',\%net_devices,'block',\%block_devices);
  my %children = find_children('usb',$id,\%subdevices);
  if (keys %children) {$usb_device{'children'} = \%children; }
  if ($skip_device) {
    return;
  } else {
    return %usb_device;
  }
}

# MAIN::IOMMU - Build "%iommu_groups" > 'PCI_id' hash tree of devices found above
my %iommu_groups;
my %pci_bus;
my $dir_iommu_groups = '/sys/kernel/iommu_groups/';
my $dir_pci_devices = '/sys/bus/pci/devices/';
my @list_iommu_groups = sort({$a<=>$b} dir2array($dir_iommu_groups));
for (@list_iommu_groups) {
  my $iommu_group = $_;
  my ( %iommu_group, %pci_devices );
## redo this with open() / glob() ?
  my @pci_devices = qx(ls ${dir_iommu_groups}/${_}/devices 2>&1);
  chomp(@pci_devices);
  for (@pci_devices) {
    my %pci_device;
    my $pci_id = $_;
    my $pci_vendor = file2string("${dir_pci_devices}${pci_id}/vendor");
    my $pci_device = file2string("${dir_pci_devices}${pci_id}/device");
    my $pci_class = $lspci{$pci_id}{'class'};
    my $pci_vendor_name = $lspci{$pci_id}{'vendor_name'};
    my $pci_description = $lspci{$pci_id}{'description'};
    %pci_device = ('id',$pci_id,'type','PCI_slot','vendor',$pci_vendor,'device',$pci_device,'class',$pci_class,'vendor_name',$pci_vendor_name,'description',$pci_description,'parent_id',$iommu_group,'parent_type','IOMMU_Group');
#    %pci_device = ('id',$pci_id,'type','PCI_slot','vendor',$pci_vendor,'device',$pci_device,'class',$pci_class,'vendor_name',$pci_vendor_name,'description',$pci_description);
    my %subdevices = ('usb',\%usb_devices,'net',\%net_devices,'block',\%block_devices);
    my %children = find_children('pci',$pci_id,\%subdevices);
    if (keys %children) {$pci_device{'children'} = \%children; }
    $iommu_groups{'iommu'}{'children'}{$iommu_group}{'children'}{$pci_device{'id'}} = \%pci_device;
    $iommu_groups{'iommu'}{'children'}{$iommu_group}{'type'} = 'IOMMU_Group';
#    $iommu_groups{'iommu'}{'children'}{$iommu_group}{'parent_id'} = $iommu_group;
    $iommu_groups{'iommu'}{'children'}{$iommu_group}{'parent_id'} = 'iommu';
    $iommu_groups{'iommu'}{'children'}{$iommu_group}{'parent_type'} = 'IOMMU';
#push @{ $iommu_groups{'iommu'}{'children'}{$iommu_group}{'array_test'} }, \%pci_device;
#    $iommu_groups{'iommu'}{'children'}{$iommu_group}{'id'} = $iommu_group;
    $iommu_groups{'iommu'}{'type'} = 'IOMMU';

#    $iommu_groups{'iommu2test'}{'children'}{$iommu_group}{'children'}{$pci_device{'id'}} = \%pci_device;
#    $iommu_groups{'iommu2test'}{'type'} = 'IOMMU Groups';
#    $iommu_groups{'iommu2test'} = $iommu_groups{'iommu'};
  }
}
#print Dumper \%iommu_groups;exit;
## duplicate for testing only
#$iommu_groups{'iommu2test'} = %$iommu_groups{'iommu'};

# SUB::find_children('parent_bus_type','parent_device_id',%{list_of_device_types})
#  ... called by MAIN::IOMMU, MAIN::USB, MAIN::TBT
sub find_children {
  my $parent_type   = $_[0];
  my $parent_id     = $_[1];
  my %child_devices = %{$_[2]};
  my %return        = ();
  for my $subtype (keys %child_devices) {
    if ($child_devices{$subtype}{$parent_type}{'children'}{$parent_id}) {
      for my $device (keys  %{$child_devices{$subtype}{$parent_type}{'children'}{$parent_id}{'children'}}) {
        $child_devices{$subtype}{$parent_type}{'children'}{$parent_id}{'children'}{$device}{'parent_id'} = $parent_id;
        $return{$device} = $child_devices{$subtype}{$parent_type}{'children'}{$parent_id}{'children'}{$device};
      }
    }
  }
  return %return;
}

# OUTPUT:: Use commandline ($opts) to define display type and format
#  ... all SUBs called here are below this code
my %display_ref = (
  'b'=>\%block_devices,
  'i'=>\%iommu_groups,
  'n'=>\%net_devices,
  'p'=>\%pci_bus,
#  't'=>\%thunderbolt_devices,
  'u'=>\%usb_devices,
);
my %display_name = (
  'b'=>'Bus(es) > Block Devices',
  'i'=>'IOMMU Groups > PCI > All Bus Devices',
  'n'=>'Bus(es) > Network Interfaces',
  'p'=>'PCI [all except roots] > All Bus Devices',
  't'=>'PCI > Thunderbolt Devices',
  'u'=>'PCI > USB Devices',
);
my %format_name = (
  'a'=>'default',
  'f'=>'with full/verbose values',
  'g'=>'with data structure labels',
  'J'=>'as JSON',
  'j'=>'as minimized JSON',
  'p'=>'Perl Data::Dumper',
);
my $format = $opt{'format'};
my $display = $opt{'display'};
my $display_ref = $display_ref{$display};
my $display_name = $display_name{$display};
my $newline = '';
if ($format eq 'a') { $newline = '➤'; } else { $newline = '#'; }


print "$newline Command Executed: `" . basename $0;
for (@ARGV) { print " $_"; }
print '`' . "\n";

print "$newline Displaying: $display_name (format: $format_name{$format})\n";
unless ($opt{'quiet'}) { # --quiet short circuits output
  if ($format eq 'g') {
    expand_generic($display_ref);
  } elsif ($format eq 'J') {
    my $json = JSON::XS->new->utf8->pretty(1);
    print $json->encode($display_ref);
  } elsif ($format eq 'j') {
    my $json = JSON::XS->new->utf8->pretty(0);
    print $json->encode($display_ref);
    print "\n";
  } elsif ($format eq 'p') {
    $Data::Dumper::Terse = 1;
    print Dumper \$display_ref;
  } else {       # 'a' is default output, 'f' uses same function
    expand($display_ref);
    print "\n";
  }
}

# SUB::expand(\%ref) - displays tree view of data
#  ... recurses, called by: OUTPUT:: (default view)
#  ... expects to only process hashes (see expand_generic() for a reusable routine)
my %indent_counter = ();
sub expand {
  my $indent = 0;
  my @indent_tracker = ();
  my $inner; $inner = sub {
    my $ref = $_[0];
    my $key = $_[1];
    if(ref $ref eq 'HASH'){
      if ($ref->{'type'}) {
        # display the device's keys on a single line -except- 'children'
        # this is where we handle iterations with key:value instead of hash
        print expand_indent($indent,@indent_tracker),expand_deviceinfo($ref,$key),"\n";
      }
      for my $k (sort sort_expand keys %{$ref}){  # modified, show key=children last
        if ($k eq 'children') {
          $indent++;
          # equalize 'type' for @indent_tracker and %indent_counter, store how many total
          my $tree_type = '';
#                 if ($ref->{'type'}) {
            $tree_type = ($ref->{'type'}) ? lc $ref->{'type'} : '';
            $tree_type =~ s/_.*$//;
            push @indent_tracker, $tree_type . '__' . $key;
#          }
          $indent_counter{$tree_type . '__' . $key}{'children_total'} = scalar keys %{$ref->{$k}};
        } elsif ($k eq 'type') {
          # equalize parent 'type' for %indent_counter, track how many used so far
          if ($ref->{'parent_type'}) {
            my $tree_parent_type = lc $ref->{'parent_type'};
            $tree_parent_type =~ s/_.*//;
            $indent_counter{$tree_parent_type . '__' . $ref->{'parent_id'}}{'children_used'}++;
          }
#print Dumper \%indent_counter;
        }
        $inner->($ref->{$k},$k);
        if ($k eq 'children') {
          pop @indent_tracker;
          $indent--;
        }
      }
    } elsif(ref $ref eq 'ARRAY'){ # shouldn't see ARRAY, warn if so
      my $key = ($key) ? $key : '';
      print expand_indent_old($indent),"> WARNING: ARRAY found, key=$key ref=$ref\n";
      $inner->($_) for @{$ref};
    }
  };
  $inner->($_[0]); # start the first run
}

# SUB::expand_indent('#') - formats indenting based on default or --verbose
#  ... called by SUB::expand()
sub expand_indent {
  my $indent             = ($_[0]) ? shift(@_) : 0;
  my @indent_tracker     = (@_)    ? @_        : ();
  my $indent_spaces      = '│   ';
  my $indent_spaces_last = '    ';
  my $indent_string      = '├── ';
  my $indent_string_last = '└── ';
  my $indent_return      = '';
  if ($format eq 'f') { # full/verbose uses minimal single space indenting
    $indent_spaces = ' ';
    if ($indent) {
      $indent_return = $indent_spaces x $indent;
    }
  } else { # default fancy indenting
#print "> @indent_tracker\n";
    if ($indent) {
      while (@indent_tracker) {
        my $tracker = shift @indent_tracker;
        my $total = ($indent_counter{$tracker}{'children_total'}) ? $indent_counter{$tracker}{'children_total'} : '0';
        my $used  = ($indent_counter{$tracker}{'children_used'})  ? $indent_counter{$tracker}{'children_used'}  : '0';
#print "> $tracker used=$used total=$total\n";
        if (@indent_tracker) {
            $indent_return .= ($used < $total)       ? $indent_spaces : $indent_spaces_last;
        } else {
            $indent_return .= (($used + 1) < $total) ? $indent_string : $indent_string_last;
        }
      }
    }
  }
  return "$indent_return";
}

# SUB::expand_old(\%ref) - displays tree view of data
#  ... recurses, called by: OUTPUT:: (default view)
#  ... expects to only process hashes (see expand_generic() for a reusable routine)
sub expand_old {
  my $indent = 0;
  my $inner; $inner = sub {
    my $ref = $_[0];
    my $key = $_[1];
    if(ref $ref eq 'HASH'){
      if ($ref->{'type'}) {
        # display the device's keys on a single line -except- 'children'
        # this is where we handle iterations with key:value instead of hash
        print expand_indent_old($indent),expand_deviceinfo($ref,$key),"\n";
      }
      for my $k (sort sort_expand keys %{$ref}){  # modified, show key=children last
        if ($k eq 'children') { $indent++; }
        $inner->($ref->{$k},$k);
        if ($k eq 'children') { $indent--; }
      }
    } elsif(ref $ref eq 'ARRAY'){ # shouldn't see ARRAY, warn if so
      my $key = ($key) ? $key : '';
      print expand_indent_old($indent),"> WARNING: ARRAY found, key=$key ref=$ref\n";
      $inner->($_) for @{$ref};
    }
  };
  $inner->($_[0]); # start the first run
}
# SUB::expand_indent_old('#') - formats indenting based on default or --verbose
#  ... called by SUB::expand()
sub expand_indent_old {
  my $indent = ($_[0]) ? $_[0] : 0;
  my ($indent_spaces,$indent_string,$indent_newline) = ('','','');
  if ($format eq 'f') { # full/verbose uses minimal single space indenting
    $indent_spaces = ' ';
    $indent_string = $indent_spaces x $indent;
  } elsif ($indent) { # default fancy indenting
    if ($indent) { $indent--; }
    $indent_spaces = '│   ';
    $indent_string = ($indent_spaces x $indent) . '├── ';
  } else { # default 0 indent
  }
  return "${indent_newline}${indent_string}";
}

# SUB::sort_expand_generic() - sort routine to force 'children' last for generic output
#  ... called by SUB::expand(), SUB::expand_generic()
sub sort_expand {
  if (looks_like_number($a) && looks_like_number($b)) { # numeric
    return $a <=> $b;
  } elsif ($a ne 'children' && $b ne 'children') { # alpha, force 'children' last
    if (! defined $a) {   # handle 'undef' values
      return -1;
    } elsif (! defined $b) {
      return 1;
    } else {
      return $a cmp $b;
    }
  } elsif ($a eq 'children') {
    return 1;
  } else {
    return -1;
  }
}

# SUB::expand_generic(\%hashref) - displays any nested data (hash or array)
#  ... recurses, called by: OUTPUT:: ... if option --generic
#  ... original credit: https://stackoverflow.com/a/13363234/2234204 ... 'expand_references2()'
#  ... unlike expand(): -not- dependent on specific structure, any combo of hashes+arrays
sub expand_generic {
  my $indenting = -1;
  my $inner; $inner = sub {
    my $ref = $_[0];
    my $key = $_[1];
    $indenting++;
    if (ref $ref eq 'ARRAY') {
      print '  ' x $indenting,'ARRAY:';
      printf("%s\n",($key) ? $key : '');
      $inner->($_) for @{$ref};
    } elsif (ref $ref eq 'HASH') {
      print '  ' x $indenting,'HASH:';
      printf("%s\n",($key) ? $key : '');
#      for my $k(sort keys %{$ref}){                     # original
      for my $k(sort sort_expand keys %{$ref}){          # modified, show key=children last
        $inner->($ref->{$k},$k);
      }
    } else {
#      if($key){                                         # original
      if ($key && defined $ref) {                        # modified, handle 'undef' values
        print '  ' x $indenting,$key,' => ',$ref,"\n";
      } elsif ($key) {                                   # added
        print '  ' x $indenting,$key,' => undef',"\n";   # added
      } else {                                           # added
        print '  ' x $indenting,$ref,"\n";
      }
    }
    $indenting--;
  };
  $inner->($_) for @_;
}

# SUB::expand_deviceinfo(%rehash) - return string of keys:values per device
#  ... called by SUB::expand_specific()
sub expand_deviceinfo {
  my $ref  = $_[0];
  my $key  = $_[1];
  my %out; # formatted output keys:values
  # format display keys:values
  # 'type' and 'id' should always exist if data format correct
  $out{'type'} = ($ref->{'type'}) ? $ref->{'type'} : '!UNKNOWNtype'; #shouldn't see !UKNOWNtype, but ...
  $out{'id'}   = ($key)           ? "$key"         : '0'; # quotes (") so 0 will print
  if ($out{'id'} eq lc $out{'type'}) { $out{'id'} = ''; }; # don't let top level look redundant ("IOMMU: iommu");

  # Populate output strings
  $out{'class'}       = ($ref->{'class'})       ? $ref->{'class'}       : '';
  $out{'description'} = ($ref->{'description'}) ? $ref->{'description'} : '';
  $out{'vendor_name'} = ($ref->{'vendor_name'}) ? $ref->{'vendor_name'} : '';
  $out{'vendor'}      = ($ref->{'vendor'})      ? $ref->{'vendor'}      : '';
  $out{'device'}      = ($ref->{'device'})      ? $ref->{'device'}      : '';
  $out{'busnum'}      = ($ref->{'busnum'})      ? $ref->{'busnum'}      : '';
  $out{'devnum'}      = ($ref->{'devnum'})      ? $ref->{'devnum'}      : '';
  # Map input keys to output keys based on type (IOMMU_group, PCI_slot or !UNKNOWN have no remapping)
  # USB_ map: class=driver description=product vendor_name=manufacturer vendor=idVendor device=idProduct
  if ($out{'type'} =~ m/^USB_[\S]*$/) {
    $out{'class'}       = ($ref->{'driver'})       ? $ref->{'driver'}       : '';
    $out{'description'} = ($ref->{'product'})      ? $ref->{'product'}      : '';
    $out{'vendor_name'} = ($ref->{'manufacturer'}) ? $ref->{'manufacturer'} : '';
    $out{'vendor'}      = ($ref->{'idVendor'})     ? $ref->{'idVendor'}     : '';
    $out{'device'}      = ($ref->{'idProduct'})    ? $ref->{'idProduct'}    : '';
    # if no 'description' use `lsusb` description (example: Intel Wifi doesn't have 'product')
    if (! $out{'description'} && $ref->{'idVendor'} && $ref->{'idProduct'}) {
      $out{'description'} = $lsusb{"$ref->{'idVendor'}:$ref->{'idProduct'}"}{'description'}
    }
  # NET_ map: class=driver address=address
  } elsif ($out{'type'} =~ m/^NET_[\S]*$/) {
    $out{'class'}         = ($ref->{'driver'})       ? $ref->{'driver'}       : '';
    $out{'address'}       = ($ref->{'address'})      ? $ref->{'address'}      : '';
  # BLK_ map: class=TYPE description=LABEL,PARTTYPENAME,FSUSE% vendor_name=MODEL
  #NAME,TYPE,FSTYPE,PARTTYPENAME,LABEL,SIZE,FSUSE%,MODEL,SERIAL
  } elsif ($out{'type'} =~ m/^BLK_[\S]*$/) {
    $out{'class'}       = ($ref->{'fstype'}) ? $ref->{'fstype'} : 'no filesystem';
    $out{'vendor_name'} = ($ref->{'model'})  ? $ref->{'model'}  : '';
    $out{'address'}     = ($ref->{'serial'}) ? $ref->{'serial'} : '';
    my @out_description = ();
    if ($ref->{'label'}) { push @out_description, 'label=' . $ref->{'label'}; }
    if ($ref->{'parttypename'}) { push @out_description, 'type=' . $ref->{'parttypename'}; }
    for (@out_description) {
      if ($out{'description'}) { $out{'description'} .= ", "; }
      $out{'description'} .= $_;
    }
# ? $ref->{'parttypename'} : '' ;
#    $out{'description'} = ($ref->{'label'}) ? $out{'description'} . $ref->{'label'} : '';

  }
  # shorten abbreviated output (limited to devices I had), add more as desired
#  if (! $opt{'verbose'}) {
  if ($format eq 'a') { # abbreviated, 'f' full won't do this
    # only display IOMMU_group 'type'
    $out{'type'} = ($out{'type'} eq 'PCI_slot' || $out{'type'} =~ m/^USB_/) ? '' : $out{'type'};
    $out{'type'} = ($out{'type'} =~ m/^[^_|^IOMMU]*_(.*)$/) ? $1 : $out{'type'};
    $out{'id'} =~ s/^0000://; # remove PCI Domain if 0000
    $out{'id'} =~ s/^LVM_Thinpool-(.*)$/$1/i;
    my $class = $out{'class'}; # declare each in case $out{'whatever'} is empty
    $class =~ s/[\s](\[|\()[\S]*(\]|\))$//i; # remove [stuff] & (stuff) at end, ex: "Non-Essential Instrumentation [1300]"
    $class =~ s/[\s](bridge|compatible controller|controller|device)$//i;
    $class =~ s/non-volatile memory$/NVME/i;
    $class =~ s/^serial attached/SA/i;
    $class =~ s/^non-essential //i;
    $class =~ s/^no filesystem$/no fs/i;
    $out{'class'} = $class;
    my $description = $out{'description'};
    $description =~ s/pci-express/PCIe/i;
    $description =~ s/solid state drive/SSD/i;
    $out{'description'} = $description;
    my $vendor_name = $out{'vendor_name'};
    $vendor_name =~ s/^linux[\s].*$/Linux kernel/i;
    $vendor_name =~ s/[\s]corporation//i;
    $vendor_name =~ s/[\s](inc\.|co\., ltd\.)$//i;
    $vendor_name =~ s/[\s](tech\.|technology|semiconductor)$//i;
    $vendor_name =~ s/[\s]*$//;
    $vendor_name =~ s/American Power Conversion/APC/;
    $vendor_name =~ s/^.*\[(.*)\]$/$1/; # if has short version, use it
    $out{'vendor_name'} = $vendor_name;
    my $vendor = $out{'vendor'}; # remove '0x' from vendor & device
    my $device = $out{'device'};
    $vendor =~ s/^0x//i;
    $device =~ s/^0x//i;
    $out{'vendor'} = $vendor;
    $out{'device'} = $device;
  }
  # format whatever we have into display strings, id in quotes (") so 0 will print
  $out{'type'}          = ($out{'type'})                     ? "$out{'type'}: "                      : '';
  $out{'id'}            = "($out{'id'})"                     ? "$out{'id'}"                         : '';
  $out{'class'}         = ($out{'class'})                    ? " <$out{'class'}>"                   : '';
  $out{'description'}   = ($out{'description'})              ? " \"$out{'description'}\""           : '';
  $out{'vendor_name'}   = ($out{'vendor_name'})              ? " ($out{'vendor_name'})"             : '';
  $out{'busnum_devnum'} = ($out{'busnum'} && $out{'devnum'}) ? " \{$out{'busnum'}:$out{'devnum'}\}" : '';
  if ($out{'vendor'} && $out{'device'}) {
    $out{'address'} = " [$out{'vendor'}:$out{'device'}]";
  } elsif ($out{'address'}) {
    $out{'address'} = " [$out{'address'}]";
  } else {
    $out{'address'} = '';
  }

  # send formatted string, anything that didn't exist is empty (spacing added above)
  return "$out{'type'}$out{'id'}$out{'class'}$out{'description'}$out{'vendor_name'}$out{'address'}$out{'busnum_devnum'}";
}

exit;

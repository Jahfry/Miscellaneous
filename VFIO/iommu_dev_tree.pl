#!/usr/bin/perl
# iommu_dev_tree.pl - show IOMMU information including USB devices attached
#
# version: 20220505-1 - basically works for PCI+USB, formatting is bad, needs NET+BLOCK
#
# Details:
#   * Run with --man for easier consumption of the help below
#   * Tested on Proxmox VE 7.1 (based on Debian Bullseye)
#   * if your system has Ruby, this might do the job in a much shorter file:
#     https://gist.github.com/JaciBrunning/6be34dfd11b7b8cfa0aab57ad260c518
#
# Notes:
# * Subroutines placed directly below code that first use them (sorry?)
#
# * Devices read in below have added fields:
#   (unusual names used for sorting output)
#   ... '-type'           = "type" of device (PCI_slot, USB_device, etc)
##   ... 'x_output_format' = how to place device-specific vars into final output
#   ... '~devices_attached' = list of devices attached "below" this one
#
# POD:

=head1

=head1 NAME

    iommu_dev_tree.pl - tree of IOMMU groups and attached devices

=head1 USAGE

    iommu_dev_tree.pl [option ... use a single option]
      Options
             (none)       ... Default output (short with abbreviations)
        -v  |  --verbose  ... Long Output for other scripts/debugging
                                adds quotes (") to "Description"
        -d  |  --dumper   ... Output Perl Data::Dumper (very long)
        -r  |  --raw      ... Like -v but uses generic formatting (longest)
        -q  |  --quiet    ... Nothing except explicit additions (debugging)
        -h  |  --help     ... Help
        -m  |  --man      ... Full help

=head1 DESCRIPTION

    * Prints tree of IOMMU groups and devices attached
    * Output is abbreviated for readability by default
       + abbreviations limited by what I know of various devices
       + will still have some long lines that wrap
    * --dumper (-d) outputs in Perl Data::Dumper format

=head2 OUTPUT

  IOMMU group
   +- PCI devices
       +- USB Controllers
       +- USB Devices
  (the following not yet done)
       +- Storage Controllers (only tested with SATA)
           +- Hard disk
           +- SSD
       +- Network Controllers
           +- NIC
           +- Bridge

=head2 EXAMPLES

  ... Abstract:
    IOMMU_Group: 20
     +- PCI_slot <class> Description (vendor_name) [vendor:device]
         +- bus:device <usb_root#> Description [idVendor:idProduct]
             +- bus:device Description [idVendor:idProduct]
  ... Example (default):
    IOMMU_Group: 20
    +- 02:08.0 <USB> Matisse USB 3.0 Host Controller (AMD) [1022:149c]
       +- 001:001 <usb1> xHCI Host Controller [1d6b:0003]
          +- 001:002 Integrated Technology Express, Inc. IT8297 RGB LED Controller [048d:8297]
  ... Example (-v|--verbose):
    IOMMU_Group: 20
     PCI_slot: 0000:02:08.0 <USB Controller> "Matisse USB 3.0 Host Controller" (Advanced Micro Devices, Inc. [AMD]) [0x1022:0x149c]
      USB_root: 001:001 <usb1> "xHCI Host Controller" [1d6b:0003]
       USB_device: 001:002 "Integrated Technology Express, Inc. IT8297 RGB LED Controller" [048d:8297]


=head2 SOURCES

  * IOMMU Groups via '/sys/kernel/iommu_groups/*'
  * PCI Devices via
     '/sys/bus/pci/devices/*'
     `lspci -qmm`
  * USB Devices via:
     '/sys/bus/usb/devices/*'
     `lsusb`
  * Block devices (disks) via '/sys/block/*' ???
  * Network Interfaces via  '/sys/class/net/*' ???

=head2 ADDITIONAL COMMANDS

To get more information about a specific device:

  * PCI Device = `lspci -v -s [slot] -d [vendor:device]`
     Example:
       +- 02:08.0 <USB> Matisse USB 3.0 Host Controller (AMD) [1022:149c]
     Run: `lspci -v -s 02:08.0 -d 1022:149c`
       NOTE: if your system has more than 1 PCI Domain (rare):
         * run this script with '-v' ('--verbose') option
         * include domain (ie, '0000:') of PCI_slot
  * USB Device = `lsusb -v -d [idVendor:idProduct]`
     Example:
       +- 001:002 Integrated Technology Express, Inc. IT8297 RGB LED Controller [048d:8297]
     Run: `lsusb -v -s 001:002 -d 048d:8297`

=head1 REPO

https://github.com/Jahfry/Miscellaneous/blob/main/VFIO/iommu_dev_tree.pl

=cut

# MAIN::Use
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use File::Basename;
use Cwd qw(abs_path);
use Data::Dumper qw(Dumper);
use utf8;
binmode *STDOUT, ':encoding(UTF-8)';
$|=1; # auto flush, otherwise 'die' can print before the last 'print'

# MAIN::Options - parse command line ... https://metacpan.org/pod/Getopt::Long
#  ... note: "--man" not using '-verbose 2' in case perl-doc not installed
my %opt;
GetOptions (
  'verbose' => \$opt{'verbose'},
  'dumper' => \$opt{'dumper'},
  'raw' => \$opt{'raw'},
  'quiet' => \$opt{'quiet'},
  'h|help|?' => \$opt{'help'},
  'man' => \$opt{'man'},
) or pod2usage(-verbose => 0);
pod2usage(-verbose => 0) if $opt{'usage'};
pod2usage(-verbose => 1) if $opt{'help'};
pod2usage(-verbose => 99,-sections => "NAME|USAGE|DESCRIPTION|DETAILS|REPO") if $opt{'man'};

# if adding sata/block: `ls -aFl /sys/block`
# if adding NICs: `ls -aFl /sys/class/net`

# MAIN::lsusb - get USB device description from `lsusb`
my @list_lsusb = system2array("lsusb");
my %lsusb_by_vendorproduct;
for (@list_lsusb) {
  # $1=bus $2=device $3=vendor_id $4=product_id $5=device_name
  m/^Bus ([0-9]{3}) Device ([0-9]{3}): ID ([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4}) (.*)$/;
  $lsusb_by_vendorproduct{"${3}:${4}"} = {'bus',$1,'device',$2,'description',$5};
}

# MAIN:lspci - get PCI device description from `lspci`
my @list_lspci = system2array("lspci","-Dqmm");
my %lspci_by_id;
for (@list_lspci) {
  # $1=pci_id $2=class $3=vendor_name $5=description
  m/^([^ ]*) "([^"]*)" "([^"]*)" "([^"]*)" (.*)$/;
  $lspci_by_id{"${1}"} = {'class',$2,'vendor_name',$3,'description',$4};
}

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

# MAIN::USB - Build "%usb_devices" ... a tree of 'PCI_slot' > 'USB_dev' (can be multiple)
my %usb_devices;
my $dir_usb_devices = '/sys/bus/usb/devices';
my @usb_devices = sort(dir2array($dir_usb_devices));
for (sort(dir2array($dir_usb_devices))) {
  # build tree if 'usb#' (ie, 'usb1', etc), ignore others, they are collected recursively
  if (m/^(usb[^\s]*)/i) {
    my $usb_root = $1;
    my %usb_device = usbfiles2hash("${dir_usb_devices}/${usb_root}"); # sub recurses
    my $usb_device_path = abs_path("${dir_usb_devices}/${usb_root}");
    my $pci_id_match = qr/[\dA-Fa-f]{4}:[\dA-Fa-f]{2}:[\dA-Fa-f]{2}\.[\dA-Fa-f]{1}/;
    my @returned = $usb_device_path =~ m/^.*\/(${pci_id_match})\/([^\/]*)(.*)/;
    push @{ $usb_devices{${returned}[0]}{"$usb_root"} }, \%usb_device;
    $usb_devices{${returned}[0]}{'-type'} = 'USB_root';
  }
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

# SUB: usbfiles2hash("dirname") - read files with USB properties and return hash
#  ... recurses, called by: MAIN::USB
## convert to inner()?
sub usbfiles2hash {
  my $usb_dir = $_[0] or die "usbfile2hash() first argument must be a directory: $!";
  my %usb_device;
  my $skip_device = 0;
  my $id = basename($usb_dir);
  # @usb_vars = which files we care about parsing
  my @usb_vars = ('idProduct','idVendor','busnum','devnum','manufacturer','product');
  for (dir2array("$usb_dir")) {
    if (m/^[0-9]{1,}\-[0-9:\.\-]*$/) {
      my %usb_device_attached = usbfiles2hash("${usb_dir}/${_}"); # recursion
      if (%usb_device_attached) {
        push @{ $usb_device{'~devices_attached'}{$id} }, \%usb_device_attached;
      }
    }
    for my $key (@usb_vars) {
    $usb_device{'id'} = $id;
      if (-r "${usb_dir}/${key}") {
        $usb_device{"$key"} = file2string("${usb_dir}/${key}");
      }
      $usb_device{'driver'} = (-l "${usb_dir}/driver") ? basename(readlink("${usb_dir}/driver")) : '';
      if ($usb_device{'driver'} eq 'usb') {
        $usb_device{'-type'} = "USB_root";
      } elsif ($usb_device{'driver'} eq 'hub') {
        $usb_device{'-type'} = "USB_hub";
        unless ($usb_device{'product'} && $usb_device{'driver'}) { # don't add empty hubs/devices
          $skip_device = 1;
        }
      } elsif ($usb_device{'driver'}) {
        my $type = $usb_device{'driver'};
        $type =~ s/usb[-]*//;
        $usb_device{'-type'} = "USB_" . $type;
      }
    }
  }
  if ($skip_device) {
    return;
  } else {
    return %usb_device;
  }
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


# MAIN::IOMMU - Build "%iommu_groups" > 'PCI_id' hash tree of devices found above
my %iommu_groups;
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
    my $pci_class = $lspci_by_id{$pci_id}{'class'};
    my $pci_vendor_name = $lspci_by_id{$pci_id}{'vendor_name'};
    my $pci_description = $lspci_by_id{$pci_id}{'description'};
    %pci_device = ('id',$pci_id,'-type','PCI_slot','vendor',$pci_vendor,'device',$pci_device,'class',$pci_class,'vendor_name',$pci_vendor_name,'description',$pci_description);
    $iommu_group{'~devices_attached'}{$pci_id} = \%pci_device;
    $iommu_group{'-type'} = 'IOMMU_Group';
    if ($usb_devices{$pci_id}) {
      $iommu_group{'~devices_attached'}{$pci_id}{'~devices_attached'} = $usb_devices{$pci_id};
    }
  }
  push @{ $iommu_groups{$iommu_group} }, \%iommu_group;
}


# OUTPUT:: Use commandline ($opts) to call output style
if ($opt{'dumper'}) {       # --dumper = output in Perl Data::Dumper format
  $Data::Dumper::Terse = 1; print "\%iommu_groups = \n"; print Dumper \%iommu_groups;
  exit;
} else {
  if (! $opt{'quiet'}) {    # --quiet  = only output errors & explicit prints (for debugging)
    if ($opt{'raw'}) {      # --raw    = output entire hash via 'expand_generic'
      expand_generic(\%iommu_groups);
    } else {                # (no opts)= output via 'expand_specific'
      expand_specific(\%iommu_groups);
    }
  }
}

# SUB::expand_generic(\%hashref) - displays ALL data from a hash
#  ... recurses, called by: OUTPUT:: ... if option --raw
#  ... https://stackoverflow.com/a/13363234/2234204 (renamed from 'expand_references2')
#  ... does -not- depend on internal data format, any hash|array nest  should work
#      (if re-using code with a different data format in another script, use this)
sub expand_generic {
  my $indenting = -1;
  my $inner; $inner = sub {
    my $ref = $_[0];
    my $key = $_[1];
    $indenting++;
    if(ref $ref eq 'ARRAY'){
      print '  ' x $indenting,'ARRAY:';
      printf("%s\n",($key) ? $key : '');
      $inner->($_) for @{$ref};
    }elsif(ref $ref eq 'HASH'){
      print '  ' x $indenting,'HASH:';
      printf("%s\n",($key) ? $key : '');
      for my $k(sort keys %{$ref}){
        $inner->($ref->{$k},$k);
      }
    }else{
      if($key){
        print '  ' x $indenting,$key,' => ',$ref,"\n";
      }else{
        print '  ' x $indenting,$ref,"\n";
      }
    }
    $indenting--;
  };
  $inner->($_) for @_;
}

# SUB::expand_specific(\%hashref) - displays desired data from our hash
#  ... recurses, called by 'OUTPUT::' ... if no options OR --verbose
#  ... derived from expand_generic()
#  ... dependent on internal data format (use '--dumper' to see)
sub expand_specific {
  my $indent = -2; # starts at -2 to be 0 on first output
  my $level  = 1;  # tracks tree level (not indenting)
  my $id     = ''; # passes the previous $id to the next level for display
  my %rehash = (); # rebuilds key=values for display when a branch finishes
  my $inner;
  $inner = sub {   # recursive
    my $ref = $_[0];
    my $key = $_[1];
    $level++;
    $id = ($_[2]) ? $_[2] : '0' ; # if empty = first iteration, 0 is string for display
    if (ref $ref ne 'ARRAY' && ref $ref ne 'HASH') {
#      if ($key !~ m/-type|~devices_attached/) {
      if ($key ne '~devices_attached') {
        $rehash{$key} = $ref; # store, print all during beginning of next HASH
      } elsif (! $key) { # should never see this:
        print "\n",expand_specific_indenting($indent),"! (warning ... value = $ref)";
      }
    } elsif (ref $ref eq 'ARRAY'){
        for (sort {$a <=> $b} @{$ref}) { $inner->($_,'',"$key"); }
    } elsif (ref $ref eq 'HASH'){ # all expected output generated here
      if (%rehash) {   # if info from prior device, display now
        print expand_specific_deviceinfo->(\%rehash);
        %rehash = ();   # reset %rehash for next round of keys
      }
      $indent++;
      my $type = ($$ref{'-type'}) ? $$ref{'-type'} : '';
      my $id = ($key) ? $key : $id;   # pass $id down if not a $key
      if ($id eq '~devices_attached') { $indent--;
      } elsif ($type && $id ne '~devices_attached') {
        print "\n",expand_specific_indenting($indent),"${type}: ${id}";
      }
      my $keys_alpha = 0;
      for (keys %{$ref}) {
        last if ($keys_alpha);
        if (! m/^([0-9]*)$/) { $keys_alpha = 1; }
      }
      # sort numerically if able (ie, for IOMMU_Group)
      #if ($level == 2) {  # worked without needing $keys_alpha, but brittle
      if (! $keys_alpha) {
        for my $k(sort {$a <=> $b} keys %{$ref}){ $inner->($ref->{$k},$k,"$id"); }
      } else {
        for my $k(sort keys %{$ref}){ $inner->($ref->{$k},$k,"$id"); }
      }
      if ($id eq '~devices_attached') { $indent++; }
      $indent--;
    }
    $level--;
  }; # semi-colon (;) is important, ends 'inner = sub', don't remove
  $inner->($_,'',"$id") for @_;
  print expand_specific_deviceinfo->(\%rehash) . "\n\n";
}

#www
# SUB::expand_specific_deviceinfo(%rehash) - return string of keys:values per device
#  ... called by SUB::expand_specific()
sub expand_specific_deviceinfo {
  my $ref  = $_[0];
  my $type = ($ref->{-type}) ? $ref->{-type} : 0;
  my $rehash = '';
  for my $key (keys %{$ref}) {
    if ($key !~ /^(-type|id)$/) { # ?
      $rehash .= " $key=$ref->{$key}";
    }
  }
#  $rehash = " type=$ref->{-type} $rehash";

  return substr($rehash,0,60);
#  return $rehash;
}

# SUB::expand_specific_indenting('#') - formats indenting based on default or --verbose
#  ... called by SUB::expand_specific()
## add '> ' for default level 0 and pad others by 2?
sub expand_specific_indenting {
  my $indent = ($_[0]) ? $_[0] : 0;
  my ($indent_spaces,$indent_string,$indent_newline) = ('','','');
  if ($opt{'verbose'}) { # verbose uses minimal single space indenting
    $indent_spaces = ' ';
    $indent_string = $indent_spaces x $indent;
    unless ($indent) { $indent_newline = "\n"; }
  } elsif ($indent) { # default fancy indenting
### if going to try to get very fancy on a tree, we'd need to iterate sub-objects ahead of time in MAIN::
## what to know: "do we have another object in tree at this level? If not, no | needed and +- is \-"
    $indent--;
    $indent_spaces = '│   ';
    $indent_string = '   ' . ($indent_spaces x $indent) . '╞═ ';
  } else { # default 0 indent
    $indent_string = "➤ $indent_string";
  }
  return "$indent_newline $indent_string";
}

exit;


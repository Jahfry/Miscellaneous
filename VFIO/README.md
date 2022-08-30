# **Scripts and other information I have created for Linux VFIO using qemu**

## 1. Hookscript for invoking `driverctl`

* CODE LINK: [driverctl hookscript](../proxmoxVE/hookscript-driverctl.pl)
* This is actually in a different subdirectory
* Information about how I use this is [here](../proxmoxVE/05.ProxmoxGPUPassthrough.md#05d-driverctl-hookscript)
* I wrote this for my Proxmox machine but should generically work for other qemu-based VM hosts as long as you can install `driverctl` 
  + Debian-based should "just work" once `driverctl` is installed
  + Other systems may need paths adjusted

---

## 2. Device Tree

* CODE LINK: [dev_tree.pl](dev_tree.pl)
* **Not in a complete state but is working**
* Displays a list of devices with default sort by IOMMU groups (not just PCI devices, currently shows USB, future plan is Network and Block devices)
* Has a number of different output options
* See the POD information the script (or run script like `iommu_dev_tree.pl --manual`) for documentation
* Requires:
  * Perl with these common modules: Pod::Usage, File::Basename, Cwd, Data::Dumper, utf8
  * `lspci`, `lsusb`

---

Licenses: See [main README.md](../README.md) for licensing information.

# Proxmox VE NAS and Gaming VMs - README

***NOTE: I no longer use my Proxmox host as a gaming VM host, leaving this all here for historical reasons***

## Background:

I'm using Proxmox VE to run multiple VMs and containers. These files *should* be a log of everything I did to get my system configured. 

* ***Proxmox VE versions tested:***
    * 8.1.3 ... updated on 2023-12-13 to Proxmox VE 8.4 with no issues found so far, changes made in 7.1 carried through various updates
        * NOTICE: I moved back to gaming on a different machine, so I don't plan to update these docs for the forseeable future for that use case
    * ~~7.2~~ ... not yet tested, watching a couple of issues before moving to it [**updating docs for 7.2 now**]
    * 7.1 ... guide was originally started (should work mostly as-is on earlier versions)
* *These pages are detailed, geared more towards documentation vs quick start.*
* I have tested these directions multiple times on fresh installs **on my own system**, *but they can't include every detail for* ***your system***. Adding extra information to help you figure out workarounds. 
* If you find **something wrong**, (or have a question) please *[add an Issue](https://github.com/Jahfry/Miscellaneous/issues)*. This may may get linked to other sites and it will be helpful to not need to track all links. 

If you're configuring a similar system, start on [01. Hardware](01.Hardware.md). 

If here for a specific topic, look through 'Content Map' (next). 

---

## Content Map:

**NOTE:** I run my commands in many of these pages logged in as 'root' in a 'bash' shell. If you do something different you'll need to modify some commands (like adding `sudo` rather than using directly as copied. Or log in as root and run `bash` before pasting commands. 

1. If logged in to a non-root user (with permission), `su -` to switch to root (password for this is the root password)
2. If in a different shell, `bash` (I do use bash syntax at times)

* README (**this page**)
* [01. Hardware](01.Hardware.md)
    + [01.A. Hardware Used](01.Hardware.md#01a-hardware-used)
    + [01.B. RAM Timings](01.Hardware.md#01b-ram-timings)
        - [01.B.i. Many Warnings](01.Hardware.md#01bi-many-warnings)
        - [01.B.ii. More Thoughts and Info](01.Hardware.md#01bii-more-info-and-thoughts)
        - [01.B.iii. RAM Heat Spreaders](01.Hardware.md#01biii-ram-heat-spreaders)
        - [01.B.iv. BIOS Settings](01.Hardware.md#01biv-bios-settings)
* [02. Proxmox Install](02.ProxmoxInstall.md)
* [03. Proxmox Tweaks](03.ProxmoxTweaks.md)
    + [03.A. System Setup](03.ProxmoxTweaks.md#03a-system-setup)
        - [03.A.i Free/non-Subscription Repo](03.ProxmoxTweaks.md#03ai-freenon-subscription-repo)
        - [03.A.ii System Update](03.ProxmoxTweaks.md#03aii-system-update)
    + [03.B. UI Adjustments](03.ProxmoxTweaks.md#03b-ui-adjustments)
    + [03.C. Minimizing SSD Wear](03.ProxmoxTweaks.md#03c-minimizing-ssd-wear)
        - [03.C.i. Disable Proxmox High Availability Services](03.ProxmoxTweaks.md#03ci-disable-proxmox-high-availability-services)
        - [03.C.ii. log2ram - Move Frequently Written Files to RAM](03.ProxmoxTweaks.md#03cii-log2ram---move-frequently-written-files-to-ram)
        - [03.C.iii. Setting swappiness](03.ProxmoxTweaks.md#03ciii-setting-swappiness)
        - [03.C.iv. Results](03.ProxmoxTweaks.md#03civ-results)
    + [03.D. Lowering ZFS RAM use](03.ProxmoxTweaks.md#03d-lowering-zfs-ram-use)
    + [03.E. Fix Missing Drivers](03.ProxmoxTweaks.md#03e-fix-missing-drivers)
        - [03.E.i. 'regulatory.db'](03.ProxmoxTweaks.md#03ei-regulatorydb)
        - [03.E.ii. FAILED fixes for 'iwlwifi' and 'thermal_zone2'](03.ProxmoxTweaks.md#03eii-failed-fixes-for-iwlwifi-and-thermal_zone2)
* [04. Proxmox Extras](04.ProxmoxExtras.md)
    + [04.A. Importing Existing ZFS Pool](04.ProxmoxExtras.md#04a-importing-existing-zfs-pool)
    + [04.B. Useful Utilities](04.ProxmoxExtras.md#04b-useful-utilities)
    + [04.C. Networking](04.ProxmoxExtras.md#04c-networking)
* [05. Proxmox GPU Passthrough](05.ProxmoxGPUPassthrough.md)
    + [05.A. VFIO Kernel Modules](05.ProxmoxGPUPassthrough.md#05a-vfio-kernel-modules)
    + [05.B. Boot Parameters](05.ProxmoxGPUPassthrough.md#05b-boot-parameters)
    + [05.C. GPU IDs](05.ProxmoxGPUPassthrough.md#05c-gpu-ids)
+ [06. VM Windows 10](06.VMWindows10.md) (** in progress **)

---

## Credit Where It's Due

Sources I pulled various pieces from (apologies if I missed stuff):

* [Proxmox Forums](https://forum.proxmox.com/)
    + [Proxmox USB Bootstick mit log2ram oder folder2ram](https://forum.proxmox.com/threads/proxmox-usb-bootstick-mit-log2ram-oder-folder2ram.76583/) (German, use translate as necessary)
* [Reddit.com/r/Proxmox](https://www.reddit.com/r/Proxmox)
    + [Suggestions to decreasing wearout of ssd's in Proxmox](https://www.reddit.com/r/Proxmox/comments/u129sw/suggestions_to_decreasing_wearout_of_ssds_in/)

---

## Version/Changes:

* Version: 0.0.0-20220413
    + Not anywhere near ready for other people

---
> [^ [TOP OF PAGE](#user-content-proxmox-ve-nas-and-gaming-vms---README)] ... ***End:*** *Proxmox VE NAS and Gaming VMs - README*
> 
> \> NEXT: [01 - Hardware](01.Hardware.md)

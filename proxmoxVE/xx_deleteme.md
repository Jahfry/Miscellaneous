# Proxmox VE 7.1 NAS and Gaming VMs - 00 - Introduction

***files still in progress ... don't use this ... probably don't even read it yet***

I'm posting is for 3 reasons:

* Log what I did in case I need to redo the install later
* Have something others can sanity check for me
* If it's sane, allow other folks to use it like a guide

If you're configuring a similar system, you might want to start on the Hardware page. I've setup navigation links at the bottom of each page to let you page through each topic. 

If you're here for a specific topic, look through the listing here to find it. 

*These are long pages, geared more towards new users than experts.*

* While I have tested these directions multiple times on fresh installs **on my own system**, *I can't verify everything on* ***your system***. I'm trying to add enough extra information to help you figure out workarounds. 
* If you run into **something wrong**, *please [add an Issue](https://github.com/Jahfry/Miscellaneous/issues)*. This guide may get posted to other sites like Reddit and it will be helpful to not need to track all links. 
* Feel free to ask questions via 'Issues'.

---

## Content Map:

**NOTE:** I run my commands in many of these pages logged in as 'root' in a 'bash' shell. If you do something different just know you'll need to modify some commands rather than using directly as copied. Or log in as root and run `bash` before pasting. 

1. If logged in to a non-root user (with permission), `su -` to switch to root (password for this is the root password)
2. If in a different shell, `bash` (I do use bash syntax at times)

* [00. Introduction](00.Introduction.md)
* [01. Hardware](01.Hardware.md)
    + [01.A. Hardware Used](01.Hardware.md#01a-hardware-used)
    + [01.B. RAM Timings](01.Hardware.md#01b-ram-timings)
        - [01.B.i. Many Warnings](01.Hardware.md#01bi-many-warnings)
        - [01.B.ii. More Thoughts and Info](01.Hardware.md#01bii-more-info-and-thoughts)
        - [01.B.iii. RAM Heat Spreaders](01.Hardware.md#01biii-ram-heat-spreaders)
        - [01.B.iv. BIOS Settings](01.Hardware.md#01biv-bios-settings)
* [02. Proxmox Install](02.ProxmoxInstall.md)
* [03. Proxmox Tweaks](03.ProxmoxTweaks.md)
    + [03.A. UI Adjustments](03.ProxmoxTweaks.md#03a-ui-adjustments)
    + [03.B. System Setup](03.ProxmoxTweaks.md#03b-system-setup)
        - [03.B.i Free/non-Subscription Repo](03.ProxmoxTweaks.md#03bi-freenon-subscription-repo)
        - [03.B.ii System Update](03.ProxmoxTweaks.md#03bii-system-update)
    + [03.C. Minimizing SSD Wear](03.ProxmoxTweaks.md#03c-minimizing-ssd-wear)
        - [03.C.i. Disable Proxmox High Availability Services](03.ProxmoxTweaks.md#03ci-disable-proxmox-high-availability-services)
        - [03.C.ii. log2ram - Move Frequently Written Files to RAM](03.ProxmoxTweaks.md#03cii-log2ram---move-frequently-written-files-to-ram)
        - [03.C.iii. Setting swappiness](03.ProxmoxTweaks.md#03ciii-setting-swappiness)
        - [03.C.iv. Results](03.ProxmoxTweaks.md#03civ-results)
    + [03.D. Lowering ZFS RAM use](03.ProxmoxTweaks.md#03d-lowering-zfs-ram-use)
    + [03.E. Fix Missing Drivers](03.ProxmoxTweaks.md#03e-fix-missing-drivers)
        - [03.E.i. 'regulatory.db'](03.ProxmoxTweaks.md#03ei-regulatorydb)
        - [03.E.ii. FAILED fixes for 'iwlwifi' and 'thermal_zone2'](03.ProxmoxTweaks.md#03eii-failed-fixes-for-iwlwifi-and-thermal_zone2)
* [04. Proxmox Extras](04.ProxmoxExtras.md) ... ***in progress***
    + [04.A. Importing Existing ZFS Pool](04.ProxmoxExtras.md#04a-importing-existing-zfs-pool)
    + [04.B. Useful Utilities](04.ProxmoxExtras.md#04b-useful-utilities)
* [05.Proxmox GPU Passthrough](05.ProxmoxGPUPassthrough.md)
    + [05.A. VFIO Kernel Modules](05.ProxmoxGPUPassthrough.md#05a-vfio-kernel-modules)
    + [05.B. Boot Parameters](05.ProxmoxGPUPassthrough.md#05b-boot-parameters)
    + [05.C. GPU IDs](05.ProxmoxGPUPassthrough.md#05c-gpu-ids)
    + [05.D. Install and Configure 'driverctl'](05.ProxmoxGPUPassthrough.md#05d-install-and-configure-driverctl)
        - [05.D.i. Override GPU Modules](05.ProxmoxGPUPassthrough.md#05di-override-gpu-modules)
        - [05.D.ii. Reverting 'drivertctl' Overrides](05.ProxmoxGPUPassthrough.md#05dii-reverting-driverctl-overrides)
        - [05.D.iii. Switch Between Console Video and VFIO](05.ProxmoxGPUPassthrough.md#05diii-switch-between-console-video-and-vfio)


---

## Credit Where It's Due

Sources I pulled various pieces from (apologies if I missed stuff):

* [Proxmox Forums](https://forum.proxmox.com/)
    + [Proxmox USB Bootstick mit log2ram oder folder2ram](https://forum.proxmox.com/threads/proxmox-usb-bootstick-mit-log2ram-oder-folder2ram.76583/) (German, use translate as necessary)
* [Reddit.com/r/Proxmox](https://www.reddit.com/r/Proxmox)
    + [Suggestions to decreasing wearout of ssd's in Proxmox](https://www.reddit.com/r/Proxmox/comments/u129sw/suggestions_to_decreasing_wearout_of_ssds_in/)
* [Gareth's blog](https://gareth.com/index.php/2021/09/14/proxmox-7-installation/)



---
> [^ [TOP OF PAGE](#user-content-proxmox-ve-71-nas-and-gaming-vms---00---introduction)] ... ***End:*** *Proxmox VE 7.1 NAS and Gaming VMs - 00 - Introduction*
> 
> \> NEXT: [01 - Hardware](01.Hardware.md)
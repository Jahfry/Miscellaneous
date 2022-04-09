# TrueNAS Scale and Passing Through a Single GPU

*** IMPORTANT: This doesn't (yet?) work ***

TrueNAS Scale (abbreviated below as 'TNS') is a new (this was written 4/8/2022) Debian Linux-based version of TrueNAS with some really nice functionality around VMs. 

I was investigating the use of TrueNAS for my mixed NAS + gaming VM machine and really thought I was going to switch. Like, today, right now, my body is ready. 

However I ran into a major problem that makes it not feasible for my uses. You have to have more than 1 GPU in your system to attach one of them to a VM via PCI Passthrough (VFIO). 

Originally I wrote the following hoping that when I got to the end it would be working. So if the rest of this reads as a how-to, it's not, and that's why I added this top section saying "not working". 

The problem boils down to a common one in the world of appliantized operating systems ... the UI is great (and is a huge part of why I wanted to use TNS) but it has to have every function you want to use built in. If it doesn't there are 2 common outcomes:

1) The appliance gives you the freedom to do everything under the hood using the core OS (Proxmox is more in this direction), at the risk of the user breaking something

2) The appliance locks down everything so hard the user can't do anything not in the UI so that they can't be the thing that screwed up the system. 

TNS is straddling a middle-ground. It's not as open as some systems, but, you can get access to the core OS and tinker if you want. But in this case you won't be able to use the UI to do what you want which in large part removes the reason for using TNS. 

Please note, I'm not trying to give iX a hard time about this. I completely understand. My career was started with Cobalt Networks doing much the same type of appliantization for web servers back in the late 90s. I completely get how complicated it is to build this type of system and keep it from becoming fragile. 

I also understand I'm not the focus target for TrueNAS Scale. These days I'm trying to have fewer machines (I'm down to 2) that I need to maintain while using VFIO to let me FEEL like I have a bunch of machines. TrueNAS added VM/VFIO but it's not the core focus. But it was really exciting to see an alternative to Proxmox as I really liked the NAS focus of TNS and the simplicity of the k3s / Docker apps in TNS. 

I'm probably going back to Proxmox for now. Which is fine, I'm not saying that in a ragequit kind of way. I'm just noting that so that it's clear this note may be a bit of a dead-end. Hopefully iX has the time to look at implementing something like I've detailed below in the future because I likely will be back and documenting weird setups using it. I also have a bit of hope, just because TrueNAS Scale even exists, that iX might be looking to capture a wider market going forward. In which case I think setups like I was hoping for are a very interesting market to go for. You know, the almost-dinosaurs who want the fancy newness but with a better UI experience. 


---

There's really "only" 1 more Debian package that TrueNAS needs to make passing through single GPUs (driverctl). All of the other commands needed already exist on TrueNAS Scale's default install. BUT ... the UI also needs some architecture to support it. 

*(I said "single GPU" a bunch of times here. I do have 2 GPUs, but the intent is to have both used by 2 different VMs at once time. Dedicating one to the console video is just more than I want to give up.)*


In an ***ideal*** world, the UI would understand how to use `driverctl` such that the UI could bind to it for boot. Then, once booted, give the user the option to use the GPU on a VM (using `driverctl` to unbind the GPU, possibly when the VM is being fired up). It could print a message to the console prior to detaching the GPU so that there is a reminder on the console video like 'GPU currently detached for use with X' (X being a VM, a container, etc). Then if/when the VM is shut down, the UI process could rebind the console to the GPU. 

That ideal scenario isn't strictly necessary, the system could simply run headless, but doing all of that would allow the user to retain the use of the console video if they ever needed it and make it usable by default whenever a VM wasn't using the GPU.


## Problem #1: TrueNAS Scale doesn't allow a single GPU to be isolated for VMs

TNS will reserve the first (sometimes only) GPU in the system for TNS's local console. This is a problem if you are wanting to use that GPU for passthrough to a VM. 

To see this you can go to `System Settings` > `Advanced` > `Isolated GPU Devices` > `Configure`. Attempting to isolate the GPU the host has attached to gives this error: ***"At least 1 GPU is required by the host for it’s functions. With your selection, no GPU is available for the host to consume."*** 

Similarly, if you try to create a VM with the GPU that is attached to the host in `Virtualization` > `Add` you'll be met with ***"At least 1 GPU is required by the host for it’s functions. With your selection, no GPU is available for the host to consume."***

While it is definitely useful to have a dedicated console (especially if having problems booting), once the system is up and running it is generally unused. And in fact many people run their TrueNAS devices headless (no GPU at all, possibly having used one during installation and then removing for other cards). 

The goal for this problem is to see if we can unbind the driver. We probably won't be able to isolate it in the UI. We may have problems with assigning these as passthrough to VMs created in the UI as well. I've posted a feature request about all of this [here](https://www.truenas.com/community/threads/scale-requires-gpu-for-host-request-allow-single-gpu-for-passthrough.100390/) but I have no idea if or when iX devs might get around to this. TNS first release is very very new at the time of this writing (4/8/2022). 

I've done this on a stock Debian system before using `driverctl`, which is very nice for binding/unbinding GPUs on the fly while the system is running (at least on Nvidia cards, tested with a GTX 1060 and 3080TI). Unfortunately this leads to Problem #2:

### Problem #1a: TrueNAS Scale locks down `apt`

On a stock Debian system (or Ubuntu, Proxmox, etc) the admin has access to the `apt` command to install packages on the system. While TNS is based on Debian (Bullseye currently) it is what I term "appliantized" and sets permission for `apt` to not be executable. While this is an easy fix it does have implications for future updates and management. 

I found someone else dealing with this issue [here](https://xtremeownage.com/2022/03/26/truenas-scale-re-enable-apt-get/) but I disagree with the aggressiveness of their solution. What they do is enable `apt` via changing permissions (which we're going to do, too) but then they wipe out the other apt sources in /etc/apt/sources.lst saying that since apt isn't enabled that they just left the default Debian sources. 

**I'm only guessing here**, but, I have worked for appliantization outfits before and given the sources in sources.lst are pointing at very specific TNS targets ... I'm guessing that TNS ***does use apt for updates*** even with the root user unable to exec `apt` by permission. 

So, we're going to go about this a little differently after the first step:

* open a TNS shell ( `System Settings` > `Advanced` > `Shell`), which will log you in as root. The rest of these steps are commands:
* `chmod +x /bin/apt*                                    # allow root to run apt`
* `cp /etc/apt/sources.list /etc/apt/sources.list.orig   # backup sources.list`
* `echo deb http://deb.debian.org/debian bullseye main > /etc/apt/sources.list`
* `apt update                                            # pull in the additional packages list`
* `apt install driverctl                                 # install driverctl`
* `mv /etc/apt/sources.list /etc/apt/sources.list.debian # in case we ever need it again`
* `mv /etc/apt/sources.list.orig /etc/apt/sources.list   # go back to the original file`
* `apt update                                            # make sure the system sees the original list`

## Problem #1b: Detaching the GPU from the host

Now we're going to user `driverctl` to try detaching the GPU from the host. To do this you'll need to know the id for the GPU devices (modern GPUs have a display device and a separate audio device). I use this script, saved as `iommu-list`:

```
#!/usr/bin/bash
shopt -s nullglob
for g in `find /sys/kernel/iommu_groups/* -maxdepth 0 -type d | sort -V`; do
    echo "IOMMU Group ${g##*/}:"
    for d in $g/devices/*; do
        echo -e "\t$(lspci -nns ${d##*/})"
    done;
done;
```

* Save that to `iommu-list`
* Make it exectuable with `chmod +x ./iommu-list`
* Run it via `iommu-list` and you should see output like this (yours will be longer, this is snipped):

<pre>
IOMMU Group 26:
          07:00.0 Ethernet controller [0200]: Realtek Semiconductor Co., Ltd. RTL8125 2.5GbE Controller [10ec:8125] (rev 01)
IOMMU Group 27:
        0b:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP106 [GeForce GTX 1060 6GB] [10de:1c03] (rev a1)
        0b:00.1 Audio device [0403]: NVIDIA Corporation GP106 High Definition Audio Controller [10de:10f1] (rev a1)
IOMMU Group 28:
        0c:00.0 Non-Essential Instrumentation [1300]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse PCIe Dummy Function [1022:148a]
</pre>

*IOMMU Group 27:* is the section with the GPU devices. If you see MORE devices in the same IOMMU group, you need to investigate turning on IOMMU in your UEFI / BIOS before coming back to this point. 

In this example the 2 devices I'm going to control using `driverctl` are **0b.00.0** and **0b.00.1**. 

Take a look at which devices are *currently* claiming these devices with:

`driverctl list-devices` (look through the list to find your devices, mine in the example being 0b.00.0 / 0b.00.1)

We can unbind the GPU from the host via the following 2 commands.

**NOTES:**

* Notice that the format of the command is different from the output of the `iommu-list` script. Instead of **0b.00.0** convert (whatever your device showed as) to be the equivalent of **0000:0b:00.1** (prepend '0000:' and change the first '.' to ':')
* At this point the host console display will stop functioning as the host no longer controls it. If you reboot the system at this point you'll see the console output for most of the boot-up but it will stop scrolling when it gets to the video driver and **you won't be able to see the console menu after booting** while the override is set. 

`driverctl set-override 0000:0b:00.0 vfio-pci`
`driverctl set-override 0000:0b:00.1 vfio-pci`

## Problem 2: TrueNAS still thinks the host owns the GPU

Technically the GPU is now available to be bound to a GPU. But ... if you want to use the TrueNAS UI to set up said VM ... it will still give all the same errors we saw at the beginning of this file. 

This is the point at which iX (or someone more familiar with TNS than me) will need to modify the UI. 





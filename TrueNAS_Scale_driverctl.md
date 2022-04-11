# TrueNAS Scale and Passing Through a Single GPU


**Background**
TrueNAS Scale (abbreviated below as 'TNS') is a new (v22.02, this was written 4/8/2022) Debian Linux-based version of TrueNAS with some really nice functionality around VMs. 

I was investigating the use of TrueNAS for my mixed NAS + gaming VM machine and really thought I was going to switch. Like, today, right now, my body is ready. 

However I ran into a major problem that makes it not feasible for my uses. You have to have more than 1 GPU in your system to attach one of them to a VM via PCI Passthrough (VFIO) with the UI as it is released. 

The problem boils down to a common one in the world of appliantized operating systems ... the UI is great (and is a huge part of why I wanted to use TNS) but it has to have every function you want to use built in. If it doesn't there are 2 common outcomes:

1) The appliance gives you the freedom to do everything under the hood using the core OS (Proxmox is more in this direction), at the risk of the user breaking something

2) The appliance locks down everything so hard the user can't do anything not in the UI so that they can't be the thing that screwed up the system. 

TNS is straddling a middle-ground. It's not as open as some systems, but, you can get access to the core OS and tinker if you want. But in this case you won't be able to use the UI to do what you want which in large part removes the reason for using TNS. 

Please note, I'm not trying to give iX a hard time about this. I completely understand. My career was started with Cobalt Networks doing much the same type of appliantization for web servers back in the late 90s. I completely get how complicated it is to build this type of system and keep it from becoming fragile. 

I also understand I'm not the focus target for TrueNAS Scale. These days I'm trying to have fewer machines (I'm down to 2) that I need to maintain while using VFIO to let me FEEL like I have a bunch of machines. TrueNAS added VM/VFIO but it's not the core focus. But it was really exciting to see an alternative to Proxmox as I really liked the NAS focus of TNS and the simplicity of the k3s / Docker apps in TNS. 

I'm probably going back to Proxmox for now. Which is fine, I'm not saying that in a ragequit kind of way. I'm just noting that so that it's clear this note may be a bit of a dead-end. Hopefully iX has the time to look at implementing something like I've detailed below in the future because I likely will be back and documenting weird setups using it. I also have a bit of hope, just because TrueNAS Scale even exists, that iX might be looking to capture a wider market going forward. In which case I think setups like I was hoping for are a very interesting market to go for. You know, the almost-dinosaurs who want the fancy newness but with a better UI experience. 

**Problem:** TrueNAS Scale doesn't allow a single GPU to be isolated for VMs

TNS will reserve the first (sometimes only) GPU in the system for TNS's local console. This is a problem if you are wanting to use that GPU for passthrough to a VM. 

To see this you can go to `System Settings` > `Advanced` > `Isolated GPU Devices` > `Configure`. Attempting to isolate the GPU the host has attached to gives this error: ***"At least 1 GPU is required by the host for it’s functions. With your selection, no GPU is available for the host to consume."*** 

Similarly, if you try to create a VM with the GPU that is attached to the host in `Virtualization` > `Add` you'll be met with ***"At least 1 GPU is required by the host for it’s functions. With your selection, no GPU is available for the host to consume."***

While it is definitely useful to have a dedicated console (especially if having problems booting), once the system is up and running it is generally unused. And in fact many people run their TrueNAS devices headless (no GPU at all, possibly having used one during installation and then removing for other cards). 

I've posted a feature request about all of this [here](https://www.truenas.com/community/threads/scale-requires-gpu-for-host-request-allow-single-gpu-for-passthrough.100390/) but I have no idea if or when iX devs might get around to this.

I've done this on a stock Debian system before using `driverctl`, which is very nice for binding/unbinding GPUs on the fly while the system is running (at least on Nvidia cards, tested with a GTX 1060 and 3080TI). Unfortunately this leads to Problem #2:

*So what have I done?*

I hacked the TrueNAS UI to allow isolation of a single GPU. 

But ... 


***BIG MASSIVE WARNING:*** **I didn't get to the point where I had passthrough actually working in bringing up a video output on my Windows VM**. 

That warning isn't big and massive because I don't think my UI hack worked. I'm sure it did. But what I haven't done up to this point is actually finish the process of making video output work on the VM (the VM does bind and allow driver installs for the GPU). 

I'm debating internally about whether I stick with TNS at this point or go back to a more generic Debian or Fedora (or maybe Proxmox). 

*What I did get working* before I decided I'm going to let TrueNAS Scale cook more for VMs was:

* Binding a isolating a single GPU
* Attaching that GPU to a Windows VM
* Installing the nvidia driver and having Windows report that the adapter is working (no code 31 or 43)
* Repeated this entire process 2 more times on fresh installs to make sure my UI hacks worked solidly

My assumption is that the missing parts will revolve around GPU BIOS (romfile paramater). 

I was probably very very close to getting it all done. And I might revisit this. But for now I'm personally better off switching to a standard distro, learning the intricacies better (my prior VM passthroughs were on Unraid, so I didn't have a lot of under the hood experience, and a bit on Proxmox). 

I'm providing these notes in case anyone else really wants to give it a shot. The main value here being in seeing how to hack the TrueNAS Scale UI to stop erroring out on trying to isolate a single GPU. 


**NOTES:**

* If you see 'TNS' below it's shorthand for 'TrueNAS Scale'. 
* This was all written against the first release version of TNS (22.02)
* I'm not writing up every detailed step of TNS install/setup here. 
* **These changes are NOT going to be supported by iX**
* If anything updates the UI, you'll need to reapply the changes
* I know almost nothing about Angular or TNS's middlewared, I'm just hacking where I saw the relevant error condition
* This very well *could* break something else later on, but I think it's working
* (do I need to say it? You do this at your own risk)

---

## Install TrueNAS to your boot disk of choice

### Setup up some basics on TNS

* Create a storage pool

* Create a user credential for logging in with SSH (permit sudo)
    ... yes, TNS has a shell interface in the UI, you *can* just use that. Since I am a nano user, I want my ^W to maybe not close the browser. 

* Enable SSH service

* Connect to the system with SSH
    ... login as the regular user you created with sudo permissions
	... I'm lazy about using `sudo` so once connected, issue `su -` and enter the root password (or remember to add `sudo` to following commands). 

---

## Back up the files we're going to be modifying

* the first 4 are client-side sanity checks prior to submitting (final "Save") data to the server
* the last file is a server-side sanity check after a submit (final "Save")

```
cp /usr/share/truenas/webui/609-es2015.f059fa779e0b83eaa150.js /usr/share/truenas/webui/609-es2015.f059fa779e0b83eaa150.js.orig
cp /usr/share/truenas/webui/609-es5.f059fa779e0b83eaa150.js    /usr/share/truenas/webui/609-es5.f059fa779e0b83eaa150.js.orig
cp /usr/share/truenas/webui/715-es2015.b3b1eb8aed99ad4e4035.js /usr/share/truenas/webui/715-es2015.b3b1eb8aed99ad4e4035.js.orig
cp /usr/share/truenas/webui/715-es5.b3b1eb8aed99ad4e4035.js    /usr/share/truenas/webui/715-es5.b3b1eb8aed99ad4e4035.js.orig
cp /usr/lib/python3/dist-packages/middlewared/plugins/system_advanced/config.py /usr/lib/python3/dist-packages/middlewared/plugins/system_advanced/config.py.orig
```

---

## Edit the UI to prevent the error regarding needing 1 GPU for the host

What are we doing?

* The sections in these 4 files are what the TNS UI will use to validate when you try to select a GPU to isolate
* These files are all minified (all of the code is on a single line), so I've given easy commands to edit the files
* The change is always the "if()" that contains the text "1 GPU" (the if() happens before "1 GPU", but you can search for that text and backtrack). 
* Change the if() condition from "greater than or equal" (ie, >=) to "greater than" (ie, >). 
* Each file has a different syntax in the "if()", hence the need for 4 different edits
* **IMPORTANT:** replacements in the last 2 files below happen in 2 places, identically. So don't just replace the first (the |g in the commands handles this if pasting the perl commands)

*These commands will edit the files for you:*

```
perl -i -pe 's|\Qif([...t].length>=(null===(i=this.availableGpus)\E|if([...t].length>(null===(i=this.availableGpus)|g' /usr/share/truenas/webui/609-es2015.f059fa779e0b83eaa150.js
perl -i -pe 's|\Qif(t(a).length>=(null===(o=e.availableGpus)\E|if(t(a).length>(null===(o=e.availableGpus)|g' /usr/share/truenas/webui/609-es5.f059fa779e0b83eaa150.js
perl -i -pe 's|\Q{name:"gpus"});if(i.length&&i.length>=o.options.length)\E|{name:"gpus"});if(i.length&&i.length>o.options.length)|g' /usr/share/truenas/webui/715-es2015.b3b1eb8aed99ad4e4035.js
perl -i -pe 's|\Q{name:"gpus"});if(r.length&&r.length>=c.options.length)\E|{name:"gpus"});if(r.length&&r.length>c.options.length)|g' /usr/share/truenas/webui/715-es5.b3b1eb8aed99ad4e4035.js

```

*Or if you want to do it yourself:* 

(no need to both run the commands above and do these edits, they are identical, just documenting what the commands do)

* Specific list of replacements, per file:
    * '/usr/share/truenas/webui/609-es2015.f059fa779e0b83eaa150.js'
	    * `if([...t].length>=(null===(i=this.availableGpus)` (original)
		* `if([...t].length>(null===(i=this.availableGpus)` (edited)
	* '/usr/share/truenas/webui/609-es5.f059fa779e0b83eaa150.js'
	    * `if(t(a).length>=(null===(o=e.availableGpus)` (original)
		* `if(t(a).length>(null===(o=e.availableGpus)` (edited)
	* '/usr/share/truenas/webui/715-es2015.b3b1eb8aed99ad4e4035.js' (this change occurs twice)
	    * `{name:"gpus"});if(i.length&&i.length>=o.options.length)` (original)
		* `{name:"gpus"});if(i.length&&i.length>o.options.length)` (edited)
	* '/usr/share/truenas/webui/715-es5.b3b1eb8aed99ad4e4035.js' (this change occurr twice)
	    * `{name:"gpus"});if(r.length&&r.length>=c.options.length)` (original)
		* `{name:"gpus"});if(r.length&&r.length>c.options.length)` (edited)
		

There is 1 more file you need to edit. This file is used to validate the GPU selection -after- you've successfully submitted the form with the "Save" button. 

'/usr/lib/python3/dist-packages/middlewared/plugins/system_advanced/config.py'

This file isn't minified, so it's rather easy to edit. Just search for the section containing "1 GPU" to find the right block. 

The section to comment out:

<pre>
            if len(available - provided) < 1:
                verrors.add(
                    f'{schema}.isolated_gpu_pci_ids',
                    'A minimum of 1 GPU is required for the host to ensure it functions as desired.'
                )
</pre>

becomes:

<pre>
#            if len(available - provided) < 1:
#                verrors.add(
#                    f'{schema}.isolated_gpu_pci_ids',
#                    'A minimum of 1 GPU is required for the host to ensure it functions as desired.'
#                )
</pre>



---

## Finish up and restart the UI

If you don't do these 3 steps then the error message will continue to come up when trying to isolate the single GPU. 

* delete the cached config.py (it will be rebuilt)

```
rm /usr/lib/python3/dist-packages/middlewared/plugins/system_advanced/__pycache__/config.cpython-39.pyc
```

* restart the middlwared UI to load the changes to the 'config.py' file 


```
service middlewared restart
service nginx restart
```

* Shift-Reload the TrueNAS UI in your browser to reload cached UI javascript. 


---

## See if it worked

* In the TNS UI, go to 'System Settings' > 'Advanced' > 'Isolated GPU Device(s)'
* Try selecting your GPU now and see if it allows you to set it (if you have more than 1, try isolating all of them)
	* If you are still unable to do the final "Save" when isolating the GPU, verify the changes made so far and maybe try rebooting
	    ... the final "Save" error is handled by the 'config.py' changes

---

## Setup a Windows VM 

I'm not going to document *everything* about this process. There are some videos on Youtube that cover the TNS UI for Virtualization. But I will make some notes on how I did it. 

**IMPORTANT:** I'm writing these instructions using a Nvidia GTX 1060. Things may go a bit differently if you're on AMD. 

### *Naming note:* Don't to make your VM name very long. 

For example I named mine "Windows_10_Pro_64bit_MASTER" to be descriptive. The problem you can run into is, even if the name fits the character limit, you may later want to clone the VM to test something else. And you can then run into the max 63 character file name on TNS. The character limit includes the path (zvol, dataset, directory name, etc). 

When I try to clone my first VM with a name more than a couple of characters, I get this error if the name is more than 3 characters:

<pre>
! ValidationErrors
[ENAMETOOLONG] vm_create.devices.0.attributes.path: Disk path /dev/zvol/myarray/VM-ssd-1/Windows_10_Pro_64bit_MASTER-siggio_Clone is too long, reduce to less than 63 characters
</pre>

And it's worse if I want to clone the clone, as it will append both clone names, such that I can't clone a clone because I don't even have 1 character left available. 

Renaming the VM in TNS UI doesn't help as the underlying file name is the problem, and it doesn't change upon a VM name change. This isn't unique to TNS, though some GUI assistance would be helpful here. 

Minimizing the length of the dataset name and/or VM name would go a long way to being able to name clones descriptively later on, not just the main VM. 

Or name it something VERY short (like "1", "2", etc) when first creating the VM and then rename it in the UI afterwards for descriptiveness.

### Other Windows VM setup notes

* When initially installing Windows, **don't** attach a GPU yet. Use the VNC display to start. 
* Do the initial install and make sure to allow remote desktop
	* "Search" for 'Remote Desktop Settings'
	* Click on for 'Enable Remote Desktop'
* Take note of the IP your VM has by opening a 'cmd' window on it and doing `ipconfig`, noting the 'IPv4 Address'
* Connect to that IP from another machine using Remote Desktop (RDP)
    * This isn't strictly necessary if everything later on works. But, it makes sure you have a different way to view your VM desktop after removing the VNC display if the passthrough doesn't work (but it does need to successfully boot, something I had problems with)
    * From another Win10/Win11 machine just run 'Remote Desktop Connection'
	* Put the IP of your VM from previous step in the address
	* If you need to change the username (maybe 1 machine has a local account but the other has a Microsoft account), click 'More Choices' > 'Use a Different Account'
    * If it works, you'll see the desktop in your RDP client and the VNC desktop will log you out (if you log back in via the VNC desktop, the RDP connection will close, all is good)
    * (going past this assumes RDP is working, if not, keep trying)
* On the VM, disable "Fast Start", so that a shutdown really does a full shutdown
    * I'm unsure if VMs have this issue, but I hate Fast Start
	* [More info](https://www.windowscentral.com/how-disable-windows-10-fast-startup)
    * 'Control Panel' > 'Power Options'
	* 'Power & Sleep Settings' > 'Choose what the power button does' > 'Change settings that are currently unavailable' > **uncheck** 'Turn on fast startup (recommended)' > 'Save changes'
* On the VM, install the VirtIO drivers
    * I keep a copy on the same volume that I keep the Win10 Isolated
	* Shut down the VM
	* Edit the CDROM device to point to the VirtIO Isolated
	* Start the VM and navigate to the CD-ROM to start the install
* In the TNS UI:
	* Shut down the VM (either from the TNS UI or the Windows RDP connection will work for this one)
    * 'Virtualization' > click the drop-down on the right side of the VM you're working on > 'Devices' > click the 3dot hamburger menu next to 'DISPLAY' > 'Delete' ... this will remove your VNC display (why we enabled RDP)
	* 'Virtualization' > click the drop-down for the VM again > 'Edit' > (scroll to the bottom) > under "GPU's" select your GPU > 'Save'
	* Start the VM again
        * WARNING: if you have your TNS console video visible, it will stop updating at this point
		* You can see what happened to the TNS console video by doing this in the TNS shell (SSH): `driverctl list-devices`

> What driverctl used to report:

<pre>
0000:0b:00.0 nvidia
0000:0b:00.1 snd_hda_intel
</pre>

> What it reports now:

<pre>
0000:0b:00.0 vfio-pci [*]
0000:0b:00.1 vfio-pci [*]
</pre>

* The above verifies that the GPU that was on the host originally is now attached to your GPU. Though it probably isn't all working just yet. The "[*]" means the device is active on that interface when checked. 
    * Connect to the VM using RDP again. 
	* Opening 'Device Manager', if done quickly, will likely show that a display adapter is disabled with 'code 31'. This just means the driver isn't loaded yet. 
	    * If your system is connected to the internet, Windows should automatically download and install the Nvidia driver and GeForce software
		* If not, you'll need to get the driver installer from Nvidia copied to your VM and install it
		* Once the driver is installed and running, code 31 should go away ... but ...
		* You *might* see 'code 43' at this point. That's why I delete the VNC display as when I redid this with that step, I stopped getting 'code 43' ... but ...
		* I still didn't actually have video output at this point, just a black screen from the display disconnecting from the TNS host. 

---

## This is where I paused to consider my life choices

* my VM can boot if it has the GPU attached as long as it also has a VNC output. 
* Device Manager shows code 31 on the GPU until the nvidia driver is installed
* After installing the nvidia driver on the VM the code 31 goes away and code 43 doesn't appear
* Removing the VNC adapter and starting the VM results in never getting the system to boot
* Do I just need a romfile? Quite possibly. 

At this point the initial problem is solved but I'm just not fluent enough with configuring VMs. 

But ... I'm starting to realize how many little things with using TNS as a VM Host are going to get to me over time. The storage UI is flat out great, but, once I have storage running ... it's the VMs and containers I'm going to want to focus on most. 

My hope had been that the TNS UI would be able to make VMs "just work", but overall the work involved ends up being similar to more traditional methods and there are fewer guides out there for TNS as it's quite young. So it may not make sense to keep going this route if the work ends up the same. 

		
### Prevent nvidia and snd_hda_intel modules were never loaded by the host

I didn't need to do this to get the GPU isolated, and it didn't end up fixing the no video problem on the VM, just making notes in case I come back to this project. 

* Create a file named '/etc/modprobe.d/custom-blacklist.conf' that contains:

<pre>
# custom blacklist created to block the host from using the nvidia driver
# this is only for hacking in single gpu passthrough support
# don't forget to `update-initramfs -u` and reboot after adding this file

blacklist nvidia
blacklist snd_hda_intel
</pre>

* `update-initramfs -u`
* reboot

---

## IOMMU additional apps

* These are both optional things, feel free to skip them until you need them.
* Create a script called 'iommu-list' with the following contents

```
#!/bin/bash
# iommu-list
shopt -s nullglob
for g in `find /sys/kernel/iommu_groups/* -maxdepth 0 -type d | sort -V`; do
    echo "IOMMU Group ${g##*/}:"
    for d in $g/devices/*; do
        echo -e "\t$(lspci -nns ${d##*/})"
    done;
done;
```
* `chmod +x iommu-list`
    *run `iommu-list` to get a breakdown of your IOMMU groups and make sure IOMMU is working for you. 
    * A snippet of the output on my system showing the important group for my GPU (there will be many more entries):

<pre>
[snip]
IOMMU Group 27:
        0b:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP106 [GeForce GTX 1060 6GB] [10de:1c03] (rev a1)
        0b:00.1 Audio device [0403]: NVIDIA Corporation GP106 High Definition Audio Controller [10de:10f1] (rev a1)
[snip]
</pre>

* Install the Debian package for `driverctl`
 	* look at http://ftp.debian.org/debian/pool/main/d/driverctl/ to make sure the next command is the latest version
  	* `wget http://ftp.debian.org/debian/pool/main/d/driverctl/driverctl_0.111-1_all.deb`
   	* `dpkg -i driverctl_0.111-1_all.deb`
	    ... `apt` is purposefully not executable by iX so I don't enable it (though you can simply give '/bin/apt*' executable permissions)
		... The main Debian repository isn't configured in '/etc/apt/sources.list' ... I don't recommend messing with that as it does appear iX uses apt repos even though it isn't executable by default. 
		... Importantly this means `driverctl` will never be updated if a new version comes out (unless iX adds driverctl to a future release)

* Look at the output of driverctl ... the following are with an unmodified TNS install
    * `driverctl list-devices`
        ... output should look similar to this but will vary with your hardware (there will be many more entries):
        ... notice that '0000:0b:00.0' and '0000:0b:00.1' correspond to '0b:00.0' and '0b:00.1' from the output of `iommu-list`
<pre>
[snip]
0000:0b:00.0 nvidia
0000:0b:00.1 snd_hda_intel
[snip]
</pre>

---

## Things I'd like to see in a future TrueNAS Scale release:

TrueNAS features wanted:

* Supported single GPU passthrough, possibly using something dynamic like driverctl
* GPU ROM file UI
* More consistent UI between initial VM setup and later editing of options (example: create with VNC display, deleting it is in a different UI paradigm, and then how would you re-add it later?)
* CPU Pinning
* Support for changing linux swappiness
* "Notes" notepad on each major item like individual VMs, Applications, Groups, pools. Meta data so that we can keep notes directly in the UI. 

I really think TNS has the capability to embrace the VM/homelab space. That wasn't the original direction of TrueNAS/FreeNAS, but, if they want to expand market share into this realm they're well on the way. I'm likely the one at fault for trying to do more than TNS intended. But I also feel that the Passthrough concept is closer-enough to mainstream that with some tweaks TNS could really shine there. 


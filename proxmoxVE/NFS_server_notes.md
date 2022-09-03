Crib notes for enabling NFS on Proxmox. 

NOTE: This isn't for a final configuration, just to get access to an existing ZFS pool to fix the contents. 

`apt-get update`

`apt-get install nfs-common nfs-kernel-server`

`nano /etc/exports`

<pre>
# add this to file (change to what you need)
/Data 10.0.0.0/255.255.192.0(rw,no_root_squash)
</pre>

`systemctl start nfs-kernel-server`

`systemctl enable nfs-kernel-server`


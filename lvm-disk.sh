#!/usr/bin/env bash

set -o pipefail
set -o nounset
set -o errexit

################################################################
# Migrate existing folder to a new partition
#
# Globals:
#   None
# Arguments:
#   1 - the path of the disk or partition
#   2 - the folder path to migration
#   3 - the mount options to use.
# Outputs:
#   None
################################################################
# migrate_and_mount_disk() {
#     local disk_name=$1
#     local folder_path=/mnt/$2
#     local mount_options=$3
#     local temp_path="/tmp/root${folder_path}"
#     local old_path="${folder_path}-old"

#     # install an ext4 filesystem to the disk
#     mkfs -t ext4 ${disk_name}

#     # check if the folder already exists
#     if [ -d "${folder_path}" ]; then
#         FILE=$(ls -A ${folder_path})
#         >&2 echo $FILE
#         mkdir -p ${temp_path}
#         mount ${disk_name} ${temp_path}
#         # Empty folder give error on /*
#         if [ ! -z "$FILE" ]; then
#             cp -Rax ${folder_path}/* ${temp_path}
#         fi
#     fi

#     # create the folder
#     mkdir -p ${folder_path}

#     # add the mount point to fstab and mount the disk
#     echo "UUID=$(blkid -s UUID -o value ${disk_name}) ${folder_path} ext4 ${mount_options} 0 1" >> /tmp/root/etc/fstab
#     mount -a

#     # if selinux is enabled restore the objects on it
#     if selinuxenabled; then
#         restorecon -R ${folder_path}
#     fi
# }

disk_name='/dev/nvme1n2'

# partition the disk
parted -a optimal -s $disk_name \
    mklabel gpt \
    mkpart bbp 1MB 2MB \
    set 1 bios_grub on \
    mkpart boot ext4 2MB 500MB \
    mkpart root ext4 500MB 100%

# wait for the disks to settle
sleep 5

mkdir -p /tmp/boot /tmp/root /tmp/root/home /tmp/root/var/log/audit /tmp/root/var/tmp
#boot###
vgcreate root_vg ${disk_name}p3
lvcreate -l 20%VG -n root_lv root_vg
lvcreate -l 20%VG -n home_lv root_vg
lvcreate -l 20%VG -n var_lv root_vg
lvcreate -l 15%VG -n vlog_lv root_vg
lvcreate -l 15%VG -n audit_lv root_vg
lvcreate -l 10%VG -n vtmp_lv root_vg
mkfs -F -t ext4 ${disk_name}p2
mkfs -F -t ext4 /dev/root_vg/root_lv
mount -t ext4 /dev/root_vg/root_lv /tmp/root
mkdir -p /tmp/root/boot
mount ${disk_name}p2 /tmp/root/boot
rsync -av --exclude=home --exclude=var /mnt/tmp/ /tmp/root/
echo "/dev/root_vg/root_lv / ext4  defaults  0 1" > /tmp/root/etc/fstab
echo "UUID=$(blkid -s UUID -o value ${disk_name}p2) /boot ext4  defaults  0 1" >> /tmp/root/etc/fstab



migrate_and_mount_disk() {
lvname=$1
mountpoint=$2
mount_options=$3
mkfs -F -t ext4 /dev/root_vg/${lvname}
mkdir -p /tmp/root/${mountpoint}
mount /dev/root_vg/${lvname} /tmp/root${mountpoint}
    # check if the folder already exists
    if [ -d "/mnt/tmp/${mountpoint}" ]; then
        FILE=$(ls -A /mnt/tmp/${mountpoint})
        >&2 echo $FILE
        # Empty folder give error on /*
        if [ ! -z "$FILE" ]; then
             rsync -av /mnt/tmp${mountpoint}/ /tmp/root${mountpoint}/
        fi
    fi
#rsync -av /mnt/tmp${mountpoint} /tmp/root${mountpoint}
#echo "UUID=$(blkid -s UUID -o value ${disk_name}${partition}) ${mountpoint} ext4  ${mount_options}  0 1" >> /tmp/root/etc/fstab
echo "/dev/root_vg/${lvname} ${mountpoint} ext4  ${mount_options}  0 1" >> /tmp/root/etc/fstab
}
# migrate and mount the existing
#migrate_and_mount_disk root_lv  /            defaults
migrate_and_mount_disk var_lv /var            defaults,nofail,nodev
migrate_and_mount_disk vlog_lv /var/log        defaults,nofail,nodev,nosuid,noexec
migrate_and_mount_disk audit_lv /var/log/audit  defaults,nofail,nodev,nosuid,noexec
migrate_and_mount_disk home_lv /home           defaults,nofail,nodev,nosuid
migrate_and_mount_disk vtmp_lv /var/tmp        defaults,nofail,nodev,nosuid,noexec

#### disable grub config file ####
#sudo mv /etc/grub.d/10_linux /home/ubuntu
#sudo mv /etc/grub.d/20_linux_xen /home/ubuntu

rm /tmp/root/boot/grub/grub.cfg
grub-mkconfig -o /tmp/root/boot/grub/grub.cfg

### install bootloader
grub-install --target=i386-pc --directory=/tmp/root/usr/lib/grub/i386-pc --recheck --boot-directory=/tmp/root/boot ${disk_name}
NEW_ROOT_UUID=`blkid ${disk_name}p2 | awk '{print $5}' | awk -F '=' '{print $2}' | tr -d '"'`
sed -i -e "s/root=PARTUUID=.*$/root=PARTUUID=${NEW_ROOT_UUID}/g" /tmp/root/boot/grub/grub.cfg
sed -i -e "s/GRUB_FORCE_PARTUUID=.*$/GRUB_FORCE_PARTUUID=${NEW_ROOT_UUID}/g" /tmp/root/etc/default/grub.d/40-force-partuuid.cfg
# Create folder instead of starting/stopping docker daemon
#mkdir -p /var/lib/docker
#chown -R root:docker /var/lib/docker
#migrate_and_mount_disk "${disk_name}p5" /var/lib/docker defaults,nofail

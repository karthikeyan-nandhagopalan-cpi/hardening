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

disk_name='/dev/nvme1n1'

# partition the disk
parted -a optimal -s $disk_name \
    mklabel gpt \
    mkpart bbp 1MB 2MB \
    set 1 bios_grub on \
    mkpart root ext4 2MB 20% \
    mkpart var ext4 20% 40% \
    mkpart varlog ext4 40% 60% \
    mkpart varlogaudit ext4 60% 75% \
    mkpart home ext4 75% 90% \
    mkpart vartmp ext4 90% 100%

# wait for the disks to settle
sleep 5

mkdir -p /tmp/root /tmp/root/home /tmp/root/var/log/audit /tmp/root/var/tmp
#root###
mkfs -F -t ext4 ${disk_name}p2
mount ${disk_name}p2 /tmp/root/
rsync -av --exclude=home --exclude=var /mnt/tmp/ /tmp/root/
echo "UUID=$(blkid -s UUID -o value ${disk_name}p2) / ext4  defaults  0 1" > /tmp/root/etc/fstab

migrate_and_mount_disk() {
partition=$1
mountpoint=$2
mount_options=$3
mkfs -F -t ext4 ${disk_name}${partition}
mkdir -p /tmp/root/${mountpoint}
mount ${disk_name}${partition} /tmp/root${mountpoint}
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
echo "UUID=$(blkid -s UUID -o value ${disk_name}${partition}) ${mountpoint} ext4  ${mount_options}  0 1" >> /tmp/root/etc/fstab
}
# migrate and mount the existing
#migrate_and_mount_disk "${disk_name}p1" /tmp/root            defaults
migrate_and_mount_disk p3 /var            defaults,nofail,nodev
migrate_and_mount_disk p4 /var/log        defaults,nofail,nodev,nosuid
migrate_and_mount_disk p5 /var/log/audit  defaults,nofail,nodev,nosuid
migrate_and_mount_disk p6 /home           defaults,nofail,nodev,nosuid
migrate_and_mount_disk p7 /var/tmp        defaults,nofail,nodev,nosuid

#### disable grub config file ####
#sudo mv /etc/grub.d/10_linux /home/ubuntu
#sudo mv /etc/grub.d/20_linux_xen /home/ubuntu

rm /tmp/root/boot/grub/grub.cfg
grub-mkconfig -o /tmp/root/boot/grub/grub.cfg

### install bootloader
#grub-install --target=i386-pc --directory=/tmp/root/usr/lib/grub/i386-pc --recheck --boot-directory=/tmp/root/boot ${disk_name}
NEW_ROOT_UUID=`blkid ${disk_name}p2 | awk '{print $5}' | awk -F '=' '{print $2}' | tr -d '"'`
#sed -i -e "s/root=PARTUUID=.*$/root=PARTUUID=${NEW_ROOT_UUID}/g" /tmp/root/boot/grub/grub.cfg
sed -i -e "s/GRUB_FORCE_PARTUUID=.*$/GRUB_FORCE_PARTUUID=${NEW_ROOT_UUID}/g" /tmp/root/etc/default/grub.d/40-force-partuuid.cfg
grub-mkconfig -o /tmp/root/boot/grub/grub.cfg
sed -i -e "s/root=PARTUUID=.*$/root=PARTUUID=${NEW_ROOT_UUID}/g" /tmp/root/boot/grub/grub.cfg
grub-install --target=i386-pc --directory=/tmp/root/usr/lib/grub/i386-pc --recheck --boot-directory=/tmp/root/boot ${disk_name}
mount --bind /proc /tmp/root/proc
mount --bind /sys /tmp/root/sys
mount --bind /dev /tmp/root/dev
cat << EOF | chroot /tmp/root /bin/bash
grub-install ${disk_name}
grub-mkdevicemap
echo "GRUB_FORCE_PARTUUID=" > /etc/default/grub.d/40-force-partuuid.cfg
update-grub
EOF
# Create folder instead of starting/stopping docker daemon
#mkdir -p /var/lib/docker
#chown -R root:docker /var/lib/docker
#migrate_and_mount_disk "${disk_name}p5" /var/lib/docker defaults,nofail
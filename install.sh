#!/bin/bash

# Color preset variables
color_reset='\033[0m'
color_red='\033[1;31m'
color_green='\033[1;32m'
color_yellow='\033[1;33m'
color_blue='\033[1;34m'

# Variables
pschose=""
username=""
fullname=""
host=""
kb_layout=""
kernel=""
storage_device=""


# read -p "$(echo -e "${color_blue}Enter keyboard layout: ${color_reset}")" kb_layout
echo -e "${color_yellow}Loading keyboard layout...${color_reset}"
loadkeys br-abnt2
echo -e "${color_green}Done loading keyboard layout.${color_reset}"
read -p "$(echo -e "${color_blue}Enter 'server' for server settings and 'personal' for personal settings: ${color_reset}")" pschose
read -p "$(echo -e "${color_blue}Enter username: ${color_reset}")" username
read -p "$(echo -e "${color_blue}Enter user's full name: ${color_reset}")" fullname
read -p "$(echo -e "${color_blue}Enter host name: ${color_reset}")" host
read -p "$(echo -e "${color_blue}Enter kernel: ${color_reset}")" kernel
read -p "$(echo -e "${color_blue}Enter storage device: ${color_reset}")" storage_device

echo -e "${color_yellow}Creating partitions and formating them...${color_reset}"
vgremove -q -f -y $(vgdisplay | grep "VG Name" | awk '{print $3}')
pvremove -q -f -y $(pvdisplay | grep "PV Name" | awk '{print $3}')
wipefs --all --force "${storage_device}"
parted -s -a optimal --script "${storage_device}" \
    mklabel gpt \
    mkpart ESP fat32 2M 514M \
    set 1 esp on \
    name 1 efi \
    mkpart primary 514M 100% \
    quit
parted --script "${storage_device}" print
storage_device_partition_efi="$(ls ${storage_device}* | grep -E "^${storage_device}p?1$")"
storage_device_partition_root="$(ls ${storage_device}* | grep -E "^${storage_device}p?2$")"
yes | mkfs.fat -F32 "${storage_device_partition_efi}"
yes | mkfs.btrfs "${storage_device_partition_root}"
echo -e "${color_green}Done creating partitions and formating them.${color_reset}"

echo -e "${color_yellow}Creating mountpoints and mounting partitions...${color_reset}"
mount "${storage_device_partition_root}" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@snapshots
umount /mnt
mount -o noatime,compress=lzo,space_cache,subvol=@ "${storage_device_partition_root}" /mnt
mkdir -p /mnt/{boot/efi,home,var,.snapshots}
mount -o noatime,compress=lzo,space_cache,subvol=@home "${storage_device_partition_root}" $ /mnt/home
mount -o noatime,compress=lzo,space_cache,subvol=@var "${storage_device_partition_root}" /mnt/var
mount -o noatime,compress=lzo,space_cache,subvol=@snapshots "${storage_device_partition_root}" /mnt/.snapshots
mount "${storage_device_partition_efi}" /mnt/boot/efi
echo -e "${color_green}Done creating mountpoints and mounting partitions.${color_reset}"

echo -e "${color_yellow}Setting up mirrors...${color_reset}"
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bkp
reflector --country Brazil --age 24 --protocol https,http --sort rate --save /etc/pacman.d/mirrorlist
echo -e "${color_green}Done setting up mirrors.${color_reset}"

echo -e "${color_yellow}Installing core packages...${color_reset}"
core_packages=(
    "base
    base-devel
    ${kernel}
    ${kernel}-headers
    linux-firmware
    snapper
    util-linux
    intel-ucode
    btrfs-progs
    nano
    sudo
    man-db
    man-pages
    openssh
    reflector
    fuse
    networkmanager
    wireless_tools
    wpa_supplicant
    packagekit
    grub
    efibootmgr
    lvm2
    parted
    iptables
    ebtables
    bash-completion
    curl
    wget
    git
    podman
    rclone
    ffmpeg
    pacman-contrib"
)

server_packages=(
    "python3
    python-pip
    moreutils
    jq
    unrar
    unzip"
)

personal_packages=(
    "mesa
    vulkan-icd-loader
    vulkan-intel
    intel-media-driver
    alsa-{utils,plugins,firmware}
    pulseaudio pulseaudio-{equalizer,alsa}
    xorg
    dosfstools
    os-prober
    mtools
    system-config-printer
    cups
    cups-pdf
    qemu
    virt-manager
    virt-viewer
    bridge-utils
    gnome
    gnome-software-packagekit-plugin
    chromium
    gnome-tweak-tool
    gnome-usage"
)


if [[ "$pschose" == "server" ]];
then
    packages=("${core_packages} ${server_packages}")
    inner_packages=("wheel glances")
elif [[ "$pschose" == "personal" ]]
then
    packages=("${core_packages} ${personal_packages}")
    inner_packages=("gnome-weather epiphany totem")
fi

for package in ${packages}
do
    pacstrap /mnt ${package} --noconfirm
done

for package in ${inner_packages}
do
    if [[ "$pschose" == "server" ]]
    then
        arch-chroot /mnt ${package}
    elif [[ "$pschose" == "personal" ]]
    then
        arch-chroot /mnt pacman -Rs ${package} --noconfirm
    fi
done
echo -e "${color_green}Done installing core packages.${color_reset}"

echo -e "${color_yellow}Setting up swapfile...${color_reset}"
arch-chroot /mnt truncate -s 0 /.swapfile
arch-chroot /mnt chattr +C /.swapfile
arch-chroot /mnt btrfs property set /.swapfile compression none
arch-chroot /mnt dd if=/dev/zero of=/.swapfile bs=1M count=7629 status=progress
arch-chroot /mnt chmod 600 /.swapfile
arch-chroot /mnt mkswap /.swapfile
arch-chroot /mnt swapon /.swapfile
echo -e "${color_green}Done setting up swapfile.${color_reset}"

echo -e "${color_yellow}Generating fstab...${color_reset}"
genfstab -U -p /mnt >> /mnt/etc/fstab
cat /mnt/etc/fstab
echo -e "${color_green}Done generating fstab.${color_reset}"

echo -e "${color_yellow}Setting up region and language...${color_reset}"
arch-chroot /mnt ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
arch-chroot /mnt hwclock --systohc
sed -i 's/#pt_BR.UTF-8 UTF-8/pt_BR.UTF-8 UTF-8/g' /mnt/etc/locale.gen
echo "LANG=pt_BR.UTF-8" > /mnt/etc/locale.conf
echo "KEYMAP=br-abnt2" > /mnt/etc/vconsole.conf
arch-chroot /mnt locale-gen
arch-chroot /mnt timedatectl set-ntp true
echo -e "${color_green}Done setting up region and language.${color_reset}"

echo -e "${color_yellow}Setting up hosts...${color_reset}"
echo "$host" > /mnt/etc/hostname
echo "127.0.0.1 localhost" >> /mnt/etc/hosts
echo "::1 localhost" >> /mnt/etc/hosts
echo "127.0.1.1 $host.localdomain $host" >> /mnt/etc/hosts
echo -e "${color_green}Done setting up hosts.${color_reset}"

echo -e "${color_yellow}Setting up numlock on tty...${color_reset}"
touch /mnt/usr/local/bin/numlock \
      /mnt/etc/systemd/system/numlock.service
chmod +x /mnt/usr/local/bin/numlock
tee /mnt/usr/local/bin/numlock <<- 'EOF'
#!/bin/bash
for tty in /dev/tty{1..6}
do
  /usr/bin/setleds -D +num < "$tty";
done
EOF
tee /mnt/etc/systemd/system/numlock.service <<- 'EOF'
[Unit]
Description=numlock
[Service]
ExecStart=/usr/local/bin/numlock
StandardInput=tty
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
echo -e "${color_green}Done setting up numlock on tty...${color_reset}"

echo -e "${color_yellow}mkinitcpio set up...${color_reset}"
sed -i 's/block filesystems/block lvm2 filesystems/g' /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -p $kernel
echo -e "${color_green}Done mkinitcpio.${color_reset}"

echo -e "${color_yellow}Creating a new user...${color_reset}"
arch-chroot /mnt useradd -mG wheel "${username}" -c "${fullname}"
echo -e "${color_blue}Type in the password for the username...${color_reset}"
arch-chroot /mnt passwd "${username}"
echo -e "${color_blue}Type in the password for the root...${color_reset}"
arch-chroot /mnt passwd root
echo -e "${color_green}Done creating a new user.${color_reset}"
if [[ "$pschose" == "server" ]]
then
  echo -e "${color_yellow}Allowing wheel group to use sudo...${color_reset}"
  sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g' /mnt/etc/sudoers
  echo -e "${color_green}Done allowing wheel group to use sudo.${color_reset}"
  sed -i 's/#KillUserProcesses=no/KillUserProcesses=no/g' /mnt/etc/systemd/logind.conf
  arch-chroot /mnt loginctl enable-linger "${username}"
fi
echo -e "${color_yellow}Setting up services...${color_reset}"
touch /mnt/etc/{subgid,subuid,sysctl.conf}
echo "kernel.unprivileged_userns_clone=1" >> /mnt/etc/sysctl.conf
arch-chroot /mnt usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $username
sed -i 's/#user_allow_other/user_allow_other/g' /mnt/etc/fuse.conf
arch-chroot /mnt systemctl enable NetworkManager numlock podman sshd
if [[ "$pschose" == "personal" ]]
then
  arch-chroot /mnt set-default graphical.target
  arch-chroot /mnt systemctl enable cups gdm libvirtd fstrim.timer
  rm /mnt/usr/share/applications/system-config-printer.desktop \
        /mnt/usr/share/applications/bvnc.desktop \
        /mnt/usr/share/applications/cups.desktop \
        /mnt/usr/share/applications/bssh.desktop \
        /mnt/usr/share/applications/avahi-discover.desktop \
        /mnt/usr/share/applications/qv4l2.desktop \
        /mnt/usr/share/applications/qvidcap.desktop \
        /mnt/usr/share/applications/lstopo.desktop
fi
echo -e "${color_green}Done setting up services.${color_reset}"

echo -e "${color_yellow}Setting up GRUB...${color_reset}"
arch-chroot /mnt sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0/g' /etc/default/grub
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=$host --removable
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
echo -e "${color_green}Done setting up GRUB.${color_reset}"

echo -e "${color_yellow}Removing script file...${color_reset}"
rm $0
echo -e "${color_green}Done removing script file.${color_reset}"

#!/bin/bash
DISTRO_NAME="Arch Linux ARM"

echo -e 

if [ -z ${RFS_WIFI_SSID+x} ]; then
  echo "WIFI SSID not set! Using 'Pixel C'";
  WIFI_SSID="Pixel C"
fi

if [ -z ${RFS_WIFI_PASSWORD+x} ]; then
  echo "WIFI Password not set! Using 'connectme!'";
  WIFI_PASSWORD="connectme!"
fi

function e_status(){
  echo -e '\e[1;36m'${1}'\e[0;37m'
}

#if [ "$ARCH" -eq "arm64" ]; then
#  QEMU_ARCH="aarch64"
#fi

function run_in_qemu(){
  PROOT_NO_SECCOMP=1 proot -0 -r $rootfs_dir -q qemu-$ARCH-static -b /etc/resolv.conf -b /etc/mtab -b /proc -b /sys $*
}

if [ -f /tmp/rootfs_builder_${DISTRO}.tar.gz ]; then
  e_status "$DISTRO_NAME tarball is already available in /tmp/, we're going to use this file."
else
  e_status "Downloading..."
  wget -O /tmp/rootfs_builder_${DISTRO}.tar.gz -q 'http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz'
fi

e_status "Extracting..."
bsdtar -xpf /tmp/rootfs_builder_${DISTRO}.tar.gz -C $rootfs_dir

e_status "QEMU-chrooting"

packages="lightdm 
lightdm-gtk-greeter 
xf86-video-fbdev 
binutils 
make 
noto-fonts 
sudo 
git 
gcc 
xorg-xinit 
xorg-server 
onboard 
bluez 
bluez-tools 
bluez-utils
openbox 
sudo 
kitty
netctl
wpa_supplicant
dhcpcd
dialog 
mesa
networkmanager"

e_status "Adding Pubkeys..."
run_in_qemu pacman-key --init
# HACK: `pacman-key --init && pacman-key --populate archlinuxarm` hangs.
cp distros/${DISTRO}/pacman-gpg/* $rootfs_dir/etc/pacman.d/gnupg

e_status "Installing packages..."
run_in_qemu pacman -Syu --needed --noconfirm $packages

e_status "Setting hostname..."
echo "pixel-c" > $rootfs_dir/etc/hostname

run_in_qemu systemctl enable NetworkManager
run_in_qemu systemctl enable lightdm
run_in_qemu systemctl enable bluetooth
run_in_qemu systemctl enable dhcpcd

e_status "Adding Keyboard to LightDM"
sed -i 's/#keyboard=/keyboard=onboard/' $rootfs_dir/etc/lightdm/lightdm-gtk-greeter.conf

e_status "Adding Wi-Fi connection"
mkdir -p $rootfs_dir/etc/NetworkManager/system-connection/
cat > $rootfs_dir/etc/NetworkManager/system-connection/wifi-conn-1 <<EOF
[connection]
id=wifi-conn-1
uuid=4f1ca129-1d42-4b8b-903f-591640da4015
type=wifi
permissions=
[wifi]
mode=infrastructure
ssid=$WIFI_SSID

[wifi-security]
key-mgmt=wpa-psk
psk=$WIFI_PASSWORD

[ipv4]
dns-search=
method=auto

[ipv6]
addr-gen-mode=stable-privacy
dns-search=
method=auto
EOF

if [ -z "$KBD_BT_ADDR" ]; then
  e_status "Configuring BT Keyboard"
  
  cat > $rootfs_dir/etc/btkbd.conf <<EOF
BTKBDMAC = ''$KBD_BT_ADDR''
EOF
  e_status "=> Adding BT Keyboard service"

  cat > $rootfs_dir/etc/systemd/system/btkbd.service <<EOF
[Unit]
Description=systemd Unit to automatically start a Bluetooth keyboard
Documentation=https://wiki.archlinux.org/index.php/Bluetooth_Keyboard
ConditionPathExists=/etc/btkbd.conf
ConditionPathExists=/usr/bin/bluetoothctl

[Service]
Type=oneshot
EnvironmentFile=/etc/btkbd.conf
ExecStart=/usr/bin/bluetoothctl connect ${BTKBDMAC}

[Install]
WantedBy=bluetooth.target
EOF
  run_in_qemu systemctl enable btkbd
fi

if [ ! -z "$KB_LAYOUT" -o -! -z "$KB_MAP" ]; then
  KB_LAYOUT = "ch"
  KB_MAP = "de"
fi

cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "$KB_LAYOUT"
        Option "XkbModel" "$KB_MAP"
EndSection
EOF

mkdir -p $rootfs_dir/home/alarm/.config/openbox
cat > $rootfs_dir/home/alarm/.config/openbox/autostart <<EOF 
kitty &
onboard &
EOF

e_status "Adding BCM4354.hcd"
wget -O $rootfs_dir/lib/firmware/brcm/BCM4354.hcd 'https://github.com/denysvitali/linux-smaug/blob/v4.17-rc3/firmware/bcm4354.hcd?raw=true'

e_status "Removing /var/cache/ content"
rm -rf $rootfs_dir/var/cache
mkdir -p $rootfs_dir/var/cache

e_status "RootFS generation done."

unset RFS_WIFI_SSID
unset RFS_WIFI_PASSWORD

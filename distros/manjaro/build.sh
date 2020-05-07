#!/usr/bin/env bash

# shellcheck source=./lib/fast_apt/fast_apt.sh
source "$(cd "$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]+x}")")")" && pwd)/lib/fast_apt/fast_apt.sh"

# arch rootfs builder 
# mirror list x86 https://www.archlinux.org/mirrorlist/all/

readonly -a supported_archs=("aarch64")
readonly default_root="/tmp/rootfs-build/arch-${supported_archs[0]}"
readonly default_host_name="pixel-c"
readonly default_time_zone="America/Toronto"
readonly default_wifi_ssid="Pixel C"
readonly default_wifi_password="connectme!"
readonly default_user="pixel"
readonly default_user_id="1000"
# "minimal"   "Minimal Edition            (only CLI)"
# "kde-plasma" "Full KDE/Plasma Desktop    (full featured)" 
# "xfce"      "Full XFCE desktop and apps (full featured)" 
# "mate"      "Full MATE desktop and apps (lightweight)" 
# "lxqt"      "Full LXQT Desktop and apps (lightweight)" 
# "i3"        "Mininal i3 WM with apps    (very light)" 
# "cubocore"  "QT based Desktop           (lightweight)" 
# "gnome"     "Full Gnome desktop and apps (EXPERIMANTAL)"
readonly edition="kde-plasma"
export container="arch-builder"
export NSPAWN="systemd-nspawn --machine=$container -q --resolv-conf=copy-host --timezone=off -D"
function clean_up_container(){
    machinectl kill "$container" || true;
    sleep 1
    machinectl stop "$container" || true;
    sleep 1
    machinectl poweroff "$container" || true;
    sleep 1
    machinectl terminate "$container" || true;
    sleep 1
}
function prepare_rootfs(){
    log_info "preparing rootfs..."
    log_info "installing dependancies..."
    local -r root="$1"
    local -r arch="$2"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    assert_not_empty "arch" "${arch+x}" "architecture is needed"
    if  file_exists "$root.tar.gz"; then
        log_info "cleaning up legacy archive at $root.tar.gz"
        rm "$root.tar.gz"
    fi

    log_info "generating machine ID ..."
    rm -f /etc/machine-id /var/lib/dbus/machine-id
    dbus-uuidgen --ensure=/etc/machine-id
    dbus-uuidgen --ensure
    local -r packages=(
        "debootstrap"
        "binfmt-support"
        "qemu-user-static"
        "aria2"
        "bsdtar"
        "openssl"
        "systemd-container"
    )
    apt-get update
    apt-get install -y "${packages[@]}"
    if [[ ! -f "/lib/binfmt.d/qemu-${arch}-static.conf" ]]; then
        mkdir -p "/lib/binfmt.d/"
        pushd "/tmp/" >/dev/null 2>&1
            rm -rf qemu-static-conf
            git clone https://github.com/computermouth/qemu-static-conf.git
            cp /tmp/qemu-static-conf/*.conf /lib/binfmt.d/
            rm -rf qemu-static-conf
            systemctl restart systemd-binfmt.service
        [[ "$?" != 0 ]] && popd
        popd >/dev/null 2>&1
    fi
    update-binfmts --enable "qemu-${arch}"
    local -r payload='kernel.unprivileged_userns_clone=1'
    local -r dest="/etc/sysctl.d/nspawn.conf"
    if [[ -f "$dest" ]]; then
        if [[ -z $(grep "$payload" "$dest") ]]; then
            log_info "enabling unprivileged user namespaces "
            echo "$payload" >"$dest"
            systemctl restart systemd-sysctl.service
        fi
        else
        log_info "enabling unprivileged user namespaces "
        echo "$payload" >"$dest"
        systemctl restart systemd-sysctl.service
    fi
    rm -rf "$root"
    rm -rf "$root/../pkg-cache"
    mkdir -p "$root"
    pushd "/tmp/" >/dev/null 2>&1
        rm -f "ArchLinuxARM-${arch}-latest.tar.gz"
        if  ! file_exists "ArchLinuxARM-${arch}-latest.tar.gz"; then
            log_info "downloading latest arch rootfs for ${arch} architecture  '$root'..."
            local -r download_list="/tmp/arch-${arch}.list"
            # using manjaro rootfs 
            local -r link="https://osdn.net/projects/manjaro-arm/storage/.rootfs/Manjaro-ARM-$arch-latest.tar.gz"
            echo "$link" >"$download_list"
            echo " out=ArchLinuxARM-${arch}-latest.tar.gz" >>"$download_list"
            if  file_exists "$download_list"; then
                downloader "$download_list"
            fi
        fi
        if  file_exists "ArchLinuxARM-${arch}-latest.tar.gz"; then
            bsdtar -xpf "ArchLinuxARM-${arch}-latest.tar.gz" -C "$root/"
            # TODO delete after completion
            rm "ArchLinuxARM-${arch}-latest.tar.gz"
        fi
    [[ "$?" != 0 ]] && popd
    popd >/dev/null 2>&1
}
function install_packages(){
    local -r root="$1"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    local -r main_dependancies=(
        # "xf86-video-fbdev "
        "manjaro-system"
        "manjaro-release" 
        "base"
        "bootsplash-systemd"
        "systemd"
        "systemd-libs"
        "lightdm"
        "lightdm-gtk-greeter"
        "binutils"
        "make"
        "noto-fonts"
        "sudo"
        "git"
        "gcc"
        "xorg-xinit"
        "xorg-server"
        "onboard"
        "bluez"
        "bluez-tools"
        "bluez-utils"
        "openbox"
        "sudo"
        "kitty"
        "netctl"
        "wpa_supplicant"
        "dhcpcd"
        "dialog"
        "mesa"
        "networkmanager"
        "openssh"
        "rsync"
        "base-devel"
        "uboot-tools"
        "dropbear"
    )
    
    local -r pkg_edition=$(grep "^[^#;]" "$root/../../distros/manjaro/editions/$edition" | awk '{print $1}')
    log_info "Setting up keyrings..."
    $NSPAWN "$root" pacman-key --init 1> /dev/null 2>&1
    $NSPAWN "$root" pacman-key --populate archlinux archlinuxarm manjaro manjaro-arm 1> /dev/null 2>&1
    log_info "binding pkg-cache..."
    mkdir -p "$root/../pkg-cache"
    mount -o bind "$root/../pkg-cache" "$root/var/cache/pacman/pkg"
    log_info "Generating mirrorlist..."
    $NSPAWN "$root" pacman-mirrors -f5 1> /dev/null 2>&1
    log_info "updating package list ..."
    $NSPAWN "$root" pacman -Syy
    log_info "setting locals to en_US.UTF-8"
    $NSPAWN "$root" locale-gen en_US.UTF-8
    log_info "installing packages ..."
    $NSPAWN "$root" pacman -Syyu --needed --noconfirm "${main_dependancies[@]}" 
    $NSPAWN "$root" pacman -Syyu --needed --noconfirm $pkg_edition
    log_info "Setting up system settings..."
    # $NSPAWN "$root" chmod u+s /usr/bin/ping #1> /dev/null 2>&1
    # rm -f "$root/etc/ssl/certs/ca-certificates.crt"
    # rm -f "$root/etc/ca-certificates/extracted/tls-ca-bundle.pem"
    # cp -a "/etc/ssl/certs/ca-certificates.crt" "$root/etc/ssl/certs/"
    # cp -a "/etc/ca-certificates/extracted/tls-ca-bundle.pem" $root/etc/ca-certificates/extracted/

     sed -i "s/.*PasswordAuthentication.*/PasswordAuthentication yes/g" "$root/etc/ssh/sshd_config"
    sed -i "s/.*PermitRootLogin.*/PermitRootLogin yes/g" "$root/etc/ssh/sshd_config"

}
function setup_user(){
    local -r root="$1"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    local commands=()
    log_info "deleting user '$default_user' in case it exists.possibly rememnants of faulty partial chroot setup."
    commands+=("")
    $NSPAWN  "$root" deluser --remove-home "${default_user}" > /dev/null 2>&1 || true
    $NSPAWN  "$root" useradd -l -G wheel,sys,audio,input,video,storage,lp,network,users,power,sudo,adm -md "/home/$default_user" -s /bin/bash -p password "$default_user"
}
# TODO repeat
function hostname_setup(){
    local -r root="$1"
    local -r host="$2"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    assert_not_empty "host" "${host+x}" "host must be set"
    log_info "Setting hostname to $host"
    local -r target="$root/etc/hostname"
    local -r dir="$(dirname "$target")"
    log_info "creating parent directory $dir"
    mkdir -p "$dir"
cat > "$target" <<EOF
$host
EOF
}
# TODO repeat
function timezone_setup(){
    local -r root="$1"
    local -r zone="$2"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    assert_not_empty "zone" "${zone+x}" "time zone must be set"
    log_info "setting timezone to $zone"
    # $NSPAWN  "$root" timedatectl set-timezone $zone
    local -r target="$root/etc/timezone"
    local -r dir="$(dirname "$target")"
    log_info "creating parent directory $dir"
    mkdir -p "$dir"
    echo "$zone" > "$target"
    $NSPAWN "$root" ln -sf /usr/share/zoneinfo/"$zone" /etc/localtime #1> /dev/null 2>&1
}

function enable_systemd_services(){
    local -r root="$1"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    shift;
    $NSPAWN "$root" systemctl enable getty.target haveged.service 
    
    local -r service_edition=$(grep "^[^#;]" "$root/../../distros/manjaro/editions/$edition" | awk '{print $1}')
    $NSPAWN "$root" systemctl enable $service_edition || true
    if [ -f "$root/usr/bin/xdg-user-dirs-update" ]; then
        $NSPAWN "$root" systemctl --global enable xdg-user-dirs-update.service 1> /dev/null 2>&1
    fi
    local -r systemd_services=(
        "sshd"
        "NetworkManager"
        "lightdm"
        "bluetooth"
        "dhcpcd"
    )
    # for i in "${systemd_services[@]}"; do
        # log_info "enabling service $i"
    # done
    $NSPAWN "$root" systemctl enable "${systemd_services[@]}"  || true
    $NSPAWN "$root" --user "$default_user" systemctl --user enable pulseaudio.service || true #1> /dev/null 2>&1

}
function setup_overlays(){
    local -r root="$1"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    shift;
    log_info "setting up overlays for $edition"
    cp -ap "$root/../../distros/manjaro/overlays/$edition"/* "$root"

}
# TODO repeat
function keyboard_setup(){
    log_info "Adding Keyboard to LightDM"
    local -r root="$1" 
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    local target="$root/etc/lightdm/lightdm-gtk-greeter.conf"
    local dir="$(dirname "$target")"
    local -r KB_LAYOUT="us"
    local -r KB_MAP="pc104"
    log_info "creating parent directory $dir"
    mkdir -p "$dir"
    sed -i 's/#keyboard=/keyboard=onboard/' "$target"
    log_info "setting x11 Keyboard to conf"
    target="$root/etc/X11/xorg.conf.d/00-keyboard.conf"
    dir="$(dirname "$target")"
    log_info "creating parent directory $dir"
    mkdir -p "$dir"
cat > "$target" <<EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "$KB_LAYOUT"
        Option "XkbModel" "$KB_MAP"
EndSection
EOF
}
# TODO repeat
function wifi_setup(){
    log_info "setting up Wi-Fi connection"
    local -r root="$1"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    local wifi_ssid="$2"
    local wifi_password="$3"

    local -r target="$root/etc/NetworkManager/system-connection/wifi-conn-1"
    local -r dir="$(dirname "$target")"
    log_info "creating parent directory $dir"
    mkdir -p "$dir"
cat > "$target" <<EOF
[connection]
id=wifi-conn-1
uuid=4f1ca129-1d42-4b8b-903f-591640da4015
type=wifi
permissions=
[wifi]
mode=infrastructure
ssid=$wifi_ssid

[wifi-security]
key-mgmt=wpa-psk
psk=$wifi_password

[ipv4]
dns-search=
method=auto

[ipv6]
addr-gen-mode=stable-privacy
dns-search=
method=auto
EOF
}
# TODO repeat
function setup_alarm(){
    log_info "setting up alarm"
    local -r root="$1"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    local -r target="$root/home/alarm/.config/openbox/autostart"
    local -r dir="$(dirname "$target")"
    log_info "creating parent directory $dir"
    mkdir -p "$dir"
cat > "$target" <<EOF 
kitty &
onboard &
EOF
}
# TODO repeat
function setup_bcm4354(){
    log_info "Adding BCM4354.hcd"
    local -r root="$1"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    local -r target="$root/lib/firmware/brcm/BCM4354.hcd"
    local -r dir="$(dirname "$target")"
    log_info "creating parent directory $dir"
    mkdir -p "$dir"
    local -r url="https://github.com/denysvitali/linux-smaug/blob/v4.17-rc3/firmware/bcm4354.hcd?raw=true"
    log_info "downloading $url"
    wget -O "$target" "$url"
}
function cleanup(){
    local -r root="$1"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    log_info "Cleaning install for unwanted files..."
    # umount -l -v -f "$root/root/var/cache/pacman/pkg" || true
    find "$root" -type d -exec umount -lvf {} || true 
    $NSPAWN "$root" rm -f "/usr/bin/qemu-aarch64-static"
    $NSPAWN "$root" rm -f "/var/cache/pacman/pkg/"* || true
    $NSPAWN "$root" rm -f "/var/log/"*
    $NSPAWN "$root" rm -f "/etc/"*.pacnew
    $NSPAWN "$root" rm -f "/usr/lib/systemd/system/systemd-firstboot.service"
    $NSPAWN "$root" rm -f "/etc/machine-id"
}
function tar_archive(){
    local -r root="$1"
    log_info "archiving '$root' to '$root.tar.gz'"
    pushd "$root" >/dev/null 2>&1
        tar -zcvf "$root.tar.gz" .
    [[ "$?" != 0 ]] && popd
    popd >/dev/null 2>&1
    # TODO dails due to device being busy
    rm -rf "$root"
}
############################################# start ###############################################
function build_manjaro(){
    local arch="$1";
    if [[  $(string_is_empty_or_null "${arch+x}") ]]; then
        arch="${supported_archs[0]}"
        log_warn "Architecture was not given ! Using default";
    fi
    shift;
    local -r root="$1"
    shift;
    local  host_name="$1"
        if [[  $(string_is_empty_or_null "${host_name+x}") ]]; then
        host_name=default_host_name
        log_warn "hostname was not given! Using default";
    fi
    shift;
    local -r time_zone="$1"
        if [[  $(string_is_empty_or_null "${time_zone+x}") ]]; then
        time_zone=default_time_zone
        log_warn "timezone was not given! Using default";
    fi
    shift;
    local -r wifi_ssid="$1"
    if [[  $(string_is_empty_or_null "${wifi_ssid+x}") ]]; then
        wifi_ssid=default_wifi_ssid
        log_warn "wifi ssid was not given! Using default";
    
    fi
    shift;
    local -r wifi_password="$1"
    if [[  $(string_is_empty_or_null "${wifi_password+x}") ]]; then
        wifi_password=default_wifi_password
        log_warn "wifi password was not given! Using default";
    fi
    shift;
    # umount "$root/root/var/cache/pacman/pkg" || true

    echo "*******************************************************************************************"
    echo "*                                                                                         *"
    log_info "Building Manjaro Linux Root File System In with systemd-nspawn"
    log_info "Architecture: $arch"
    log_info "Host Name: $host_name"
    log_info "timezone: $time_zone"
    log_info "wifi ssid: $wifi_ssid"
    log_info "wifi password: $wifi_password"
    echo "*                                                                                         *"
    echo "*******************************************************************************************"

    
    if [[ ! -d "$root" ]]; then
        log_warn "root filesystem '$root' not found. creating ..."
        mkdir -p "$root"
    fi
    log_info "setting ownership of '$root' to '$UID'  "
    chown -R "$UID:$UID" "$root" || true >/dev/null 2>&1
    prepare_rootfs "$root" "$arch"
    hostname_setup "$root" "${host_name}"
    timezone_setup "$root" "${time_zone}"
    install_packages "$root"
    enable_systemd_services "$root" 
    setup_overlays "$root"
    # TODO fix
    # setup_user "$root"
    keyboard_setup "$root"
    wifi_setup "$root" "${wifi_ssid}" "${wifi_password}" 
    setup_alarm "$root"
    setup_bcm4354 "$root"
    cleanup "$root"
    chown -R 0:0 "$root/"
    # chown -R "$default_user_id":"$default_user_id" "$root/home/$default_user" || true
    # chown -R "$default_user_id":"$default_user_id" "$root/home/alarm" || true
    chmod +s "$root/usr/bin/chfn" || true
    chmod +s "$root/usr/bin/newgrp" || true
    chmod +s "$root/usr/bin/passwd" || true
    chmod +s "$root/usr/bin/chsh" || true
    chmod +s "$root/usr/bin/gpasswd" || true
    chmod +s "$root/bin/umount" || true
    chmod +s "$root/bin/mount" || true
    chmod +s "$root/bin/su" || true
    tar_archive "$root"
    log_info "RootFS generation completed and stored at '$root.tar.gz'"
}
function help() {
    echo
    echo "Usage: [$(basename "$0")] [OPTIONAL ARG] [COMMAND | COMMAND <FLAG> <ARG>]"
    echo
    echo
    echo -e "[Synopsis]:\tBuilds Arch Linux Root File System"
    echo
    echo "Optional Flags:"
    echo
    echo -e "  --arch\t\tTarget CPU Architecture."
    echo -e "  \t\t\t+[available options] : ${supported_archs[@]}"
    echo -e "  \t\t\t+[default] : '${supported_archs[0]}'"
    echo
    echo -e "  --root-dir\t\tfile system root directory."
    echo -e "  \t\t\t+[default] : '${default_root}'"
    echo
    echo -e "  --host-name\t\tdistro's host name."
    echo -e "  \t\t\t+[default] : '${default_host_name}'"
    echo
    echo -e "  --time-zone\t\tdistro's time zone."
    echo -e "  \t\t\t+[default] : '${default_time_zone}'"
    echo
    echo -e "  --wifi-ssid\t\tavailable wifi network's ssid."
    echo -e "  \t\t\t+[default] : '${default_wifi_ssid}'"
    echo
    echo -e "  --wifi-password\tavailable wifi network's password"
    echo -e "  \t\t\t+[default] : '${default_wifi_password}'"
    echo
    echo "Example:"
    echo
    echo "  sudo $(basename "$0") --arch ${supported_archs[0]} \ "
    echo "                        --build-dir \$(pwd)/build \ "
    echo "                        --wifi-ssid my-fast-wifi \ "
    echo "                        --wifi-password my-super-secret-password"
    echo
}

function main() {
    if ! is_root; then
        log_error " needs root permission to build debian root filesysytem.exiting..."
        exit 1
    fi
    local arch=""
    local root_dir=""
    local host_name=""
    local time_zone=""
    local wifi_ssid=""
    local wifi_password=""
    while [[ $# -gt 0 ]]; do
        local key="$1"
        case "$key" in
        --arch)
            shift
            arch="$1"
            ;;
        --root-dir)
            shift
            root_dir="$1"
            ;;
        --host-name)
            shift
            host_name="$1"
            ;;
        --time-zone)
            shift
            time_zone="$1"
            ;;
        --wifi-ssid)
            shift
            wifi_ssid="$1"
            ;;
        --wifi-password)
            shift
            wifi_password="$1"
            ;;
        --help)
            help
            exit
            ;;
        *)
            help
            exit
            ;;
        esac
        shift
    done 
    clean_up_container
    build_manjaro "$arch" "$root_dir" "$host_name" "$time_zone" "$wifi_ssid" "$wifi_password"
    exit
}

if [ -z "${BASH_SOURCE+x}" ]; then
    main "${@}"
    exit $?
else
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        main "${@}"
        exit $?
    fi
fi
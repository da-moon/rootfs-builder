#!/usr/bin/env bash

# shellcheck source=./lib/fast_apt/fast_apt.sh
source "$(cd "$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]+x}")")")" && pwd)/lib/fast_apt/fast_apt.sh"

readonly -a supported_archs=("aarch64")
readonly -a supported_codenames=("buster" "stretch" "jessie")
readonly default_root="/tmp/rootfs-buil/debian-${supported_codenames[0]}"
readonly default_host_name="pixel-c"
readonly default_time_zone="America/Toronto"
readonly default_wifi_ssid="Pixel C"
readonly default_wifi_password="connectme!"
readonly default_user="pixel"
readonly default_user_id="1000"


function timezone_setup(){
    local -r root="$1"
    local -r zone="$2"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    assert_not_empty "zone" "${zone+x}" "time zone must be set"
    log_info "setting timezone to $zone"
    local -r target="$root/etc/timezone"
    local -r dir="$(dirname "$target")"
    log_info "creating parent directory $dir"
    mkdir -p "$dir"
    echo "$zone" > "$target"
}
function prepare_rootfs(){
    log_info "preparing rootfs..."
    log_info "installing dependancies..."
    local -r root="$1"
    local -r arch="$2"
    local -r code_name="$3"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    assert_not_empty "arch" "${arch+x}" "architecture is needed"
    assert_not_empty "code_name" "${code_name+x}" "codename is needed"
    local -r packages=(
        "debootstrap"
        "binfmt-support"
        "qemu-user-static"
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
    log_info "crearting rootfs directory '$root'..."
    mkdir -p "$root"
    log_info "setting up keyring for debian "$code_name"..."
    qemu-debootstrap --include=debian-archive-keyring --arch arm64 "$code_name" "$root" || true

}
function setup_mounts(){
    log_info "setting up mounts..."
    local -r root="$1"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    mount -t sysfs "sys" "$root/sys/"  || true
    mount -t proc  "proc" "$root/proc/" || true
    mount -o bind "/dev" "$root/dev/" || true
    mount -o bind "/dev/pts" "$root/dev/pts" || true
}
function teardown_mounts(){
    log_info "tearing down mounts..."
    local root="$1"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    umount -lvf "$root/dev/ptr" > /dev/null 2>&1 || true
    umount -lvf "$root/"* > /dev/null 2>&1 || true
}

function enable_systemd_services(){
    local -r root="$1"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    shift;
    local -r services="$1"
    for i in "${services[@]}"; do
        log_info "enabling service $i"
        chroot "$root" \
        env -i HOME="/root" \
            PATH="/bin:/usr/bin:/sbin:/usr/sbin" \
            TERM="$TERM" \
            systemctl enable "$i"
    done

}
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
    127.0.0.1       localhost
    ::1             localhost ip6-localhost ip6-loopback
    ff02::1         ip6-allnodes
    ff02::2         ip6-allrouters
    127.0.1.1       $host_name
EOF
    chroot "$root" env -i /bin/hostname hostname

}
function install_packages(){
    log_info "installing base packages ..."
    local -r root="$1"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    local -r main_dependancies=(
        "bash"
        "bluez"
        "sudo"
        "binutils"
        "network-manager"
        "lightdm"
        "lightdm-gtk-greeter"
        "openbox"
        "onboard"
        "ssh" 
        "net-tools" 
        "ethtool" 
        "wireless-tools" 
        "init" 
        "iputils-ping" 
        "rsyslog" 
        "bash-completion" 
        "ifupdown" 
        "systemd"
        "time"
        "htop"
        "man-db" 
        "lsof"
        "aria2"
        "apt-utils" 
        "unzip" 
        "build-essential" 
        "software-properties-common"
        "make" 
        "vim" 
        "nano" 
        "ca-certificates"
        "wget" 
        "jq" 
        "apt-transport-https" 
        "parallel"
        "gcc"
        "g++"
        "ufw"
        "progress"
        "bzip2"
        "strace"
        "tmux"
        "zip"
    )
    chroot "$root" apt-get update
    log_info "updating apt sources"
    chroot "$root" apt-get update
    log_info "updating installing netselect-apt"
    chroot "$root" \
            env -i \
                HOME="/root" \
                PATH="/bin:/usr/bin:/sbin:/usr/sbin" \
                SHELL="/bin/bash" \
                TERM="$TERM" \
                DEBIAN_FRONTEND="noninteractive" \
            apt-get --yes \
                -o DPkg::Options::=--force-confdef \
                install netselect-apt 
    log_info "removing fast-sources if it exist"
    chroot "$root" rm -rf  /etc/apt/sources-fast* 
    log_info "using netselct apt to find fastest sources"
        chroot "$root" \
            env -i \
                HOME="/root" \
                PATH="/bin:/usr/bin:/sbin:/usr/sbin" \
                SHELL="/bin/bash" \
                TERM="$TERM" \
                DEBIAN_FRONTEND="noninteractive" \
            netselect-apt  --tests 15 \
                --sources \
                --outfile /etc/apt/sources-fast.list \
            stable
    log_info "updating apt sources to use fastest servers"
    chroot "$root" apt-get update
    log_info "installing whiptail locales wget curl"
    chroot "$root" \
        env -i \
                HOME="/root" \
                PATH="/bin:/usr/bin:/sbin:/usr/sbin" \
                TERM="$TERM" \
                SHELL="/bin/bash" \
                DEBIAN_FRONTEND="noninteractive" \
            apt-get --yes \
                -o DPkg::Options::=--force-confdef \
                install whiptail locales wget curl 
    log_info "setting locals to en_US.UTF-8"
    chroot "$root" \
        env -i \
                HOME="/root" \
                PATH="/bin:/usr/bin:/sbin:/usr/sbin" \
                TERM="$TERM" \
                SHELL="/bin/bash" \
                DEBIAN_FRONTEND="noninteractive" \
            locale-gen en_US.UTF-8
    log_info "installing packages"
    chroot "$root" \
        env -i \
                HOME="/root" \
                PATH="/bin:/usr/bin:/sbin:/usr/sbin" \
                SHELL="/bin/bash" \
                TERM="$TERM" \
                DEBIAN_FRONTEND="noninteractive" \
            apt-get --yes \
                -o DPkg::Options::=--force-confdef \
                install "${main_dependancies[@]}"
    log_info "upgrading software"
    chroot "$root" \
        env -i \
                HOME="/root" \
                PATH="/bin:/usr/bin:/sbin:/usr/sbin" \
                SHELL="/bin/bash" \
                TERM="$TERM" \
                DEBIAN_FRONTEND="noninteractive" \
            apt-get  --yes \
                -o DPkg::Options::=--force-confdef \
                upgrade
    log_info "clearning up after apt ..."
    chroot "$root" apt-get --yes clean
    chroot "$root" apt-get --yes autoclean
    chroot "$root" apt-get --yes autoremove
}
function setup_user(){
    local -r root="$1"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    local commands=()
    # chroot "$root" getent passwd "$default_user" > /dev/null 
    # if [ $? -eq 0 ]; then
    log_info "deleting user '$default_user' in case it exists.possibly rememnants of faulty partial chroot setup."
    commands+=("")
    chroot "$root" deluser --remove-home "${default_user}" > /dev/null 2>&1 || true
    chroot "$root" useradd -l -G sudo,adm -md "/home/$default_user" -s /bin/bash -p password "$default_user"

}
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
    log_info "Cleaning up ...."
    local -r root="$1"
    assert_not_empty "root" "${root+x}" "root filesystem directory is needed"
    local -r target="$root/var/cache"
    rm -rf "$target"
    mkdir -p "$target"
}
function tar_archive(){
    local -r root="$1"
    log_info "archiving '$root' to '$root.tar.gz'"
    tar -cpzf "$root.tar.gz" "$root"
}
############################################# start ###############################################
function build_debian(){
    export DEBIAN_FRONTEND=noninteractive
    export DEBCONF_NONINTERACTIVE_SEEN=true


    local arch="$1";
    if [[  $(string_is_empty_or_null "${code_name+x}") ]]; then
        arch="${supported_archs[0]}"
        log_warn "Architecture was not given ! Using default";
    fi
    shift;
    local  code_name="$1";
    if [[  $(string_is_empty_or_null "${code_name+x}") ]]; then
        code_name="${supported_codenames[0]}"
        log_warn "Code name was not given! Using '$code_name'";
    fi
    shift;
    local -r root="$1"
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
    echo "*******************************************************************************************"
    echo "*                                                                                         *"
    log_info "Building Debian Root File System"
    log_info "Codename: $code_name"
    log_info "Architecture: $arch"
    log_info "Host Name: $host_name"
    log_info "timezone: $time_zone"
    log_info "wifi ssid: $wifi_ssid"
    log_info "wifi password: $wifi_password"
    echo "*                                                                                         *"
    echo "*******************************************************************************************"

    local -r systemd_services=(
        "NetworkManager"
        "lightdm"
        "bluetooth"
        "dhcpcd"
    )
    if [[ ! -d "$root" ]]; then
        log_warn "root filesystem '$root' not found. creating ..."
        mkdir -p "$root"
    fi
    log_info "setting ownership of '$root' to '$UID'  "
    chown -R "$UID:$UID" "$root" || true >/dev/null 2>&1
        prepare_rootfs "$root" "$arch" "$code_name"
        setup_mounts "$root"
        timezone_setup "$root" "${time_zone}"
        hostname_setup "$root" "${host_name}"
        install_packages "$root"
        setup_user "$root"
        enable_systemd_services "$root" "${systemd_services[@]}"
        keyboard_setup "$root"
        wifi_setup "$root" "${wifi_ssid}" "${wifi_password}" 
        setup_alarm "$root"
        setup_bcm4354 "$root"
        cleanup "$root"
        log_info "leaving chroot"
        teardown_mounts "$root"  
        chown -R 0:0 "$root/"
        chown -R "$default_user_id":"$default_user_id" "$root/home/$default_user" || true
        chown -R "$default_user_id":"$default_user_id" "$root/home/alarm" || true
        chmod +s "$root/usr/bin/chfn" || true
        chmod +s "$root/usr/bin/newgrp" || true
        chmod +s "$root/usr/bin/passwd" || true
        chmod +s "$root/usr/bin/chsh" || true
        chmod +s "$root/usr/bin/gpasswd" || true
        chmod +s "$root/bin/umount" || true
        chmod +s "$root/bin/mount" || true
        chmod +s "$root/bin/su" || true
        tar_archive "$root"
        unset DEBIAN_FRONTEND
        unset DEBCONF_NONINTERACTIVE_SEEN
        # rm -rf "$root"
        log_info "RootFS generation completed and stored at '$root.tar.gz'"
}

function help() {
    echo
    echo "Usage: [$(basename "$0")] [OPTIONAL ARG] [COMMAND | COMMAND <FLAG> <ARG>]"
    echo
    echo
    echo -e "[Synopsis]:\tBuilds debian Root File System"
    echo
    echo "Optional Flags:"
    echo
    echo -e "  --arch\t\tTarget CPU Architecture."
    echo -e "  \t\t\t+[available options] : ${supported_archs[@]}"
    echo -e "  \t\t\t+[default] : '${supported_archs[0]}'"
    echo
    echo -e "  --codename\t\tdebian codename."
    echo -e "  \t\t\t+[available options] : ${supported_codenames[@]}"
    echo -e "  \t\t\t+[default] : '${supported_codenames[0]}'"
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
    echo "                        --codename ${supported_codenames[0]} \ "
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
    local code_name=""
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
        --codename)
            shift
            code_name="$1"
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
    build_debian "$arch" "$code_name" "$root_dir" "$host_name" "$time_zone" "$wifi_ssid" "$wifi_password"
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


# OLDPATH="$PATH"
# if [ -z "$KBD_BT_ADDR" ]; then
#   log_info "Configuring BT Keyboard"
#   cat > $rootfs_dir/etc/btkbd.conf <<EOF
# BTKBDMAC = ''$KBD_BT_ADDR''
# EOF
#   log_info "=> Adding BT Keyboard service"
#   cat > $rootfs_dir/etc/systemd/system/btkbd.service <<EOF
# [Unit]
# Description=systemd Unit to automatically start a Bluetooth keyboard
# Documentation=https://wiki.archlinux.org/index.php/Bluetooth_Keyboard
# ConditionPathExists=/etc/btkbd.conf
# ConditionPathExists=/usr/bin/bluetoothctl

# [Service]
# Type=oneshot
# EnvironmentFile=/etc/btkbd.conf
# ExecStart=/usr/bin/bluetoothctl connect ${BTKBDMAC}

# [Install]
# WantedBy=bluetooth.target
# EOF
#   run_in_qemu systemctl enable btkbd
# fi

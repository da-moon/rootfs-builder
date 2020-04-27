#!/usr/bin/env bash

# shellcheck source=./lib/os/os.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/os/os.sh"

export ARCH=aarch64
export RFS_WIFI_SSID="$WIFI_SSID"
export RFS_WIFI_PASSWORD="$WIFI_PASSWORD"
assert_not_empty "DISTRO" "$DISTRO" "distro name must be set"
assert_not_empty "TOP" "$TOP" "TOP must be set"
assert_not_empty "SYSROOT" "$SYSROOT" "SYSROOT must be set"
log_info "distro is set to $DISTRO"
log_info "top is set to $TOP"
log_info "SYSROOT is set to $SYSROOT"
if [[ ! -d "$(pwd)/$SYSROOT" ]]; then
  log_warn "SYSROOT directory  $(pwd)/$SYSROOT not found. creating ..."
  mkdir -p "$(pwd)/$SYSROOT"
fi
if [[ ! -d "$(pwd)/distros/$DISTRO" ]]; then
  log_error "directory $(pwd)/distros/$DISTRO not found!";
  distros=$(ls distros)
  log_info "Distros available: $distros";
  exit 1
fi
if [[ ! $(file_exists "$(pwd)/distros/$DISTRO/build.sh") ]]; then
  log_error "$(pwd)/distros/$DISTRO/build.sh not found!"
  exit 1;
fi

log_info "setting ownership of '$SYSROOT' to UID '$UID'"
sudo chown -R "$UID:$GID" "$SYSROOT"
source "$(pwd)/distros/$DISTRO/build.sh"
if [ "$?" -ne "0" ]; then
  exit 1;
fi 
# Chmod
sudo chown -R 0:0 "$SYSROOT/"
sudo chown -R 1000:1000 "$SYSROOT/home/pixelc" || true
sudo chown -R 1000:1000 "$SYSROOT/home/alarm" || true

sudo chmod +s "$SYSROOT/usr/bin/chfn"
sudo chmod +s "$SYSROOT/usr/bin/newgrp"
sudo chmod +s "$SYSROOT/usr/bin/passwd"
sudo chmod +s "$SYSROOT/usr/bin/chsh"
sudo chmod +s "$SYSROOT/usr/bin/gpasswd"
sudo chmod +s "$SYSROOT/bin/umount"
sudo chmod +s "$SYSROOT/bin/mount"
sudo chmod +s "$SYSROOT/bin/su"

pushd "$SYSROOT"
sudo tar -cpzf "$TOP/out/${DISTRO}_rootfs.tar.gz" .
popd
#!/bin/sh

set -e

mkdir -p ~/qemu/freebsd && cd ~/qemu/freebsd
curl -O https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/aarch64/Latest/FreeBSD-15.0-RELEASE-arm64-aarch64-zfs.raw.xz
xz -dk FreeBSD-15.0-RELEASE-arm64-aarch64-zfs.raw.xz
cp /opt/local/share/qemu/edk2-aarch64-code.fd .
qemu-img resize -f raw FreeBSD-15.0-RELEASE-arm64-aarch64-zfs.raw +15G
sudo qemu-system-aarch64 \
  -m 8192M -smp 4 -cpu host -M virt,accel=hvf \
  -bios edk2-aarch64-code.fd \
  -rtc base=localtime,clock=rt \
  -nographic -serial mon:stdio -device usb-kbd -device usb-tablet \
  -device qemu-xhci \
  -drive if=virtio,file=FreeBSD-15.0-RELEASE-arm64-aarch64-zfs.raw,format=raw,id=hd0 \
  -netdev vmnet-bridged,id=net0,ifname=en0 \
  -device virtio-net-pci,netdev=net0,mac=52:54:00:12:34:56

passwd root
sysrc sshd_enable="YES"
sysrc sshd_flags="-o PermitRootLogin=without-password -o KbdInteractiveAuthentication=no"
service sshd start
# ...
shutdown -p now

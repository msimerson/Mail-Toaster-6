#!/bin/sh

set -e

mkdir -p ~/qemu/freebsd && cd ~/qemu/freebsd
cp /opt/local/share/qemu/edk2-aarch64-code.fd .

install_from_image()
{
	curl -O https://download.freebsd.org/releases/VM-IMAGES/15.0-RELEASE/aarch64/Latest/FreeBSD-15.0-RELEASE-arm64-aarch64-zfs.raw.xz
	xz -dk FreeBSD-15.0-RELEASE-arm64-aarch64-zfs.raw.xz
	qemu-img resize -f raw FreeBSD-15.0-RELEASE-arm64-aarch64-zfs.raw +15G
}

install_from_iso()
{
	curl -O https://download.freebsd.org/releases/ISO-IMAGES/15.0-RELEASE/FreeBSD-15.0-RELEASE-arm64-aarch64-disc1.iso
	qemu-img create -f qcow2 freebsd-15.qcow2 20G
	sudo qemu-system-aarch64 \
		-m 8192M -smp 4 -M virt,accel=hvf -cpu host \
		-bios edk2-aarch64-code.fd \
		-nographic \
		-device virtio-blk-pci,drive=hd0,id=blk0 \
		-drive if=none,file=freebsd-15.qcow2,format=qcow2,id=hd0 \
		-device virtio-blk-pci,drive=cd0,id=blk1 \
		-drive if=none,file=/Users/matt/Downloads/FreeBSD-15.0-RELEASE-arm64-aarch64-disc1.iso,format=raw,id=cd0,readonly=on \
		-netdev vmnet-bridged,id=net0,ifname=en0 \
		-device virtio-net-pci,netdev=net0
}

start_from_image()
{
	qemu-system-aarch64 \
	  -m 8192M -smp 4 -cpu host -M virt,accel=hvf \
	  -bios edk2-aarch64-code.fd \
	  -rtc base=localtime,clock=rt \
	  -nographic -serial mon:stdio \
	  -device qemu-xhci \
	  -device usb-kbd -device usb-tablet \
	  -drive if=virtio,file=FreeBSD-15.0-RELEASE-arm64-aarch64-zfs.raw,format=raw,id=hd0 \
	  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
	  -device virtio-net-pci,netdev=net0

	passwd root
}

start_from_iso()
{
	sudo qemu-system-aarch64 \
	  -m 8192M -smp 4 -cpu host -M virt,accel=hvf \
	  -bios edk2-aarch64-code.fd \
	  -rtc base=localtime,clock=rt \
	  -nographic -serial mon:stdio \
	  -device qemu-xhci \
	  -device virtio-blk-pci,drive=hd0,id=blk0 \
	  -drive if=none,file=freebsd-15.qcow2,format=qcow2,id=hd0 \
	  -netdev vmnet-bridged,id=net0,ifname=en0 \
	  -device virtio-net-pci,netdev=net0,mac=52:54:00:12:34:56
}

setup_iso()
{
	zfs destroy zroot/usr/src
	zfs destroy zroot/var/audit
	zfs destroy zroot/var/mail

	service motd onestart
	pkg install FreeBSD-ssh FreeBSD-bsdconfig FreeBSD-pf FreeBSD-jail
	sysrc sshd_enable="YES"
	sysrc sshd_flags="-o PermitRootLogin=without-password -o KbdInteractiveAuthentication=no"
	service sshd start
	mkdir -m 700 ~/.ssh
	cat <<EOF >> ~/.ssh/authorized_keys
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKworNI/GGwoLV6vvgoI2yd1cp5UObK6aPZkthkCnyjP matt@imac27.simerson.net
EOF

	pkg install -y sudo
	echo 'matt ALL = (ALL) NOPASSWD: ALL' > /usr/local/etc/sudoers.d/matt

	pkg install -y gitup && gitup ports
	pkg install -y vim-tiny git-tiny
	git clone git@github.com:msimerson/Mail-Toaster-6.git mt6
	ln -s ~root/mt6 ~matt/mt6


}


poweroff
qemu-img snapshot -c 15.0 freebsd-15.qcow2
qemu-img snapshot -l freebsd-15.qcow2

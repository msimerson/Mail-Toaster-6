#!/bin/sh

. mail-toaster.sh || exit

export BHYVE_VM_NAME=ubuntu-guest

create_bridge()
{
	if ! grep -q "tap.up_on_open" /etc/sysctl.conf; then
		tell_status "setting tap.up_on_open"
		sysctl net.link.tap.up_on_open=1
		echo "net.link.tap.up_on_open=1" >> /etc/sysctl.conf
	fi

	# create a named bridge for bhyve VMs
	ifconfig bridge bridge-public 2>/dev/null || {
		tell_status "creating bridge-public"
		ifconfig bridge create name bridge-public up
		get_public_facing_nic
		ifconfig bridge-public addm "$PUBLIC_NIC"
	}

	# create tap interface for VM
	ifconfig tap-ubuntu 2>/dev/null || {
		tell_status "creating VM tap interface"
		ifconfig tap create name tap-ubuntu up
		ifconfig bridge-public addm tap-ubuntu
	}

	if ! grep -q if_bridge_load /boot/loader.conf; then
		tell_status "enabling bridge & tap load at boot time"
		sysrc -f /boot/loader.conf if_bridge_load=YES
		sysrc -f /boot/loader.conf if_tap_load=YES
	fi
}

configure_grub()
{
	tee -a device.map <<EO_DMAP
(hd0) /dev/zvol/$ZFS_BHYVE_VOL/bhyve/ubuntu-guest
(cd0) /$ZFS_BHYVE_VOL/ISO/ubuntu-22.04.2-live-server-amd64.iso
EO_DMAP

	tell_status "loading the Linux kernel"
	grub-bhyve -m device.map -r cd0 -M 1024M ubuntu-guest

	tee -a <<EO_GRUB
	grub> ls
(hd0) (cd0) (cd0,msdos1) (host)
grub> ls (cd0)/isolinux
boot.cat boot.msg grub.conf initrd.img isolinux.bin isolinux.cfg memtest
splash.jpg TRANS.TBL vesamenu.c32 vmlinuz
grub> linux (cd0)/isolinux/vmlinuz
grub> initrd (cd0)/isolinux/initrd.img
grub> boot
EO_GRUB

	# within Ubuntu VM
	tee -a /etc/default/grub <<EO_DEFAULT_GRUB
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_TERMINAL='serial console'
GRUB_CMDLINE_LINUX="console=hvc0 console=ttyS0,115200n8"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
EO_DEFAULT_GRUB

	sudo update-grub
}

install_ubuntu_bhyve_zfs()
{
	if ! zfs_filesystem_exists "$ZFS_BHYVE_VOL/bhyve"; then
		zfs create "$ZFS_BHYVE_VOL/bhyve"
		zfs set recordsize=64K "$ZFS_BHYVE_VOL/bhyve"
	fi

	if ! zfs_filesystem_exists "$ZFS_BHYVE_VOL/bhyve/$BHYVE_VM_NAME"; then
		zfs create -V20G -o volmode=dev "$ZFS_BHYVE_VOL/bhyve/$BHYVE_VM_NAME"
	fi
}

generate_config()
{
	tee "$ZFS_BHYVE_VOL/bhyve/$BHYVE_VM_NAME.conf <<EO_BHYVE_CONF
name=$BHYVE_VM_NAME

cpus=1
#cores=1
#threads=1
#sockets=1

memory.size=1G
memory.wired=false

acpi_tables=true
destroy_on_poweroff=true

#uuid=""

pci.0.0.0.device=hostbridge

#pci.0.2.0.device=e1000  (use for Windows)
pci.0.2.0.device=virtio-net
pci.0.2.0.type=tap
pci.0.2.0.backend=tap-ubuntu

pci.0.3.0.device=virtio-blk
pci.0.3.0.path=/dev/zvol/$ZFS_BHYVE_VOL/bhyve/$BHYVE_VM_NAME

pci.0.4.0.device=ahci
pci.0.4.0.path=/$ZFS_BHYVE_VOL/ISO/ubuntu-22.04.2-live-server-amd64.iso

pci.0.29.0.device=fbuf
pci.0.29.0.wait=false
pci.0.29.0.rfb=0.0.0.0:5900
pci.0.29.0.w=800
pci.0.29.0.h=600

pci.0.30.0.device=xhci
pci.0.30.0.slot.1.device=tablet

pci.0.31.0.device=lpc

lpc.com1.device=stdio
#lpc.com1.device=/dev/nmdm0A
#lpc.com2.device=/dev/nmdm1A
lpc.bootrom=/usr/local/share/uefi-firmware/BHYVE_UEFI.fd

EO_BHYVE_CONF
}

install_ubuntu_bhyve()
{
	if ! grep -q vmm_load /boot/loader.conf; then
		tell_status "loading kernel module: vmm"
		kldstat vmm || kldload vmm || exit 1
		sysrc -f /boot/loader.conf vmm_load=YES
	fi

	create_bridge
	install_ubuntu_bhyve_zfs

	tell_status "installing bhyve"
	stage_pkg_install bhyve-firmware grub2-bhyve || exit
	#configure_grub

	tell_status "launching bhyve VM with CD installer"
	bhyve \
		-H -P -w \
		-c 1 -m 1G \
		-s 0:0,hostbridge \
		-s 2:0,virtio-net,tap-ubuntu \
		-s 3:0,ahci-cd,/$ZFS_BHYVE_VOL/ISO/ubuntu-22.04.2-live-server-amd64.iso \
		-s 4:0,virtio-blk,/dev/zvol/$ZFS_BHYVE_VOL/bhyve/ubuntu-guest \
		-s 29:0,fbuf,tcp=0.0.0.0:5900,w=800,h=600,wait \
		-s 30:0,xhci,tablet \
		-s 31:0,lpc \
		-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \
		-l com1,stdio \
		ubuntu-guest

	# -s 29:0,fbuf,tcp=0.0.0.0:5900,w=800,h=600,wait \  (VNC)
	# -s 30:0,xhci,tablet \  (sync mouse with host)
	# -s <slot>,virtio-input,/dev/input/eventX   (keyboard/mouse events)
	# -l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI_CSM.fd \ (BIOS)
	# -l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \     (UEFI)

	bhyvectl --destroy --vm=ubuntu-guest
}

configure_ubuntu()
{
	local _pdir="$STAGE_MNT/usr/local/etc/periodic"
}

start_ubuntu()
{
	tell_status "starting up VM"
	bhyve -AHP \
		-c 4 -m 1G \
		-s 0:0,hostbridge \
		-s 2:0,virtio-net,tap-ubuntu \
		-s 4:0,virtio-blk,/dev/zvol/$ZFS_BHYVE_VOL/bhyve/ubuntu-guest \
		-s 29:0,fbuf,tcp=0.0.0.0:5900,w=800,h=600 \
		-s 30:0,xhci,tablet \
		-s 31:0,lpc \
		-l com1,stdio \
		-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \
		ubuntu-guest

	# Desktop versions of Windows require a CD/DVD device, can be an empty file created with touch(1).

	bhyvectl --destroy --vm=ubuntu-guest
}

test_ubuntu()
{
	echo "hrmm, how to test?"
}

install_ubuntu_bhyve
#start_ubuntu
#test_ubuntu

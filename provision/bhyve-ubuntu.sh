#!/bin/sh

. mail-toaster.sh || exit

create_bridge()
{
	if ! grep -q tap.up_on_open /etc/sysctl.conf; then
		tell_status "setting tap.up_on_open"
		sysctl net.link.tap.up_on_open=1
		sysrc -f /etc/sysctl.conf net.link.tap.up_on_open=1
	fi

	# create a named bridge for bhyve VMs
	ifconfig bridge bridge-public 2>/dev/null || {
		tell_status "creating bridge bridge-public"
		ifconfig bridge create name bridge-public
		get_public_facing_nic
		ifconfig bridge-public addm "$PUBLIC_NIC"
		ifconfig bridge-public up
	}

	# create tap interface for VM
	ifconfig tap-ubuntu 2>/dev/null || {
		tell_status "creating VM tap interface"
		ifconfig tap create name tap-ubuntu
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
(hd0) /dev/zvol/zsan/bhyve/ubuntu-guest
(cd0) /zsan/ISO/ubuntu-22.04.2-live-server-amd64.iso
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

	# within VM
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
	# if ...
	zfs create zsan/bhyve
	zfs set recordsize=64K zsan/bhyve
	zfs create -V20G -o volmode=dev zsan/bhyve/ubuntu-guest
	# fi
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

	bhyve \
		-H -P -w \
		-c 2 -m 1G \
		-s 0:0,hostbridge \
		-s 1:0,lpc \
		-s 2:0,virtio-net,tap-ubuntu \
		-s 3:0,ahci-cd,/zsan/ISO/ubuntu-22.04.2-live-server-amd64.iso \
		-s 4:0,virtio-blk,/dev/zvol/zsan/bhyve/ubuntu-guest \
		-s 29:0,fbuf,tcp=0.0.0.0:5900,w=800,h=600,wait \
		-s 30:0,xhci,tablet \
		-l com1,stdio \
		-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \
		ubuntu-guest
}

# install_ubuntu_vm()
# {
# 	sysrc vm_enable=YES
# 	sysrc vm_dir=zfs:zsan/bhyve
# }

install_ubuntu()
{
	# tell_status "installing ubuntu"
	install_ubuntu_bhyve

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
		-s 1:0,lpc \
		-s 2:0,virtio-net,tap-ubuntu \
		-s 3:0,virtio-blk,/dev/zvol/zsan/bhyve/ubuntu-guest \
		-s 4:0,ahci-cd,/zsan/ISO/ubuntu-22.04.2-live-server-amd64.iso \
		-l com1,stdio \
		-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \
		ubuntu-guest
}

test_ubuntu()
{
	echo "hrmm, how to test?"
}

base_snapshot_exists || exit
create_staged_fs ubuntu
start_staged_jail ubuntu
install_ubuntu
configure_ubuntu
start_ubuntu
test_ubuntu
promote_staged_jail ubuntu

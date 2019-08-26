#!/bin/bash

# Variables
rsync_ip="127.0.0.1"
port="1873"
android_path_rsync="/"

# Get android arch
arch=$(adb shell getprop ro.product.cpu.abi)
case $arch in
	arm64*|aarch64*)  arch="aarch64"  ;;
	arm*|aarch*)      arch="arm"      ;;
	x86*)             arch="x86"      ;;
esac

# Download pre-built rsync
! [ -f rsync.bin ] && curl --progress-bar -L -o rsync.bin "https://github.com/JBBgameich/rsync-static/releases/download/continuous/rsync-$arch"

# Kill running rsync instances
adb shell killall rsync

# Push rsync
adb push rsync.bin /data/rsync
adb shell chmod +x /data/rsync

# Create rsyncd.conf
echo -e "address = $rsync_ip\nport = $port\n[root]\npath = $android_path_rsync\nuse chroot = false\nread only = false\nuid = 0\ngid = 0" > rsyncd.conf
adb push rsyncd.conf /data/rsyncd.conf

# Start rsync daemon on the device
adb shell '/data/rsync --daemon --config=/data/rsyncd.conf &'
adb forward tcp:6010 tcp:1873

# Where there is SElinux enabled (enforcing), we need to allow those ports
if [ getenforce ]; then
	sudo semanage port -a -t rsync_port_t -p tcp 6010
	sudo semanage port -a -t rsync_port_t -p tcp 1873
fi

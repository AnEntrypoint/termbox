#!/bin/bash
# Build the termbox installer USB: Ubuntu 26.04.1 Server with unattended autoinstall.
# Usage: sudo usb/build-usb.sh /dev/sdX      (erases the device)
# Needs: xorriso gdisk dosfstools lsblk. The ISO is downloaded once into $WORK and checksum-verified.
set -euo pipefail

DEV="${1:?usage: sudo $0 /dev/sdX}"
WORK="${WORK:-/var/tmp/termbox-usb}"
TIMEZONE="${TIMEZONE:-Africa/Johannesburg}"
ISO_NAME=ubuntu-26.04.1-live-server-amd64.iso
ISO_URL="https://releases.ubuntu.com/26.04.1/$ISO_NAME"
ISO_SHA256=cc8a95cde20f6ced61a322420de00f10cc3c90ced545daa46cb9c1a117f1d927
OUT="$WORK/termbox-installer.iso"
HERE="$(cd "$(dirname "$0")" && pwd)"

die() { echo "error: $*" >&2; exit 1; }

for t in xorriso sgdisk mkfs.vfat lsblk; do command -v "$t" >/dev/null || die "install $t first"; done
[ -b "$DEV" ] || die "$DEV is not a block device"
[ "$(lsblk -dno TRAN "$DEV")" = usb ] || die "$DEV is not a USB device; refusing"
[ "$(lsblk -dno TYPE "$DEV")" = disk ] || die "$DEV is not a whole disk"

echo "This will ERASE $DEV:"
lsblk "$DEV"
read -r -p "Type ERASE to continue: " answer
[ "$answer" = ERASE ] || die "aborted"

# Unmount any partitions of the stick before writing to it
for part in $(lsblk -lnpo NAME "$DEV" | tail -n +2); do
  sudo umount "$part" 2>/dev/null || true
done

# Office user password: hashed here, never stored in the repo
read -r -s -p "Password for the office user: " pw; echo
read -r -s -p "Repeat it: " pw2; echo
[ -n "$pw" ] && [ "$pw" = "$pw2" ] || die "passwords empty or different"
HASH=$(printf '%s' "$pw" | openssl passwd -6 -stdin)
unset pw pw2

# Pin the install to the commit this USB was built from
TERMBOX_REF=$(git -C "$HERE/.." rev-parse HEAD 2>/dev/null) || die "run from a git checkout of termbox"

mkdir -p "$WORK"
if [ ! -f "$WORK/$ISO_NAME" ]; then
  curl -fL -o "$WORK/$ISO_NAME" "$ISO_URL"
fi
echo "$ISO_SHA256  $WORK/$ISO_NAME" | sha256sum -c -

# Add 'autoinstall' to the ISO's kernel line so the installer runs without questions
XDIR=$(mktemp -d)
trap 'rm -rf "$XDIR"' EXIT
xorriso -osirrox on -indev "$WORK/$ISO_NAME" -extract /boot/grub/grub.cfg "$XDIR/grub.cfg" 2>/dev/null
sed -i -E '/^[[:space:]]*linux/ s/ ---/ autoinstall ---/' "$XDIR/grub.cfg"
grep -q 'autoinstall ---' "$XDIR/grub.cfg" || die "could not patch the boot menu; ISO layout changed"
xorriso -indev "$WORK/$ISO_NAME" -outdev "$OUT" -boot_image any replay \
  -update "$XDIR/grub.cfg" /boot/grub/grub.cfg -commit >"$WORK/repack.log" 2>&1 \
  || die "repacking the ISO failed, see $WORK/repack.log"

echo "Writing installer image to $DEV"
sudo dd if="$OUT" of="$DEV" bs=4M conv=fsync status=progress
sudo sync
sudo partprobe "$DEV" || true
sleep 2

# Seed partition in the free space after the ISO: NoCloud reads the volume labelled CIDATA
sudo sgdisk -e "$DEV" >/dev/null
sudo sgdisk -n 0:0:0 -t 0:0700 -c 0:CIDATA "$DEV" >/dev/null
sudo partprobe "$DEV" || true
sleep 2
PART=$(lsblk -lnpo NAME,TYPE "$DEV" | awk '$2=="part"{p=$1} END{print p}')
sudo mkfs.vfat -n CIDATA "$PART" >/dev/null

SEED=$(mktemp -d)
sed -e "s|__PASSWORD_HASH__|$HASH|" -e "s|__TERMBOX_REF__|$TERMBOX_REF|g" \
    -e "s|__TIMEZONE__|$TIMEZONE|g" "$HERE/user-data.tmpl" > "$SEED/user-data"
cp "$HERE/meta-data" "$SEED/meta-data"
MNT=$(mktemp -d)
sudo mount "$PART" "$MNT"
sudo cp "$SEED/user-data" "$SEED/meta-data" "$MNT/"
sudo umount "$MNT"
rm -rf "$SEED" "$MNT"
sudo sync
echo "Done. $DEV is ready: boot the office box from it. Pinned to ${TERMBOX_REF}."

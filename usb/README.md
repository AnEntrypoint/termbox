# termbox office installer

Turns a USB stick into a self-installing Ubuntu 26.04.1 Server. Booting an office box from it installs Ubuntu, Docker and the termbox desktop with no questions except the office password.

## Build the stick (once, on a Linux machine)

```
sudo apt install xorriso gdisk dosfstools
sudo usb/build-usb.sh /dev/sdX
```

The script asks you to type `ERASE`, checks that the device is USB, verifies the Ubuntu ISO checksum, adds `autoinstall` to its boot menu and writes a `CIDATA` seed partition with the autoinstall config. The config is pinned to the commit the script runs from.

## Install an office box

1. Boot the box from the stick and wait. It partitions the SSD, installs, and reboots.
2. The first boot starts the `termbox` service, which pulls `ghcr.io/anentrypoint/termbox:latest`.
3. Open `http://<box-ip>:3000` and log in as `abc` with the password in `/srv/termbox/env` (`sudo cat /srv/termbox/env`).
4. Inside the desktop, run `claude` once and sign in. The login is saved to `/srv/termbox/claude` on the box and reused by every container.

## What each layer is

| Layer | Where | Updated by |
|---|---|---|
| Ubuntu 26.04.1 Server, Docker | the stick's ISO | rebuild the stick |
| Desktop image (Claude Code, freddie, gridcraft) | `ghcr.io/anentrypoint/termbox` | CI, daily at 02:00 UTC |
| Host units (`termbox`, `termbox-update`) | `host/` in this repo, fetched at install time | rebuild the stick |

Each box checks for a new image daily at 03:00 and restarts the desktop only when the image changed. Containers run with `--rm`, so the desktop is wiped on every exit. Only `/srv/termbox/claude` survives.

## Disk (256 GB SSD)

| Partition | Size | Holds |
|---|---|---|
| `/boot/efi` | 1 GB | bootloader |
| `/` | 80 GB | Ubuntu, host tools |
| `/srv` | rest (~155 GB) | Docker images and layers (`/srv/docker`), shared Claude login (`/srv/termbox/claude`) |

Old image layers are pruned after 7 days unused.

## Known gaps

- Not yet tested on a real box. The ISO boot-menu patch is verified, but autoinstall boot and the storage layout are not.
- The image needs to be public in GHCR (or boxes need `docker login ghcr.io`) to pull.
- Claude Desktop is not included. Anthropic has no Linux build; freddie is the agent harness used instead.
- The desktop is reachable by anyone on the office LAN at port 3000, protected only by the box password.

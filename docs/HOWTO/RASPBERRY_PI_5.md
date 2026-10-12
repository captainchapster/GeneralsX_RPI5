# Zero Hour on the Raspberry Pi 5

GeneralsX runs Command & Conquer Generals Zero Hour natively on a Raspberry Pi 5. The menu, skirmish, campaign, save/load, videos and LAN play all work, at around 70 FPS in a 1024x768 skirmish with three AI players.

## What you need

- A Raspberry Pi 5. It was tested on the 8 GB model; 4 GB is untested.
- A 64-bit OS: Raspberry Pi OS, Debian bookworm/trixie or Twister OS. It was tested on Twister OS (Xfce, X11). The Wayland desktop of Raspberry Pi OS is untested.
- Your own copy of **Generals** and **Zero Hour** (Steam, EA app or the original discs). The game files are not included.

Nothing replaces your system graphics driver. The package brings its own newer Mesa Vulkan driver for the Pi's GPU (Mesa 26), which only the game uses.

## Install

1. If your game files are on a USB stick (see below), plug it into the Pi.
2. Download `GeneralsXZH-pi5-aarch64.tar.gz` from the [releases page](https://github.com/captainchapster/GeneralsX_RPI5/releases/latest).
3. Open it and extract the `GeneralsXZH-pi5` folder, for example to your Downloads folder.
4. Open that folder and double-click **Setup**. If the file manager asks, choose **Run** (or **Execute**).

The Setup wizard finds your game files, installs a few system components (it asks for your password if it needs it), copies everything with a progress bar, and adds **C&C Generals Zero Hour** to the Games menu and, if you like, the desktop. When it's done you can delete the downloaded file and folder.

Prefer a terminal? This downloads the latest release and starts the same Setup:

```bash
curl -fsSL https://github.com/captainchapster/GeneralsX_RPI5/releases/latest/download/install-pi5-zh.sh | bash
```

Without a desktop (or with `--text`), Setup runs as a text installer in the terminal.

## Getting the game files onto the Pi

Zero Hour needs both games' folders. Copy them from a Windows PC with the game installed, for example on a USB stick:

| Store | Zero Hour folder | Generals folder |
|---|---|---|
| EA app | `C:\Program Files\EA Games\Command and Conquer Generals Zero Hour\Command and Conquer Generals Zero Hour` | `C:\Program Files\EA Games\Command and Conquer Generals Zero Hour\Command and Conquer Generals` |
| Steam and others | see [Getting the Game Files](https://github.com/fbraz3/GeneralsX/wiki/Getting-the-Game-Files) | |

Copy each whole folder. Setup looks for them on USB sticks and other drives and in your home folder, and lets you choose each folder if it can't find them. The text installer can also be given them:

```bash
~/GeneralsX/pi5/install-pi5-zh.sh --zh-data "/media/$USER/USB/Command and Conquer Generals Zero Hour" \
                                  --generals-data "/media/$USER/USB/Command and Conquer Generals"
```

They end up in `~/GeneralsX/GeneralsZH` and `~/GeneralsX/Generals`.

## Playing

- The game starts fullscreen. It switches the monitor to the game's resolution rather than scaling every frame, which is much faster on the Pi. Ultrawide monitors get black bars at the sides.
- Use the in-game Options to change the resolution. 1024x768 is a good balance on the Pi.
- To run it in a window, start it from a terminal with `~/GeneralsX/pi5/run-pi5-zh.sh -win`.

## LAN games with other computers

The Pi can play LAN games against GeneralsX on Linux, macOS and Windows, as long as everyone runs the **same GeneralsX version** with the same game data.

- If games don't show up in the Network lobby, open Options on each computer and pick that computer's real LAN address in the IP address list. Windows often defaults to a virtual adapter.
- On Windows, allow the game through the firewall. It uses UDP ports 8086 and 8088.

Online play (Generals Online) is not available in this build.

## Troubleshooting

- Every run writes `~/GeneralsX/logs/zh-last-run.log`. Include it when reporting a problem.
- Crackling or beeping Bluetooth audio affects the whole Pi, not just the game: the Pi 5's Wi-Fi and Bluetooth share one chip. If you're on a cable, turn Wi-Fi off with `sudo rfkill block wifi`, or permanently with `dtoverlay=disable-wifi` in `/boot/firmware/config.txt`.
- Setup saves what it did in `~/GeneralsX/logs/setup.log`.
- "no V3DV ICD JSON" means the bundled driver is missing; run Setup again.

## Updating and removing

To update, run Setup from a newer release; your game files, saved games and settings stay.

To remove the game, choose **Uninstall C&C Generals Zero Hour** in the Games menu. It removes the game program, shortcuts and graphics driver, and keeps your game files in `~/GeneralsX`. From a terminal: `~/GeneralsX/pi5/Setup --uninstall`.

## Building it yourself

On the Pi, from a checkout of the `rpi5/phase1-aarch64` branch:

```bash
./scripts/build/linux/build-pi5-mesa.sh     # Mesa V3DV driver into /opt/mesa-26.2.4
./scripts/build/linux/build-pi5-zh.sh       # the game (the first build takes a while)
./scripts/build/linux/bundle-pi5-zh.sh      # GeneralsXZH-pi5-aarch64.tar.gz
```

Then install the package as above. GitHub builds the same package with the **Build Pi 5** workflow.

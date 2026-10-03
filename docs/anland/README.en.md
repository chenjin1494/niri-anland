# Droidspaces + Arch Linux ARM64 + Anland legacy 5.x + niri

> **Current status:** This repository includes the Anland legacy 5.x producer backend behind the optional Cargo feature `anland`. The ARM64 Actions workflow builds against the pinned legacy producer bridge and creates a `.tar.xz` package. Real Droidspaces/Adreno device acceptance is pending; successful installation or GLES initialization alone does not verify hardware DMA-BUF, input, and frame synchronization.

This guide targets a rooted Android ARM64 device, an Arch Linux ARM64 Droidspaces container, and the Anland **legacy v5** Android app. It does not target Anland main / v6 and does not use X11.

## 1. Compatibility and prerequisites

- Android 11 or later, ARM64, root, and a Droidspaces build with the separate **Anland Display** container option.
- Adreno/KGSL is the recommended, tested path. The container must expose `/dev/dri/renderD128` and normally `/dev/kgsl-3d0`, with matching Android kernel/driver and userspace Mesa.
- The intended package target is Arch Linux ARM aarch64. Check on the device:

```sh
uname -m
getprop ro.build.version.release
ls -l /dev/dri/renderD128 /dev/kgsl-3d0
```

`uname -m` should report `aarch64`. If nodes are missing, fix Droidspaces/kernel device access; installing Mesa in the container cannot create kernel device nodes.

The Mesa for Android Container upstream guide requires Mesa 26.3.0 or newer for Anland support. GPUs tested there include Adreno 660, 710/720/722/730/732/735/740/750, and 810/829/830/840; 825 is experimental. Other GPUs may work, but support cannot be inferred from this list. See [upstream compatibility and installation notes](https://github.com/lfdevs/mesa-for-android-container/blob/adreno-main/.github/README.md).

## 2. Android and Droidspaces settings

1. Install the v5 APK from the [Anland legacy project](https://github.com/SuperTurtleDev/anland/tree/legacy). Verify that it is `anland-v5.apk`, not the main/v6 APK. Grant root-helper access when prompted.
2. Create/import an Arch Linux ARM64 container in Droidspaces. In its configuration set:

| Setting | Value | Notes |
|---|---|---|
| GPU Access | On | Exposes Adreno GPU devices |
| Anland Display | On | Creates a daemon and socket for this container |
| Configure Termux:X11 | Off | This setup is Wayland-only |
| Configure PulseAudio | Off | Do not mix in PulseAudio; remove stale `PULSE_SERVER` configuration |
| Hardware Access | Off by default | Enable only when this RootFS/device demonstrably needs additional hardware mapping |
| SELinux | enforcing | Keep enforcing; diagnose a specific AVC denial instead of disabling it globally |
| `nocaps`, `noseccomp` | Off by default | Enable individually only when required by the current Droidspaces version or RootFS |

3. In Anland app Settings, use these values as needed. Settings save immediately; connection, audio, and resolution changes usually apply on the next connection.

| Anland setting | Recommended value | When to change |
|---|---|---|
| Root helper / Connect with root | Enable and grant root | Required for Android app access to the restricted socket; Linux desktop still runs as normal user |
| Touchpad Mode (relative movement) | Off for touchscreen; test for a physical touchpad | Enable only when a physical touchpad needs relative motion |
| Capture external pointer | Enable if a USB/Bluetooth mouse is not captured automatically | External mouse input |
| Accessibility Key Interception | Off by default; enable and grant Android Accessibility permission if keys are missing | Fn, media, or other hardware keys not forwarded normally |
| Immersive Mode | Off by default | Hides Android system bars; bind a physical escape key first |
| Extra Keys Bar / Soft Keyboard Toggle Key | As needed | Touchscreen soft keyboard or no physical keyboard |
| Forward microphone / camera | Off; enable only if needed | The legacy producer bridge includes audio/camera channels; verify each service on the target device |
| Audio keep-alive | Off | Enable only after producer audio works, if silent sessions suspend audio |
| Foreground scheduling | Off by default | Optional; may increase battery use and does not enable GPU acceleration |
| Display resolution / Auto-stretch | Start at fixed 1280x720; Auto-stretch off | Try native resolution after stability; avoid non-uniform stretching |
| Screen orientation | Fix to the desired landscape orientation | Exit and reopen Anland after changing |
| Settings notification | Optional | Shortcut to settings only; does not keep daemon/desktop alive |

In a normal-user container shell, clear the current session variable and look for old startup-file settings:

```sh
unset PULSE_SERVER
grep -nH 'PULSE_SERVER' "$HOME/.bashrc" "$HOME/.profile" 2>/dev/null || true
```

If this finds an old `export PULSE_SERVER=...` line, remove it with an editor; `unset` alone does not change shell startup files.

4. Do not install a separate Anland daemon Magisk module and do not manually bind-mount `/data/local/tmp/display_daemon.sock`. Droidspaces integration creates a per-container dynamic socket and mounts it inside the container as `/run/display.sock`.
5. Start the container and check the infrastructure inside it as root:

```sh
test -S /run/display.sock && echo 'Anland socket ready'
test -e /dev/dri/renderD128 && echo 'DRM render node ready'
test -e /dev/kgsl-3d0 && echo 'KGSL node ready'
```

6. After installing in section 5, run `/opt/niri-anland/bin/start-anland` as the normal user in the container. Once niri has started, choose **Launch Anland** on the running-container card/details page. Do not open Anland from the Android app drawer: that entry uses the global default socket, not this container's dynamic socket.

For the meaning and timing of Android app settings, see the [Anland legacy Settings Guide](https://github.com/SuperTurtleDev/anland/blob/legacy/doc/UserManual/anland_settings_guide.md).

## 3. Prepare the Arch ARM64 container

Droidspaces RootFS import screens vary by version. Use its official Arch Linux ARM64 image flow; do not use an x86_64 Arch image on an ARM64 device. After first entry, run as root:

```sh
pacman-key --init
pacman-key --populate archlinuxarm
pacman -Syu --needed curl ca-certificates sudo unzip \
  libinput libdisplay-info libxkbcommon seatd systemd-libs libdrm \
  mesa libglvnd wayland pipewire pango libadwaita dbus
```

If keyring initialization/signature synchronization fails, follow Arch Linux ARM image instructions to correct system time, update `archlinuxarm-keyring`, and synchronize again. Do not permanently disable signature verification. Arch Linux ARM is rolling release; back up container data before upgrades.

Create a normal user and grant the wheel group sudo access:

```sh
useradd -m -G wheel -s /bin/bash desktop
passwd desktop
EDITOR=vi visudo
```

In `visudo`, uncomment only `%wheel ALL=(ALL:ALL) ALL`, then save and exit. Do not overwrite the sudoers file directly. Switch to the normal user:

```sh
su - desktop
```

Do not run the Wayland compositor or DMS as root. DMS refuses to run as root.

## 4. Install Adreno container Mesa

As the normal user, download this verified **Arch Linux ARM64** package. These commands use the 26.3.0-devel-20260824 release and verify its published SHA-256. For a later release, first confirm its notes and that the asset matches Arch ARM64:

```sh
mkdir -p "$HOME/downloads/mesa" "$HOME/tmp/mesa/extract"
cd "$HOME/downloads/mesa"
curl -fL 'https://github.com/lfdevs/mesa-for-android-container/releases/download/mesa-26.3.0-devel-20260824/mesa-for-android-container_26.3.0-devel-20260824_archlinux_arm64.tar' -o mesa-arch-arm64.tar
printf '%s  %s\n' '75b7638829b211c20c26b6110e525ca23ab28980ce58af824ab16c8e7afcfa26' mesa-arch-arm64.tar | sha256sum -c -
tar -tf mesa-arch-arm64.tar
tar -xf mesa-arch-arm64.tar -C "$HOME/tmp/mesa/extract"
mapfile -t mesa_pkgs < <(find "$HOME/tmp/mesa/extract" -type f -name '*.pkg.tar.xz' -print)
((${#mesa_pkgs[@]} > 0)) || { echo 'No Arch ARM package files found' >&2; exit 1; }
sudo pacman -U "${mesa_pkgs[@]}"
```

The outer asset is a `.tar` containing pacman `*.pkg.tar.xz` packages; it is not a tar.gz to extract over `/`. The commands verify the checksum, inspect the archive, extract into a staging directory, then install the matching package files with pacman. Never overlay a different distribution's driver files onto the root filesystem.

To diagnose the graphics driver without launching X11/GLX:

```sh
sudo pacman -S --needed vulkan-tools
MESA_LOADER_DRIVER_OVERRIDE=kgsl vulkaninfo --summary
```

Check that the reported device/driver is the actual Adreno/Turnip GPU, not a software device. niri needs GLES; verify the startup log selects the KGSL GLES renderer and connects the Anland DMA-BUF. Hardware acceptance still requires sustained composition, input, orientation/resolution changes, and DMS on the target device.

> **Note:** A distro upgrade can replace custom Mesa packages. Keep the original archive/version and recheck renderer selection and DMA-BUF import after upgrades.

## 5. Install niri and DMS

### niri archive

After the `.github/workflows/anland-arch-arm64.yml` run completes, download its `niri-anland-archlinux-aarch64` artifact ZIP. The workflow uploads a GitHub Actions artifact retained for 30 days; it does not create a GitHub Release. Transfer the ZIP into the container's `$HOME/downloads` (for example, with the Droidspaces file transfer UI), then extract and verify/install it inside the container:

```sh
cd "$HOME/downloads"
unzip niri-anland-archlinux-aarch64.zip -d niri-anland-actions
cd niri-anland-actions
sha256sum -c niri-anland-*-archlinux-aarch64.tar.xz.sha256
tar -tf niri-anland-*-archlinux-aarch64.tar.xz
mkdir -p "$HOME/niri-anland-install"
tar -xf niri-anland-*-archlinux-aarch64.tar.xz -C "$HOME/niri-anland-install"
cd "$HOME/niri-anland-install"
sudo ./install.sh
```

The installer places the compositor, launcher, and both shared bridge libraries under `/opt/niri-anland`; it does not replace the system `niri`. Start it as the normal user with `/opt/niri-anland/bin/start-anland`. To uninstall, run `sudo ./uninstall.sh` from the extracted directory.

### DMS package

Arch Linux ARM aarch64 publishes `dms-shell` and `quickshell` packages. Before installing, review whether pacman will replace or upgrade your custom Mesa packages:

```sh
sudo pacman -S --needed dms-shell
```

After installation, configure the DMS Wayland shell and disable Xwayland Satellite in `~/.config/niri/config.kdl`. Create/edit the file:

```sh
mkdir -p "$HOME/.config/niri"
"${EDITOR:-vi}" "$HOME/.config/niri/config.kdl"
```

Add these entries (keep only one `spawn-at-startup` if you already have one):

```kdl
xwayland-satellite {
    off
}
spawn-at-startup "dms" "run"
```

`start-anland` creates a session D-Bus when one is not already present, and niri then starts DMS. For manual debugging, run `dms run` as the normal user inside the running niri Wayland session. Do not also enable a systemd unit; two startup methods may create duplicate shell instances.

DMS is a Wayland shell, not an Anland producer. Without Android host network, power, Bluetooth, or brightness interfaces mapped into the container, the corresponding DMS controls cannot operate those host features automatically.

## 6. Wayland-only session and input

The Anland desktop must not start `Xorg`, Termux:X11, or `xinit`, and must not set `DISPLAY`. Disable Xwayland Satellite in `~/.config/niri/config.kdl`:

```kdl
xwayland-satellite {
    off
}
```

Create/edit it with `mkdir -p ~/.config/niri && "${EDITOR:-vi}" ~/.config/niri/config.kdl`. Do not set `DISPLAY` or start `Xorg`, Termux:X11, or `xinit`.

```sh
printf 'WAYLAND_DISPLAY=%s\n' "$WAYLAND_DISPLAY"
printf 'DISPLAY=%s\n' "${DISPLAY-}"
printf 'NIRI_SOCKET=%s\n' "$NIRI_SOCKET"
```

Physical keyboards/mice connected to Android are forwarded by the Anland consumer. Do not also pass the same raw input device through to the container, or events may be duplicated. Enable **Accessibility Key Interception** in Anland Settings only when needed for Fn/F1-F12/Esc (first grant Android Accessibility permission). Enable **Capture external pointer** as needed. Immersive mode requires root and a bound physical key with a detectable scan code for escape. Start troubleshooting at a fixed 1280x720 resolution; try automatic/native resolution after the session is stable. Resolution changes normally apply on the next connection.

## 7. Troubleshooting

- **No `/run/display.sock`:** verify Anland Display is enabled for the container and use Launch Anland from the running container card. Do not enter the global daemon path manually.
- **Missing GPU node:** check GPU Access, the host's Adreno/KGSL hardware support, and Droidspaces kernel permissions. Installing Mesa inside the container does not create kernel nodes.
- **Renderer is `llvmpipe`:** check Mesa >=26.3.0, the Arch ARM64 package, KGSL node, and `MESA_LOADER_DRIVER_OVERRIDE=kgsl`; retain `vulkaninfo --summary` and EGL/GLES logs.
- **Android window connects but is black:** launch with `/opt/niri-anland/bin/start-anland` (it sets `ANLAND=1`); inspect niri logs for renderer, Anland session generation, render-target, and frame-submit errors; verify the selected DMA-BUF format/size imports successfully.
- **Duplicate keyboard/mouse events:** use only Android/Anland forwarding; disable raw container device passthrough.
- **DMS fails to start:** confirm it is not root, Wayland and `NIRI_SOCKET` are set, user D-Bus exists, and Quickshell can create an EGL context.
- **Do not permanently disable SELinux or seccomp:** inspect Droidspaces AVC/container logs and make a targeted adjustment only for a confirmed policy issue.

## 8. Sources

- [Anland legacy niri producer adapter, pinned commit](https://github.com/SuperTurtleDev/anland/tree/96d8dc645aefdf80196331e1ce8b4379b61bfb8c/producers/niri/anland_backend)
- [Anland legacy user guide](https://github.com/SuperTurtleDev/anland/blob/legacy/doc/UserManual/anland_guide.md)
- [Anland legacy settings guide](https://github.com/SuperTurtleDev/anland/blob/legacy/doc/UserManual/anland_settings_guide.md)
- [Mesa for Android Container compatibility and installation](https://github.com/lfdevs/mesa-for-android-container/blob/adreno-main/.github/README.md)
- [DMS installation](https://danklinux.com/docs/dankmaterialshell/installation)
- [Arch Linux ARM dms-shell package](https://archlinuxarm.org/packages/aarch64/dms-shell)
- [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS)

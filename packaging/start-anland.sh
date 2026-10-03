#!/usr/bin/env bash
set -euo pipefail

PREFIX=/opt/niri-anland
NIRI="$PREFIX/bin/niri"
SOCKET=${ANLAND_SOCKET:-/run/display.sock}

if [[ ${EUID} -eq 0 ]]; then
    echo 'Do not run the Wayland compositor as root.' >&2
    exit 1
fi
if [[ ! -x "$NIRI" ]]; then
    echo "Missing Anland niri binary: $NIRI" >&2
    exit 1
fi
if [[ ! -S "$SOCKET" ]]; then
    echo "Missing Anland container socket: $SOCKET" >&2
    echo 'Enable Anland Display for this Droidspaces container and launch it from its card.' >&2
    exit 1
fi

export LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export ANLAND=1
export ANLAND_PRESENT_BACKEND=legacy
export ANLAND_SOCKET="$SOCKET"
export ANLAND_DRM_DEVICE=${ANLAND_DRM_DEVICE:-/dev/dri/renderD128}
export MESA_LOADER_DRIVER_OVERRIDE=${MESA_LOADER_DRIVER_OVERRIDE:-kgsl}
export GALLIUM_DRIVER=${GALLIUM_DRIVER:-kgsl}
export FD_FORCE_KGSL=${FD_FORCE_KGSL:-1}
export FD_DEV_FEATURES=${FD_DEV_FEATURES:-enable_tp_ubwc_flag_hint=1}
export MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE=${MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE:-1}
export QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-wayland}

# Never let a parent desktop socket select niri's nested Winit backend.
unset WAYLAND_DISPLAY WAYLAND_SOCKET DISPLAY

if [[ -z ${XDG_RUNTIME_DIR:-} ]]; then
    export XDG_RUNTIME_DIR="${TMPDIR:-/tmp}/niri-runtime-${UID}"
    install -d -m 700 "$XDG_RUNTIME_DIR"
fi
if [[ ! -d "$XDG_RUNTIME_DIR" || ! -O "$XDG_RUNTIME_DIR" ]]; then
    echo "XDG_RUNTIME_DIR must be an existing directory owned by uid $UID." >&2
    exit 1
fi
chmod 700 "$XDG_RUNTIME_DIR"

if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
    exec dbus-run-session -- "$NIRI" "$@"
fi
exec "$NIRI" "$@"

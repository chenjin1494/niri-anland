#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    echo "Run install.sh as root (sudo ./install.sh)." >&2
    exit 1
fi
if [[ ! -x opt/niri-anland/bin/niri ]]; then
    echo "Run this script from the extracted archive directory." >&2
    exit 1
fi

PREFIX=/opt/niri-anland
STATE_DIR=/var/lib/niri-anland
MANIFEST="$STATE_DIR/installed-files"
install -d "$PREFIX" "$STATE_DIR"
NEW_MANIFEST=$(mktemp "$STATE_DIR/installed-files.XXXXXX")
trap 'rm -f "$NEW_MANIFEST"' EXIT
find opt/niri-anland -type f -print | sed 's#^opt/niri-anland/#/opt/niri-anland/#' > "$NEW_MANIFEST"

if [[ -f "$MANIFEST" ]]; then
    while IFS= read -r path; do
        case "$path" in
            /opt/niri-anland/*)
                if [[ "$path" =~ (^|/)\.\.?(/|$) ]]; then
                    echo "Refusing traversal path in manifest: $path" >&2
                    exit 1
                fi
                ;;
            *) echo "Refusing unexpected manifest path: $path" >&2; exit 1 ;;
        esac
    done < "$MANIFEST"
    while IFS= read -r path; do
        if ! grep -Fxq -- "$path" "$NEW_MANIFEST"; then
            rm -f -- "$path"
        fi
    done < "$MANIFEST"
fi

cp -a opt/niri-anland/. "$PREFIX/"
mv -f "$NEW_MANIFEST" "$MANIFEST"
trap - EXIT
printf '%s\n' 'Installed the niri Anland legacy producer backend and documentation.'
printf 'Compositor: %s/bin/niri\n' "$PREFIX"
printf 'Shared producer libraries: %s/lib\n' "$PREFIX"
printf 'Files installed under %s\n' "$PREFIX"

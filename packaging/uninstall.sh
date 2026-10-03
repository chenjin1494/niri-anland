#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    echo "Run uninstall.sh as root (sudo ./uninstall.sh)." >&2
    exit 1
fi
MANIFEST=/var/lib/niri-anland/installed-files
if [[ ! -f "$MANIFEST" ]]; then
    echo "No niri-anland install manifest found at $MANIFEST." >&2
    exit 1
fi

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
    rm -f -- "$path"
done < "$MANIFEST"
rm -f "$MANIFEST"
rmdir /opt/niri-anland/bin /opt/niri-anland/lib \
    /opt/niri-anland/share/licenses/niri-anland /opt/niri-anland/share/licenses/anland \
    /opt/niri-anland/share/licenses /opt/niri-anland/share/doc/niri-anland \
    /opt/niri-anland/share/doc /opt/niri-anland/share/niri-anland \
    /opt/niri-anland/share /opt/niri-anland 2>/dev/null || true
rmdir /var/lib/niri-anland 2>/dev/null || true
printf '%s\n' 'Removed files recorded in the niri-anland install manifest.'

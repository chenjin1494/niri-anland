#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

if [[ "$(uname -m)" != "aarch64" ]]; then
    echo "This package must be built on native aarch64 Arch Linux." >&2
    exit 1
fi
for tool in pacman cargo cmake git readelf; do
    command -v "$tool" >/dev/null || { echo "Missing build tool: $tool" >&2; exit 1; }
done

VERSION=${VERSION:-$(sed -n 's/^version = "\([^"]*\)"/\1/p' Cargo.toml | head -n1)}
ANLAND_REV=96d8dc645aefdf80196331e1ce8b4379b61bfb8c
ARCHIVE="niri-anland-${VERSION}-archlinux-aarch64.tar.xz"
STAGE=$(mktemp -d)
ANLAND_SOURCE=$(mktemp -d)
trap 'rm -rf "$STAGE" "$ANLAND_SOURCE"' EXIT

# Pin the protocol and C producer implementation to the requested Anland v5 tree.
git clone --quiet --filter=blob:none --no-checkout https://github.com/SuperTurtleDev/anland.git "$ANLAND_SOURCE/repo"
git -C "$ANLAND_SOURCE/repo" fetch --quiet --depth=1 origin "$ANLAND_REV"
git -C "$ANLAND_SOURCE/repo" checkout --quiet --detach FETCH_HEAD
[[ "$(git -C "$ANLAND_SOURCE/repo" rev-parse HEAD)" == "$ANLAND_REV" ]] || {
    echo "Anland source did not resolve to the pinned v5 commit." >&2
    exit 1
}

BRIDGE_BUILD="$STAGE/bridge-build"
cmake -S packaging/anland-bridge -B "$BRIDGE_BUILD" \
    -DANLAND_ROOT="$ANLAND_SOURCE/repo" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BRIDGE_BUILD" --parallel "$(nproc)"
export ANLAND_NIRI_BRIDGE_BUILD="$BRIDGE_BUILD"
LD_LIBRARY_PATH="$BRIDGE_BUILD:$BRIDGE_BUILD/common/libdisplay_producer${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    cargo test --locked --features anland --lib anland
cargo build --locked --release --features anland

install -Dm755 target/release/niri "$STAGE/opt/niri-anland/bin/niri"
install -Dm755 "$BRIDGE_BUILD/libanland_niri_bridge.so" \
    "$STAGE/opt/niri-anland/lib/libanland_niri_bridge.so"
install -Dm755 "$BRIDGE_BUILD/common/libdisplay_producer/libdisplay_producer.so" \
    "$STAGE/opt/niri-anland/lib/libdisplay_producer.so"
install -Dm644 LICENSE "$STAGE/opt/niri-anland/share/licenses/niri-anland/LICENSE"
install -Dm644 "$ANLAND_SOURCE/repo/LICENSE" \
    "$STAGE/opt/niri-anland/share/licenses/anland/LICENSE"
install -Dm644 docs/anland/README.zh-CN.md "$STAGE/opt/niri-anland/share/doc/niri-anland/README.zh-CN.md"
install -Dm644 docs/anland/README.en.md "$STAGE/opt/niri-anland/share/doc/niri-anland/README.en.md"
install -Dm755 packaging/install.sh "$STAGE/install.sh"
install -Dm755 packaging/uninstall.sh "$STAGE/uninstall.sh"
install -Dm755 packaging/start-anland.sh "$STAGE/opt/niri-anland/bin/start-anland"

readelf -d "$STAGE/opt/niri-anland/bin/niri" | grep -Fq '$ORIGIN/../lib'
readelf -d "$STAGE/opt/niri-anland/lib/libanland_niri_bridge.so" | grep -Fq '$ORIGIN'
"$STAGE/opt/niri-anland/bin/niri" --version

mkdir -p dist
tar -C "$STAGE" --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner -cJf "dist/$ARCHIVE" .
(cd dist && sha256sum "$ARCHIVE" > "$ARCHIVE.sha256" && sha256sum -c "$ARCHIVE.sha256")
tar -tJf "dist/$ARCHIVE" >/dev/null
readelf -h "$STAGE/opt/niri-anland/bin/niri" | grep -q 'AArch64'
readelf -h "$STAGE/opt/niri-anland/lib/libanland_niri_bridge.so" | grep -q 'AArch64'
readelf -h "$STAGE/opt/niri-anland/lib/libdisplay_producer.so" | grep -q 'AArch64'
printf 'Created %s\n' "dist/$ARCHIVE"

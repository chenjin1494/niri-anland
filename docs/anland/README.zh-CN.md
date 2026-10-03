# Droidspaces + Arch Linux ARM64 + Anland legacy 5.x + niri

> **当前状态 / Status:** 本仓库已集成 Anland legacy 5.x producer 后端，位于可选 Cargo feature `anland` 下。ARM64 Actions 工作流会固定构建对应 legacy producer bridge 并生成 `.tar.xz` 安装包。尚未在真实 Droidspaces/Adreno 设备完成验收；成功安装或 GLES 初始化不等于 DMA-BUF、输入和帧同步已在硬件上验证。
>
> This repository includes the Anland legacy 5.x producer backend behind the optional Cargo feature `anland`. The ARM64 Actions workflow builds against the pinned legacy producer bridge and creates a `.tar.xz` package. Real Droidspaces/Adreno device acceptance is pending; a successful installation or GLES initialization does not verify hardware DMA-BUF, input, and frame synchronization.

本指南面向已 root 的 Android ARM64 设备、Droidspaces Arch Linux ARM64 容器、Anland **legacy v5** Android App。它不适用于 Anland main / v6，也不使用 X11。

This guide targets a rooted Android ARM64 device, an Arch Linux ARM64 Droidspaces container, and the Anland **legacy v5** Android app. It does not target Anland main / v6 and does not use X11.

## 1. 兼容性和前提 / Compatibility and prerequisites

- Android 11+、ARM64、root；Droidspaces 版本必须包含独立的 **Anland Display** 容器选项。
- Adreno GPU 是已验证的推荐路径。容器须暴露 `/dev/dri/renderD128` 和通常所需的 `/dev/kgsl-3d0`，且 Android 内核/驱动与用户态 Mesa 匹配。
- 计划构建目标为 Arch Linux ARM aarch64；先在设备上确认：

```sh
uname -m
getprop ro.build.version.release
ls -l /dev/dri/renderD128 /dev/kgsl-3d0
```

`uname -m` 应为 `aarch64`。节点缺失时先解决 Droidspaces/内核设备映射，不能靠容器内安装 Mesa 创建 GPU 设备节点。

Mesa for Android Container 的上游说明要求 Anland 使用 Mesa 26.3.0 或更新版本。已实测 GPU 包括 Adreno 660、710/720/722/730/732/735/740/750、810/829/830/840；825 标为实验性。其他型号并非必定不支持，但不能按此列表外推保证。来源：[项目兼容性和安装说明](https://github.com/lfdevs/mesa-for-android-container/blob/adreno-main/.github/README.md)。

## 2. Android 与 Droidspaces 设置 / Android and Droidspaces settings

1. 从 [Anland legacy 发布页](https://github.com/SuperTurtleDev/anland/tree/legacy)取得 v5 APK，确认是 `anland-v5.apk`，不要安装 v6/main APK。授予应用 root helper 所需的 root 权限。
2. 在 Droidspaces 为新容器选择 Arch Linux ARM64 RootFS。编辑容器配置：

| 设置 / Setting | 值 / Value | 说明 / Notes |
|---|---|---|
| GPU Access | 开 / On | Adreno GPU 设备访问 |
| Anland Display | 开 / On | 创建此容器专属 daemon 与 socket |
| Configure Termux:X11 | 关 / Off | 本方案完全不走 X11 |
| Configure PulseAudio | 关 / Off | 不要混用 PulseAudio；卸载/清除旧设置中的 `PULSE_SERVER` |
| Hardware Access | 默认关 / Off by default | 仅当此 RootFS/设备确实需要额外硬件映射时开启 |
| SELinux | enforcing | 保持强制模式；仅依据对应 AVC 日志排障 |
| `nocaps`, `noseccomp` | 默认关 / Off by default | 仅在当前 Droidspaces 版本或 RootFS 明确要求时分别开启 |

3. 在 Anland App 设置中按用途设置以下选项（设置自动保存；连接、音频、分辨率通常在下次连接生效）：

| Anland 设置 | 建议值 | 何时更改 |
|---|---|---|
| Root helper / Connect with root | 开启并授予 root | 必须；只让 Android App 连接受限 socket，不代表 Linux 桌面以 root 运行 |
| Touchpad Mode (relative movement) | 触控屏关闭；物理触控板按设备行为试用 | Android 触控屏应提供绝对坐标；触控板需要相对位移时再开启 |
| Capture external pointer | 有 USB/蓝牙鼠标且未自动捕获时开启 | 外接鼠标输入 |
| Accessibility Key Interception | 默认关闭，特殊按键缺失时开启并授予 Android 无障碍权限 | Fn、媒体键或未转发的硬件键 |
| Immersive Mode | 默认关闭 | 全屏隐藏 Android 系统栏；先绑定可用的物理退出键 |
| Extra Keys Bar / Soft Keyboard Toggle Key | 按需要开启 | 触屏软键盘或无实体键盘时 |
| Forward microphone / camera | 关闭；有需要时再开启 | legacy producer bridge 已含音频/摄像头通道，但需按设备和具体 service 逐项验收 |
| Audio keep-alive | 关闭 | 仅在 producer 音频实现后，为避免静音时设备休眠再开启 |
| Foreground scheduling | 默认关闭 | 可选；前台调度可能增加耗电，不是 GPU 加速开关 |
| Display resolution / Auto-stretch | 首次固定 1280×720；Auto-stretch 关闭 | 稳定后试原生分辨率；避免非等比拉伸 |
| Screen orientation | 按设备横屏方向固定 | 修改后退出并重开 Anland App |
| Settings notification | 可选 | 仅设置快捷通知，与 daemon/桌面存活无关 |

在容器普通用户 shell 中清理当前会话变量，并检查启动文件中是否有旧设置：

```sh
unset PULSE_SERVER
grep -nH 'PULSE_SERVER' "$HOME/.bashrc" "$HOME/.profile" 2>/dev/null || true
```

若输出旧的 `export PULSE_SERVER=...`，用编辑器移除该行；只执行 `unset` 不会自动改写 shell 启动文件。

4. 不要安装单独的 Anland daemon Magisk 模块，不要手动 bind-mount `/data/local/tmp/display_daemon.sock`。Droidspaces 集成会为每个容器创建动态 socket，并在容器中挂载为 `/run/display.sock`。
5. 启动容器，在容器内作为 root 检查基础设施：

```sh
test -S /run/display.sock && echo 'Anland socket ready'
test -e /dev/dri/renderD128 && echo 'DRM render node ready'
test -e /dev/kgsl-3d0 && echo 'KGSL node ready'
```

6. 完成第 5 节安装后，在容器普通用户 shell 运行 `/opt/niri-anland/bin/start-anland`；待 niri 后端启动，再从 Droidspaces 运行容器卡片/详情页按 **Launch Anland** 打开显示窗口。不要点击 Android 应用抽屉中的 Anland 图标；那个入口使用全局默认 socket，无法选择此容器的动态 socket。

完整 Android 设置含义请参考 [Anland legacy Settings Guide](https://github.com/SuperTurtleDev/anland/blob/legacy/doc/UserManual/anland_settings_guide.md)。

## 3. 首次准备 Arch ARM64 容器 / Prepare the Arch ARM64 container

Droidspaces 的 RootFS 导入/创建界面名称会随版本变化。使用其官方 Arch Linux ARM64 rootfs 导入流程，不要把 x86_64 Arch 镜像用于 ARM64。首次进入容器后以 root 执行：

```sh
pacman-key --init
pacman-key --populate archlinuxarm
pacman -Syu --needed curl ca-certificates sudo unzip \
  libinput libdisplay-info libxkbcommon seatd systemd-libs libdrm \
  mesa libglvnd wayland pipewire pango libadwaita dbus
```

若 Arch Linux ARM 镜像的 keyring 初始化/签名同步失败，先按 Arch Linux ARM 官方镜像说明校准系统时间、更新 `archlinuxarm-keyring` 并重新同步；不要用关闭签名验证作为永久修复。发行版为滚动更新，更新前备份容器数据。

创建普通用户并授予管理员组：

```sh
useradd -m -G wheel -s /bin/bash desktop
passwd desktop
EDITOR=vi visudo
```

在 `visudo` 中仅取消 `%wheel ALL=(ALL:ALL) ALL` 前面的注释符号，保存退出。不要直接覆盖 sudoers 文件。切换普通用户：

```sh
su - desktop
```

Wayland 合成器和 DMS 不应以 root 运行。DMS 拒绝 root 启动。

## 4. 安装 Adreno 容器 Mesa / Install Mesa for Adreno

在普通用户 shell 中下载项目提供的 **Arch Linux ARM64** 包。以下使用已核验的 26.3.0-devel-20260824 release，并校验上游 SHA-256。后续版本请先确认 release notes 与资产仍匹配 Arch ARM64：

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

外层资产是 `.tar`，内部包含 pacman 的 `*.pkg.tar.xz` 包；它不是可直接解压到 `/` 的 tar.gz。上面的命令先校验校验和、检查归档清单并解到临时目录，再由 pacman 安装匹配架构的包。不要把其他发行版的驱动覆盖到根目录。

使用 EGL/Vulkan 工具检查驱动而非 X11/GLX：

```sh
sudo pacman -S --needed mesa-utils vulkan-tools
MESA_LOADER_DRIVER_OVERRIDE=kgsl vulkaninfo --summary
```

检查输出中 Vulkan device/driver 为实际 Adreno/Turnip，而非软件设备。niri 需要 GLES；检查启动日志选择 KGSL GLES renderer 并成功连接 Anland DMA-BUF。硬件验收还需在目标设备上持续合成，并验证键鼠、旋转/分辨率变化和 DMS。

> **注意：** distro package 更新可能替换自定义 Mesa。升级前保存外层归档及其版本；升级后重做 renderer 和 DMA-BUF 导入检查。

## 5. 安装 niri 与 DMS / Install niri and DMS

### niri 包 / niri package

运行 `.github/workflows/anland-arch-arm64.yml` 工作流后，从对应 GitHub Actions 运行记录下载 `niri-anland-archlinux-aarch64` artifact ZIP。该 workflow 上传 Actions artifact（保留 30 天），不会自动创建 GitHub Release。通过 Droidspaces 文件传输将 ZIP 放入容器 `$HOME/downloads`，在容器中解压 artifact 并校验安装：

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

安装程序将 compositor、启动器和两个共享 bridge library 安装到 `/opt/niri-anland`，不覆盖系统自带的 `niri`。启动时用普通用户运行 `/opt/niri-anland/bin/start-anland`；卸载时从解压目录运行 `sudo ./uninstall.sh`。

### DMS 包 / DMS package

Arch Linux ARM aarch64 提供 `dms-shell` 与 `quickshell` 包。安装时先检查 pacman 是否将同时升级/替换你安装的 Mesa：

```sh
sudo pacman -S --needed dms-shell
```

安装成功后，在 `~/.config/niri/config.kdl` 使用 DMS Wayland shell，并禁用 Xwayland Satellite。创建或编辑配置：

```sh
mkdir -p "$HOME/.config/niri"
"${EDITOR:-vi}" "$HOME/.config/niri/config.kdl"
```

加入以下内容（若该项已配置，只保留一个 `spawn-at-startup`）：

```kdl
xwayland-satellite {
    off
}
spawn-at-startup "dms" "run"
```

`start-anland` 会在没有现存用户 D-Bus 时建立 session bus，之后由 niri 启动 DMS。若要手动调试，确认 UID 非 0 且 niri Wayland 会话已运行后，在同一会话环境运行 `dms run`。不要同时配置 systemd unit 和 `spawn-at-startup`，避免启动两个 shell 实例。

DMS 是 Wayland shell，不是 Anland producer。容器未映射 Android 宿主的网络、电源、蓝牙、亮度设备时，对应 DMS 控件不会因此自动获得宿主控制能力。

## 6. Wayland-only 会话与输入 / Wayland-only session and input

Anland desktop 不启动 `Xorg`、Termux:X11、`xinit`，也不设置 `DISPLAY`。关闭 niri 配置中的 Xwayland Satellite，文件为 `~/.config/niri/config.kdl`：

```kdl
xwayland-satellite {
    off
}
```

用 `mkdir -p ~/.config/niri && "${EDITOR:-vi}" ~/.config/niri/config.kdl` 创建/编辑配置；不要写入 `DISPLAY`，不要启动 `Xorg`、Termux:X11 或 `xinit`。

```sh
printf 'WAYLAND_DISPLAY=%s\n' "$WAYLAND_DISPLAY"
printf 'DISPLAY=%s\n' "${DISPLAY-}"
printf 'NIRI_SOCKET=%s\n' "$NIRI_SOCKET"
```

硬件键盘/鼠标接入 Android 后由 Anland consumer 转发，不要在 Droidspaces 中再把同一物理输入设备直通容器，否则会重复输入。Anland Settings 按需求启用 **Accessibility Key Interception**（首次还需在 Android 无障碍设置授权），用于 Fn/F1-F12/Esc 等 Android 未转发的键；**Capture external pointer** 按需开启。沉浸模式要求 root 且应预先绑定可检测 scan code 的退出键。显示分辨率先用固定 1280×720 排障，稳定后再尝试自动分辨率；分辨率修改通常在下一次连接生效。

## 7. 故障排查 / Troubleshooting

- **没有 `/run/display.sock`：**确认容器配置启用了 Anland Display，并从运行容器卡片使用 Launch Anland；不要手动填写全局 daemon 路径。
- **GPU 节点不存在：**确认 GPU Access，检查宿主是否为受支持的 Adreno/KGSL 设备及 Droidspaces 内核权限；容器内安装 Mesa 不会创建内核节点。
- **renderer 是 `llvmpipe`：**确认 Mesa >=26.3.0、Arch ARM64 对应包、KGSL 节点和 `MESA_LOADER_DRIVER_OVERRIDE=kgsl`；收集 `vulkaninfo --summary` 与 EGL/GLES 日志。
- **Android 窗口已连接但黑屏：**确认使用 `/opt/niri-anland/bin/start-anland`（会设置 `ANLAND=1`），查看 niri 日志中的 renderer、Anland session generation、render-target 和 frame-submit 错误；确认当前选中 DMA-BUF 格式/尺寸可导入。
- **重复键鼠事件：**只保留 Android/Anland 转发路径，关闭容器原始设备直通。
- **DMS 启动失败：**确认不是 root、Wayland socket 和 `NIRI_SOCKET` 已设置、D-Bus session 可用、Quickshell 能创建 EGL context。
- **不要永久关闭 SELinux 或 seccomp：**先检查 Droidspaces AVC/容器日志，只对已确认的策略问题做针对性调整。

## 8. 来源 / Sources

- [Anland legacy niri producer 适配层（固定 commit）](https://github.com/SuperTurtleDev/anland/tree/96d8dc645aefdf80196331e1ce8b4379b61bfb8c/producers/niri/anland_backend)
- [Anland legacy user guide](https://github.com/SuperTurtleDev/anland/blob/legacy/doc/UserManual/anland_guide.md)
- [Anland legacy settings guide](https://github.com/SuperTurtleDev/anland/blob/legacy/doc/UserManual/anland_settings_guide.md)
- [Mesa for Android Container compatibility and installation](https://github.com/lfdevs/mesa-for-android-container/blob/adreno-main/.github/README.md)
- [DMS installation](https://danklinux.com/docs/dankmaterialshell/installation)
- [Arch Linux ARM dms-shell package](https://archlinuxarm.org/packages/aarch64/dms-shell)
- [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS)

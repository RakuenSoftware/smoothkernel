# SmoothDesktop

Desktop flavor. A Windows-replacement desktop built on KDE Plasma 6 with a config-only theme package, gaming-ready out of the box, Flatpak-preconfigured for app availability.

## What it is

For users who want to leave Windows and land on a Linux desktop that *works on first boot* — drivers current, codecs present, Steam and Proton ready, printing configured, Bluetooth paired by clicking, screen sharing via the normal portal, a taskbar/start-menu paradigm that doesn't require UX retraining.

Not trying to be a general-purpose Linux distro. Opinionated about the DE (Plasma), the app set, the update model. Power users can customize anything; defaults are chosen for the "switching from Windows" user.

## Why Plasma, not GNOME

Plasma's layout matches Windows/macOS metaphors almost 1:1:

- Bottom taskbar with pinned apps + running apps + system tray + clock
- Application launcher ("start menu") bottom-left
- Desktop icons (GNOME removed these)
- Dolphin file manager with a conventional two-pane / breadcrumb interface
- Right-click context menus everywhere
- Per-window controls (min/max/close) on every window

GNOME's workflow (activities overview, no desktop icons, no taskbar, window buttons on the left, app-based model rather than window-based) is a harder migration for Windows users. Plasma is the right choice for the positioning.

## The custom-shell temptation — explicitly rejected

Building a custom Rakuen desktop shell would cost as much as `smoothtv` (weeks-to-months) for incremental differentiation over a well-themed Plasma. Plasma's layout engine is flexible enough that config + theming gets 90% of a custom shell's perceived polish for 2% of the effort.

The budget for a custom shell goes to SmoothHTPC, where no good OSS alternative exists. On desktop, Plasma is the right build-vs-buy answer.

## Suite composition (`smoothdesktop` suite)

| Package | Purpose |
|---|---|
| `smoothdesktop` | Meta — pulls workstation base + Plasma + theme + apps + gaming |
| `smoothdesktop-tuning` | sysctl + udev + tuned |
| `smoothdesktop-theme` | Plasma layout + KWin theme + icons + cursors + wallpapers + defaults |

From `common`: `smooth-workstation`, `linux-smoothkernel`, `smooth-base`, etc.

## Meta-package dependencies

```
Depends:
 smooth-workstation,
 smoothdesktop-tuning,
 smoothdesktop-theme,
 kde-standard,                 # Plasma + common KDE apps, without PIM/edu bloat
 sddm,
 plasma-workspace,
 plasma-nm,
 plasma-pa,
 powerdevil,
 bluedevil,
 dolphin,
 konsole,
 kate,
 okular,
 gwenview,
 ark,
 firefox-esr | firefox,
 thunderbird,
 libreoffice,
 vlc,
 gimp,
 xdg-desktop-portal-kde,
 flatpak,
 gnome-software-plugin-flatpak,
 cups,
 system-config-printer-kde,
 printer-driver-all,
 steam-installer | steam-launcher,
 gamescope,
 gamemode,
 mangohud,
 lutris,
 winehq-stable,
 winetricks,
 winbind
Recommends:
 discover,
 spectacle,
 kdeconnect,
 obs-studio,
 playonlinux,
 q4wine
```

Because `apt` resolves dependencies before any package `postinst` runs, the desktop bootstrap path does the source setup first. The SmoothDesktop ISO profile, or an equivalent `smoothdesktop-bootstrap` helper on an existing Debian install, enables Debian `contrib non-free non-free-firmware`, enables `i386`, and adds the WineHQ source/key before `apt install smoothdesktop`. Without that ordering, `steam-installer` and `winehq-stable` are not resolvable during the initial install.

Everything desktop-relevant on first boot. Users can uninstall what they don't want; the point is a complete-feeling system without a first-week hunt for basics.

## `smoothdesktop-theme`

Pure config, no code. Ships:

```
/usr/share/plasma/look-and-feel/com.rakuen.smoothdesktop/
    metadata.desktop
    contents/defaults
    contents/layouts/org.kde.plasma.desktop-layout.js
    contents/colors/
    contents/icons/

/usr/share/aurorae/themes/Smooth/
    (KWin window decoration)

/usr/share/icons/Smooth/
    (icon theme, potentially inheriting from Breeze or Papirus)

/usr/share/wallpapers/Smooth/
    (curated wallpapers)

/etc/xdg/kdeglobals                 (default color scheme, font, icon theme)
/etc/xdg/kwinrc                     (default window rules, effects)
/etc/xdg/plasmarc                   (default panel layout fallback)
/etc/xdg/kwinoutputconfig.xml       (scaling defaults for common HiDPI configs)
```

Plus mime associations (`/etc/xdg/mimeapps.list`):

- `text/html` → Firefox
- `application/pdf` → Okular
- `video/*` → VLC
- `image/*` → Gwenview
- File-protocol defaults to Dolphin

And a default Flathub preconfig (`/etc/flatpak/remotes.d/flathub.flatpakrepo`) so `flatpak install flathub <app>` works on first boot without user setup.

## Gaming stack

Out of the box, the user gets:

- **Steam** — Flathub preferred (Valve's maintained flatpak is better than apt's steam-installer for currency). The `smoothdesktop` meta depends on `steam-installer` as a fallback with a recommends on `flatpak-plugin-flathub` so Discover offers the flatpak version.
- **Proton** — managed by Steam itself; no special packaging.
- **Proton-GE** — not in apt; users install via ProtonUp-Qt (flatpak) or manually. We don't bundle it; we document it in the user guide.
- **Gamescope** — from Debian (current enough in trixie).
- **Gamemode** — from Debian.
- **MangoHud** — from Debian; works with both native and Proton games via `MANGOHUD=1`.
- **Lutris** — from Debian; for non-Steam Windows/native games.
- **Wine** — for Windows-program compatibility. Covered in detail below.

## Windows program compatibility

Running Windows applications is a first-class feature. Three complementary paths ship out of the box:

### Wine (the base layer) — WineHQ stable

From **WineHQ's official stable repo** (`https://dl.winehq.org/wine-builds/debian/`), not Debian's `wine` package. WineHQ ships the actively-developed upstream Wine; Debian's package lags by months and misses Wine features (DXVK integration paths, WoW64-no-i386 transitions, newer Windows-app compatibility fixes). For a desktop positioned as a Windows replacement, WineHQ is the right source.

The desktop bootstrap path adds WineHQ's apt source and GPG key before `smoothdesktop` is installed:

```
# WineHQ signing key → /etc/apt/keyrings/winehq-archive.key
# Source list → /etc/apt/sources.list.d/winehq.list:
# deb [signed-by=/etc/apt/keyrings/winehq-archive.key] https://dl.winehq.org/wine-builds/debian/ trixie main
```

Included in `smoothdesktop`:

- **`winehq-stable`** — WineHQ's stable channel metapackage, pulls `wine-stable`, `wine-stable-amd64`, `wine-stable-i386` via multiarch
- **`winetricks`** — scripted installer for Microsoft runtimes, DLLs, fonts, and common dependencies Windows apps expect (DirectX, .NET, VC++ redistributables, Corefonts)
- **`winbind`** — SMB/AD authentication support some Windows apps need

We ship `winehq-stable`, not `winehq-staging` or `winehq-devel` — staging carries experimental patches that can regress working apps; devel is a rolling preview. Stable is the right default for a product; advanced users can swap the channel themselves.

### i386 multiarch

WineHQ's 32-bit packages require Debian's i386 architecture enabled. The same desktop bootstrap path runs `dpkg --add-architecture i386 && apt update` before `winehq-stable` is resolved, so the dependency resolver sees the 32-bit packages Wine pulls in. Without this, 32-bit Windows apps (still the majority of legacy software) won't run.

### Prefix managers (Lutris, Bottles)

Raw Wine works but is fiddly for non-technical users; a prefix manager handles dependency bundles (DXVK, VKD3D, Proton-like components) per-app:

- **Lutris** (apt) — preconfigured with Epic/GOG/Battle.net installer integrations.
- **Bottles** — recommended to install via Flathub (`flatpak install flathub com.usebottles.bottles`); it's cleanly sandboxed and the Flathub version is much more current than Debian's. Not in apt Depends, but the `smoothdesktop-theme` Flathub preconfig makes it one click from Discover.

### Proton-GE (for gaming-adjacent Windows apps)

For Windows games distributed outside Steam — and Windows apps that need aggressive DXVK/VKD3D patches — **Proton-GE** is often the right tool. Not shipped by us (ProtonUp-Qt is the standard installer, available via Flathub); documented in the user guide as the answer when vanilla Wine struggles.

### Typical usage

```bash
# Out of the box, a Windows .exe just works for simple apps:
wine /path/to/installer.exe

# For apps needing runtimes, winetricks bundles them:
winetricks dotnet48 vcrun2019 corefonts

# For games / complex apps, Lutris or Bottles is the right path.
```

The stack covers: Windows productivity apps (Office, specialist tools), Windows games (via Steam+Proton or Lutris), and legacy 32-bit Windows apps (via multiarch Wine).

## Codecs, DRM, and non-free bits

- `intel-media-va-driver-non-free` (Intel VA-API for new-codec decode) — via `smooth-gfx`.
- `libdvd-pkg` — for DVD playback, if anyone still does that.
- Spotify, Netflix, Disney+ — users install Widevine-containing Chrome or Firefox themselves. Widevine DRM can't be redistributed; we don't ship it.
- Microsoft fonts — `ttf-mscorefonts-installer` from Debian `contrib`; SmoothDesktop's bootstrap path already enables `contrib`, so this stays a user-choice package rather than a repo-bootstrap step.

## Desktop-specific tuning (`smoothdesktop-tuning`)

**Sysctl:**

```
vm.swappiness = 60
vm.max_map_count = 1048576            # games need this (same as HTPC)
kernel.split_lock_mitigate = 0        # some games; Linux 5.17+
fs.inotify.max_user_watches = 524288  # IDEs/syncthing/etc.
```

**tuned profile:** CPU governor `schedutil`.

**udev:** mq-deadline for SSD, none for NVMe.

## Printing, Bluetooth, screen sharing

All "just works" defaults:

- **Printing** — `cups` + `printer-driver-all` + `system-config-printer-kde`. Network printer discovery via `avahi-daemon`. Scanner support via `sane-utils` + `simple-scan` on recommends.
- **Bluetooth** — `bluedevil` (KDE's BT stack) + `bluez`. Pairing and audio routing Just Work.
- **Screen sharing** — `xdg-desktop-portal-kde` for Wayland screen share from within apps using the portal API (Firefox, Chrome, Discord, OBS).

## NVIDIA

See [`GRAPHICS.md`](GRAPHICS.md). v1 posture: user enables Debian's `non-free`, installs `nvidia-driver-<latest>`, DKMS builds against `linux-smoothkernel-headers`, everything works. If we later decide to mirror NVIDIA drivers into `common`, `smoothdesktop` picks up the benefit transparently.

## First-run experience

After install:

1. SDDM greeter with Rakuen branding.
2. Login → Plasma startup with the `com.rakuen.smoothdesktop` look-and-feel applied.
3. No extra first-run wizard from us — Plasma's own "welcome" app (Discover) surfaces updates and featured Flathub apps.
4. Audio device, monitor arrangement, keyboard layout detected automatically (systemd + pipewire + plasma).

## Non-goals

- **Shipping a curated Flathub subset.** Flathub's policy is good enough; we don't re-curate.
- **An "everything for macOS users" alt-theme.** The theme is Windows-leaning. macOS-style dock/global-menu is a third-party KDE layout users can apply themselves.
- **Gaming-only distro positioning.** We care about gaming, but the primary positioning is "Windows replacement." Gaming is one use case, not the use case.
- **Tiling window manager variant.** Out of scope. Users who want tiling install KWin's bismuth/krohnkite scripts or switch to a dedicated tiling distro.

## Open questions

- **Wayland by default or X11 by default.** Plasma 6 Wayland is the right default in 2026, but a small set of proprietary apps still break. Probably Wayland with a documented escape hatch.
- **Snapshot / rollback.** btrfs + snapper or nothing? Desktop users benefit from "apt upgrade broke my system, roll back." Deferred decision.
- **KDE Plasma override policy.** Debian's Plasma freeze feels tolerable at trixie launch; revisit at mid-cycle. See [`ARCHITECTURE.md`](ARCHITECTURE.md) → "Override only where Debian stable is actually stale."

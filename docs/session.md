# Trying Orbit

Orbit installs as an extra entry on the login screen. The normal **COSMIC**
session stays installed and unchanged, so you can switch back at any time.

## What you need

- COSMIC installed from your distribution. Orbit replaces only the
  compositor; the panel, settings and apps are your normal COSMIC ones.
- Orbit and your COSMIC should be the same version. The installer warns you
  (`ORB-W01`) when they differ.
- Rust and the build libraries. On Arch-based systems:

  ```bash
  sudo pacman -S --needed rust base-devel libinput libxkbcommon mesa libdisplay-info seatd pixman
  ```

- The `orbit-applets` checkout next to `orbit-comp`, for the Window Layout
  applet with its Scrolling button. Without it the panel keeps COSMIC's own
  applet, and the keyboard shortcuts still work.

## Install

From the `orbit-comp` checkout:

```bash
session/install.sh
```

This builds both projects (the first release build takes a while), copies
them into `~/.local/share/orbit/prefix`, and asks for your administrator
password to add two files:

- `/usr/local/bin/orbit-session`, the session launcher.
- `/usr/share/wayland-sessions/orbit.desktop`, the login screen entry.

Then save your work, log out, choose **Orbit** on the login screen, and log in.

After you change the code, run `session/install.sh` again and log in again.
The installed copy doesn't change while you rebuild, so a running Orbit
session never picks up a half-built binary.

Useful options: `--build-only` (no login screen entry and no password),
`--debug` (faster to build), `--no-build` (install what's already built), and
`--no-applet`. Run `session/install.sh --help` for the full list.

## Using it

On your first Orbit login, tiled workspaces scroll. Turn tiling on for a
workspace with **Super+Y** or the Window Layout applet. Then:

| Keys                            | Action                                       |
|---------------------------------|----------------------------------------------|
| Super+Left / Super+Right        | Focus the column to the left or right        |
| Super+Shift+Left / Right        | Move the window to the left or right         |
| Super+Ctrl+Up / Super+Ctrl+Down | Switch workspace (stacked vertically while scrolling) |
| Super+C                         | Centre the focused column                    |
| Three-finger swipe sideways     | Pan the strip of columns                     |

The applet switches between **Floating**, **Tiling** (COSMIC's classic layout)
and **Scrolling**, for the current workspace and for new workspaces. The
engine choice is global and stored in
`~/.config/cosmic/com.system76.CosmicComp/v1/tiling_engine`; normal COSMIC
ignores it.

While the engine is Scrolling, the applet also shows:

| Setting | What it does | Default |
|---|---|---|
| New window width | Column width for newly opened windows: 25%, 50%, 75%, 90% or a custom 25–100% | 50% |
| Focus the window you scroll to | A touchpad pan focuses the window it scrolls into, once enough of it is on screen | Off |
| Once this much of it is on screen | How much of that window must be visible first | 60% |
| Blur the desktop behind windows | Blurs the wallpaper and desktop icons behind a scrolling workspace | On |

They're stored together in the `scrolling` key next to `tiling_engine`.

**Maximize** on a scrolling workspace widens the window's column to the full
screen, and maximizing again restores its width. Apps that reopen maximized,
such as browsers, open at the new-window width instead.

Orbit uses your normal COSMIC settings (wallpaper, panel, keyboard and so on),
so changes you make in one session appear in the other.

## When something goes wrong

- **Orbit doesn't start:** the launcher starts normal COSMIC instead and
  shows a notification with an error code. A broken install never leaves you
  without a desktop.
- **The login screen loops or the screen stays black:** choose **COSMIC** on
  the login screen. If you can't, press Ctrl+Alt+F3, log in, and run
  `session/uninstall.sh`.
- **To report a problem**, run:

  ```bash
  ~/.local/share/orbit/prefix/bin/orbit-report
  ```

  It saves a report with your user name, home folder, host name, email
  addresses and window titles removed, lets you read it, and offers to open an
  email with it attached. Nothing is sent unless you send that email yourself.

Logs are in `~/.local/state/orbit/`: `install.log`, `uninstall.log` and
`session.log`.

### Error codes

| Code    | Meaning                                                       |
|---------|---------------------------------------------------------------|
| ORB-I01 | Rust (`cargo`) isn't installed                                |
| ORB-I02 | COSMIC isn't installed (`/usr/bin/start-cosmic` missing)      |
| ORB-I04 | The compositor failed to build                                |
| ORB-I05 | The Window Layout applet failed to build                      |
| ORB-I06 | `--no-build` was used, but there's no build to install        |
| ORB-I07 | Copying into `~/.local/share/orbit` failed                    |
| ORB-I08 | A file or folder Orbit needs belongs to something else         |
| ORB-I09 | Adding the login screen files failed (often a cancelled password) |
| ORB-I10 | The installer was run as root                                 |
| ORB-I11 | `--destdir` isn't an absolute path                            |
| ORB-W01 | Orbit and the installed COSMIC are different versions          |
| ORB-W02 | The `orbit-applets` checkout wasn't found; COSMIC's applet is used |
| ORB-S01 | Orbit's compositor isn't installed; normal COSMIC was started  |
| ORB-S02 | COSMIC's session launcher is missing                          |
| ORB-S03 | `orbit-session` was run inside a running desktop               |
| ORB-U01 | The uninstaller found a file Orbit didn't create, and left it  |
| ORB-U02 | Removing Orbit's files failed                                 |
| ORB-U03 | The uninstaller was run as root                               |
| ORB-U04 | The uninstaller was run inside an Orbit session               |

Codes are stable: a code always keeps its meaning, and a removed code is
never reused.

## Uninstall

Log in to normal COSMIC, then run:

```bash
session/uninstall.sh
```

It removes only files Orbit's installer created. Add `--purge` to also delete
the logs and reports in `~/.local/state/orbit`.

## Testing the scripts

```bash
python3 -m unittest discover -s session/tests -v
```

The tests use a throwaway home folder and a staging directory. They never
touch the real login screen, systemd user manager or COSMIC settings.

#!/usr/bin/env bash
# Build Orbit and install it as an extra login session next to normal COSMIC.
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

SESSION_DIR=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd -P)
COMP_ROOT=$(dirname -- "$SESSION_DIR")
# shellcheck source=lib.sh
. "$SESSION_DIR/lib.sh"

usage() {
    cat <<'EOF'
Usage: session/install.sh [options]

Builds the Orbit compositor and Window Layout applet, copies them into
~/.local/share/orbit, and adds an "Orbit" entry to the login screen.
Your normal COSMIC session is not changed.

Options:
  --build-only      Build and install for your account, but don't add the
                    login screen entry (no administrator password needed).
  --no-build        Install binaries that are already built.
  --debug           Use debug builds (faster to compile, slower to run).
  --no-applet       Skip the Window Layout applet; the panel keeps COSMIC's.
  --destdir DIR     Put the login screen files under DIR instead of /. For
                    testing; DIR must be an absolute path.
  -h, --help        Show this help.

Environment:
  ORBIT_APPLETS_DIR  Checkout of orbit-applets (default: ../orbit-applets).
EOF
}

BUILD=true PROFILE=release APPLET=true SYSTEM=true DESTDIR=${DESTDIR-}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --build-only) SYSTEM=false ;;
        --no-build) BUILD=false ;;
        --debug) PROFILE=debug ;;
        --no-applet) APPLET=false ;;
        --destdir)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            DESTDIR=$2; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

mkdir -p "$ORBIT_STATE"
ORBIT_LOG=$ORBIT_STATE/install.log
: >"$ORBIT_LOG"
exec > >(tee -a "$ORBIT_LOG") 2> >(tee -a "$ORBIT_LOG" >&2)
orbit_note "Orbit install log: $ORBIT_LOG"

# --- Preflight -----------------------------------------------------------

[ "$(id -u)" -ne 0 ] || orbit_fail ORB-I10 "Don't run the installer as root" \
    "Orbit installs into your own account and asks for the administrator password only when it adds the login screen entry. Run it again as your normal user, without sudo." \
    "effective uid is 0"

case "$DESTDIR" in
    ''|/*) ;;
    *) orbit_fail ORB-I11 "The staging folder isn't valid" \
        "--destdir needs an absolute path, such as /tmp/orbit-stage." \
        "DESTDIR=$DESTDIR" ;;
esac

if [ "$BUILD" = true ]; then
    command -v cargo >/dev/null 2>&1 || orbit_fail ORB-I01 "Rust isn't installed" \
        "Orbit is built from source and needs the Rust toolchain. On Arch-based systems install it with: sudo pacman -S rust. Then run this installer again." \
        "cargo not found in PATH"
fi

if [ "$SYSTEM" = true ] && [ -z "$DESTDIR" ] && [ ! -x /usr/bin/start-cosmic ]; then
    orbit_fail ORB-I02 "COSMIC isn't installed" \
        "Orbit runs inside the COSMIC desktop and replaces only its window manager. Install COSMIC first (on Arch-based systems: sudo pacman -S cosmic), then run this installer again." \
        "/usr/bin/start-cosmic is missing"
fi

ORBIT_EPOCH=$(git -C "$COMP_ROOT" describe --tags --match 'epoch-*' --abbrev=0 2>/dev/null || echo unknown)
ORBIT_DESCRIBE=$(git -C "$COMP_ROOT" describe --tags --match 'epoch-*' --dirty 2>/dev/null || echo unknown)
SYSTEM_COSMIC=
if command -v pacman >/dev/null 2>&1; then
    SYSTEM_COSMIC=$(pacman -Q cosmic-session 2>/dev/null | awk '{print $2}' | sed -E 's/^[0-9]+://; s/-[^-]+$//') || true
elif command -v dpkg-query >/dev/null 2>&1; then
    SYSTEM_COSMIC=$(dpkg-query -W -f='${Version}' cosmic-session 2>/dev/null | sed -E 's/^[0-9]+://; s/[~+-].*$//') || true
fi
if [ -n "$SYSTEM_COSMIC" ] && [ "$ORBIT_EPOCH" != unknown ] && [ "epoch-$SYSTEM_COSMIC" != "$ORBIT_EPOCH" ]; then
    orbit_warn ORB-W01 "Orbit and your COSMIC are different versions" \
        "Your COSMIC is $SYSTEM_COSMIC and this Orbit checkout is based on ${ORBIT_EPOCH#epoch-}. The panel, settings or login can misbehave when they don't match. If anything goes wrong, pick the normal COSMIC session at the login screen."
fi

APPLETS_DIR=${ORBIT_APPLETS_DIR:-$(dirname -- "$COMP_ROOT")/orbit-applets}
if [ "$APPLET" = true ] && [ ! -f "$APPLETS_DIR/cosmic-applet-tiling/Cargo.toml" ]; then
    orbit_warn ORB-W02 "Window Layout applet not found" \
        "Couldn't find the orbit-applets checkout at $APPLETS_DIR, so the panel keeps COSMIC's own layout applet, which has no Scrolling button. Keyboard shortcuts still work. Set ORBIT_APPLETS_DIR to use a different folder."
    APPLET=false
fi

# --- Build ---------------------------------------------------------------

profile_flag=()
[ "$PROFILE" = release ] && profile_flag=(--release)

COMP_BIN="$COMP_ROOT/target/$PROFILE/cosmic-comp"
APPLET_BIN="$APPLETS_DIR/target/$PROFILE/cosmic-applet-tiling"

if [ "$BUILD" = true ]; then
    orbit_step "Building the Orbit compositor ($PROFILE)"
    [ "$PROFILE" = release ] && orbit_note "The first release build can take 10 minutes or more."
    cargo build --locked "${profile_flag[@]}" --manifest-path "$COMP_ROOT/Cargo.toml" \
        || orbit_fail ORB-I04 "The compositor didn't build" \
            "Compiling Orbit's compositor failed. Make sure the build libraries are installed (on Arch-based systems: sudo pacman -S --needed base-devel libinput libxkbcommon mesa libdisplay-info seatd pixman), then try again. The compiler output above says which part failed." \
            "cargo build exited with status $? (profile $PROFILE)"
    if [ "$APPLET" = true ]; then
        orbit_step "Building the Window Layout applet ($PROFILE)"
        cargo build --locked "${profile_flag[@]}" --manifest-path "$APPLETS_DIR/Cargo.toml" -p cosmic-applet-tiling \
            || orbit_fail ORB-I05 "The Window Layout applet didn't build" \
                "Compiling the panel applet failed. You can install without it using --no-applet; the panel then keeps COSMIC's own layout applet." \
                "cargo build -p cosmic-applet-tiling exited with status $? (profile $PROFILE)"
    fi
fi

[ -x "$COMP_BIN" ] || orbit_fail ORB-I06 "The compositor hasn't been built yet" \
    "There's no $PROFILE build to install. Run the installer without --no-build, or add --debug if you built a debug version." \
    "missing $COMP_BIN"
if [ "$APPLET" = true ] && [ ! -x "$APPLET_BIN" ]; then
    orbit_fail ORB-I06 "The applet hasn't been built yet" \
        "There's no $PROFILE build of the Window Layout applet to install. Run the installer without --no-build, or use --no-applet." \
        "missing $APPLET_BIN"
fi

# --- Install for this user ---------------------------------------------------

orbit_step "Installing Orbit into $ORBIT_DATA"
if [ -e "$ORBIT_DATA" ] && ! orbit_owned_file "$ORBIT_DATA/owner"; then
    orbit_fail ORB-I08 "Another program is using Orbit's folder" \
        "$ORBIT_DATA already exists but wasn't created by this installer, so it was left alone. Move or remove it, then run the installer again." \
        "no $ORBIT_OWNER_LINE marker in $ORBIT_DATA/owner"
fi

install_prefix() {
    # Runs under `||`, where bash ignores set -e, so every step checks itself.
    local stage="$ORBIT_DATA/prefix.new" src="$APPLETS_DIR/cosmic-applet-tiling/data"
    rm -rf -- "$stage" || return 1
    install -d "$stage/bin" "$stage/share/orbit" "$stage/share/applications" \
        "$stage/share/icons/hicolor/scalable/apps" || return 1
    install -m 0755 "$COMP_BIN" "$stage/bin/cosmic-comp" || return 1
    install -m 0755 "$SESSION_DIR/orbit-report" "$stage/bin/orbit-report" || return 1
    install -m 0644 "$SESSION_DIR/lib.sh" "$stage/share/orbit/lib.sh" || return 1
    if [ "$APPLET" = true ]; then
        install -m 0755 "$APPLET_BIN" "$stage/bin/cosmic-applet-tiling" || return 1
        # Applets are panel plugins, not menu entries; drop the unregistered
        # COSMIC category so desktop-file validators stay quiet.
        grep -v '^Categories=COSMIC;$' "$src/com.system76.CosmicAppletTiling.desktop" \
            >"$stage/share/applications/com.system76.CosmicAppletTiling.desktop" || return 1
        install -m 0644 "$src"/icons/scalable/apps/com.system76.CosmicAppletTiling*.svg \
            "$stage/share/icons/hicolor/scalable/apps/" || return 1
    fi
    {
        echo "$ORBIT_DESCRIBE"
        echo "commit: $(git -C "$COMP_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
        if [ "$APPLET" = true ]; then
            echo "applet: $(git -C "$APPLETS_DIR" describe --tags --match 'epoch-*' --dirty 2>/dev/null || echo unknown)"
        else
            echo "applet: system"
        fi
        echo "profile: $PROFILE"
        echo "installed: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$stage/share/orbit/build-info" || return 1
    # Swap in one step so a running Orbit session never sees a half-copied prefix.
    rm -rf -- "$ORBIT_DATA/prefix.old" || return 1
    if [ -d "$ORBIT_PREFIX" ]; then
        mv -- "$ORBIT_PREFIX" "$ORBIT_DATA/prefix.old" || return 1
    fi
    mv -- "$stage" "$ORBIT_PREFIX" || return 1
    rm -rf -- "$ORBIT_DATA/prefix.old"
}

mkdir -p "$ORBIT_DATA"
printf '%s\n' "$ORBIT_OWNER_LINE" >"$ORBIT_DATA/owner"
install_prefix 2>&1 || orbit_fail ORB-I07 "Orbit couldn't be copied into your account" \
    "Copying the built files into $ORBIT_DATA failed. Check that the disk isn't full and that you own that folder, then try again." \
    "install_prefix failed"
orbit_note "Installed $ORBIT_DESCRIBE ($PROFILE)."

if [ "$SYSTEM" = false ]; then
    orbit_note ""
    orbit_note "Built and installed for your account. Run session/install.sh without"
    orbit_note "--build-only to add Orbit to the login screen."
    exit 0
fi

# --- Login screen entry --------------------------------------------------------

orbit_step "Adding Orbit to the login screen"
launcher="$DESTDIR$SYSTEM_LAUNCHER"
desktop="$DESTDIR$SYSTEM_DESKTOP"
for target in "$launcher" "$desktop"; do
    if [ -e "$target" ] || [ -L "$target" ]; then
        orbit_owned_file "$target" || orbit_fail ORB-I08 "A file Orbit needs is already taken" \
            "$target exists but wasn't installed by Orbit, so it was left alone. Remove or rename it if you don't need it, then run the installer again." \
            "no $ORBIT_OWNER_LINE marker in $target"
    fi
done

as_root=()
if [ -z "$DESTDIR" ]; then
    orbit_note "Your administrator password is needed to add two files:"
    orbit_note "  $SYSTEM_LAUNCHER and $SYSTEM_DESKTOP"
    as_root=(sudo --)
fi
{
    "${as_root[@]}" install -D -m 0755 "$SESSION_DIR/orbit-session" "$launcher" \
        && "${as_root[@]}" install -D -m 0644 "$SESSION_DIR/orbit.desktop" "$desktop"
} || orbit_fail ORB-I09 "Orbit couldn't be added to the login screen" \
    "Orbit is installed for your account, but the login screen entry wasn't added. This usually means the administrator password was cancelled or wrong. Run the installer again to retry." \
    "installing $launcher or $desktop failed"

orbit_note ""
if [ -n "$DESTDIR" ]; then
    orbit_note "Login screen files staged under $DESTDIR. The real login screen wasn't changed."
else
    orbit_note "Done. Save your work, log out, choose Orbit on the login screen, and log in."
    orbit_note "If it doesn't start, you'll get normal COSMIC and a notification explaining why."
fi

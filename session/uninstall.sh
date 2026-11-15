#!/usr/bin/env bash
# Remove the Orbit login session and Orbit's files from your account.
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

SESSION_DIR=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd -P)
# shellcheck source=lib.sh
. "$SESSION_DIR/lib.sh"

usage() {
    cat <<'EOF'
Usage: session/uninstall.sh [--purge] [--destdir DIR]

Removes the Orbit login screen entry and ~/.local/share/orbit. Only files
that Orbit's installer created are removed. Your COSMIC settings and the
normal COSMIC session are not touched.

  --purge        Also remove Orbit's logs and reports (~/.local/state/orbit).
  --destdir DIR  Remove staged login screen files under DIR instead of /.
EOF
}

PURGE=false DESTDIR=${DESTDIR-}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --purge) PURGE=true ;;
        --destdir)
            [ "$#" -ge 2 ] || { usage >&2; exit 2; }
            DESTDIR=$2; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
case "$DESTDIR" in
    ''|/*) ;;
    *) echo "--destdir needs an absolute path." >&2; exit 2 ;;
esac

mkdir -p "$ORBIT_STATE"
ORBIT_LOG=$ORBIT_STATE/uninstall.log
: >"$ORBIT_LOG"
exec > >(tee -a "$ORBIT_LOG") 2> >(tee -a "$ORBIT_LOG" >&2)

[ "$(id -u)" -ne 0 ] || orbit_fail ORB-U03 "Don't run the uninstaller as root" \
    "Run it as your normal user; it asks for the administrator password itself when needed." \
    "effective uid is 0"

if [ "${ORBIT_SESSION-}" = 1 ] && [ -z "$DESTDIR" ]; then
    orbit_fail ORB-U04 "You're logged in to Orbit right now" \
        "Removing Orbit while it's running would break this session. Log out, log in to the normal COSMIC session, and run the uninstaller there." \
        "ORBIT_SESSION=1"
fi

system_files=()
for target in "$DESTDIR$SYSTEM_LAUNCHER" "$DESTDIR$SYSTEM_DESKTOP"; do
    [ -e "$target" ] || [ -L "$target" ] || continue
    orbit_owned_file "$target" || orbit_fail ORB-U01 "A file wasn't installed by Orbit" \
        "$target looks like it belongs to something else, so nothing was removed. Check it and remove it by hand if it's Orbit's." \
        "no $ORBIT_OWNER_LINE marker in $target"
    system_files+=("$target")
done

if [ "${#system_files[@]}" -gt 0 ]; then
    orbit_step "Removing Orbit from the login screen"
    as_root=()
    if [ -z "$DESTDIR" ]; then
        orbit_note "Your administrator password is needed to remove ${system_files[*]}"
        as_root=(sudo --)
    fi
    "${as_root[@]}" rm -f -- "${system_files[@]}" || orbit_fail ORB-U02 "Orbit couldn't be removed from the login screen" \
        "The administrator password was probably cancelled or wrong. Run the uninstaller again to retry." \
        "rm ${system_files[*]} failed"
fi

if [ -e "$ORBIT_DATA" ]; then
    orbit_owned_file "$ORBIT_DATA/owner" || orbit_fail ORB-U01 "Orbit's folder wasn't created by Orbit" \
        "$ORBIT_DATA exists but has no Orbit marker, so it was left alone." \
        "no $ORBIT_OWNER_LINE marker in $ORBIT_DATA/owner"
    orbit_step "Removing $ORBIT_DATA"
    rm -rf -- "$ORBIT_DATA" || orbit_fail ORB-U02 "Orbit's files couldn't be removed" \
        "Removing $ORBIT_DATA failed. Check that you own it, then try again." \
        "rm -rf failed"
fi

if [ "$PURGE" = true ]; then
    # The log being written by tee is unlinked here, which is fine on Linux.
    rm -rf -- "$ORBIT_STATE"
    echo "Removed Orbit's logs and reports."
fi

echo "Orbit is uninstalled. The normal COSMIC session is unchanged."
echo "Orbit's tiling_engine setting stays in ~/.config/cosmic; normal COSMIC ignores it."

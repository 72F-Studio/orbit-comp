# Shared helpers for the Orbit session scripts. Sourced by bash scripts only.
# SPDX-License-Identifier: GPL-3.0-only

ORBIT_OWNER_ID=orbit-session-v1
ORBIT_OWNER_LINE="X-OrbitOwner=$ORBIT_OWNER_ID"

# Where problem reports are sent. Left empty, the mail client opens with no
# recipient filled in and the user picks one.
ORBIT_REPORT_EMAIL=${ORBIT_REPORT_EMAIL-}

ORBIT_DATA=${XDG_DATA_HOME:-$HOME/.local/share}/orbit
ORBIT_PREFIX=$ORBIT_DATA/prefix
ORBIT_STATE=${XDG_STATE_HOME:-$HOME/.local/state}/orbit
ORBIT_REPORTS=$ORBIT_STATE/reports

SYSTEM_LAUNCHER=/usr/local/bin/orbit-session
SYSTEM_DESKTOP=/usr/share/wayland-sessions/orbit.desktop

# Set by each script to its own log file before calling orbit_fail.
ORBIT_LOG=${ORBIT_LOG-}

if [ -t 1 ]; then
    _b=$'\e[1m' _r=$'\e[31m' _y=$'\e[33m' _d=$'\e[2m' _n=$'\e[0m'
else
    _b='' _r='' _y='' _d='' _n=''
fi

orbit_note() { printf '%s\n' "$*"; }
orbit_step() { printf '\n%s==> %s%s\n' "$_b" "$*" "$_n"; }

# Remove anything that identifies the user or their machine from log text.
orbit_redact() {
    local host
    host=$(cat /etc/hostname 2>/dev/null || uname -n)
    sed -E \
        -e "s#${HOME//#/\\#}#~#g" \
        -e "s#/home/${USER:-__nouser__}#~#g" \
        -e "s#\\b${USER:-__nouser__}\\b#<user>#g" \
        -e "s#\\b${host:-__nohost__}\\b#<host>#g" \
        -e 's#[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}#<email>#g' \
        -e 's#(token|password|secret|key)=[^[:space:]]+#\1=<redacted>#Ig' \
        -e 's#title(=|: )"[^"]*"#title\1"<redacted>"#g'
}

orbit_system_summary() {
    echo "kernel: $(uname -r)"
    if command -v pacman >/dev/null 2>&1; then
        pacman -Q 2>/dev/null | grep -E '^cosmic-(comp|session|panel|applets|settings) ' | sed 's/^/package: /'
    elif command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W -f='package: ${Package} ${Version}\n' cosmic-comp cosmic-session cosmic-panel cosmic-applets 2>/dev/null
    fi
    if command -v lspci >/dev/null 2>&1; then
        lspci -k 2>/dev/null | grep -A2 -E 'VGA|3D|Display' | grep -E 'VGA|3D|Display|in use' | sed 's/^[0-9a-f:.]* //; s/^/gpu: /'
    fi
    if [ -f "$ORBIT_PREFIX/share/orbit/build-info" ]; then
        sed 's/^/build: /' "$ORBIT_PREFIX/share/orbit/build-info"
    fi
}

# orbit_write_report CODE HEADLINE WHY -> prints the report path
orbit_write_report() {
    local code=$1 headline=$2 why=$3 file
    mkdir -p "$ORBIT_REPORTS"
    file="$ORBIT_REPORTS/orbit-report-$code-$(date +%Y%m%d-%H%M%S).txt"
    {
        echo "Orbit problem report"
        echo "error: $code"
        echo "summary: $headline"
        echo "detail: $why"
        echo "time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo
        orbit_system_summary
        for log in "$ORBIT_LOG" "$ORBIT_STATE/session.log"; do
            [ -n "$log" ] && [ -f "$log" ] || continue
            echo
            echo "--- last 150 lines of $(basename -- "$log") ---"
            tail -n 150 -- "$log"
        done
        if command -v journalctl >/dev/null 2>&1; then
            echo
            echo "--- compositor warnings and errors from this boot ---"
            journalctl --user -b --no-pager -o short-iso -p warning 2>/dev/null \
                | grep -iE 'cosmic.comp|cosmic.session|orbit' | tail -n 100
        fi
    } 2>/dev/null | orbit_redact >"$file"
    printf '%s\n' "$file"
}

# Whether prompts can be shown. Decided before output is redirected to the log.
if [ -t 0 ] && [ -t 1 ]; then ORBIT_INTERACTIVE=true; else ORBIT_INTERACTIVE=false; fi

# orbit_start_log FILE: copy all output to FILE as well as the terminal.
# On exit, wait for the copies to finish so nothing prints after the prompt
# comes back, which looks like the script hung.
orbit_start_log() {
    ORBIT_LOG=$1
    : >"$ORBIT_LOG"
    exec 3>&1 4>&2
    exec > >(tee -a "$ORBIT_LOG" >&3)
    _orbit_tee_out=$!
    exec 2> >(tee -a "$ORBIT_LOG" >&4)
    _orbit_tee_err=$!
    trap _orbit_end_log EXIT
}
_orbit_end_log() {
    exec 1>&3 2>&4
    wait "$_orbit_tee_out" "$_orbit_tee_err" 2>/dev/null || true
}

# Let the user read the report, then open their mail client with it attached.
# Nothing is ever uploaded by the script itself. Prompts talk to the terminal
# directly, so they work while output is also going to the log.
orbit_offer_report() {
    local file=$1 code=$2 answer
    orbit_note ""
    orbit_note "A report without personal details was saved to:"
    orbit_note "  $file"
    [ "$ORBIT_INTERACTIVE" = true ] && [ -r /dev/tty ] && [ -w /dev/tty ] || return 0
    printf 'Show the report now? [y/N] ' >/dev/tty
    read -r answer </dev/tty || return 0
    case "$answer" in
        y|Y|yes) { "${PAGER:-less}" -- "$file" || cat -- "$file"; } </dev/tty >/dev/tty 2>&1 ;;
    esac
    command -v xdg-email >/dev/null 2>&1 || return 0
    printf 'Open an email to the developer with this report attached? [y/N] ' >/dev/tty
    read -r answer </dev/tty || return 0
    case "$answer" in
        y|Y|yes)
            xdg-email --subject "Orbit problem report ($code)" \
                --body "What were you doing when this happened?" \
                --attach "$file" ${ORBIT_REPORT_EMAIL:+"$ORBIT_REPORT_EMAIL"} \
                >/dev/null 2>&1 \
                || orbit_note "Couldn't open your mail client. Attach the file above by hand."
            ;;
    esac
}

# orbit_fail CODE HEADLINE DESCRIPTION WHY
# HEADLINE is short and human. DESCRIPTION says what went wrong and what to try.
# WHY is the technical cause; it stays under the details line and in the report.
orbit_fail() {
    local code=$1 headline=$2 description=$3 why=${4-} file
    {
        printf '\n%s%s✗ %s%s\n' "$_b" "$_r" "$headline" "$_n"
        printf '%s\n' "$description" | fold -s -w 78 | sed 's/^/  /'
        printf '\n  %s▸ Details: error %s%s\n' "$_d" "$code" "$_n"
        [ -n "$why" ] && printf '%s\n' "$why" | orbit_redact | sed "s/^/    $_d/; s/\$/$_n/"
    } >&2
    file=$(orbit_write_report "$code" "$headline" "$why")
    orbit_offer_report "$file" "$code" >&2
    exit 1
}

# orbit_warn CODE HEADLINE DESCRIPTION
orbit_warn() {
    printf '\n%s! %s%s\n' "$_y" "$2" "$_n" >&2
    printf '%s\n' "$3" | fold -s -w 78 | sed 's/^/  /' >&2
    printf '  %s▸ Details: warning %s%s\n' "$_d" "$1" "$_n" >&2
}

# True when PATH is a regular file carrying the Orbit ownership marker.
# An empty regular file also counts: it holds nothing to lose, and is what an
# interrupted install leaves behind.
orbit_owned_file() {
    [ -f "$1" ] && [ ! -L "$1" ] || return 1
    [ ! -s "$1" ] || grep -qF "$ORBIT_OWNER_LINE" -- "$1"
}

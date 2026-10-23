#!/usr/bin/env bash
# Build, sign, and install a local Hypertalk.app for testing.
#   scripts/dev-install.sh
#
# macOS keys the Accessibility and Microphone grants to the app's code
# identity. An ad-hoc signature changes on every build, so each rebuild
# silently loses the grants. Signing with the Developer ID certificate and
# the fixed bundle ID com.jetlej.hypertalk (packaging/Info.plist) keeps one
# identity across rebuilds and releases.
#
# Installs to /Applications, or ~/Applications when /Applications is not
# writable, and links /usr/local/bin/hypertalk to the app's executable. A plain
# binary already at that path (an old CLI install) is only replaced after you
# say yes. A running copy is quit and reopened.
#
#   HYPERTALK_SIGN_IDENTITY  signing identity (default: the keychain's Developer ID)
#   HYPERTALK_INSTALL_DIR    where Hypertalk.app goes
#   HYPERTALK_LINK_DIR       where the hypertalk link goes (default /usr/local/bin;
#                         set it empty to skip the link)
#   HYPERTALK_NO_RESTART=1   don't quit and reopen a running copy

set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${HYPERTALK_INSTALL_DIR:-}" ]; then
    if [ -w /Applications ]; then
        HYPERTALK_INSTALL_DIR=/Applications
    else
        HYPERTALK_INSTALL_DIR="$HOME/Applications"
    fi
fi
LINK_DIR="${HYPERTALK_LINK_DIR-/usr/local/bin}"
BUILD="${HYPERTALK_BUILD_DIR:-build}"
DEST="$HYPERTALK_INSTALL_DIR/Hypertalk.app"
EXE="$DEST/Contents/MacOS/hypertalk"

VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo 0.0.0)"
HYPERTALK_TIMESTAMP=none HYPERTALK_BUILD_DIR="$BUILD" scripts/build-app.sh "${VERSION#v}"

WAS_RUNNING=0
if [ -z "${HYPERTALK_NO_RESTART:-}" ] && pgrep -f "^$EXE" >/dev/null 2>&1; then
    WAS_RUNNING=1
    echo "→ quitting the running Hypertalk"
    pkill -TERM -f "^$EXE" || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -f "^$EXE" >/dev/null 2>&1 || break
        sleep 0.5
    done
fi

echo "→ installing to $DEST"
mkdir -p "$HYPERTALK_INSTALL_DIR"
rm -rf "$DEST"
ditto "$BUILD/Hypertalk.app" "$DEST"

if [ -n "$LINK_DIR" ]; then
    LINK="$LINK_DIR/hypertalk"
    REPLACE=1
    if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
        REPLACE=0
        if [ -t 0 ]; then
            printf '%s is a separate hypertalk binary (an old CLI install). Replace it with a link to %s? [y/N] ' "$LINK" "$EXE"
            read -r answer
            case "$answer" in y|Y|yes) REPLACE=1 ;; esac
        fi
        [ "$REPLACE" = 1 ] || echo "  left $LINK as it was"
    fi
    if [ "$REPLACE" = 1 ]; then
        echo "→ linking $LINK"
        mkdir -p "$LINK_DIR" 2>/dev/null || sudo mkdir -p "$LINK_DIR"
        SUDO=""
        [ -w "$LINK_DIR" ] || SUDO="sudo"
        $SUDO ln -sfn "$EXE" "$LINK"
    fi
fi

if [ "$WAS_RUNNING" = 1 ]; then
    echo "→ reopening Hypertalk"
    open "$DEST"
fi

if [ -f "$HOME/Library/LaunchAgents/com.digimata.parrot.plist" ]; then
    echo "note: the old LaunchAgent is still installed. Open $DEST once; it removes the agent."
fi

echo "✓ installed Hypertalk $("$EXE" --version 2>/dev/null || echo "$VERSION") at $DEST"

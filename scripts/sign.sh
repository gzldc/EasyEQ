#!/usr/bin/env bash
# Shared signing helper, sourced by bundle.sh and package.sh (not run directly).
# Ad-hoc signing (SIGN_IDENTITY unset, empty or "-") uses --timestamp=none; any real identity
# uses --timestamp (secure timestamp), which notarization requires.
# SIGN_DRY_RUN=1 prints the codesign command instead of running it.
#
# Local development: if SIGN_IDENTITY is unset and the keychain holds a self-signed identity named
# "EasyEQ Local Signing", it is used instead of ad-hoc. Its designated requirement is pinned to the
# certificate, so macOS keeps the system-audio permission across rebuilds.

LOCAL_SIGN_IDENTITY="EasyEQ Local Signing"

sign_app() {
  local app="$1"
  local identity="${SIGN_IDENTITY:-}"
  if [ -z "$identity" ]; then
    if security find-identity -p codesigning 2>/dev/null | grep -q "\"$LOCAL_SIGN_IDENTITY\""; then
      identity="$LOCAL_SIGN_IDENTITY"
    else
      identity="-"
    fi
  fi
  local ts_flag="--timestamp"
  if [ "$identity" = "-" ] || [ "$identity" = "$LOCAL_SIGN_IDENTITY" ]; then
    ts_flag="--timestamp=none"
  fi
  if [ "${SIGN_DRY_RUN:-0}" = "1" ]; then
    echo "DRY RUN: codesign --force --options runtime $ts_flag --sign \"$identity\" $app"
    return 0
  fi
  codesign --force --options runtime "$ts_flag" --sign "$identity" "$app"
}

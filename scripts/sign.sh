#!/usr/bin/env bash
# Shared signing helper, sourced by bundle.sh and package.sh (not run directly).
# Ad-hoc signing (SIGN_IDENTITY unset, empty or "-") uses --timestamp=none; any real identity
# uses --timestamp (secure timestamp), which notarization requires.
# SIGN_DRY_RUN=1 prints the codesign command instead of running it.

sign_app() {
  local app="$1"
  local identity="${SIGN_IDENTITY:--}"
  local ts_flag="--timestamp"
  if [ "$identity" = "-" ]; then
    ts_flag="--timestamp=none"
  fi
  if [ "${SIGN_DRY_RUN:-0}" = "1" ]; then
    echo "DRY RUN: codesign --force --options runtime $ts_flag --sign \"$identity\" $app"
    return 0
  fi
  codesign --force --options runtime "$ts_flag" --sign "$identity" "$app"
}

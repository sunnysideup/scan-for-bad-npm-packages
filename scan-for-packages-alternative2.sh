#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/sng-jroji/hulud-party.git"
DIR="hulud-party"

# remove if exists
[ -d "$DIR" ] && rm -rf "$DIR"

# clone repo
git clone --depth=1 "$REPO" "$DIR"

# ensure scan.sh exists and is executable
if [ ! -f "$DIR/scan.sh" ]; then
  echo "scan.sh not found in $DIR"
  exit 1
fi

# run scan.sh from original dir
chmod +x "$DIR/scan.sh"
sudo "$DIR/scan.sh"

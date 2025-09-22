#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/safedep/shai-hulud-migration-response.git"
DIR="shai-hulud-migration-response"

# remove if exists
[ -d "$DIR" ] && rm -rf "$DIR"

# clone repo
git clone --depth=1 "$REPO" "$DIR"




# ensure common.sh exists and is executable
if [ ! -f "$DIR/scripts/common.sh" ]; then
  echo "common.sh not found in $DIR"
  exit 1
fi
cd "$DIR"


echo "INSTALL USING BREW OR GO"
# go install github.com/safedep/vet@latest
# brew 
# brew tap safedep/tap
# brew install safedep/tap/vet
sudo ./scripts/pv-scan.sh
sudo ./scripts/pv-query.sh
sudo ./scripts/pv-payload-hash-scan.sh 


# run scan.sh from original dir
chmod +x "$DIR/scripts" -R


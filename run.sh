#!/usr/bin/env bash
set -euo pipefail

# Variables
BASE_DIR="/var/www"
TMP_DIR="$BASE_DIR/tmp"
REPO_URL="https://github.com/sunnysideup/scan-for-bad-npm-packages.git"
REPO_NAME="scan-for-bad-npm-packages"
REPO_DIR="$TMP_DIR/$REPO_NAME"
TARGET_DIRS=("$BASE_DIR" "$HOME")


# Function to run a given scan across all dirs
run_scan () {
    local script="$1"
    local args="${2:-}"
    echo "=== Running $(basename "$script") ==="
    for dir in "${TARGET_DIRS[@]}"; do
        echo "-> Target: $dir"
        cd "$dir"
        sudo bash "$REPO_DIR/$script" $args
    done
}

# Quick scans
run_scan "scan-for-suspect-packages.sh"
run_scan "scan-for-bad-strings.sh" "--list $REPO_DIR/bad-string.txt"

# Detailed scans
run_scan "scan-for-packages.sh" "--list $REPO_DIR/compromised-all.txt"
run_scan "scan-for-packages-alternative.sh" "--list $REPO_DIR/compromised-all.txt"

echo "All scans completed successfully."

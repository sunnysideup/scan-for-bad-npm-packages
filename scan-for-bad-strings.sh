#!/usr/bin/env bash
set -euo pipefail

patternFile=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list|-f) patternFile="${2:-}"; shift 2 ;;
    *) echo "Unknown option: $1"; echo "Usage: $0 --list <file-with-patterns>"; exit 1 ;;
  esac
done

[[ -n "$patternFile" ]] || { echo "Error: --list required"; exit 1; }
[[ -f "$patternFile" ]] || { echo "Error: File '$patternFile' not found!"; exit 1; }

while IFS= read -r pattern; do
  # skip empty/whitespace-only and comment lines
  [[ -z "${pattern// }" || "${pattern:0:1}" == "#" ]] && continue

  echo "=== Searching for: $pattern ==="
  grep -RsnFH --color=always -I \
    -- "$pattern" . 2>/dev/null \
    || echo "No matches for: $pattern"
  echo
done < "$patternFile"

echo "============================"
echo "Search complete."
echo "============================"
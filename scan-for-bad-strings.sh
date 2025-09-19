#!/usr/bin/env bash
set -euo pipefail

scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

patternFile="$scriptDir/bad-strings.txt"


while [[ $# -gt 0 ]]; do
  case "$1" in
    --list|-f) patternFile="${2:-}"; shift 2 ;;
    --comp)    compromisedFile="${2:-}"; shift 2 ;;
    *) echo "Unknown option: $1"; echo "Usage: $0 --list <file>"; exit 1 ;;
  esac
done

[[ -n "$patternFile" ]] || { echo "Error: --list required"; exit 1; }
[[ -f "$patternFile" ]] || { echo "Error: File '$patternFile' not found!"; exit 1; }

# ---- helpers
warn() { printf '%s\n' "$*" >&2; }

EXCLUDES=(
  --exclude-dir='.git'
  # --exclude-dir='node_modules'
  # --exclude-dir='vendor'
  --exclude-dir='.cache'
)

# ---- 1) Search patterns from --list (any file types)
while IFS= read -r pattern; do
  [[ -z "${pattern// }" || "${pattern:0:1}" == "#" ]] && continue
  echo "=== Searching for: $pattern ==="
  grep -RsnFH --color=always -I "${EXCLUDES[@]}" -- "$pattern" . 2>/dev/null \
    || echo "No matches for: $pattern"
  echo
done < "$patternFile"


echo "============================"
echo "Search complete."
echo "============================"

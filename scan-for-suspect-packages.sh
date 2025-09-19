#!/usr/bin/env bash
set -euo pipefail

# Directory where the script itself is located
scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

compromisedFile="$scriptDir/compromised-all.txt"


# ---- helpers
warn() { printf '%s\n' "$*" >&2; }

# Files to limit searches to (for compromised list)
INCLUDES=(
  --include='package.json'
  --include='package-lock.json'
  --include='npm-shrinkwrap.json'
  --include='yarn.lock'
  --include='pnpm-lock.yaml'
  --include='composer.json'
  --include='composer.lock'
)

EXCLUDES=(
  --exclude-dir='.git'
)

# ---- 2) Read compromised-all.txt (take text before first TAB), search only in manifest/lock files
if [[ -f "$compromisedFile" ]]; then
  echo "=== Processing compromised list: $compromisedFile ==="
  # cut to first field, trim, drop blanks/comments, uniq
  mapfile -t compromised < <(
    awk -F'\t' '{gsub(/^[ \t]+|[ \t]+$/,"",$1); if($1!="" && $1!~/^[[:space:]]*#/){print $1}}' "$compromisedFile" \
    | sort -u
  )

  for pkg in "${compromised[@]}"; do
    echo "--- Searching manifests for: $pkg ---"
    grep -RsnFH --color=always -I "${EXCLUDES[@]}" "${INCLUDES[@]}" -- "$pkg" . 2>/dev/null \
      || echo "OK"
    echo
  done
else
  warn "Warning: '$compromisedFile' not found; skipping compromised search."
fi

echo "============================"
echo "Search complete."
echo "============================"

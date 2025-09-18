#!/usr/bin/env bash

# usage: ./search.sh patterns.txt

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <file-with-patterns>"
  exit 1
fi

patternFile="$1"

if [[ ! -f "$patternFile" ]]; then
  echo "File not found: $patternFile"
  exit 1
fi

while IFS= read -r pattern; do
  # skip empty or whitespace-only lines
  [[ -z "${pattern// }" ]] && continue

  echo "=== Searching for: $pattern ==="
  grep -Rsn --color=always --exclude-dir=.git --exclude-dir=node_modules \
    "$pattern" . 2>/dev/null || echo "No matches for: $pattern"
  echo
done < "$patternFile"
echo "Search complete."
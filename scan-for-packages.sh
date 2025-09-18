#!/usr/bin/env bash
set -euo pipefail

usage(){ echo "Usage: $0 --list <file_or_url> [--jobs N]"; exit 1; }

LIST_SRC=""; JOBS="${JOBS:-}"
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --list) LIST_SRC="${2:-}"; shift 2 ;;
    --jobs) JOBS="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done
[ -n "$LIST_SRC" ] || usage
: "${JOBS:=$(command -v nproc >/dev/null && nproc || echo 4)}"

# --- fetch targets (file or URL) ---
fetch() {
  local src="$1"
  if [[ "$src" =~ ^https?:// ]]; then
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$src"
    elif command -v wget >/dev/null 2>&1; then wget -qO- "$src"
    else echo "Need curl or wget to fetch URL: $src" >&2; exit 2; fi
  else
    cat "$src"
  fi
}

trim(){ sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
normalize_spec(){ printf '%s' "$1" | sed -E 's/^[\^~>=< ]*//; s/[[:space:]]*$//'; }
version_in_list(){ local v="$1" list="$2" IFS=',' x; for x in $list; do [ "$(trim<<<"$v")" = "$(trim<<<"$x")" ] && return 0; done; return 1; }

json_get(){ # $1=file $2=jqexpr
  if command -v jq >/dev/null 2>&1; then jq -r "$2 // empty" "$1" 2>/dev/null || true
  else
    node -e '
      try{
        const fs=require("fs");
        const f=process.argv[1], sel=process.argv[2];
        const get=(o,p)=>p.split(".").reduce((a,k)=>a&&a[k],o);
        const o=JSON.parse(fs.readFileSync(f,"utf8"));
        const v=get(o, sel.replace(/\["([^"]+)"\]/g,".$1").replace(/^\.+/,""));
        if(v!=null && typeof v!=="object") process.stdout.write(String(v));
      }catch(e){}
    ' "$1" "$2" 2>/dev/null || true
  fi
}

installed_pkg_version(){ # $1=dir $2=pkg
  local pj="$1/node_modules/$2/package.json"
  [ -f "$pj" ] && json_get "$pj" '.version' || true
}

# single jq call across deps (fast path)
requested_pkg_spec(){ # $1=package.json $2=pkg
  local pj="$1" pkg="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg p "$pkg" '
      (.dependencies[$p] // .devDependencies[$p] // .peerDependencies[$p] // .optionalDependencies[$p]) // empty
    ' "$pj" 2>/dev/null || true
  else
    local val
    for k in dependencies devDependencies peerDependencies optionalDependencies; do
      val="$(json_get "$pj" ".${k}[\"${pkg}\"]")"
      [ -n "${val:-}" ] && { printf '%s\n' "$val"; return 0; }
    done
  fi
}

lock_npm_version(){ # $1=dir $2=pkg
  local f v; for f in "$1/package-lock.json" "$1/npm-shrinkwrap.json"; do
    [ -f "$f" ] || continue
    if command -v jq >/dev/null 2>&1; then
      v="$(jq -r --arg p "node_modules/$2" '.packages[$p].version // .dependencies[$p|sub("^node_modules/";"")].version // empty' "$f" 2>/dev/null || true)"
      [ -n "$v" ] && { printf '%s\n' "$v"; return 0; }
    else
      awk -v pkg="$2" '
        $0 ~ "\"node_modules/"pkg"\"" { hit=1; next }
        hit && /"version"[[:space:]]*:/ { match($0,/"version"[[:space:]]*:[[:space:]]*"([^"]+)"/,m); print m[1]; exit }
      ' "$f" && return 0 || true
      awk -v pkg="$2" '
        $0 ~ "\"dependencies\"[[:space:]]*:" {dep=1}
        dep && $0 ~ "\""pkg"\"" {hit=1; next}
        hit && /"version"[[:space:]]*:/ { match($0,/"version"[[:space:]]*:[[:space:]]*"([^"]+)"/,m); print m[1]; exit }
      ' "$f" && return 0 || true
    fi
  done; return 1
}

lock_yarn_version(){ # $1=dir $2=pkg
  local f="$1/yarn.lock"; [ -f "$f" ] || return 1
  awk -v pkg="$2" '
    /^[^[:space:]].*:/{
      hdr=$0; gsub(/^[[:space:]]+|:[[:space:]]*$/,"",hdr)
      if (hdr ~ ("^\"?" pkg "@")) found=1; else found=0
      next
    }
    found && /^[[:space:]]*version[[:space:]]+"[^"]+"/{
      match($0,/version[[:space:]]+"([^"]+)"/,m); print m[1]; exit
    }
  ' "$f"
}

lock_pnpm_versions(){ # $1=dir $2=pkg
  local f="$1/pnpm-lock.yaml"; [ -f "$f" ] || return 1
  awk -v pkg="$2" 'match($0, "/" pkg "@([^:/]+):", m){ print m[1] }' "$f" | sort -u
}

# -------- load and prep targets --------
mapfile -t TARGET_ROWS < <(fetch "$LIST_SRC" | sed '/^[[:space:]]*$/d' | sed 's/[[:space:]]*,[[:space:]]*/,/g')

# create a simple package list file for quick grep prefilter
TMP_PKGS="$(mktemp)"; trap 'rm -f "$TMP_PKGS"' EXIT
for row in "${TARGET_ROWS[@]}"; do printf '%s\n' "$(printf '%s' "$row" | cut -f1)"; done | sort -u > "$TMP_PKGS"

# ---------- worker: process a single package.json ----------
process_one() {
  local pj="$1" dir pkg vers inst_ver spec norm v
  dir="$(dirname "$pj")"

  # quick prefilter: skip if project does not reference any target package in common files
  if ! grep -Fq -f "$TMP_PKGS" "$pj" 2>/dev/null \
     && ! grep -Fq -f "$TMP_PKGS" "$dir/yarn.lock" 2>/dev/null \
     && ! grep -Fq -f "$TMP_PKGS" "$dir/package-lock.json" 2>/dev/null \
     && ! grep -Fq -f "$TMP_PKGS" "$dir/pnpm-lock.yaml" 2>/dev/null; then
    return 0
  fi

  for row in "${TARGET_ROWS[@]}"; do
    pkg="$(printf '%s' "$row" | cut -f1)"
    vers="$(printf '%s' "$row" | cut -f2- | tr -d '\r' | trim)"
    [ -n "$pkg" ] || continue

    if inst_ver="$(installed_pkg_version "$dir" "$pkg")" && [ -n "$inst_ver" ] && version_in_list "$inst_ver" "$vers"; then
      printf 'INSTALLED\t%s@%s\t%s\n' "$pkg" "$inst_ver" "$dir"
      continue
    fi

    if spec="$(requested_pkg_spec "$pj" "$pkg")" && [ -n "$spec" ]; then
      norm="$(normalize_spec "$spec")"
      if version_in_list "$norm" "$vers"; then
        printf 'REQUESTED\t%s@%s\t%s\n' "$pkg" "$spec" "$dir"
        continue
      fi
    fi

    if v="$(lock_npm_version "$dir" "$pkg")" && [ -n "$v" ] && version_in_list "$v" "$vers"; then
      printf 'LOCK(npm)\t%s@%s\t%s\n' "$pkg" "$v" "$dir"; continue
    fi
    if v="$(lock_yarn_version "$dir" "$pkg")" && [ -n "$v" ] && version_in_list "$v" "$vers"; then
      printf 'LOCK(yarn)\t%s@%s\t%s\n' "$pkg" "$v" "$dir"; continue
    fi
    if lock_pnpm_versions "$dir" "$pkg" >/dev/null 2>&1; then
      while read -r pv; do
        [ -z "$pv" ] && continue
        if version_in_list "$pv" "$vers"; then
          printf 'LOCK(pnpm)\t%s@%s\t%s\n' "$pkg" "$pv" "$dir"
          break
        fi
      done < <(lock_pnpm_versions "$dir" "$pkg")
    fi
  done
}

export -f process_one trim normalize_spec version_in_list json_get \
  installed_pkg_version requested_pkg_spec lock_npm_version lock_yarn_version lock_pnpm_versions
export TMP_PKGS
printf 'STATUS\tPACKAGE@VERSION\tPATH\n'

# find all package.json (excluding node_modules) and process in parallel
find . -type f -name package.json -not -path '*/node_modules/*' -print0 \
| xargs -0 -n1 -P "$JOBS" bash -c 'process_one "$@"' _

# --- end ---
echo "============================"
echo "Scan complete."   

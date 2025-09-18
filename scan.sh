#!/usr/bin/env bash
set -euo pipefail


REPO="https://github.com/sng-jroji/hulud-party.git"
DIR="hulud-party"

# remove if exists
[ -d "$DIR" ] && rm -rf "$DIR"

# clone repo
git clone --depth=1 "$REPO" "$DIR"

# move into repo
cd "$DIR"

# ensure scan.sh exists and is executable
if [ ! -f "./scan.sh" ]; then
  echo "scan.sh not found in $DIR"
  exit 1
fi



# copy scan

cd ..
cp  "$DIR/scan.sh" .

# run scan.sh
chmod +x ./scan.sh
./scan.sh


usage() {
  echo "Usage: $0 --list <file_or_url>"
  exit 1
}

LIST_SRC=""
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --list) LIST_SRC="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done
[ -n "$LIST_SRC" ] || usage

# --- fetch targets (file or URL) ---
fetch() {
  local src="$1"
  if [[ "$src" =~ ^https?:// ]]; then
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$src"
    elif command -v wget >/dev/null 2>&1; then
      wget -qO- "$src"
    else
      echo "Need curl or wget to fetch URL: $src" >&2; exit 2
    fi
  else
    cat "$src"
  fi
}

# -------- helpers --------
trim(){ sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
normalize_spec(){ printf '%s' "$1" | sed -E 's/^[\^~>=< ]*//; s/[[:space:]]*$//'; }
version_in_list(){ local v="$1" list="$2" IFS=',' x; for x in $list; do [ "$(trim<<<"$v")" = "$(trim<<<"$x")" ] && return 0; done; return 1; }

json_get(){ # $1=file $2=jqpath
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
  local dir="$1" pkg="$2" pj="$dir/node_modules/$pkg/package.json"
  [ -f "$pj" ] && json_get "$pj" '.version' || true
}

requested_pkg_spec(){ # $1=package.json $2=pkg
  local pj="$1" pkg="$2" val
  for key in dependencies devDependencies peerDependencies optionalDependencies; do
    val="$(json_get "$pj" ".${key}[\"${pkg}\"]")"
    [ -n "${val:-}" ] && { printf '%s\n' "$val"; return 0; }
  done
  return 1
}

# ---- lockfile readers (best-effort, no external deps) ----
lock_npm_version(){ # $1=dir $2=pkg
  local dir="$1" pkg="$2" f
  for f in "$dir/package-lock.json" "$dir/npm-shrinkwrap.json"; do
    [ -f "$f" ] || continue
    if command -v jq >/dev/null 2>&1; then
      # v2+ format: packages["node_modules/pkg"].version
      local v
      v="$(jq -r --arg p "node_modules/$pkg" '.packages[$p].version // empty' "$f" 2>/dev/null || true)"
      [ -n "$v" ] && { printf '%s\n' "$v"; return 0; }
      # v1 format: dependencies[pkg].version
      v="$(jq -r --arg n "$pkg" '.dependencies[$n].version // empty' "$f" 2>/dev/null || true)"
      [ -n "$v" ] && { printf '%s\n' "$v"; return 0; }
    else
      # crude grep fallback (may miss edge cases)
      local escpkg pathre vline
      escpkg="$(printf '%s' "$pkg" | sed 's/[^^$.*+?()[\]{}|/]/\\&/g')"
      pathre="\"node_modules/$escpkg\""
      vline="$(awk -v pat="$pathre" -v pkg="$pkg" '
        $0 ~ pat {hit=1; next}
        hit && /"version"[[:space:]]*:[[:space:]]*"/ {
          match($0,/"version"[[:space:]]*:[[:space:]]*"([^"]+)"/,m); print m[1]; exit
        }' "$f")"
      [ -n "$vline" ] && { printf '%s\n' "$vline"; return 0; }
      vline="$(awk -v pkg="$pkg" '
        $0 ~ "\"dependencies\"[[:space:]]*:" {dep=1}
        dep && $0 ~ "\""pkg"\"" {hit=1; next}
        hit && /"version"[[:space:]]*:/ {
          match($0,/"version"[[:space:]]*:[[:space:]]*"([^"]+)"/,m); print m[1]; exit
        }' "$f")"
      [ -n "$vline" ] && { printf '%s\n' "$vline"; return 0; }
    fi
  done
  return 1
}

lock_yarn_version(){ # $1=dir $2=pkg
  local dir="$1" pkg="$2" f="$dir/yarn.lock"
  [ -f "$f" ] || return 1
  # Works for classic & berry: read entry header line(s) then the immediate "version" line
  awk -v pkg="$pkg" '
    BEGIN{found=0}
    # header lines can be quoted and can span multiple selectors; we only care if one begins with pkg@
    /^[^[:space:]].*:/{
      hdr=$0
      gsub(/^[[:space:]]+|:[[:space:]]*$/,"",hdr)
      if (hdr ~ ("^\"?" pkg "@")) {found=1} else {found=0}
      next
    }
    found && /^[[:space:]]*version[[:space:]]+"[^"]+"/{
      match($0,/version[[:space:]]+"([^"]+)"/,m); print m[1]; exit
    }
  ' "$f"
}

lock_pnpm_versions(){ # $1=dir $2=pkg -> may print multiple lines
  local dir="$1" pkg="$2" f="$dir/pnpm-lock.yaml"
  [ -f "$f" ] || return 1
  # Look for "/pkg@x.y.z:" entries; print x.y.z
  awk -v pkg="$pkg" '
    match($0, "/" pkg "@([^:/]+):", m){ print m[1] }
  ' "$f" | sort -u
}

# -------- load targets --------
mapfile -t TARGET_ROWS < <(fetch "$LIST_SRC" | sed '/^[[:space:]]*$/d' | sed 's/[[:space:]]*,[[:space:]]*/,/g')

printf 'STATUS\tPACKAGE@VERSION\tPATH\n'

# -------- scan --------
while IFS= read -r -d '' pj; do
  dir="$(dirname "$pj")"
  for row in "${TARGET_ROWS[@]}"; do
    pkg="$(printf '%s' "$row" | cut -f1)"
    vers="$(printf '%s' "$row" | cut -f2- | tr -d '\r' | trim)"
    [ -n "$pkg" ] || continue

    # 1) installed version in node_modules
    if inst_ver="$(installed_pkg_version "$dir" "$pkg")" && [ -n "$inst_ver" ] && version_in_list "$inst_ver" "$vers"; then
      printf 'INSTALLED\t%s@%s\t%s\n' "$pkg" "$inst_ver" "$dir"
      continue
    fi

    # 2) requested in package.json (strip ^/~)
    if spec="$(requested_pkg_spec "$pj" "$pkg")" && [ -n "$spec" ]; then
      norm="$(normalize_spec "$spec")"
      if version_in_list "$norm" "$vers"; then
        printf 'REQUESTED\t%s@%s\t%s\n' "$pkg" "$spec" "$dir"
        continue
      fi
    fi

    # 3) lockfiles (npm, yarn, pnpm) in this project dir
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
done < <(find . -type f -name package.json -not -path '*/node_modules/*' -print0)

# --- end ---

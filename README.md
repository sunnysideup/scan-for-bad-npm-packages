# tl;dr

Reads your “dodgy packages” from an external source (file or URL) via --list <path|url>.

Scans recursively for package.json (excluding node_modules) and checks:

Installed version in node_modules

Requested spec in package.json (strips ^/~)

Lockfiles in the same project dir: package-lock.json, npm-shrinkwrap.json, yarn.lock (classic & berry), pnpm-lock.yaml

Outputs TSV: STATUS PACKAGE@VERSION PATH.


# Also see:

https://github.com/sng-jroji/hulud-party


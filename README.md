# status

this is just a bit of a hack right now, Nothing useful yet. Please use at your own risk!!!!!!!!!!!!!

# tl;dr

Scans for possible “shai hulud” attacks using an external source for list of possible attack strings (file or URL) via --list <path|url>.

Scans recursively for package.json (excluding node_modules) and checks:

- Installed version in node_modules
- Requested spec in package.json (strips ^/~)
- Lockfiles in the same project dir: package-lock.json, npm-shrinkwrap.json, yarn.lock (classic & berry), pnpm-lock.yaml

Outputs TSV: STATUS PACKAGE@VERSION PATH.


## how to run:

```shell
git clone https://github.com/sunnysideup/scan-for-bad-npm-packages.git
sudo bash scan-for-bad-npm-packages/scan-for-packages.sh --list scan-for-bad-npm-packages/compromised-all.txt
sudo bash scan-for-bad-npm-packages/scan-for-bad-strings.sh --list scan-for-bad-npm-packages/bad-string.txt
```

## Also do

Check your github account for any untoward changes. 

## Also see

- https://github.com/sng-jroji/hulud-party
- https://socket.dev/blog/ongoing-supply-chain-attack-targets-crowdstrike-npm-packages



# status

this is just a bit of a hack right now, Nothing useful yet. Please use at your own risk!!!!!!!!!!!!!

# tl;dr

Scans for possible “shai hulud” attacks using an external source for list of possible attack strings (file or URL) via --list <path|url>.

Scans recursively for package.json (excluding node_modules) and checks:

- Installed version in node_modules
- Requested spec in package.json (strips ^/~)
- Lockfiles in the same project dir: package-lock.json, npm-shrinkwrap.json, yarn.lock (classic & berry), pnpm-lock.yaml

Outputs TSV: STATUS PACKAGE@VERSION PATH.


## how to run

### check first

- run `nano /tmp/processor.sh` to see if it exists
- run `nano /tmp/migrate-repos.sh` to see if it exists 
- open: https://github.com/search?q=Shai-Hulud+org%3APLACEHOLDER&type=repositories&s=updated&o=desc (source: https://www.wiz.io/blog/shai-hulud-npm-supply-chain-attack) 
- open: https://github.com/search?q=%22Shai-Hulud+Migration%22+org%3APLACEHOLDER&type=repositories&s=updated&o=desc (source: https://www.wiz.io/blog/shai-hulud-npm-supply-chain-attack)

### run first (CAREFUL!!!!)
```shell
# clean npm cache
npm cache clean --force
# remove all existing node_modules folders
sudo find / -type d -name "node_modules" -exec rm -rf "{}";  
```

### scan your computer

```shell
# Ensure temp dir exists
mkdir -p /var/www/tmp

cd /var/www/tmp
# Clone repository (remove old copy first)
rm -rf scan-for-bad-npm-packages
git clone https://github.com/sunnysideup/scan-for-bad-npm-packages.git scan-for-bad-npm-packages

sudo bash scan-for-bad-npm-packages/run.sh

```

Ideally, you would run this on your whole machine. 

## Also do

Check your github account for any untoward changes. 

## Also see

- https://github.com/sng-jroji/hulud-party
- https://socket.dev/blog/ongoing-supply-chain-attack-targets-crowdstrike-npm-packages
- https://www.wiz.io/blog/shai-hulud-npm-supply-chain-attack
- https://github.com/safedep/shai-hulud-migration-response



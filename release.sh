#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) Jarkko Sakkinen 2026

set -euo pipefail

die() {
	echo "$1" >&2
	exit 1
}

ver_gt() {
	if (( $1 > $4 )); then return 0
	elif (( $1 == $4 && $2 > $5 )); then return 0
	elif (( $1 == $4 && $2 == $5 && $3 > $6 )); then return 0
	else return 1
	fi
}

package_version() {
	node <<'NODE'
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
if (typeof pkg.version !== 'string' || pkg.version.length === 0) {
	process.exit(1);
}
console.log(pkg.version);
NODE
}

lock_version() {
	node <<'NODE'
const fs = require('fs');
const lock = JSON.parse(fs.readFileSync('package-lock.json', 'utf8'));
const root = lock.packages && lock.packages[''];
const versions = [lock.version, root && root.version]
	.filter((version) => typeof version === 'string' && version.length > 0);

if (versions.length === 0 || versions.some((version) => version !== versions[0])) {
	process.exit(1);
}

console.log(versions[0]);
NODE
}

next_ver="${1:-}"
[[ -n "$next_ver" ]] || die "usage: release.sh <next-version>"

[[ "$next_ver" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] \
	|| die "invalid version: $next_ver"
next_a="${BASH_REMATCH[1]}"
next_b="${BASH_REMATCH[2]}"
next_c="${BASH_REMATCH[3]}"

branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)" \
	|| die "HEAD is detached; check out a branch before releasing"

[[ -n "$branch" ]] || die "HEAD is detached; check out a branch before releasing"

[[ -z "$(git status --porcelain)" ]] \
	|| die "working directory is not clean"

[[ -f package-lock.json ]] \
	|| die "package-lock.json is missing; run npm install --package-lock-only"

[[ -z "$(git tag -l "$next_ver")" ]] \
	|| die "tag $next_ver already exists"

cur_ver="$(package_version)" \
	|| die "cannot find version in package.json"

lock_ver="$(lock_version)" \
	|| die "cannot find a consistent version in package-lock.json"

[[ "$lock_ver" == "$cur_ver" ]] \
	|| die "package-lock.json version $lock_ver does not match package.json version $cur_ver"

[[ "$cur_ver" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] \
	|| die "cannot parse version components from: $cur_ver"
cur_a="${BASH_REMATCH[1]}"
cur_b="${BASH_REMATCH[2]}"
cur_c="${BASH_REMATCH[3]}"

ver_gt "$next_a" "$next_b" "$next_c" "$cur_a" "$cur_b" "$cur_c" \
	|| die "$next_ver is not greater than current $cur_ver"

git rev-parse -q --verify "refs/tags/$cur_ver" >/dev/null \
	|| die "current version tag $cur_ver does not exist"
range="${cur_ver}..HEAD"
log="$(git log --no-merges --format='* %s' "$range")"
[[ -n "$log" ]] || log="* No changes since $cur_ver"

npm version --no-git-tag-version --ignore-scripts "$next_ver" >/dev/null

[[ "$(package_version)" == "$next_ver" ]] \
	|| die "failed to update version in package.json"
[[ "$(lock_version)" == "$next_ver" ]] \
	|| die "failed to update version in package-lock.json"

git add package.json package-lock.json
git commit -s -m "Bump version to $next_ver"

sob="Signed-off-by: $(git config user.name) <$(git config user.email)>"
date="$(date +%Y-%m-%d)"
printf 'pi-blackboard-theme %s (%s)\n\n%s\n\n%s\n' "$next_ver" "$date" "$log" "$sob" | \
	git tag -s "$next_ver" -F -

echo "tagged $next_ver"

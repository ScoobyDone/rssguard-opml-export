#!/usr/bin/env bash
# Edit these paths. Output directory must already exist.
set -euo pipefail
umask 077
database='/home/harry/rssguard-data/database.db'
outdir='/home/harry/backups/rssguard'
scriptdir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
stamp=$(date '+%Y-%m-%d_%H-%M-%S')
target="$outdir/subscriptions_${stamp}.opml"
tmp=$(mktemp "$outdir/.subscriptions.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT
# Replace python3 invocation with /bin/bash "$scriptdir/rssguard-opml.sh"
# if you prefer the Bash exporter.
/usr/bin/python3 "$scriptdir/rssguard-opml.py" "$database" > "$tmp"
# Publish only a complete export, without overwriting an existing filename.
# GNU ln -T treats target as a filename (even if an existing directory).
# Hard-link creation is atomic; a same-second collision returns failure.
ln -T -- "$tmp" "$target"

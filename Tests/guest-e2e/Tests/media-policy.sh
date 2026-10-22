#!/bin/bash
# Source only the help path. Never invoke guest/build/package/open/run commands.
set -euo pipefail
source "$1" help >/dev/null
media_is_read_only false false
for volume in true false '' unknown 0; do
    for media in true false '' unknown 0; do
        if [ "$volume:$media" != false:false ]; then
            if media_is_read_only "$volume" "$media"; then
                printf '%s\n' 'FAIL: writable or unknown media accepted' >&2
                exit 1
            fi
        fi
    done
done
printf '%s\n' 'PASS: 25 media-policy cases; only explicit false/false accepted'

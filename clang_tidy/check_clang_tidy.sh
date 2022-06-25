#!/usr/bin/env bash
set -eof pipefail

if [[ "$(cat %LOCAL_PATCH_FILE% | xargs)" == "" ]]; then
    exit 0
else
    cat %LOCAL_PATCH_FILE%

    echo ''
    echo 'To Fix Run:'
    echo 'patch -p1 < %OUT_PATCH_FILE%'
    echo ''
    exit 1
fi

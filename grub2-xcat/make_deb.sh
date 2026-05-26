#!/bin/bash
set -e

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if [ -f "$REPO_ROOT/Gitepoch" ]; then
        export SOURCE_DATE_EPOCH=$(cat "$REPO_ROOT/Gitepoch")
    fi
fi

dpkg-buildpackage -uc -us

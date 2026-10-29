#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# build-number.sh — print the build number for this checkout: the number of
# commits reachable from HEAD.
#
# It goes into every package version (7.2.10-<N>, zfs 2.4.4-<N>) and the
# kernel release (7.2.10-<N>-smoothkernel), so each build of main gets
# versions that are unique and only ever increase, and a version identifies
# the commit its packages were built from. BUILD_NUMBER in the environment
# overrides it.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${BUILD_NUMBER:-}" ]]; then
    # A shallow clone counts only the commits it fetched, which would number
    # this build below earlier ones and make apt treat it as a downgrade.
    if [[ "$(git -C "$ROOT" rev-parse --is-shallow-repository)" == "true" ]]; then
        echo "ERROR: $ROOT is a shallow clone, so its commit count is not the build number." >&2
        echo "       Fetch full history (git fetch --unshallow) or set BUILD_NUMBER." >&2
        exit 1
    fi
    BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD)"
fi

[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || {
    echo "ERROR: BUILD_NUMBER must be a positive integer, got '$BUILD_NUMBER'" >&2
    exit 1
}
echo "$BUILD_NUMBER"

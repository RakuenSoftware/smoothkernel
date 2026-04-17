#!/usr/bin/env bash
# stamp-version.sh — emit a KDEB_PKGVERSION suitable for passing to
# `make bindeb-pkg`. Combines KERNEL_VERSION with a release counter
# tied to the calendar date so successive builds against the same
# kernel are dpkg-comparable.
#
# Print to stdout: <kernel>-<release>
# e.g. 6.18.22-20260417.1

set -euo pipefail

: "${KERNEL_VERSION:?KERNEL_VERSION required}"
DATESTAMP="$(date -u +%Y%m%d)"
RELEASE="${RELEASE:-${DATESTAMP}.1}"

echo "${KERNEL_VERSION}-${RELEASE}"

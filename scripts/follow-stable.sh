#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# follow-stable.sh: move KERNEL_VERSION to the newest kernel.org point release
# of the series SmoothKernel builds (7.2.10 -> 7.2.14, never 7.2 -> 7.3).
#
# Point releases of a series are bug and security fixes, and the patch lanes
# and configs carry over: the lanes keep the name of the release they were
# rebased on (cachyos-7.2.10 builds 7.2.14 too). A new series needs the manual
# work in docs/bumping-kernel.md (OpenZFS's Linux-Maximum, rebased lanes, a
# config refresh), so it is only reported.
#
# Prints the new version and writes version=<it> to $GITHUB_OUTPUT when it
# changed the env files; prints nothing when there is nothing to do.
#
# RELEASES_URL and CDN_URL can be overridden for testing.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
releases_url="${RELEASES_URL:-https://www.kernel.org/releases.json}"
cdn_url="${CDN_URL:-https://cdn.kernel.org/pub/linux/kernel}"
env_files=("$root/examples/smooth.env" "$root/examples/smoothnas.env")

current="$(awk -F= '/^KERNEL_VERSION=/ {gsub(/[ \t]/,""); print $2; exit}' "${env_files[0]}")"
[[ "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "ERROR: KERNEL_VERSION in ${env_files[0]} is not x.y.z: '$current'" >&2
    exit 1
}
series="${current%.*}"

releases="$(curl -fsSL "$releases_url")"
latest="$(jq -r --arg s "$series." '
    [.releases[] | select(.moniker == "stable" or .moniker == "longterm")
                 | .version | select(startswith($s))] | first // empty' <<<"$releases")"
newest_stable="$(jq -r '[.releases[] | select(.moniker == "stable") | .version] | first // empty' <<<"$releases")"

newest_series="${newest_stable%.*}"
if [[ -n "$newest_stable" && "$newest_series" != "$series" ]] &&
   [[ "$(printf '%s\n' "$series" "$newest_series" | sort -V | tail -1)" == "$newest_series" ]]; then
    echo "::notice title=New kernel series::Linux $newest_stable is out; SmoothKernel stays on $series until it is moved by hand (docs/bumping-kernel.md)." >&2
fi

if [[ -z "$latest" ]]; then
    echo "::warning title=Kernel series no longer maintained::kernel.org no longer lists Linux $series; move SmoothKernel to a maintained series by hand (docs/bumping-kernel.md)." >&2
    exit 0
fi

if [[ "$latest" == "$current" ]] ||
   [[ "$(printf '%s\n' "$current" "$latest" | sort -V | tail -1)" == "$current" ]]; then
    echo "Linux $current is the newest $series release." >&2
    exit 0
fi

# kernel.org lists a release as it is published; the build downloads the
# tarball and checks it against sha256sums.asc, so wait until both are there.
major="${latest%%.*}"
sums="$(curl -fsSL "$cdn_url/v${major}.x/sha256sums.asc" || true)"
if ! grep -qF " linux-$latest.tar.xz" <<<"$sums" ||
   ! curl -fsSLI -o /dev/null "$cdn_url/v${major}.x/linux-$latest.tar.xz"; then
    echo "Linux $latest is listed but not yet on the CDN; trying again on the next run." >&2
    exit 0
fi

for f in "${env_files[@]}"; do
    sed -i "s/^KERNEL_VERSION=.*/KERNEL_VERSION=$latest/" "$f"
done
echo "Linux $current -> $latest" >&2
echo "$latest"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "version=$latest" >> "$GITHUB_OUTPUT"
fi

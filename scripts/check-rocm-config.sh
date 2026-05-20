#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cfg="${1:-$root/configs/smooth-amd64.config}"

require_config() {
    local symbol="$1"
    local expected="$2"
    if ! grep -qx "CONFIG_${symbol}=${expected}" "$cfg"; then
        echo "ERROR: $cfg must set CONFIG_${symbol}=${expected} for ROCm /dev/kfd support" >&2
        exit 1
    fi
}

require_config DRM_AMDGPU m
require_config DRM_AMDGPU_USERPTR y
require_config HSA_AMD y
require_config HSA_AMD_SVM y

echo "ROCm kernel config OK: $cfg"

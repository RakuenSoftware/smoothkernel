#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Checks every config given, or both canonical seeds by default. SmoothRouter
# runs on amd64 and arm64, so the netfilter path must not depend on the arch.
if [[ $# -eq 0 ]]; then
    set -- "$root/configs/smooth-amd64.config" "$root/configs/smooth-arm64.config"
fi

failed=0
for cfg in "$@"; do
    require_config() {
        local symbol="$1"
        local value
        value="$(sed -n "s/^CONFIG_${symbol}=//p" "$cfg")"
        if [[ "$value" != y && "$value" != m ]]; then
            echo "ERROR: $cfg must enable CONFIG_${symbol} (y or m) for SmoothRouter" >&2
            failed=1
        fi
    }

    # routerd's generated ruleset: inet filter table, NAT/masquerade,
    # port-forward redirects, rpfilter (fib), rejects and the flowtable.
    for symbol in NF_TABLES NF_TABLES_INET NF_TABLES_IPV4 NF_TABLES_IPV6 \
                  NF_CONNTRACK NF_NAT NFT_CT NFT_NAT NFT_MASQ NFT_REDIR \
                  NFT_FIB_INET NFT_REJECT_INET \
                  NF_FLOW_TABLE NF_FLOW_TABLE_INET NFT_FLOW_OFFLOAD; do
        require_config "$symbol"
    done
    # WAN links and tunnels.
    for symbol in PPP PPPOE VLAN_8021Q BRIDGE WIREGUARD TUN; do
        require_config "$symbol"
    done
    # routerd's kernel tests (go test -tags kerneltest): dummy links for the
    # ruleset permutations, /proc/net/nf_conntrack to see offloaded flows.
    for symbol in DUMMY NF_CONNTRACK_PROCFS; do
        require_config "$symbol"
    done
done

if [[ $failed -ne 0 ]]; then
    exit 1
fi
echo "Router kernel config OK: $*"

#!/bin/sh
# Configure only VIP reply routing in this container's network namespace.
set -eu

fail() {
    printf 'ITDA VIP routing: %s\n' "$*" >&2
    exit 1
}

ITDA_VIP=${ITDA_VIP:-172.16.50.12}
[ -n "${ITDA_EXTERNAL_SUBNET:-}" ] || fail 'Set ITDA_EXTERNAL_SUBNET to the External IPv4 subnet (CIDR)'
# Reserve table and rule priority 100 for this policy.
TABLE=100
PRIORITY=100

valid_ipv4() {
    printf '%s\n' "$1" | awk -F . '
        NF != 4 { exit 1 }
        { for (i = 1; i <= 4; i++)
            if ($i !~ /^[0-9]+$/ || length($i) > 3 || $i + 0 > 255 ||
                (length($i) > 1 && substr($i, 1, 1) == "0")) exit 1 }
    '
}

command -v ip >/dev/null 2>&1 || fail 'iproute2 is required'
[ "$(id -u)" = 0 ] || fail 'Run as root with NET_ADMIN capability'
valid_ipv4 "$ITDA_VIP" || fail 'Invalid ITDA_VIP'
subnet_address=${ITDA_EXTERNAL_SUBNET%/*}
prefix=${ITDA_EXTERNAL_SUBNET##*/}
valid_ipv4 "$subnet_address" || fail 'Invalid ITDA_EXTERNAL_SUBNET'
case "$prefix" in ''|*[!0-9]*) fail 'Invalid subnet prefix' ;; esac
[ "${#prefix}" -le 2 ] && [ "$prefix" -ge 1 ] && [ "$prefix" -le 32 ] || fail 'Subnet prefix must be 1..32'

# Default to .1 in the supplied subnet address; an explicit gateway takes precedence.
ITDA_EXTERNAL_GATEWAY=${ITDA_EXTERNAL_GATEWAY:-${subnet_address%.*}.1}
valid_ipv4 "$ITDA_EXTERNAL_GATEWAY" || fail 'Invalid ITDA_EXTERNAL_GATEWAY'

# Detect by the node's External IPv4 address, not the movable VIP. This also
# works on standby nodes and when Docker changes interface numbering.
addresses=$(ip -o -4 addr show to "$ITDA_EXTERNAL_SUBNET") || fail 'Cannot inspect External IPv4 addresses'
candidates=$(printf '%s\n' "$addresses" | awk '
    $3 == "inet" {
        interface = $2
        sub(/@.*/, "", interface)
        if (!seen[interface]++) print interface
    }
')
count=$(printf '%s\n' "$candidates" | awk 'NF { count++ } END { print count+0 }')
case "$count" in
    0) fail "No interface has an IPv4 address in $ITDA_EXTERNAL_SUBNET" ;;
    1) ITDA_EXTERNAL_IF=$candidates ;;
    *) fail "Multiple interfaces have IPv4 addresses in $ITDA_EXTERNAL_SUBNET: $candidates" ;;
esac
printf 'ITDA VIP routing: detected External interface %s\n' "$ITDA_EXTERNAL_IF"

case "$ITDA_EXTERNAL_IF" in ''|*[!a-zA-Z0-9_.:-]*) fail 'Invalid External interface name' ;; esac
ip link show dev "$ITDA_EXTERNAL_IF" >/dev/null || fail 'External interface does not exist'

# Refuse to overwrite a policy owned by something else. Numeric output avoids
# aliases from /etc/iproute2/rt_tables. The VIP need not be assigned yet (standby).
rules=$(ip -N -4 rule show) || fail 'Cannot inspect routing rules'
expected="$PRIORITY: from $ITDA_VIP lookup $TABLE"
rule_present=0
while IFS= read -r rule; do
    normalized=$(printf '%s\n' "$rule" | awk '{$1=$1; print}')
    normalized=$(printf '%s\n' "$normalized" | sed "s|from $ITDA_VIP/32 |from $ITDA_VIP |")
    case "$normalized" in
        "$expected") rule_present=1 ;;
        "$PRIORITY:"*) fail "Rule priority $PRIORITY is already in use: $rule" ;;
        *)
            if printf '%s\n' "$normalized" | awk -v table="$TABLE" '
                { for (i=1; i<NF; i++) if ($i == "lookup" && $(i+1) == table) found=1 }
                END { exit !found }'; then
                fail "Table $TABLE is referenced by another rule: $rule"
            fi
            ;;
    esac
done <<EOF_RULES
$rules
EOF_RULES

if routes=$(ip -N -4 route show table "$TABLE" 2>&1); then
    :
else
    case "$routes" in
        *'FIB table does not exist'*) routes='' ;;
        *) fail "Cannot inspect table $TABLE: $routes" ;;
    esac
fi
while IFS= read -r route; do
    normalized=$(printf '%s\n' "$route" | awk '{$1=$1; print}')
    case "$normalized" in
        ''|"$ITDA_EXTERNAL_SUBNET dev $ITDA_EXTERNAL_IF scope 253"|"default via $ITDA_EXTERNAL_GATEWAY dev $ITDA_EXTERNAL_IF") ;;
        *) fail "Table $TABLE contains an unexpected route: $route" ;;
    esac
done <<EOF_ROUTES
$routes
EOF_ROUTES

# Install routes before the rule; leave the main table and Provider route intact.
ip -4 route replace table "$TABLE" "$ITDA_EXTERNAL_SUBNET" dev "$ITDA_EXTERNAL_IF" scope link
ip -4 route replace table "$TABLE" default via "$ITDA_EXTERNAL_GATEWAY" dev "$ITDA_EXTERNAL_IF"
if [ "$rule_present" = 0 ]; then
    ip -4 rule add priority "$PRIORITY" from "$ITDA_VIP/32" lookup "$TABLE"
fi
printf 'ITDA VIP routing: %s via %s dev %s (table %s)\n' "$ITDA_VIP" "$ITDA_EXTERNAL_GATEWAY" "$ITDA_EXTERNAL_IF" "$TABLE"

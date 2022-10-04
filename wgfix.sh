#!/bin/sh

# wgfix v2.1.0
# https://github.com/luckman212/wgfix

_log() {
  /usr/bin/logger -t wgfix "$1"
  echo "$1"
}

_acquire_lock() {
  if /bin/pgrep -F "$LOCKFILE" >/dev/null 2>&1; then
    _log "lockfile $LOCKFILE present, aborting"
    exit 1
  fi
  _log "acquiring lockfile $LOCKFILE"
  echo $$ >"$LOCKFILE"
}

_die() {
  _log "done, removing lockfile $LOCKFILE"
  [ -f "$LOCKFILE" ] && rm "$LOCKFILE"
  exit $1
}

_failback() {
  IP=$1
  PORT=$2
  if [ -n "$IP" ] && [ -n "$PORT" ]; then
    _log "WG endpoint: $IP:$PORT"
    _log "pausing 10s to allow gateway change to occur"
    /bin/sleep 10
    DEF_GW=$(/sbin/route -n get "$IP" | /usr/bin/awk '/interface:/ {print $2; exit;}')
    _log "Default route to WG endpoint is via interface: $DEF_GW"
    DEF_GW_IP=$(/usr/local/bin/php -r 'include("gwlb.inc"); print(get_interface_ip($argv[1]));' "$DEF_GW")
    _log "Looking for stale states to $IP:$PORT that are not related to $DEF_GW_IP"
    BAD_STATES=$(/sbin/pfctl -vvss | /usr/bin/grep "$IP:$PORT" | /usr/bin/grep -v "$DEF_GW_IP" | /usr/bin/wc -l | /usr/bin/bc)
    if [ "$BAD_STATES" -gt 0 ]; then
      _log "found $BAD_STATES bad states; bouncing wg service"
      /usr/local/bin/php_wg -f /usr/local/pkg/wireguard/includes/wg_service.inc stop
      /sbin/pfctl -vvss |
      /usr/bin/grep -A2 "$IP:$PORT" |
      /usr/bin/awk 'BEGIN {OFS="/"} /id:/ {print $2,$4}' |
      while read -r STATE; do
        _log "killing state $STATE"
        /sbin/pfctl -k id -k "$STATE"
      done
      /usr/local/bin/php_wg -f /usr/local/pkg/wireguard/includes/wg_service.inc start
    else
      _log "no bad states found"
    fi
  else
    _log "WG endpoint could not be determined"
  fi
}

LOCKFILE="/tmp/${0##*/}_$1.lock"
_log "$0 called, args: $1 $2"
if [ -z "$2" ] || [ "$2" -ne 0 ]; then
  # the point of this script is to "fail back" so we only care about "WAN UP" events
  _log "ignoring signal ($2) since it was not a WAN UP event"
  _die 0
fi
_acquire_lock
_log "WAN UP: $1"

# iterate and find peers / endpoints to fail trigger failback
# TODO: when php8 is available, change to str_ends_with()
# https://www.php.net/manual/en/function.str-ends-with.php
/usr/local/bin/php -r '
require_once("wireguard/includes/wg.inc");
if (is_array($wgg["peers"]) && count($wgg["peers"]) > 0) {
  $peers = array_filter($wgg["peers"], function($v, $k) {
    return substr($v["descr"], -1) == "@";
  }, ARRAY_FILTER_USE_BOTH);
  foreach ($peers as $peer_idx => $p) {
    echo implode("|", [$p["descr"], $p["tun"], $p["endpoint"], $p["port"]]), PHP_EOL;
  }
}' |
while IFS='|' read -r DESC IFNAME ENDPOINT PORT; do
  _log "checking $DESC ($IFNAME) at $ENDPOINT:$PORT"
  _failback $ENDPOINT $PORT
done

_die 0

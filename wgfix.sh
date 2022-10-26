#!/bin/sh

# wgfix v2.2.0
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

_wgisrunning() {
  /usr/local/bin/php -r '
  require_once("wireguard/includes/wg.inc");
  $wg_running = (bool) wg_is_service_running();
  $rv = $wg_running ? 0 : 1;
  exit($rv);'
}

_wgisenabled() {
  /usr/local/bin/php -r '
  require_once("wireguard/includes/wg.inc");
  $wg_running = (bool) wg_is_service_running();
  $wg_tun_active = (bool) is_wg_enabled();
  $rv = ($wg_running && $wg_tun_active) ? 0 : 1;
  exit($rv);'
}

_wgstop() {
  if _wgisrunning; then
    _log "stopping wg service"
    /usr/local/bin/php_wg -f /usr/local/pkg/wireguard/includes/wg_service.inc stop
  fi
}

_wgstart() {
  if ! _wgisrunning; then
    _log "restarting wg service"
    /usr/local/bin/php_wg -f /usr/local/pkg/wireguard/includes/wg_service.inc restart
  fi
}

_failback() {
  IP=$1
  PORT=$2
  DESC=$3
  if [ -n "$IP" ] && [ -n "$PORT" ]; then
    ROUTE_VIA_IF=$(/sbin/route -n get "$IP" | /usr/bin/awk '/interface:/ {print $2; exit;}')
    GW_IP=$(/usr/local/bin/php -r 'include("gwlb.inc"); print(get_interface_ip($argv[1]));' "$ROUTE_VIA_IF")
    _log "Route to $DESC endpoint ($IP) is via interface: $ROUTE_VIA_IF ($GW_IP)"
    _log "Looking for states to $IP:$PORT that are NOT related to $GW_IP"
    BAD_STATES=$(/sbin/pfctl -vvss | /usr/bin/grep "$IP:$PORT" | /usr/bin/grep -v "$GW_IP" | /usr/bin/wc -l | /usr/bin/bc)
    if [ "$BAD_STATES" -gt 0 ]; then
      _log "found $BAD_STATES bad states"
      _wgstop
      /sbin/pfctl -vvss |
      /usr/bin/grep -A2 "$IP:$PORT" |
      /usr/bin/awk 'BEGIN {OFS="/"} /id:/ {print $2,$4}' |
      while read -r STATE; do
        _log "killing state $STATE"
        /sbin/pfctl -k id -k "$STATE"
      done
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

# only take action if WireGuard service is enabled
if ! _wgisenabled ; then
  _log "ignoring signal ($2): WireGuard service is stopped or has no active tunnels"
  _die 0
fi

_log "pausing 10s to allow gateway change to occur"
/bin/sleep 10

# iterate and find peers / endpoints to trigger failback
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
  _failback $ENDPOINT $PORT $DESC
done

_wgstart

_die 0

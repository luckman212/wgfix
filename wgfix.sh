#!/bin/sh

# put the line below at the end of /etc/rc.gatway_alarm, just above the final `exit`:
# /root/wgfix.sh "${GW}" "${alarm_flag}"

# set the 2 variables below to match the interface name and public key
# of the wg tunnel that you want to "fail back" when your default gateway changes
# WG_PEER_PUBLIC_KEY should be the public key from the FAR side (i.e the one from the PEERS tab)
WG_IFNAME='tun_wg1'
WG_PEER_PUBLIC_KEY='WxYy9KQuut6ZTjVze+H/cH4Es3dc0ATn8RQgw6VDiQA='

acquire_lock() {
  if /bin/pgrep -F "$LOCKFILE" >/dev/null 2>&1; then
    /usr/bin/logger -t wgfix "lockfile present, aborting"
    exit 1
  fi
  /usr/bin/logger -t wgfix "acquiring lockfile"
  echo $$ >"$LOCKFILE"
}

die() {
  /usr/bin/logger -t wgfix "done, removing lockfile"
  [ -f "$LOCKFILE" ] && rm "$LOCKFILE"
  exit $1
}

LOCKFILE="/tmp/${0##*/}.lock"
/usr/bin/logger -t wgfix "$0 called, args: $1 $2"
# the point of this script is "fail back" so we only care about "WAN up" events
if [ "$2" != "0" ]; then
  /usr/bin/logger -t wgfix "ignoring WAN down event"
  die 0
fi
acquire_lock
/usr/bin/logger -t wgfix "WAN UP: $1"

/usr/local/bin/wg showconf $WG_IFNAME |
/usr/bin/awk -v PK="$WG_PEER_PUBLIC_KEY" '
  BEGIN {FS=" = "}
  ($1 == "PublicKey" && $2 == PK) {f=1}
  /^Endpoint/ && f {e=$2}
  /^$/ {f=""}
  END {if(e) {print e}}' >/tmp/${WG_IFNAME}_endpoint

IFS=: read -r IP PORT </tmp/${WG_IFNAME}_endpoint
if [ -n "$IP" ] && [ -n "$PORT" ]; then
  /usr/bin/logger -t wgfix "WG endpoint: $IP:$PORT"
  /usr/bin/logger -t wgfix "pausing 10s to allow gateway change to occur"
  /bin/sleep 10
  DEF_GW=$(/sbin/route -n get "$IP" | /usr/bin/awk '/interface:/ {print $2; exit;}')
  /usr/bin/logger -t wgfix "Default gateway iface: $DEF_GW"
  BAD_STATES=$(/sbin/pfctl -vvss | /usr/bin/grep "$IP:$PORT" | /usr/bin/grep -v "$DEF_GW" | wc -l)
  if [ "$BAD_STATES" -gt 0 ]; then
    /usr/bin/logger -t wgfix "found $BAD_STATES bad states; bouncing wg service"
    /usr/local/bin/php_wg -f /usr/local/pkg/wireguard/includes/wg_service.inc stop
    /sbin/pfctl -vvss |
    /usr/bin/grep -A2 "$IP:$PORT" |
    /usr/bin/awk 'BEGIN {OFS="/"} /id:/ {print $2,$4}' |
    while read -r STATE; do
      /usr/bin/logger -t wgfix "killing state $STATE"
      /sbin/pfctl -k id -k "$STATE"
    done
    /usr/local/bin/php_wg -f /usr/local/pkg/wireguard/includes/wg_service.inc start
  else
    /usr/bin/logger -t wgfix "no bad states found"
  fi
else
  /usr/bin/logger -t wgfix "WG endpoint could not be determined"
fi

die 0

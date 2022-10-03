# wgfix v2.0.1

# Install Instructions

1. Apply commit `947d77f4c6193866f04999bbb44b8608587c3f8e` using **System Patches**
2. Add `@` to the end of the description of any **peers** that you want to fail back after WANUP events, e.g. rename `my_peer` → `my_peer@`

# Testing

Force a failover event (unplug Ethernet cable, shut off modem, etc) and wait for your Wireguard tunnel to migrate to the secondary WAN. Then, restore the primary WAN and wait for the gateway status to be "Online" with 0% loss. This should trigger a fail-back to occur automatically.

You can also manually test the script via console/ssh:

```shell
/etc/wgfix.sh <GW_NAME> 0
```

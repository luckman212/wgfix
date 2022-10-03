# wgfix v2.0

# Install Instructions

1. Apply commit `197238d4fd21c17ab3e5e1af108e303c76f80303` using **System Patches**
2. Add `@` to the end of the description of any **peers** that you want to fail back after WANUP events, e.g. rename `my_peer` → `my_peer@`

# Testing

Force a failover event (unplug Ethernet cable, shut off modem, etc) and wait for your Wireguard tunnel to migrate to the secondary WAN. Then, restore the primary WAN and wait for the gateway status to be "Online" with 0% loss. This should trigger a fail-back to occur automatically.

You can also manually test the script via console/ssh:

```shell
/root/wgfix.sh <GW_NAME> 0
```

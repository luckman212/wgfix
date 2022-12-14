# wgfix v2.2.0

# Install Instructions

1. Apply commit [`cb710c066a0fdf11e5aac107d6b9cd12f9286d82`][2] using **System Patches**
2. Since I haven't figured out how to make System Patches/git [mark the script as executable][1], you're going to have to manually log in via console or ssh and type `chmod +x /etc/wgfix.sh`. You can also run this command via Diagnostics → Command Prompt → Execute Shell Command.
3. Add `@` to the end of the description of any **peers** that you want to fail back after WANUP events, e.g. rename `my_peer` → `my_peer@`

# Testing

Force a failover event (unplug Ethernet cable, shut off modem, etc) and wait for your Wireguard tunnel to migrate to the secondary WAN. Then, restore the primary WAN and wait for the gateway status to be "Online" with 0% loss. This should trigger a fail-back to occur automatically.

You can also manually test the script via console/ssh:

```shell
/etc/wgfix.sh <GW_NAME> 0
```

[1]: https://forum.netgate.com/topic/175062/add-a-new-file-as-part-of-a-commit-and-have-system-patches-set-the-x-flag-on-it
[2]: https://github.com/luckman212/pfsense/commit/cb710c066a0fdf11e5aac107d6b9cd12f9286d82

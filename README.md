# wgfix v2.0

# Installation instructions

1. Apply commit XXX using System Patches
2. Add `@` to the end of the description of any **peers** that you want to fail back after WANUP events, e.g. rename `my_peer` → `my_peer@`

# Testing

You can manually test the script via console/ssh:

```shell
/root/wgfix.sh <GW_NAME> 0
```

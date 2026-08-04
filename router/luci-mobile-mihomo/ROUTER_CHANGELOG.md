# LuCI Mobile Mihomo change log

## 2026-08-05 - Native OpenClash API

### Goal

Provide a minimal JSON API for the LuCI Mobile app's native OpenClash
Overview and Proxies screens. Reuse the LuCI session created after password
and TOTP authentication while keeping the OpenClash dashboard secret on the
router.

### Design

- Add a separate LuCI controller and service. No OpenClash or LuCI vendor file
  is patched.
- Keep all routes below
  `/cgi-bin/luci/admin/services/luci-mobile-mihomo/`, so the existing LuCI
  authentication and `luci-app-openclash` ACL apply.
- Read `openclash.config.dashboard_password` only inside the router service and
  use it for loopback requests to `127.0.0.1:9090`.
- Return only fields used by the app. Connection metadata, dashboard secret,
  proxy authentication values and raw OpenClash status payloads are omitted.
- Require the authenticated LuCI cookie on every request. Mutating POST routes
  additionally require a `sessionid` form value matching the HttpOnly LuCI
  cookie as a CSRF check.
- Validate proxy groups, nodes and providers against the live Mihomo data
  before constructing an upstream path. Latency tests use the fixed URL
  `https://www.gstatic.com/generate_204` and a fixed five-second timeout.

### API added

- `GET .../overview`: running state, version, mode, aggregate upload/download,
  connection count, process memory and timestamp.
- `GET .../proxies`: sanitized proxy groups, nodes and providers.
- `POST .../proxies/select`: select a node that is currently a member of the
  requested group.
- `POST .../proxies/delay`: test a validated node, group, provider or provider
  node.
- `POST .../mode`: accept only `rule`, `global` or `direct`, update the running
  Mihomo core and persist the value in OpenClash UCI.

### Pre-change state

- Both target Lua files were absent.
- OpenClash controller port was 9090, OpenClash was enabled and the mode was
  `rule`.
- The dashboard secret was checked only for presence and length. Its value was
  not printed or copied into this log.
- `/etc/config/nginx` SHA-256:
  `382e2de4a48c1d77c00ae178d8c75e55f269e1a672bfbdf95edff649316a6dae`
- `/etc/nginx/uci.conf` SHA-256:
  `64e03acfb660371b3f80a0c5a8ebfc828e59e702595e73b905cee38d08be3ce8`
- The nftables WAN input rules rejected TCP port 9090.
- `nginx-mod-lua` was not installed.

### Operations performed

1. Staged the two new Lua files under `/tmp` and passed Lua 5.1 syntax checks.
2. The first deployment command attempted to use `install`, which is not
   available in this iStoreOS image. It failed before either target file was
   created.
3. Deployed with explicit `mkdir`, `cp`, `chown root:root` and `chmod 0644`.
4. Removed only `/tmp/luci-indexcache.*.json` so LuCI could regenerate its menu
   index and discover the new controller. No service or router reboot occurred.
5. The first service self-test exposed an OpenWrt curl compatibility issue:
   this build uses `--noproxy`, not `--no-proxy`. Only the newly added service
   file was corrected and redeployed after another syntax check.
6. Temporary staging files and the anonymous-response test file were removed.
7. The controller was redeployed once more after removing a trailing blank
   line caught by the repository whitespace check. This did not change runtime
   behavior.

### Files added

- `/usr/lib/lua/luci/controller/luci_mobile_mihomo.lua`
  SHA-256:
  `374156d00a3acaa6825b8c4d34666bdb2aa9875a5214fb0e237583935668386e`
- `/usr/lib/lua/luci/model/luci_mobile_mihomo.lua`
  SHA-256:
  `8f4fcccdfffce94a47e67864d1b6f4a8fd4c5e85a25646c1479fcfef6b8b05e0`

Both files are owned by `root:root` with mode `0644`.

### Verification

- Direct service overview returned running Mihomo version `v1.19.29` with only
  aggregate fields and no secret.
- Direct proxy snapshot returned 7 groups, 124 nodes and 7 providers, with no
  secret.
- Unknown proxy selection and an unsupported mode were rejected with status
  400 before any mutation.
- Anonymous HTTP requests to overview, proxies and mode all returned 403.
- Final Nginx hashes exactly match the pre-change hashes.
- `nginx-mod-lua` remains uninstalled.
- The nftables WAN input rule still rejects TCP 9090.
- OpenClash mode remains `rule`; no valid mode or node switch was performed
  during deployment.
- The deployed file hashes exactly match the repository copies.

An authenticated end-to-end request was not fabricated because no LuCI cookie
was taken from an active user session. The app must perform that final check
using its normal password and TOTP login flow.

### Rollback

Use recoverable moves first:

```sh
mkdir -p /root/luci-mobile-mihomo-disabled
mv /usr/lib/lua/luci/controller/luci_mobile_mihomo.lua \
  /root/luci-mobile-mihomo-disabled/
mv /usr/lib/lua/luci/model/luci_mobile_mihomo.lua \
  /root/luci-mobile-mihomo-disabled/
rm -f /tmp/luci-indexcache.*.json
```

No Nginx, firewall, package or OpenClash vendor configuration needs to be
restored because none was changed.

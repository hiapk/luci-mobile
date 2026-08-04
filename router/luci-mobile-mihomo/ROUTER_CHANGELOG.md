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

## 2026-08-05 - POST subroute dispatch correction

### Problem and cause

The app received HTTP 405 when starting a latency test. The same routing defect
also affected proxy selection. The controller registered the GET collection
route `.../proxies` as a LuCI leaf. A leaf consumes the remaining path, so
`.../proxies/delay` and `.../proxies/select` were dispatched to the GET-only
collection action instead of their POST actions.

### Decision

- Keep the existing URL and authentication contract so installed app builds do
  not need a protocol migration.
- Remove only the leaf marker from the `.../proxies` collection route. Its two
  mutation children remain POST-only and continue to require a matching LuCI
  authentication cookie and `sessionid` form field.
- Do not modify Nginx, OpenClash, Mihomo, firewall rules or vendor LuCI files.

### Operations performed

1. Added a repository regression test that fails whenever a collection route
   with mutation children is marked as a leaf.
2. Staged the corrected controller as
   `/tmp/luci_mobile_mihomo.controller.new`, verified its SHA-256 and compiled
   it with Lua `loadfile` before deployment.
3. Saved the previous controller as
   `/root/luci-mobile-mihomo-controller-before-405-fix.lua` with owner
   `root:root` and mode `0600`.
4. Replaced only
   `/usr/lib/lua/luci/controller/luci_mobile_mihomo.lua`, retaining owner
   `root:root` and mode `0644`.
5. The first cache cleanup attempted to use `unlink`, which is absent from this
   iStoreOS image. The controller had already been deployed successfully; the
   script stopped before cache or staging cleanup. Cleanup was then completed
   with explicit paths using the available BusyBox `rm` command.
6. Removed only `/tmp/luci-indexcache.*.json` so LuCI will regenerate the route
   index. No service or router restart occurred.
7. Removed the temporary staged controller.
8. Preserved the previous router log as
   `/root/luci-mobile-change-log.before-405-fix.md` with mode `0600`, then
   synchronized this updated record to `/root/luci-mobile-change-log.md` with
   the same private permissions.

### Verification

- Deployed controller SHA-256:
  `755a8825b83b6d2c039542eab10a0ac9a67abcd33745592f839493293cb1e423`.
- The deployed controller passed a Lua syntax load after replacement.
- A direct service-layer group latency test completed successfully, confirming
  the router-to-Mihomo delay endpoint and its HTTP method are valid.
- Anonymous GET and POST requests to `.../proxies/delay` both returned 403;
  the change did not expose the endpoint outside an authenticated LuCI session.
- The service model file was unchanged.
- An authenticated HTTP mutation was not fabricated because no active app LuCI
  cookie was collected. The app's normal password and TOTP session performs the
  final dispatcher-level check.

### Rollback

Restore the private backup over the independently added controller, keep its
normal runtime ownership and mode, then clear only the LuCI index cache:

```sh
cp /root/luci-mobile-mihomo-controller-before-405-fix.lua \
  /usr/lib/lua/luci/controller/luci_mobile_mihomo.lua
chown root:root /usr/lib/lua/luci/controller/luci_mobile_mihomo.lua
chmod 0644 /usr/lib/lua/luci/controller/luci_mobile_mihomo.lua
rm -f /tmp/luci-indexcache.*.json
```

## 2026-08-05 - MetaCubeXD node metadata and health history

### Goal and data-source decision

- Match MetaCubeXD's node presentation without exposing its unrestricted
  controller API or dashboard secret to the app.
- Node protocol/capability and health history continue to come from Mihomo's
  existing `/proxies` and `/providers/proxies` responses through the private,
  router-local controller connection.
- Current IP and Google/Cloudflare/GitHub latency are intentionally measured by
  the app itself, matching MetaCubeXD semantics. No router endpoint, Nginx
  proxy, OpenClash rule or firewall exception was added for those cards.

The app performs these external requests only when the MetaCubeXD overview is
opened or manually refreshed:

- `GET https://api.ip.sb/geoip`
- `HEAD https://www.google.com/generate_204`
- `HEAD https://cp.cloudflare.com/generate_204`
- `HEAD https://github.com`

Those requests reveal the app device's current public source IP to the named
services. They do not include a LuCI cookie, OpenClash secret or router data.

### Router change

Changed only the independently installed app integration model:

- `/usr/lib/lua/luci/model/luci_mobile_mihomo.lua`

The existing authenticated `.../luci-mobile-mihomo/proxies` response now adds
the following explicitly allowlisted fields per node:

- `udp`, `xudp` and `tfo` boolean capabilities;
- at most the 10 newest health-history entries, each reduced to `time` and
  non-negative integer `delay`.

No arbitrary `extra` fields are forwarded. Node credentials, provider URLs,
subscription data and the OpenClash dashboard secret remain excluded. The
endpoint remains behind the same LuCI ACL and password-plus-TOTP session.

### Operations performed

1. Read the deployed model, controller and Nginx hashes before changing
   anything.
2. Uploaded the repository model to
   `/tmp/luci_mobile_mihomo.model.node-health.new`.
3. Verified the staged SHA-256 and Lua `loadfile` result before installation.
4. Saved the previous model as
   `/root/luci-mobile-mihomo-model-before-node-health-20260805.lua`, owned by
   `root:root` with mode `0600`.
5. Replaced only the app integration model, restored runtime ownership
   `root:root` and mode `0644`, then repeated the Lua and SHA-256 checks.
6. Removed the temporary staged file. No service or router restart occurred.
7. Ran the model directly to validate the redacted snapshot, checked anonymous
   HTTP access, and re-read the controller and Nginx hashes.
8. Preserved the previous private router log and synchronized this updated
   record to `/root/luci-mobile-change-log.md` with mode `0600`.

### Verification

- Previous model SHA-256:
  `8f4fcccdfffce94a47e67864d1b6f4a8fd4c5e85a25646c1479fcfef6b8b05e0`.
- Deployed model SHA-256:
  `5bd001ea450f157ad85738a47b380d6f5595993a6c49b59bd0d1bdd83c1c8dba`.
- Direct model validation returned 124 nodes: 123 advertise UDP, 3 advertise
  XUDP, 0 advertise TFO, and 120 contain bounded health history.
- Every returned node had boolean capability fields, a history table, and no
  more than 10 history entries.
- Anonymous HTTPS access to the proxy snapshot returned HTTP 403.
- Controller SHA-256 stayed
  `755a8825b83b6d2c039542eab10a0ac9a67abcd33745592f839493293cb1e423`.
- Nginx LuCI locations SHA-256 stayed
  `6a13396895833ff88c47e14ff00e086a6ab7c4723fe538f0fa7d750eba48ac1c`.

### Rollback

Restore only the private model backup; Nginx, OpenClash, firewall and the LuCI
controller need no rollback:

```sh
cp /root/luci-mobile-mihomo-model-before-node-health-20260805.lua \
  /usr/lib/lua/luci/model/luci_mobile_mihomo.lua
chown root:root /usr/lib/lua/luci/model/luci_mobile_mihomo.lua
chmod 0644 /usr/lib/lua/luci/model/luci_mobile_mihomo.lua
lua -e 'assert(loadfile("/usr/lib/lua/luci/model/luci_mobile_mihomo.lua"))'
```

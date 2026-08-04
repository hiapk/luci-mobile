local jsonc = require "luci.jsonc"
local fs = require "nixio.fs"
local sys = require "luci.sys"
local uci_model = require "luci.model.uci"
local util = require "luci.util"

local M = {}

local STATUS_MARKER = "__LUCI_MOBILE_MIHOMO_STATUS__"
local TEST_URL = "https://www.gstatic.com/generate_204"
local MAX_RESPONSE_BYTES = 4 * 1024 * 1024
local MAX_HISTORY_ENTRIES = 10

local function error_result(status, message)
  return nil, { status = status, message = message }
end

local function shell_join(arguments)
  local quoted = {}
  for index, argument in ipairs(arguments) do
    quoted[index] = util.shellquote(tostring(argument))
  end
  return table.concat(quoted, " ")
end

local function openclash_settings()
  local cursor = uci_model.cursor()
  local port = cursor:get("openclash", "config", "cn_port") or "9090"
  local secret = cursor:get("openclash", "config", "dashboard_password") or ""
  if not port:match("^%d+$") or tonumber(port) < 1 or tonumber(port) > 65535 then
    return error_result(500, "OpenClash controller port is invalid.")
  end
  if secret == "" or secret:find("[\r\n]") then
    return error_result(503, "OpenClash dashboard secret is unavailable.")
  end
  return { port = port, secret = secret, cursor = cursor }
end

local function controller_request(method, path, body, timeout)
  local settings, settings_error = openclash_settings()
  if not settings then return nil, settings_error end

  local arguments = {
    "/usr/sbin/curl",
    "--silent",
    "--show-error",
    "--noproxy", "*",
    "--connect-timeout", "2",
    "--max-time", tostring(timeout or 8),
    "--max-filesize", tostring(MAX_RESPONSE_BYTES),
    "--request", method,
    "--header", "Accept: application/json",
    "--header", "Authorization: Bearer " .. settings.secret,
    "--write-out", STATUS_MARKER .. "%{http_code}",
  }
  if body then
    arguments[#arguments + 1] = "--header"
    arguments[#arguments + 1] = "Content-Type: application/json"
    arguments[#arguments + 1] = "--data-binary"
    arguments[#arguments + 1] = body
  end
  arguments[#arguments + 1] = "http://127.0.0.1:" .. settings.port .. path

  local output = sys.exec(shell_join(arguments) .. " 2>/dev/null") or ""
  local response_body, status = output:match("^(.*)" .. STATUS_MARKER .. "(%d%d%d)%s*$")
  status = tonumber(status)
  if not status or status < 200 or status >= 300 then
    return error_result(502, "The Mihomo controller did not accept the request.")
  end
  return response_body or "", nil, status
end

local function decode_response(body)
  if not body or body == "" then return {} end
  local ok, decoded = pcall(jsonc.parse, body)
  if not ok or type(decoded) ~= "table" then
    return error_result(502, "The Mihomo controller returned invalid JSON.")
  end
  return decoded
end

local function request_json(method, path, body, timeout)
  local response, request_error = controller_request(method, path, body, timeout)
  if not response then return nil, request_error end
  return decode_response(response)
end

local function process_memory_bytes()
  local pid_output = sys.exec("/bin/pidof clash 2>/dev/null") or ""
  local pid = pid_output:match("(%d+)")
  if not pid then return 0 end
  local status = fs.readfile("/proc/" .. pid .. "/status") or ""
  local memory_kb = tonumber(status:match("VmRSS:%s*(%d+)%s+kB")) or 0
  return memory_kb * 1024
end

local function openclash_mode(cursor)
  local mode = cursor:get("openclash", "config", "proxy_mode") or "rule"
  if mode ~= "rule" and mode ~= "global" and mode ~= "direct" then
    return "rule"
  end
  return mode
end

local function core_running(cursor)
  if cursor:get("openclash", "config", "enable") ~= "1" then return false end
  return (sys.call("/bin/pidof clash >/dev/null 2>&1") == 0)
end

function M.overview()
  local cursor = uci_model.cursor()
  local running = core_running(cursor)
  local result = {
    running = running,
    version = "",
    mode = openclash_mode(cursor),
    uploadTotal = 0,
    downloadTotal = 0,
    connections = 0,
    memoryBytes = running and process_memory_bytes() or 0,
    timestamp = os.time(),
  }
  if not running then return result end

  local version, version_error = request_json("GET", "/version")
  if not version then return nil, version_error end
  local connections, connections_error = request_json("GET", "/connections")
  if not connections then return nil, connections_error end

  result.version = tostring(version.version or "")
  result.uploadTotal = math.max(0, tonumber(connections.uploadTotal) or 0)
  result.downloadTotal = math.max(0, tonumber(connections.downloadTotal) or 0)
  result.connections = type(connections.connections) == "table"
      and #connections.connections or 0
  return result
end

local function latest_delay(proxy)
  if type(proxy) ~= "table" or type(proxy.history) ~= "table" then return 0 end
  for index = #proxy.history, 1, -1 do
    local delay = tonumber(proxy.history[index] and proxy.history[index].delay)
    if delay then return math.max(0, delay) end
  end
  return 0
end

local function sanitized_history(proxy)
  local result = {}
  if type(proxy) ~= "table" or type(proxy.history) ~= "table" then return result end
  local first = math.max(1, #proxy.history - MAX_HISTORY_ENTRIES + 1)
  for index = first, #proxy.history do
    local entry = proxy.history[index]
    local delay = type(entry) == "table" and tonumber(entry.delay) or nil
    if delay and delay >= 0 then
      result[#result + 1] = {
        time = tostring(entry.time or ""):sub(1, 64),
        delay = math.floor(delay),
      }
    end
  end
  return result
end

local function node_record(name, proxy)
  local delay = latest_delay(proxy)
  local alive = proxy.alive
  if type(alive) ~= "boolean" then alive = delay > 0 end
  return {
    name = name,
    type = tostring(proxy.type or ""),
    delay = delay,
    alive = alive,
    udp = proxy.udp == true,
    xudp = proxy.xudp == true,
    tfo = proxy.tfo == true,
    history = sanitized_history(proxy),
  }
end

local function sorted_values(values)
  table.sort(values, function(left, right)
    return tostring(left.name):lower() < tostring(right.name):lower()
  end)
  return values
end

local function proxy_payloads()
  local proxies, proxies_error = request_json("GET", "/proxies")
  if not proxies then return nil, proxies_error end
  local providers, providers_error = request_json("GET", "/providers/proxies")
  if not providers then return nil, providers_error end
  return proxies.proxies or {}, providers.providers or {}
end

local function build_snapshot(proxies, providers)
  local groups = {}
  local nodes_by_name = {}
  for name, proxy in pairs(proxies) do
    if type(proxy) == "table" and type(proxy.all) == "table" and #proxy.all > 0 then
      local members = {}
      for _, member in ipairs(proxy.all) do
        if type(member) == "string" and member ~= "" then
          members[#members + 1] = member
        end
      end
      groups[#groups + 1] = {
        name = name,
        type = tostring(proxy.type or ""),
        now = tostring(proxy.now or ""),
        all = members,
      }
    elseif type(proxy) == "table" then
      nodes_by_name[name] = node_record(name, proxy)
    end
  end

  local provider_list = {}
  for provider_name, provider in pairs(providers) do
    local node_names = {}
    if type(provider) == "table" and type(provider.proxies) == "table" then
      for _, proxy in ipairs(provider.proxies) do
        local name = type(proxy) == "table" and proxy.name or nil
        if type(name) == "string" and name ~= "" then
          node_names[#node_names + 1] = name
          local current = nodes_by_name[name]
          local candidate = node_record(name, proxy)
          if not current or (current.delay or 0) == 0 then
            nodes_by_name[name] = candidate
          end
        end
      end
    end
    provider_list[#provider_list + 1] = {
      name = provider_name,
      vehicleType = tostring(provider.vehicleType or ""),
      updatedAt = tostring(provider.updatedAt or ""),
      proxies = node_names,
    }
  end

  local nodes = {}
  for _, node in pairs(nodes_by_name) do nodes[#nodes + 1] = node end
  return {
    groups = sorted_values(groups),
    nodes = sorted_values(nodes),
    providers = sorted_values(provider_list),
  }
end

function M.proxies()
  local proxies, providers_or_error = proxy_payloads()
  if not proxies then return nil, providers_or_error end
  return build_snapshot(proxies, providers_or_error)
end

local function valid_name(value)
  return type(value) == "string" and #value > 0 and #value <= 256
      and not value:find("[%z\r\n]")
end

local function contains(values, expected)
  if type(values) ~= "table" then return false end
  for _, value in ipairs(values) do
    if value == expected then return true end
  end
  return false
end

function M.select_proxy(group_name, proxy_name)
  if not valid_name(group_name) or not valid_name(proxy_name) then
    return error_result(400, "Invalid proxy selection.")
  end
  local proxies, payload_error = request_json("GET", "/proxies")
  if not proxies then return nil, payload_error end
  local group = proxies.proxies and proxies.proxies[group_name]
  if type(group) ~= "table" or not contains(group.all, proxy_name) then
    return error_result(400, "The proxy is not a member of this group.")
  end
  local path = "/proxies/" .. util.urlencode(group_name)
  local response, request_error = request_json(
    "PUT", path, jsonc.stringify({ name = proxy_name })
  )
  if not response then return nil, request_error end
  return { ok = true }
end

local function delay_path(kind, name, provider, proxies, providers)
  local query = "?url=" .. util.urlencode(TEST_URL) .. "&timeout=5000"
  if kind == "group" then
    local group = proxies[name]
    if type(group) ~= "table" or type(group.all) ~= "table" then return nil end
    return "/group/" .. util.urlencode(name) .. "/delay" .. query
  end
  if kind == "node" then
    if type(proxies[name]) ~= "table" then return nil end
    return "/proxies/" .. util.urlencode(name) .. "/delay" .. query
  end
  local provider_data = providers[provider or ""]
  if type(provider_data) ~= "table" then return nil end
  if kind == "provider" and name == provider then
    return "/providers/proxies/" .. util.urlencode(provider) .. "/healthcheck"
  end
  if kind == "provider_node" and type(provider_data.proxies) == "table" then
    for _, proxy in ipairs(provider_data.proxies) do
      if type(proxy) == "table" and proxy.name == name then
        return "/providers/proxies/" .. util.urlencode(provider) .. "/"
            .. util.urlencode(name) .. "/healthcheck" .. query
      end
    end
  end
  return nil
end

function M.test_delay(kind, name, provider)
  if not valid_name(kind) or not valid_name(name)
      or (provider and not valid_name(provider)) then
    return error_result(400, "Invalid latency test.")
  end
  local proxies, providers_or_error = proxy_payloads()
  if not proxies then return nil, providers_or_error end
  local path = delay_path(kind, name, provider, proxies, providers_or_error)
  if not path then return error_result(400, "Unknown latency test target.") end
  local response, request_error = request_json("GET", path, nil, 15)
  if not response then return nil, request_error end

  if type(response.delay) == "number" then
    return { delay = math.max(0, response.delay) }
  end
  local delays = {}
  for proxy_name, delay in pairs(response) do
    if type(proxy_name) == "string" and type(delay) == "number" then
      delays[proxy_name] = math.max(0, delay)
    end
  end
  return { ok = true, delays = delays }
end

function M.switch_mode(mode)
  if mode ~= "rule" and mode ~= "global" and mode ~= "direct" then
    return error_result(400, "Unsupported OpenClash mode.")
  end
  local cursor = uci_model.cursor()
  if core_running(cursor) then
    local response, request_error = request_json(
      "PATCH", "/configs", jsonc.stringify({ mode = mode })
    )
    if not response then return nil, request_error end
  end
  cursor:set("openclash", "config", "proxy_mode", mode)
  cursor:set("openclash", "@overwrite[0]", "proxy_mode", mode)
  if not cursor:commit("openclash") then
    return error_result(500, "OpenClash mode could not be saved.")
  end
  return { ok = true, mode = mode }
end

return M

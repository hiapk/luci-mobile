module("luci.controller.luci_mobile_mihomo", package.seeall)

local http = require "luci.http"
local service = require "luci.model.luci_mobile_mihomo"

function index()
  local root = entry(
    { "admin", "services", "luci-mobile-mihomo" },
    firstchild(), nil
  )
  root.dependent = false
  root.acl_depends = { "luci-app-openclash" }

  entry(
    { "admin", "services", "luci-mobile-mihomo", "overview" },
    call("action_overview"), nil
  ).leaf = true
  entry(
    { "admin", "services", "luci-mobile-mihomo", "proxies" },
    call("action_proxies"), nil
  ).leaf = true
  entry(
    { "admin", "services", "luci-mobile-mihomo", "proxies", "select" },
    call("action_select_proxy"), nil
  ).leaf = true
  entry(
    { "admin", "services", "luci-mobile-mihomo", "proxies", "delay" },
    call("action_test_delay"), nil
  ).leaf = true
  entry(
    { "admin", "services", "luci-mobile-mihomo", "mode" },
    call("action_switch_mode"), nil
  ).leaf = true
end

local function method_is(expected)
  if http.getenv("REQUEST_METHOD") == expected then return true end
  http.header("Allow", expected)
  http.status(405, "Method Not Allowed")
  return false
end

local function csrf_is_valid()
  local supplied = http.formvalue("sessionid")
  if not supplied or supplied == "" then return false end
  return supplied == http.getcookie("sysauth_https")
      or supplied == http.getcookie("sysauth_http")
      or supplied == http.getcookie("sysauth")
end

local function prepare_json()
  http.header("Cache-Control", "no-store")
  http.header("X-Content-Type-Options", "nosniff")
  http.prepare_content("application/json")
end

local function run(action)
  local ok, result, action_error = pcall(action)
  if not ok then
    http.status(500, "Internal Server Error")
    prepare_json()
    http.write_json({ error = "The router could not complete the request." })
    return
  end
  if not result then
    http.status(action_error and action_error.status or 500)
    prepare_json()
    http.write_json({
      error = action_error and action_error.message or "Request failed."
    })
    return
  end
  prepare_json()
  http.write_json(result)
end

local function run_post(action)
  if not method_is("POST") then return end
  if not csrf_is_valid() then
    http.status(403, "Forbidden")
    prepare_json()
    http.write_json({ error = "The LuCI session token is invalid." })
    return
  end
  run(action)
end

function action_overview()
  if not method_is("GET") then return end
  run(service.overview)
end

function action_proxies()
  if not method_is("GET") then return end
  run(service.proxies)
end

function action_select_proxy()
  run_post(function()
    return service.select_proxy(
      http.formvalue("group"), http.formvalue("proxy")
    )
  end)
end

function action_test_delay()
  run_post(function()
    return service.test_delay(
      http.formvalue("kind"),
      http.formvalue("name"),
      http.formvalue("provider")
    )
  end)
end

function action_switch_mode()
  run_post(function()
    return service.switch_mode(http.formvalue("mode"))
  end)
end

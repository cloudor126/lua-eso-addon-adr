--========================================
--        Action Duration Reminder - embedded bootstrap
--========================================
-- Entry point of the embedded (copy-in) ADR core. This file is NOT part of
-- the standalone addon; it is distributed inside the "embedded" folder of
-- each ADR release, meant to be copied together with the module files
-- listed in EMBED.md into YOUR addon (suggested: <YourAddon>/libs/ADR/).
--
-- Manifest order inside your addon:
--   EmbedAdr.lua -> Utils.lua -> i18n files -> Settings.lua
--   -> Models.lua -> Core.lua -> Debug.lua
--
-- See EMBED.md (same folder) and API.md for the usage details.

-- 1) A standalone ActionDurationReminder (or another host's embedded copy)
--    is already loaded: skip the whole embedded set. ADR_EMBED_SKIP is the
--    guard line automatically prepended to every module file. Also expose a
--    no-op fallback so hosts may call ADR_EMBED.activate() unconditionally.
if _G.ActionDurationReminder then
  _G.ADR_EMBED_SKIP = true
  if not _G.ADR_EMBED then
    _G.ADR_EMBED = {
      version = "@@ADDON_VERSION@@",
      apiVersion = tonumber("@@API_VERSION@@") or 0,
      activate = function() end,
    }
  end
  return
end

-- 2) No ActionDurationReminder present: bootstrap the embedded copy.
--========================================
--        vars
--========================================
local l = {} -- private table for local use
local m = { l = l } -- public table for module use
local NAME = "ActionDurationReminder"
local VERSION = "@@ADDON_VERSION@@"
local API_VERSION = tonumber("@@API_VERSION@@") or 0

--========================================
--        l
--========================================
---store actions for bindings
---@type table<string, fun(...: any)>
l.actionMap = {}
---@type table<string, string>
l.dict = {}
---store extensions for types
---@type table<string, fun(...: any)[]
l.extensionMap = {}
---@type table<string, any>
l.registry = {}
l.started = false
l.activated = false
---store start listeners for initiation
---@type fun(...: any)[]
l.startListeners = {}

l.start = function()
  if l.started then
    return
  end
  l.started = true
  while #l.startListeners > 0 do
    table.remove(l.startListeners, 1)()
  end
end

--========================================
--        m
--========================================
---@type string
m.name = NAME
---@type string
m.version = VERSION
---@type number
m.apiVersion = API_VERSION
---@type string
m.title = "Action Duration Reminder"
---@type boolean 本副本为内嵌副本(通过embedded/目录拷入宿主插件)的标记
m.embedded = true

---@type fun(key: string, action: fun())
m.addAction = function(key, action)
  l.actionMap[key] = action
end

m.callExtension = function(key, ...)
  local list = l.extensionMap[key] or {}
  for key, var in ipairs(list) do
    var(...)
  end
end

m.doAction = function(key, ...)
  local targetAction = l.actionMap[key]
  targetAction(...)
end

m.extend = function(key, extension)
  local list = l.extensionMap[key]
  if not list then
    list = {}
    l.extensionMap[key] = list
  end
  table.insert(list, extension)
end

m.hookStart = function(listener)
  if l.started then
    listener()
  end
  table.insert(l.startListeners, listener)
end

local reservedWords = {
  ["失衡"] = true,
}
m.isSimpleWord = function(s)
  if s:find(" ", 1, true) then
    return false
  end
  if s:find("(", 1, true) then
    return false
  end

  if s:byte(1) and s:byte(1) > 128 then
    if reservedWords[s] then
      return false
    end
    return s:len() <= 6
  end
  return true
end

m.load = function(typeName)
  return l.registry[typeName]
end

m.putText = function(key, value)
  l.dict[key] = value
end

m.register = function(typeName, typeProto)
  l.registry[typeName] = typeProto
end

m.text = function(key, ...)
  if select("#", ...) == 0 then
    return l.dict[key] or key
  end
  return l.dict[key] and string.format(l.dict[key], ...) or string.format(key, ...)
end

--========================================
--        debug (defaults, overridden by Debug.lua)
--========================================
---@type table<string, string> switch -> displayName
l.debugSwitchMap = {}
---@type table<string, table<string, string[]>> switch -> subSwitch -> {settingKey, displayName, tooltip}
l.debugSettingMap = {}

m.registerDebugSwitch = function(switch, displayName)
  l.debugSwitchMap[switch] = displayName
end

m.registerDebugSubSwitch = function(dss, displayName, tooltip)
  if not dss[2] then
    return
  end
  if not l.debugSettingMap[dss[1]] then
    l.debugSettingMap[dss[1]] = {}
  end
  -- Auto-generate settingKey: "debug" + capitalize(switch) + capitalize(subSwitch)
  local settingKey = "debug" .. dss[1]:sub(1, 1):upper() .. dss[1]:sub(2) .. dss[2]:sub(1, 1):upper() .. dss[2]:sub(2)
  l.debugSettingMap[dss[1]][dss[2]] = { settingKey, displayName, tooltip }
end

m.getDebugSwitchMap = function()
  return l.debugSwitchMap
end

m.getDebugSettingMap = function()
  return l.debugSettingMap
end

m.debugEnabled = function()
  return false
end

m.debug = function(format, ...)
  local s = string.format(format, ...)
  s = s:gsub("\n", "\n" .. string.rep(" ", 24)):gsub("%[", "|c22dd22[", 1):gsub("%]", "]|r", 1)
  d("|c0000dd[ADR]|r" .. s)
end

--========================================
--        register
--========================================
_G[NAME] = m

--========================================
--        embed bootstrap handle
--========================================
-- Call ADR_EMBED.activate("<YourAddonName>", "<YourAddonName>ADRSV") from any
-- of your files that loads after EmbedAdr.lua (typically your addon's main
-- file). The 2nd argument is the saved-variables table name your manifest
-- declares for the embedded copy (## SavedVariables: <YourAddonName>ADRSV);
-- the embedded core stores its settings there instead of sharing "ADRSV"
-- with the standalone addon. Startup is deferred until YOUR addon's
-- ADD_ON_LOADED fires, so the declared saved variables are ready.
_G.ADR_EMBED = {
  version = VERSION,
  apiVersion = API_VERSION,
  activate = function(hostAddonName, svName)
    if l.activated or l.started then
      return
    end
    l.activated = true
    if svName then
      _G.ADR_EMBED_SV_NAME = svName
    end
    local eventName = tostring(hostAddonName) .. "_ADR_EMBED"
    EVENT_MANAGER:RegisterForEvent(eventName, EVENT_ADD_ON_LOADED, function(_, addonName)
      if addonName ~= hostAddonName then
        return
      end
      EVENT_MANAGER:UnregisterForEvent(eventName, EVENT_ADD_ON_LOADED)
      l.start()
    end)
  end,
}

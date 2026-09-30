--========================================
--        vars
--========================================
local l = {} -- private table for local use
local m = { l = l } -- public table for module use
local NAME = "ActionDurationReminder"
local VERSION = "@@ADDON_VERSION@@"
local TITLE = "Action Duration Reminder"
local LINK_TYPE = "ADR_LINK"

--========================================
--        types
--========================================
---@class adr.addon.M
---@field name? string
---@field version? string
---@field title? string
---@field addAction? fun(key: string, action: fun(...: any))
---@field callExtension? fun(key: string, ...: any)
---@field doAction? fun(key: string, ...: any)
---@field extend? fun(key: string, extension: fun(...: any))
---@field hookStart? fun(listener: fun(...: any))
---@field isSimpleWord? fun(s: string): boolean
---@field load? fun(typeName: string): any
---@field putText? fun(key: string, value: string)
---@field register? fun(typeName: string, typeProto: any)
---@field text? fun(key: string, ...: any): string
---调试体系(Debug模块运行时覆盖实现)
---@field registerDebugSwitch? fun(switch: string, displayName: string)
---@field registerDebugSubSwitch? fun(dss: string[], displayName: string, tooltip: string)
---@field getDebugSwitchMap? fun(): table<string, string>
---@field getDebugSettingMap? fun(): table<string, table<string, string[]>>
---@field debugEnabled? fun(dss: string[], abilityName?: string): boolean
---@field debug? fun(format: string, ...: string)

--========================================
--        l
--========================================
---store actions for bindings
---@type table<string, fun(...: any)>
l.actionMap = {}
---@type table<string, string>
l.dict = {}
---store extensions for types
---@type table<string, fun(...: any)[]>
l.extensionMap = {}
---@type table<string, any>
l.registry = {}
l.started = false
---store start listeners for initiation
---@type fun(...: any)[]
l.startListeners = {}

---@type fun(eventCode: number, addonName: string)
l.onAddonStarted = function(eventCode, addonName)
  if NAME ~= addonName then
    return
  end
  EVENT_MANAGER:UnregisterForEvent(addonName, eventCode)
  l.start()
end

l.start = function()
  if l.started then
    return
  end
  l.started = true
  while #l.startListeners > 0 do
    table.remove(l.startListeners, 1)()
  end

  --  if HodorReflexes and HodorReflexes.users then
  --    HodorReflexes.users["@Cloudor"] = {"Cloudor", "|cfffe00Cloudor|r", "ActionDurationReminder/src/cloudor.dds"}
  --  end
end

--========================================
--        m
--========================================
---@type string
m.name = NAME
---@type string
m.version = VERSION
---@type string
m.title = TITLE

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
--        debug
--========================================
---@type table<string, string> switch -> displayName
l.debugSwitchMap = {}
---@type table<string, table<string, string[]>> switch -> subSwitch -> {settingKey, displayName, tooltip}
l.debugSettingMap = {}

---@type fun(switch: string, displayName: string)
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

-- Debug module will provide debugEnabled, debugDefaults, refreshMenu implementations
-- For now, provide no-op implementations that Debug module will override

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
EVENT_MANAGER:RegisterForEvent(m.name, EVENT_ADD_ON_LOADED, l.onAddonStarted)

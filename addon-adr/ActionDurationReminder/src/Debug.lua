local addon = ActionDurationReminder
local settings = addon.load("Settings#M")
local l = {
  getSavedVars = function()
    return settings.getSavedVars()
  end,
}
---Debug模块公开表(addon.register("Debug#M"))
---@class adr.debug.M
---@field getLogs? fun(): string[]
---@field getLogVersion? fun(): number
---@field clearLogs? fun()
local m = { l = l }

--========================================
--        l
--========================================

-- Ring buffer of recent debug log lines, consumed by the Debug Console window
l.logs = {}
-- Bumped on every push so viewers can cheaply detect new content
l.logVersion = 0

---@type fun(line: string)
l.pushLog = function(line)
  local cap = l.getSavedVars().debugBufferCap or 1000
  if #l.logs >= cap then
    table.remove(l.logs, 1)
  end
  l.logs[#l.logs + 1] = string.format("[%8.2f] %s", GetGameTimeMilliseconds() / 1000, line)
  l.logVersion = l.logVersion + 1
end

-- Wrap the Addon.lua stub so every debug line also lands in the ring buffer;
-- chat output becomes optional (default off) to keep the chat frame clean
local stubDebug = addon.debug
addon.debug = function(format, ...)
  local raw = string.format(format, ...)
  l.pushLog(raw)
  if l.getSavedVars().debugChatOutput then
    stubDebug("%s", raw)
  end
end

---@type fun(): string[]
m.getLogs = function()
  return l.logs
end

---@type fun(): number
m.getLogVersion = function()
  return l.logVersion
end

---@type fun()
m.clearLogs = function()
  for i = #l.logs, 1, -1 do
    l.logs[i] = nil
  end
  l.logVersion = l.logVersion + 1
end

--========================================
--        m
--========================================

-- Override addon.debugEnabled with full implementation using Settings
addon.debugEnabled = function(dss, abilityName)
  if type(dss) ~= "table" then
    return false
  end
  local sv = l.getSavedVars()
  if not sv.debugLoggingEnabled then
    return false
  end
  local switch, subSwitch = dss[1], dss[2]
  if abilityName and sv.debugFilterPattern ~= "" then
    if not abilityName:match(sv.debugFilterPattern) then
      return false
    end
  end
  if subSwitch then
    local info = addon.getDebugSettingMap()[switch] and addon.getDebugSettingMap()[switch][subSwitch]
    if info then
      return sv[info[1]]
    end
  end
  return false
end

--========================================
--        l
--========================================

-- Debug module defaults
---扩展 adr.settings.SavedVars:本模块持久化字段,与下方 defaults 一一对应
---@class adr.settings.SavedVars
---@field debugLoggingEnabled? boolean
---@field debugFilterPattern? string
---@field debugLogTrackedEffectsInChat? boolean
---@field debugChatOutput? boolean
---@field debugBufferCap? number
---@field addonLogTrackedEffectsInChat? boolean

---@type adr.settings.SavedVars
local debugSavedVarsDefaults = {
  debugLogTrackedEffectsInChat = false,
  debugFilterPattern = "",
  debugLoggingEnabled = false,
  debugChatOutput = false,
  debugBufferCap = 1000,
}

--========================================
--        init
--========================================

-- Register debug defaults
addon.extend(settings.EXTKEY_ADD_DEFAULTS, function()
  -- Add Debug module's own defaults
  settings.addDefaults(debugSavedVarsDefaults)
  -- Add all DSS defaults (all true)
  for _, subs in pairs(addon.getDebugSettingMap()) do
    for _, info in pairs(subs) do
      local settingKey = info[1]
      settings.addDefaults({ [settingKey] = true })
    end
  end
end)

-- Build Debug submenu in settings menu
addon.extend(settings.EXTKEY_ADD_MENUS, function()
  local controls = {
    {
      type = "checkbox",
      name = addon.text("Log Tracked Effects"),
      tooltip = addon.text("Print tracked effects to chat when they are applied"),
      getFunc = function()
        return l.getSavedVars().debugLogTrackedEffectsInChat
      end,
      setFunc = function(value)
        l.getSavedVars().debugLogTrackedEffectsInChat = value
      end,
      width = "full",
    },
    {
      type = "checkbox",
      name = addon.text("Enable Debug Logging"),
      tooltip = addon.text("Enable fine-grained debug logging without using console commands"),
      getFunc = function()
        return l.getSavedVars().debugLoggingEnabled
      end,
      setFunc = function(value)
        l.getSavedVars().debugLoggingEnabled = value
      end,
      width = "half",
    },
    {
      type = "button",
      name = addon.text("Open Debug Console"),
      tooltip = addon.text("Open a window to browse, filter and copy recent debug logs"),
      func = function()
        SCENE_MANAGER:Hide("gameMenuInGame")
        addon.load("DebugWindow#M").open()
      end,
      width = "half",
    },
    {
      type = "checkbox",
      name = addon.text("Also Print To Chat"),
      tooltip = addon.text(
        "Debug logs also go to the ring buffer used by the Debug Console; enable this to additionally print them to the chat frame"
      ),
      getFunc = function()
        return l.getSavedVars().debugChatOutput
      end,
      setFunc = function(value)
        l.getSavedVars().debugChatOutput = value
      end,
      width = "half",
    },
    {
      type = "slider",
      name = addon.text("Debug Buffer Cap"),
      tooltip = addon.text("Maximum number of debug log lines kept in the Debug Console ring buffer"),
      min = 100,
      max = 5000,
      step = 50,
      getFunc = function()
        return l.getSavedVars().debugBufferCap
      end,
      setFunc = function(value)
        l.getSavedVars().debugBufferCap = value
        -- trim immediately when lowered
        local logs = l.logs
        while #logs > value do
          table.remove(logs, 1)
        end
        l.logVersion = l.logVersion + 1
      end,
      width = "half",
      default = debugSavedVarsDefaults.debugBufferCap,
    },
  }

  local detailedControls = {
    {
      type = "editbox",
      name = addon.text("Ability Name Filter"),
      tooltip = addon.text(
        'Lua pattern to filter debug logs by ability name (e.g., " Lash$" matches names ending with " Lash". Leave empty to disable)'
      ),
      getFunc = function()
        return l.getSavedVars().debugFilterPattern
      end,
      setFunc = function(text)
        l.getSavedVars().debugFilterPattern = text
      end,
      isMultiline = false,
      width = "full",
      disabled = function()
        return not l.getSavedVars().debugLoggingEnabled
      end,
    },
    {
      type = "button",
      name = addon.text("Enable All"),
      tooltip = addon.text("Enable all debug sub-switches"),
      func = function()
        local sv = l.getSavedVars()
        for _, settings in pairs(addon.getDebugSettingMap()) do
          for _, info in pairs(settings) do
            sv[info[1]] = true
          end
        end
      end,
      width = "half",
    },
    {
      type = "button",
      name = addon.text("Disable All"),
      tooltip = addon.text("Disable all debug sub-switches"),
      func = function()
        local sv = l.getSavedVars()
        for _, settings in pairs(addon.getDebugSettingMap()) do
          for _, info in pairs(settings) do
            sv[info[1]] = false
          end
        end
      end,
      width = "half",
    },
  }

  table.insert(controls, {
    type = "submenu",
    name = addon.text("Detailed Debug Options"),
    disabled = function()
      return not l.getSavedVars().debugLoggingEnabled
    end,
    controls = detailedControls,
  })

  -- Build debug option controls from registered switches/subswitches
  for switch, displayName in pairs(addon.getDebugSwitchMap()) do
    table.insert(detailedControls, { type = "header", name = addon.text(displayName) })
    local subs = addon.getDebugSettingMap()[switch] or {}
    for subSwitch, info in pairs(subs) do
      local settingKey = info[1]
      local subDisplayName = info[2]
      local tooltip = info[3]
      table.insert(detailedControls, {
        type = "checkbox",
        name = addon.text(subDisplayName),
        tooltip = addon.text(tooltip),
        getFunc = function()
          return l.getSavedVars()[settingKey]
        end,
        setFunc = function(value)
          l.getSavedVars()[settingKey] = value
        end,
        width = "full",
      })
    end
  end

  settings.addMenuOptions({
    type = "submenu",
    name = addon.text("Debug"),
    controls = controls,
  })
end)

--========================================
--        register
--========================================
addon.register("Debug#M", m)

addon.register("Debug", m)

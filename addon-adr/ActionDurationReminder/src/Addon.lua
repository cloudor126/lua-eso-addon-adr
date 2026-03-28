--========================================
--        vars
--========================================
local l = {} -- #L private table for local use
local m = {l=l} -- #M public table for module use
local NAME = 'ActionDurationReminder'
local VERSION = '@@ADDON_VERSION@@'
local TITLE = 'Action Duration Reminder'

--========================================
--        l
--========================================
l.actionMap = {} -- #map<#string,#()->()> store actions for bindings
l.dict = {} --#map<#string,#string>
l.extensionMap = {} -- #map<#string,#list<#()->()>> store extensions for types
l.registry = {} --#map<#string,#any>
l.started = false
l.startListeners = {} -- #list<#()->()> store start listeners for initiation

l.onAddonStarted -- #(#number:eventCode,#string:addonName)->()
= function(eventCode, addonName)
  if NAME ~= addonName then return end
  EVENT_MANAGER:UnregisterForEvent(addonName, eventCode)
  l.start()
end

l.start -- #()->()
= function()
  if l.started then return end
  l.started = true
  while #l.startListeners > 0 do
    table.remove(l.startListeners,1)()
  end
--  if HodorReflexes and HodorReflexes.users then
--    HodorReflexes.users["@Cloudor"] = {"Cloudor", "|cfffe00Cloudor|r", "ActionDurationReminder/src/cloudor.dds"}
--  end
end

--========================================
--        m
--========================================
m.name = NAME -- #string
m.version = VERSION -- #string
m.title = TITLE -- #string

m.addAction -- #(#string:key,#()->():action)->()
= function(key, action)
  l.actionMap[key] = action
end

m.callExtension -- #(#string:key,#any:...)->()
= function(key, ...)
  local list = l.extensionMap[key] or {}
  for key, var in ipairs(list) do
    var(...)
  end
end

m.doAction -- #(#string:key,#any:...)->()
= function(key,...)
  local targetAction = l.actionMap[key]
  targetAction(...)
end

m.extend -- #(#string:key, #()->():extension)->()
= function(key, extension)
  local list = l.extensionMap[key]
  if not list then
    list = {}
    l.extensionMap[key] = list
  end
  table.insert(list, extension)
end

m.hookStart -- #(#()->():listener)->()
= function(listener)
  if l.started then listener() end
  table.insert(l.startListeners, listener)
end

m.isSimpleWord -- #(#stirng:s)->(#boolean)
= function(s)
  if s:find(' ',1,true) then return false end
  if s:find('(',1,true) then return false end
  if s:byte(1) and s:byte(1)>128 then return s:len()<=6 end
  return true
end

m.load -- #(#string:typeName)->($1)
= function(typeName)
  return l.registry[typeName]
end

m.putText -- #(#string:key, #string:value)->()
= function(key, value)
  l.dict[key] = value
end

m.register -- #(#string:typeName, #any:typeProto)->()
= function(typeName, typeProto)
  l.registry[typeName]=typeProto
end

m.text -- #(#string:key, #any:...)->(#string)
= function(key,...)
  if select('#',...) ==0 then
    return l.dict[key] or key
  end
  return l.dict[key] and string.format(l.dict[key],...) or string.format(key,...)
end

--========================================
--        debug
--========================================
l.debugSwitchMap = {} -- #map<#string,#string> switch -> displayName
l.debugSettingMap = {} -- #map<#string,#map<#string,#string>> switch -> subSwitch -> settingKey

m.registerDebugSwitch -- #(#string:switch, #string:displayName)->()
= function(switch, displayName)
  l.debugSwitchMap[switch] = displayName
  l.debugSettingMap[switch] = {}
end

m.registerDebugSubSwitch -- #(#string:switch, #string:subSwitch, #string:settingKey)->()
= function(switch, subSwitch, settingKey)
  if not l.debugSettingMap[switch] then
    l.debugSettingMap[switch] = {}
  end
  l.debugSettingMap[switch][subSwitch] = settingKey
end

m.debugEnabled -- #(#table:dss,#string:abilityName)->(#boolean)
= function(dss, abilityName)
  if type(dss) ~= 'table' then return false end
  local sv = m.getSavedVars()
  if not sv.addonDebugLoggingEnabled then return false end
  local switch, subSwitch = dss[1], dss[2]
  if abilityName and sv.addonDebugFilterPattern ~= '' then
    if not abilityName:match(sv.addonDebugFilterPattern) then
      return false
    end
  end
  if subSwitch then
    local settingKey = l.debugSettingMap[switch] and l.debugSettingMap[switch][subSwitch]
    if settingKey then
      return sv[settingKey]
    end
  end
  return false
end

m.debug -- #(#string:format, #string:...)->()
= function(format, ...)
  df('[ADR] ' .. format, ...)
end

m.getSavedVars -- #()->(#SavedVars)
= function()
  local settings = l.registry["Settings#M"]
  return settings and settings.getSavedVars() or {}
end

-- extension for debug options - modules register their debug switches
m.EXTKEY_DEBUG_OPTIONS = "Debug:addOptions"

-- Build Debug submenu by collecting options from all modules
addon.extend(settings.EXTKEY_ADD_MENUS, function()
  local controls = {
    {
      type = "checkbox",
      name = addon.text("Log Tracked Effects"),
      tooltip = addon.text("Print tracked effects to chat when they are applied"),
      getFunc = function() return m.getSavedVars().addonLogTrackedEffectsInChat end,
      setFunc = function(value) m.getSavedVars().addonLogTrackedEffectsInChat = value end,
      width = "full",
    },
    {
      type = "checkbox",
      name = addon.text("Enable Debug Logging"),
      tooltip = addon.text("Enable fine-grained debug logging without using console commands"),
      getFunc = function() return m.getSavedVars().addonDebugLoggingEnabled end,
      setFunc = function(value) m.getSavedVars().addonDebugLoggingEnabled = value end,
      width = "full",
    },
    {
      type = "submenu",
      name = addon.text("Detailed Debug Options"),
      disabled = function() return not m.getSavedVars().addonDebugLoggingEnabled end,
      controls = {
        {
          type = "editbox",
          name = addon.text("Ability Name Filter"),
          tooltip = addon.text('Lua pattern to filter debug logs by ability name (e.g., " Lash$" matches names ending with " Lash". Leave empty to disable)'),
          getFunc = function() return m.getSavedVars().addonDebugFilterPattern end,
          setFunc = function(text) m.getSavedVars().addonDebugFilterPattern = text end,
          isMultiline = false,
          width = "full",
          disabled = function() return not m.getSavedVars().addonDebugLoggingEnabled end,
        },
        {
          type = "button",
          name = addon.text("Enable All"),
          tooltip = addon.text("Enable all debug sub-switches"),
          func = function()
            local sv = m.getSavedVars()
            for _, settings in pairs(l.debugSettingMap) do
              for _, key in pairs(settings) do
                sv[key] = true
              end
            end
            m.refreshMenu()
          end,
          width = "half",
        },
        {
          type = "button",
          name = addon.text("Disable All"),
          tooltip = addon.text("Disable all debug sub-switches"),
          func = function()
            local sv = m.getSavedVars()
            for _, settings in pairs(l.debugSettingMap) do
              for _, key in pairs(settings) do
                sv[key] = false
              end
            end
            m.refreshMenu()
          end,
          width = "half",
        },
      },
    },
  }

  -- Collect debug options from all modules via extension
  local moduleControls = {}
  addon.callExtension(m.EXTKEY_DEBUG_OPTIONS, moduleControls)
  for _, c in ipairs(moduleControls) do
    table.insert(controls[3].controls, c)
  end

  settings.addMenuOptions({
    type = "submenu",
    name = addon.text("Debug"),
    controls = controls,
  })
end)

-- Addon-level defaults (Settings will pick these up directly)
m.addonDefaults = {
  addonLogTrackedEffectsInChat = false,
  addonDebugFilterPattern = '',
  addonDebugLoggingEnabled = false,
}

m.refreshMenu -- #()->()
= function()
  LAM2:RefreshPanel('ADRAddonOptions')
end

--========================================
--        register
--========================================
_G[NAME] = m
EVENT_MANAGER:RegisterForEvent(m.name, EVENT_ADD_ON_LOADED, l.onAddonStarted)

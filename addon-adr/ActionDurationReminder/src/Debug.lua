local addon = ActionDurationReminder
local settings = addon.load("Settings#M")
local l = {
  getSavedVars = function() return settings.getSavedVars() end,
}
local m = {l=l}

--========================================
--        m
--========================================

m.refreshMenu -- #()->()
= function()
  LAM2:RefreshPanel('ADRAddonOptions')
end

-- Override addon.debugEnabled with full implementation using Settings
addon.debugEnabled = function(dss, abilityName)
  if type(dss) ~= 'table' then return false end
  local sv = l.getSavedVars()
  if not sv.debugLoggingEnabled then return false end
  local switch, subSwitch = dss[1], dss[2]
  if abilityName and sv.debugFilterPattern ~= '' then
    if not abilityName:match(sv.debugFilterPattern) then
      return false
    end
  end
  if subSwitch then
    local info = addon.getDebugSettingMap[switch] and addon.getDebugSettingMap[switch][subSwitch]
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
local debugSavedVarsDefaults
  = {
    debugLogTrackedEffectsInChat = false,
    debugFilterPattern = '',
    debugLoggingEnabled = false,
  }

--========================================
--        init
--========================================

-- Register debug defaults
addon.extend(settings.EXTKEY_ADD_DEFAULTS, function()
  -- Add Debug module's own defaults
  settings.addDefaults(debugSavedVarsDefaults)
  -- Add all DSS defaults (all true)
  for _, subs in pairs(addon.getDebugSettingMap) do
    for _, info in pairs(subs) do
      local settingKey = info[1]
      settings.addDefaults({[settingKey] = true})
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
      getFunc = function() return l.getSavedVars().debugLogTrackedEffectsInChat end,
      setFunc = function(value) l.getSavedVars().debugLogTrackedEffectsInChat = value end,
      width = "full",
    },
    {
      type = "checkbox",
      name = addon.text("Enable Debug Logging"),
      tooltip = addon.text("Enable fine-grained debug logging without using console commands"),
      getFunc = function() return l.getSavedVars().debugLoggingEnabled end,
      setFunc = function(value) l.getSavedVars().debugLoggingEnabled = value end,
      width = "full",
    },
    {
      type = "submenu",
      name = addon.text("Detailed Debug Options"),
      disabled = function() return not l.getSavedVars().debugLoggingEnabled end,
      controls = {
        {
          type = "editbox",
          name = addon.text("Ability Name Filter"),
          tooltip = addon.text('Lua pattern to filter debug logs by ability name (e.g., " Lash$" matches names ending with " Lash". Leave empty to disable)'),
          getFunc = function() return l.getSavedVars().debugFilterPattern end,
          setFunc = function(text) l.getSavedVars().debugFilterPattern = text end,
          isMultiline = false,
          width = "full",
          disabled = function() return not l.getSavedVars().debugLoggingEnabled end,
        },
        {
          type = "button",
          name = addon.text("Enable All"),
          tooltip = addon.text("Enable all debug sub-switches"),
          func = function()
            local sv = l.getSavedVars()
            for _, settings in pairs(addon.getDebugSettingMap) do
              for _, info in pairs(settings) do
                sv[info[1]] = true
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
            local sv = l.getSavedVars()
            for _, settings in pairs(addon.getDebugSettingMap) do
              for _, info in pairs(settings) do
                sv[info[1]] = false
              end
            end
            m.refreshMenu()
          end,
          width = "half",
        },
      },
    },
  }

  -- Build debug option controls from registered switches/subswitches
  for switch, displayName in pairs(addon.getDebugSwitchMap) do
    table.insert(controls[3].controls, { type = "header", name = addon.text(displayName) })
    local subs = addon.getDebugSettingMap[switch] or {}
    for subSwitch, info in pairs(subs) do
      local settingKey = info[1]
      local subDisplayName = info[2]
      local tooltip = info[3]
      table.insert(controls[3].controls, {
        type = "checkbox",
        name = addon.text(subDisplayName),
        tooltip = addon.text(tooltip),
        getFunc = function() return l.getSavedVars()[settingKey] end,
        setFunc = function(value) l.getSavedVars()[settingKey] = value end,
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

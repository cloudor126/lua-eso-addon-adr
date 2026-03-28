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
    local info = l.debugSettingMap[switch] and l.debugSettingMap[switch][subSwitch]
    if info then
      return sv[info[1]]
    end
  end
  return false
end

--========================================
--        l
--========================================
l.debugSwitchMap = {}
l.debugSettingMap = {}

-- Debug module defaults
local debugSavedVarsDefaults
  = {
    debugLogTrackedEffectsInChat = false,
    debugFilterPattern = '',
    debugLoggingEnabled = false,
    -- fine-grained debug options (default all true when logging enabled)
    -- DS_ACTION
    debugActionFind = true,
    debugActionNew = true,
    debugActionMatch = true,
    debugActionUnref = true,
    debugActionStack = true,
    debugActionRemove = true,
    debugActionDelete = true,
    debugActionSave = true,
    debugActionClear = true,
    -- DS_COMBAT
    debugCombatEvent = true,
    debugCombatFade = true,
    debugCombatStack = true,
    debugCombatTick = true,
    debugCombatDuration = true,
    debugCombatChannel = true,
    -- DS_EFFECT
    debugEffectGain = true,
    debugEffectFade = true,
    debugEffectUpdate = true,
    debugEffectRefresh = true,
    debugEffectTransfer = true,
    debugEffectMiss = true,
    -- DS_FILTER
    debugFilterAccept = true,
    debugFilterReject = true,
    -- DS_TARGET
    debugTargetTrack = true,
  }

--========================================
--        init
--========================================
addon.hookStart(function()
  -- Get references to Addon's debug registration tables
  local addonModule = addon.load("Addon#M")
  l.debugSwitchMap = addonModule.l.debugSwitchMap or {}
  l.debugSettingMap = addonModule.l.debugSettingMap or {}
end)

-- Register debug defaults
addon.extend(settings.EXTKEY_ADD_DEFAULTS, function()
  settings.addDefaults(debugSavedVarsDefaults)
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
            for _, settings in pairs(l.debugSettingMap) do
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
            for _, settings in pairs(l.debugSettingMap) do
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
  for switch, displayName in pairs(l.debugSwitchMap) do
    table.insert(controls[3].controls, { type = "header", name = addon.text(displayName) })
    local subs = l.debugSettingMap[switch] or {}
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

-- Add debug defaults
addon.extend(settings.EXTKEY_ADD_DEFAULTS, function()
  return m.debugDefaults
end)

--========================================
--        register
--========================================
addon.register("Debug#M", m)

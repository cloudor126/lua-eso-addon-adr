--========================================
--        vars
--========================================
---@type adr.addon.M
local addon = ActionDurationReminder
local l = {}
---@type adr.settings.M
local m = { l = l }
local SV_NAME = "ADRSV"
local SV_VER = "1.0"

--========================================
--        types
--========================================
---@type adr.settings.SavedVars
local savedVarsDefaults = {
  settingsAccountWide = false,
}

---LibAddonMenu2菜单项(字段随LAM2控件类型扩展)
---@class adr.settings.MenuOption
---@field type? string
---@field name? string
---@field getFunc? fun(): any
---@field setFunc? fun(value: any)
---@field width? string|number
---@field default? any

---存档变量(字段随各模块addDefaults扩展)
---@class adr.settings.SavedVars
---@field settingsAccountWide? boolean
---alert
---@field alertEnabled? boolean
---@field alertIconOnly? boolean
---@field alertPlaySound? boolean
---@field alertSoundName? string
---@field alertAheadSeconds? number
---@field alertKeepSeconds? number
---@field alertKeyWords? string
---@field alertBlackKeyWords? string
---@field alertOffsetX? number
---@field alertOffsetY? number
---@field alertFontName? string
---@field alertCustomFontName? string
---@field alertFontSize? number
---@field alertFontStyle? string
---@field alertIconSize? number
---@field alertIconOpacity? number
---bar
---@field barEnabled? boolean
---@field barShowShift? boolean
---@field barShowShiftFully? boolean
---@field barShowShiftScalePercent? number
---@field barShowInQuickslot? boolean
---@field barShiftOffsetX? number
---@field barShiftOffsetY? number
---@field barCooldownVisible? boolean
---@field barCooldownColor? number[]
---@field barCooldownEndingColor? number[]
---@field barCooldownEndingSeconds? number
---@field barCooldownOpacity? number
---@field barCooldownThickness? number
---@field barLabelEnabled? boolean
---@field barLabelColor? number[]
---@field barLabelEndingColor? number[]
---@field barLabelFontName? string
---@field barLabelFontSize? number
---@field barLabelFontStyle? string
---@field barLabelYOffset? number
---@field barLabelYOffsetInShift? number
---@field barLabelIgnoreDecimal? boolean
---@field barLabelIgnoreDeciamlThreshold? number 原拼写如此
---@field barLowPriorityLabelColor? number[]
---@field barStackLabelEnabled? boolean
---@field barStackLabelColor? number[]
---@field barStackLabelFontName? string
---@field barStackLabelFontSize? number
---@field barStackLabelFontStyle? string
---@field barStackLabelYOffset? number
---@field barStackLabelYOffsetInShift? number
---@field barProgressVisible? boolean
---@field barProgressColor? number[]
---@field barProgressOpacity? number
---@field barProgressDirection? string
---chatAlert
---@field chatAlertEnabled? boolean
---@field chatAlertChannelParty? boolean
---@field chatAlertChannelGuild? boolean
---@field chatAlertChannelSay? boolean
---@field chatAlertChannelWhisper? boolean
---@field chatAlertDurationSeconds? number
---@field chatAlertFontName? string
---@field chatAlertFontSize? number
---@field chatAlertFontStyle? string
---@field chatAlertAlignment? string|number
---@field chatAlertGuildPrefixFormat? string
---@field chatAlertMaxAlerts? number
---@field chatAlertMaxMessageLength? number
---@field chatAlertOffsetX? number
---@field chatAlertOffsetY? number
---@field chatAlertOnlyInCombat? boolean
---@field chatAlertPlaySound? boolean
---@field chatAlertPromptShown? boolean
---@field chatAlertShowUserId? boolean
---@field chatAlertSoundName? string
---core
---@field coreMultipleTargetTracking? boolean
---@field coreMultipleTargetTrackingWithoutClearing? boolean
---@field coreSecondsBeforeFade? number
---@field coreMinimumDurationSeconds? number
---@field coreIgnoreLongDebuff? boolean
---@field coreKeyWords? string
---@field coreBlackKeyWords? string
---@field coreClearAreaActionsOnCombatEnd? boolean
---patch
---@field patchMoveBarsEnabled? boolean
---debug
---@field debugLoggingEnabled? boolean
---@field debugFilterPattern? string
---@field debugLogTrackedEffectsInChat? boolean
---@field addonLogTrackedEffectsInChat? boolean

---Settings模块公开表(addon.register("Settings#M"))
---@class adr.settings.M
---@field EXTKEY_ADD_DEFAULTS? string
---@field EXTKEY_ADD_MENUS? string
---@field addDefaults? fun(...: any)
---@field addMenuOptions? fun(...: adr.settings.MenuOption)
---@field getAccountSavedVars? fun(): adr.settings.SavedVars
---@field getCharacterSavedVars? fun(): adr.settings.SavedVars
---@field getSavedVars? fun(): adr.settings.SavedVars

--========================================
--        l
--========================================
---@type adr.settings.SavedVars
l.accountSavedVars = {}
---@type adr.settings.SavedVars
l.characterSavedVars = {}
---@type adr.settings.MenuOption[]
l.menuOptions = {}

---@type fun()
l.onStart = function()
  -- load saved vars with defaults
  -- first, pick up addon-level defaults directly from addon
  if addon.debugDefaults then
    zo_mixin(savedVarsDefaults, addon.debugDefaults)
  end
  -- then let modules add their own defaults
  addon.callExtension(m.EXTKEY_ADD_DEFAULTS)
  l.accountSavedVars = ZO_SavedVars:NewAccountWide(SV_NAME, SV_VER, nil, savedVarsDefaults)
  l.characterSavedVars = ZO_SavedVars:New(SV_NAME, SV_VER, nil, savedVarsDefaults)
  -- register addon panel
  local LAM2 = LibAddonMenu2
  if LAM2 == nil then
    return
  end
  local panelData = {
    type = "panel",
    name = addon.title or addon.name,
    displayName = "ADR Settings",
    author = "Cloudor",
    version = addon.version,
    website = "https://www.esoui.com/downloads/info1536-ActionDurationReminder.html",
    feedback = "https://www.esoui.com/downloads/info1536-ActionDurationReminder.html#comments",
    slashCommand = "/adrset",
    registerForRefresh = true,
    registerForDefaults = true,
  }
  LAM2:RegisterAddonPanel("ADRAddonOptions", panelData)
  -- init menu options
  m.addMenuOptions({
    type = "checkbox",
    name = addon.text("Account Wide Configuration"),
    getFunc = function()
      return l.characterSavedVars.settingsAccountWide
    end,
    setFunc = function(value)
      l.characterSavedVars.settingsAccountWide = value
    end,
    width = "full",
    default = true,
  })
  addon.callExtension(m.EXTKEY_ADD_MENUS)
  LAM2:RegisterOptionControls("ADRAddonOptions", l.menuOptions)
end

--========================================
--        m
--========================================
m.EXTKEY_ADD_DEFAULTS = "Settings:addDefaults"
m.EXTKEY_ADD_MENUS = "Settings:addMenus"

---@type fun(...: any)
m.addDefaults = function(...)
  zo_mixin(savedVarsDefaults, ...)
end

---@type fun(...: adr.settings.MenuOption)
m.addMenuOptions = function(...)
  for i = 1, select("#", ...) do
    local option = select(i, ...)
    table.insert(l.menuOptions, option)
  end
end

---@type fun(): adr.settings.SavedVars
m.getAccountSavedVars = function()
  return l.accountSavedVars
end

---@type fun(): adr.settings.SavedVars
m.getCharacterSavedVars = function()
  return l.characterSavedVars
end

---@type fun(): adr.settings.SavedVars
m.getSavedVars = function()
  return l.characterSavedVars.settingsAccountWide and l.accountSavedVars or l.characterSavedVars
end

--========================================
--        register
--========================================
addon.register("Settings#M", m)
addon.register("Settings", m)
addon.hookStart(l.onStart)

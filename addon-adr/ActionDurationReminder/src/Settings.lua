--========================================
--        vars
--========================================
local addon = ActionDurationReminder -- Addon#M
local l = {} -- #L
local m = {l=l} -- #M
local SV_NAME = "ADRSV"
local SV_VER = "1.0"

---
--@type SavedVars
local savedVarsDefaults = {
  settingsAccountWide = false,
}

---
--@type MenuOption
--@field #string type
--@field #string name
--@field #()->(#any) getFunc
--@field #(#any:value)->() setFunc
--@field #string width
--@field #any default

--========================================
--        l
--========================================
l.accountSavedVars = {}  --#SavedVars
l.characterSavedVars = {}  --#SavedVars
l.menuOptions = {} --#list<#MenuOption>

l.onStart -- #()->()
= function()
  -- load saved vars with defaults
  addon.callExtension(m.EXTKEY_ADD_DEFAULTS)
  l.accountSavedVars = ZO_SavedVars:NewAccountWide(SV_NAME, SV_VER, nil, savedVarsDefaults)
  l.characterSavedVars = ZO_SavedVars:New(SV_NAME, SV_VER, nil, savedVarsDefaults)
  -- register addon panel
  local LAM2 = LibAddonMenu2
  if LAM2 == nil then return end
  local panelData = {
    type = 'panel',
    name = addon.name,
    displayName = "ADR Settings",
    author = "Cloudor",
    version = addon.version,
    website = "https://www.esoui.com/downloads/info1536-ActionDurationReminder.html",
    feedback = "https://www.esoui.com/downloads/info1536-ActionDurationReminder.html#comments",
    slashCommand = "/adrset",
    registerForRefresh = true,
    registerForDefaults = true,
  }
  LAM2:RegisterAddonPanel('ADRAddonOptions', panelData)
  -- init menu options
  m.addMenuOptions({
    type = "checkbox",
        name = addon.text("Account Wide Configuration"),
        getFunc = function() return l.characterSavedVars.settingsAccountWide end,
        setFunc = function(value)
            l.characterSavedVars.settingsAccountWide = value
        end,
        width = "full",
        default = true,
  })
  addon.callExtension(m.EXTKEY_ADD_MENUS)
  LAM2:RegisterOptionControls('ADRAddonOptions', l.menuOptions)
end

--========================================
--        m
--========================================
m.EXTKEY_ADD_DEFAULTS = "Settings:addDefaults"
m.EXTKEY_ADD_MENUS = "Settings:addMenus"

m.addDefaults -- #(#any:...)->()
= function(...)
  zo_mixin(savedVarsDefaults,...)
end

m.addMenuOptions -- #(#MenuOption:...)->()
= function(...)
  for i=1,select('#',...) do
    local option = select(i, ...)
    table.insert(l.menuOptions, option)
  end
end

m.getAccountSavedVars -- #()->(#SavedVars)
= function()
  return l.accountSavedVars
end

m.getCharacterSavedVars -- #()->(#SavedVars)
= function()
  return l.characterSavedVars
end

m.getSavedVars -- #()->(#SavedVars)
= function()
  return l.characterSavedVars.settingsAccountWide and l.accountSavedVars or l.characterSavedVars
end

--========================================
--        register
--========================================
addon.register("Settings#M",m)
addon.hookStart(l.onStart)

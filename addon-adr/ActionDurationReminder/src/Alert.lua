--========================================
--        vars
--========================================
local addon = ActionDurationReminder -- Addon#M
local settings = addon.load("Settings#M")
local models = addon.load("Models#M")
local core = addon.load("Core#M")
local l = {} -- #L
local m = {l=l} -- #M

local DS_ALERT = "alert" -- debug switch for alert

-- DSS (Debug Switch + SubSwitch) constants for addon.debugEnabled
local DSS_ALERT_SHOW = {DS_ALERT, 'show'}      -- alert shown
local DSS_ALERT_HIDE = {DS_ALERT, 'hide'}      -- alert hidden
local DSS_ALERT_SKIP = {DS_ALERT, 'skip'}      -- alert skipped
local DSS_ALERT_RULE = {DS_ALERT, 'rule'}      -- rule check
local DSS_ALERT_REMOVE = {DS_ALERT, 'remove'}  -- alert removed by rule

-- Power Lash Guide ability id (fake id from Core.lua)
local POWER_LASH_GUIDE_ABILITY_ID = -999001

local zhFlags = {
  zh = true,
  ze = true,
  zf = true,
  zg = true,
  jf = true,
} -- #map<#string,#boolean>

---
--@type AlertSavedVars
local alertSavedVarsDefaults ={
  alertEnabled = true,
  alertIconOnly = false,
  alertPlaySound = false,
  alertSoundName = 'NEW_TIMED_NOTIFICATION',
  alertAheadSeconds = 1,
  alertKeepSeconds = 2,
  alertIconSize = 50,
  alertIconOpacity = 100,
  alertFontName = "BOLD_FONT",
  alertFontStyle = "thick-outline",
  alertCustomFontName = "",
  alertFontSize = 32,
  alertOffsetX = 0,
  alertOffsetY = 0,
  alertKeyWords = '',
  alertBlackKeyWords = '',
}

--========================================
--        l
--========================================
l.controlPool = {}

l.frame = nil --TopLevelWindow#TopLevelWindow

l.showedControls = {} -- #list<Control#Control>

-- Active alerts: alert objects created by rules
-- Each alert: { rule, action, ability, startTime, control }
l.activeAlerts = {} -- #list<Alert>

l.soundChoices = {} -- #list<#number>
for k,v in pairs(SOUNDS) do
  table.insert(l.soundChoices, k)
end
table.sort(l.soundChoices)

-- Check if ability passes whitelist/blacklist filters
l.shouldShowAbility -- #(Models#Ability:ability)->(#boolean)
= function(ability)
  local keywords = l.getSavedVars().alertKeyWords:lower()
  local checked = false
  local checkOk = false
  for line in keywords:gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line and line:len()>0 then
      checked = true
      if line:match('^%d+$') then
        checkOk = tonumber(line) == ability.id
      else
        checkOk = zo_strformat("<<1>>", ability.name):lower():find(line,1,true)
      end
      if checkOk then break end
    end
  end
  if checked and not checkOk then
    if addon.debugEnabled(DSS_ALERT_SKIP, ability.name) then
      addon.debug("[LSw]skipped by whitelist: %s(%d)", ability.name, ability.id)
    end
    return false
  end
  keywords = l.getSavedVars().alertBlackKeyWords:lower()
  for line in keywords:gmatch("[^\r\n]+") do
    line = line:match "^%s*(.-)%s*$"
    if line and line:len()>0 then
      if line:match('^%d+$') then
        if tonumber(line) == ability.id then
          if addon.debugEnabled(DSS_ALERT_SKIP, ability.name) then
            addon.debug("[LSb]skipped by blacklist id: %s(%d)", ability.name, ability.id)
          end
          return false
        end
      end
      if zo_strformat("<<1>>", ability.name):lower():find(line,1,true) then
        if addon.debugEnabled(DSS_ALERT_SKIP, ability.name) then
          addon.debug("[LSb]skipped by blacklist name: %s(%d)", ability.name, ability.id)
        end
        return false
      end
    end
  end
  return true
end

-- Show alert UI for an alert object
l.showAlert -- #(Alert:alert)->()
= function(alert)
  if alert.control then return end -- already shown

  local savedVars = l.getSavedVars()
  local ability = alert.ability

  if addon.debugEnabled(DSS_ALERT_SHOW, ability.name) then
    addon.debug("[L+]showing alert: %s(%d) @%.2f", ability.name, ability.id, alert.startTime/1000)
  end
  if savedVars.alertPlaySound then PlaySound(SOUNDS[savedVars.alertSoundName]) end
  local control = l.retrieveControl()
  local fontstr = (zhFlags[GetCVar("language.2")] and "EsoZH/fonts/univers67.otf" or ("$("..savedVars.alertFontName..")")) .."|"..savedVars.alertFontSize.."|"..savedVars.alertFontStyle
  control.label:SetFont(fontstr)

  control.label:SetText(savedVars.alertIconOnly and '' or zo_strformat('<<C:1>>',ability.showName))
  control.icon:SetTexture(ability.icon)
  control:SetAnchor(BOTTOMLEFT, GuiRoot, CENTER, -150 + savedVars.alertOffsetX, -150 + savedVars.alertOffsetY)
  control:SetHidden(false)
  control.ability = ability
  control.startTime = alert.startTime
  for i,v in ipairs(l.showedControls) do
    local _, _, _, _, offsetX, offsetY = v:GetAnchor(0)
    v:ClearAnchors()
    v:SetAnchor(BOTTOMLEFT, GuiRoot, CENTER, offsetX, offsetY -savedVars.alertIconSize-10)
  end
  table.insert(l.showedControls,control)

  -- link control to alert
  alert.control = control

  -- set timeout to hide control (alert may be removed earlier by rule)
  zo_callLater(
    function()
      l.returnControl(control)
    end,
    savedVars.alertKeepSeconds*1000
  )
end

--========================================
--        Alert Rules
--========================================

-- Shared detection: is action in instant/ready-to-trigger state?
l.isActionInstant --#(Models#Action:action)->(#boolean)
= function(action)
  local stackEffect = action:getStackEffect()
  local stackCount = stackEffect and stackEffect.stackCount or 0
  -- check fakeInstant i.e. Crystal Fragment
  if action.fake and stackCount == 0 then return true end
  -- check bound armaments at stack 4
  if stackCount == 4 and action.ability.icon:find('bound_armament',35,true)
    and GetGameTimeMilliseconds() > action.startTime + 300 -- don't alert at the moment it being used
  then
    return true
  end
  -- check transmuteInstant i.e. Assasin's Will
  if GetGameTimeMilliseconds() > action.startTime + 300 then -- switching shouldn't happen just after performing
    local oldestAction = action:getOldest()
    local currentId = GetSlotBoundId(oldestAction.slotNum)
    local currentAbility = models.newAbility(currentId,GetSlotName(oldestAction.slotNum),'')
    if oldestAction:matchesAbility(currentAbility) then
      -- record currentId in action data
      if not action.data['alert.transmuteRefChecked'] then
        action.data['alert.transmuteRefChecked'] = true
        action.data['alert.transmuteRefId'] = currentId
      end
      if oldestAction.ability.id ~= currentId
        and action.data['alert.transmuteRefId'] ~= currentId
      then
        if stackCount <= 1 then -- i.e. Bound Armaments transmute when just getting an attack stack
          action.data['alert.transmuteRefId'] = currentId
          return false
        end
        return true
      end
    end
  end
  --
  return false
end

-- Check if action should skip common preconditions
l.shouldSkipAction --#(Models#Action:action)->(#boolean)
= function(action)
  -- check ultimate
  if action.slotNum == 8 then return true end
  -- check tick
  if action.tickEffect and action.duration==0 then return true end
  -- check action in 1/2
  if action:getStageInfo() == '1/2' then return true end
  return false
end

-- Alert rule: timeout (near expiration)
l.alertRuleTimeout = {
  name = "timeout",
  shouldAlert = function(action, alert)
    -- skip instant actions for timeout rule
    if l.isActionInstant(action) then return false end
    -- skip if duration comes from low level effect
    local duration, durSource = action:getDuration()
    if durSource == models.DUR_SOURCE_PRIORITY then
      local optEffect = action:optEffect()
      if optEffect and optEffect.levelIsLow then
        return false
      end
    end
    -- remove if action was refreshed (startTime changed)
    if alert and action.startTime ~= alert.startTime then return false end
    -- check if near expiration (or no longer near if alert exists)
    local aheadTime = l.getSavedVars().alertAheadSeconds * 1000
    return action:getFullEndTime() - aheadTime < GetGameTimeMilliseconds()
  end,
}

-- Alert rule: instant (ready to trigger)
l.alertRuleInstant = {
  name = "instant",
  shouldAlert = function(action, alert)
    return l.isActionInstant(action)
  end,
}

-- Alert rule: Power Lash Guide
l.alertRulePowerLash = {
  name = "powerLash",
  shouldAlert -- (Models#Action:action, #any:alert)->(#boolean)
   = function(action, alert)
    local stackEffect = action:getStackEffect() -- Models#Effect
    return stackEffect and stackEffect.ability.id == POWER_LASH_GUIDE_ABILITY_ID
  end,
}

l.alertRules = {
  l.alertRuleTimeout,
  l.alertRuleInstant,
  l.alertRulePowerLash,
}

-- Debug log throttle: prevent repeated logs within interval
local logThrottleInterval = 1 -- seconds
local logThrottleMap = {} -- #map<#string,#number> key -> lastLogTime

l.shouldLog -- #(#string:key)->(#boolean)
= function(key)
  local now = GetGameTimeSeconds()
  local lastTime = logThrottleMap[key]
  if lastTime and now - lastTime < logThrottleInterval then
    return false
  end
  logThrottleMap[key] = now
  return true
end

-- Find active alert for action and rule
l.findActiveAlert --#(Models#Action:action, #table:rule)->(Alert)
= function(action, rule)
  for _, alert in ipairs(l.activeAlerts) do
    if alert.rule.name == rule.name and alert.action == action then
      return alert
    end
  end
  return nil
end

-- Find alert by control
l.findAlertByControl --#(Control:control)->(Alert)
= function(control)
  for _, alert in ipairs(l.activeAlerts) do
    if alert.control == control then
      return alert
    end
  end
  return nil
end

-- Create a new alert for action and rule
l.createAlert --#(Models#Action:action, #table:rule)->(Alert)
= function(action, rule)
  local showAbility = action.ability
  local mutantId = GetSlotBoundId(action.slotNum, action.hotbarCategory) --#number
  if GetSlotType(action.slotNum, action.hotbarCategory) == ACTION_TYPE_CRAFTED_ABILITY then
    mutantId = GetAbilityIdForCraftedAbilityId(mutantId)
  end
  if showAbility.id ~= mutantId then
    local slotAbility = models.newAbility(mutantId, GetSlotName(action.slotNum), GetSlotTexture(action.slotNum))
    if action:matchesAbility(slotAbility) then
      slotAbility.id = action.ability.id
      showAbility = slotAbility
    end
  end

  -- filter by whitelist/blacklist
  if not l.shouldShowAbility(showAbility) then
    return nil
  end

  local alert = {
    rule = rule,
    action = action,
    ability = showAbility,
    startTime = action.startTime,
    control = nil,
  }
  table.insert(l.activeAlerts, alert)

  if addon.debugEnabled(DSS_ALERT_RULE, action.ability.name) then
    addon.debug("[LR!]rule '%s' triggered for: %s", rule.name, action:toLogString_Short())
  end

  -- show UI immediately
  l.showAlert(alert)

  return alert
end

-- Remove an alert
l.removeAlert --#(Alert:alert, #string:reason)->()
= function(alert, reason)
  -- hide control if associated
  if alert.control then
    if addon.debugEnabled(DSS_ALERT_REMOVE, alert.ability.name) then
      addon.debug("[L-]alert removed by %s: %s(%d)", reason, alert.ability.name, alert.ability.id)
    end
    alert.control:SetHidden(true)
    -- control will be returned to pool via timeout or orphan check
  end

  -- remove from activeAlerts
  for i, a in ipairs(l.activeAlerts) do
    if a == alert then
      table.remove(l.activeAlerts, i)
      break
    end
  end
end

l.checkAction --#(Models#Action:action)->()
= function(action)
  -- common preconditions
  if l.shouldSkipAction(action) then
    if addon.debugEnabled(DSS_ALERT_SKIP, action.ability.name) then
      local key = "LSp/" .. action.ability.name
      if l.shouldLog(key) then
        addon.debug("[LSp]skipped by preconditions: %s", action:toLogString_Short())
      end
    end
    return
  end

  -- check each rule
  for _, rule in ipairs(l.alertRules) do
    local existingAlert = l.findActiveAlert(action, rule)
    local shouldAlert = rule.shouldAlert(action, existingAlert)

    if existingAlert then
      -- alert exists but shouldAlert is false -> remove it
      if not shouldAlert then
        l.removeAlert(existingAlert, "rule")
      end
      -- if shouldAlert is true, keep the existing alert (no-op)
    else
      -- no alert exists
      if shouldAlert then
        l.createAlert(action, rule)
      end
    end
  end
end

l.findSoundIndex -- #(#string:name)->(#number)
= function(name)
  for key, var in ipairs(l.soundChoices) do
    if var==name then return key end
  end
  return -1
end

l.getSavedVars -- #()->(#AlertSavedVars)
= function()
  return settings.getSavedVars()
end

local lastLog = 0
addon.alertLogCntValve = 20
addon.alertLogInterval = 300
-- /script ActionDurationReminder.alertLogCntValve=0 ActionDurationReminder.alertLogInterval=5
-- /script ActionDurationReminder.alertLogCntValve=20 ActionDurationReminder.alertLogInterval=300

-- Remove alerts whose action no longer exists
l.cleanupStaleAlerts -- #(map<#number,Models#Action>:snActionMap)->()
= function(snActionMap)
  local toRemove = {} -- #list<Alert>
  for _, alert in ipairs(l.activeAlerts) do
    local actionExists = false
    for _, a in pairs(snActionMap) do
      if a == alert.action then
        actionExists = true
        break
      end
    end
    if not actionExists then
      table.insert(toRemove, alert)
    end
  end
  for _, alert in ipairs(toRemove) do
    l.removeAlert(alert, "action removed")
  end
end

-- Check orphaned controls (controls without active alerts)
l.checkOrphanedControls -- #()->()
= function()
  for _, control in ipairs(l.showedControls) do
    if not control:IsHidden() then
      local alert = l.findAlertByControl(control)
      if not alert then
        if addon.debugEnabled(DSS_ALERT_HIDE, control.ability and control.ability.name) then
          addon.debug("[L-]hiding orphaned control: %s(%d)", control.ability and control.ability.name or '?', control.ability and control.ability.id or 0)
        end
        control:SetHidden(true)
      end
    end
  end
end

l.onCoreUpdate -- #()->()
= function()
  local savedVars = l.getSavedVars()
  if not savedVars.alertEnabled then return end

  local snActionMap = core.getSnActionMap()
  local cntMap = {} -- #map<#number,#number>
  local maxSnMap = {} -- #map<#number, #number>

  -- 1. Check actions for new alerts and update existing alerts
  for sn,action in pairs(snActionMap) do
    l.checkAction(action)
    cntMap[action.ability.id] = (cntMap[action.ability.id] or 0) + 1
    maxSnMap[action.ability.id] = math.max(cntMap[action.ability.id] or 0, action.sn)
  end

  -- 2. Remove alerts whose action no longer exists
  l.cleanupStaleAlerts(snActionMap)

  -- 3. Check orphaned controls
  l.checkOrphanedControls()

  local now = GetGameTimeSeconds()
  -- TODO move this check into core
  if now - lastLog > addon.alertLogInterval then
    local didLog = false
    for id, cnt in pairs(cntMap) do
      if cnt > addon.alertLogCntValve then
        didLog = true
        if savedVars.addonLogTrackedEffectsInChat then
          df("[!ADR!] |t24:24:%s|t%s(%d) #%d", GetAbilityIcon(id), GetAbilityName(id), id, cnt)
        end
        -- also remove potential leaked actions
        local toRemove = {} --#list<Models#Action>
        for sn,action in pairs(snActionMap) do
          if action.ability.id == id and sn<maxSnMap[id] then toRemove[#toRemove+1] =action end
        end
        for key, var in ipairs(toRemove) do
          core.l.removeAction(var)
        end
      end
    end
    if didLog then lastLog = now end
  end
end

l.openAlertFrame -- #()->()
= function()
  local savedVars = l.getSavedVars()
  if not l.frame then
    l.frame = WINDOW_MANAGER:CreateTopLevelWindow()
    l.frame:SetDimensions(350, 70)
    l.frame:SetMouseEnabled(true)
    l.frame:SetMovable(true)
    l.frame:SetDrawLayer(DL_COUNT)
    l.frame:SetHandler('OnMoveStop', function()
      local left = l.frame:GetLeft()
      local bottom = l.frame:GetBottom()
      local centerX,centerY = GuiRoot:GetCenter()
      savedVars.alertOffsetX = left - centerX + 150
      savedVars.alertOffsetY = bottom - centerY + 150
      zo_callLater(function()
        SetGameCameraUIMode(true)
      end, 10)
    end)
    local backdrop = WINDOW_MANAGER:CreateControl(nil, l.frame, CT_BACKDROP) --BackdropControl#BackdropControl
    backdrop:SetAnchor(TOPLEFT)
    backdrop:SetAnchor(BOTTOMRIGHT)
    backdrop:SetCenterColor(0,0,1,0.5)
    backdrop:SetEdgeTexture('',1,1,1,1)
    backdrop:SetDrawLayer(DL_COUNT)
    backdrop:SetDrawLevel(0)
    local label = WINDOW_MANAGER:CreateControl(nil, l.frame, CT_LABEL) --LabelControl#LabelControl
    label:SetFont('$(MEDIUM_FONT)|$(KB_18)|soft-shadow-thin')
    label:SetColor(1,1,1)
    label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    label:SetAnchor(CENTER)
    label:SetDrawLayer(DL_COUNT)
    label:SetDrawLevel(1)
    label:SetText('ADR Alert Frame')
    -- Close button as a top-level window so it receives mouse events independently
    local closeBtn = WINDOW_MANAGER:CreateTopLevelWindow()
    closeBtn:SetDimensions(32, 32)
    closeBtn:SetDrawLayer(DL_OVERLAY)
    closeBtn:SetMouseEnabled(true)
    closeBtn:SetMovable(false)
    closeBtn.parentFrame = l.frame -- reference for handler
    -- Use a texture for visual
    local closeTexture = closeBtn:CreateControl(nil, CT_TEXTURE)
    closeTexture:SetAnchor(CENTER)
    closeTexture:SetDimensions(24, 24)
    closeTexture:SetTexture('/esoui/art/buttons/closebutton_disabled.dds')
    closeTexture:SetDrawLayer(DL_OVERLAY)
    closeBtn.texture = closeTexture
    -- Mouse handlers
    closeBtn:SetHandler('OnMouseEnter', function()
      closeTexture:SetTexture('/esoui/art/buttons/closebutton_up.dds')
    end)
    closeBtn:SetHandler('OnMouseExit', function()
      closeTexture:SetTexture('/esoui/art/buttons/closebutton_disabled.dds')
    end)
    closeBtn:SetHandler('OnMouseDown', function()
      closeTexture:SetTexture('/esoui/art/buttons/closebutton_down.dds')
    end)
    closeBtn:SetHandler('OnMouseUp', function(self, button)
      if button == 1 then
        self.parentFrame:SetHidden(true)
        self:SetHidden(true)
      end
    end)
    l.closeBtn = closeBtn
  end
  l.frame:SetHidden(false)
  l.frame:ClearAnchors()
  l.frame:SetAnchor(BOTTOMLEFT, GuiRoot, CENTER, - 150 + savedVars.alertOffsetX, - 150 + savedVars.alertOffsetY)
  -- Position close button relative to frame
  l.closeBtn:ClearAnchors()
  l.closeBtn:SetAnchor(TOPRIGHT, l.frame, TOPRIGHT, 4, -4)
  l.closeBtn:SetHidden(false)
end



l.retrieveControl -- #()->(Control#Control)
= function()
  local savedVars = l.getSavedVars()
  if #l.controlPool >0 then
    local control = table.remove(l.controlPool,#l.controlPool)
    control.icon:SetDimensions(savedVars.alertIconSize,savedVars.alertIconSize)
    control.icon:SetAlpha(savedVars.alertIconOpacity/100.0)
    return control
  end
  local control = WINDOW_MANAGER:CreateTopLevelWindow()
  local icon = control:CreateControl(nil, CT_TEXTURE) -- TextureControl#TextureControl
  icon:SetDrawLayer(DL_CONTROLS)
  icon:SetDimensions(savedVars.alertIconSize,savedVars.alertIconSize)
  icon:SetAlpha(savedVars.alertIconOpacity/100.0)
  icon:SetAnchor(LEFT)
  control.icon = icon
  local label = control:CreateControl(nil, CT_LABEL)
  label:SetFont("ZoFontGameMedium")
  label:SetColor(1,1,1)
  label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
  label:SetAnchor(LEFT, icon, RIGHT, 10, 0)
  label:SetDrawLayer(DL_TEXT)
  control.label = label
  return control
end

l.returnControl -- #(Control#Control:control)->()
= function(control)
  for key, var in ipairs(l.showedControls) do
    if var == control then
      table.remove(l.showedControls,key)
    end
  end
  if addon.debugEnabled(DSS_ALERT_HIDE, control.ability and control.ability.name) then
    addon.debug("[L-]hiding alert (timeout): %s(%d)", control.ability and control.ability.name or '?', control.ability and control.ability.id or 0)
  end
  control:SetHidden(true)
  control:ClearAnchors()
  table.insert(l.controlPool, control)

  -- clear alert's control reference if linked
  local alert = l.findAlertByControl(control)
  if alert then
    alert.control = nil
  end
end

--========================================
--        register
--========================================
addon.register("Alert#M", m)

-- Register Alert debug switches
addon.registerDebugSwitch(DS_ALERT, "Alert Debug")
addon.registerDebugSubSwitch(DSS_ALERT_SHOW, 'Alert Show [L+]', 'Log when alerts are shown')
addon.registerDebugSubSwitch(DSS_ALERT_HIDE, 'Alert Hide [L-]', 'Log when alerts are hidden')
addon.registerDebugSubSwitch(DSS_ALERT_SKIP, 'Alert Skip [LS*]', 'Log when alerts are skipped')
addon.registerDebugSubSwitch(DSS_ALERT_RULE, 'Alert Rule [LR*]', 'Log rule check results')
addon.registerDebugSubSwitch(DSS_ALERT_REMOVE, 'Alert Remove [L-]', 'Log when alerts are removed by rule')

addon.extend(core.EXTKEY_UPDATE, l.onCoreUpdate)

addon.extend(settings.EXTKEY_ADD_DEFAULTS, function()
  settings.addDefaults(alertSavedVarsDefaults)
end)

addon.extend(settings.EXTKEY_ADD_MENUS, function ()
  local text = addon.text
  settings.addMenuOptions({
    type = "submenu",
    name = text("Popup Alert"),
    controls = {
      {
        type = "checkbox",
        name = text("Enable Popup Alert"),
        tooltip = text("Show a popup alert before skill timer expires"),
        getFunc = function() return l.getSavedVars().alertEnabled end,
        setFunc = function(value) l.getSavedVars().alertEnabled = value end,
        width = "full",
        default = alertSavedVarsDefaults.alertEnabled,
      },  {
        type = "checkbox",
        name = text("Icon Only Mode"),
        tooltip = text("Show only the skill icon without text"),
        getFunc = function() return l.getSavedVars().alertIconOnly end,
        setFunc = function(value) l.getSavedVars().alertIconOnly = value end,
        disabled = function() return not l.getSavedVars().alertEnabled end,
        width = "full",
        default = alertSavedVarsDefaults.alertIconOnly,
      }, {
        type = "button",
        name = text("Move Popup"),
        func = function()
          SCENE_MANAGER:Hide("gameMenuInGame")
          l.openAlertFrame()
          zo_callLater(function()
            SetGameCameraUIMode(true)
          end, 10)
        end,
        width = "half",
        disabled = function() return not l.getSavedVars().alertEnabled end,
      }, {
        type = "button",
        name = text("Reset Position"),
        func = function()
          l.getSavedVars().alertOffsetX = 0
          l.getSavedVars().alertOffsetY = 0
        end,
        width = "half",
        disabled = function() return not l.getSavedVars().alertEnabled end,
      }, {
        type = "checkbox",
        name = text("Play Sound"),
        tooltip = text("Play a sound when alert appears"),
        getFunc = function() return l.getSavedVars().alertPlaySound end,
        setFunc = function(value) l.getSavedVars().alertPlaySound = value end,
        disabled = function() return not l.getSavedVars().alertEnabled end,
        width = "full",
        default = alertSavedVarsDefaults.alertPlaySound,
      }, {
        type = "slider",
        name = text("Alert Sound"),
        min = 1, max = #l.soundChoices, step = 1,
        getFunc = function() return l.findSoundIndex(l.getSavedVars().alertSoundName) end,
        setFunc = function(value) l.getSavedVars().alertSoundName = l.soundChoices[value]; PlaySound(SOUNDS[l.getSavedVars().alertSoundName]) end,
        width = "full",
        disabled = function() return not l.getSavedVars().alertPlaySound or not l.getSavedVars().alertEnabled end,
        default = l.findSoundIndex(alertSavedVarsDefaults.alertSoundName),
      }, {
        type = "button",
        name = text("Test Sound"),
        func = function()
          PlaySound(SOUNDS[l.getSavedVars().alertSoundName])
        end,
        width = "full",
        disabled = function() return not l.getSavedVars().alertPlaySound or not l.getSavedVars().alertEnabled end,
      }, {
        type = "slider",
        name = text("Alert Lead Time"),
        tooltip = text("Start showing the alert this many seconds before the skill expires"),
        min = 0, max = 3, step = 0.5,
        getFunc = function() return l.getSavedVars().alertAheadSeconds end,
        setFunc = function(value) l.getSavedVars().alertAheadSeconds = value end,
        width = "full",
        disabled = function() return not l.getSavedVars().alertEnabled end,
        default = alertSavedVarsDefaults.alertAheadSeconds,
      }, {
        type = "slider",
        name = text("Alert Duration"),
        tooltip = text("How long to display the alert"),
        min = 1, max = 18, step = 0.5,
        getFunc = function() return l.getSavedVars().alertKeepSeconds end,
        setFunc = function(value) l.getSavedVars().alertKeepSeconds = value end,
        width = "full",
        disabled = function() return not l.getSavedVars().alertEnabled end,
        default = alertSavedVarsDefaults.alertKeepSeconds,
      }, {
        type = "dropdown",
        name = text("Font Name"),
        choices = {"MEDIUM_FONT", "BOLD_FONT", "CHAT_FONT", "ANTIQUE_FONT", "HANDWRITTEN_FONT", "STONE_TABLET_FONT", "GAMEPAD_MEDIUM_FONT", "GAMEPAD_BOLD_FONT"},
        getFunc = function() return l.getSavedVars().alertFontName end,
        setFunc = function(value) l.getSavedVars().alertFontName = value end,
        disabled = function() return not l.getSavedVars().alertEnabled or l.getSavedVars().alertIconOnly end,
        width = "full",
        default = alertSavedVarsDefaults.alertFontName,
      }, {
        type = "slider",
        name = text("Font Size"),
        min = 18, max = 48, step = 2,
        getFunc = function() return l.getSavedVars().alertFontSize end,
        setFunc = function(value) l.getSavedVars().alertFontSize = value end,
        disabled = function() return not l.getSavedVars().alertEnabled or l.getSavedVars().alertIconOnly end,
        width = "full",
        default = alertSavedVarsDefaults.alertFontSize,
      },{
        type = "dropdown",
        name = text("Font Style"),
        choices = {"thick-outline","soft-shadow-thick","soft-shadow-thin"},
        getFunc = function() return l.getSavedVars().alertFontStyle end,
        setFunc = function(value) l.getSavedVars().alertFontStyle = value end,
        disabled = function() return not l.getSavedVars().alertEnabled or l.getSavedVars().alertIconOnly end,
        width = "full",
        default = alertSavedVarsDefaults.alertFontStyle,
      },{
        type = "slider",
        name = text("Icon Size"),
        tooltip = text("Size of the skill icon in the popup"),
        min = 18, max = 98, step = 2,
        getFunc = function() return l.getSavedVars().alertIconSize end,
        setFunc = function(value) l.getSavedVars().alertIconSize = value end,
        disabled = function() return not l.getSavedVars().alertEnabled end,
        width = "full",
        default = alertSavedVarsDefaults.alertIconSize,
      }, {
        type = "slider",
        name = text("Icon Opacity"),
        tooltip = text("Transparency of the skill icon"),
        min = 10, max = 100, step = 10,
        getFunc = function() return l.getSavedVars().alertIconOpacity end,
        setFunc = function(value) l.getSavedVars().alertIconOpacity = value end,
        disabled = function() return not l.getSavedVars().alertEnabled end,
        width = "full",
        default = alertSavedVarsDefaults.alertIconOpacity,
      }, {
        type = "editbox",
        name = text("Whitelist Patterns"),
        tooltip = text("Skills to show alert for. One pattern per line. Use skill name substring or numeric ability ID"),
        getFunc = function() return l.getSavedVars().alertKeyWords end,
        setFunc = function(text) l.getSavedVars().alertKeyWords = text end,
        isMultiline = true,
        isExtraWide = true,
        width = "full",
        disabled = function() return not l.getSavedVars().alertEnabled end,
        requiresReload = false,
        default = alertSavedVarsDefaults.alertKeyWords,
      },{
        type = "editbox",
        name = text("Blacklist Patterns"),
        tooltip = text("Skills to never show alert for. One pattern per line. Use skill name substring or numeric ability ID"),
        getFunc = function() return l.getSavedVars().alertBlackKeyWords end,
        setFunc = function(text) l.getSavedVars().alertBlackKeyWords = text end,
        isMultiline = true,
        isExtraWide = true,
        width = "full",
        disabled = function() return not l.getSavedVars().alertEnabled end,
        requiresReload = false,
        default = alertSavedVarsDefaults.alertBlackKeyWords,
      }}})
end)

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
local DSS_ALERT_REMOVE = {DS_ALERT, 'remove'}  -- alert removed by rule
local DSS_ALERT_CREATE = {DS_ALERT, 'create'}  -- alert created by rule

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
l.activeAlerts = {} -- #list<#Alert>

l.soundChoices = {} -- #list<#number>
for k,v in pairs(SOUNDS) do
  table.insert(l.soundChoices, k)
end
table.sort(l.soundChoices)

local disabledTimeoutAbilityIds = {
  -- flame lash
  [20816] = true,
  [20824] = true,
}
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
      addon.debug("[L^w]skipped by whitelist: %s(%d)", ability.name, ability.id)
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
            addon.debug("[L^b]skipped by blacklist id: %s(%d)", ability.name, ability.id)
          end
          return false
        end
      end
      if zo_strformat("<<1>>", ability.name):lower():find(line,1,true) then
        if addon.debugEnabled(DSS_ALERT_SKIP, ability.name) then
          addon.debug("[L^b]skipped by blacklist name: %s(%d)", ability.name, ability.id)
        end
        return false
      end
    end
  end
  return true
end

-- Show alert UI for an alert object
l.showAlert -- #(#Alert:alert)->()
= function(alert)
  if alert.control then return end -- already shown

  local savedVars = l.getSavedVars()
  local ability = alert.ability

  if addon.debugEnabled(DSS_ALERT_SHOW, ability.name) then
    addon.debug("[LS]showing alert: %s", ability:toLogString())
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
  if action.alertSkipResult ~= nil then return action.alertSkipResult end

  local skipReason = nil
  -- check ultimate
  if action.slotNum == 8 then
    skipReason='check ultimate'
  elseif  not l.shouldShowAbility(action.ability) then
    skipReason = 'filter by whitelist/blacklist'
  end
  -- filter by whitelist/blacklist
  if skipReason then
    action.alertSkipResult = true
    if addon.debugEnabled(DSS_ALERT_SKIP, action.ability.name) then
      local key = "L^p/" .. action.ability.name
      if l.shouldLog(key) then
        addon.debug("[L^p]skipped %s \n reason: %s", action:toLogString_SingleLine(), skipReason)
      end
    end
    return true
  end

  action.alertSkipResult = false
  return false
end

-- Alert rule: timeout (near expiration)
l.alertRuleTimeout
= {
  name = "Timeout",
  shouldAlert = function(action, alert)
    -- check id list
    if disabledTimeoutAbilityIds[action.ability.id] then return false, 'disabled id' end
    -- check tick
    if action.tickEffect and action.duration==0 then return false,'is tick' end
    -- check action in 1/2
    if action:getStageInfo() == '1/2' then return false,'1/2 stage' end
    -- skip instant actions for timeout rule
    if l.isActionInstant(action) then return false, "is instant" end
    -- skip channelling action
    if action.channelStartTime >0 and action.channelEndTime >0 then
      return false, "is chanelling"
    end
    -- skip if duration comes from low level effect
    local duration, durSource = action:getDuration()
    if durSource == models.DUR_SOURCE_PRIORITY then
      local optEffect = action:optEffect()
      if optEffect and optEffect.levelIsLow then
        return false, "low level opted effect"
      end
    end
    -- no duration
    if not alert and duration==0 then return false,"no duration" end

    local now = GetGameTimeMilliseconds()
    local startTime = action.startTime
    local aheadTime = l.getSavedVars().alertAheadSeconds * 1000
    local tailTime = l.getSavedVars().alertKeepSeconds*1000
    local endTime = action:getEndTime()

    -- already ended
    if not alert and endTime <= now then return false, 'already ended' end
    -- remove if action was refreshed (startTime changed)
    if alert and startTime ~= alert.startTime then return false, "action refreshed" end
    -- check if near expiration (or no longer near if alert exists)

    if now > endTime - aheadTime and now < endTime + tailTime  then
      return true, string.format("%.2f in expiration(%.2f, %.2f)",
        now/1000, (endTime - aheadTime)/1000, (endTime+tailTime)/1000)
    else
      return false, string.format("%.2f not in expiration(%.2f, %.2f)",
        now/1000, (endTime - aheadTime)/1000, (endTime+tailTime)/1000)
    end
  end,
}

-- Alert rule: crux (full cruxes to use)
l.alertRuleCrux = {
  name = "Crux",
  shouldAlert -- #(Models#Action:action, #Alert:alert)->(#boolean)
  = function(action, alert)
    if action.showCrux then
      local effect = action:getStackEffect()
      if effect and effect.stackCount == 3 then
        return true, 'enough crux'
      end
      return false, 'not enough crux'
    end
    return false, "not showing crux"
  end,
}

-- Alert rule: instant (ready to trigger)
l.alertRuleInstant = {
  name = "Instant",
  shouldAlert = function(action, alert)
    if l.isActionInstant(action) then
      return true, "is instant"
    else
      return false, "not instant"
    end
  end,
}

-- Alert rule: Power Lash Guide
l.alertRulePowerLash --
= {
  name = "PowerLash",
  shouldAlert -- #(Models#Action:action, #Alert:alert)->(#boolean, #string)
  = function(action, alert)
    local stackEffect = action:getStackEffect() -- Models#Effect
    if stackEffect and stackEffect.ability.id == models.POWER_LASH_GUIDE_ABILITY_ID then
      return true, "power lash ready"
    else
      return false, "no power lash"
    end
  end
,
}

l.alertRules = {
  l.alertRuleTimeout,
  l.alertRuleInstant,
  l.alertRulePowerLash,
  l.alertRuleCrux,
}

-- Debug log throttle: prevent repeated logs within interval
local logThrottleInterval = 1 -- seconds
local logThrottleMap = {} -- #map<#string,#number> key lastLogTime

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
l.findActiveAlert --#(Models#Action:action, #table:rule)->(#Alert)
= function(action, rule)
  for _, alert in ipairs(l.activeAlerts) do
    if alert.rule.name == rule.name and alert.action == action then
      return alert
    end
  end
  return nil
end

-- Find alert by control
l.findAlertByControl --#(#Control:control)->(#Alert)
= function(control)
  for _, alert in ipairs(l.activeAlerts) do
    if alert.control == control then
      return alert
    end
  end
  return nil
end

-- Create a new alert for action and rule
l.createAlert --#(Models#Action:action, #table:rule, #string:reason)->(#Alert)
= function(action, rule, reason)
  if addon.debugEnabled(DSS_ALERT_CREATE, action.ability.name) then
    addon.debug("[L+]rule '%s' created(%s) alert for %s", rule.name, reason or "?", action:toLogString())
  end
  local showAbility = models.newAbility(action.ability.id, action.ability.name, action.ability.icon)
  -- Only check mutant for crafted abilities (skill line abilities that can morph/transform)
  -- For normal abilities, bar swap changes the slot to a completely different skill,
  -- and we should not replace the original ability icon.
  if GetSlotType(action.slotNum, action.hotbarCategory) == ACTION_TYPE_CRAFTED_ABILITY then
    local mutantId = GetAbilityIdForCraftedAbilityId(GetSlotBoundId(action.slotNum, action.hotbarCategory))
    if showAbility.id ~= mutantId then
      local slotAbility = models.newAbility(mutantId, GetSlotName(action.slotNum), GetSlotTexture(action.slotNum))
      if action:matchesAbility(slotAbility) then
        slotAbility.id = action.ability.id
        showAbility = slotAbility
      end
    end
  end
  local stackEffect = action:getStackEffect()

  local alert = {} -- #Alert
  alert.rule = rule
  alert.action = action -- Modles#Action
  alert.ability = showAbility -- Models#Ability
  alert.startTime = action.startTime -- #number
  alert.control = nil -- #Control
  table.insert(l.activeAlerts, alert)

  -- show UI immediately
  l.showAlert(alert)
  return alert
end

-- Remove an alert
l.removeAlert --#(#Alert:alert, #string:reason)->()
= function(alert, reason)
  -- hide control if associated
  if alert.control then
    if addon.debugEnabled(DSS_ALERT_REMOVE, alert.ability.name) then
      addon.debug("[L-]alert removed by %s: %s", reason, alert.ability:toLogString())
    end
    l.returnControl(alert.control)
  end

  -- remove from activeAlerts
  for i, a in ipairs(l.activeAlerts) do
    if a == alert then
      table.remove(l.activeAlerts, i)
      break
    end
  end
end

l.removeAllAlertByAction --#(Models#Action:action, #string:reason)->()
= function(action, reason)
  -- remove from activeAlerts
  for i, a in ipairs(l.activeAlerts) do
    if a.action == action then
      l.removeAlert(a, reason)
    end
  end
end

l.checkAction --#(Models#Action:action)->()
= function(action)
  -- common static preconditions
  if l.shouldSkipAction(action) then return end

  -- check each rule
  for _, rule in ipairs(l.alertRules) do
    local existingAlert = l.findActiveAlert(action, rule)
    local shouldAlert, reason = rule.shouldAlert(action, existingAlert)

    if existingAlert then
      -- alert exists but shouldAlert is false -> remove it
      if not shouldAlert then
        l.removeAlert(existingAlert, "rule '" .. rule.name .. "': " .. reason)
      end
      -- if shouldAlert is true, keep the existing alert (no-op)
    else
      -- no alert exists
      if shouldAlert then
        l.createAlert(action, rule, reason)
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

-- Remove alerts whose action no longer exists
l.cleanupStaleAlerts -- #(#map<#number,Models#Action>:snActionMap)->()
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
          addon.debug("[LH]hiding orphaned control: %s(%d)", control.ability and control.ability.name or '?', control.ability and control.ability.id or 0)
        end
        l.returnControl(control)
      end
    end
  end
end

l.onCoreUpdate -- #()->()
= function()
  local savedVars = l.getSavedVars()
  if not savedVars.alertEnabled then return end

  local snActionMap = core.getSnActionMap()

  -- 1. Check actions for new alerts and update existing alerts
  for sn, action in pairs(snActionMap) do
    if action.newAction then
      l.removeAllAlertByAction(action, 'action renewed')
    else
      l.checkAction(action)
    end
  end

  -- 2. Remove alerts whose action no longer exists
  l.cleanupStaleAlerts(snActionMap)

  -- 3. Check orphaned controls
  l.checkOrphanedControls()
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
    backdrop:SetCenterColor(0.2, 0.2, 0.2, 0.6)
    backdrop:SetEdgeTexture('/esoui/art/chatwindow/chat_bg_edge.dds', 256, 256, 32)
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
  -- clear alert's control reference if linked
  local alert = l.findAlertByControl(control)
  if alert then
    alert.control = nil
  end
  for key, var in ipairs(l.showedControls) do
    if var == control then
      table.remove(l.showedControls,key)
    end
  end
  control:SetHidden(true)
  control:ClearAnchors()
  table.insert(l.controlPool, control)

end

--========================================
--        register
--========================================
addon.register("Alert#M", m)

-- Register Alert debug switches
addon.registerDebugSwitch(DS_ALERT, "Alert Debug")
addon.registerDebugSubSwitch(DSS_ALERT_SHOW, 'Alert Show [LS]', 'Log when alerts are shown')
addon.registerDebugSubSwitch(DSS_ALERT_HIDE, 'Alert Hide [LH]', 'Log when alerts are hidden')
addon.registerDebugSubSwitch(DSS_ALERT_SKIP, 'Alert Skip [L^]', 'Log when alerts are skipped')
addon.registerDebugSubSwitch(DSS_ALERT_REMOVE, 'Alert Remove [L-]', 'Log when alerts are removed by rule')
addon.registerDebugSubSwitch(DSS_ALERT_CREATE, 'Alert Create [L+]', 'Log when alerts are triggered by rule')

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

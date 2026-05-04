--========================================
--        Chat Alert Module
--========================================
-- To reset welcome prompt for testing, run in game:
--   /script ActionDurationReminder.load("ChatAlert#M").resetWelcomePrompt(); ReloadUI()
--========================================
--        vars
--========================================
local addon = ActionDurationReminder -- Addon#M
local settings = addon.load("Settings#M")
local l = {} -- #L
local m = {l=l} -- #M

local DS_CHATALERT = "chatalert" -- debug switch for chat alert

local DSS_CHATALERT_SHOW = {DS_CHATALERT, 'show'}   -- chat alert shown [KS]
local DSS_CHATALERT_HIDE = {DS_CHATALERT, 'hide'}   -- chat alert hidden [KH]
local DSS_CHATALERT_SKIP = {DS_CHATALERT, 'skip'}   -- chat alert skipped [K^]

---
--@type ChatAlertSavedVars
local chatAlertSavedVarsDefaults = {
  chatAlertEnabled = true,
  chatAlertDurationSeconds = 3,
  chatAlertMaxAlerts = 5,
  chatAlertChannelParty = true,
  chatAlertChannelSay = false,
  chatAlertChannelWhisper = false,
  chatAlertShowUserId = true,
  chatAlertChannelGuild = false,
  chatAlertOffsetX = 0,
  chatAlertOffsetY = 150,
  chatAlertFontName = "MEDIUM_FONT",
  chatAlertFontSize = 40,
  chatAlertFontStyle = "soft-shadow-thin",
  chatAlertPlaySound = false,
  chatAlertSoundName = 'NEW_TIMED_NOTIFICATION',
  chatAlertOnlyInCombat = true,
  chatAlertMaxMessageLength = 100,
  chatAlertPromptShown = false,
}

--========================================
--        l
--========================================
l.controlPool = {}
l.showedControls = {} -- #list<Control#Control>
l.activeAlerts = {}   -- #list<#ChatAlert>  each: { channelId, fromName, text, control, timerId }
l.inCombat = false
l.frame = nil
l.closeBtn = nil
l.nextUpdateId = 1

l.soundChoices = {}
for k,v in pairs(SOUNDS) do
  table.insert(l.soundChoices, k)
end
table.sort(l.soundChoices)

l.findSoundIndex -- #(#string:name)->(#number)
= function(name)
  for key, var in ipairs(l.soundChoices) do
    if var == name then return key end
  end
  return -1
end

l.getSavedVars -- #()->(#ChatAlertSavedVars)
= function()
  return settings.getSavedVars()
end

--========================================
--        control pool
--========================================
l.retrieveControl -- #()->(Control#Control)
= function()
  if #l.controlPool > 0 then
    return table.remove(l.controlPool, #l.controlPool)
  end
  local control = WINDOW_MANAGER:CreateTopLevelWindow()
  control:SetClampedToScreen(true)
  -- Semi-transparent backdrop for readability
  local backdrop = WINDOW_MANAGER:CreateControl(nil, control, CT_BACKDROP)
  backdrop:SetAnchor(TOPLEFT, nil, TOPLEFT, -4, -2)
  backdrop:SetAnchor(BOTTOMRIGHT, nil, BOTTOMRIGHT, 4, 2)
  backdrop:SetCenterColor(0.1, 0.1, 0.1, 0.4)
  backdrop:SetEdgeColor(0, 0, 0, 0)
  backdrop:SetDrawLayer(DL_BACKGROUND)
  control.backdrop = backdrop
  -- Countdown progress bar (shrinks from right to left)
  local cooldownBar = WINDOW_MANAGER:CreateControl(nil, control, CT_BACKDROP)
  cooldownBar:SetCenterColor(0.3, 0.3, 0.3, 0.5)
  cooldownBar:SetEdgeColor(0, 0, 0, 0)
  cooldownBar:SetDrawLayer(DL_BACKGROUND)
  cooldownBar:SetHidden(true)
  control.cooldownBar = cooldownBar
  -- Sender name label (bold, light blue)
  local senderLabel = control:CreateControl(nil, CT_LABEL)
  senderLabel:SetColor(0.6, 0.8, 1.0)
  senderLabel:SetAnchor(LEFT, nil, LEFT, 4, 0)
  senderLabel:SetDrawLayer(DL_TEXT)
  control.senderLabel = senderLabel
  -- Message text label (white, after sender)
  local label = control:CreateControl(nil, CT_LABEL)
  label:SetColor(1, 1, 1)
  label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
  label:SetAnchor(TOPLEFT, senderLabel, TOPRIGHT, 6, 0)
  label:SetDrawLayer(DL_TEXT)
  label:SetWrapMode(TEXT_WRAP_MODE_WORD_WRAP)
  control.label = label
  return control
end

l.returnControl -- #(Control#Control:control)->()
= function(control)
  control.timerId = nil
  if control.updateId then
    EVENT_MANAGER:UnregisterForUpdate(addon.name.."_ChatAlertBar"..control.updateId)
    control.updateId = nil
  end
  if control.cooldownBar then
    control.cooldownBar:SetHidden(true)
  end
  for key, var in ipairs(l.showedControls) do
    if var == control then
      table.remove(l.showedControls, key)
    end
  end
  control:SetHidden(true)
  control:ClearAnchors()
  table.insert(l.controlPool, control)
end

--========================================
--        display
--========================================
l.repositionControls -- #()->()
= function()
  local savedVars = l.getSavedVars()
  local yOffset = 0
  for i, control in ipairs(l.showedControls) do
    local height = control:GetHeight()
    control:ClearAnchors()
    control:SetAnchor(BOTTOMLEFT, GuiRoot, CENTER,
      -150 + savedVars.chatAlertOffsetX,
      -150 + savedVars.chatAlertOffsetY - yOffset)
    yOffset = yOffset + height + 4
  end
end

l.showChatAlert -- #(#number:channelId, #string:fromName, #string:text)->()
= function(channelId, fromName, text)
  local savedVars = l.getSavedVars()

  -- Enforce max concurrent alerts: remove oldest if at limit
  while #l.showedControls >= savedVars.chatAlertMaxAlerts do
    l.returnControl(l.showedControls[1])
    if #l.activeAlerts > 0 then
      table.remove(l.activeAlerts, 1)
    end
  end

  if addon.debugEnabled(DSS_CHATALERT_SHOW, fromName) then
    addon.debug("[KS]showing chat alert: %s: %s", fromName, text)
  end

  if savedVars.chatAlertPlaySound then
    PlaySound(SOUNDS[savedVars.chatAlertSoundName])
  end

  local control = l.retrieveControl()
  local fontstr = ("$("..savedVars.chatAlertFontName..")")
    .."|"..savedVars.chatAlertFontSize.."|"..savedVars.chatAlertFontStyle
  control.label:SetFont(fontstr)
  control.senderLabel:SetFont(fontstr)

  control.senderLabel:SetText(fromName .. ":")
  control.label:SetText(text)

  -- Set max width for wrapping (in pixels)
  local maxWidth = 500
  control.label:SetDimensionConstraints(0, 0, maxWidth, 0)

  control:SetAnchor(BOTTOMLEFT, GuiRoot, CENTER,
    -150 + savedVars.chatAlertOffsetX,
    -150 + savedVars.chatAlertOffsetY)
  control:SetHidden(false)

  -- Calculate actual dimensions after text is set
  local lineHeight = savedVars.chatAlertFontSize + 4
  local textHeight = control.label:GetTextHeight()
  local numLines = math.ceil(textHeight / lineHeight)
  local actualHeight = math.max(lineHeight, textHeight + 4)
  local senderWidth = control.senderLabel:GetTextWidth() + 10
  local textWidth = math.min(control.label:GetTextWidth() + 10, maxWidth)
  local fullWidth = senderWidth + textWidth + 10
  control:SetDimensions(fullWidth, actualHeight)

  -- Position sender label vertically centered for multi-line
  control.senderLabel:ClearAnchors()
  if numLines > 1 then
    control.senderLabel:SetAnchor(TOPLEFT, nil, TOPLEFT, 4, 2)
  else
    control.senderLabel:SetAnchor(LEFT, nil, LEFT, 4, 0)
  end
  control.label:ClearAnchors()
  control.label:SetAnchor(TOPLEFT, control.senderLabel, TOPRIGHT, 6, 0)

  -- Start countdown bar (shrinks from right to left)
  local durationMs = savedVars.chatAlertDurationSeconds * 1000
  local startTime = GetFrameTimeSeconds()
  if control.cooldownBar then
    control.cooldownBar:ClearAnchors()
    control.cooldownBar:SetAnchor(TOPLEFT, nil, TOPLEFT, 0, 0)
    control.cooldownBar:SetDimensions(fullWidth, actualHeight)
    control.cooldownBar:SetHidden(false)
  end

  -- Update countdown bar every frame
  local updateId = l.nextUpdateId
  l.nextUpdateId = l.nextUpdateId + 1
  control.updateId = updateId
  local function updateBar()
    if not control.timerId then return end
    if control.cooldownBar and not control:IsHidden() then
      local elapsed = (GetFrameTimeSeconds() - startTime) * 1000
      local remaining = durationMs - elapsed
      if remaining <= 0 then
        control.cooldownBar:SetDimensions(0, actualHeight)
      else
        local progress = remaining / durationMs
        control.cooldownBar:SetDimensions(fullWidth * progress, actualHeight)
      end
    end
  end
  EVENT_MANAGER:RegisterForUpdate(addon.name.."_ChatAlertBar"..updateId, 0, updateBar)

  -- Shift existing alerts upward
  local shiftAmount = actualHeight + 4
  for i, v in ipairs(l.showedControls) do
    local _, _, _, _, offsetX, offsetY = v:GetAnchor(0)
    v:ClearAnchors()
    v:SetAnchor(BOTTOMLEFT, GuiRoot, CENTER, offsetX, offsetY - shiftAmount)
  end

  table.insert(l.showedControls, control)

  local alert = {
    channelId = channelId,
    fromName = fromName,
    text = text,
    control = control,
  }
  table.insert(l.activeAlerts, alert)

  -- Auto-hide timer
  control.timerId = true
  zo_callLater(function()
    if not control.timerId then return end
    control.timerId = nil
    if control.updateId then
      EVENT_MANAGER:UnregisterForUpdate(addon.name.."_ChatAlertBar"..control.updateId)
      control.updateId = nil
    end
    if addon.debugEnabled(DSS_CHATALERT_HIDE, fromName) then
      addon.debug("[KH]auto-hid chat alert: %s", fromName)
    end
    l.returnControl(control)
    for i, a in ipairs(l.activeAlerts) do
      if a.control == control then
        table.remove(l.activeAlerts, i)
        break
      end
    end
    l.repositionControls()
  end, savedVars.chatAlertDurationSeconds * 1000)
end

l.hideAllAlerts -- #()->()
= function()
  while #l.showedControls > 0 do
    l.returnControl(l.showedControls[1])
  end
  l.activeAlerts = {}
end

--========================================
--        chat event
--========================================

l.onChatMessageChannel -- #(#number:eventCode,#MsgChannelType:channelType,#string:fromName,#string:text,#boolean:isCustomerService,#string:fromDisplayName)->()
= function(eventCode, channelType, fromName, text, isCustomerService, fromDisplayName)
  local savedVars = l.getSavedVars()
  if not savedVars.chatAlertEnabled then return end

  -- Filter by channel
  local channelAllowed = false
  if channelType == CHAT_CHANNEL_PARTY and savedVars.chatAlertChannelParty then
    channelAllowed = true
  elseif channelType == CHAT_CHANNEL_SAY and savedVars.chatAlertChannelSay then
    channelAllowed = true
  elseif channelType == CHAT_CHANNEL_WHISPER and savedVars.chatAlertChannelWhisper then
    channelAllowed = true
  elseif (channelType == CHAT_CHANNEL_GUILD_1 or channelType == CHAT_CHANNEL_GUILD_2
       or channelType == CHAT_CHANNEL_GUILD_3 or channelType == CHAT_CHANNEL_GUILD_4
       or channelType == CHAT_CHANNEL_GUILD_5)
       and savedVars.chatAlertChannelGuild then
    channelAllowed = true
  end
  if not channelAllowed then
    if addon.debugEnabled(DSS_CHATALERT_SKIP, "channel") then
      addon.debug("[K^]skipped chat alert: channel %d not enabled", channelType)
    end
    return
  end

  -- Filter by combat state
  if savedVars.chatAlertOnlyInCombat and not l.inCombat then
    if addon.debugEnabled(DSS_CHATALERT_SKIP, "combat") then
      addon.debug("[K^]skipped chat alert: not in combat")
    end
    return
  end

  if isCustomerService then return end

  -- Trim message length
  if #text > savedVars.chatAlertMaxMessageLength then
    text = text:sub(1, savedVars.chatAlertMaxMessageLength) .. "..."
  end

  -- Determine display name
  local displayName
  if savedVars.chatAlertShowUserId then
    displayName = fromDisplayName
  else
    displayName = fromName:gsub("|c%x%x%x%x%x%x", ""):gsub("|r", "")
    displayName = zo_strformat("<<1>>", displayName)
  end

  l.showChatAlert(channelType, displayName, text)
end

--========================================
--        combat state
--========================================
l.onPlayerCombatState -- #(#number:eventCode, #boolean:inCombat)->()
= function(eventCode, inCombat)
  l.inCombat = inCombat
  if not inCombat and l.getSavedVars().chatAlertOnlyInCombat then
    l.hideAllAlerts()
  end
end

--========================================
--        positioning frame
--========================================
l.openChatAlertFrame -- #()->()
= function()
  local savedVars = l.getSavedVars()
  if not l.frame then
    l.frame = WINDOW_MANAGER:CreateTopLevelWindow()
    l.frame:SetDimensions(400, 24)
    l.frame:SetMouseEnabled(true)
    l.frame:SetMovable(true)
    l.frame:SetDrawLayer(DL_COUNT)
    l.frame:SetHandler('OnMoveStop', function()
      local left = l.frame:GetLeft()
      local bottom = l.frame:GetBottom()
      local centerX, centerY = GuiRoot:GetCenter()
      savedVars.chatAlertOffsetX = left - centerX + 150
      savedVars.chatAlertOffsetY = bottom - centerY + 150
      zo_callLater(function()
        SetGameCameraUIMode(true)
      end, 10)
    end)
    local backdrop = WINDOW_MANAGER:CreateControl(nil, l.frame, CT_BACKDROP)
    backdrop:SetAnchor(TOPLEFT)
    backdrop:SetAnchor(BOTTOMRIGHT)
    backdrop:SetCenterColor(0.2, 0.2, 0.2, 0.6)
    backdrop:SetEdgeTexture('/esoui/art/chatwindow/chat_bg_edge.dds', 256, 256, 32)
    backdrop:SetDrawLayer(DL_COUNT)
    backdrop:SetDrawLevel(0)
    local label = WINDOW_MANAGER:CreateControl(nil, l.frame, CT_LABEL)
    label:SetFont('$(MEDIUM_FONT)|$(KB_18)|soft-shadow-thin')
    label:SetColor(1, 1, 1)
    label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    label:SetAnchor(CENTER)
    label:SetDrawLayer(DL_COUNT)
    label:SetDrawLevel(1)
    label:SetText(addon.text("ADR Chat Alert Frame"))
    -- Close button
    local closeBtn = WINDOW_MANAGER:CreateTopLevelWindow()
    closeBtn:SetDimensions(32, 32)
    closeBtn:SetDrawLayer(DL_OVERLAY)
    closeBtn:SetMouseEnabled(true)
    closeBtn:SetMovable(false)
    closeBtn.parentFrame = l.frame
    local closeTexture = closeBtn:CreateControl(nil, CT_TEXTURE)
    closeTexture:SetAnchor(CENTER)
    closeTexture:SetDimensions(24, 24)
    closeTexture:SetTexture('/esoui/art/buttons/closebutton_disabled.dds')
    closeTexture:SetDrawLayer(DL_OVERLAY)
    closeBtn.texture = closeTexture
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
  l.frame:SetAnchor(BOTTOMLEFT, GuiRoot, CENTER,
    -150 + savedVars.chatAlertOffsetX,
    -150 + savedVars.chatAlertOffsetY)
  l.closeBtn:ClearAnchors()
  l.closeBtn:SetAnchor(TOPRIGHT, l.frame, TOPRIGHT, 4, -4)
  l.closeBtn:SetHidden(false)
end

--========================================
--        first-run prompt
--========================================
l.registerWelcomeDialog -- #()->()
= function()
  ESO_Dialogs["ADR_CHAT_ALERT_WELCOME"] =
  {
    title =
    {
      text = addon.text("Chat Alert"),
    },
    mainText =
    {
      text = addon.text("ADR has a new Chat Alert feature! During combat, group chat messages often go unnoticed in the chat window. Chat Alert will display them as popup alerts on screen so you never miss important callouts.\n\nP.S. Yes, this is from 2026, but I promise it's the good CODE. — @Cloudor"),
    },
    mustChoose = true,
    buttons =
    {
      [1] =
      {
        text = addon.text("Enable"),
        callback = function(dialog)
          l.getSavedVars().chatAlertEnabled = true
          l.getSavedVars().chatAlertPromptShown = true
        end,
      },
      [2] =
      {
        text = addon.text("Disable"),
        callback = function(dialog)
          l.getSavedVars().chatAlertEnabled = false
          l.getSavedVars().chatAlertPromptShown = true
        end,
      },
    },
  }
end

l.showWelcomePrompt -- #()->()
= function()
  local savedVars = l.getSavedVars()
  if savedVars.chatAlertPromptShown then return end
  l.registerWelcomeDialog()
  ZO_Dialogs_ShowDialog("ADR_CHAT_ALERT_WELCOME")
end

--========================================
--        start
--========================================
l.onStart -- #()->()
= function()
  EVENT_MANAGER:RegisterForEvent(addon.name.."_ChatAlert", EVENT_CHAT_MESSAGE_CHANNEL, l.onChatMessageChannel)
  EVENT_MANAGER:RegisterForEvent(addon.name.."_ChatAlert", EVENT_PLAYER_COMBAT_STATE, l.onPlayerCombatState)
  l.inCombat = IsUnitInCombat('player')
  l.showWelcomePrompt()
end

--========================================
--        register
--========================================
-- Public method to reset welcome prompt flag (for testing first-run experience)
m.resetWelcomePrompt = function()
  l.getSavedVars().chatAlertPromptShown = false
end

addon.register("ChatAlert#M", m)

addon.registerDebugSwitch(DS_CHATALERT, "Chat Alert Debug")
addon.registerDebugSubSwitch(DSS_CHATALERT_SHOW, 'Chat Alert Show [KS]', 'Log when chat alerts are shown')
addon.registerDebugSubSwitch(DSS_CHATALERT_HIDE, 'Chat Alert Hide [KH]', 'Log when chat alerts are hidden')
addon.registerDebugSubSwitch(DSS_CHATALERT_SKIP, 'Chat Alert Skip [K^]', 'Log when chat alerts are skipped')

addon.hookStart(l.onStart)

addon.extend(settings.EXTKEY_ADD_DEFAULTS, function()
  settings.addDefaults(chatAlertSavedVarsDefaults)
end)

addon.extend(settings.EXTKEY_ADD_MENUS, function()
  local text = addon.text
  settings.addMenuOptions({
    type = "submenu",
    name = text("Chat Alert"),
    controls = {
      {
        type = "checkbox",
        name = text("Enable Chat Alert"),
        tooltip = text("Show group chat messages as popup alerts during combat"),
        getFunc = function() return l.getSavedVars().chatAlertEnabled end,
        setFunc = function(value) l.getSavedVars().chatAlertEnabled = value end,
        width = "full",
        default = chatAlertSavedVarsDefaults.chatAlertEnabled,
      }, {
        type = "checkbox",
        name = text("Only Show In Combat"),
        tooltip = text("Only display chat alerts while in combat"),
        getFunc = function() return l.getSavedVars().chatAlertOnlyInCombat end,
        setFunc = function(value) l.getSavedVars().chatAlertOnlyInCombat = value end,
        disabled = function() return not l.getSavedVars().chatAlertEnabled end,
        width = "full",
        default = chatAlertSavedVarsDefaults.chatAlertOnlyInCombat,
      }, {
        type = "checkbox",
        name = text("Show User ID"),
        tooltip = text("Show @UserID instead of character name for message sender"),
        getFunc = function() return l.getSavedVars().chatAlertShowUserId end,
        setFunc = function(value) l.getSavedVars().chatAlertShowUserId = value end,
        disabled = function() return not l.getSavedVars().chatAlertEnabled end,
        width = "full",
        default = chatAlertSavedVarsDefaults.chatAlertShowUserId,
      }, {
        type = "checkbox",
        name = text("Party Channel"),
        tooltip = text("Show messages from party chat"),
        getFunc = function() return l.getSavedVars().chatAlertChannelParty end,
        setFunc = function(value) l.getSavedVars().chatAlertChannelParty = value end,
        width = "half",
        default = chatAlertSavedVarsDefaults.chatAlertChannelParty,
        disabled = function() return not l.getSavedVars().chatAlertEnabled end,
      }, {
        type = "checkbox",
        name = text("Say Channel"),
        tooltip = text("Show messages from say chat"),
        getFunc = function() return l.getSavedVars().chatAlertChannelSay end,
        setFunc = function(value) l.getSavedVars().chatAlertChannelSay = value end,
        width = "half",
        default = chatAlertSavedVarsDefaults.chatAlertChannelSay,
        disabled = function() return not l.getSavedVars().chatAlertEnabled end,
      }, {
        type = "checkbox",
        name = text("Whisper Channel"),
        tooltip = text("Show whisper messages"),
        getFunc = function() return l.getSavedVars().chatAlertChannelWhisper end,
        setFunc = function(value) l.getSavedVars().chatAlertChannelWhisper = value end,
        width = "half",
        default = chatAlertSavedVarsDefaults.chatAlertChannelWhisper,
        disabled = function() return not l.getSavedVars().chatAlertEnabled end,
      }, {
        type = "checkbox",
        name = text("Guild Channel"),
        tooltip = text("Show messages from guild chat"),
        getFunc = function() return l.getSavedVars().chatAlertChannelGuild end,
        setFunc = function(value) l.getSavedVars().chatAlertChannelGuild = value end,
        width = "half",
        default = chatAlertSavedVarsDefaults.chatAlertChannelGuild,
        disabled = function() return not l.getSavedVars().chatAlertEnabled end,
      }, {
        type = "slider",
        name = text("Chat Alert Duration"),
        tooltip = text("How long to display chat alerts in seconds"),
        min = 1, max = 15, step = 0.5,
        getFunc = function() return l.getSavedVars().chatAlertDurationSeconds end,
        setFunc = function(value) l.getSavedVars().chatAlertDurationSeconds = value end,
        width = "full",
        disabled = function() return not l.getSavedVars().chatAlertEnabled end,
        default = chatAlertSavedVarsDefaults.chatAlertDurationSeconds,
      }, {
        type = "slider",
        name = text("Max Concurrent Alerts"),
        tooltip = text("Maximum number of chat alerts shown at once"),
        min = 1, max = 10, step = 1,
        getFunc = function() return l.getSavedVars().chatAlertMaxAlerts end,
        setFunc = function(value) l.getSavedVars().chatAlertMaxAlerts = value end,
        width = "full",
        disabled = function() return not l.getSavedVars().chatAlertEnabled end,
        default = chatAlertSavedVarsDefaults.chatAlertMaxAlerts,
      }, {
        type = "slider",
        name = text("Max Message Length"),
        tooltip = text("Truncate messages longer than this many characters"),
        min = 20, max = 200, step = 10,
        getFunc = function() return l.getSavedVars().chatAlertMaxMessageLength end,
        setFunc = function(value) l.getSavedVars().chatAlertMaxMessageLength = value end,
        width = "full",
        disabled = function() return not l.getSavedVars().chatAlertEnabled end,
        default = chatAlertSavedVarsDefaults.chatAlertMaxMessageLength,
      }, {
        type = "button",
        name = text("Move Chat Alert"),
        func = function()
          SCENE_MANAGER:Hide("gameMenuInGame")
          l.openChatAlertFrame()
          zo_callLater(function()
            SetGameCameraUIMode(true)
          end, 10)
        end,
        width = "half",
        disabled = function() return not l.getSavedVars().chatAlertEnabled end,
      }, {
        type = "button",
        name = text("Reset Chat Alert Position"),
        func = function()
          l.getSavedVars().chatAlertOffsetX = 0
          l.getSavedVars().chatAlertOffsetY = 150
        end,
        width = "half",
        disabled = function() return not l.getSavedVars().chatAlertEnabled end,
      }, {
        type = "checkbox",
        name = text("Play Chat Alert Sound"),
        tooltip = text("Play a sound when a chat alert appears"),
        getFunc = function() return l.getSavedVars().chatAlertPlaySound end,
        setFunc = function(value) l.getSavedVars().chatAlertPlaySound = value end,
        disabled = function() return not l.getSavedVars().chatAlertEnabled end,
        width = "full",
        default = chatAlertSavedVarsDefaults.chatAlertPlaySound,
      }, {
        type = "slider",
        name = text("Chat Alert Sound"),
        min = 1, max = #l.soundChoices, step = 1,
        getFunc = function() return l.findSoundIndex(l.getSavedVars().chatAlertSoundName) end,
        setFunc = function(value) l.getSavedVars().chatAlertSoundName = l.soundChoices[value]; PlaySound(SOUNDS[l.getSavedVars().chatAlertSoundName]) end,
        width = "full",
        disabled = function() return not l.getSavedVars().chatAlertPlaySound or not l.getSavedVars().chatAlertEnabled end,
        default = l.findSoundIndex(chatAlertSavedVarsDefaults.chatAlertSoundName),
      }, {
        type = "dropdown",
        name = text("Chat Alert Font Name"),
        choices = {"MEDIUM_FONT", "BOLD_FONT", "CHAT_FONT", "ANTIQUE_FONT", "HANDWRITTEN_FONT", "STONE_TABLET_FONT", "GAMEPAD_MEDIUM_FONT", "GAMEPAD_BOLD_FONT"},
        getFunc = function() return l.getSavedVars().chatAlertFontName end,
        setFunc = function(value) l.getSavedVars().chatAlertFontName = value end,
        disabled = function() return not l.getSavedVars().chatAlertEnabled end,
        width = "full",
        default = chatAlertSavedVarsDefaults.chatAlertFontName,
      }, {
        type = "slider",
        name = text("Chat Alert Font Size"),
        min = 14, max = 80, step = 2,
        getFunc = function() return l.getSavedVars().chatAlertFontSize end,
        setFunc = function(value) l.getSavedVars().chatAlertFontSize = value end,
        disabled = function() return not l.getSavedVars().chatAlertEnabled end,
        width = "full",
        default = chatAlertSavedVarsDefaults.chatAlertFontSize,
      }, {
        type = "dropdown",
        name = text("Chat Alert Font Style"),
        choices = {"soft-shadow-thin", "soft-shadow-thick", "thick-outline", "outline"},
        getFunc = function() return l.getSavedVars().chatAlertFontStyle end,
        setFunc = function(value) l.getSavedVars().chatAlertFontStyle = value end,
        disabled = function() return not l.getSavedVars().chatAlertEnabled end,
        width = "full",
        default = chatAlertSavedVarsDefaults.chatAlertFontStyle,
      },
    }
  })
end)

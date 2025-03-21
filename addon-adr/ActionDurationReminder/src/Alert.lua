--========================================
--        vars
--========================================
local addon = ActionDurationReminder -- Addon#M
local settings = addon.load("Settings#M")
local models = addon.load("Models#M")
local core = addon.load("Core#M")
local l = {} -- #L
local m = {l=l} -- #M
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
  alertRemoveWhenCastAgain = true,
}

--========================================
--        l
--========================================
l.controlPool = {}

l.frame = nil --TopLevelWindow#TopLevelWindow

l.showedControls = {} -- #list<Control#Control>

l.soundChoices = {} -- #list<#number>
for k,v in pairs(SOUNDS) do
  table.insert(l.soundChoices, k)
end
table.sort(l.soundChoices)

l.alert -- #(Models#Ability:ability, #number:startTime)->()
= function(ability, startTime)
  local savedVars = l.getSavedVars()
  -- filter by keywords
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
  if checked and not checkOk then return end
  keywords = l.getSavedVars().alertBlackKeyWords:lower()
  for line in keywords:gmatch("[^\r\n]+") do
    line = line:match "^%s*(.-)%s*$"
    if line and line:len()>0 then
      if line:match('^%d+$') then
        if tonumber(line) == ability.id then return end
      end
      if zo_strformat("<<1>>", ability.name):lower():find(line,1,true) then
        return
      end
    end
  end
  --
  if savedVars.alertPlaySound then PlaySound(SOUNDS[savedVars.alertSoundName]) end
  local control = l.retrieveControl()
  local fontstr = (zhFlags[GetCVar("language.2")] and "EsoZH/fonts/univers67.otf" or ("$("..savedVars.alertFontName..")")) .."|"..savedVars.alertFontSize.."|"..savedVars.alertFontStyle
  control.label:SetFont(fontstr)

  control.label:SetText(savedVars.alertIconOnly and '' or zo_strformat('<<C:1>>',ability.showName))
  control.icon:SetTexture(ability.icon)
  control:SetAnchor(BOTTOMLEFT, GuiRoot, CENTER, -150 + savedVars.alertOffsetX, -150 + savedVars.alertOffsetY)
  control:SetHidden(false)
  control.ability = ability
  control.startTime = startTime
  for i,v in ipairs(l.showedControls) do
    local _, _, _, _, offsetX, offsetY = v:GetAnchor(0)
    v:ClearAnchors()
    v:SetAnchor(BOTTOMLEFT, GuiRoot, CENTER, offsetX, offsetY -savedVars.alertIconSize-10)
  end
  table.insert(l.showedControls,control)
  zo_callLater(
    function()
      l.returnControl(control)
    end,
    savedVars.alertKeepSeconds*1000
  )
end

l.checkAction --#(Models#Action:action)->()
= function(action)
  -- check ultimate
  if action.slotNum == 8 then return end
  -- check action alerted
  if action.data.alerted then return end
  -- check action just override without new effects
  if action:getFullEndTime()-action.startTime < 3000 then return end
  if action:getStageInfo() == '1/2' then return end

  --
  local onlyShowAfterTimeout = false
  local instant = l.isActionInstant(action)
  local aheadTime = l.getSavedVars().alertAheadSeconds *1000
  local markTime = action.startTime
  if onlyShowAfterTimeout then
    aheadTime = 0
  elseif instant then
    aheadTime = action:getDuration()
  end
  if onlyShowAfterTimeout then aheadTime = 0 end
  if action:getFullEndTime() - aheadTime < GetGameTimeMilliseconds() then
    action.data.alerted = true
    local showAbility = action.ability
    local mutantId = GetSlotBoundId(action.slotNum, action.hotbarCategory) --#number
    if showAbility.id ~= mutantId then
      local slotAbility = models.newAbility(mutantId, GetSlotName(action.slotNum), GetSlotTexture(action.slotNum))
      if action:matchesAbility(slotAbility) then
        slotAbility.id = action.ability.id
        showAbility = slotAbility
      end
    end
    l.alert(showAbility, action.startTime)
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

l.isActionInstant --#(Models#Action:action)->(#boolean)
= function(action)
  -- check fakeInstant i.e. Crystal Fragment
  if action.fake and action.stackCount ==0 then return true end
  -- check bound armaments at stack 4
  if action.stackCount==4 and action.ability.icon:find('bound_armament',35,true)
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
        if action.stackCount <= 1 then -- i.e. Bound Armaments transmute when just getting an attack stack
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

local lastLog = 0
addon.alertLogCntValve = 20
addon.alertLogInterval = 300
-- /script ActionDurationReminder.alertLogCntValve=0 ActionDurationReminder.alertLogInterval=5
-- /script ActionDurationReminder.alertLogCntValve=20 ActionDurationReminder.alertLogInterval=300
l.onCoreUpdate -- #()->()
= function()
  local savedVars = l.getSavedVars()
  if not savedVars.alertEnabled then return end

  local snActionMap = core.getSnActionMap()
  local cntMap = {} -- #map<#number,#number>
  local maxSnMap = {} -- #map<#number, #number>
  for sn,action in pairs(snActionMap) do
    l.checkAction(action)
    cntMap[action.ability.id] = (cntMap[action.ability.id] or 0) + 1
    maxSnMap[action.ability.id] = math.max(cntMap[action.ability.id] or 0, action.sn)
  end

  local now = GetGameTimeSeconds()
  -- TODO move this check into core
  if now - lastLog > addon.alertLogInterval then
    local didLog = false
    for id, cnt in pairs(cntMap) do
      if cnt > addon.alertLogCntValve then
        didLog = true
        if savedVars.coreLogTrackedEffectsInChat then
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
  if savedVars.alertRemoveWhenCastAgain then
    for k,v in pairs(l.showedControls) do
      if not v:IsHidden() then
        local action = core.getActionByAbilityName(v.ability.name)
        if action and action.startTime ~= v.startTime then
          v:SetHidden(true)
        end
      end
    end
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
    local label = WINDOW_MANAGER:CreateControl(nil, backdrop, CT_LABEL) --LabelControl#LabelControl
    label:SetFont('$(MEDIUM_FONT)|$(KB_18)|soft-shadow-thin')
    label:SetColor(1,1,1)
    label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    label:SetAnchor(CENTER)
    label:SetDrawLayer(DL_COUNT)
    label:SetDrawLevel(1)
    label:SetText('ADR Alert Frame')
    local labelClose = WINDOW_MANAGER:CreateControl(nil, backdrop, CT_LABEL) --LabelControl#LabelControl
    labelClose:SetFont('$(MEDIUM_FONT)|$(KB_18)|soft-shadow-thin')
    labelClose:SetColor(1,1,1)
    labelClose:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    labelClose:SetVerticalAlignment(TEXT_ALIGN_BOTTOM)
    labelClose:SetAnchor(BOTTOMRIGHT, nil, BOTTOMRIGHT, -5, -2)
    labelClose:SetDrawLayer(DL_COUNT)
    labelClose:SetDrawLevel(1)
    labelClose:SetText('[X]')
    labelClose:SetMouseEnabled(true)
    labelClose:SetHandler('OnMouseUp', function() l.frame:SetHidden(true) end)
  end
  l.frame:SetHidden(false)
  l.frame:ClearAnchors()
  l.frame:SetAnchor(BOTTOMLEFT, GuiRoot, CENTER, - 150 + savedVars.alertOffsetX, - 150 + savedVars.alertOffsetY)
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
  control:SetHidden(true)
  control:ClearAnchors()
  table.insert(l.controlPool, control)
end

--========================================
--        register
--========================================
addon.register("Alert#M", m)

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
        name = text("Enabled"),
        getFunc = function() return l.getSavedVars().alertEnabled end,
        setFunc = function(value) l.getSavedVars().alertEnabled = value end,
        width = "full",
        default = alertSavedVarsDefaults.alertEnabled,
      },  {
        type = "checkbox",
        name = text("Icon Only"),
        getFunc = function() return l.getSavedVars().alertIconOnly end,
        setFunc = function(value) l.getSavedVars().alertIconOnly = value end,
        disabled = function() return not l.getSavedVars().alertEnabled end,
        width = "full",
        default = alertSavedVarsDefaults.alertIconOnly,
      }, {
        type = "checkbox",
        name = text("Remove When Cast Again"),
        getFunc = function() return l.getSavedVars().alertRemoveWhenCastAgain end,
        setFunc = function(value) l.getSavedVars().alertRemoveWhenCastAgain = value end,
        disabled = function() return not l.getSavedVars().alertEnabled end,
        width = "full",
        default = alertSavedVarsDefaults.alertRemoveWhenCastAgain,
      }, {
        type = "button",
        name = text("Move Alert Frame"),
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
        name = text("Reset Alert Frame"),
        func = function()
          l.getSavedVars().alertOffsetX = 0
          l.getSavedVars().alertOffsetY = 0
        end,
        width = "half",
        disabled = function() return not l.getSavedVars().alertEnabled end,
      }, {
        type = "checkbox",
        name = text("Sound Enabled"),
        getFunc = function() return l.getSavedVars().alertPlaySound end,
        setFunc = function(value) l.getSavedVars().alertPlaySound = value end,
        disabled = function() return not l.getSavedVars().alertEnabled end,
        width = "full",
        default = alertSavedVarsDefaults.alertPlaySound,
      }, {
        type = "slider",
        name = text("Sound Select Index"),
        --tooltip = "",
        min = 1, max = #l.soundChoices, step = 1,
        getFunc = function() return l.findSoundIndex(l.getSavedVars().alertSoundName) end,
        setFunc = function(value) l.getSavedVars().alertSoundName = l.soundChoices[value]; PlaySound(SOUNDS[l.getSavedVars().alertSoundName]) end,
        width = "full",
        disabled = function() return not l.getSavedVars().alertPlaySound or not l.getSavedVars().alertEnabled end,
        default = l.findSoundIndex(alertSavedVarsDefaults.alertSoundName),
      }, {
        type = "button",
        name = text("Sound Test"),
        func = function()
          PlaySound(SOUNDS[l.getSavedVars().alertSoundName])
        end,
        width = "full",
        disabled = function() return not l.getSavedVars().alertPlaySound or not l.getSavedVars().alertEnabled end,
      }, {
        type = "slider",
        name = text("Seconds to Show Before End"),
        --tooltip = "",
        min = 0, max = 3, step = 0.5,
        getFunc = function() return l.getSavedVars().alertAheadSeconds end,
        setFunc = function(value) l.getSavedVars().alertAheadSeconds = value end,
        width = "full",
        disabled = function() return not l.getSavedVars().alertEnabled end,
        default = alertSavedVarsDefaults.alertAheadSeconds,
      }, {
        type = "slider",
        name = text("Seconds to Show"),
        --tooltip = "",
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
        --tooltip = "",
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
        --tooltip = "",
        min = 18, max = 98, step = 2,
        getFunc = function() return l.getSavedVars().alertIconSize end,
        setFunc = function(value) l.getSavedVars().alertIconSize = value end,
        disabled = function() return not l.getSavedVars().alertEnabled end,
        width = "full",
        default = alertSavedVarsDefaults.alertIconSize,
      }, {
        type = "slider",
        name = text("Icon Opacity %"),
        --tooltip = "",
        min = 10, max = 100, step = 10,
        getFunc = function() return l.getSavedVars().alertIconOpacity end,
        setFunc = function(value) l.getSavedVars().alertIconOpacity = value end,
        disabled = function() return not l.getSavedVars().alertEnabled end,
        width = "full",
        default = alertSavedVarsDefaults.alertIconOpacity,
      }, {
        type = "editbox",
        name = text("Patterns of White List in line"), -- or string id or function returning a string
        getFunc = function() return l.getSavedVars().alertKeyWords end,
        setFunc = function(text) l.getSavedVars().alertKeyWords = text end,
        -- tooltip = "Editbox's tooltip text.", -- or string id or function returning a string (optional)
        isMultiline = true, --boolean (optional)
        isExtraWide = true, --boolean (optional)
        width = "full", --or "half" (optional)
        disabled = function() return not l.getSavedVars().alertEnabled end, --or boolean (optional)
        -- warning = "May cause permanent awesomeness.", -- or string id or function returning a string (optional)
        requiresReload = false, -- boolean, if set to true, the warning text will contain a notice that changes are only applied after an UI reload and any change to the value will make the "Apply Settings" button appear on the panel which will reload the UI when pressed (optional)
        default = alertSavedVarsDefaults.alertKeyWords, -- default value or function that returns the default value (optional)
      -- reference = "MyAddonEditbox" -- unique global reference to control (optional)
      },{
        type = "editbox",
        name = text("Patterns of Black List in line"), -- or string id or function returning a string
        getFunc = function() return l.getSavedVars().alertBlackKeyWords end,
        setFunc = function(text) l.getSavedVars().alertBlackKeyWords = text end,
        -- tooltip = "Editbox's tooltip text.", -- or string id or function returning a string (optional)
        isMultiline = true, --boolean (optional)
        isExtraWide = true, --boolean (optional)
        width = "full", --or "half" (optional)
        disabled = function() return not l.getSavedVars().alertEnabled end, --or boolean (optional)
        -- warning = "May cause permanent awesomeness.", -- or string id or function returning a string (optional)
        requiresReload = false, -- boolean, if set to true, the warning text will contain a notice that changes are only applied after an UI reload and any change to the value will make the "Apply Settings" button appear on the panel which will reload the UI when pressed (optional)
        default = alertSavedVarsDefaults.alertBlackKeyWords, -- default value or function that returns the default value (optional)
      -- reference = "MyAddonEditbox" -- unique global reference to control (optional)
      }}})
end)

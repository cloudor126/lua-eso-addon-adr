--========================================
--        vars
--========================================
local addon = ActionDurationReminder -- Addon#M
local settings = addon.load("Settings#M")
local core = addon.load("Core#M")
local views = addon.load("Views#M")
local models = addon.load("Models#M")
local l = {} -- #L
local m = {l=l} -- #M

---
--@type BarSavedVars
local barSavedVarsDefaults
  = {
    barEnabled = true,
    barShowShift = true,
    barShowInQuickslot = false,
    barShiftOffsetX = 0,
    barShiftOffsetY = 0,
    barLabelFontName = "BOLD_FONT",
    barLabelFontSize = 18,
    barLabelFontStyle = 'thick-outline',
    barLabelYOffset = 0,
    barLabelYOffsetInShift = 0,
    barStackLabelYOffset = 0,
    barStackLabelYOffsetInShift = 0,
    barLabelIgnoreDecimal = true,
    barLabelIgnoreDeciamlThreshold = 10,
    barStackLabelFontName = "BOLD_FONT",
    barStackLabelFontSize = 18,
    barStackLabelFontStyle = 'thick-outline',
    barCooldownVisible = true,
    barCooldownColor = {1,1,0},
    barCooldownEndingSeconds = 1,
    barCooldownEndingColor = {1,0,0},
    barCooldownOpacity = 100,
    barCooldownThickness = 2,
  }

--========================================
--        l
--========================================
l.shiftBarFrame = nil -- BackdropControl#BackdropControl
l.mainBarWidgetMap = {}--#map<#number, Views#Widget>
l.quickslotWidget = nil --Views#Widget
l.quickslotFakeAction = nil --Models#Action
l.shiftedBarWidgetMap = {}--#map<#number, Views#Widget>
l.appendedBarWidgetMap = {}--#map<#number, Views#Widget>

l.getSavedVars -- #()->(#BarSavedVars)
= function()
  return settings.getSavedVars()
end

l.hideWidgets -- #()->()
= function()
  for key, var in pairs(l.mainBarWidgetMap) do
    var:hide()
  end
  for key, var in pairs(l.shiftedBarWidgetMap) do
    var:hide()
  end
  for key, var in pairs(l.appendedBarWidgetMap) do
    var:hide()
  end
end

l.onCoreUpdate -- #()->()
= function()
  if not l.getSavedVars().barEnabled then return end
  local now = GetGameTimeMilliseconds()
  local showedActionMap = {} --#map<#number,Models#Action>
  local weaponPairIndex = GetActiveWeaponPairInfo()
  -- 1. show in action bar widgets
  for slotNum = 3,8 do
    local widget = l.mainBarWidgetMap[slotNum]
    local abilityId = GetSlotBoundId(slotNum)
    local action = core.getActionBySlot(weaponPairIndex,slotNum)
    if action and not action:matchesAbilityName(GetSlotName(slotNum)) then action = nil end -- check this position action
    if not action then action = core.getActionByAbilityId(abilityId) end
    if action then
      action.flags.isShifted = false
      showedActionMap[action.ability.id] = action
      showedActionMap[abilityId] = action
      if not widget then
        widget = views.newWidget(slotNum, false)
        l.mainBarWidgetMap[slotNum] = widget
      end
      widget:updateWithAction(action, now)
    elseif widget then
      widget:hide()
    end
  end
  -- 2. clean shift and extend widgets
  for key,var in pairs(l.shiftedBarWidgetMap) do
    local widget = var --Views#Widget
    widget:hide()
  end
  for key,var in pairs(l.appendedBarWidgetMap) do
    local widget = var --Views#Widget
    widget:hide()
  end
  -- 3. show quickslot
  if l.getSavedVars().barShowInQuickslot then
    local remain,duration, global = GetSlotCooldownInfo(GetCurrentQuickslot(),HOTBAR_CATEGORY_QUICKSLOT_WHEEL)
    if remain>0 and not global then
      if not l.quickslotWidget then
        l.quickslotWidget = views.newWidget(9, false)
      end
      if not l.quickslotFakeAction then
        l.quickslotFakeAction = models.newAction(3,1,false)
      end
      l.quickslotFakeAction.startTime = now+remain-duration
      l.quickslotFakeAction.duration = duration
      l.quickslotFakeAction.endTime = now +remain
      l.quickslotWidget:updateWithAction(l.quickslotFakeAction, now)
    elseif l.quickslotWidget then
      l.quickslotWidget:hide()
    end
  end
  -- 4. prepare to show shift and extend
  if not l.getSavedVars().barShowShift then return end
  local toShowActionMap = {} --#map<#number,adr.model.Action#Action>
  local toShowIdList = {} --#list<#number>
  for id, action in pairs(core.getIdActionMap()) do
    if not showedActionMap[id] then
      action.flags.shifted = true
      toShowActionMap[id] = action
      toShowIdList[#toShowIdList+1] = id
    end
  end
  if #toShowIdList==0 then return end
  -- 4.$ sort later actions show first
  table.sort(toShowIdList, function(id1,id2)return toShowActionMap[id1]:getStartTime() > toShowActionMap[id2]:getStartTime() end)
  local appendIndex = 0
  for i=1,#toShowIdList do
    local id = toShowIdList[i]
    local action = toShowActionMap[id]
    local slotNum = action.slotNum
    --    local inAppend = core.getWeaponPairInfo().ultimate and ( action.weaponPairIndex ~= core.getWeaponPairInfo().index) or action.weaponPairUltimate
    local inAppend = false
    local widget = l.shiftedBarWidgetMap[slotNum]
    if inAppend or (widget and widget.visible) then
      appendIndex=appendIndex+1
      widget = l.appendedBarWidgetMap[appendIndex]
      if not widget then
        widget = views.newWidget(8,true,appendIndex)
        l.appendedBarWidgetMap[appendIndex] = widget
      end
    elseif not widget then
      widget = views.newWidget(slotNum,true)
      l.shiftedBarWidgetMap[slotNum] = widget
    end
    widget:updateWithAction(action, now)
    widget.backdrop:SetDimensions(50,50)
  end
end

l.openShiftBarFrame -- #()->()
= function()
  local slot3 = ZO_ActionBar_GetButton(3).slot -- Control#Control
  local slot7 = ZO_ActionBar_GetButton(7).slot -- Control#Control
  if not l.shiftBarFrame then
    l.shiftBarFrame = WINDOW_MANAGER:CreateControl(nil, slot3, CT_BACKDROP)
    local width = slot7:GetRight() - slot3:GetLeft()
    local _,height = slot7:GetDimensions()
    l.shiftBarFrame:SetDimensions(width, height)
    l.shiftBarFrame:SetMouseEnabled(true)
    l.shiftBarFrame:SetMovable(true)
    l.shiftBarFrame:SetDrawLayer(DL_COUNT)
    l.shiftBarFrame:SetCenterColor(0,0,1,0.5)
    l.shiftBarFrame:SetEdgeTexture('',1,1,1,0)
    l.shiftBarFrame:SetHandler('OnMoveStop', function()
      local left = l.shiftBarFrame:GetLeft()
      local bottom = l.shiftBarFrame:GetBottom()
      l.getSavedVars().barShiftOffsetX = left - slot3:GetLeft()
      l.getSavedVars().barShiftOffsetY = bottom - slot3:GetTop()
      l.updateWidgets(views.updateWidgetShiftOffset)
      zo_callLater(function()
        SetGameCameraUIMode(true)
      end, 10)
    end)
    local label = WINDOW_MANAGER:CreateControl(nil, l.shiftBarFrame, CT_LABEL) --LabelControl#LabelControl
    label:SetFont('$(MEDIUM_FONT)|$(KB_18)|soft-shadow-thin')
    label:SetColor(1,1,1)
    label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    label:SetAnchor(CENTER)
    label:SetDrawLayer(DL_COUNT)
    label:SetDrawLevel(1)
    label:SetText(addon.text("ADR Shift Bar Frame"))
    local labelClose = WINDOW_MANAGER:CreateControl(nil, l.shiftBarFrame, CT_LABEL) --LabelControl#LabelControl
    labelClose:SetFont('$(MEDIUM_FONT)|$(KB_18)|soft-shadow-thin')
    labelClose:SetColor(1,1,1)
    labelClose:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    labelClose:SetVerticalAlignment(TEXT_ALIGN_BOTTOM)
    labelClose:SetAnchor(TOPRIGHT, nil, TOPRIGHT, -5, 2)
    labelClose:SetDrawLayer(DL_COUNT)
    labelClose:SetDrawLevel(1)
    labelClose:SetText('[X]')
    labelClose:SetMouseEnabled(true)
    labelClose:SetHandler('OnMouseUp', function()
      l.shiftBarFrame:SetHidden(true)
    end)
  end
  l.shiftBarFrame:SetHidden(false)
  l.shiftBarFrame:ClearAnchors()
  l.shiftBarFrame:SetAnchor(BOTTOMLEFT, slot3, TOPLEFT, l.getSavedVars().barShiftOffsetX, l.getSavedVars().barShiftOffsetY+1)
end

l.updateWidgets -- #(#(Views#Widget:widget)->():func)->()
= function(func)
  for _, widget in pairs(l.mainBarWidgetMap) do
    func(widget)
  end
  for _, widget in pairs(l.shiftedBarWidgetMap) do
    func(widget)
  end
  for _, widget in pairs(l.appendedBarWidgetMap) do
    func(widget)
  end
end

--========================================
--        m
--========================================

--========================================
--        register
--========================================
addon.register("Bar#M",m)

addon.extend(settings.EXTKEY_ADD_DEFAULTS,function()
  settings.addDefaults(barSavedVarsDefaults)
end)

addon.extend(core.EXTKEY_UPDATE,l.onCoreUpdate);

addon.extend(settings.EXTKEY_ADD_MENUS, function()
  local text = addon.text
  settings.addMenuOptions(
    {
      type = "submenu",
      name = text("Bar"),
      controls = {
        {
          type = "checkbox",
          name = text("Timers Enabled"),
          getFunc = function() return l.getSavedVars().barEnabled end,
          setFunc = function(value) l.getSavedVars().barEnabled = value;if not value then l.hideWidgets() end end,
          width = "full",
          default = barSavedVarsDefaults.barEnabled,
        },
        {
          type = "checkbox",
          name = text("Shift Bar Enabled"),
          getFunc = function() return l.getSavedVars().barShowShift end,
          setFunc = function(value) l.getSavedVars().barShowShift = value end,
          width = "full",
          default = barSavedVarsDefaults.barShowShift,
          disabled = function() return not l.getSavedVars().barEnabled end,
        },{
          type = "description",
          text = "",
          title = text("Shift Bar Location"),
          width = "half",
          disabled = function() return not l.getSavedVars().barEnabled end,
        },{
          type = "button",
          name = text("Move Shift Bar"),
          func = function()
            SCENE_MANAGER:Hide("gameMenuInGame")
            l.openShiftBarFrame()
            zo_callLater(function()
              SetGameCameraUIMode(true)
            end, 10)
          end,
          width = "half",
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barShowShift end,
        },{
          type = "checkbox",
          name = text("Track Quickslot"),
          getFunc = function() return l.getSavedVars().barShowInQuickslot end,
          setFunc = function(value) l.getSavedVars().barShowInQuickslot = value end,
          width = "full",
          default = barSavedVarsDefaults.barShowInQuickslot,
          disabled = function() return not l.getSavedVars().barEnabled end,
        },{
          type = "dropdown",
          name = text("Label Font Name"),
          choices = {"MEDIUM_FONT", "BOLD_FONT", "CHAT_FONT", "ANTIQUE_FONT", "HANDWRITTEN_FONT", "STONE_TABLET_FONT", "GAMEPAD_MEDIUM_FONT", "GAMEPAD_BOLD_FONT"},
          getFunc = function() return l.getSavedVars().barLabelFontName end,
          setFunc = function(value) l.getSavedVars().barLabelFontName = value; l.updateWidgets(views.updateWidgetFont) end,
          width = "full",
          default = barSavedVarsDefaults.barLabelFontName,
          disabled = function() return not l.getSavedVars().barEnabled end,
        },{
          type = "slider",
          name = text("Label Font Size"),
          --tooltip = "",
          min = 12, max = 48, step = 1,
          getFunc = function() return l.getSavedVars().barLabelFontSize end,
          setFunc = function(value) l.getSavedVars().barLabelFontSize = value ; l.updateWidgets(views.updateWidgetFont) end,
          width = "full",
          default = barSavedVarsDefaults.barLabelFontSize,
          disabled = function() return not l.getSavedVars().barEnabled end,
        },{
          type = "dropdown",
          name = text("Label Font Style"),
          choices = {"thick-outline","soft-shadow-thick","soft-shadow-thin","outline"},
          getFunc = function() return l.getSavedVars().barLabelFontStyle end,
          setFunc = function(value) l.getSavedVars().barLabelFontStyle = value; l.updateWidgets(views.updateWidgetFont) end,
          width = "full",
          default = barSavedVarsDefaults.barLabelFontStyle,
          disabled = function() return not l.getSavedVars().barEnabled end,
        },{
          type = "slider",
          name = text("Label Vertical Offset"),
          min = -50, max = 50, step = 1,
          getFunc = function() return l.getSavedVars().barLabelYOffset end,
          setFunc = function(value) l.getSavedVars().barLabelYOffset = value ; l.updateWidgets(views.updateWidgetLabelYOffset) end,
          width = "full",
          default = barSavedVarsDefaults.barLabelYOffset,
          disabled = function() return not l.getSavedVars().barEnabled end,
        },{
          type = "slider",
          name = text("Stack Label Vertical Offset"),
          min = -50, max = 50, step = 1,
          getFunc = function() return l.getSavedVars().barStackLabelYOffset end,
          setFunc = function(value) l.getSavedVars().barStackLabelYOffset = value ; l.updateWidgets(views.updateWidgetStackLabelYOffset) end,
          width = "full",
          default = barSavedVarsDefaults.barStackLabelYOffset,
          disabled = function() return not l.getSavedVars().barEnabled end,
        },{
          type = "slider",
          name = text("Label Vertical Offset In Shift Bar"),
          min = -50, max = 50, step = 1,
          getFunc = function() return l.getSavedVars().barLabelYOffsetInShift end,
          setFunc = function(value) l.getSavedVars().barLabelYOffsetInShift = value ; l.updateWidgets(views.updateWidgetLabelYOffset) end,
          width = "full",
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barShowShift end,
          default = barSavedVarsDefaults.barLabelYOffsetInShift,
        },{
          type = "slider",
          name = text("Stack Label Vertical Offset In Shift Bar"),
          min = -50, max = 50, step = 1,
          getFunc = function() return l.getSavedVars().barStackLabelYOffsetInShift end,
          setFunc = function(value) l.getSavedVars().barStackLabelYOffsetInShift = value ; l.updateWidgets(views.updateWidgetStackLabelYOffset) end,
          width = "full",
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barShowShift end,
          default = barSavedVarsDefaults.barStackLabelYOffsetInShift,
        },{
          type = "checkbox",
          name = text("Label Ignore Decimal Part"),
          getFunc = function() return l.getSavedVars().barLabelIgnoreDecimal end,
          setFunc = function(value) l.getSavedVars().barLabelIgnoreDecimal = value end,
          width = "full",
          default = barSavedVarsDefaults.barLabelIgnoreDecimal,
          disabled = function() return not l.getSavedVars().barEnabled end,
        },{
          type = "slider",
          name = text("Label Ignore Decimal Part Threshold"),
          min = 0, max = 30, step = 0.5,
          getFunc = function() return l.getSavedVars().barLabelIgnoreDeciamlThreshold end,
          setFunc = function(value) l.getSavedVars().barLabelIgnoreDeciamlThreshold = value end,
          width = "full",
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barLabelIgnoreDecimal end,
          default = barSavedVarsDefaults.barLabelIgnoreDeciamlThreshold,
        },{
          type = "dropdown",
          name = text("Stack Label Font Name"),
          choices = {"MEDIUM_FONT", "BOLD_FONT", "CHAT_FONT", "ANTIQUE_FONT", "HANDWRITTEN_FONT", "STONE_TABLET_FONT", "GAMEPAD_MEDIUM_FONT", "GAMEPAD_BOLD_FONT"},
          getFunc = function() return l.getSavedVars().barStackLabelFontName end,
          setFunc = function(value) l.getSavedVars().barStackLabelFontName = value; l.updateWidgets(views.updateWidgetFont) end,
          width = "full",
          default = barSavedVarsDefaults.barStackLabelFontName,
          disabled = function() return not l.getSavedVars().barEnabled end,
        },{
          type = "slider",
          name = text("Stack Label Font Size"),
          --tooltip = "",
          min = 12, max = 48, step = 1,
          getFunc = function() return l.getSavedVars().barStackLabelFontSize end,
          setFunc = function(value) l.getSavedVars().barStackLabelFontSize = value ; l.updateWidgets(views.updateWidgetFont) end,
          width = "full",
          default = barSavedVarsDefaults.barStackLabelFontSize,
          disabled = function() return not l.getSavedVars().barEnabled end,
        },{
          type = "dropdown",
          name = text("Stack Label Font Style"),
          choices = {"thick-outline","soft-shadow-thick","soft-shadow-thin","outline"},
          getFunc = function() return l.getSavedVars().barStackLabelFontStyle end,
          setFunc = function(value) l.getSavedVars().barStackLabelFontStyle = value; l.updateWidgets(views.updateWidgetFont) end,
          width = "full",
          default = barSavedVarsDefaults.barStackLabelFontStyle,
          disabled = function() return not l.getSavedVars().barEnabled end,
        },{
          type = "checkbox",
          name = text("Line Enabled"),
          getFunc = function() return l.getSavedVars().barCooldownVisible end,
          setFunc = function(value) l.getSavedVars().barCooldownVisible = value; l.updateWidgets(views.updateWidgetCooldown) end,
          width = "full",
          default = barSavedVarsDefaults.barCooldownVisible,
          disabled = function() return not l.getSavedVars().barEnabled end,
        },{
          type = "slider",
          name = text("Line Thickness"),
          min = 2, max = 8, step = 1,
          getFunc = function() return l.getSavedVars().barCooldownThickness end,
          setFunc = function(value) l.getSavedVars().barCooldownThickness = value ; l.updateWidgets(views.updateWidgetCooldown) end,
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barCooldownVisible end,
          width = "full",
          default = barSavedVarsDefaults.barCooldownThickness,
        },{
          type = "slider",
          name = text("Line Opacity %"),
          min = 10, max = 100, step = 10,
          getFunc = function() return l.getSavedVars().barCooldownOpacity end,
          setFunc = function(value) l.getSavedVars().barCooldownOpacity = value ; l.updateWidgets(views.updateWidgetCooldown) end,
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barCooldownVisible end,
          width = "full",
          default = barSavedVarsDefaults.barCooldownOpacity,

        },{
          type = "colorpicker",
          name = text("Line Color"),
          getFunc = function() return unpack(l.getSavedVars().barCooldownColor) end,
          setFunc = function(r,g,b,a) l.getSavedVars().barCooldownColor={r,g,b}; l.updateWidgets(views.updateWidgetCooldown) end,
          width = "full",
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barCooldownVisible end,
          default = {
            r = barSavedVarsDefaults.barCooldownColor[1],
            g = barSavedVarsDefaults.barCooldownColor[2],
            b = barSavedVarsDefaults.barCooldownColor[3],
          }
        },{
          type = "slider",
          name = text("Line Ending Seconds"),
          min = 0, max = 4, step = 0.5,
          getFunc = function() return l.getSavedVars().barCooldownEndingSeconds end,
          setFunc = function(value) l.getSavedVars().barCooldownEndingSeconds = value ; l.updateWidgets(views.updateWidgetCooldown) end,
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barCooldownVisible end,
          width = "full",
          default = barSavedVarsDefaults.barCooldownEndingSeconds,
        },{
          type = "colorpicker",
          name = text("Line Ending Color"),
          getFunc = function() return unpack(l.getSavedVars().barCooldownEndingColor) end,
          setFunc = function(r,g,b,a) l.getSavedVars().barCooldownEndingColor={r,g,b}; l.updateWidgets(views.updateWidgetCooldown) end,
          width = "full",
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barCooldownVisible end,
          default = {
            r = barSavedVarsDefaults.barCooldownEndingColor[1],
            g = barSavedVarsDefaults.barCooldownEndingColor[2],
            b = barSavedVarsDefaults.barCooldownEndingColor[3],
          }
        }
      }})
end)

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
    barShowShiftFully = false,
    barShowShiftScalePercent = 100,
    barShowInQuickslot = false,
    barShiftOffsetX = 0,
    barShiftOffsetY = 0,
    barLabelEnabled = true,
    barLabelFontName = "BOLD_FONT",
    barLabelFontSize = 18,
    barLabelFontStyle = 'thick-outline',
    barLabelYOffset = 0,
    barLabelYOffsetInShift = 0,
    barLabelIgnoreDecimal = true,
    barLabelIgnoreDeciamlThreshold = 10,
    barStackLabelEnabled = true,
    barStackLabelYOffset = 0,
    barStackLabelYOffsetInShift = 0,
    barStackLabelFontName = "BOLD_FONT",
    barStackLabelFontSize = 18,
    barStackLabelFontStyle = 'thick-outline',
    barCooldownVisible = true,
    barCooldownColor = {1,1,0},
    barCooldownEndingSeconds = 1,
    barCooldownEndingColor = {1,0,0},
    barCooldownOpacity = 100,
    barCooldownThickness = 2,
    barLowPriorityLabelColor = {0.6, 0.6, 0.6}, -- gray for low priority effects
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
  local hotbarCategory = GetActiveHotbarCategory()
  -- 1. show in action bar widgets
  for slotNum = 3,8 do
    local widget = l.mainBarWidgetMap[slotNum]
    local abilityId = GetSlotBoundId(slotNum,hotbarCategory)
    if GetSlotType(slotNum,hotbarCategory) == ACTION_TYPE_CRAFTED_ABILITY then
      abilityId = GetAbilityIdForCraftedAbilityId(abilityId)
    end
    local action = core.getActionBySlot(hotbarCategory,slotNum)
    if action
      -- check this position action
      and not action:matchesAbilityIcon(GetSlotTexture(slotNum))
      and not action:matchesAbilityName(GetSlotName(slotNum))
    then action = nil end
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
        l.quickslotFakeAction = models.newAction(3,0)
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
      -- filter removed long-stack action (but keep actions with stackEffect)
      local stackEffect = action:getStackEffect()
      local stackCount = stackEffect and stackEffect.stackCount or 0
      if #action.effectList==0 and stackCount > 0 and action.hotbarCategory==hotbarCategory and not action.showCrux then
        action.stackEffect = nil
      end
      -- collect
      action.flags.shifted = true
      toShowActionMap[id] = action
      toShowIdList[#toShowIdList+1] = id
    end
  end
  -- 4.1 sort later actions show first
  if #toShowIdList>0 then
    table.sort(toShowIdList, function(id1,id2)return toShowActionMap[id1]:getStartTime() > toShowActionMap[id2]:getStartTime() end)
    local appendIndex = 0
    for i=1,#toShowIdList do
      local id = toShowIdList[i]
      local action = toShowActionMap[id]
      local slotNum = action.slotNum
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
      widget.backdrop:SetDimensions(views.getSlotBaseSize(), views.getSlotBaseSize())
    end
  end
  -- 4.2 show fully
  if l.getSavedVars().barShowShiftFully then
    local withOakensoul = GetItemLinkIcon(GetItemLink(BAG_WORN, EQUIP_SLOT_RING1)):find('oakensoul')
      or GetItemLinkIcon(GetItemLink(BAG_WORN, EQUIP_SLOT_RING2)):find('oakensoul')
    if not withOakensoul then
      for slotNum = 3,8 do
        local widget = l.shiftedBarWidgetMap[slotNum]
        if not widget then
          widget = views.newWidget(slotNum,true)
          widget:hide()
          l.shiftedBarWidgetMap[slotNum] = widget
        end
        if not widget.visible then
          widget:updateWithSlot(slotNum)
          widget.backdrop:SetDimensions(views.getSlotBaseSize(), views.getSlotBaseSize())
        end
      end
    end
  end
end

l.openShiftBarFrame -- #()->()
= function()
  local slot3 = ZO_ActionBar_GetButton(3).slot -- Control#Control
  local slot7 = ZO_ActionBar_GetButton(7).slot -- Control#Control
  if not l.shiftBarFrame then
    local width = slot7:GetRight() - slot3:GetLeft()
    local _,height = slot7:GetDimensions()
    -- Create frame as TopLevelWindow for proper mouse handling
    l.shiftBarFrame = WINDOW_MANAGER:CreateTopLevelWindow()
    l.shiftBarFrame:SetDimensions(width, height)
    l.shiftBarFrame:SetMouseEnabled(true)
    l.shiftBarFrame:SetMovable(true)
    l.shiftBarFrame:SetDrawLayer(DL_COUNT)
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
    -- Add backdrop as child of frame
    local backdrop = WINDOW_MANAGER:CreateControl(nil, l.shiftBarFrame, CT_BACKDROP)
    backdrop:SetAnchor(TOPLEFT)
    backdrop:SetAnchor(BOTTOMRIGHT)
    backdrop:SetCenterColor(0.2, 0.2, 0.2, 0.6)
    backdrop:SetEdgeTexture('/esoui/art/chatwindow/chat_bg_edge.dds', 256, 256, 32)
    backdrop:SetDrawLayer(DL_COUNT)
    backdrop:SetDrawLevel(0)
    local label = WINDOW_MANAGER:CreateControl(nil, l.shiftBarFrame, CT_LABEL) --LabelControl#LabelControl
    label:SetFont('$(MEDIUM_FONT)|$(KB_18)|soft-shadow-thin')
    label:SetColor(1,1,1)
    label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    label:SetAnchor(CENTER)
    label:SetDrawLayer(DL_COUNT)
    label:SetDrawLevel(1)
    label:SetText(addon.text("ADR Shift Bar Frame"))
    -- Close button as a top-level window so it receives mouse events independently
    local closeBtn = WINDOW_MANAGER:CreateTopLevelWindow()
    closeBtn:SetDimensions(32, 32)
    closeBtn:SetDrawLayer(DL_OVERLAY)
    closeBtn:SetMouseEnabled(true)
    closeBtn:SetMovable(false)
    closeBtn.parentFrame = l.shiftBarFrame -- reference for handler
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
    l.shiftBarCloseBtn = closeBtn
    -- Store reference for position calculation
    l.shiftBarSlot3 = slot3
  end
  l.shiftBarFrame:SetHidden(false)
  l.shiftBarFrame:ClearAnchors()
  l.shiftBarFrame:SetAnchor(BOTTOMLEFT, l.shiftBarSlot3, TOPLEFT, l.getSavedVars().barShiftOffsetX, l.getSavedVars().barShiftOffsetY+1)
  -- Position close button relative to frame
  l.shiftBarCloseBtn:ClearAnchors()
  l.shiftBarCloseBtn:SetAnchor(TOPRIGHT, l.shiftBarFrame, TOPRIGHT, 4, -4)
  l.shiftBarCloseBtn:SetHidden(false)
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
          name = text("Enable Timer Bars"),
          tooltip = text("Display countdown bars on your action bar slots"),
          getFunc = function() return l.getSavedVars().barEnabled end,
          setFunc = function(value) l.getSavedVars().barEnabled = value;if not value then l.hideWidgets() end end,
          width = "full",
          default = barSavedVarsDefaults.barEnabled,
        },
        {
          type = "checkbox",
          name = text("Show Shift Bar"),
          tooltip = text("Display a secondary bar above your action bar showing timers for your other weapon set"),
          getFunc = function() return l.getSavedVars().barShowShift end,
          setFunc = function(value) l.getSavedVars().barShowShift = value end,
          width = "full",
          default = barSavedVarsDefaults.barShowShift,
          disabled = function() return not l.getSavedVars().barEnabled end,
        },{
          type = "slider",
          name = text("Shift Bar Scale"),
          tooltip = text("Scale of the shift bar"),
          min = 40, max = 100, step = 10,
          getFunc = function() return l.getSavedVars().barShowShiftScalePercent end,
          setFunc = function(value) l.getSavedVars().barShowShiftScalePercent = value ; l.updateWidgets(views.updateWidgetShiftScalePercent) end,
          width = "full",
          default = barSavedVarsDefaults.barShowShiftScalePercent,
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barShowShift end,
        },{
          type = "description",
          text = "",
          title = text("Shift Bar Position"),
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
          name = text("Show Empty Slots"),
          tooltip = text("Display all 6 slots even when empty"),
          getFunc = function() return l.getSavedVars().barShowShiftFully end,
          setFunc = function(value) l.getSavedVars().barShowShiftFully = value end,
          width = "full",
          default = barSavedVarsDefaults.barShowShiftFully,
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barShowShift end,
        },{
          type = "checkbox",
          name = text("Track Quickslot Item"),
          tooltip = text("Show timer for your equipped quickslot item"),
          getFunc = function() return l.getSavedVars().barShowInQuickslot end,
          setFunc = function(value) l.getSavedVars().barShowInQuickslot = value end,
          width = "full",
          default = barSavedVarsDefaults.barShowInQuickslot,
          disabled = function() return not l.getSavedVars().barEnabled end,
        },{
          type = "checkbox",
          name = text("Show Time Labels"),
          tooltip = text("Display remaining time as text on timer bars"),
          getFunc = function() return l.getSavedVars().barLabelEnabled end,
          setFunc = function(value) l.getSavedVars().barLabelEnabled = value end,
          width = "full",
          default = barSavedVarsDefaults.barLabelEnabled,
          disabled = function() return not l.getSavedVars().barEnabled end,
        },{
          type = "dropdown",
          name = text("Label Font Name"),
          choices = {"MEDIUM_FONT", "BOLD_FONT", "CHAT_FONT", "ANTIQUE_FONT", "HANDWRITTEN_FONT", "STONE_TABLET_FONT", "GAMEPAD_MEDIUM_FONT", "GAMEPAD_BOLD_FONT"},
          getFunc = function() return l.getSavedVars().barLabelFontName end,
          setFunc = function(value) l.getSavedVars().barLabelFontName = value; l.updateWidgets(views.updateWidgetFont) end,
          width = "full",
          default = barSavedVarsDefaults.barLabelFontName,
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barLabelEnabled end,
        },{
          type = "slider",
          name = text("Label Font Size"),
          min = 12, max = 48, step = 1,
          getFunc = function() return l.getSavedVars().barLabelFontSize end,
          setFunc = function(value) l.getSavedVars().barLabelFontSize = value ; l.updateWidgets(views.updateWidgetFont) end,
          width = "full",
          default = barSavedVarsDefaults.barLabelFontSize,
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barLabelEnabled end,
        },{
          type = "dropdown",
          name = text("Label Font Style"),
          choices = {"thick-outline","soft-shadow-thick","soft-shadow-thin","outline"},
          getFunc = function() return l.getSavedVars().barLabelFontStyle end,
          setFunc = function(value) l.getSavedVars().barLabelFontStyle = value; l.updateWidgets(views.updateWidgetFont) end,
          width = "full",
          default = barSavedVarsDefaults.barLabelFontStyle,
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barLabelEnabled end,
        },{
          type = "slider",
          name = text("Label Vertical Offset"),
          tooltip = text("Adjust time label position up or down"),
          min = -50, max = 50, step = 1,
          getFunc = function() return l.getSavedVars().barLabelYOffset end,
          setFunc = function(value) l.getSavedVars().barLabelYOffset = value ; l.updateWidgets(views.updateWidgetLabelYOffset) end,
          width = "full",
          default = barSavedVarsDefaults.barLabelYOffset,
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barLabelEnabled end,
        },{
          type = "slider",
          name = text("Label Offset (Shift Bar)"),
          tooltip = text("Adjust time label position on the shift bar"),
          min = -50, max = 50, step = 1,
          getFunc = function() return l.getSavedVars().barLabelYOffsetInShift end,
          setFunc = function(value) l.getSavedVars().barLabelYOffsetInShift = value ; l.updateWidgets(views.updateWidgetLabelYOffset) end,
          width = "full",
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barShowShift or not l.getSavedVars().barLabelEnabled end,
          default = barSavedVarsDefaults.barLabelYOffsetInShift,
        },{
          type = "checkbox",
          name = text("Hide Decimals When Long"),
          tooltip = text("Show only whole seconds when time remaining is above threshold"),
          getFunc = function() return l.getSavedVars().barLabelIgnoreDecimal end,
          setFunc = function(value) l.getSavedVars().barLabelIgnoreDecimal = value end,
          width = "full",
          default = barSavedVarsDefaults.barLabelIgnoreDecimal,
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barLabelEnabled end,
        },{
          type = "slider",
          name = text("Decimal Hide Threshold"),
          tooltip = text("Hide decimal portion when time remaining exceeds this value"),
          min = 0, max = 30, step = 0.5,
          getFunc = function() return l.getSavedVars().barLabelIgnoreDeciamlThreshold end,
          setFunc = function(value) l.getSavedVars().barLabelIgnoreDeciamlThreshold = value end,
          width = "full",
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barLabelIgnoreDecimal or not l.getSavedVars().barLabelEnabled end,
          default = barSavedVarsDefaults.barLabelIgnoreDeciamlThreshold,
        },{
          type = "checkbox",
          name = text("Show Stack Count"),
          tooltip = text("Display stack count for stackable effects"),
          getFunc = function() return l.getSavedVars().barStackLabelEnabled end,
          setFunc = function(value) l.getSavedVars().barStackLabelEnabled = value end,
          width = "full",
          default = barSavedVarsDefaults.barStackLabelEnabled,
          disabled = function() return not l.getSavedVars().barEnabled end,
        },{
          type = "slider",
          name = text("Stack Label Vertical Offset"),
          tooltip = text("Adjust stack label position up or down"),
          min = -50, max = 50, step = 1,
          getFunc = function() return l.getSavedVars().barStackLabelYOffset end,
          setFunc = function(value) l.getSavedVars().barStackLabelYOffset = value ; l.updateWidgets(views.updateWidgetStackLabelYOffset) end,
          width = "full",
          default = barSavedVarsDefaults.barStackLabelYOffset,
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barStackLabelEnabled end,
        },{
          type = "slider",
          name = text("Stack Label Offset (Shift Bar)"),
          min = -50, max = 50, step = 1,
          getFunc = function() return l.getSavedVars().barStackLabelYOffsetInShift end,
          setFunc = function(value) l.getSavedVars().barStackLabelYOffsetInShift = value ; l.updateWidgets(views.updateWidgetStackLabelYOffset) end,
          width = "full",
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barShowShift or not l.getSavedVars().barStackLabelEnabled end,
          default = barSavedVarsDefaults.barStackLabelYOffsetInShift,
        },{
          type = "dropdown",
          name = text("Stack Label Font Name"),
          choices = {"MEDIUM_FONT", "BOLD_FONT", "CHAT_FONT", "ANTIQUE_FONT", "HANDWRITTEN_FONT", "STONE_TABLET_FONT", "GAMEPAD_MEDIUM_FONT", "GAMEPAD_BOLD_FONT"},
          getFunc = function() return l.getSavedVars().barStackLabelFontName end,
          setFunc = function(value) l.getSavedVars().barStackLabelFontName = value; l.updateWidgets(views.updateWidgetFont) end,
          width = "full",
          default = barSavedVarsDefaults.barStackLabelFontName,
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barStackLabelEnabled end,
        },{
          type = "slider",
          name = text("Stack Label Font Size"),
          min = 12, max = 48, step = 1,
          getFunc = function() return l.getSavedVars().barStackLabelFontSize end,
          setFunc = function(value) l.getSavedVars().barStackLabelFontSize = value ; l.updateWidgets(views.updateWidgetFont) end,
          width = "full",
          default = barSavedVarsDefaults.barStackLabelFontSize,
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barStackLabelEnabled end,
        },{
          type = "dropdown",
          name = text("Stack Label Font Style"),
          choices = {"thick-outline","soft-shadow-thick","soft-shadow-thin","outline"},
          getFunc = function() return l.getSavedVars().barStackLabelFontStyle end,
          setFunc = function(value) l.getSavedVars().barStackLabelFontStyle = value; l.updateWidgets(views.updateWidgetFont) end,
          width = "full",
          default = barSavedVarsDefaults.barStackLabelFontStyle,
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barStackLabelEnabled end,
        },{
          type = "checkbox",
          name = text("Show Cooldown Line"),
          tooltip = text("Display a progress line under skill slots showing remaining cooldown"),
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
          name = text("Line Opacity"),
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
          name = text("Line Ending Threshold"),
          tooltip = text("Change to ending color when remaining time is below this value"),
          min = 0, max = 4, step = 0.5,
          getFunc = function() return l.getSavedVars().barCooldownEndingSeconds end,
          setFunc = function(value) l.getSavedVars().barCooldownEndingSeconds = value ; l.updateWidgets(views.updateWidgetCooldown) end,
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barCooldownVisible end,
          width = "full",
          default = barSavedVarsDefaults.barCooldownEndingSeconds,
        },{
          type = "colorpicker",
          name = text("Line Ending Color"),
          tooltip = text("Line color when remaining time is below threshold"),
          getFunc = function() return unpack(l.getSavedVars().barCooldownEndingColor) end,
          setFunc = function(r,g,b,a) l.getSavedVars().barCooldownEndingColor={r,g,b}; l.updateWidgets(views.updateWidgetCooldown) end,
          width = "full",
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barCooldownVisible end,
          default = {
            r = barSavedVarsDefaults.barCooldownEndingColor[1],
            g = barSavedVarsDefaults.barCooldownEndingColor[2],
            b = barSavedVarsDefaults.barCooldownEndingColor[3],
          }
        },{
          type = "colorpicker",
          name = text("Low Priority Effect Color"),
          tooltip = text("Color for low priority effects (tail effects, Crux, etc.) displayed with angle brackets"),
          getFunc = function() return unpack(l.getSavedVars().barLowPriorityLabelColor) end,
          setFunc = function(r,g,b,a) l.getSavedVars().barLowPriorityLabelColor={r,g,b} end,
          width = "full",
          disabled = function() return not l.getSavedVars().barEnabled or not l.getSavedVars().barLabelEnabled end,
          default = {
            r = barSavedVarsDefaults.barLowPriorityLabelColor[1],
            g = barSavedVarsDefaults.barLowPriorityLabelColor[2],
            b = barSavedVarsDefaults.barLowPriorityLabelColor[3],
          }
        }
      }})
end)

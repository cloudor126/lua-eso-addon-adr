--========================================
--        vars
--========================================
local addon = ActionDurationReminder -- Addon#M
local settings = addon.load("Settings#M")
local l = {} -- #L
local m = {l=l} -- #M
local mWidget = {} -- #Widget

--========================================
--        l
--========================================
l.getSavedVars -- #()->(Bar#BarSavedVars)
= function()
  return settings.getSavedVars()
end

l.getLabelFont -- #()->(#string)
= function()
  return "$("..l.getSavedVars().barLabelFontName..")|"..l.getSavedVars().barLabelFontSize.."|thick-outline"
end

--========================================
--        m
--========================================
m.newWidget -- #(#number:slotNum,#boolean:shifted, #number:appendIndex)->(#Widget)
= function(slotNum, shifted, appendIndex)
  local savedVars = l.getSavedVars() -- Bar#BarSavedVars
  local inst = {} -- #Widget
  inst.slotNum = slotNum --#number
  inst.shifted = shifted --#boolean
  inst.appendIndex = appendIndex --#number
  --
  inst.visible = true
  local slot = ZO_ActionBar_GetButton(slotNum).slot --Control#Control
  local slotIcon = slot:GetNamedChild("Icon")
  local flipCard = slot:GetNamedChild("FlipCard")
  inst.slotIcon = slotIcon --Control#Control
  inst.flipCard = flipCard --Control#Control
  --========================================
  local backdrop = nil
  local background = nil
  local barCooldownThickness = savedVars.barCooldownThickness
  if shifted then
    local offsetX = savedVars.barShiftOffsetX
    local offsetY = savedVars.barShiftOffsetY
    backdrop = WINDOW_MANAGER:CreateControl(nil, slot, CT_TEXTURE)
    inst.backdrop = backdrop --TextureControl#TextureControl
    backdrop:SetDrawLayer(DL_BACKGROUND)
    if appendIndex then
      backdrop:SetAnchor(BOTTOM, slot, TOP, offsetX + (appendIndex-1) * 55, offsetY)
    else
      backdrop:SetAnchor(BOTTOM, slot, TOP, offsetX , offsetY)
    end
    backdrop:SetDimensions(50 - math.max(0, barCooldownThickness - 2), 50 - math.max(0, barCooldownThickness - 2))
    backdrop:SetTexture("esoui/art/actionbar/abilityframe64_up.dds")
    backdrop:SetTextureCoords(0, .625, 0, .8125)
    background = WINDOW_MANAGER:CreateControl(nil, backdrop, CT_TEXTURE)
    inst.background = background--TextureControl#TextureControl
    background:SetDrawLayer(DL_CONTROLS)
    background:SetAnchor(TOPLEFT, backdrop, TOPLEFT, 2, 2)
    background:SetAnchor(BOTTOMRIGHT, backdrop, BOTTOMRIGHT, -2, -2 )
  end
  local label = WINDOW_MANAGER:CreateControl(nil, backdrop or slotIcon, CT_LABEL)
  inst.label = label --LabelControl#LabelControl
  label:SetFont(l.getLabelFont())
  label:SetColor(1,1,1)
  label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
  label:SetVerticalAlignment(TEXT_ALIGN_BOTTOM)
  label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
  label:SetAnchor(BOTTOM, backdrop or slotIcon, BOTTOM, 0, savedVars.barLabelYOffset + (shifted and 1 or 3))
  label:SetDrawLayer(DL_TEXT)
  local countLabel = WINDOW_MANAGER:CreateControl(nil, backdrop or slotIcon, CT_LABEL)
  inst.countLabel = countLabel --LabelControl#LabelControl
  countLabel:SetFont(l.getLabelFont())
  countLabel:SetColor(1,1,1)
  countLabel:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
  countLabel:SetVerticalAlignment(TEXT_ALIGN_TOP)
  countLabel:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
  countLabel:SetAnchor(TOPRIGHT, backdrop or slotIcon, TOPRIGHT, 0, - savedVars.barLabelYOffset - 5)
  countLabel:SetDrawLayer(DL_TEXT)
  local cooldown = WINDOW_MANAGER:CreateControl(nil, backdrop or slot, CT_COOLDOWN)
  inst.cooldown = cooldown --CooldownControl#CooldownControl
  cooldown:SetDrawLayer(DL_BACKGROUND)
  if background then
    cooldown:SetAnchor( TOPLEFT, background, TOPLEFT, -barCooldownThickness,-barCooldownThickness )
    cooldown:SetAnchor( BOTTOMRIGHT, background, BOTTOMRIGHT,barCooldownThickness, barCooldownThickness )
  else
    cooldown:SetAnchor( CENTER, flipCard, CENTER)
    local slotWidth,slotHeight = slot:GetDimensions()
    cooldown:SetDimensions( slotWidth, slotHeight)
  end
  cooldown:SetFillColor(unpack(savedVars.barCooldownColor))
  if savedVars.barCooldownOpacity < 100 then cooldown:SetAlpha(savedVars.barCooldownOpacity/100) end
  inst.cdMark = 0
  return setmetatable(inst, {__index=mWidget})
end

m.updateWidgetCooldown -- #(#Widget:widget)->()
= function(widget)
  local savedVars = l.getSavedVars()
  if widget.cooldown then
    widget.cooldown:SetHidden(not savedVars.barCooldownVisible)
    widget.cooldown:SetFillColor(unpack(savedVars.barCooldownColor))
    if savedVars.barCooldownOpacity < 100 then
      widget.cooldown:SetAlpha(savedVars.barCooldownOpacity/100)
    else
      widget.cooldown:SetAlpha(1)
    end
  end
  local barCooldownThickness = savedVars.barCooldownThickness
  if widget.backdrop then
    widget.backdrop:SetDimensions(50-math.max(0,barCooldownThickness-2),50-math.max(0,barCooldownThickness-2))
  end
  if widget.background and widget.cooldown then
    widget.cooldown:ClearAnchors()
    widget.cooldown:SetAnchor( TOPLEFT, widget.background, TOPLEFT, -barCooldownThickness,-barCooldownThickness )
    widget.cooldown:SetAnchor( BOTTOMRIGHT, widget.background, BOTTOMRIGHT,barCooldownThickness, barCooldownThickness )
  end
end

m.updateWidgetFont -- #(#Widget:widget)->()
= function(widget)
  local font = l.getLabelFont()
  if widget.label then widget.label:SetFont(font) end
  if widget.countLabel then widget.countLabel:SetFont(font) end
end

m.updateWidgetLabelYOffset -- #(#Widget:widget)->()
= function(widget)
  if widget.label then
    widget.label:ClearAnchors()
    widget.label:SetAnchor(BOTTOM, widget.label:GetParent(), BOTTOM, 0, l.getSavedVars().barLabelYOffset +
      (widget.shifted and 1 or 3))
  end
  if widget.countLabel then
    widget.countLabel:ClearAnchors()
    widget.countLabel:SetAnchor(TOPRIGHT, widget.countLabel:GetParent(), TOPRIGHT, 0, - l.getSavedVars().barLabelYOffset - 5)
  end
end

m.updateWidgetShiftOffset -- #(#Widget:widget)->()
= function(widget)
  if not widget.shifted then return end
  local offsetX = l.getSavedVars().barShiftOffsetX
  local offsetY = l.getSavedVars().barShiftOffsetY
  if widget.backdrop then
    local slot = widget.backdrop:GetParent()
    widget.backdrop:ClearAnchors()
    if widget.appendIndex then
      widget.backdrop:SetAnchor(BOTTOM, slot, TOP, offsetX + (widget.appendIndex - 1) * 55, offsetY)
    else
      widget.backdrop:SetAnchor(BOTTOM, slot, TOP, offsetX , offsetY)
    end
  end
end



--========================================
--        mWidget
--========================================
mWidget.hide  -- #(#Widget:self)->()
= function(self)
  if self.backdrop then self.backdrop:SetHidden(true) end
  if self.background then self.background:SetHidden(true) end
  self.label:SetHidden(true)
  self.countLabel:SetHidden(true)
  self.cooldown:SetHidden(true)
  self.visible = false
  local _,_,_,_,flipOffset =  self.flipCard:GetAnchor(0)
  if flipOffset > 0 then
    local flipParent = self.flipCard:GetParent()
    self.flipCard:ClearAnchors()
    self.flipCard:SetAnchor(TOPLEFT, flipParent, TOPLEFT, 0, 0)
    self.flipCard:SetAnchor(BOTTOMRIGHT, flipParent, BOTTOMRIGHT, 0, 0)
  end
end

mWidget.updateCooldown = m.updateWidgetCooldown -- #(#Widget:self)->()

mWidget.updateFont = m.updateWidgetFont -- #(#Widget:self)->()

mWidget.updateLabelYOffset = m.updateWidgetLabelYOffset -- #(#Widget:self)->()

mWidget.updateShiftOffset = m.updateWidgetShiftOffset -- #(#Widget:self)->()

mWidget.updateWithAction -- #(#Widget:self, Models#Action:action,#number:now)->()
= function(self, action, now)
  self.visible = true
  if self.backdrop then self.backdrop:SetHidden(false) end
  if self.background then
    self.background:SetTexture(action.ability.icon)
    self.background:SetHidden(false)
  end
  local endTime = action:getEndTime()
  local remain = math.max(endTime-now,0)
  local hint = string.format('%.1f', remain/1000)
  if l.getSavedVars().barLabelIgnoreDecimal and remain/1000 > l.getSavedVars().barLabelIgnoreDeciamlThreshold then
    hint = string.format('%d', remain/1000)
  end
  self.label:SetText(hint)
  self.label:SetHidden(false)
  local stageInfo = action:getStageInfo()
  if action.stackCount and action.stackCount > 0 then
    self.countLabel:SetText(action.stackCount)
    self.countLabel:SetHidden(false)
  elseif stageInfo then
    self.countLabel:SetText(stageInfo)
    self.countLabel:SetHidden(false)
  else
    self.countLabel:SetHidden(true)
  end
  local cdMark = endTime
  if action:isUnlimited() then
    self.label:SetHidden(true)
    self.cooldown:SetHidden(true)
    return
  end
  if remain > 7000 and action:getDuration() > 8000 then
    cdMark = action.endTime - 7000
    if self.cdMark ~= cdMark then
      self.cdMark = cdMark
      local scale = action.duration/1000 - 7
      local scaledTotal = action.duration * scale
      local scaledRemain = remain * scale
      self.cooldown:StartCooldown(scaledRemain, scaledTotal, CD_TYPE_RADIAL, CD_TIME_TYPE_TIME_UNTIL, false )
    end
  elseif remain > 0 then
    if self.cdMark ~= cdMark then
      self.cdMark = cdMark
      self.cooldown:StartCooldown(remain, 8000, CD_TYPE_RADIAL, CD_TIME_TYPE_TIME_UNTIL, false )
    end
  else
    self.cdMark = 0
    local numSemiSeconds = math.floor((now-action:getEndTime())/200)
    if numSemiSeconds % 2 == 0 then
      self.label:SetHidden(true)
    end
  end
  local cdHidden = cdMark==0 or not l.getSavedVars().barCooldownVisible
  self.cooldown:SetHidden(cdHidden)
end


--========================================
--        register
--========================================
addon.register("Views#M", m)

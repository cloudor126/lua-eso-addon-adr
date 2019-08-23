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
    backdrop:SetDimensions(50 , 50)
    backdrop:SetTexture("esoui/art/actionbar/abilityframe64_up.dds")
    backdrop:SetTextureCoords(0, .625, 0, .8125)
    background = WINDOW_MANAGER:CreateControl(nil, backdrop, CT_TEXTURE)
    inst.background = background--TextureControl#TextureControl
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
  label:SetAnchor(BOTTOM, backdrop or slotIcon, BOTTOM, 0, shifted and (-savedVars.barLabelYOffsetInShift+1) or (-savedVars.barLabelYOffset + 3))
  local countLabel = WINDOW_MANAGER:CreateControl(nil, backdrop or slotIcon, CT_LABEL)
  inst.countLabel = countLabel --LabelControl#LabelControl
  countLabel:SetFont(l.getLabelFont())
  countLabel:SetColor(1,1,1)
  countLabel:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
  countLabel:SetVerticalAlignment(TEXT_ALIGN_TOP)
  countLabel:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
  countLabel:SetAnchor(TOPRIGHT, backdrop or slotIcon, TOPRIGHT, 0, - l.getSavedVars().barLabelYOffset - 5)
  inst.cdMark = 0
  return setmetatable(inst, {__index=mWidget})
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
    widget.label:SetAnchor(BOTTOM, widget.label:GetParent(), BOTTOM, 0,
      widget.shifted and (-l.getSavedVars().barLabelYOffsetInShift + 1) or (-l.getSavedVars().barLabelYOffset + 3))
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
  self.visible = false
  local _,_,_,_,flipOffset =  self.flipCard:GetAnchor(0)
  if flipOffset > 0 then
    local flipParent = self.flipCard:GetParent()
    self.flipCard:ClearAnchors()
    self.flipCard:SetAnchor(TOPLEFT, flipParent, TOPLEFT, 0, 0)
    self.flipCard:SetAnchor(BOTTOMRIGHT, flipParent, BOTTOMRIGHT, 0, 0)
  end
end

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
    return
  end
  if remain > 7000 and action:getDuration() > 8000 then
    cdMark = action.endTime - 7000
    if self.cdMark ~= cdMark then
      self.cdMark = cdMark
      local scale = action.duration/1000 - 7
      local scaledTotal = action.duration * scale
      local scaledRemain = remain * scale
    end
  elseif remain > 0 then
    if self.cdMark ~= cdMark then
      self.cdMark = cdMark
    end
  else
    self.cdMark = 0
    local numSemiSeconds = math.floor((now-action:getEndTime())/200)
    if numSemiSeconds % 2 == 0 then
      self.label:SetHidden(true)
    end
  end
end


--========================================
--        register
--========================================
addon.register("Views#M", m)

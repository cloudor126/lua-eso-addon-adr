--========================================
--        vars
--========================================
local addon = ActionDurationReminder -- Addon#M
local settings = addon.load("Settings#M")
local l = {} -- #L
local m = {l=l} -- #M
local mWidget = {} -- #Widget
local mCooldown = {} -- #Cooldown

--========================================
--        l
--========================================
l.getSavedVars -- #()->(Bar#BarSavedVars)
= function()
  return settings.getSavedVars()
end

l.getLabelFont -- #()->(#string)
= function()
  return "$("..l.getSavedVars().barLabelFontName..")|"..l.getSavedVars().barLabelFontSize.."|"..l.getSavedVars().barLabelFontStyle
end

l.getStackLabelFont -- #()->(#string)
= function()
  return "$("..l.getSavedVars().barStackLabelFontName..")|"..l.getSavedVars().barStackLabelFontSize.."|"..l.getSavedVars().barStackLabelFontStyle
end

l.debugIdList = {} -- #list<#number>
--========================================
--        m
--========================================
m.newCooldown -- #(Control#Control:background, #number:drawTier)->(#Cooldown)
= function(background, drawTier)
  local inst = {} -- #Cooldown
  inst.id = GetGameTimeMilliseconds()
  table.insert(l.debugIdList,inst.id)
  inst.background = background -- Control#Control
  inst.drawTier = drawTier -- #number
  inst.hidden = false
  inst.shifted = false
  inst.duration = 0 -- #number
  inst.endTime = 0 -- #number
  inst.topRight = nil -- TextureControl#TextureControl
  inst.right = nil -- TextureControl#TextureControl
  inst.bottom = nil -- TextureControl#TextureControl
  inst.left = nil -- TextureControl#TextureControl
  inst.topLeft = nil -- TextureControl#TextureControl
  inst.endingSeconds = l.getSavedVars().barCooldownEndingSeconds
  inst.endingColor = l.getSavedVars().barCooldownEndingColor
  inst.color = l.getSavedVars().barCooldownColor
  inst.alpha =  l.getSavedVars().barCooldownOpacity/100
  return setmetatable(inst, {__index=mCooldown})
end

m.newWidget -- #(#number:slotNum,#boolean:shifted, #number:appendIndex)->(#Widget)
= function(slotNum, shifted, appendIndex)
  local savedVars = l.getSavedVars() -- Bar#BarSavedVars
  local inst = {} -- #Widget
  inst.slotNum = slotNum --#number
  inst.shifted = shifted --#boolean
  inst.appendIndex = appendIndex --#number
  --
  inst.visible = true
  local slot = ZO_ActionBar_GetButton(slotNum, slotNum >8 and HOTBAR_CATEGORY_QUICKSLOT_WHEEL or nil).slot --Control#Control
  local slotIcon = slot:GetNamedChild("Icon")
  --  local flipCard = slot:GetNamedChild("FlipCard")
  inst.slotIcon = slotIcon --Control#Control
  --  inst.flipCard = flipCard --Control#Control
  --========================================
  local backdrop = nil
  local background = nil
  if shifted then
    local offsetX = savedVars.barShiftOffsetX
    local offsetY = savedVars.barShiftOffsetY
    backdrop = WINDOW_MANAGER:CreateControl(nil, slot, CT_TEXTURE) -- Control#Control
    if l.getSavedVars().barShowShiftScalePercent<100 then
      backdrop:SetScale(l.getSavedVars().barShowShiftScalePercent/100)
    end
    inst.backdrop = backdrop --TextureControl#TextureControl
    backdrop:SetDrawLayer(DL_BACKGROUND)
    if appendIndex then
      backdrop:SetAnchor(BOTTOM, slot, TOP, offsetX + (appendIndex-1) * 55, offsetY)
    else
      backdrop:SetAnchor(BOTTOM, slot, TOP, offsetX , offsetY)
    end
    backdrop:SetDimensions(50 , 50)
    backdrop:SetTexture("esoui/art/actionbar/abilityframe64_up.dds")
    background = WINDOW_MANAGER:CreateControl(nil, backdrop, CT_TEXTURE)
    inst.background = background--TextureControl#TextureControl
    local offset = dui and 4.2 or 2
    background:SetAnchor(TOPLEFT, backdrop, TOPLEFT, offset, offset)
    background:SetAnchor(BOTTOMRIGHT, backdrop, BOTTOMRIGHT, -offset, -offset )
  end
  local label = WINDOW_MANAGER:CreateControl(nil, backdrop or slotIcon, CT_LABEL)  --LabelControl#LabelControl
  inst.label = label --LabelControl#LabelControl
  label:SetFont(l.getLabelFont())
  label:SetColor(1,1,1)
  label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
  label:SetVerticalAlignment(TEXT_ALIGN_BOTTOM)
  label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
  if slotNum == 9 then
    label:SetAnchor(TOPLEFT, slotIcon, TOPLEFT, 5, 3)
    label:SetDrawTier(DT_HIGH)
  else
    label:SetAnchor(BOTTOM, backdrop or slotIcon, BOTTOM, 0, shifted and (-savedVars.barLabelYOffsetInShift+1) or (-savedVars.barLabelYOffset + 3))
  end
  local stackLabel = WINDOW_MANAGER:CreateControl(nil, backdrop or slotIcon, CT_LABEL)
  inst.stackLabel = stackLabel --LabelControl#LabelControl
  stackLabel:SetFont(l.getStackLabelFont())
  stackLabel:SetColor(1,1,1)
  stackLabel:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
  stackLabel:SetVerticalAlignment(TEXT_ALIGN_TOP)
  stackLabel:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
  stackLabel:SetAnchor(TOPRIGHT, backdrop or slotIcon, TOPRIGHT, 0, shifted and( - savedVars.barStackLabelYOffsetInShift - 5) or ( - savedVars.barStackLabelYOffset - 5))
  local stackLabel2 = WINDOW_MANAGER:CreateControl(nil, backdrop or slotIcon, CT_LABEL)
  inst.stackLabel2 = stackLabel2 --LabelControl#LabelControl
  stackLabel2:SetFont(l.getStackLabelFont())
  stackLabel2:SetColor(1,1,1)
  stackLabel2:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
  stackLabel2:SetVerticalAlignment(TEXT_ALIGN_TOP)
  stackLabel2:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
  stackLabel2:SetAnchor(TOPLEFT, backdrop or slotIcon, TOPLEFT, 2, shifted and( - savedVars.barStackLabelYOffsetInShift - 5) or ( - savedVars.barStackLabelYOffset - 5))
  
  inst.cooldown = m.newCooldown(backdrop or slot, backdrop and 0 or DT_HIGH) --#Cooldown
  inst.cooldown.shifted = shifted
  inst.cdMark = 0
  --
  return setmetatable(inst, {__index=mWidget})
end

m.updateWidgetCooldown -- #(#Widget:widget)->()
= function(widget)
  local savedVars = l.getSavedVars()
  if widget.cooldown then
    widget.cooldown:setHidden(not savedVars.barCooldownVisible)
    widget.cooldown:setColor(unpack(savedVars.barCooldownColor))
    widget.cooldown:setEndingSeconds(savedVars.barCooldownEndingSeconds)
    widget.cooldown:setEndingColor(unpack(savedVars.barCooldownEndingColor))
    if savedVars.barCooldownOpacity < 100 then
      widget.cooldown:setAlpha(savedVars.barCooldownOpacity/100)
    else
      widget.cooldown:setAlpha(1)
    end
  end
end

m.updateWidgetFont -- #(#Widget:widget)->()
= function(widget)
  if widget.label then widget.label:SetFont(l.getLabelFont()) end
  if widget.stackLabel then widget.stackLabel:SetFont(l.getStackLabelFont()) end
  if widget.stackLabel2 then widget.stackLabel2:SetFont(l.getStackLabelFont()) end
end

m.updateWidgetLabelYOffset -- #(#Widget:widget)->()
= function(widget)
  if widget.label then
    widget.label:ClearAnchors()
    widget.label:SetAnchor(BOTTOM, widget.label:GetParent(), BOTTOM, 0,
      widget.shifted and (-l.getSavedVars().barLabelYOffsetInShift + 1) or (-l.getSavedVars().barLabelYOffset + 3))
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

m.updateWidgetShiftScalePercent -- #(#Widget:widget)->()
= function(widget)
  if not widget.shifted then return end
  if widget.backdrop then
    widget.backdrop:SetScale(l.getSavedVars().barShowShiftScalePercent/100)
  end
end

m.updateWidgetStackLabelYOffset -- #(#Widget:widget)->()
= function(widget)
  if widget.stackLabel then
    widget.stackLabel:ClearAnchors()
    widget.stackLabel:SetAnchor(TOPRIGHT, widget.stackLabel:GetParent(), TOPRIGHT, 0,
      widget.shifted and (- l.getSavedVars().barStackLabelYOffsetInShift - 5) or (- l.getSavedVars().barStackLabelYOffset - 5))
  end
  if widget.stackLabel2 then
    widget.stackLabel2:ClearAnchors()
    widget.stackLabel2:SetAnchor(TOPLEFT, widget.stackLabel2:GetParent(), TOPLEFT, 2,
      widget.shifted and (- l.getSavedVars().barStackLabelYOffsetInShift - 5) or (- l.getSavedVars().barStackLabelYOffset - 5))
  end
end

--========================================
--        mCooldown
--========================================
mCooldown.createPart --#(#Cooldown:self)->(TextureControl#TextureControl)
= function(self)
  local part = self.background:CreateControl(nil, CT_TEXTURE) --TextureControl#TextureControl
  if self.drawTier and self.drawTier>0 then
    part:SetDrawTier(self.drawTier)
    part:SetDrawLayer(DL_TEXT)
  else
    part:SetDrawLevel(1)
  end
  part:SetColor(unpack(l.getSavedVars().barCooldownColor))
  local opacity = l.getSavedVars().barCooldownOpacity -- #number
  if opacity<100 then part:SetAlpha(opacity/100) end
  return part
end

mCooldown.draw -- #(#Cooldown:self, #number:duration, #number:endTime)->()
= function(self, duration, endTime)
  if self.duration~=duration or self.endTime ~= endTime then return end -- another start happened
  local remain = endTime - GetGameTimeMilliseconds()
  self:drawRemain(remain)
  if not self.hidden then
    zo_callLater(function()
      self:draw(duration, endTime)
    end,40) -- 25fps
  end
end

mCooldown.drawRemain -- #(#Cooldown:self, #number:remain, #boolean:shifted)->()
= function(self, remain)
  -- 0. check hidden
  if not l.getSavedVars().barCooldownVisible or self.duration == 0 or self.hidden or remain<=0 then
    local controlList = {self.topLeft,self.left,self.bottom,self.right, self.topRight} --#list<TextureControl#TextureControl>
    for key, var in pairs(controlList) do
      if var then var:SetHidden(true) end
    end
    return
  end
  local duration = self.duration
  local savedVars = l.getSavedVars()
  local shrink = 1
  local width,height = self.background:GetDimensions()
  if Azurah then
    local scale = Azurah:CheckModified('ZO_ActionBar1')
    if scale and scale ~= 1 then
      width = width / scale
      height = height / scale
    end
  end
  if self.shifted then
    local percent = l.getSavedVars().barShowShiftScalePercent
    if percent <100 then
      width = width *100/ percent
      height = height * 100 / percent
    end
  end
  width = width - l.getSavedVars().barCooldownThickness - 2*shrink
  height = height - l.getSavedVars().barCooldownThickness - 2*shrink
  -- 1. topRight
  if remain > duration * 7 / 8 then
    if not self.topRight then
      self.topRight = self:createPart()
    end
    local length = width /2 * math.min(1, remain*8/duration - 7)
    self.topRight:SetAnchor(TOPRIGHT,self.background,TOPRIGHT,-shrink,shrink)
    self.topRight:SetDimensions(length,savedVars.barCooldownThickness)
    self.topRight:SetHidden(false)
  else
    if self.topRight and not self.topRight:IsHidden() then self.topRight:SetHidden(true) end
  end
  -- 2. right
  if remain > duration * 5 / 8 then
    if not self.right then
      self.right = self:createPart()
    end
    local length = height * math.min(1, (remain*8/duration - 5)/2)
    self.right:SetAnchor(BOTTOMRIGHT, self.background, BOTTOMRIGHT,-shrink,-shrink)
    self.right:SetDimensions(savedVars.barCooldownThickness,length)
    self.right:SetHidden(false)
  else
    if self.right and not self.right:IsHidden() then self.right:SetHidden(true) end
  end
  -- 3. bottom
  if remain > duration * 3 / 8 then
    if not self.bottom then
      self.bottom = self:createPart()
    end
    local length = width * math.min(1, (remain*8/duration - 3)/2)
    self.bottom:SetAnchor(BOTTOMLEFT, self.background, BOTTOMLEFT,shrink,-shrink)
    self.bottom:SetDimensions(length,savedVars.barCooldownThickness)
    self.bottom:SetHidden(false)
  else
    if self.bottom and not self.bottom:IsHidden() then self.bottom:SetHidden(true) end
  end
  -- 4. left
  if remain > duration /8 then
    if not self.left then
      self.left = self:createPart()
    end
    local length = height * math.min(1,(remain * 8/duration-1)/2)
    self.left:SetAnchor(TOPLEFT, self.background, TOPLEFT,shrink,shrink)
    self.left:SetDimensions(savedVars.barCooldownThickness,length)
    self.left:SetHidden(false)
  else
    if self.left and not self.left:IsHidden() then self.left:SetHidden(true) end
  end
  -- 5. topLeft
  if remain >0 then
    if not self.topLeft then
      self.topLeft = self:createPart()
    end
    local length = width/2 * math.min(1, remain*8/duration)
    self.topLeft:SetAnchor(TOPRIGHT, self.background, TOP,0,shrink)
    self.topLeft:SetDimensions(length,savedVars.barCooldownThickness)
    self.topLeft:SetHidden(false)
  else
    if self.topLeft and not self.topLeft:IsHidden() then self.topLeft:SetHidden(true) end
  end
  -- $. updateColor
  self:updateColor(not self.noEnding and remain<self.endingSeconds*1000)
end

mCooldown.setAlpha -- #(#Cooldown:self, #number:alpha)->()
= function(self, alpha)
  self.alpha = alpha
end

mCooldown.setColor -- #(#Cooldown:self, #number:r, #number:g, #number:b, #number:a)->()
= function(self, r,g,b,a)
  self.color = {r,g,b,a}
end

mCooldown.setEndingColor -- #(#Cooldown:self, #number:r, #number:g, #number:b, #number:a)->()
= function(self, r,g,b,a)
  self.endingColor = {r,g,b,a}
end

mCooldown.setEndingSeconds -- #(#Cooldown:self, #number:endingSeconds)->()
= function(self, endingSeconds)
  self.endingSeconds = endingSeconds
end

mCooldown.setHidden -- #(#Cooldown:self, #boolean:hidden)->()
= function(self, hidden)
  if hidden == self.hidden then return end
  self.hidden = hidden
  self:draw(self.duration, self.endTime)
end

mCooldown.start -- #(#Cooldown:self, #number:remain, #number:duration, #boolean:noEnding)->()
= function(self, remain, duration, noEnding)
  local endTime = GetGameTimeMilliseconds() + remain
  if not self.hidden and self.duration == duration and self.endTime == endTime then
    return
  end
  self.endTime = endTime
  self.duration = duration
  self.hidden = false
  self.noEnding = noEnding
  self:draw(duration, self.endTime)
end

mCooldown.updateColor --#(#Cooldown:self, #boolean:ending)->()
= function(self, ending)
  local list = {self.topLeft,self.left,self.bottom,self.right,self.topRight} -- #list<TextureControl#TextureControl>
  for key, var in ipairs(list) do
    if var then
      var:SetColor(unpack(ending and self.endingColor or self.color))
      var:SetAlpha(self.alpha)
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
  self.stackLabel:SetHidden(true)
  self.stackLabel2:SetHidden(true)
  self.cooldown:setHidden(true)
  self.visible = false
end

mWidget.updateCooldown = m.updateWidgetCooldown -- #(#Widget:self)->()

mWidget.updateFont = m.updateWidgetFont -- #(#Widget:self)->()

mWidget.updateLabelYOffset = m.updateWidgetLabelYOffset -- #(#Widget:self)->()

mWidget.updateStackLabelYOffset = m.updateWidgetStackLabelYOffset -- #(#Widget:self)->()

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
  local otherInfo = action:getStageInfo() or action:getAreaEffectCount()
  -- label
  if l.getSavedVars().barLabelEnabled then
    local hint = string.format('%.1f', remain/1000)
    if l.getSavedVars().barLabelIgnoreDecimal and remain/1000 >= l.getSavedVars().barLabelIgnoreDeciamlThreshold then
      hint = string.format('%d', remain/1000)
    end
    self.label:SetText(hint)
    self.label:SetHidden(false)
  else
    self.label:SetHidden(true)
  end
  -- stack label
  if l.getSavedVars().barStackLabelEnabled then
    -- stackLabel
    if action.stackCount and action.stackCount > 0 then
      self.stackLabel:SetText(action.stackCount)
      self.stackLabel:SetHidden(false)
    elseif otherInfo then
      self.stackLabel:SetText(otherInfo)
      self.stackLabel:SetHidden(false)
    else
      self.stackLabel:SetHidden(true)
    end
    -- stackLabel2
    if action.stackCount2 and action.stackCount2 > 0 then
      self.stackLabel2:SetText(action.stackCount2)
      self.stackLabel2:SetHidden(false)
    else
      self.stackLabel2:SetHidden(true)
    end
  else
    self.stackLabel:SetHidden(true)
    self.stackLabel2:SetHidden(true)
  end
  -- cooldown
  local cdMark = endTime
  if action:isUnlimited() then
    self.label:SetHidden(true)
    self.cooldown:setHidden(true)
    return
  end
  local duration = action:getDuration()
  if remain > 7000 and duration > 8000 then
    cdMark = action.endTime - 7000
    if self.cdMark ~= cdMark then
      self.cdMark = cdMark
      local scale = duration/1000 - 7
      local scaledTotal = duration * scale
      local scaledRemain = scaledTotal - (duration - remain)
      self.cooldown:start(scaledRemain, scaledTotal, true)
    end
  elseif remain > 0 then
    if self.cdMark ~= cdMark then
      self.cdMark = cdMark
      self.cooldown:start(remain, 8000, otherInfo == '1/2')
    end
  else
    self.cdMark = 0
    local numSemiSeconds = math.floor((now-action:getEndTime())/200)
    if numSemiSeconds % 2 == 0 then
      self.label:SetHidden(true)
    end
  end
  local cdHidden = self.cdMark==0 or not l.getSavedVars().barCooldownVisible
  self.cooldown:setHidden(cdHidden)
end

mWidget.updateWithSlot -- #(#Widget:self, #number:slotNum)->()
= function(self, slotNum)
  self.visible = true
  if self.backdrop then self.backdrop:SetHidden(false) end
  if self.background then
    local texture = GetSlotTexture(slotNum,2-GetActiveWeaponPairInfo())
    if texture and texture:len()>0 then self.background:SetTexture(texture)
      self.background:SetHidden(false)
    else
      self.background:SetHidden(true)
    end
  end
  -- label
  self.label:SetHidden(true)
  -- stack label
  self.stackLabel:SetHidden(true)
  self.stackLabel2:SetHidden(true)
  -- cooldown
  self.cooldown:setHidden(true)
end
--========================================
--        register
--========================================
addon.register("Views#M", m)

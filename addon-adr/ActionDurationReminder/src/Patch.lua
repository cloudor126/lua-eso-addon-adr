--========================================
--        vars
--========================================
---@type adr.addon.M
local addon = ActionDurationReminder
---@type adr.settings.M
local settings = addon.load("Settings#M")
---@type adr.models.M
local models = addon.load("Models#M")
---@type adr.core.M
local core = addon.load("Core#M")
local l = {}
local m = { l = l }

--========================================
--        types
--========================================
---扩展 adr.settings.SavedVars:本模块持久化字段,与下方 defaults 一一对应
---@class adr.settings.SavedVars
---@field patchMoveBarsEnabled? boolean
---@type adr.settings.SavedVars
local patchSavedVarsDefaults = {
  patchMoveBarsEnabled = true,
}

---矩形边界(上下左右)
---@class adr.patch.Rect
---@field left? number
---@field top? number
---@field right? number
---@field bottom? number

---性条栏锚点信息
---@class adr.patch.Info
---@field point? number
---@field relativeTo? Control
---@field relativePoint? number
---@field offsetX? number
---@field offsetY? number
---@field bottom? number
---@field newRect? adr.patch.Rect

--========================================
--        l
--========================================
---@type table<string, adr.patch.Info>
l.hudInfo = {}
l.newRectReady = false
l.shifted = false

---@type fun(rectList: adr.patch.Rect[], name: string, hud: Control, gap: number): adr.patch.Rect, number, number
l.computeNewOffsetY = function(rectList, name, hud, gap)
  ---@type adr.patch.Rect
  local hudRect = {
    left = hud:GetLeft(),
    right = hud:GetRight(),
    top = hud:GetTop(), -- bar have out margin
    bottom = hud:GetBottom(), -- bar have out margin
  }
  local delta = 0
  for _, rect in pairs(rectList) do
    delta = delta + l.moveUp(hudRect, rect, gap)
  end
  return hudRect, l.hudInfo[name].offsetY + delta, l.hudInfo[name].bottom + delta
end

---@type fun(): adr.settings.SavedVars
l.getSavedVars = function()
  return settings.getSavedVars()
end

---@type fun(movingRect: adr.patch.Rect, rect: adr.patch.Rect, gap: number): number
l.moveUp = function(movingRect, rect, gap)
  if movingRect.left > rect.right or movingRect.right < rect.left then
    return 0
  end
  if movingRect.bottom + gap < rect.top or movingRect.top - gap > rect.bottom then
    return 0
  end
  local delta = rect.top - gap - movingRect.bottom
  movingRect.top = movingRect.top + delta
  movingRect.bottom = movingRect.bottom + delta
  return delta
end

---@type fun()
l.onCoreUpdate = function()
  -- 1.1 check if enabled
  if not l.getSavedVars().patchMoveBarsEnabled then
    return
  end
  -- 1.2 check if we have done
  local shiftBarVisible = false
  local barSavedVars = settings.getSavedVars()
  if barSavedVars.barShowShift then
    for id, action in pairs(core.getIdActionMap()) do
      if action.flags.shifted then
        shiftBarVisible = true
        break
      end
    end
  end
  if not shiftBarVisible and not l.shifted then
    return
  end
  if shiftBarVisible and l.shifted then
    return
  end
  -- 2. collect info
  local gap = 5
  ---@type table<string, Control>
  local hudTable = {
    hb = ZO_PlayerAttributeHealth,
    mb = ZO_PlayerAttributeMagicka,
    sb = ZO_PlayerAttributeStamina,
    bb = ZO_BuffDebuffTopLevelSelfContainer,
  }
  -- 2.1 record their original info
  for name, hud in pairs(hudTable) do
    if not l.hudInfo[name] then
      local _, point, relativeTo, relativePoint, offsetX, offsetY = hud:GetAnchor(0)
      local bottom = hud:GetBottom()
      l.hudInfo[name] = {
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        offsetX = offsetX,
        offsetY = offsetY,
        bottom = bottom,
      }
    end
  end

  -- 2.2 compute newRect
  if not l.newRectReady then
    local rectList = {}
    local slot3 = ZO_ActionBar_GetButton(3).slot
    local slot7 = ZO_ActionBar_GetButton(7).slot
    local shiftY = -50 - gap
    local offsetX = barSavedVars.barShiftOffsetX
    local offsetY = barSavedVars.barShiftOffsetY
    rectList[#rectList + 1] = {
      top = slot3:GetTop() + shiftY + offsetY,
      bottom = slot3:GetBottom() + shiftY + offsetY,
      left = slot3:GetLeft() + offsetX,
      right = slot7:GetRight() + offsetX,
    }
    local nameList = { "hb", "mb", "sb", "bb" }
    table.sort(nameList, function(name1, name2)
      return hudTable[name1]:GetBottom() > hudTable[name2]:GetBottom()
    end)
    for index = 1, #nameList do
      local name = nameList[index]
      local hud = hudTable[name]
      local hudRect, newOffsetY, newBottom = l.computeNewOffsetY(rectList, name, hud, gap)
      rectList[#rectList + 1] = hudRect
      l.hudInfo[name].newRect = hudRect
    end
    l.newRectReady = true
  end
  -- 3. check bottom to set anchor
  for name, hud in pairs(hudTable) do
    local info = l.hudInfo[name]
    local bottom = shiftBarVisible and info.newRect.bottom or info.bottom
    if bottom ~= hud:GetBottom() then
      hud:ClearAnchors()
      if shiftBarVisible then
        hud:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, info.newRect.left, info.newRect.top)
        hud:SetAnchor(BOTTOMRIGHT, GuiRoot, TOPLEFT, info.newRect.right, info.newRect.bottom)
      else
        hud:SetAnchor(info.point, info.relativeTo, info.relativePoint, info.offsetX, info.offsetY)
      end
    end
  end
  -- 4. reset data
  l.shifted = shiftBarVisible
  if not shiftBarVisible then
    l.hudInfo = {}
    l.newRectReady = false
  end
end

--========================================
--        m
--========================================

--========================================
--        register
--========================================
addon.extend(core.EXTKEY_UPDATE, l.onCoreUpdate)

addon.extend(settings.EXTKEY_ADD_DEFAULTS, function()
  settings.addDefaults(patchSavedVarsDefaults)
end)

addon.extend(settings.EXTKEY_ADD_MENUS, function()
  local text = addon.text
  settings.addMenuOptions({
    type = "submenu",
    name = text("Patch"),
    controls = {
      {
        type = "checkbox",
        name = text("Auto-Move Attribute Bars"),
        tooltip = text("Automatically reposition health/magicka/stamina bars to avoid overlap with timer bars"),
        getFunc = function()
          return l.getSavedVars().patchMoveBarsEnabled
        end,
        setFunc = function(value)
          l.getSavedVars().patchMoveBarsEnabled = value
        end,
        width = "full",
        default = patchSavedVarsDefaults.patchMoveBarsEnabled,
      },
    },
  })
end)

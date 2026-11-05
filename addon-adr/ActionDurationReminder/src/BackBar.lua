--========================================
--        vars
--========================================
---@type adr.addon.M
local addon = ActionDurationReminder
---@type adr.settings.M
local settings = addon.load("Settings#M")
---@type adr.core.M
local core = addon.load("Core#M")
local l = {}
---@type adr.backbar.M
local m = { l = l }

--========================================
--        types
--========================================
---BackBar模块公开表(addon.register("BackBar#M"))
---双bar预设(dynamic/static)的第二行：原生 ActionButton 克隆引擎。
---克隆以 槽号+40 构造(控件名 ActionButton43..48，避开原生 1..8 与 FAB 的 +20)，
---构造后把 slot.slotNum/button.slotNum 重映射回真实槽位 3..8，
---使原生 HandleSlotChanged/UpdateState/UpdateUsable 刷新链直接生效
---(图标、不可用发暗、toggle 高亮、冷却均为原生渲染)。
---@class adr.backbar.M
---@field isActive? fun(): boolean
---@field getSlotControl? fun(slotNum: number): Control|nil

--========================================
--        l
--========================================
local CLONE_SLOT_OFFSET = 40
local EVENT_NAME = "ADRBackBar"
local ROW_GAP_Y = 4

---@type table<number, table> slotNum(3..8) -> ActionButton克隆
l.buttons = {}
---@type Control|nil
l.container = nil
---@type boolean 行已激活(事件已注册)
l.active = false
---@type number|nil 当前克隆行对应的非激活武器条
l.currentHotbar = nil

---@type fun(): adr.settings.SavedVars
l.getSavedVars = function()
  return settings.getSavedVars()
end

---当前非激活武器条(主副条之外的热栏——攻城/施法条等——返回 nil)
---@type fun(): number|nil
l.inactiveHotbar = function()
  local active = GetActiveHotbarCategory()
  if active == HOTBAR_CATEGORY_PRIMARY then
    return HOTBAR_CATEGORY_BACKUP
  end
  if active == HOTBAR_CATEGORY_BACKUP then
    return HOTBAR_CATEGORY_PRIMARY
  end
  return nil
end

---平台相关的按钮间距(与原生 KEYBOARD/GAMEPAD_CONSTANTS 对齐)
---@type fun(): number, number, number
l.platformOffsets = function()
  if IsInGamepadPreferredMode() then
    return 10, 65, 6
  end
  return 2, 62, ROW_GAP_Y
end

---是否佩戴 Oakensoul(无副武器条)
---@type fun(): boolean
l.hasOakensoul = function()
  return GetItemLinkIcon(GetItemLink(BAG_WORN, EQUIP_SLOT_RING1)):find("oakensoul") ~= nil
    or GetItemLinkIcon(GetItemLink(BAG_WORN, EQUIP_SLOT_RING2)):find("oakensoul") ~= nil
end

---隐藏克隆大招按钮上的原生装饰(充能条/就绪特效/肩键提示等属于激活条)
---@type fun(button: table)
l.hideUltimateDecorations = function(button)
  local decorations = {
    "UltimateBar",
    "LeadingEdge",
    "FillAnimationLeft",
    "FillAnimationRight",
    "ReadyBurst",
    "ReadyLoop",
    "LeftKeybind",
    "RightKeybind",
    "Decoration",
    "Frame",
  }
  for i = 1, #decorations do
    local child = button.slot:GetNamedChild(decorations[i])
    if child then
      child:SetHidden(true)
    end
  end
end

---布局：克隆行锚在原生条正上方，X 与原生条对齐(3号槽对齐，其余链式排布)
---@type fun()
l.layoutRow = function()
  local first = l.buttons[3]
  if not first or not l.container then
    return
  end
  local abilityGap, ultGap, gapY = l.platformOffsets()
  local nativeSlot3 = ZO_ActionBar_GetButton(3).slot
  first.slot:ClearAnchors()
  first.slot:SetAnchor(BOTTOMLEFT, nativeSlot3, TOPLEFT, 0, -gapY)
  for slotNum = 4, 7 do
    local button = l.buttons[slotNum]
    button.slot:ClearAnchors()
    button:ApplyAnchor(l.buttons[slotNum - 1].slot, abilityGap)
  end
  local ult = l.buttons[8]
  ult.slot:ClearAnchors()
  ult:ApplyAnchor(l.buttons[7].slot, ultGap)
end

---同步单个克隆槽位(原生刷新链：图标/actionId/状态/不可用发暗)
---@type fun(slotNum: number, hotbar: number)
l.syncSlot = function(slotNum, hotbar)
  local button = l.buttons[slotNum]
  if not button then
    return
  end
  button.slot.hotbarCategory = hotbar
  button.button.hotbarCategory = hotbar
  button:HandleSlotChanged(hotbar)
end

---同步整行(换武器/全量刷新)
---@type fun()
l.syncAll = function()
  if not l.container then
    return
  end
  local hotbar = l.inactiveHotbar()
  l.currentHotbar = hotbar
  if not hotbar then
    l.container:SetHidden(true)
    return
  end
  l.container:SetHidden(false)
  for slotNum = 3, 8 do
    l.syncSlot(slotNum, hotbar)
  end
end

---创建克隆行(幂等)
---@type fun()
l.createRow = function()
  if l.container then
    return
  end
  local parent = ZO_ActionBar_GetButton(3).slot:GetParent()
  l.container = WINDOW_MANAGER:CreateControl("ADRBackBarRow", parent, CT_CONTROL)
  local hotbar = l.inactiveHotbar() or HOTBAR_CATEGORY_BACKUP
  for slotNum = 3, 8 do
    local template = slotNum == 8 and "ZO_UltimateActionButton" or "ZO_ActionButton"
    local button = ActionButton:New(
      slotNum + CLONE_SLOT_OFFSET,
      ACTION_BUTTON_TYPE_VISIBLE,
      l.container,
      template,
      hotbar
    )
    -- 重映射到真实槽位，原生刷新链(GetSlot/GetHotbarCategory)即取到真实数据
    button.slot.slotNum = slotNum
    button.button.slotNum = slotNum
    button.slot.hotbarCategory = hotbar
    button.button.hotbarCategory = hotbar
    button:SetShowBindingText(false)
    if slotNum == 8 then
      l.hideUltimateDecorations(button)
    end
    l.buttons[slotNum] = button
  end
  l.layoutRow()
  l.syncAll()
end

---重应用平台模板(键盘/手柄切换)
---@type fun()
l.applyPlatformStyle = function()
  if not l.container then
    return
  end
  for slotNum = 3, 8 do
    local button = l.buttons[slotNum]
    local base = slotNum == 8 and "ZO_UltimateActionButton" or "ZO_ActionButton"
    button:ApplyStyle(ZO_GetPlatformTemplate(base))
    if slotNum == 8 then
      l.hideUltimateDecorations(button)
    end
  end
  l.layoutRow()
  l.syncAll()
end

---@type fun()
l.registerEvents = function()
  local EM = GetEventManager()
  EM:RegisterForEvent(EVENT_NAME, EVENT_HOTBAR_SLOT_UPDATED, function(_, slotNum, hotbarCategory)
    if l.buttons[slotNum] and hotbarCategory == l.currentHotbar then
      l.syncSlot(slotNum, hotbarCategory)
    end
  end)
  EM:RegisterForEvent(EVENT_NAME, EVENT_HOTBAR_SLOT_STATE_UPDATED, function(_, slotNum, hotbarCategory)
    local button = l.buttons[slotNum]
    if button and hotbarCategory == l.currentHotbar then
      button:UpdateState()
    end
  end)
  EM:RegisterForEvent(EVENT_NAME, EVENT_ACTION_SLOTS_ACTIVE_HOTBAR_UPDATED, function()
    l.syncAll()
  end)
  EM:RegisterForEvent(EVENT_NAME, EVENT_ACTION_SLOTS_ALL_HOTBARS_UPDATED, function()
    l.syncAll()
  end)
  EM:RegisterForEvent(EVENT_NAME, EVENT_PLAYER_ACTIVATED, function()
    l.syncAll()
  end)
  EM:RegisterForEvent(EVENT_NAME, EVENT_INVENTORY_SINGLE_SLOT_UPDATE, function()
    l.syncAll()
  end)
  EM:AddFilterForEvent(EVENT_NAME, EVENT_INVENTORY_SINGLE_SLOT_UPDATE, REGISTER_FILTER_BAG_ID, BAG_WORN)
end

---@type fun()
l.unregisterEvents = function()
  local EM = GetEventManager()
  local events = {
    EVENT_HOTBAR_SLOT_UPDATED,
    EVENT_HOTBAR_SLOT_STATE_UPDATED,
    EVENT_ACTION_SLOTS_ACTIVE_HOTBAR_UPDATED,
    EVENT_ACTION_SLOTS_ALL_HOTBARS_UPDATED,
    EVENT_PLAYER_ACTIVATED,
    EVENT_INVENTORY_SINGLE_SLOT_UPDATE,
  }
  for i = 1, #events do
    EM:UnregisterForEvent(EVENT_NAME, events[i])
  end
end

---激活克隆行(双bar预设)
---@type fun()
l.activate = function()
  local ok, err = pcall(l.createRow)
  if not ok then
    addon.debug("[BB]create row failed: %s", tostring(err))
    return
  end
  l.active = true
  l.registerEvents()
end

---停用克隆行(切回经典预设/关闭计时条)
---@type fun()
l.deactivate = function()
  l.unregisterEvents()
  l.active = false
  if l.container then
    l.container:SetHidden(true)
  end
end

---@type fun()
l.onCoreUpdate = function()
  local sv = l.getSavedVars()
  local want = sv.barEnabled and sv.barPreset ~= "classic"
  if want and not l.active then
    l.activate()
  elseif not want and l.active then
    l.deactivate()
  end
  if l.active and l.container then
    -- Oakensoul 或非武器热栏(攻城等)时隐藏第二行；恢复时全量重同步
    if l.hasOakensoul() or l.inactiveHotbar() == nil then
      l.container:SetHidden(true)
      l.currentHotbar = nil
    elseif l.container:IsControlHidden() then
      l.syncAll()
    end
  end
end

--========================================
--        m
--========================================
---@type fun(): boolean
m.isActive = function()
  return l.active
end

---@type fun(slotNum: number): Control|nil
m.getSlotControl = function(slotNum)
  local button = l.buttons[slotNum]
  return button and button.slot or nil
end

--========================================
--        register
--========================================
addon.register("BackBar#M", m)

addon.register("BackBar", m)

addon.extend(core.EXTKEY_UPDATE, l.onCoreUpdate)

if ZO_PlatformStyle then
  ZO_PlatformStyle:New(function()
    if l.active then
      l.applyPlatformStyle()
    end
  end)
end

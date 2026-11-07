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
---@field getEffectivePreset? fun(): string
---@field getSlotControl? fun(slotNum: number): Control|nil
---@field updateScale? fun()
---@field updateLayout? fun()

--========================================
--        l
--========================================
local CLONE_SLOT_OFFSET = 40
local EVENT_NAME = "ADRBackBar"
local ROW_GAP_Y = 4

---扩展 adr.settings.SavedVars:本模块持久化字段
---@class adr.settings.SavedVars
---@field backBarDimAlpha? number
---@field backBarDesaturation? number
---@type adr.settings.SavedVars
local backBarSavedVarsDefaults = {
  backBarDimAlpha = 50,
  backBarDesaturation = 50,
}

---@type boolean 静态预设下原生条是否被拍升(退出/切回动态时需还原)
l.nativeLifted = false

---@type boolean 静态双克隆行已接管(原生槽隐藏中)
l.staticEngaged = false
---@type boolean 静态克隆行创建失败闭锁(本会话不再重试)
l.staticRowsFailed = false
---@type table<number, table> 静态主手行 slotNum(3..8) -> 克隆(恒绑定 PRIMARY)
l.staticPrimary = {}
---@type table<number, table> 静态副手行 slotNum(3..8) -> 克隆(恒绑定 BACKUP)
l.staticBackup = {}

---@type table<number, table> slotNum(3..8) -> ActionButton克隆(动态/经典用)
l.buttons = {}
---@type Control|nil 纯显隐用分组容器(不参与定位/缩放，锚点语义零风险)
l.container = nil
---@type boolean 行已激活(事件已注册)
l.active = false
---@type boolean 克隆行创建失败闭锁(本会话不再重试)
l.createFailed = false
---@type number|nil 当前克隆行对应的非激活武器条
l.currentHotbar = nil
---@type string|nil 上次已应用布局的预设(切换预设时触发重布局)
l.lastAppliedPreset = nil
---@type boolean 静态布局首次应用提示(每会话一次)
l.staticAppliedNotified = false
---@type boolean 经典模式：克隆行仅显示有计时的槽(可见性由 Bar 模块每帧驱动)
l.classicMode = false
---@type table<number, boolean>|nil 经典模式下各槽可见集(事件同步后重应用)
l.classicVisibleMap = nil

---冲突检测(会话级)：FAB 自带完整双bar，存在时硬回退①；
---BUI/Azurah 只会整体移动/换肤动作条，本模块锚点为相对锚可跟随，仅警告不降级；每次会话提示一次
---@type fun(): string
l.effectivePreset = function()
  local preset = l.getSavedVars().barPreset
  if preset == "classic" then
    return "classic"
  end
  if _G.FancyActionBar then
    l.notifyConflict("fancy")
    return "classic"
  end
  if preset == "static" and (_G.BanditsUserInterface or _G.BUI or _G.Azurah) then
    l.notifyConflict("mover")
  end
  return preset
end

---@type string|nil
l.conflictNotified = nil

---@type fun(kind: string)
l.notifyConflict = function(kind)
  if l.conflictNotified == kind then
    return
  end
  l.conflictNotified = kind
  local key = kind == "fancy" and "ADR double bar disabled: FancyActionBar+ detected"
    or "ADR static bar warning: a bar-mover addon was detected"
  d(string.format("[ADR] %s", addon.text(key)))
end

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
---返回：技能间距, 大招间距, 行间隙, 切手按钮默认锚X, 切手按钮默认锚Y
---@type fun(): number, number, number, number, number
l.platformOffsets = function()
  if IsInGamepadPreferredMode() then
    return 10, 65, 6, 61, 4
  end
  return 2, 62, ROW_GAP_Y, 59, -4
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

---平台原生模板尺寸(与 actionbutton.xml 的 Keyboard/Gamepad 模板一致)；
---不用 GetWidth 测量：ESO 返回的是已含 scale 的屏幕值，缩放后会越量越小
local PLATFORM_DIMS = {
  keyboard = { ability = 50, ult = 50 },
  gamepad = { ability = 64, ult = 70 },
}

---测量克隆技能段(3-7)原始尺寸(本地像素，平台常量)
---@type fun(): number, number
l.measureRowDims = function()
  local abilityGap = l.platformOffsets()
  local dims = IsInGamepadPreferredMode() and PLATFORM_DIMS.gamepad or PLATFORM_DIMS.keyboard
  local width = dims.ability * 5 + abilityGap * 4
  return width, dims.ability
end

---激活行样式：全亮(静态双克隆中逻辑上对应原生条的那一行不吃比例/暗化)
---@type fun(button: table)
l.applyActiveStyle = function(button)
  if button.icon then
    button.icon:SetAlpha(1)
    button.icon:SetDesaturation(0)
  end
end

---应用克隆槽缩放：动态/经典=统一比例；静态=激活行100%、非激活行用比例
---@type fun()
l.applyScale = function()
  local s = l.getSavedVars().barShowShiftScalePercent / 100
  if l.staticEngaged then
    l.applyStaticRoles()
    return
  end
  for slotNum = 3, 8 do
    local button = l.buttons[slotNum]
    if button then
      button.slot:SetScale(s)
    end
  end
end

---布局：动态预设——每个克隆槽独立 BOTTOM 锚到对应原生槽 TOP(offset 0,0)。
---水平 offset 为 0，乘不乘 scale 都精确：每个槽居中于对应原生槽正上方，
---第三对第三、第五对第五、大招对大招逐槽成立
---@type fun()
l.layoutDynamic = function()
  if not l.container or not l.buttons[3] then
    return
  end
  local _, _, gapY = l.platformOffsets()
  for slotNum = 3, 8 do
    local nativeButton = ZO_ActionBar_GetButton(slotNum)
    local button = l.buttons[slotNum]
    button.slot:ClearAnchors()
    button.slot:SetAnchor(BOTTOM, nativeButton.slot, TOP, 0, -gapY)
  end
  l.applyScale()
end

---按键提示(ButtonText)固定/还原：静态下原生槽被隐藏，键提示重父到 ZO_ActionBar1
---并钉在原始屏幕位置；退出静态时还原父级与原生锚形(TOP→slot.BOTTOM)
l.keybindsPinned = false

---@type fun()
l.pinKeybinds = function()
  if l.keybindsPinned then
    return
  end
  local weaponSwap = ZO_ActionBar1 and ZO_ActionBar1:GetNamedChild("WeaponSwap")
  if not weaponSwap then
    return
  end
  local abilityGap, ultGap, _, swapX, swapY = l.platformOffsets()
  local dims = IsInGamepadPreferredMode() and PLATFORM_DIMS.gamepad or PLATFORM_DIMS.keyboard
  local textOff = IsInGamepadPreferredMode() and -6 or 1
  local swapW, swapH = weaponSwap:GetWidth(), weaponSwap:GetHeight()
  for slotNum = 3, 8 do
    local nb = ZO_ActionBar_GetButton(slotNum)
    local text = nb and nb.slot and nb.slot:GetNamedChild("ButtonText")
    if text then
      local isUlt = slotNum == 8
      local w = isUlt and dims.ult or dims.ability
      local x = swapX + swapW + abilityGap
        + (isUlt and (4 * (dims.ability + abilityGap) + dims.ability + ultGap)
            or ((slotNum - 3) * (dims.ability + abilityGap)))
        + w / 2
      local y = swapY + swapH / 2 + w / 2 + textOff
      -- 重父到 ZO_ActionBar1：静态下原生槽被隐藏，子控件需独立父级才能保持可见
      text:SetParent(ZO_ActionBar1)
      text:ClearAnchors()
      text:SetAnchor(TOP, ZO_ActionBar1, TOPLEFT, x, y)
    end
  end
  l.keybindsPinned = true
end

---@type fun()
l.unpinKeybinds = function()
  if not l.keybindsPinned then
    return
  end
  l.keybindsPinned = false
  local textOff = IsInGamepadPreferredMode() and -6 or 1
  for slotNum = 3, 8 do
    local nb = ZO_ActionBar_GetButton(slotNum)
    local text = nb and nb.slot and nb.slot:GetNamedChild("ButtonText")
    if text then
      text:ClearAnchors()
      text:SetAnchor(TOP, nb.slot, BOTTOM, 0, textOff)
    end
  end
end

---静态下用淡入淡出时间线替换原生按钮的翻转时间线：原生代码在换武器时无条件
---静态克隆槽 X 偏移(切手基准，屏幕单位)：技能 3-7 链式，大招在技能段+原生大招间距处
---@type fun(slotNum: number, dims: table, abilityGap: number, ultGap: number): number
l.staticOffsetX = function(slotNum, dims, abilityGap, ultGap)
  if slotNum == 8 then
    return abilityGap + 4 * (dims.ability + abilityGap) + dims.ability + ultGap + dims.ult / 2
  end
  return abilityGap + (slotNum - 3) * (dims.ability + abilityGap) + dims.ability / 2
end

---静态预设：双克隆行。主手行(P)恒在上、副手行(B)恒在下，位置永不变化；
---仅隐藏原生6个技能按钮(切手/药剂/伴侣等全部不动)；键位数字钉在原位；
---激活行 100% 尺寸全亮(不吃比例/暗化)，非激活行用比例+暗化；换武器仅互换明暗/尺寸角色，
---内容永不重刷(两行各自恒绑定自己的武器集)
---@type fun()
l.layoutStatic = function()
  if not l.container or not l.buttons[3] then
    return
  end
  if l.hasOakensoul() or l.inactiveHotbar() == nil then
    l.exitStatic()
    return
  end
  if not l.createStaticRows() then
    l.layoutDynamic()
    return
  end
  local abilityGap, ultGap, gapY, swapX, swapY = l.platformOffsets()
  local weaponSwap = ZO_ActionBar1:GetNamedChild("WeaponSwap")
  local dims = IsInGamepadPreferredMode() and PLATFORM_DIMS.gamepad or PLATFORM_DIMS.keyboard
  -- 首次应用时确认提示(便于验证静态布局确实生效)
  if not l.staticAppliedNotified then
    l.staticAppliedNotified = true
    d(string.format("[ADR] %s", addon.text("ADR static double bar applied")))
  end
  local swapW = weaponSwap:GetWidth()
  local swapH = weaponSwap:GetHeight()
  local bottomCenterY = swapY + swapH / 2
  local topCenterY = bottomCenterY - dims.ability - gapY
  -- 键位数字钉在原位(重父到 ZO_ActionBar1 以独立于被隐藏的原生槽)
  l.pinKeybinds()
  -- 隐藏原生6个技能按钮(仅此6个；切手/药剂/伴侣大招不动)
  for slotNum = 3, 8 do
    ZO_ActionBar_GetButton(slotNum).slot:SetHidden(true)
  end
  -- 隐藏动态单克隆行，展示两静态行；位置为绝对坐标(锚点 offset 为屏幕单位，
  -- 不随槽自身 scale 变化)
  for slotNum = 3, 8 do
    l.buttons[slotNum].slot:SetHidden(true)
    local x = swapX + swapW + abilityGap
      + (slotNum == 8 and (4 * (dims.ability + abilityGap) + dims.ability + ultGap + dims.ult / 2)
        or ((slotNum - 3) * (dims.ability + abilityGap) + dims.ability / 2))
    local pButton = l.staticPrimary[slotNum]
    pButton.slot:ClearAnchors()
    pButton.slot:SetAnchor(CENTER, ZO_ActionBar1, TOPLEFT, x, topCenterY)
    pButton.slot:SetHidden(false)
    local bButton = l.staticBackup[slotNum]
    bButton.slot:ClearAnchors()
    bButton.slot:SetAnchor(CENTER, ZO_ActionBar1, TOPLEFT, x, bottomCenterY)
    bButton.slot:SetHidden(false)
  end
  l.staticEngaged = true
  l.applyStaticRoles()
end

---退出静态：恢复原生槽显示、还原键位数字、隐藏两静态行
---@type fun()
l.exitStatic = function()
  if not l.staticEngaged then
    return
  end
  l.staticEngaged = false
  for slotNum = 3, 8 do
    ZO_ActionBar_GetButton(slotNum).slot:SetHidden(false)
    l.staticPrimary[slotNum].slot:SetHidden(true)
    l.staticBackup[slotNum].slot:SetHidden(true)
    l.buttons[slotNum].slot:SetHidden(false)
  end
  l.unpinKeybinds()
end

---静态角色应用：激活行 100%+全亮，非激活行 比例+暗化；换武器仅调此函数
---@type fun()
l.applyStaticRoles = function()
  if not l.staticEngaged then
    return
  end
  local s = l.getSavedVars().barShowShiftScalePercent / 100
  local active = GetActiveHotbarCategory()
  local activeSet = active == HOTBAR_CATEGORY_PRIMARY and l.staticPrimary or l.staticBackup
  local inactiveSet = active == HOTBAR_CATEGORY_PRIMARY and l.staticBackup or l.staticPrimary
  for slotNum = 3, 8 do
    local aButton = activeSet[slotNum]
    aButton.slot:SetScale(1)
    l.applyActiveStyle(aButton)
    local iButton = inactiveSet[slotNum]
    iButton.slot:SetScale(s)
    l.applyInactiveStyle(iButton)
  end
end

---创建静态双克隆行(幂等，失败闭锁)
---@type fun(): boolean
l.createStaticRows = function()
  if l.staticPrimary[3] then
    return true
  end
  if l.staticRowsFailed or not l.container then
    return false
  end
  local ok, err = pcall(function()
    for slotNum = 3, 8 do
      local template = slotNum == 8 and "ZO_UltimateActionButton" or "ZO_ActionButton"
      local pButton = ActionButton:New(
        slotNum + 60,
        ACTION_BUTTON_TYPE_VISIBLE,
        l.container,
        template,
        HOTBAR_CATEGORY_PRIMARY
      )
      local bButton = ActionButton:New(
        slotNum + 80,
        ACTION_BUTTON_TYPE_VISIBLE,
        l.container,
        template,
        HOTBAR_CATEGORY_BACKUP
      )
      for _, button in ipairs({ pButton, bButton }) do
        button.slot.slotNum = slotNum
        button.button.slotNum = slotNum
        button:SetShowBindingText(false)
        button:SetupBounceAnimation()
        l.setupDragDropHandlers(button, function()
          return button.slot.hotbarCategory
        end)
        if slotNum == 8 then
          l.hideUltimateDecorations(button)
        end
      end
      l.staticPrimary[slotNum] = pButton
      l.staticBackup[slotNum] = bButton
    end
  end)
  if not ok then
    l.staticRowsFailed = true
    l.staticPrimary = {}
    l.staticBackup = {}
    d(string.format("[ADR] static rows creation failed: %s (dynamic fallback)", tostring(err)))
    return false
  end
  return true
end

---按预设分发布局；切回动态/关闭时还原原生锚；同步第二行缩放(所有预设生效)
---@type fun()
l.layoutRow = function()
  if not l.buttons[3] or not l.container then
    return
  end
  if l.getSavedVars().barPreset == "static" and l.effectivePreset() == "static" then
    l.layoutStatic()
  else
    l.exitStatic()
    l.layoutDynamic()
  end
end

---非激活行图标暗化(同FAB)：只改 icon 纹理，不影响标签/冷却线；
---必须在原生 UpdateUsable 重刷颜色之后调用
---@type fun(button: table)
l.applyInactiveStyle = function(button)
  local sv = l.getSavedVars()
  if button.icon then
    button.icon:SetAlpha((sv.backBarDimAlpha or 50) / 100)
    button.icon:SetDesaturation((sv.backBarDesaturation or 50) / 100)
  end
end

---同步单个克隆槽位(原生刷新链：图标/actionId/状态/不可用发暗)
---@type fun(slotNum: number, hotbar: number)
l.syncSlot = function(slotNum, hotbar)
  l.syncButton(l.buttons[slotNum], hotbar)
end

---同步克隆按钮(静态双克隆/动态单克隆共用)
---@type fun(button: table|nil, hotbar: number)
l.syncButton = function(button, hotbar)
  if not button then
    return
  end
  button.slot.hotbarCategory = hotbar
  button.button.hotbarCategory = hotbar
  button:HandleSlotChanged(hotbar)
  if l.staticEngaged then
    l.applyStaticRoles()
  else
    l.applyInactiveStyle(button)
  end
  -- HandleSlotChanged→SetEnabled(true) 会重新显示槽位，经典模式下重应用可见性
  if not l.staticEngaged and l.classicMode then
    button.slot:SetHidden(not (l.classicVisibleMap and l.classicVisibleMap[button.slot.slotNum] == true))
  end
end

---同步整行(换武器/全量刷新)。relayout=false 时仅刷数据不重排锚点
---(换装等高频事件避免锚点风暴: too many anchors processed)
---@type fun(relayout?: boolean)
l.syncAll = function(relayout)
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
  if relayout ~= false then
    l.layoutRow()
  end
  for slotNum = 3, 8 do
    l.syncSlot(slotNum, hotbar)
  end
end

---克隆按钮拖放处理器：原生 ZO_AbilitySlot_* 的放置路径不带 hotbarCategory，
---会把拖入的技能放到当前激活条；拾取路径虽带参数但一并用安全调用重写保持一致。
---右键仍走原生 OnSlotClicked(清除菜单已正确读取克隆行的 hotbarCategory)
---翻转半程回调：缩到底时换入新武器条内容(同原生 OnSwapAnimationHalfDone)
---@type fun(_, button: table)
local function onSwapAnimationHalfDone(_, button)
  local hotbar = l.inactiveHotbar()
  if not hotbar then
    return
  end
  l.currentHotbar = hotbar
  button.slot.hotbarCategory = hotbar
  button.button.hotbarCategory = hotbar
  button:HandleSlotChanged(hotbar)
  l.applyInactiveStyle(button)
  -- 经典模式下重应用可见性(HandleSlotChanged 会重新显示槽位)
  if l.classicMode then
    button.slot:SetHidden(not (l.classicVisibleMap and l.classicVisibleMap[button.slot.slotNum] == true))
  end
end

---翻转结束回调
---@type fun(_, button: table)
local function onSwapAnimationDone(_, button)
  button.noUpdates = false
end

---@type fun(button: table)
l.setupDragDropHandlers = function(button, getCategory)
  local buttonControl = button.button
  if not buttonControl then
    return
  end
  if not getCategory then
    getCategory = l.inactiveHotbar
  end

  buttonControl:SetHandler("OnReceiveDrag", function()
    if GetCursorContentType() == MOUSE_CONTENT_EMPTY then
      return
    end
    local hotbar = getCategory()
    if hotbar then
      CallSecureProtected("PlaceInActionBar", button.slot.slotNum, hotbar)
    end
  end)

  buttonControl:SetHandler("OnDragStart", function()
    if GetCursorContentType() ~= MOUSE_CONTENT_EMPTY or ZO_ActionBar_AreActionBarsLocked() then
      return false
    end
    local hotbar = getCategory()
    if not hotbar or not IsSlotUsed(button.slot.slotNum, hotbar) then
      return false
    end
    CallSecureProtected("PickupAction", button.slot.slotNum, hotbar)
    return true
  end)

  buttonControl:SetHandler("OnClicked", function(_, mouseButton)
    if mouseButton == MOUSE_BUTTON_INDEX_LEFT and GetCursorContentType() ~= MOUSE_CONTENT_EMPTY then
      local hotbar = getCategory()
      if hotbar then
        CallSecureProtected("PlaceInActionBar", button.slot.slotNum, hotbar)
      end
    else
      -- 右键菜单等交还原生路径
      ZO_AbilitySlot_OnSlotClicked(buttonControl, mouseButton)
    end
  end)
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
    -- ApplyStyle→ResetBounceAnimation 依赖 self.bounceAnimation，不初始化会 nil 崩溃(FAB 克隆时同样显式调用)
    button:SetupBounceAnimation()
    -- 换武器翻转动画(半程换内容的回调在上方定义)
    button:SetupSwapAnimation(onSwapAnimationHalfDone, onSwapAnimationDone)
    l.setupDragDropHandlers(button)
    if slotNum == 8 then
      l.hideUltimateDecorations(button)
    end
    l.buttons[slotNum] = button
  end
  -- 注入平台模板(键盘 50x50/手柄 64x64、FlipCard 尺寸等)：
  -- ZO_ActionButton 虚拟模板本身不带尺寸，缺失会导致 FlipCard 0x0、图标不可见
  l.applyPlatformStyle()
end

---重应用平台模板(键盘/手柄切换)
---@type fun()
l.applyPlatformStyle = function()
  if not l.container then
    return
  end
  local function styleSet(set)
    for slotNum = 3, 8 do
      local button = set[slotNum]
      if button then
        local base = slotNum == 8 and "ZO_UltimateActionButton" or "ZO_ActionButton"
        button:ApplyStyle(ZO_GetPlatformTemplate(base))
        if slotNum == 8 then
          l.hideUltimateDecorations(button)
        end
      end
    end
  end
  styleSet(l.buttons)
  styleSet(l.staticPrimary)
  styleSet(l.staticBackup)
  l.layoutRow()
  l.syncAll()
end

---换武器时克隆行动画。
---动态/经典：翻转(FlipCard缩→换→展，同原生)。
---静态：两行瞬间定格到新状态(静态=无位置动画)，仅切手按钮平滑滑移到新位；
---双排轻微 alpha 下潜(最低 0.3)，内容在半程谷底换入。代际号防连打叠帧。
---@type fun()
l.playSwapAnimation = function()
  if not l.container or not l.buttons[3] then
    return
  end
  local hotbar = l.inactiveHotbar()
  if not hotbar then
    l.syncAll()
    return
  end
  if l.getSavedVars().barPreset ~= "static" then
    for slotNum = 3, 8 do
      local button = l.buttons[slotNum]
      if button and button.hotbarSwapAnimation then
        button.hotbarSwapAnimation:PlayFromStart()
      end
    end
    return
  end
  -- 静态：事件路由已直接 applyStaticRoles，此处不会进入；保险起见同样瞬时处理
  l.applyStaticRoles()
end

---@type fun()
l.registerEvents = function()
  local EM = GetEventManager()
  EM:RegisterForEvent(EVENT_NAME, EVENT_HOTBAR_SLOT_UPDATED, function(_, slotNum, hotbarCategory)
    if l.staticEngaged then
      -- 静态：按恒定分类路由到对应克隆行
      if hotbarCategory == HOTBAR_CATEGORY_PRIMARY then
        l.syncButton(l.staticPrimary[slotNum], hotbarCategory)
      elseif hotbarCategory == HOTBAR_CATEGORY_BACKUP then
        l.syncButton(l.staticBackup[slotNum], hotbarCategory)
      end
    elseif l.buttons[slotNum] and hotbarCategory == l.currentHotbar then
      l.syncSlot(slotNum, hotbarCategory)
    end
  end)
  EM:RegisterForEvent(EVENT_NAME, EVENT_HOTBAR_SLOT_STATE_UPDATED, function(_, slotNum, hotbarCategory)
    if l.staticEngaged then
      local button = hotbarCategory == HOTBAR_CATEGORY_PRIMARY and l.staticPrimary[slotNum]
        or l.staticBackup[slotNum]
      if button then
        button:UpdateState()
        l.applyStaticRoles()
      end
    else
      local button = l.buttons[slotNum]
      if button and hotbarCategory == l.currentHotbar then
        button:UpdateState()
        l.applyInactiveStyle(button)
      end
    end
  end)
  EM:RegisterForEvent(EVENT_NAME, EVENT_ACTION_SLOTS_ACTIVE_HOTBAR_UPDATED, function(_, didActiveHotbarChange)
    if l.staticEngaged then
      -- 静态：位置/内容均不变，仅激活角色(明暗/尺寸)互换
      l.applyStaticRoles()
      return
    end
    if didActiveHotbarChange then
      -- 换武器：播放翻转动画，内容在半程换入(动画回调内完成)，不同步闪变
      l.playSwapAnimation()
    else
      l.syncAll()
    end
  end)
  EM:RegisterForEvent(EVENT_NAME, EVENT_ACTION_SLOTS_ALL_HOTBARS_UPDATED, function()
    l.syncAll()
  end)
  EM:RegisterForEvent(EVENT_NAME, EVENT_PLAYER_ACTIVATED, function()
    l.syncAll()
  end)
  EM:RegisterForEvent(EVENT_NAME, EVENT_INVENTORY_SINGLE_SLOT_UPDATE, function()
    -- 换装高频事件：仅刷数据(可用状态/计数)，不重排锚点
    l.syncAll(false)
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

---系统 back row(原生迷你副条)与克隆行会重复显示，激活时关闭该系统设置(不恢复，同FAB做法)
---@type fun()
l.suppressSystemBackRow = function()
  if GetSetting_Bool(SETTING_TYPE_UI, UI_SETTING_SHOW_ACTION_BAR_BACK_ROW) then
    SetSetting(SETTING_TYPE_UI, UI_SETTING_SHOW_ACTION_BAR_BACK_ROW, "false")
  end
end

---激活克隆行(双bar预设)。创建失败时清理残缺状态并闭锁本次会话不再重试，
---由 Bar.lua 的贴图满行回退兜底
---@type fun()
l.activate = function()
  if l.createFailed then
    return
  end
  local ok, err = pcall(l.createRow)
  if not ok then
    d(string.format("[ADR] BackBar clone row creation failed: %s (texture fallback active)", tostring(err)))
    addon.debug("[BB]create row failed: %s", tostring(err))
    l.createFailed = true
    l.buttons = {}
    if l.container then
      pcall(function()
        l.container:SetHidden(true)
      end)
      l.container = nil
    end
    return
  end
  l.active = true
  l.lastAppliedPreset = l.effectivePreset()
  if l.lastAppliedPreset ~= "classic" then
    l.suppressSystemBackRow()
  end
  l.registerEvents()
end

---停用克隆行(切回经典预设/关闭计时条)
---@type fun()
l.deactivate = function()
  l.unregisterEvents()
  l.active = false
  l.lastAppliedPreset = nil
  l.exitStatic()
  if l.container then
    l.container:SetHidden(true)
  end
end

---@type fun()
l.onCoreUpdate = function()
  local sv = l.getSavedVars()
  -- FAB 存在时任何预设都不激活克隆行(回退贴图经典)；否则所有预设激活，
  -- classic 仅作为可见性模式(每槽有计时才显示，由 Bar 模块每帧传入可见集)
  local want = sv.barEnabled and _G.FancyActionBar == nil
  if want and not l.active then
    l.activate()
  elseif not want and l.active then
    l.deactivate()
  end
  if l.active and l.container then
    l.classicMode = l.effectivePreset() == "classic"
    -- 预设切换(动态↔静态)时重新布局：activate/deactivate 分支覆盖不到已激活状态下的切换
    local effective = l.effectivePreset()
    if effective ~= l.lastAppliedPreset then
      l.lastAppliedPreset = effective
      l.syncAll()
    end
    -- Oakensoul 或非武器热栏(攻城等)时隐藏克隆行并交还原生条；恢复时全量重同步
    if l.hasOakensoul() or l.inactiveHotbar() == nil then
      l.exitStatic()
      l.container:SetHidden(true)
      l.currentHotbar = nil
    elseif l.container:IsControlHidden() then
      l.syncAll()
    elseif l.staticEngaged then
      -- 原生代码可能在事件中重新显示原生槽，逐帧确保隐藏(幂等)
      for slotNum = 3, 8 do
        ZO_ActionBar_GetButton(slotNum).slot:SetHidden(true)
      end
    end
  end
end

--========================================
--        m
--========================================
---@type fun(): boolean
m.isActive = function()
  return l.active and l.buttons[3] ~= nil
end

---@type fun(): string
m.getEffectivePreset = function()
  return l.effectivePreset()
end

---菜单滑条直接调用：立即应用第二行缩放(锚点均与scale无关，仅更新叶子scale)；
---静态预设的锚点 offset 依赖 scale，需重排
---@type fun()
m.updateScale = function()
  l.applyScale()
  if l.active and l.container and l.effectivePreset() == "static" then
    l.layoutStatic()
  end
end

---菜单下拉框直接调用：预设切换后立即重布局
---@type fun()
m.updateLayout = function()
  if l.active and l.container then
    l.classicMode = l.effectivePreset() == "classic"
    l.lastAppliedPreset = l.effectivePreset()
    l.syncAll()
  end
end

---克隆行当前是否可用于承载标签(存在、已同步到非激活条、非 Oakensoul)
---@type fun(): boolean
m.isRowUsable = function()
  return l.active and l.container ~= nil and l.currentHotbar ~= nil and not l.hasOakensoul()
end

---是否处于经典可见性模式
---@type fun(): boolean
m.isClassicMode = function()
  return l.classicMode
end

---当前克隆行对应的非激活条
---@type fun(): number|nil
m.getHotbar = function()
  return l.currentHotbar
end

---设置各克隆槽可见性(仅经典模式生效；非经典或传 nil 时全部显示)
---@type fun(visibleMap: table<number, boolean>|nil)
m.setSlotsVisible = function(visibleMap)
  if not l.container then
    return
  end
  l.classicVisibleMap = visibleMap
  for slotNum = 3, 8 do
    local button = l.buttons[slotNum]
    if button then
      local visible = not l.classicMode or (visibleMap ~= nil and visibleMap[slotNum] == true)
      button.slot:SetHidden(not visible)
    end
  end
end

---@type fun(slotNum: number): Control|nil
m.getSlotControl = function(slotNum)
  -- 静态：非激活行(标签/冷却线载体)是静态非激活集；动态/经典：动态单克隆集
  if l.staticEngaged then
    local active = GetActiveHotbarCategory()
    local inactiveSet = active == HOTBAR_CATEGORY_PRIMARY and l.staticBackup or l.staticPrimary
    local button = inactiveSet[slotNum]
    return button and button.slot or nil
  end
  local button = l.buttons[slotNum]
  return button and button.slot or nil
end

---主条(激活条)槽控件：静态下为静态激活集(原生槽已隐藏)；否则为原生槽。
---供 Bar 模块把主条计时标签重定向到激活克隆行
---@type fun(slotNum: number): Control|nil
m.getActiveSlotControl = function(slotNum)
  if l.staticEngaged then
    local active = GetActiveHotbarCategory()
    local activeSet = active == HOTBAR_CATEGORY_PRIMARY and l.staticPrimary or l.staticBackup
    local button = activeSet[slotNum]
    return button and button.slot or nil
  end
  local nb = ZO_ActionBar_GetButton(slotNum)
  return nb and nb.slot or nil
end

---静态双克隆行是否接管(原生槽隐藏中)
---@type fun(): boolean
m.isStaticNativeHidden = function()
  return l.staticEngaged
end

---菜单滑条直接调用：立即重新应用暗化(静态=角色化，激活行全亮)
---@type fun()
m.updateStyle = function()
  if l.staticEngaged then
    l.applyStaticRoles()
    return
  end
  for slotNum = 3, 8 do
    local button = l.buttons[slotNum]
    if button then
      l.applyInactiveStyle(button)
    end
  end
end

--========================================
--        register
--========================================
addon.register("BackBar#M", m)

addon.register("BackBar", m)

addon.extend(core.EXTKEY_UPDATE, l.onCoreUpdate)

addon.extend(settings.EXTKEY_ADD_DEFAULTS, function()
  settings.addDefaults(backBarSavedVarsDefaults)
end)

-- 菜单项由 Bar 模块以二级子菜单(Double Bar)形式挂在 Bar 组内，紧随预设下拉框

--诊断命令：/adrbackbar 输出第二行引擎的实时状态并强制重布局
SLASH_COMMANDS["/adrbackbar"] = function()
  local sv = l.getSavedVars()
  local buttonCount = 0
  for _ in pairs(l.buttons) do
    buttonCount = buttonCount + 1
  end
  local weaponSwap = ZO_ActionBar1 and ZO_ActionBar1:GetNamedChild("WeaponSwap") or nil
  d(string.format(
    "[ADR] v%s preset=%s effective=%s active=%s container=%s buttons=%d lastApplied=%s hotbar=%s lifted=%s weaponSwap=%s nativeOnTop=%s",
    tostring(addon.version),
    tostring(sv.barPreset),
    tostring(l.effectivePreset()),
    tostring(l.active),
    tostring(l.container ~= nil),
    buttonCount,
    tostring(l.lastAppliedPreset),
    tostring(l.currentHotbar),
    tostring(l.staticEngaged),
    tostring(weaponSwap ~= nil),
    tostring(GetActiveHotbarCategory() == HOTBAR_CATEGORY_PRIMARY)
  ))
  if l.active and l.container then
    l.syncAll()
    d("[ADR] relayout forced: " .. tostring(l.effectivePreset()))
  else
    d("[ADR] BackBar inactive (need barEnabled=true and non-classic preset)")
  end
end

if ZO_PlatformStyle then
  ZO_PlatformStyle:New(function()
    if l.active then
      l.applyPlatformStyle()
    end
  end)
end

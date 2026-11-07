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

---@type table<number, table> slotNum(3..8) -> ActionButton克隆
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

---应用克隆槽缩放(叶子控件自身缩放，同FAB的 backUlt.slot:SetScale 模式；
---中间容器永不缩放——scaled容器锚点语义不可靠，是右贴偏移的根源)
---@type fun()
l.applyScale = function()
  local s = l.getSavedVars().barShowShiftScalePercent / 100
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

---静态预设：切手按钮垂直移动会带动锚在其左侧的药剂快捷栏(含Q键提示)。
---仅无激活伴侣时快捷栏才锚在切手上(原生常量 offset -5)；此情形下垂直补偿回原位。
---有伴侣时快捷栏锚伴侣大招槽，不受切手移动影响，无需补偿
---@type fun(nativeOnTop: boolean, liftY: number)
l.compensateQuickslot = function(nativeOnTop, liftY)
  local weaponSwap = ZO_ActionBar1 and ZO_ActionBar1:GetNamedChild("WeaponSwap")
  if not weaponSwap then
    return
  end
  l.quickslotCompensated = false
  if DoesUnitExist("companion") and HasActiveCompanion() then
    return
  end
  local qs = ZO_ActionBar_GetButton(1, HOTBAR_CATEGORY_QUICKSLOT_WHEEL)
  if qs and qs.slot then
    qs.slot:ClearAnchors()
    qs.slot:SetAnchor(RIGHT, weaponSwap, LEFT, -5, nativeOnTop and liftY or 0)
    l.quickslotCompensated = true
  end
end

---恢复原生3号槽与切手按钮默认锚(静态预设动过才需要)，并还原快捷栏补偿
---@type fun()
l.restoreNativeAnchor = function()
  if not l.nativeLifted then
    return
  end
  l.nativeLifted = false
  local nativeButton3 = ZO_ActionBar_GetButton(3)
  local abilityGap, _, _, swapX, swapY = l.platformOffsets()
  local weaponSwap = ZO_ActionBar1 and ZO_ActionBar1:GetNamedChild("WeaponSwap")
  nativeButton3.slot:ClearAnchors()
  if weaponSwap then
    nativeButton3:ApplyAnchor(weaponSwap, abilityGap)
    weaponSwap:ClearAnchors()
    weaponSwap:SetAnchor(TOPLEFT, ZO_ActionBar1, TOPLEFT, swapX, swapY)
  end
  if l.quickslotCompensated then
    l.quickslotCompensated = false
    local qs = ZO_ActionBar_GetButton(1, HOTBAR_CATEGORY_QUICKSLOT_WHEEL)
    if qs and qs.slot and weaponSwap then
      qs.slot:ClearAnchors()
      qs.slot:SetAnchor(RIGHT, weaponSwap, LEFT, -5, 0)
    end
  end
  l.unpinKeybinds()
  l.restoreNativeFlip()
end

---按键提示(ButtonText)固定/还原：静态抬升原生条时，1-5/T 键提示钉在原始屏幕位置，
---不随原生条上下移动；还原时恢复原生锚形(TOP→slot.BOTTOM, offsetY 键盘1/手柄-6)
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
---PlayFromStart hotbarSwapAnimation，替换后原生条同步获得交叉淡化而非翻转；
---还原时放回原时间线
l.staticSwapSaved = {}

---@type fun()
l.suppressNativeFlip = function()
  for slotNum = 3, 8 do
    local nb = ZO_ActionBar_GetButton(slotNum)
    if nb and nb.hotbarSwapAnimation and not l.staticSwapSaved[slotNum] then
      l.staticSwapSaved[slotNum] = nb.hotbarSwapAnimation
      if not nb.adrSwapFade then
        -- 空时间线：原生代码换武器时仍会 PlayFromStart，但无任何动画动作，
        -- 表现完全由静态编排(切手缓动+双排alpha下潜)接管
        nb.adrSwapFade = ANIMATION_MANAGER:CreateTimeline()
      end
      nb.hotbarSwapAnimation = nb.adrSwapFade
    end
  end
end

---@type fun()
l.restoreNativeFlip = function()
  for slotNum = 3, 8 do
    local nb = ZO_ActionBar_GetButton(slotNum)
    if nb and l.staticSwapSaved[slotNum] then
      nb.hotbarSwapAnimation = l.staticSwapSaved[slotNum]
      l.staticSwapSaved[slotNum] = nil
    end
  end
end

---静态克隆槽 X 偏移(切手基准，本地单位)：技能 3-7 链式，大招在技能段+原生大招间距处
---@type fun(slotNum: number, dims: table, abilityGap: number, ultGap: number): number
l.staticOffsetX = function(slotNum, dims, abilityGap, ultGap)
  if slotNum == 8 then
    return abilityGap + 4 * (dims.ability + abilityGap) + dims.ability + ultGap + dims.ult / 2
  end
  return abilityGap + (slotNum - 3) * (dims.ability + abilityGap) + dims.ability / 2
end

---静态预设：主手条固定在上，副手条固定在下。
---原生条渲染当前激活条：主手激活时原生条抬到上行，克隆行(副手)占原生条原位；
---副手激活时原生条留在原位，克隆行(主手)在上。均以武器切换按钮为锚基准(同FAB)。
---克隆槽用未缩放本地间距的锚点 offset(引擎×scale后即均匀缩放组)，槽各自 SetScale
---@type fun()
l.layoutStatic = function()
  if not l.container or not l.buttons[3] then
    return
  end
  local abilityGap, ultGap, gapY = l.platformOffsets()
  local weaponSwap = ZO_ActionBar1 and ZO_ActionBar1:GetNamedChild("WeaponSwap")
  if not weaponSwap then
    d("[ADR] layoutStatic: WeaponSwap not found, falling back to dynamic layout")
    l.layoutDynamic()
    return
  end
  local nativeButton3 = ZO_ActionBar_GetButton(3)
  local liftY = nativeButton3.slot:GetHeight() + gapY
  local active = GetActiveHotbarCategory()
  local nativeOnTop = active == HOTBAR_CATEGORY_PRIMARY
  -- 首次应用时确认提示(便于验证静态布局确实生效)
  if not l.staticAppliedNotified then
    l.staticAppliedNotified = true
    d(string.format("[ADR] %s", addon.text("ADR static double bar applied")))
  end
  local dims = IsInGamepadPreferredMode() and PLATFORM_DIMS.gamepad or PLATFORM_DIMS.keyboard
  local scale = l.getSavedVars().barShowShiftScalePercent / 100
  -- 切手按钮随原生行上下移动(始终在原生条左侧)，原生条跟随切手(与默认锚同形)。
  -- 移动后 weaponSwap RIGHT 点即当前原生行的中心线。
  local _, _, _, swapX, swapY = l.platformOffsets()
  weaponSwap:ClearAnchors()
  weaponSwap:SetAnchor(TOPLEFT, ZO_ActionBar1, TOPLEFT, swapX, swapY + (nativeOnTop and -liftY or 0))
  nativeButton3.slot:ClearAnchors()
  nativeButton3.slot:SetAnchor(LEFT, weaponSwap, RIGHT, abilityGap, 0)
  l.nativeLifted = nativeOnTop
  l.compensateQuickslot(nativeOnTop, liftY)
  l.suppressNativeFlip()
  -- 克隆行常量行距锚定：克隆行边缘锚到切手基准 + 行距，
  -- 渲染后的行间隙 = gapY 恒定(不随缩放变化)。
  --   克隆在下(原生抬升)：TOP 锚，offsetY_local = +(liftY - H/2)/scale
  --     (渲染后克隆顶 = 原生底 + gapY；liftY - H/2 = H/2 + gapY)
  --   克隆在上(原生在原位)：BOTTOM 锚，offsetY_local = -(H/2 + gapY)/scale = -(liftY - H/2)/scale
  local rowOffLocal = (liftY - dims.ability / 2) / scale
  local cloneAnchorType = nativeOnTop and TOP or BOTTOM
  local cloneOffY = nativeOnTop and rowOffLocal or -rowOffLocal
  for slotNum = 3, 8 do
    local button = l.buttons[slotNum]
    local offsetX = l.staticOffsetX(slotNum, dims, abilityGap, ultGap)
    button.slot:ClearAnchors()
    button.slot:SetAnchor(cloneAnchorType, weaponSwap, RIGHT, offsetX, cloneOffY)
  end
  l.applyScale()
  -- 主手激活(原生条抬升)时钉住键位提示；副手时原生条已在原位，解除钉住
  if nativeOnTop then
    l.pinKeybinds()
  else
    l.unpinKeybinds()
  end
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
    l.restoreNativeAnchor()
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
  local button = l.buttons[slotNum]
  if not button then
    return
  end
  button.slot.hotbarCategory = hotbar
  button.button.hotbarCategory = hotbar
  button:HandleSlotChanged(hotbar)
  l.applyInactiveStyle(button)
  -- HandleSlotChanged→SetEnabled(true) 会重新显示槽位，经典模式下重应用可见性
  if l.classicMode then
    button.slot:SetHidden(not (l.classicVisibleMap and l.classicVisibleMap[slotNum] == true))
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
l.setupDragDropHandlers = function(button)
  local buttonControl = button.button
  if not buttonControl then
    return
  end

  buttonControl:SetHandler("OnReceiveDrag", function()
    if GetCursorContentType() == MOUSE_CONTENT_EMPTY then
      return
    end
    local hotbar = l.inactiveHotbar()
    if hotbar then
      CallSecureProtected("PlaceInActionBar", button.slot.slotNum, hotbar)
    end
  end)

  buttonControl:SetHandler("OnDragStart", function()
    if GetCursorContentType() ~= MOUSE_CONTENT_EMPTY or ZO_ActionBar_AreActionBarsLocked() then
      return false
    end
    local hotbar = l.inactiveHotbar()
    if not hotbar or not IsSlotUsed(button.slot.slotNum, hotbar) then
      return false
    end
    CallSecureProtected("PickupAction", button.slot.slotNum, hotbar)
    return true
  end)

  buttonControl:SetHandler("OnClicked", function(_, mouseButton)
    if mouseButton == MOUSE_BUTTON_INDEX_LEFT and GetCursorContentType() ~= MOUSE_CONTENT_EMPTY then
      local hotbar = l.inactiveHotbar()
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
  -- 静态：静态=无位置动画。两行瞬间定格到新状态(同帧)；只有切手按钮从旧位平滑滑移到新位；
  -- 双排轻微 alpha 下潜(最低 0.3，绝不全隐)，内容在下潜谷底(半程)换入。代际号防连打叠帧
  local nativeButton3 = ZO_ActionBar_GetButton(3)
  local abilityGap, ultGap, gapY, swapX, swapY = l.platformOffsets()
  local slotH = nativeButton3.slot:GetHeight()
  local liftY = slotH + gapY
  local nativeOnTop = GetActiveHotbarCategory() == HOTBAR_CATEGORY_PRIMARY
  -- 1. 两行瞬间定格到新状态：克隆行/快捷栏/键位提示/原生条全部就位
  l.layoutStatic()
  local weaponSwap = ZO_ActionBar1 and ZO_ActionBar1:GetNamedChild("WeaponSwap")
  if not weaponSwap then
    return
  end
  -- 2. 切手按钮从旧位平滑滑移到新位(旧位抬升状态与新状态相反)
  l.staticSwapGen = (l.staticSwapGen or 0) + 1
  local gen = l.staticSwapGen
  local startSwapY = nativeOnTop and swapY or (swapY - liftY)
  local endSwapY = nativeOnTop and (swapY - liftY) or swapY
  weaponSwap:SetAnchor(TOPLEFT, ZO_ActionBar1, TOPLEFT, swapX, startSwapY)
  local steps = 14
  local i = 0
  local applyAllAlpha = function(a)
    for slotNum = 3, 8 do
      local button = l.buttons[slotNum]
      if button then
        button.slot:SetAlpha(a)
      end
      local nb = ZO_ActionBar_GetButton(slotNum)
      if nb then
        nb.slot:SetAlpha(a)
      end
    end
  end
  local swapContent = function()
    local hb = l.inactiveHotbar()
    if not hb then
      return
    end
    l.currentHotbar = hb
    for slotNum = 3, 8 do
      local button = l.buttons[slotNum]
      if button then
        button.slot.hotbarCategory = hb
        button.button.hotbarCategory = hb
        button:HandleSlotChanged(hb)
        l.applyInactiveStyle(button)
      end
      -- 原生条内容同步换入(原生翻转时间线已被替换)，并补齐原生结束回调职责
      local nb = ZO_ActionBar_GetButton(slotNum)
      if nb then
        nb:SetShowCooldown(false)
        nb:HandleSlotChanged(GetActiveHotbarCategory())
        nb.noUpdates = false
      end
    end
  end
  local tick
  tick = function()
    if gen ~= l.staticSwapGen then
      return
    end
    i = i + 1
    local t = i / steps
    -- 仅切手按钮滑移
    local y = startSwapY + (endSwapY - startSwapY) * t
    weaponSwap:SetAnchor(TOPLEFT, ZO_ActionBar1, TOPLEFT, swapX, y)
    -- alpha 下潜：t=0.5 时 0.3
    local a = 1 - 0.7 * (t <= 0.5 and t or (1 - t))
    applyAllAlpha(a)
    if i == steps / 2 then
      swapContent()
    end
    if i < steps then
      zo_callLater(tick, 30)
    else
      applyAllAlpha(1)
    end
  end
  zo_callLater(tick, 30)
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
      l.applyInactiveStyle(button)
    end
  end)
  EM:RegisterForEvent(EVENT_NAME, EVENT_ACTION_SLOTS_ACTIVE_HOTBAR_UPDATED, function(_, didActiveHotbarChange)
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
  l.restoreNativeAnchor()
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
    -- Oakensoul 或非武器热栏(攻城等)时隐藏第二行；恢复时全量重同步
    if l.hasOakensoul() or l.inactiveHotbar() == nil then
      l.container:SetHidden(true)
      l.currentHotbar = nil
      l.restoreNativeAnchor()
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
  local button = l.buttons[slotNum]
  return button and button.slot or nil
end

---菜单滑条直接调用：立即重新应用非激活暗化
---@type fun()
m.updateStyle = function()
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
    tostring(l.nativeLifted),
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

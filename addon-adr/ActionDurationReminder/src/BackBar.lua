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
---@field isRowUsable? fun(): boolean
---@field isClassicMode? fun(): boolean
---@field getHotbar? fun(): number|nil
---@field setSlotsVisible? fun(visibleMap: table<number, boolean>|nil)
---@field getActiveSlotControl? fun(slotNum: number): Control|nil
---@field isStaticNativeHidden? fun(): boolean
---@field updateStyle? fun()

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
---@type boolean 经典模式：克隆行仅显示有计时的槽(可见性由 Bar 模块每帧驱动)
l.classicMode = false
---@type table<number, boolean>|nil 经典模式下各槽可见集(事件同步后重应用)
l.classicVisibleMap = nil

---冲突检测(会话级)：FAB 自带完整双bar，存在时硬回退①；
---BUI/Azurah 只会整体移动/换肤动作条，本模块锚点为相对锚可跟随，仅警告不降级；每次会话提示一次
---@type fun(): string?
l.effectivePreset = function()
  local preset = l.getSavedVars().barPreset
  if preset == "classic" then
    return "classic"
  end
  if FancyActionBar then
    l.notifyConflict("fancy")
    return "classic"
  end
  if preset == "static" and (BanditsUserInterface or BUI or Azurah) then
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

---隐藏克隆大招按钮上的原生装饰：永远藏的(充能条/填充动画)与随角色显隐的
---(光效/键提示)分开，后者由角色系统控制
---@type fun(button: table)
l.hideUltimateDecorations = function(button)
  local alwaysHide = {
    "UltimateBar",
    "LeadingEdge",
    "FillAnimationLeft",
    "FillAnimationRight",
    "Decoration",
    "Frame",
  }
  for i = 1, #alwaysHide do
    local child = button.slot:GetNamedChild(alwaysHide[i])
    if child then
      child:SetHidden(true)
    end
  end
  -- 非激活状态下也藏这些(激活时由角色系统重新显示)
  l.hideUltRoleDecorations(button)
end

---隐藏随角色显隐的装饰(非激活 ult / 非激活行时调用)
---@type fun(button: table)
l.hideUltRoleDecorations = function(button)
  local roleDecorations = { "ReadyBurst", "ReadyLoop", "LeftKeybind", "RightKeybind" }
  for i = 1, #roleDecorations do
    local child = button.slot:GetNamedChild(roleDecorations[i])
    if child then
      child:SetHidden(true)
    end
  end
end

---显示激活 ult 的装饰(手柄键提示)
---@type fun(button: table)
l.showUltRoleDecorations = function(button)
  -- 手柄 UI 且键位提示设置为手柄样式时才显示肩键图标(原生同源逻辑：
  -- actionbutton.lua 用 IsInGamepadPreferredMode() and ZO_Keybindings_ShouldShowGamepadKeybind())
  local showGamepad = IsInGamepadPreferredMode() and ZO_Keybindings_ShouldShowGamepadKeybind()
  local keybinds = { "LeftKeybind", "RightKeybind" }
  for i = 1, #keybinds do
    local child = button.slot:GetNamedChild(keybinds[i])
    if child then
      child:SetHidden(not showGamepad)
    end
  end
  -- ReadyBurst/ReadyLoop 由 updateUltGlow 管理
end

---刷新所有 ult 肩键可见性(设置变更时调用)：动态刷 D8，静态刷激活行+藏非激活行
---@type fun()
l.refreshUltKeybinds = function()
  if l.staticEngaged then
    local active = GetActiveHotbarCategory()
    local activeSet = active == HOTBAR_CATEGORY_PRIMARY and l.staticPrimary or l.staticBackup
    local inactiveSet = active == HOTBAR_CATEGORY_PRIMARY and l.staticBackup or l.staticPrimary
    if activeSet[8] then
      l.showUltRoleDecorations(activeSet[8])
    end
    if inactiveSet[8] then
      l.hideUltRoleDecorations(inactiveSet[8])
    end
  elseif l.buttons[8] then
    l.showUltRoleDecorations(l.buttons[8])
  end
end

---平台原生模板尺寸(与 actionbutton.xml 的 Keyboard/Gamepad 模板一致)；
---不用 GetWidth 测量：ESO 返回的是已含 scale 的屏幕值，缩放后会越量越小
local PLATFORM_DIMS = {
  keyboard = { ability = 50, ult = 50 },
  gamepad = { ability = 64, ult = 64 },
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
---在激活 ult 上显示终极能量数字(仅 slot 8：原生 RefreshUltimateNumberVisibility 不判断槽位，
---须由调用方把关)；数字重锚到按钮右侧，避免与底部计时数字重叠
---@type fun(button: table)
l.showUltNumber = function(button)
  if button.slot.slotNum ~= 8 then
    return
  end
  if button.countText then
    button.countText:ClearAnchors()
    -- 纵坐标保持模板默认(底边对齐)，仅横坐标移到按钮外
    button.countText:SetAnchor(BOTTOMLEFT, button.slot, BOTTOMRIGHT, 2, 0)
  end
  if button.RefreshUltimateNumberVisibility then
    button:RefreshUltimateNumberVisibility()
  end
end

l.applyActiveStyle = function(button)
  if button.icon then
    button.icon:SetAlpha(1)
    button.icon:SetDesaturation(0)
  end
  -- 终极能量数字只在激活 ult 上显示(原生语义；尊重游戏设置)
  l.showUltNumber(button)
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
---键位提示偏移调整(动态/经典)：手柄下原生-6内嵌进槽内会压住图标底部像素，
---改为边外+2(仍挂原生槽位，无需重父)；停用/退出时还原原生偏移。
---静态模式不走此路径(用 pinKeybinds 的绝对钉扎方案)
l.keybindOffsetsAdjusted = false

---@type fun()
l.adjustKeybindOffsets = function()
  if l.staticEngaged or not IsInGamepadPreferredMode() then
    return
  end
  if l.keybindOffsetsAdjusted then
    return
  end
  l.keybindOffsetsAdjusted = true
  for slotNum = 3, 8 do
    local nb = ZO_ActionBar_GetButton(slotNum)
    local text = nb and nb.slot and nb.slot:GetNamedChild("ButtonText")
    if text then
      text:ClearAnchors()
      text:SetAnchor(TOP, nb.slot, BOTTOM, 0, 2)
    end
  end
end

---@type fun()
l.restoreKeybindOffsets = function()
  if not l.keybindOffsetsAdjusted then
    return
  end
  l.keybindOffsetsAdjusted = false
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

l.layoutDynamic = function()
  if not l.container or not l.buttons[3] then
    return
  end
  local _, _, gapY, swapX, swapY = l.platformOffsets()
  local dims = IsInGamepadPreferredMode() and PLATFORM_DIMS.gamepad or PLATFORM_DIMS.keyboard
  -- 手柄下解除切手按钮的永久隐藏并锚回平台默认位(动态/经典下切手不随行移动，
  -- 药剂的原生锚链不受拖动；键盘下重新断言默认锚为无害操作)
  -- 键位提示偏移：手柄原生-6内嵌会压住图标底部像素，调为边外+2；停用时还原
  -- Q 标签同样需要断言(动态模式下未被 adjustKeybindOffsets 覆盖)
  local weaponSwap = ZO_ActionBar1 and ZO_ActionBar1:GetNamedChild("WeaponSwap")
  l.adjustKeybindOffsets()
  l.reassertUltKeybinds()
  if weaponSwap then
    if l.swapGlideTimeline then
      l.swapGlideTimeline:Stop()
    end
    if IsInGamepadPreferredMode() and ZO_WeaponSwap_SetPermanentlyHidden then
      ZO_WeaponSwap_SetPermanentlyHidden(weaponSwap, false)
    end
    weaponSwap:ClearAnchors()
    weaponSwap:SetAnchor(TOPLEFT, ZO_ActionBar1, TOPLEFT, swapX, swapY)
  end
  for slotNum = 3, 8 do
    local nativeButton = ZO_ActionBar_GetButton(slotNum)
    local button = l.buttons[slotNum]
    button.slot:ClearAnchors()
    button.slot:SetAnchor(BOTTOM, nativeButton.slot, TOP, 0, -gapY)
    -- 硬设尺寸(与静态双行同款)：ApplyStyle 模板注入在克隆上不可靠，
    -- 键盘下基模板50恰好撞对，手柄下原生变64而克隆仍50就会偏小
    l.setCloneSize(button, slotNum == 8 and dims.ult or dims.ability)
  end
  -- 手柄下同时缩原生 slot8(动态模式可见，与克隆行保持一致)
  l.resizeNativeUlt()
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
  -- 钉扎态偏移：手柄用边外+2(原生-6是内嵌进自家槽位底边的设计，静态下
  -- 该位置被副手 twin 行占据，内嵌即重叠)；键盘原生+1本就在边外
  local textOff = IsInGamepadPreferredMode() and 2 or 1
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
      -- 重父到 ZO_ActionBar1：静态下原生槽被隐藏，子控件需独立父级才能保持可见。
      -- 重父后 GetNamedChild 查不到(不再是子控件)，必须保存引用供还原使用
      l.pinnedKeybindTexts = l.pinnedKeybindTexts or {}
      l.pinnedKeybindTexts[slotNum] = { text = text, slot = nb.slot }
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
  -- 用 pin 时保存的引用还原(重父后 GetNamedChild 已查不到)
  local pinned = l.pinnedKeybindTexts or {}
  for slotNum = 3, 8 do
    local entry = pinned[slotNum]
    if entry and entry.text and entry.slot then
      entry.text:SetParent(entry.slot)
      entry.text:ClearAnchors()
      entry.text:SetAnchor(TOP, entry.slot, BOTTOM, 0, textOff)
      pinned[slotNum] = nil
    end
  end
end

---静态下用淡入淡出时间线替换原生按钮的翻转时间线：原生代码在换武器时无条件
---静态双行行间距：按平台最高槽位计算(手柄大招70高于技能64，若按技能高度
---两行大招列会零间隙贴上造成重叠；键盘 50=50 不受影响)
---@type fun(): number
l.rowSeparation = function()
  --- 行间距按技能高度；手柄大招统一缩到与技能同高(64)，所有列等宽等高，
  --- 无重叠且视觉统一(键盘 50=50 本就一致)
  local _, _, gapY = l.platformOffsets()
  local dims = IsInGamepadPreferredMode() and PLATFORM_DIMS.gamepad or PLATFORM_DIMS.keyboard
  return dims.ability + gapY
end

---静态接管期间用空时间线替换原生翻转时间线：原生换武器流程会播放
---hotbarSwapAnimation，其回调 HandleSlotChanged→SetEnabled(true) 会揭开被隐藏的
---原生槽(闪烁)；空时间线无动作无回调，原生条彻底不显形。退出时还原并复位
l.staticSwapSaved = {}

---@type fun()
l.suppressNativeFlip = function()
  for slotNum = 3, 8 do
    local nb = ZO_ActionBar_GetButton(slotNum)
    if nb and nb.hotbarSwapAnimation and not l.staticSwapSaved[slotNum] then
      l.staticSwapSaved[slotNum] = nb.hotbarSwapAnimation
      if not nb.adrEmptyTimeline then
        nb.adrEmptyTimeline = ANIMATION_MANAGER:CreateTimeline()
        -- 哑 SizeAnimation：原生 ApplySwapAnimationStyle 会对时间线的首/尾动画调
        -- SetStartAndEndWidth/Height，空时间线返回 nil 会崩(登录时槽位更新即触发)
        local dummy = nb.adrEmptyTimeline:InsertAnimation(ANIMATION_SIZE, nb.flipCard)
        dummy:SetDuration(0)
      end
      nb.hotbarSwapAnimation = nb.adrEmptyTimeline
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
      -- 原生翻转结束回调的职责补齐(空时间线期间未执行)：
      -- 复位 noUpdates 并重刷内容，避免原生条状态冻结
      nb.noUpdates = false
      nb:HandleSlotChanged(GetActiveHotbarCategory())
    end
  end
end

---静态预设：双克隆行。主手行(P)恒在上、副手行(B)恒在下，位置永不变化；
---仅隐藏原生6个技能按钮(切手/药剂/伴侣等全部不动)；键位数字钉在原位；
---激活行 100% 尺寸全亮(不吃比例/暗化)，非激活行用比例+暗化；换武器仅互换明暗/尺寸角色，
---内容永不重刷(两行各自恒绑定自己的武器集)
---显式硬设克隆槽尺寸(槽体+FlipCard)：不依赖 ApplyTemplateToControl 的模板注入，
---避免 FlipCard 0x0 导致图标不可见
---@type fun(button: table, w: number)
l.setCloneSize = function(button, w)
  button.slot:SetDimensions(w, w)
  local fcSize = w - 3
  local flipCard = button.slot:GetNamedChild("FlipCard")
  if flipCard then
    flipCard:SetDimensions(fcSize, fcSize)
  end
  -- Icon/TimerOverlay：显式重锚到 FlipCard 填充(TOPLEFT+BOTTOMRIGHT)。
  -- ult 模板的 Icon override 继承链在运行时不可靠(模板链 ability→ult 的
  -- override 不会清除中间模板注入的显式 Dimensions，导致图标不跟随 FlipCard)，
  -- 清锚后重设填充锚保证 Icon 恒等于 FlipCard 尺寸
  local fillChildren = { "Icon", "TimerOverlay", "CooldownIcon" }
  for i = 1, #fillChildren do
    local child = button.slot:GetNamedChild(fillChildren[i])
    if child and flipCard then
      child:ClearAnchors()
      child:SetAnchor(TOPLEFT, flipCard, TOPLEFT, 0, 0)
      child:SetAnchor(BOTTOMRIGHT, flipCard, BOTTOMRIGHT, 0, 0)
    end
  end
  -- Button(边框贴图)：模板默认 ult=70/ability=64，需跟随统一尺寸
  local buttonChild = button.slot:GetNamedChild("Button")
  if buttonChild then
    buttonChild:SetDimensions(w, w)
  end
  -- Backdrop(边框背景)：锚到 FlipCard±4(视觉69px)。
  -- 锚到 FlipCard 而非 slot 的好处：翻转动画(SIZE 动画在 FlipCard 上)时
  -- 边框自动跟随缩窄/展开，与原生条翻转视觉一致(锚 slot 则边框不翻转)
  local backdrop = button.slot:GetNamedChild("Backdrop")
  if backdrop and flipCard then
    backdrop:ClearAnchors()
    backdrop:SetAnchor(TOPLEFT, flipCard, TOPLEFT, -4, -4)
    backdrop:SetAnchor(BOTTOMRIGHT, flipCard, BOTTOMRIGHT, 4, 4)
  end
  -- Frame(ult 独有装饰框)：已隐藏但一并重锚保险
  local frame = button.slot:GetNamedChild("Frame")
  if frame and flipCard then
    frame:ClearAnchors()
    frame:SetAnchor(TOPLEFT, flipCard, TOPLEFT, -4, -4)
    frame:SetAnchor(BOTTOMRIGHT, flipCard, BOTTOMRIGHT, 4, 4)
  end
end

---静态行链式布局(同FAB/动态行已验证模式)：
---首槽以近零偏移锚到武器切换按钮(上排 TOPLEFT/下排 BOTTOMLEFT)，后续槽链式 LEFT→RIGHT，
---大招链式接在技能段后；避免对带 scale 控件使用大偏移 CENTER 锚(原点堆叠/右贴同族问题)
---@type fun(set: table, onTop: boolean, dims: table, abilityGap: number, ultGap: number)
---静态行绝对定位(已验证正确的 CENTER 锚)：以切手默认位为基准的绝对坐标，
---每槽 CENTER 锚到 ZO_ActionBar1，槽尺寸显式硬设(不依赖模板注入)
---@type fun(set: table, centerY: number, dims: table, abilityGap: number, ultGap: number, swapX: number, swapW: number)
l.layoutStaticRow = function(set, centerY, dims, abilityGap, ultGap, swapX, swapW)
  for slotNum = 3, 8 do
    local button = set[slotNum]
    local x = swapX + swapW + abilityGap
      + (slotNum == 8 and (4 * (dims.ability + abilityGap) + dims.ability + ultGap + dims.ult / 2)
        or ((slotNum - 3) * (dims.ability + abilityGap) + dims.ability / 2))
    button.slot:ClearAnchors()
    button.slot:SetAnchor(CENTER, ZO_ActionBar1, TOPLEFT, x, centerY)
    -- 大招尺寸由角色系统决定(激活=原生尺寸/非激活=缩小)，布局时先置原生基准
    l.setCloneSize(button, slotNum == 8 and dims.ult or dims.ability)
  end
end

l.layoutStatic = function()
  if not l.container or not l.buttons[3] then
    return
  end
  -- 静态接管键位提示(绝对钉扎)，先还原动态模式的偏移调整
  l.restoreKeybindOffsets()
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
  -- 键位数字钉在原位(重父到 ZO_ActionBar1 以独立于被隐藏的原生槽)
  l.pinKeybinds()
  -- 手柄 ult 肩键提示(Left/RightKeybind)：重锚到绝对坐标(底行 slot8 位置)，
  -- 两行的肩键提示都在同一位置，不随角色互换跳位。
  -- X 用与 layoutStaticRow 完全相同的公式；Y 用与 pinKeybinds 相同的基线
  if IsInGamepadPreferredMode() then
    local abilityGap, ultGap = l.platformOffsets()
    local _, _, _, swapX, swapY = l.platformOffsets()
    local swapW = weaponSwap and weaponSwap:GetWidth() or 56
    local swapH = weaponSwap and weaponSwap:GetHeight() or 70
    local dims = PLATFORM_DIMS.gamepad
    -- 与 layoutStaticRow 相同的 slot8 X 公式
    local ultX = swapX + swapW + abilityGap
      + 4 * (dims.ability + abilityGap) + dims.ability + ultGap + dims.ult / 2
    -- 与 pinKeybinds 相同的 Y 基线(槽底边 + textOff)
    local ultY = swapY + swapH / 2 + dims.ult / 2 + 2
    for _, set in ipairs({ l.staticPrimary, l.staticBackup }) do
      local ultButton = set[8]
      if ultButton then
        local lk = ultButton.slot:GetNamedChild("LeftKeybind")
        local rk = ultButton.slot:GetNamedChild("RightKeybind")
        if lk then
          lk:ClearAnchors()
          lk:SetAnchor(CENTER, ZO_ActionBar1, TOPLEFT, ultX - 22, ultY + 11)
        end
        if rk then
          rk:ClearAnchors()
          rk:SetAnchor(CENTER, ZO_ActionBar1, TOPLEFT, ultX + 22, ultY + 11)
        end
      end
    end
  end
  -- 切手按钮：解除原生永久隐藏(手柄下默认隐藏)并落位到当前激活行左侧(瞬时；
  -- 换武器时由 TranslateAnimation 滑动)。药剂快捷栏钉绝对坐标仅键盘模式
  -- (手柄下药剂原生位置不同，不接管)
  local weaponSwap = ZO_ActionBar1:GetNamedChild("WeaponSwap")
  l.quickslotPinned = false
  if weaponSwap then
    if ZO_WeaponSwap_SetPermanentlyHidden then
      ZO_WeaponSwap_SetPermanentlyHidden(weaponSwap, false)
    end
    local _, _, gapY2, swapX2, swapY2 = l.platformOffsets()
    local liftY2 = l.rowSeparation()
    local onTop2 = GetActiveHotbarCategory() == HOTBAR_CATEGORY_PRIMARY
    if l.swapGlideTimeline then
      l.swapGlideTimeline:Stop()
    end
    weaponSwap:ClearAnchors()
    weaponSwap:SetAnchor(TOPLEFT, ZO_ActionBar1, TOPLEFT, swapX2, swapY2 + (onTop2 and -liftY2 or 0))
    -- 药剂快捷栏钉绝对坐标：无伴侣时原生在两平台都把药剂锚在切手左侧
    -- (SetCompanionAnchors→ApplyAnchor(weaponSwap, 5))，不钉就会被切手拖动
    if not (DoesUnitExist("companion") and HasActiveCompanion()) then
      local qs = ZO_ActionBar_GetButton(1, HOTBAR_CATEGORY_QUICKSLOT_WHEEL)
      if qs and qs.slot then
        qs.slot:ClearAnchors()
        qs.slot:SetAnchor(RIGHT, ZO_ActionBar1, TOPLEFT, swapX2 - 5, swapY2 + weaponSwap:GetHeight() / 2)
        -- Q 键提示与其他键位提示同基线
        l.reassertQAnchor()
        l.quickslotPinned = true
      end
    end
  end
  -- 隐藏原生6个技能按钮(仅此6个；切手/药剂/伴侣大招不动)，
  -- 并替换其翻转时间线(防止换武器时动画回调揭开原生槽造成闪烁)
  for slotNum = 3, 8 do
    ZO_ActionBar_GetButton(slotNum).slot:SetHidden(true)
  end
  l.suppressNativeFlip()
  -- 隐藏动态单克隆行：锚到屏幕外(静态路径从不为其布局，无锚则会悬在容器原点；
  -- 即使被某条刷新链揭开也不可见)，退出静态时 layoutDynamic 会重新锚定
  for slotNum = 3, 8 do
    local dButton = l.buttons[slotNum]
    dButton.slot:ClearAnchors()
    dButton.slot:SetAnchor(TOPLEFT, ZO_ActionBar1, TOPLEFT, -2000, -2000)
    dButton.slot:SetHidden(true)
  end
  local swapW = weaponSwap:GetWidth()
  local swapH = weaponSwap:GetHeight()
  local bottomCenterY = swapY + swapH / 2
  local topCenterY = bottomCenterY - l.rowSeparation()
  l.layoutStaticRow(l.staticPrimary, topCenterY, dims, abilityGap, ultGap, swapX, swapW)
  l.layoutStaticRow(l.staticBackup, bottomCenterY, dims, abilityGap, ultGap, swapX, swapW)
  for slotNum = 3, 8 do
    l.staticPrimary[slotNum].slot:SetHidden(false)
    l.staticBackup[slotNum].slot:SetHidden(false)
  end
  l.staticEngaged = true
  l.setRolesInstant()
  -- 手柄下缩原生 slot8(即使隐藏也保持一致，切回动态时无缝)
  l.resizeNativeUlt()
end

---退出静态：恢复原生槽显示、还原键位数字、隐藏两静态行
---@type fun()
l.exitStatic = function()
  if not l.staticEngaged then
    return
  end
  l.staticEngaged = false
  l.restoreNativeFlip()
  if l.swapGlideTimeline then
    l.swapGlideTimeline:Stop()
  end
  -- 停止终极攒满光效时间线(LOOP_INDEFINITELY 循环不主动停会永远播放)
  -- 并隐藏其纹理；角色渐变时间线同理(插值对已隐藏控件无意义且浪费调度)
  for _, set in ipairs({ l.staticPrimary, l.staticBackup }) do
    for slotNum = 3, 8 do
      local button = set[slotNum]
      if button then
        local tls = l.ultGlowTimelines[button]
        if tls then
          tls.burst:Stop()
          tls.loop:Stop()
        end
        for _, texName in ipairs({ "ReadyBurst", "ReadyLoop" }) do
          local tex = button.slot and button.slot:GetNamedChild(texName)
          if tex then
            tex:SetHidden(true)
          end
        end
        if button.adrRoleTimeline then
          button.adrRoleTimeline:Stop()
        end
      end
    end
  end
  -- 注意：不停原生按钮的 ready 时间线——loop 状态由实时事件驱动永远正确，
  -- 停掉会杀死正确的持续光效且脱战无能量 tick 可恢复(纹理可见性已由
  -- resizeNativeUlt 的部分隐藏清单修复，原生机制全权控制光效)
  local weaponSwap = ZO_ActionBar1 and ZO_ActionBar1:GetNamedChild("WeaponSwap")
  if weaponSwap then
    local _, _, _, swapX, swapY = l.platformOffsets()
    weaponSwap:ClearAnchors()
    weaponSwap:SetAnchor(TOPLEFT, ZO_ActionBar1, TOPLEFT, swapX, swapY)
    -- 手柄下恢复原生行为(切手按钮永久隐藏)；键盘保持可见
    if IsInGamepadPreferredMode() and ZO_WeaponSwap_SetPermanentlyHidden then
      ZO_WeaponSwap_SetPermanentlyHidden(weaponSwap, true)
    end
    if l.quickslotPinned then
      l.quickslotPinned = false
      local qs = ZO_ActionBar_GetButton(1, HOTBAR_CATEGORY_QUICKSLOT_WHEEL)
      if qs and qs.slot then
        qs.slot:ClearAnchors()
        qs.slot:SetAnchor(RIGHT, weaponSwap, LEFT, -5, 0)
      end
    end
  end
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
---瞬时设置角色(仅首次布局/退出时使用；运行中事件走 applyStaticRoles 动画路径，
---避免瞬时写入打断进行中的渐变)。非激活大招缩小至与其他列同隙
---@type fun()
l.setRolesInstant = function()
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
    if slotNum == 8 then
      l.setCloneSize(aButton, (IsInGamepadPreferredMode() and PLATFORM_DIMS.gamepad or PLATFORM_DIMS.keyboard).ult)
    end
    local iButton = inactiveSet[slotNum]
    iButton.slot:SetScale(s)
    l.applyInactiveStyle(iButton)
    if slotNum == 8 then
      l.setCloneSize(iButton, (IsInGamepadPreferredMode() and PLATFORM_DIMS.gamepad or PLATFORM_DIMS.keyboard).ult)
    end
  end
end

---应用角色：动画路径(平滑重定目标，从当前实时值续接)；时间线不可用时退化瞬时
l.applyStaticRoles = function()
  if not l.staticEngaged then
    return
  end
  l.animateStaticRoles()
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
        -- 显式设置分类(与动态组一致)：不依赖 Initialize 参数传递
        local twinCategory = (pButton == button) and HOTBAR_CATEGORY_PRIMARY or HOTBAR_CATEGORY_BACKUP
        button.slot.hotbarCategory = twinCategory
        button.button.hotbarCategory = twinCategory
        button:SetShowBindingText(false)
        -- 创建即隐藏：锚定完成前不可见(否则短暂/永久停留在容器原点=左上角)
        button.slot:SetHidden(true)
        -- ApplyStyle→ResetBounceAnimation 依赖 self.bounceAnimation；
        -- 且 ZO_ActionButton 虚拟模板不带尺寸，不注入平台模板则 FlipCard 0x0 图标不可见
        button:SetupBounceAnimation()
        button:ApplyStyle(ZO_GetPlatformTemplate(template))
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
    -- 隐藏已创建的孤儿控件(仅清表引用会让它们永久停在容器原点)
    for _, set in ipairs({ l.staticPrimary, l.staticBackup }) do
      for _, button in pairs(set) do
        pcall(function()
          button.slot:SetHidden(true)
        end)
      end
    end
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
  -- 非激活克隆的终极能量数字隐藏(避免与激活条 ult 数字重复)
  if button.countText then
    button.countText:SetHidden(true)
  end
end

---同步单个克隆槽位(原生刷新链：图标/actionId/状态/不可用发暗)
---@type fun(slotNum: number, hotbar: number)
l.syncSlot = function(slotNum, hotbar)
  if l.swapInProgress then
    return
  end
  l.syncButton(l.buttons[slotNum], hotbar)
end

---同步克隆按钮(静态双克隆/动态单克隆共用)
---@type fun(button: table|nil, hotbar: number)
---毁灭杖图标记忆：毁灭杖技能图标跟当前武器走(游戏 bug)，切手后非激活条的
---图标会变成新武器形态。条激活时抓取图标存档；条非激活时若技能未变，
---用记忆纹理覆盖克隆行，保持切手前的正确形态。
---特征：纹理路径含 'ability_destructionstaff_'
l.destaffMemory = {} -- key: hotbar..":"..slotNum → { tex, abilityId }

---抓取当前激活条全部槽位的毁灭杖图标(激活条图标跟随当前武器，是正确的)
---@type fun()
l.captureActiveDestaff = function()
  local active = GetActiveHotbarCategory()
  for slotNum = 3, 8 do
    local tex = GetSlotTexture(slotNum, active)
    if tex and tex ~= "" and tex:find("ability_destructionstaff_", 1, true) then
      l.destaffMemory[active .. ":" .. slotNum] =
        { tex = tex, abilityId = GetSlotBoundId(slotNum, active) }
    end
  end
end

---@type fun(button: table, slotNum: number, hotbar: number)
l.applyDestaffMemory = function(button, slotNum, hotbar)
  if not (button and button.icon) then
    return
  end
  local key = hotbar .. ":" .. slotNum
  local abilityId = GetSlotBoundId(slotNum, hotbar)
  local tex = GetSlotTexture(slotNum, hotbar)
  if not (tex and tex ~= "") then
    return
  end
  if GetActiveHotbarCategory() == hotbar then
    -- 激活条：图标跟随当前武器，是正确的——存档(仅毁灭杖需要)
    if tex:find("ability_destructionstaff_", 1, true) then
      l.destaffMemory[key] = { tex = tex, abilityId = abilityId }
    end
  else
    -- 非激活条：图标可能已变成当前(另一把)武器形态——若记忆里有旧图则覆盖。
    -- 不比对 abilityId：非激活时连 GetSlotBoundId 返回的都是错误武器的变体 ID，
    -- 等值比对永远不成立；key 已含 hotbar:slot，技能真实变更会在该条下次激活时
    -- 由抓取刷新(换技能是低频操作，可接受)
    local mem = l.destaffMemory[key]
    if mem and tex:find("ability_destructionstaff_", 1, true) then
      if mem.tex ~= tex then
        button.icon:SetTexture(mem.tex)
      end
    elseif not tex:find("ability_destructionstaff_", 1, true) then
      -- 槽位换成了非毁灭杖技能，清理记忆
      l.destaffMemory[key] = nil
    end
  end
end

l.syncButton = function(button, hotbar)
  if not button then
    return
  end
  button.slot.hotbarCategory = hotbar
  button.button.hotbarCategory = hotbar
  button:HandleSlotChanged(hotbar)
  -- 纹理兑底：若原生链未能设置图标纹理，强制补没
  if button.icon then
    local tex = GetSlotTexture(button.slot.slotNum, hotbar)
    if tex and tex ~= "" then
      button.icon:SetTexture(tex)
      button.icon:SetHidden(false)
    end
  end
  -- 毁灭杖图标记忆(抓取/覆盖)
  l.applyDestaffMemory(button, button.slot.slotNum, hotbar)
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

---静态切换动画(优雅实现：全部 ANIMATION_MANAGER 时间线，无手写逐帧控制)：
---1) 切手按钮在两行间滑动(TranslateAnimation，结束后落位持久锚)
---2) 两行角色(尺寸/透明)渐变(ScaleAnimation+AlphaAnimation)，去饱和瞬时设置
l.swapGlideTimeline = nil

---瞬时设置角色(动画不可用/首次布局时使用)
---@type fun(button: table, isActive: boolean, s: number, dimAlpha: number, desat: number)
l.setRoleInstant = function(button, isActive, s, dimAlpha, desat)
  button.slot:SetScale(isActive and 1 or s)
  -- 大招尺寸统一(dims.ult：手柄=技能高，键盘=50)，与角色无关
  if button.slot.slotNum == 8 then
    l.setCloneSize(button, (IsInGamepadPreferredMode() and PLATFORM_DIMS.gamepad or PLATFORM_DIMS.keyboard).ult)
  end
  if button.icon then
    button.icon:SetAlpha(isActive and 1 or dimAlpha)
    button.icon:SetDesaturation(isActive and 0 or desat)
  end
  if isActive then
    l.showUltNumber(button)
  elseif button.countText then
    button.countText:SetHidden(true)
  end
  -- 终极攒满光效(仅激活行 slot8)
  l.updateUltGlow(button, isActive)
end

---懒创建角色渐变时间线(创建失败退化为瞬时切换，不影响按钮本身)
---@type fun(button: table): boolean
l.ensureRoleTimeline = function(button)
  if button.adrRoleTimeline then
    return true
  end
  if button.adrRoleFailed then
    return false
  end
  local ok, err = pcall(function()
    button.adrRoleTimeline = ANIMATION_MANAGER:CreateTimeline()
    button.adrRoleScale = button.adrRoleTimeline:InsertAnimation(ANIMATION_SCALE, button.slot)
    button.adrRoleScale:SetDuration(300)
    button.adrRoleScale:SetEasingFunction(ZO_EaseOutQuadratic)
    button.adrRoleAlpha = button.adrRoleTimeline:InsertAnimation(ANIMATION_ALPHA, button.icon)
    button.adrRoleAlpha:SetDuration(300)
    button.adrRoleAlpha:SetEasingFunction(ZO_EaseOutQuadratic)
  end)
  if not ok then
    button.adrRoleFailed = true
    button.adrRoleTimeline = nil
    d(string.format("[ADR] role animation unavailable: %s", tostring(err)))
    return false
  end
  return true
end

---@type fun()
l.animateStaticRoles = function()
  if not l.staticEngaged then
    return
  end
  local s = l.getSavedVars().barShowShiftScalePercent / 100
  local dimAlpha = l.getSavedVars().backBarDimAlpha / 100
  local desat = l.getSavedVars().backBarDesaturation / 100
  local active = GetActiveHotbarCategory()
  for slotNum = 3, 8 do
    local pButton = l.staticPrimary[slotNum]
    local bButton = l.staticBackup[slotNum]
    for _, button in ipairs({ pButton, bButton }) do
      local isActive = (active == HOTBAR_CATEGORY_PRIMARY) == (button == pButton)
      local targetScale = isActive and 1 or s
      local targetAlpha = isActive and 1 or dimAlpha
      -- 去饱和无原生颜色动画，始终瞬时设置；终极能量数字仅激活行显示；
      -- 大招尺寸统一(dims.ult：手柄=技能高，键盘=50)，与角色无关
      if button.icon then
        button.icon:SetDesaturation(isActive and 0 or desat)
      end
      if button.slot.slotNum == 8 then
        l.setCloneSize(button, (IsInGamepadPreferredMode() and PLATFORM_DIMS.gamepad or PLATFORM_DIMS.keyboard).ult)
      end
      if isActive then
        l.showUltNumber(button)
      elseif button.countText then
        button.countText:SetHidden(true)
      end
      -- 终极攒满光效(仅激活行 slot8)
      l.updateUltGlow(button, isActive)
      if button.adrRoleTimeline then
        -- 已在目标值上则跳过重播(高频事件防抖；目标变化时从当前实时值平滑重定)
        local curScale = button.slot:GetScale()
        local curAlpha = button.icon and button.icon:GetAlpha() or 1
        if math.abs(curScale - targetScale) > 0.001 or math.abs(curAlpha - targetAlpha) > 0.001 then
          button.adrRoleScale:SetScaleValues(curScale, targetScale)
          button.adrRoleAlpha:SetAlphaValues(curAlpha, targetAlpha)
          button.adrRoleTimeline:PlayFromStart()
        end
      elseif l.ensureRoleTimeline(button) then
        -- 首次确保后重试一次本帧播放
        local b2 = button
        zo_callLater(function()
          if b2.adrRoleTimeline and l.staticEngaged then
            l.animateStaticRoles()
          end
        end, 10)
      else
        l.setRoleInstant(button, isActive, s, dimAlpha, desat)
      end
    end
  end
end

---切手按钮滑动(TranslateAnimation)。动画栈不可用时退化为瞬时落位，绝不让异常炸同步链
---@type fun(weaponSwap: Control, swapX: number, fromY: number, toY: number)
l.playSwapGlide = function(weaponSwap, swapX, fromY, toY)
  local setAnchor = function(y)
    weaponSwap:ClearAnchors()
    weaponSwap:SetAnchor(TOPLEFT, ZO_ActionBar1, TOPLEFT, swapX, y)
  end
  if l.swapGlideFailed then
    setAnchor(toY)
    return
  end
  local ok, err = pcall(function()
    if not l.swapGlideTimeline then
      l.swapGlideTimeline = ANIMATION_MANAGER:CreateTimeline()
      l.swapGlideTranslate = l.swapGlideTimeline:InsertAnimation(ANIMATION_TRANSLATE, weaponSwap)
      l.swapGlideTranslate:SetDuration(300)
      l.swapGlideTranslate:SetEasingFunction(ZO_EaseOutQuadratic)
    end
    -- 并发控制：滑移中重触发先停在当前目标(OnStop 落位)，新滑移从那里出发，
    -- 避免回跳到旧起点
    if l.swapGlideTimeline:IsPlaying() then
      l.swapGlideTimeline:Stop()
    end
    setAnchor(fromY)
    -- SetTranslateDeltas 自动以控件当前锚定位置为原点做增量平移
    -- (SetTranslateOffsets 的坐标是锚点偏移绝对值，会造成动画期间跳位)
    l.swapGlideTranslate:SetTranslateDeltas(0, toY - fromY)
    l.swapGlideTimeline:SetHandler("OnStop", function()
      setAnchor(toY)
    end)
    l.swapGlideTimeline:PlayFromStart()
  end)
  if not ok then
    l.swapGlideFailed = true
    l.swapGlideTimeline = nil
    d(string.format("[ADR] swap glide animation unavailable: %s", tostring(err)))
    setAnchor(toY)
  end
end

---@type fun()
l.animateStaticSwap = function()
  if not l.staticEngaged then
    return
  end
  -- 切手后重新断言 Q 键锚
  l.reassertQAnchor()
  local _, _, gapY, swapX, swapY = l.platformOffsets()
  local nativeButton3 = ZO_ActionBar_GetButton(3)
  local liftY = l.rowSeparation()
  local onTop = GetActiveHotbarCategory() == HOTBAR_CATEGORY_PRIMARY
  local weaponSwap = ZO_ActionBar1 and ZO_ActionBar1:GetNamedChild("WeaponSwap")
  if weaponSwap then
    local fromY = onTop and swapY or (swapY - liftY)
    local toY = onTop and (swapY - liftY) or swapY
    l.playSwapGlide(weaponSwap, swapX, fromY, toY)
  end
  l.animateStaticRoles()
  -- 换手后如果新激活 ult 已攒满，立即播音效——但仅限【未满→满】转换：
  -- 满→满时旧条已在持续辉光，原生语义不重复响(与动态预设/纯原生一致)。
  -- 光效稍后启动(与角色渐变同步)，不受转换类型限制(激活行该亮就亮)
  local activeCat = GetActiveHotbarCategory()
  local newActiveSet = activeCat == HOTBAR_CATEGORY_PRIMARY and l.staticPrimary or l.staticBackup
  local oldHotbar = activeCat == HOTBAR_CATEGORY_PRIMARY and HOTBAR_CATEGORY_BACKUP or HOTBAR_CATEGORY_PRIMARY
  local ultPower = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_ULTIMATE)
  pcall(function()
    newActiveSet[8]:UpdateCurrentUltimateMax()
  end)
  local ultMax = newActiveSet[8].currentUltimateMax or 0
  -- 旧激活条的消耗(GetSlotAbilityCost 是原生 UpdateCurrentUltimateMax 同款 API)
  local oldMax = GetSlotAbilityCost(8, COMBAT_MECHANIC_FLAGS_ULTIMATE, oldHotbar) or 0
  local isNewlyReady = ultMax > 0 and ultPower >= ultMax
  local wasReady = oldMax > 0 and ultPower >= oldMax
  if isNewlyReady then
    if not wasReady then
      PlaySound(SOUNDS.ABILITY_ULTIMATE_READY)
    end
    zo_callLater(function()
      if l.staticEngaged then
        l.updateUltGlow(newActiveSet[8], true, false)
      end
    end, 300)
  end
end

---同步整行(换武器/全量刷新)。relayout=false 时仅刷数据不重排锚点
---(换装等高频事件避免锚点风暴: too many anchors processed)
---@type fun(relayout?: boolean)
l.syncAll = function(relayout)
  if not l.container or l.swapInProgress then
    return
  end
  -- 抓取激活条毁灭杖图标(激活时是正确形态；切手后就来不及了)
  l.captureActiveDestaff()
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
  -- 静态：两行各自按恒定分类同步，与激活状态无关(内容永不随换武器重刷)
  if l.staticEngaged then
    for slotNum = 3, 8 do
      l.syncButton(l.staticPrimary[slotNum], HOTBAR_CATEGORY_PRIMARY)
      l.syncButton(l.staticBackup[slotNum], HOTBAR_CATEGORY_BACKUP)
    end
    return
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
  -- 毁灭杖图标：翻转半程直接设了新(可能错误武器形态的)图标，立即用记忆覆盖防闪变
  l.applyDestaffMemory(button, button.slot.slotNum, hotbar)
  -- HandleSlotChanged→ApplyStyle 会把 FlipCard 重置到模板值(ult=67)且
  -- ApplySwapAnimationStyle 读到 67 设入动画后半程起止值——克隆 ult 在
  -- 翻转展开阶段会偏大。同原生 reapply 的修法：缩回目标值后重设动画参数
  local dims = IsInGamepadPreferredMode() and PLATFORM_DIMS.gamepad or PLATFORM_DIMS.keyboard
  l.setCloneSize(button, button.slot.slotNum == 8 and dims.ult or dims.ability)
  if button.ApplySwapAnimationStyle then
    pcall(function()
      button:ApplySwapAnimationStyle()
    end)
  end
  l.applyInactiveStyle(button)
  -- Q 键提示锚的重断言已改为 PostHook 原生药剂栏按钮(见 registerEvents)，
  -- 不再在此处追赶原生刷新时机
  -- 经典模式下重应用可见性(HandleSlotChanged 会重新显示槽位)
  if l.classicMode then
    button.slot:SetHidden(not (l.classicVisibleMap and l.classicVisibleMap[button.slot.slotNum] == true))
  end
end

---翻转结束回调
---@type fun(_, button: table)
---缩/还原原生 slot8(手柄)：克隆行激活期间把原生大招从 70 缩到与技能同高(64)，
---否则动态模式下可见的原生 70px 大招与 64px 克隆行不一致。
---用 setCloneSize 处理(子控件名称相同：FlipCard/Button/Backdrop/Frame)；
---还原时用原生前值(手柄 70/67，键盘 50/47)
l.nativeUltResized = false

---@type fun()
l.resizeNativeUlt = function()
  local dims = IsInGamepadPreferredMode() and PLATFORM_DIMS.gamepad or PLATFORM_DIMS.keyboard
  local nb = ZO_ActionBar_GetButton(8)
  if nb and nb.slot then
    -- 缩尺寸 + 隐藏非光效装饰：不能用完整版 hideUltimateDecorations——
    -- 它会把 ReadyBurst/ReadyLoop 纹理藏掉，原生 loop 仍在隐藏纹理上无限播放，
    -- 后续 swap-to-ready 的 burst 条件(loop 未播)永不成 → 无光效无声音
    l.setCloneSize({ slot = nb.slot, icon = nb.icon }, dims.ult)
    local hide = {
      "UltimateBar", "LeadingEdge", "FillAnimationLeft", "FillAnimationRight",
      "Decoration", "Frame", "LeftKeybind", "RightKeybind",
    }
    for i = 1, #hide do
      local child = nb.slot:GetNamedChild(hide[i])
      if child then
        child:SetHidden(true)
      end
    end
    l.nativeUltResized = true
    -- PostHook 原生方法：原生翻转动画中会重设模板值(70px+装饰+肩键)，
    -- 钩在原生代码之后立刻覆盖；但保留 ReadyBurst/ReadyLoop(攒满光效是原生自然行为)
    if not l.nativeUltHooked then
      local hooked = nb
      local inReapply = false -- 防重入：reapply→ApplySwapAnimationStyle→本钩子→reapply 无限递归
      local function reapply()
        if l.nativeUltResized and not inReapply then
          inReapply = true
          local d = IsInGamepadPreferredMode() and PLATFORM_DIMS.gamepad or PLATFORM_DIMS.keyboard
          l.setCloneSize({ slot = hooked.slot, icon = hooked.icon }, d.ult)
          -- 只藏非光效装饰(保留 ReadyBurst/ReadyLoop 供原生攒满动画)
          local hide = {
            "UltimateBar", "LeadingEdge", "FillAnimationLeft", "FillAnimationRight",
            "Decoration", "Frame", "LeftKeybind", "RightKeybind",
          }
          for i = 1, #hide do
            local child = hooked.slot:GetNamedChild(hide[i])
            if child then
              child:SetHidden(true)
            end
          end
          -- 关键：重设动画起止尺寸(FlipCard 已是我们的 61，原生链里它在
          -- ApplyStyle 内部读到的还是模板 67)。不 PostHook 本方法——
          -- 防重入闸已阻断递归，且其他三个钩子入口已覆盖所有重设时机
          if hooked.ApplySwapAnimationStyle then
            pcall(function()
              hooked:ApplySwapAnimationStyle()
            end)
          end
          inReapply = false
        end
      end
      l.reapplyNativeUlt = reapply
      if hooked.ApplyStyle then
        ZO_PostHook(hooked, "ApplyStyle", reapply)
      end
      if hooked.HandleSlotChanged then
        ZO_PostHook(hooked, "HandleSlotChanged", reapply)
      end
      if hooked.UpdateUltimateMeter then
        ZO_PostHook(hooked, "UpdateUltimateMeter", reapply)
      end
      l.nativeUltHooked = true
    end
  end
end

---@type fun()
l.restoreNativeUlt = function()
  if not l.nativeUltResized then
    return
  end
  l.nativeUltResized = false
  -- 手柄原生前值：slot 70, FlipCard 67
  local nb = ZO_ActionBar_GetButton(8)
  if nb and nb.slot then
    nb.slot:SetDimensions(70, 70)
    local fc = nb.slot:GetNamedChild("FlipCard")
    if fc then
      fc:SetDimensions(ZO_GAMEPAD_ULTIMATE_BUTTON_SIZE, ZO_GAMEPAD_ULTIMATE_BUTTON_SIZE)
    end
    local btn = nb.slot:GetNamedChild("Button")
    if btn then
      btn:SetDimensions(70, 70)
    end
    -- 还原装饰可见性：Frame 在手柄键盘模式均为装饰边框，原生动态下应恢复
    local frame = nb.slot:GetNamedChild("Frame")
    if frame then
      frame:SetHidden(true) -- 原生手柄模板里 Frame 本身 hidden=true，不强制
    end
    -- Decoration 是 ult 专属装饰，恢复显示
    local deco = nb.slot:GetNamedChild("Decoration")
    if deco then
      deco:SetHidden(false)
    end
    -- Backdrop/Frame 锚不显式恢复(原生 ApplyStyle 会在下次平台切换时重设)
  end
end

---重断言 Q 标签锚(静态/动态通用)：原生 keybind refresh 或 ApplyStyle
---可能在任何时刻覆盖我们的自定义锚，每次布局/切手后重新断言
---@type fun()
---终极攒满光效(激活行 slot8)：用原生同款 ReadyBurst→ReadyLoop 序列
---(coolDown_completeEFX.dds ADD 混合，TextureAnimation 逐帧播放)
---非激活行不显示。通过 EVENT_POWER_UPDATE 驱动
l.ultGlowTimelines = {}

---@type fun(button: table, isActive: boolean, playSound?: boolean)
l.updateUltGlow = function(button, isActive, playSound)
  if button.slot.slotNum ~= 8 then
    return
  end
  local glow = button.slot:GetNamedChild("ReadyBurst")
  local loop = button.slot:GetNamedChild("ReadyLoop")
  if not glow or not loop then
    return
  end
  -- 用原生方法获取 ult 消耗(GetAbilityCost 不存在，UpdateCurrentUltimateMax 是正道)
  local ult = GetUnitPower("player", COMBAT_MECHANIC_FLAGS_ULTIMATE)
  local max = 0
  pcall(function()
    button:UpdateCurrentUltimateMax()
  end)
  max = button.currentUltimateMax or 0
  local isReady = isActive and max > 0 and ult >= max
  if isReady then
    glow:SetHidden(false)
    loop:SetHidden(false)
    -- 懒创建时间线(原生虚拟时间线 UltimateReadyBurst/Loop，同款帧动画+音效)
    if l.ultGlowTimelines[button] == nil then
      local ok = pcall(function()
        local burstTL = ANIMATION_MANAGER:CreateTimelineFromVirtual("UltimateReadyBurst", glow)
        local loopTL = ANIMATION_MANAGER:CreateTimelineFromVirtual("UltimateReadyLoop", loop)
        burstTL:SetHandler("OnStop", function(tl)
          if tl:GetProgress() >= 1.0 then
            glow:SetHidden(true)
            loopTL:PlayFromStart()
          end
        end)
        l.ultGlowTimelines[button] = { burst = burstTL, loop = loopTL }
      end)
      if not ok then
        l.ultGlowTimelines[button] = false
        d("[ADR] ult glow animation unavailable")
        return
      end
    end
    -- 音效直接在调用点播(不放在时间线闭包里——闭包捕获首次创建时的参数不会更新)
    if playSound then
      PlaySound(SOUNDS.ABILITY_ULTIMATE_READY)
    end
    local tls = l.ultGlowTimelines[button]
    if tls and not tls.burst:IsPlaying() and not tls.loop:IsPlaying() then
      tls.burst:PlayFromStart()
    end
  else
    glow:SetHidden(true)
    loop:SetHidden(true)
    local tls = l.ultGlowTimelines[button]
    if tls then
      tls.burst:Stop()
      tls.loop:Stop()
    end
  end
  -- 手柄键提示(激活行显示，键盘藏)
  if isActive then
    l.showUltRoleDecorations(button)
  else
    l.hideUltRoleDecorations(button)
  end
end

---重断言 D8 肩键锚(同 reassertQAnchor 的思路)：ApplyStyle/平台切换会重置锚到模板原生位
---调用点：layoutDynamic / applyPlatformStyle / onSwapAnimationDone
---@type fun()
l.reassertUltKeybinds = function()
  if not (l.buttons[8] and l.buttons[8].slot) then
    return
  end
  local weaponSwap = ZO_ActionBar1 and ZO_ActionBar1:GetNamedChild("WeaponSwap")
  local _, _, _, swapX, swapY = l.platformOffsets()
  local abilityGap, ultGap = l.platformOffsets()
  local swapW = weaponSwap and weaponSwap:GetWidth() or 56
  local swapH = weaponSwap and weaponSwap:GetHeight() or 70
  local dims = PLATFORM_DIMS.gamepad
  local ultX = swapX + swapW + abilityGap
    + 4 * (dims.ability + abilityGap) + dims.ability + ultGap + dims.ult / 2
  local ultY = swapY + swapH / 2 + dims.ult / 2 + 2
  local showKb = IsInGamepadPreferredMode() and ZO_Keybindings_ShouldShowGamepadKeybind()
  local dUlt = l.buttons[8]
  local lk = dUlt.slot:GetNamedChild("LeftKeybind")
  local rk = dUlt.slot:GetNamedChild("RightKeybind")
  if lk then
    lk:ClearAnchors()
    lk:SetAnchor(CENTER, ZO_ActionBar1, TOPLEFT, ultX - 22, ultY + 11)
    lk:SetHidden(not showKb)
  end
  if rk then
    rk:ClearAnchors()
    rk:SetAnchor(CENTER, ZO_ActionBar1, TOPLEFT, ultX + 22, ultY + 11)
    rk:SetHidden(not showKb)
  end
end

---重断言 Q 标签锚(静态/动态通用)：原生 keybind refresh 或 ApplyStyle
---可能在任何时刻覆盖我们的自定义锚，每次布局/切手后重新断言
---@type fun()
l.reassertQAnchor = function()
  if DoesUnitExist("companion") and HasActiveCompanion() then
    return
  end
  local qs = ZO_ActionBar_GetButton(1, HOTBAR_CATEGORY_QUICKSLOT_WHEEL)
  if qs and qs.slot then
    local qsText = qs.slot:GetNamedChild("ButtonText")
    if qsText then
      qsText:ClearAnchors()
      qsText:SetAnchor(TOP, qs.slot, BOTTOM, 0, IsInGamepadPreferredMode() and 2 or 1)
    end
  end
end

local function onSwapAnimationDone(_, button)
  button.noUpdates = false
  -- 解锁内容更新抑制(所有按钮动画完毕；最后一个回调时 swapInProgress 已被600ms兜底清)
  l.swapInProgress = false
  -- 翻转动画后原生 ApplyStyle 可能重置了 Backdrop/Frame 锚和尺寸，补上
  local dims = IsInGamepadPreferredMode() and PLATFORM_DIMS.gamepad or PLATFORM_DIMS.keyboard
  l.setCloneSize(button, button.slot.slotNum == 8 and dims.ult or dims.ability)
  -- 确保内容与 hotbar 同步(动画期间被抑制的更新在此补齐)
  if button.slot.hotbarCategory ~= l.currentHotbar then
    l.currentHotbar = button.slot.hotbarCategory
  end
  l.syncSlot(button.slot.slotNum, button.slot.hotbarCategory)
  -- Q 标签在动态模式下不动(原生条原封不动，Q 用原生锚即可——动它反而与原生刷新拉锯)
  l.reassertUltKeybinds()
  -- 切手声音确定性修复：原生在切手中(g=true)只启动无声 loop，burst+声音被跳过；
  -- g 复位时机不定导致声音时有时无。动画结束 50ms 后(g 已复位)补调原生
  -- UpdateUltimateMeter：新条满且无 loop → 原生 burst+声音；已有 loop(持续辉光中)
  -- → 不重复；不满 → 确保熄灭。零双重播放(状态判定全在原生内部)
  zo_callLater(function()
    if not l.active or l.staticEngaged then
      return
    end
    local nb = ZO_ActionBar_GetButton(8)
    if nb then
      pcall(function()
        nb:UpdateUltimateMeter()
      end)
    end
  end, 50)
end

---@type fun(button: table, getCategory?: fun(): number|nil)
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
  -- ApplyStyle 会重置 D8 肩键锚到模板原生位，平台切换后重新钉回。
  -- 延迟 200ms：ZO_PlatformStyle 有多个处理器按序执行，
  -- 后续原生处理器的 ApplyStyle 会再次重置锚，必须等全部跑完
  zo_callLater(function()
    if l.active then
      l.reassertUltKeybinds()
    end
  end, 200)
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
    -- 动画期间抑制其他事件源的内容更新(否则半程前就被 syncAll/syncSlot 换掉)
    l.swapInProgress = true
    for slotNum = 3, 8 do
      local button = l.buttons[slotNum]
      if button and button.hotbarSwapAnimation then
        button.hotbarSwapAnimation:PlayFromStart()
      end
    end
    -- 保险：如果动画被外部 Stop 导致 onSwapAnimationDone 不触发，600ms 后解锁
    zo_callLater(function()
      l.swapInProgress = false
    end, 600)
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
    -- 切手瞬间新激活条的毁灭杖图标是正确的(武器已匹配)，立即存档；
    -- 旧条的记忆在它上次激活期间已抓取
    l.captureActiveDestaff()
    if l.staticEngaged then
      -- 静态：位置/内容均不变，激活角色(明暗/尺寸)以时间线动画互换，切手按钮滑动。
      -- 只在真正换手(didActiveHotbarChange)时触发——声音追踪证实一次切手会连发
      -- 多次本事件(首饮 T 其余 F)，不门控会导致音效叠加(7 连响)与重复动画调度
      if didActiveHotbarChange then
        l.animateStaticSwap()
      end
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
  -- 终极能量变化时更新攒满光效
  EM:RegisterForEvent(EVENT_NAME .. "UltGlow", EVENT_POWER_UPDATE, function(_, unitTag, _, powerType)
    if unitTag ~= "player" or powerType ~= COMBAT_MECHANIC_FLAGS_ULTIMATE then
      return
    end
    if l.staticEngaged then
      local active = GetActiveHotbarCategory()
      local activeSet = active == HOTBAR_CATEGORY_PRIMARY and l.staticPrimary or l.staticBackup
      l.updateUltGlow(activeSet[8], true)
    end
  end)
  EM:RegisterForEvent(EVENT_NAME, EVENT_INVENTORY_SINGLE_SLOT_UPDATE, function()
    -- 换装高频事件：仅刷数据(可用状态/计数)，不重排锚点
    l.syncAll(false)
  end)
  EM:AddFilterForEvent(EVENT_NAME, EVENT_INVENTORY_SINGLE_SLOT_UPDATE, REGISTER_FILTER_BAG_ID, BAG_WORN)
  -- Keybind Display Mode 设置变化时刷新肩键。原生源码(keybindingutils.lua)用
  -- 专用事件 EVENT_KEYBIND_DISPLAY_MODE_CHANGED(非 EVENT_INTERFACE_SETTING_CHANGED)，
  -- 设置存储在 SETTING_TYPE_GAMEPAD。延迟 200ms 等原生 label 更新链跑完
  EM:RegisterForEvent(EVENT_NAME .. "KbMode", EVENT_KEYBIND_DISPLAY_MODE_CHANGED, function()
    zo_callLater(function()
      if l.active then
        l.refreshUltKeybinds()
        l.reassertUltKeybinds()
        -- 原生 slot8 的肩键被原生 label 系统的 OnUltimateChanged→HideKeys(false)
        -- 显示出来(我们只藏克隆行的)；reapplyNativeUlt 会重缩尺寸+藏原生肩键，
        -- 原生条可见时(动态)不能出现两组肩键
        if l.nativeUltResized and l.reapplyNativeUlt then
          l.reapplyNativeUlt()
        end
      end
    end, 200)
  end)
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
  EM:UnregisterForEvent(EVENT_NAME .. "UltGlow", EVENT_POWER_UPDATE)
  EM:UnregisterForEvent(EVENT_NAME .. "KbMode", EVENT_KEYBIND_DISPLAY_MODE_CHANGED)
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
  l.restoreKeybindOffsets()
  -- 还原原生 slot8 尺寸(手柄 70/67)
  l.restoreNativeUlt()
  -- 手柄下恢复切手按钮的原生行为(永久隐藏)并回默认锚
  local weaponSwap = ZO_ActionBar1 and ZO_ActionBar1:GetNamedChild("WeaponSwap")
  if weaponSwap then
    local _, _, _, swapX, swapY = l.platformOffsets()
    weaponSwap:ClearAnchors()
    weaponSwap:SetAnchor(TOPLEFT, ZO_ActionBar1, TOPLEFT, swapX, swapY)
    if IsInGamepadPreferredMode() and ZO_WeaponSwap_SetPermanentlyHidden then
      ZO_WeaponSwap_SetPermanentlyHidden(weaponSwap, true)
    end
  end
  if l.container then
    l.container:SetHidden(true)
  end
end

---@type fun()
l.onCoreUpdate = function()
  local sv = l.getSavedVars()
  -- FAB 存在时任何预设都不激活克隆行(回退贴图经典)；否则所有预设激活，
  -- classic 仅作为可见性模式(每槽有计时才显示，由 Bar 模块每帧传入可见集)
  local want = sv.barEnabled and FancyActionBar == nil
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
    -- 技能激活光效：引擎对非激活条的槽位状态不维护(查询返回过期值，dump 证实)，
    -- 公开 API 无通用真源(FAB 同样因此不在副条渲染光效)。策略：
    -- 激活条克隆→轮询 UpdateActivationHighlight(激活条查询实时正确)；
    -- 非激活条克隆→主动熄灭(宁无光效，不卡死光效)
    local activeCat = GetActiveHotbarCategory()
    local sets = l.staticEngaged and { l.staticPrimary, l.staticBackup } or { l.buttons }
    for si = 1, #sets do
      for slotNum = 3, 8 do
        local b = sets[si][slotNum]
        if b and b.hasAction then
          if b.slot.hotbarCategory == activeCat then
            pcall(function()
              b:UpdateActivationHighlight()
            end)
          elseif b.activationHighlight and not b.activationHighlight:IsControlHidden() then
            b.activationHighlight:SetHidden(true)
            if b.activationHighlight.animation then
              pcall(function()
                b.activationHighlight.animation:GetTimeline():Stop()
              end)
            end
          end
        end
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

---@type fun(): string?
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
    -- 极简 dump：每槽一行内联尺寸(slot|FC|Icon|BD|Btn)，D3/D8/N3/N8 四行直接对比
    local function oneLine(label, button)
      if not (button and button.slot) then
        d(string.format("[ADR] %s (nil)", label))
        return
      end
      local s = button.slot
      local function dim(c)
        if not c then
          return "--"
        end
        return string.format("%.0f", c:GetWidth() or -1)
      end
      local fc = s:GetNamedChild("FlipCard")
      local ic = s:GetNamedChild("Icon")
      local bd = s:GetNamedChild("Backdrop")
      local bt = s:GetNamedChild("Button")
      d(string.format("[ADR] %s slot=%.0f sc=%.2f | FC=%s Icon=%s BD=%s%s Btn=%s",
        label, s:GetWidth() or -1, s:GetScale() or -1,
        dim(fc), dim(ic),
        dim(bd), bd and bd:IsControlHidden() and "[hid]" or "", dim(bt)))
    end
    oneLine("D3", l.buttons[3])
    oneLine("D8", l.buttons[8])
    oneLine("N3", ZO_ActionBar_GetButton(3))
    oneLine("N8", ZO_ActionBar_GetButton(8))
    -- 激活光效诊断：对比三个数据源(激活条查询/各自条查询/玩家 buff 表)，
    -- 验证非激活条查询是否陈旧、以及 buff 同名链接假设
    local active = GetActiveHotbarCategory()
    local other = active == HOTBAR_CATEGORY_PRIMARY and HOTBAR_CATEGORY_BACKUP or HOTBAR_CATEGORY_PRIMARY
    for slotNum = 3, 8 do
      local qA = ActionSlotHasActivationHighlight(slotNum, active)
      local qO = ActionSlotHasActivationHighlight(slotNum, other)
      if qA or qO then
        local _, _, texA = GetSlotTexture(slotNum, active)
        local _, _, texO = GetSlotTexture(slotNum, other)
        local idO = GetSlotBoundId(slotNum, other)
        local nameO = idO and idO > 0 and GetAbilityName(idO) or ""
        d(string.format(
          "[ADR] AH slot%d actQ=%s othQ=%s | actTex=%s othTex=%s | othBar=%s",
          slotNum, tostring(qA), tostring(qO),
          tostring(texA), tostring(texO), nameO))
      end
    end
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

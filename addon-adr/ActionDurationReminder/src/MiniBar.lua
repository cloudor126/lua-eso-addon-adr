--========================================
--        MiniBar
--========================================
--迷你行预设(mini)的自包含第二行：原生 Ability Bar Back Row 的自绘复刻
--+ 计时数字。数据源 = 引擎槽位效果计时(GetActionSlotEffectTimeRemaining，
--与原生 back row 填充条/激活条槽位小倒计时同源)，与 ADR 的 action 匹配
--系统、Views widget 体系、BackBar 克隆引擎全部无关——架构定位是
--mainonly(原生条零干预) + 本外挂。
--
--关键取舍：
--- 位置纯原生(逐槽 CENTER 锚 + 原生 offsetY 常量)，与 Move Shift Bar 无关
--- 仅显示有计时的槽位(引擎效果计时 > 0；无计时槽位不渲染，用户需求)
--- 图标 GetSlotTexture(槽位查询)：引擎对非激活条返回的毁灭杖形态可能过期
--  (已知引擎限制，原生 back row 同样接受该语义)
--- 计时数字复用 Time Labels 的字体/颜色设置
local addon = ActionDurationReminder
---@type adr.settings.M
local settings = addon.load("Settings#M")
---@type adr.core.M
local core = addon.load("Core#M")
---@type adr.models.M
local models = addon.load("Models#M")
local l = {}
---@class adr.minibar.M
---@field relayout? fun()
---@field setEnabled? fun(enabled: boolean)
local m = { l = l }

--========================================
--        l
--========================================
---槽位尺寸/贴图参数：与原生 back row 模板一致
---(actionbutton.xml: ZO_ActionBarTimer_BackBarSlot 键盘 40×56 / 手柄 52×68)
local MINI_DIMS = {
  keyboard = { w = 40, h = 56, coords = { 0, 0.625, 0, 0.875 } },
  gamepad = { w = 52, h = 68, coords = { 0, 0.8125, 0, 1.0625 } },
}

---原生 back row 锚定偏移(actionbar.lua 常量：ability/ult 分开，ult 原生槽更高)
---@return number, number, table
local function nativeLayout()
  if IsInGamepadPreferredMode() then
    return -17, -30, MINI_DIMS.gamepad
  end
  return -17, -20, MINI_DIMS.keyboard
end

---@type fun(): adr.settings.SavedVars
l.getSavedVars = function()
  return settings.getSavedVars()
end

---当前非激活武器条(PRIMARY↔BACKUP；非武器热栏如攻城返回 nil)
---@return number|nil
l.inactiveHotbar = function()
  local active = GetActiveHotbarCategory()
  if active == HOTBAR_CATEGORY_PRIMARY then
    return HOTBAR_CATEGORY_BACKUP
  elseif active == HOTBAR_CATEGORY_BACKUP then
    return HOTBAR_CATEGORY_PRIMARY
  end
  return nil
end

---Oakensoul 单手戒(无第二武器条)
---@return boolean
l.hasOakensoul = function()
  local icon1 = GetItemLinkIcon(GetItemLink(BAG_WORN, EQUIP_SLOT_RING1))
  local icon2 = GetItemLinkIcon(GetItemLink(BAG_WORN, EQUIP_SLOT_RING2))
  return (icon1 and icon1:find("oakensoul") ~= nil) or (icon2 and icon2:find("oakensoul") ~= nil)
end

---计时数字格式化：整秒(迷你行紧凑显示)
---@param remainMs number
---@return string
l.formatRemain = function(remainMs)
  return string.format("%d", remainMs / 1000)
end

---槽位当前 action(Core 数据源，与主条计时同源同值)：
---优先按槽位匹配，回退按 abilityId 匹配(与 Bar 主条流程同款逻辑)
---@param slotNum number
---@param hotbar number
---@param now number
---@return adr.models.Action|nil, number|nil -- action, 剩余毫秒
local getSlotAction = function(slotNum, hotbar, now)
  local abilityId = GetSlotBoundId(slotNum, hotbar)
  if GetSlotType(slotNum, hotbar) == ACTION_TYPE_CRAFTED_ABILITY then
    abilityId = GetAbilityIdForCraftedAbilityId(abilityId)
  end
  local action = core.getActionBySlot(hotbar, slotNum)
  if
    action
    -- check this position action
    and not action:matchesAbilityIcon(GetSlotTexture(slotNum, hotbar))
    and not action:matchesAbilityName(models.patchAbilityName(GetSlotName(slotNum, hotbar)))
  then
    action = nil
  end
  if not action then
    action = core.getActionByAbilityId(abilityId)
  end
  if action then
    local remain = action:getEndTime() - now
    if remain > 0 and #action.effectList > 0 and not action:isUnlimited() then
      return action, remain
    end
  end
  return nil, nil
end

--========================================
--        建行/布局
--========================================
---创建迷你行(懒创建)：容器重父 WeaponSwap(XML 顺序 KeybindBG→WeaponSwap→技能槽)，
---深度优先绘制序使整个迷你子树先于技能槽子树——与原生条重叠时原生条遮挡
---(与 BackBar 容器同款 z-order 沉底方案)。槽位非交互(纯展示，同原生 back row)
---@type fun()
l.createRow = function()
  if l.container then
    return
  end
  local weaponSwapHost = ZO_ActionBar1 and ZO_ActionBar1:GetNamedChild("WeaponSwap")
  l.container = WINDOW_MANAGER:CreateControl("ADRMiniBarRow", weaponSwapHost or GuiRoot, CT_CONTROL)
  l.slots = {}
  for slotNum = 3, 8 do
    local control = WINDOW_MANAGER:CreateControl("ADRMiniBarSlot" .. slotNum, l.container, CT_CONTROL)
    control:SetMouseEnabled(false)
    -- Icon：图标纹理(引擎槽位贴图)
    local icon = WINDOW_MANAGER:CreateControl("Icon", control, CT_TEXTURE)
    icon:SetAnchor(TOPLEFT, control, TOPLEFT, 1, 1)
    icon:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, -1, -1)
    -- 计时数字(字体/颜色复用 Time Labels 设置)
    local label = WINDOW_MANAGER:CreateControl("Timer", control, CT_LABEL)
    label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    label:SetVerticalAlignment(TEXT_ALIGN_BOTTOM)
    label:SetAnchor(BOTTOM, control, BOTTOM, 0, 2)
    -- 三层原生贴图(创建序即绘制序：BG<Icon<Overlay<Frame；三元组零覆盖
    -- →与图标平齐靠创建序，随子树沉入原生条之下)
    local art = IsInGamepadPreferredMode() and "EsoUI/Art/ActionBar/Gamepad/gp_backrow_abilityFrame"
      or "EsoUI/Art/ActionBar/backrow_abilityFrame"
    local function layerTex(name, file)
      local t = WINDOW_MANAGER:CreateControl(name, control, CT_TEXTURE)
      t:SetTexture(file)
      t:SetAnchor(CENTER, control, CENTER)
      t:SetTextureCoords(unpack((IsInGamepadPreferredMode() and MINI_DIMS.gamepad or MINI_DIMS.keyboard).coords))
      return t
    end
    layerTex("BG", art .. "_BLANK.dds")
    layerTex("Overlay", art .. "_overlay.dds")
    layerTex("Frame", art .. ".dds")
    l.slots[slotNum] = { control = control, icon = icon, label = label, iconPath = nil }
  end
  l.relayout()
end

---重排：尺寸/贴图按当前平台，锚点纯原生(逐槽 CENTER→原生槽 CENTER，
---offsetY 用原生常量；Shift Bar Scale 滑条生效，位置偏移不生效)
---@type fun()
l.relayout = function()
  if not l.container then
    return
  end
  local sv = l.getSavedVars()
  local abilityOffY, ultOffY, dims = nativeLayout()
  local scale = sv.barShowShiftScalePercent / 100
  local art = IsInGamepadPreferredMode() and "EsoUI/Art/ActionBar/Gamepad/gp_backrow_abilityFrame"
    or "EsoUI/Art/ActionBar/backrow_abilityFrame"
  for slotNum = 3, 8 do
    local entry = l.slots[slotNum]
    local nativeButton = ZO_ActionBar_GetButton(slotNum)
    if entry and nativeButton then
      local control = entry.control
      control:SetDimensions(dims.w, dims.w)
      for _, name in ipairs({ "BG", "Overlay", "Frame" }) do
        local t = control:GetNamedChild(name)
        if t then
          t:SetTexture(art .. (name == "Frame" and ".dds" or (name == "BG" and "_BLANK.dds" or "_overlay.dds")))
          t:SetDimensions(dims.w, dims.h)
        end
      end
      control:ClearAnchors()
      -- CENTER 锚：缩放围绕锚点仍居中对位(与原生 back row 同锚型)
      control:SetAnchor(CENTER, nativeButton.slot, CENTER, 0, slotNum == 8 and ultOffY or abilityOffY)
      control:SetScale(scale)
      -- 数字字体(Time Labels 设置)
      entry.label:SetFont(string.format("$(%s)|%d|%s",
        sv.barLabelFontName or "BOLD_FONT", sv.barLabelFontSize or 18, sv.barLabelFontStyle or "thick-outline"))
    end
  end
  l.syncAll()
end

--========================================
--        同步(引擎数据驱动)
--========================================
---全槽同步(Core action 数据源)：可见性(有计时 action) + 图标(action 的
---ability 图标，非槽位查询——天然免疫毁灭杖非激活条图标过期) + 数字。
---不可用(非武器热栏/Oakensoul/预设非 mini)时整行隐藏
---@type fun()
l.syncAll = function()
  if not l.container then
    return
  end
  local sv = l.getSavedVars()
  if sv.barPreset ~= "mini" or not sv.barEnabled then
    l.container:SetHidden(true)
    return
  end
  local hotbar = l.inactiveHotbar()
  if not hotbar or l.hasOakensoul() then
    l.container:SetHidden(true)
    return
  end
  l.container:SetHidden(false)
  local now = GetGameTimeMilliseconds()
  local alpha = (sv.backBarDimAlpha or 100) / 100
  local desat = (sv.backBarDesaturation or 0) / 100
  for slotNum = 3, 8 do
    local entry = l.slots[slotNum]
    if entry then
      local action, remain = getSlotAction(slotNum, hotbar, now)
      if action then
        local iconPath = action.ability and action.ability.icon
        if iconPath and iconPath ~= "" and iconPath ~= entry.iconPath then
          entry.iconPath = iconPath
          entry.icon:SetTexture(iconPath)
        end
        entry.icon:SetAlpha(alpha)
        entry.icon:SetDesaturation(desat)
        entry.label:SetText(l.formatRemain(remain))
        entry.label:SetColor(unpack(sv.barLabelColor or { 1, 1, 1 }))
        entry.control:SetHidden(false)
      else
        entry.control:SetHidden(true)
      end
    end
  end
end

---心跳(Core 100ms)：数字倒数刷新 + 可见性/图标准时同步
---@type fun()
l.onCoreUpdate = function()
  local sv = l.getSavedVars()
  if sv.barPreset ~= "mini" or not sv.barEnabled then
    if l.container then
      l.container:SetHidden(true)
    end
    return
  end
  if not l.container then
    l.createRow()
  end
  l.syncAll()
end

--========================================
--        生命周期
--========================================
---预设启用/停用(mini ↔ 其他预设切换)
---@param enabled boolean
m.setEnabled = function(enabled)
  if enabled then
    if l.getSavedVars().barPreset == "mini" and l.getSavedVars().barEnabled then
      l.createRow()
      l.relayout()
    end
  elseif l.container then
    l.container:SetHidden(true)
  end
end

---位置/缩放/字体设置变化后重排(Bar 模块菜单调用)
---@type fun()
m.relayout = function()
  l.relayout()
end

--========================================
--        register
--========================================
addon.register("MiniBar#M", m)

---心跳(Core 100ms)：倒数刷新/可见性/图标同步
addon.extend(core.EXTKEY_UPDATE, l.onCoreUpdate)

---事件：切手→立即同步；平台切换/玩家激活→重排(延迟等原生链)
local function registerEvents()
  local em = EVENT_MANAGER
  em:RegisterForEvent("ADRMiniBar", EVENT_ACTION_SLOTS_ACTIVE_HOTBAR_UPDATED, function()
    l.syncAll()
  end)
  em:RegisterForEvent("ADRMiniBar", EVENT_GAMEPAD_PREFERRED_MODE_CHANGED, function()
    zo_callLater(function()
      l.relayout()
    end, 200)
  end)
  em:RegisterForEvent("ADRMiniBar", EVENT_PLAYER_ACTIVATED, function()
    zo_callLater(function()
      if l.getSavedVars().barPreset == "mini" and l.getSavedVars().barEnabled then
        l.createRow()
        l.relayout()
      end
    end, 200)
  end)
end
registerEvents()

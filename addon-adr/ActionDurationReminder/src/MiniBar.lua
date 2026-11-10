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
---创建迷你行(懒创建)：容器重父 QuickslotButton(创建序在技能槽按钮之前)，
---深度优先绘制序使整个迷你子树先于技能槽子树——与原生条重叠时原生条遮挡。
---宿主选择：KeybindBG/WeaponSwap 手柄下被原生永久隐藏(隐藏父级藏整个子树，
---实测坑：手柄模式整行消失)，QuickslotButton 两平台常显且创建序够早。
---槽位非交互(纯展示，同原生 back row)。子控件全部匿名：显式名字会进全局
---名字注册表，多槽重复创建必撞名(实测坑：CreateControl("Icon",...) 第二槽即撞)
---@type fun()
l.createRow = function()
  if l.container or l.createFailed then
    return
  end
  local ok, err = pcall(function()
    local host = (ZO_ActionBar1 and ZO_ActionBar1:GetNamedChild("QuickslotButton"))
      or (ZO_ActionBar1 and ZO_ActionBar1:GetNamedChild("WeaponSwap"))
      or GuiRoot
    l.container = WINDOW_MANAGER:CreateControl("ADRMiniBarRow", host, CT_CONTROL)
    l.slots = {}
    for slotNum = 3, 8 do
      local control = WINDOW_MANAGER:CreateControl("ADRMiniBarSlot" .. slotNum, l.container, CT_CONTROL)
      control:SetMouseEnabled(false)
      -- Icon：图标纹理(action 的 ability 图标；用户实物确认原生 back row 有图标)
      local icon = WINDOW_MANAGER:CreateControl(nil, control, CT_TEXTURE)
      icon:SetAnchor(TOPLEFT, control, TOPLEFT, 1, 1)
      icon:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, -1, -1)
      -- 填充条(原生 back row 特征：框顶 8px 状态条，remain/duration 填充，
      -- 施法条渐变色同原生 ZO_CAST_BAR_COLORS[BEGIN_CHARGE_UP]；
      -- 锚几何按原生 XML：Frame TL+4,+3 / TR-4,+3。
      -- 键盘原生即裸 StatusBar(无模板继承，dump 证实)——直接 CT_STATUSBAR；
      -- ZO_StatusBar 虚拟模板不存在(实测 Duplicate 报错)，手柄亮泽层舍弃)
      local nd = IsInGamepadPreferredMode() and MINI_DIMS.gamepad or MINI_DIMS.keyboard
      local fillBar = WINDOW_MANAGER:CreateControl(nil, control, CT_STATUSBAR)
      fillBar:SetAnchor(TOPLEFT, control, CENTER, -nd.w / 2 + 4, -nd.h / 2 + 3)
      fillBar:SetAnchor(TOPRIGHT, control, CENTER, nd.w / 2 - 4, -nd.h / 2 + 3)
      fillBar:SetHeight(8)
      fillBar:SetMinMax(0, 1)
      pcall(function()
        ZO_StatusBar_SetGradientColor(fillBar, ZO_CAST_BAR_COLORS[ZO_CAST_STATE_BEGIN_CHARGE_UP])
      end)
      -- 胶囊框：仅 Frame 边框层(图标之上，原生创建序)。BG(BLANK) 实测是
      -- 全幅盖板——盖上后连 Frame 边框都被盖没(用户实辨：所有边框消失)，
      -- 原生可见边框感来自已移除的 Overlay 暗纱边缘；故不使用 BG/Overlay。
      -- 方角艺术图标用内缩缓解(±3，微不可察)：个别图标四角戳出胶囊圆角
      local art = IsInGamepadPreferredMode() and "EsoUI/Art/ActionBar/Gamepad/gp_backrow_abilityFrame"
        or "EsoUI/Art/ActionBar/backrow_abilityFrame"
      local frame = WINDOW_MANAGER:CreateControl(nil, control, CT_TEXTURE)
      frame:SetTexture(art .. ".dds")
      frame:SetAnchor(CENTER, control, CENTER)
      frame:SetTextureCoords(unpack((IsInGamepadPreferredMode() and MINI_DIMS.gamepad or MINI_DIMS.keyboard).coords))
      -- 图标内缩：角部收进，减少方角戳出胶囊圆角
      icon:ClearAnchors()
      icon:SetAnchor(TOPLEFT, control, TOPLEFT, 3, 3)
      icon:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, -3, -3)
      l.slots[slotNum] =
        { control = control, icon = icon, fillBar = fillBar, frame = frame, iconPath = nil }
    end
  end)
  if not ok then
    d(string.format("[ADR] MiniBar row creation failed: %s", tostring(err)))
    l.createFailed = true
    l.slots = nil
    if l.container then
      pcall(function()
        l.container:SetHidden(true)
      end)
      l.container = nil
    end
    return
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
      -- 贴图层随平台重设(键盘/手柄切换；引用直取，子控件匿名)
      for _, layer in ipairs({ entry.frame }) do
        if layer then
          layer:SetDimensions(dims.w, dims.h)
        end
      end
      entry.frame:SetTexture(art .. ".dds")
      control:ClearAnchors()
      -- CENTER 锚：缩放围绕锚点仍居中对位(与原生 back row 同锚型)
      control:SetAnchor(CENTER, nativeButton.slot, CENTER, 0, slotNum == 8 and ultOffY or abilityOffY)
      control:SetScale(scale)
    end
  end
  l.syncAll()
end

--========================================
--        同步(引擎数据驱动)
--========================================
---全槽同步(Core action 数据源)：可见性(有计时 action) + 图标(action 的
---ability 图标，非槽位查询——天然免疫毁灭杖非激活条图标过期) + 数字。
---scale 也在心跳幂等重放(滑条免通知)。不可用(非武器热栏/Oakensoul/
---预设非 mini)时整行隐藏
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
  local scale = sv.barShowShiftScalePercent / 100
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
        entry.control:SetScale(scale)
        entry.control:SetHidden(false)
        -- 填充条：remain/duration(同原生 SetFillBar 语义；无时长置 0)
        local duration = action:getDuration()
        if entry.fillBar.SetValue then
          entry.fillBar:SetValue(duration > 0 and remain / duration or 0)
        end
      else
        entry.control:SetHidden(true)
      end
    end
  end
end

---心跳(Core 100ms)：数字倒数刷新 + 可见性/图标准时同步
---@type fun()
l.onCoreUpdate = function()
  if l.createFailed then
    return
  end
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
---位置/缩放/字体设置变化后重排(诊断/事件路径用；滑条免通知——
---scale 已在心跳幂等重放)
---@type fun()
m.relayout = function()
  l.relayout()
end

---诊断 dump(/adrbackbar 调用)：逐槽 action 匹配/剩余/图标/可见性 +
---原生 back row 设置状态(区分“多出的图标”来源)
---@type fun(): string
m.debugDump = function()
  local lines = {}
  local nativeBackRow = "?"
  if GetSetting_Bool then
    local ok, v = pcall(GetSetting_Bool, SETTING_TYPE_UI, UI_SETTING_SHOW_ACTION_BAR_BACK_ROW)
    nativeBackRow = (ok and v) and "ON" or "off"
  end
  lines[#lines + 1] = string.format("row=%s failed=%s hotbar=%s oakensoul=%s nativeBackRow=%s",
    tostring(l.container ~= nil), tostring(l.createFailed == true),
    tostring(l.inactiveHotbar()), tostring(l.hasOakensoul()), nativeBackRow)
  if l.slots then
    local now = GetGameTimeMilliseconds()
    local hotbar = l.inactiveHotbar()
    for slotNum = 3, 8 do
      local e = l.slots[slotNum]
      local action, remain = getSlotAction(slotNum, hotbar or HOTBAR_CATEGORY_BACKUP, now)
      local geo = "?"
      if e then
        local function g(c)
          if not c then
            return "--"
          end
          return string.format("%.0f,%.0f %.0fx%.0f %d/%d/%d a%.2f%s",
            c:GetLeft() or -1, c:GetTop() or -1,
            c:GetWidth() or -1, c:GetHeight() or -1,
            c:GetDrawLayer() or -1, c:GetDrawTier() or -1, c:GetDrawLevel() or -1,
            c:GetAlpha() or -1, c:IsControlHidden() and "[hid]" or "")
        end
        geo = string.format("ctl[%s] icon[%s] fill[%s] frm[%s]",
          g(e.control), g(e.icon), g(e.fillBar), g(e.frame))
      end
      lines[#lines + 1] = string.format("S%d act=%s remain=%s | %s",
        slotNum,
        action and (action.ability and action.ability.name or "?") or "nil",
        remain and string.format("%.1fs", remain / 1000) or "-",
        geo)
    end
  end
  return table.concat(lines, "\n")
end

--========================================
--        register
--========================================
addon.register("MiniBar#M", m)

---诊断命令：/adrmini 逐槽 action 匹配/剩余/图标/可见性 +
---原生 back row 设置状态(区分“多出的图标”来源)
SLASH_COMMANDS["/adrmini"] = function()
  d("[ADR Mini] " .. m.debugDump())
end

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

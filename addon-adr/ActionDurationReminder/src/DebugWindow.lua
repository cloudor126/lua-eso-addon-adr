--========================================
--        imports
--========================================
---@type adr.addon.M
local addon = ActionDurationReminder
---@type adr.settings.M
local settings = addon.load("Settings#M")
---@type adr.debug.M
local debug = addon.load("Debug#M")
local l = {}
---@type adr.debugwindow.M
local m = { l = l }

--========================================
--        types
--========================================
---DebugWindow模块公开表(addon.register("DebugWindow#M"))
---@class adr.debugwindow.M
---@field open? fun()
---@field close? fun()
---@field toggle? fun()

---扩展 adr.settings.SavedVars:本模块持久化字段,与下方 defaults 一一对应
---@class adr.settings.SavedVars
---@field debugWindowOffsetX? number
---@field debugWindowOffsetY? number
---@type adr.settings.SavedVars
local debugWindowSavedVarsDefaults = {
  debugWindowOffsetX = 0,
  debugWindowOffsetY = 0,
}

--========================================
--        l
--========================================
local WIDTH, HEIGHT = 720, 440

l.frame = nil
l.edit = nil
l.filterBox = nil
l.pauseBtn = nil
l.paused = false
l.lastVersion = -1
l.lastFilter = ""

---@type fun(): adr.settings.SavedVars
l.getSavedVars = function()
  return settings.getSavedVars()
end

---small clickable text button (no textures, backdrop + centered label)
---@param parent table
---@param buttonText string
---@param onClick fun()
---@return table
l.newButton = function(parent, buttonText, onClick)
  local btn = WINDOW_MANAGER:CreateControl(nil, parent, CT_CONTROL)
  btn:SetDimensions(96, 26)
  btn:SetMouseEnabled(true)
  local bd = WINDOW_MANAGER:CreateControl(nil, btn, CT_BACKDROP)
  bd:SetAnchor(TOPLEFT)
  bd:SetAnchor(BOTTOMRIGHT)
  bd:SetCenterColor(0.18, 0.18, 0.2, 0.9)
  bd:SetEdgeColor(0.45, 0.45, 0.5, 1)
  local label = WINDOW_MANAGER:CreateControl(nil, btn, CT_LABEL)
  label:SetFont("$(BOLD_FONT)|$(KB_15)|soft-shadow-thin")
  label:SetColor(1, 1, 1)
  label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
  label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
  label:SetAnchorFill()
  label:SetText(buttonText)
  btn.label = label
  btn:SetHandler("OnMouseEnter", function()
    bd:SetEdgeColor(0.9, 0.85, 0.3, 1)
  end)
  btn:SetHandler("OnMouseExit", function()
    bd:SetEdgeColor(0.45, 0.45, 0.5, 1)
  end)
  btn:SetHandler("OnMouseDown", function()
    onClick()
  end)
  return btn
end

---rebuild the log text area from the ring buffer, applying the substring filter
---@param force? boolean
l.refresh = function(force)
  if not l.edit then
    return
  end
  local filter = l.filterBox:GetText() or ""
  local version = debug.getLogVersion()
  if not force and version == l.lastVersion and filter == l.lastFilter then
    return
  end
  l.lastVersion = version
  l.lastFilter = filter
  local logs = debug.getLogs()
  local t = {}
  if filter == "" then
    for i = 1, #logs do
      t[#t + 1] = logs[i]
    end
  else
    local f = filter:lower()
    for i = 1, #logs do
      local line = logs[i]
      if line:lower():find(f, 1, true) then
        t[#t + 1] = line
      end
    end
  end
  if #t > 0 then
    l.edit:SetText(table.concat(t, "\n"))
  else
    l.edit:SetText(addon.text("No logs yet"))
  end
  -- keep the newest lines in view (scroll to bottom)
  l.edit:SetTopLineIndex(l.edit:GetScrollExtents() + 1)
end

--========================================
--        window
--========================================
l.build = function()
  if l.frame then
    return
  end
  local sv = l.getSavedVars()
  local frame = WINDOW_MANAGER:CreateTopLevelWindow("ADRDebugWindow")
  l.frame = frame
  frame:SetDimensions(WIDTH, HEIGHT)
  frame:SetMouseEnabled(true)
  frame:SetMovable(true)
  frame:SetDrawLayer(DL_OVERLAY)
  -- U51 lesson: never anchor a movable frame to a non-GuiRoot control
  frame:SetAnchor(CENTER, GuiRoot, CENTER, sv.debugWindowOffsetX, sv.debugWindowOffsetY)
  frame:SetHandler("OnMoveStop", function()
    local cx, cy = GuiRoot:GetCenter()
    local wcx, wcy = frame:GetCenter()
    sv.debugWindowOffsetX = zo_round(wcx - cx)
    sv.debugWindowOffsetY = zo_round(wcy - cy)
  end)
  -- window background
  local bd = WINDOW_MANAGER:CreateControl(nil, frame, CT_BACKDROP)
  bd:SetAnchor(TOPLEFT)
  bd:SetAnchor(BOTTOMRIGHT)
  bd:SetCenterColor(0.06, 0.06, 0.08, 0.96)
  bd:SetEdgeTexture("/esoui/art/chatwindow/chat_bg_edge.dds", 256, 256, 32)
  -- title
  local title = WINDOW_MANAGER:CreateControl(nil, frame, CT_LABEL)
  title:SetFont("$(BOLD_FONT)|$(KB_18)|soft-shadow-thin")
  title:SetColor(1, 1, 1)
  title:SetAnchor(TOPLEFT, frame, TOPLEFT, 14, 6)
  title:SetText(addon.text("ADR Debug Console"))
  -- close button
  local closeBtn = l.newButton(frame, "X", function()
    m.close()
  end)
  closeBtn:SetDimensions(26, 26)
  closeBtn:SetAnchor(TOPRIGHT, frame, TOPRIGHT, -8, 6)
  -- toolbar
  local bar = WINDOW_MANAGER:CreateControl(nil, frame, CT_CONTROL)
  bar:SetDimensions(WIDTH - 16, 28)
  bar:SetAnchor(TOPLEFT, frame, TOPLEFT, 8, 34)
  local filterLabel = WINDOW_MANAGER:CreateControl(nil, bar, CT_LABEL)
  filterLabel:SetFont("$(MEDIUM_FONT)|$(KB_16)")
  filterLabel:SetColor(0.8, 0.8, 0.8)
  filterLabel:SetAnchor(TOPLEFT, bar, TOPLEFT, 4, 5)
  filterLabel:SetText(addon.text("Filter"))
  local filterBd = WINDOW_MANAGER:CreateControl(nil, bar, CT_BACKDROP)
  filterBd:SetDimensions(240, 26)
  filterBd:SetAnchor(LEFT, filterLabel, RIGHT, 8, -3)
  filterBd:SetCenterColor(0.1, 0.1, 0.12, 0.9)
  filterBd:SetEdgeColor(0.45, 0.45, 0.5, 1)
  local fBox = WINDOW_MANAGER:CreateControlFromVirtual(nil, bar, "ZO_DefaultEdit")
  fBox:SetAnchor(TOPLEFT, filterBd, TOPLEFT, 6, -4)
  fBox:SetAnchor(BOTTOMRIGHT, filterBd, BOTTOMRIGHT, -6, 4)
  fBox:SetFont("$(MEDIUM_FONT)|$(KB_16)")
  fBox:SetMaxInputChars(120)
  fBox:SetColor(1, 1, 1)
  fBox:SetHandler("OnTextChanged", function()
    l.refresh(true)
  end)
  l.filterBox = fBox
  -- toolbar buttons (right aligned)
  l.copyBtn = l.newButton(bar, addon.text("Copy All"), function()
    l.refresh(true)
    l.edit:TakeFocus()
    l.edit:SelectAll()
  end)
  l.copyBtn:SetAnchor(TOPRIGHT, bar, TOPRIGHT, 0, 0)
  l.clearBtn = l.newButton(bar, addon.text("Clear"), function()
    debug.clearLogs()
    l.refresh(true)
  end)
  l.clearBtn:SetAnchor(TOPRIGHT, l.copyBtn, TOPLEFT, -8, 0)
  l.pauseBtn = l.newButton(bar, addon.text("Pause"), function()
    l.paused = not l.paused
    l.pauseBtn.label:SetText(l.paused and addon.text("Resume") or addon.text("Pause"))
    if not l.paused then
      l.refresh(true)
    end
  end)
  l.pauseBtn:SetAnchor(TOPRIGHT, l.clearBtn, TOPLEFT, -8, 0)
  -- log area: read-only multiline edit (selectable, Ctrl+A/Ctrl+C copy)
  local edit = WINDOW_MANAGER:CreateControlFromVirtual(nil, frame, "ZO_DefaultEditMultiLineForBackdrop")
  edit:SetAnchor(TOPLEFT, frame, TOPLEFT, 10, 66)
  edit:SetAnchor(BOTTOMRIGHT, frame, BOTTOMRIGHT, -10, -30)
  edit:SetMaxInputChars(500000)
  edit:SetEditEnabled(false)
  edit:SetFont("$(MEDIUM_FONT)|$(KB_15)")
  l.edit = edit
  -- bottom hint
  local hint = WINDOW_MANAGER:CreateControl(nil, frame, CT_LABEL)
  hint:SetFont("$(MEDIUM_FONT)|$(KB_14)")
  hint:SetColor(0.6, 0.6, 0.6)
  hint:SetAnchor(BOTTOMLEFT, frame, BOTTOMLEFT, 14, -6)
  hint:SetText(addon.text("Select text and press Ctrl+C to copy"))
  -- periodic auto refresh (skip while paused or while the user interacts with the boxes)
  local frameCount = 0
  frame:SetHandler("OnUpdate", function()
    frameCount = frameCount + 1
    if frameCount < 30 then
      return
    end
    frameCount = 0
    if l.paused then
      return
    end
    if l.edit:HasFocus() or l.filterBox:HasFocus() then
      return
    end
    l.refresh(false)
  end)
end

--========================================
--        m
--========================================
m.open = function()
  l.build()
  l.frame:SetHidden(false)
  l.refresh(true)
end

m.close = function()
  if l.frame then
    l.frame:SetHidden(true)
  end
end

m.toggle = function()
  if l.frame and not l.frame:IsControlHidden() then
    m.close()
  else
    m.open()
  end
end

--========================================
--        init
--========================================
addon.extend(settings.EXTKEY_ADD_DEFAULTS, function()
  settings.addDefaults(debugWindowSavedVarsDefaults)
end)

SLASH_COMMANDS["/adrlog"] = function()
  m.toggle()
end

--========================================
--        register
--========================================
addon.register("DebugWindow#M", m)

addon.register("DebugWindow", m)

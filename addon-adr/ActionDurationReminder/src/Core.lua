--========================================
--        vars
--========================================
---@type adr.addon.M
local addon = ActionDurationReminder
---@type adr.utils.M
local utils = addon.load("Utils#M")
---@type adr.settings.M
local settings = addon.load("Settings#M")
---@type adr.models.M
local models = addon.load("Models#M")
local l = {}
---@type adr.core.M
local m = { l = l }

--========================================
--        types
--========================================
---Core注入addon表的运行时字段(泄漏检测阈值与快捷接口)
---@class adr.addon.M
---@field actionLeakLogInterval? number
---@field actionLeakCntValve? number
---@field clearActions? fun()
---@field clear? fun()
---@field clearAreaActions? fun()
---@field getIdActionMap? fun(): table<number, adr.models.Action>
---@field getSnActionMap? fun(): table<number, adr.models.Action>
---@field getTimeActionMap? fun(): table<number, adr.models.Action>
---Debug模块注入的默认值
---@field debugDefaults? table

---Core模块公开表(addon.register("Core#M"))
---@class adr.core.M
---@field EXTKEY_UPDATE? string
---@field getActionByAbilityId? fun(abilityId: number): adr.models.Action?
---@field getActionByAbilityName? fun(abilityName: string, strict?: boolean): adr.models.Action?
---@field getActionBySlot? fun(hotbarCategory: number, slotNum: number): adr.models.Action?
---@field clearActions? fun()
---@field clearAreaActions? fun()
---@field getIdActionMap? fun(): table<number, adr.models.Action>
---@field getSnActionMap? fun(): table<number, adr.models.Action>
---@field getTimeActionMap? fun(): table<number, adr.models.Action>

---Power Lash引导状态缓存
---@class adr.core.PowerLashGuideState
---@field isDragonknight? boolean
---@field lastGuideType? string

local DS_ACTION = "action" -- debug switch for action
local DS_EFFECT = "effect" -- debug switch for effect
local DS_COMBAT = "combat" -- debug switch for combat events
local DS_TARGET = "target" -- debug switch for target
local DS_FILTER = "filter" -- debug switch for filter
-- /script for id, action in pairs(ActionDurationReminder.getIdActionMap()) do d(action:toLogString()) end

-- DSS (Debug Switch + SubSwitch) constants for addon.debugEnabled
-- Filter
local DSS_FILTER_ACCEPT = { DS_FILTER, "accept" }
local DSS_FILTER_REJECT = { DS_FILTER, "reject" }
-- Action
local DSS_ACTION_FIND = { DS_ACTION, "find" }
local DSS_ACTION_NEW = { DS_ACTION, "new" }
local DSS_ACTION_MATCH = { DS_ACTION, "match" }
local DSS_ACTION_UNREF = { DS_ACTION, "unref" }
local DSS_ACTION_STACK = { DS_ACTION, "stack" }
local DSS_ACTION_REMOVE = { DS_ACTION, "remove" }
local DSS_ACTION_DELETE = { DS_ACTION, "delete" }
local DSS_ACTION_SAVE = { DS_ACTION, "save" }
local DSS_ACTION_CLEAR = { DS_ACTION, "clear" }
-- Combat
local DSS_COMBAT_EVENT = { DS_COMBAT, "event" }
local DSS_COMBAT_FADE = { DS_COMBAT, "fade" }
local DSS_COMBAT_STACK = { DS_COMBAT, "stack" }
local DSS_COMBAT_TICK = { DS_COMBAT, "tick" }
local DSS_COMBAT_DURATION = { DS_COMBAT, "duration" }
local DSS_COMBAT_CHANNEL = { DS_COMBAT, "channel" }
-- Effect
local DSS_EFFECT_GAIN = { DS_EFFECT, "gain" }
local DSS_EFFECT_FADE = { DS_EFFECT, "fade" }
local DSS_EFFECT_UPDATE = { DS_EFFECT, "update" }
local DSS_EFFECT_REFRESH = { DS_EFFECT, "refresh" }
local DSS_EFFECT_TRANSFER = { DS_EFFECT, "transfer" }
local DSS_EFFECT_MISS = { DS_EFFECT, "miss" }
local DSS_EFFECT_MATCH = { DS_EFFECT, "match" }
-- Target
local DSS_TARGET_TRACK = { DS_TARGET, "track" }

---@type adr.settings.SavedVars
local coreSavedVarsDefaults = {
  coreMultipleTargetTracking = true,
  coreMultipleTargetTrackingWithoutClearing = true,
  coreSecondsBeforeFade = 5,
  coreMinimumDurationSeconds = 2.5,
  coreIgnoreLongDebuff = true,
  coreKeyWords = "",
  coreBlackKeyWords = "",
  coreClearAreaActionsOnCombatEnd = false,
}

local GetGameTimeMilliseconds = GetGameTimeMilliseconds

---@type fun(origin: string): string, integer
local fStripBracket = function(origin)
  return origin:gsub("^[^<]+<%s*([^>]+)%s*>.*$", "%1", 1)
end

--========================================
--        l
--========================================
---@type adr.models.Action[]
l.actionQueue = {}

---@type table<number, adr.models.Action>
l.idActionMap = {}

---@type table<number, number>
l.idDurationMap = {}

---@type table<number, boolean>
l.idFilteringMap = {}

l.gallopAction = nil -- Models#Action

l.lastAction = nil -- Models#Action

l.lastEffectAction = nil -- Models#Action

l.lastQuickslotTime = 0

l.ignoredCache = utils.newRecentCache(3000, 10)

---@type table<number, boolean>
l.ignoredIds = {}

---@type table<number, adr.models.Action>
l.snActionMap = {}

---@type table<number, adr.models.Action>
l.timeActionMap = {}

l.targetId = nil

---@type table<string, boolean>
l.cacheOfActionMatchingAction = {}

-- Power Lash Guide state
---@type adr.core.PowerLashGuideState
l.powerLashGuideState = {
  isDragonknight = nil, -- cached class check
  lastGuideType = nil, -- 'show' or 'hide', tracks last sent guide type
}

---@type fun(): number?, number?
l.findFlameLashSlot = function()
  for hotbarCategory = 0, 1 do
    for slotNum = 3, 8 do
      local texture = GetSlotTexture(slotNum, hotbarCategory)
      if texture and texture:find(models.FLAME_LASH_ICON_KEYWORD, 1, true) then
        return hotbarCategory, slotNum
      end
    end
  end
  return nil, nil
end

---@type fun(abilityId: number, abilityName: string): boolean
l.checkAbilityIdAndNameOk = function(abilityId, abilityName)
  local savedValue = l.idFilteringMap[abilityId]
  if savedValue ~= nil then
    return savedValue
  end

  -- check white list
  local keywords = l.getSavedVars().coreKeyWords:lower()
  local checked = false
  local checkOk = false
  for line in keywords:gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line and #line > 0 then
      local left, dur = line:match("^(.-)%s*=%s*(.-)$")
      if left then
        line = left
      end
      if not dur then
        checked = true
      end
      if line:match("^%d+$") then
        checkOk = tonumber(line) == abilityId
      else
        checkOk = zo_strformat("<<1>>", abilityName):lower():find(line, 1, true)
      end
      if checkOk then
        if addon.debugEnabled(DSS_FILTER_ACCEPT, abilityName) then
          addon.debug("[FA]%s", left)
        end
        if dur then
          if addon.debugEnabled(DSS_FILTER_ACCEPT, abilityName) then
            addon.debug("[FA=]%s=%s", left, dur)
          end
          dur = tonumber(dur)
          if dur then
            l.idDurationMap[abilityId] = dur * 1000
          end
        end
        break
      end
    end
  end
  if checked and not checkOk then
    l.idFilteringMap[abilityId] = false
    return false
  end
  -- check black list
  keywords = l.getSavedVars().coreBlackKeyWords:lower()
  for line in keywords:gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line and #line > 0 then
      local match = false
      if line:match("^%d+$") then
        local id = tonumber(line)
        match = id == abilityId
      else
        local name = zo_strformat("<<1>>", abilityName):lower()
        match = name:find(line, 1, true)
      end
      if match then
        l.idFilteringMap[abilityId] = false
        return false
      end
    end
  end
  --
  l.idFilteringMap[abilityId] = true
  return true
end

-- Register Core debug switches with the addon framework
addon.registerDebugSwitch(DS_ACTION, "Action Debug")
addon.registerDebugSubSwitch(DSS_ACTION_FIND, "Action Find [AF*]", "Log action finding operations")
addon.registerDebugSubSwitch(DSS_ACTION_NEW, "Action New [AN*]", "Log action creation")
addon.registerDebugSubSwitch(DSS_ACTION_MATCH, "Action Match [AM*]", "Log action matching operations")
addon.registerDebugSubSwitch(DSS_ACTION_UNREF, "Action Unref [AU]", "Log unref operations")
addon.registerDebugSubSwitch(DSS_ACTION_STACK, "Action Stack [AK*]", "Log stack count updates")
addon.registerDebugSubSwitch(DSS_ACTION_REMOVE, "Action Remove [AR*]", "Log action removals")
addon.registerDebugSubSwitch(DSS_ACTION_DELETE, "Action Delete [AD*]", "Log action deletions from maps")
addon.registerDebugSubSwitch(DSS_ACTION_SAVE, "Action Save [AS]", "Log when actions are saved")
addon.registerDebugSubSwitch(DSS_ACTION_CLEAR, "Action Clear [AC*]", "Log action clearing")

addon.registerDebugSwitch(DS_EFFECT, "Effect Debug")
addon.registerDebugSubSwitch(DSS_EFFECT_GAIN, "Effect Gain [E+]", "Log effect gained events")
addon.registerDebugSubSwitch(DSS_EFFECT_FADE, "Effect Fade [E-]", "Log effect faded events")
addon.registerDebugSubSwitch(DSS_EFFECT_UPDATE, "Effect Update [E=]", "Log effect updated events")
addon.registerDebugSubSwitch(DSS_EFFECT_REFRESH, "Effect Refresh [E*]", "Log effect refresh events")
addon.registerDebugSubSwitch(DSS_EFFECT_TRANSFER, "Effect Transfer [E/]", "Log effect transferred events")
addon.registerDebugSubSwitch(DSS_EFFECT_MISS, "Effect Miss [EM?]", "Log effect action not found")
addon.registerDebugSubSwitch(DSS_EFFECT_MATCH, "Effect Match [EM]", "Log effect matching operations")

addon.registerDebugSwitch(DS_COMBAT, "Combat Debug")
addon.registerDebugSubSwitch(DSS_COMBAT_EVENT, "Combat Event [CE]", "Log combat events")
addon.registerDebugSubSwitch(DSS_COMBAT_FADE, "Combat Fade [C-]", "Log combat fade/cancel")
addon.registerDebugSubSwitch(DSS_COMBAT_STACK, "Combat Stack [CS-]", "Log combat stack consumption")
addon.registerDebugSubSwitch(DSS_COMBAT_TICK, "Combat Tick [CT]", "Log tick effects")
addon.registerDebugSubSwitch(DSS_COMBAT_DURATION, "Combat Duration [CD]", "Log duration gained")
addon.registerDebugSubSwitch(DSS_COMBAT_CHANNEL, "Combat Channel [CC]", "Log channel duration")

addon.registerDebugSwitch(DS_FILTER, "Filter Debug")
addon.registerDebugSubSwitch(DSS_FILTER_ACCEPT, "Filter Accept [FA*]", "Log accepted effects/actions")
addon.registerDebugSubSwitch(DSS_FILTER_REJECT, "Filter Reject [FR*]", "Log rejected effects/actions")

addon.registerDebugSwitch(DS_TARGET, "Target Debug")
addon.registerDebugSubSwitch(DSS_TARGET_TRACK, "Target Track [TT]", "Log target tracking changes")

-- Register Core debug options for the settings menu

---@type fun(effect: adr.models.Effect, stacking?: boolean): adr.models.Action?, boolean?
l.findActionByNewEffect = function(effect, stacking)
  -- 0. cache to avoid repeated matching
  ---@type table<number, boolean>
  local notMatched = {}
  -- try last performed action
  if l.lastAction and l.lastAction.flags.forGround then
    if not notMatched[l.lastAction.sn] and l.lastAction:matchesNewEffect(effect) then
      if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
        addon.debug(
          "[AFA]found last action by new match:%s@%.2f",
          l.lastAction.ability.name,
          l.lastAction.startTime / 1000
        )
      end
      return l.lastAction
    end
    notMatched[l.lastAction.sn] = true
  end
  -- try last effect action
  if l.lastEffectAction and l.lastEffectAction.lastEffectTime + 50 > effect.startTime then
    if not notMatched[l.lastEffectAction.sn] and l.lastEffectAction.ability:matches(effect.ability, false) then
      if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
        addon.debug(
          "[AFA]found last effect action by new match:%s@%.2f",
          l.lastEffectAction.ability.name,
          l.lastEffectAction.startTime / 1000
        )
      end
      return l.lastEffectAction
    end
    notMatched[l.lastEffectAction.sn] = true
  end
  -- try performed actions
  for i = 1, #l.actionQueue do
    local action = l.actionQueue[i] --Models#Action
    if not notMatched[action.sn] and action:matchesNewEffect(effect) then
      if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
        addon.debug("[AFA]found one of queue by new match:%s", action:toLogString())
      end
      return action
    end
    notMatched[action.sn] = true
    if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
      addon.debug("[AFX]not found one of queue by new match:%s", action:toLogString())
    end
  end
  -- try saved actions
  for key, var in pairs(l.idActionMap) do
    local action = var --Models#Action
    if not notMatched[action.sn] and action:matchesNewEffect(effect) then
      if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
        addon.debug("[AFA]found one of saved by new match:%s@%.2f", action.ability.name, action.startTime / 1000)
      end
      return action
    end
    notMatched[action.sn] = true
    if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
      addon.debug("[AFX]not found one of saved by new match:%s@%.2f", action.ability.name, action.startTime / 1000)
    end
  end
  -- try slotted actions for non minor buff effects
  if not effect.ability.icon:find("ability_buff_mi", 1, true) then
    local action = l.findBarActionByNewEffect(effect, stacking)
    if action then
      return action
    end
  end
  -- not found
  if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
    addon.debug(
      "[AF?]not found new match in %i actions, lastAction: %s, lastEffectAction: %s",
      #l.actionQueue,
      l.lastAction and l.lastAction.ability.name or "nil",
      l.lastEffectAction and l.lastEffectAction.ability.name or "nil"
    )
  end
  return nil
end

---@type fun(effect: adr.models.Effect, appending?: boolean): adr.models.Action?, boolean?
l.findActionByOldEffect = function(effect, appending)
  -- 1. find that existed
  for i = 1, #l.actionQueue do
    ---@type adr.models.Action? getNewest可能返回nil(仅作真值/字段访问)
    local action = l.actionQueue[i]
    if action:matchesOldEffect(effect) then
      if action.newAction then
        action = action:getNewest()
      end
      if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
        addon.debug("[AFA]found one of queue by old match:%s@%.2f", action.ability.name, action.startTime / 1000)
      end
      return action
    end
  end
  for key, action in pairs(l.idActionMap) do
    if action:matchesOldEffect(effect) then
      if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
        addon.debug("[AFA]found one of saved by old match:%s@%.2f", action.ability.name, action.startTime / 1000)
      end
      return action
    end
  end
  -- 2. appending
  if appending then
    for i = 1, #l.actionQueue do
      local action = l.actionQueue[i]
      if action:matchesNewEffect(effect) then
        if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
          addon.debug("[AFA]found one of queue by new match:%s@%.2f", action.ability.name, action.startTime / 1000)
        end
        return action, true
      end
    end
  end
  if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
    addon.debug(
      "[AF?]not found old match in %i actions, last:%s",
      #l.actionQueue,
      l.lastAction and l.lastAction.ability.name or "nil"
    )
  end
  return nil
end

---@type fun(tickEffectId: number, unitId: number): adr.models.Action?
l.findActionByTick = function(tickEffectId, unitId)
  for key, action in pairs(l.idActionMap) do
    if action.tickEffect and action.tickEffect.ability.id == tickEffectId and action.tickEffect.unitId == unitId then
      if addon.debugEnabled(DSS_ACTION_FIND, action.ability.name) then
        addon.debug("[AFA]found action by tickEffectId:%s@%.2f", action.ability.name, action.startTime / 1000)
      end
      return action
    end
  end
  return nil
end

---@type fun(effect: adr.models.Effect, stacking?: boolean): adr.models.Action?
l.findBarActionByNewEffect = function(effect, stacking)
  -- Special handling for Power Lash Guide effect
  if effect.ability.id == models.POWER_LASH_GUIDE_ABILITY_ID then
    local hotbarCategory, slotNum = l.findFlameLashSlot()
    if hotbarCategory then
      local action = models.newAction(slotNum, hotbarCategory)
      action.ability.id = models.POWER_LASH_GUIDE_ABILITY_ID
      action.ability.name = "Power Lash Guide"
      action.ability.showName = "Power Lash Guide"
      action.ability.icon = "/esoui/art/icons/ability_dragonknight_001_b.dds"
      action.duration = 0
      action.descriptionDuration = 0
      action.endTime = 0
      if addon.debugEnabled(DSS_ACTION_FIND, "PowerLashGuide") then
        addon.debug("[AFA]found Flame Lash slot for Power Lash Guide")
      end
      return action
    end
    return nil
  end
  -- check if it's a major buff/debuff, e.g. avoid abuse of Major Expedition or Off Balance
  if effect.ability.icon:find("ability_buff_ma", 1, true) then
    return nil
  end
  if effect.ability.icon:find("ability_debuff_offb", 1, true) then
    return nil
  end
  if effect.ability.icon:find("ability_rogue_030", 1, true) then
    return nil
  end -- poison
  -- check if it's a potion effect
  if effect.startTime - l.lastQuickslotTime < 100 then
    return nil
  end
  -- check if it's a one word name effect e.g. burning, chilling, concussion
  -- or we are using chinese lang
  local isZh = GetCVar("language.2") == "zh"
  local checkDescription = effect.ability.name:find(" ", 1, true) or isZh
  checkDescription = checkDescription and (stacking or effect.duration >= 5000)
  --
  local matchSlotNum = nil
  local matchHotbarCategory = nil
  local currentHotbarCategory = GetActiveHotbarCategory()
  local indices = { currentHotbarCategory, HOTBAR_CATEGORY_PRIMARY, HOTBAR_CATEGORY_BACKUP }
  for i = 1, 3 do
    local hotbarCategory = indices[i]
    for slotNum = 3, 8 do
      local slotBoundId = GetSlotBoundId(slotNum, hotbarCategory)
      if GetSlotType(slotNum, hotbarCategory) == ACTION_TYPE_CRAFTED_ABILITY then
        slotBoundId = GetAbilityIdForCraftedAbilityId(slotBoundId)
      end
      local slotIcon = GetSlotTexture(slotNum, hotbarCategory)
      if slotBoundId > 0 then
        local slotName = fStripBracket(zo_strformat("<<1>>", GetSlotName(slotNum, hotbarCategory)))
        slotName = models.patchAbilityName(slotName)
        if
          (effect.ability.name == slotName)
          or checkDescription
            and zo_strformat("<<1>>", GetAbilityDescription(slotBoundId)):find(effect.ability.name, 1, true)
        then
          matchSlotNum = slotNum
          matchHotbarCategory = hotbarCategory
          break
        end
      end
    end
  end
  if matchSlotNum then
    local action = models.newAction(matchSlotNum, matchHotbarCategory)
    action.fake = true
    if addon.debugEnabled(DSS_ACTION_FIND, action.ability.name) then
      addon.debug("[AFA]found one by bar match:%s@%.2f", action.ability.name, action.startTime / 1000)
    end
    return action
  end
  if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
    addon.debug("[AF?]not found in bar actions")
  end
  return nil
end

---@type fun(): adr.settings.SavedVars
l.getSavedVars = function()
  return settings.getSavedVars()
end

---@type fun()
l.ensureCruxActions = function()
  -- Find all crux-consuming slots on the bar and ensure actions exist
  local currentHotbarCategory = GetActiveHotbarCategory()
  local indices = { currentHotbarCategory, HOTBAR_CATEGORY_PRIMARY, HOTBAR_CATEGORY_BACKUP }
  for i = 1, 3 do
    local hotbarCategory = indices[i]
    for slotNum = 3, 8 do
      local slotIcon = GetSlotTexture(slotNum, hotbarCategory)
      -- Check if this slot can consume crux (arcanist_002 or arcanist_003_b icon)
      if slotIcon:find("arcanist_002", 18, true) or slotIcon:find("arcanist_003_b", 18, true) then
        -- Check if action already exists for this slot
        local action = l.getActionBySlot(hotbarCategory, slotNum)
        if not action then
          -- Create and save a new action for this slot
          action = models.newAction(slotNum, hotbarCategory)
          action.fake = true
          l.saveAction(action)
          if addon.debugEnabled(DSS_ACTION_NEW, action.ability.name) then
            addon.debug("[AN+]created crux action:%s@%.2f", action.ability.name, action.startTime / 1000)
          end
        end
      end
    end
  end
end

---@type fun()
l.ensureNothingWastedActions = function()
  -- Find all Nothing Wasted displaying slots on the bar and ensure actions exist
  local currentHotbarCategory = GetActiveHotbarCategory()
  local indices = { currentHotbarCategory, HOTBAR_CATEGORY_PRIMARY, HOTBAR_CATEGORY_BACKUP }
  for i = 1, 3 do
    local hotbarCategory = indices[i]
    for slotNum = 3, 8 do
      local slotIcon = GetSlotTexture(slotNum, hotbarCategory)
      -- Check if this slot displays Nothing Wasted (necromancer_005 icon)
      if slotIcon:find("necromancer_005", 18, true) then
        local action = l.getActionBySlot(hotbarCategory, slotNum)
        if not action then
          action = models.newAction(slotNum, hotbarCategory)
          action.fake = true
          l.saveAction(action)
          if addon.debugEnabled(DSS_ACTION_NEW, action.ability.name) then
            addon.debug("[AN+]created Nothing Wasted action:%s@%.2f", action.ability.name, action.startTime / 1000)
          end
        end
      end
    end
  end
end

---@type fun(abilityId: number): adr.models.Action?
l.getActionByAbilityId = function(abilityId)
  local action = l.idActionMap[abilityId]
  if action then
    return action
  end
  for key, var in pairs(l.idActionMap) do
    if var:matchesAbilityId(abilityId) then
      return var
    end
  end
  return nil
end

---@type fun(abilityName: string, strict?: boolean): adr.models.Action?
l.getActionByAbilityName = function(abilityName, strict)
  for id, action in pairs(l.idActionMap) do
    if action:matchesAbilityName(abilityName) then
      return action
    end
  end
  return nil
end

---@type fun(action: adr.models.Action): adr.models.Action?
l.getActionByNewAction = function(action)
  local abilityName = action.ability.name
  local matcher = function(a)
    if a:getDuration() > 0 and a:getEndTime(false) < action.startTime then
      return false
    end
    if a.ability.id == action.ability.id then
      return true
    end
    -- check cache for non-trivial matches
    local cacheKey = a.ability.id .. "/" .. action.ability.id
    if l.cacheOfActionMatchingAction[cacheKey] then
      return true
    end
    local reverseKey = action.ability.id .. "/" .. a.ability.id
    -- i.e. Merciless Resolve name can match Assissin's Will action by its related ability list
    for key, var in ipairs(a.relatedAbilityList) do
      if abilityName:find(var.name, 1, true) then
        l.cacheOfActionMatchingAction[cacheKey] = true
        l.cacheOfActionMatchingAction[reverseKey] = true
        return true
      end
    end
    if abilityName:find(a.ability.name, 1, true) then
      l.cacheOfActionMatchingAction[cacheKey] = true
      l.cacheOfActionMatchingAction[reverseKey] = true
      return true
    end
    -- i.e. Assassin's Will name can match Merciless Resolve action by slot
    if
      action.hotbarCategory == a.hotbarCategory
      and action.slotNum == a.slotNum
      and a.inCombat
      and action.inCombat -- only match if both in combat (auto-swap)
    then
      l.cacheOfActionMatchingAction[cacheKey] = true
      l.cacheOfActionMatchingAction[reverseKey] = true
      return true
    end
    return false
  end

  for id, a in pairs(l.idActionMap) do
    if matcher(a) then
      if a.flags.forArea and action.flags.forEnemy then
        -- fix the flags changed from area to enemy
        action.flags.forArea = true
        action.flags.forEnemy = false
      end
      -- also replace flags, i.e. Assassin Will targets enemy but previous Grim Focus targets self
      if not a.flags.forEnemy and action.flags.forEnemy then
        action.flags = a.flags
      end

      -- this a kind of mutable skill for target i.e. werewolf Brutal Pounce <-> Brutal Carnage
      if a.ability.id ~= action.ability.id then
        return a
      end
      -- don't replace enemy actions excluding fake, so that they can be traced seperately
      if action.flags.forEnemy and not a.fake then
        -- except this action only have player effects i.e. Shrouded Dagger
        local playerOnly = true
        for key, var in ipairs(a.effectList) do
          if var.unitTag ~= "player" then
            playerOnly = false
          end
        end
        if playerOnly then
          return a
        end
        return nil
      end
      return a
    end
  end
  return nil
end

---@type fun(hotbarCategory: number, slotNum: number): adr.models.Action?
l.getActionBySlot = function(hotbarCategory, slotNum)
  for key, var in pairs(l.idActionMap) do
    if var.hotbarCategory == hotbarCategory and var.slotNum == slotNum then
      return var
    end
  end
  return nil
end

---@type fun(eventCode: number, slotNum: number)
l.onActionSlotAbilityUsed = function(eventCode, slotNum)
  -- 1. filter other actions
  if slotNum < 3 or slotNum > 8 then
    return
  end
  -- 2. create action
  local hotbar = GetActiveHotbarCategory()
  local action = models.newAction(slotNum, hotbar)
  if addon.debugEnabled(DSS_ACTION_NEW, action.ability.name) then
    addon.debug("[AN]%s", action:toLogString())
  end
  zo_callLater(function()
    action.ability.icon = GetSlotTexture(slotNum, hotbar)
  end, 500)
  if
    action.ability.icon:find("_curse", 1, true) -- daedric curse, haunting curse, daedric prey
    or action.ability.icon:find("dark_haze", 1, true) -- rune cage
    or action.ability.icon:find("dark_fog", 1, true) -- rune prison
  then
    action.flags.onlyOneTarget = true
  end
  -- 3. filter by keywords
  if not l.checkAbilityIdAndNameOk(action.ability.id, action.ability.name) then
    if addon.debugEnabled(DSS_ACTION_NEW, action.ability.name) then
      addon.debug("[AN-]filtered by keywords")
    end
    return
  end

  if l.idDurationMap[action.ability.id] then
    action.configDuration = l.idDurationMap[action.ability.id]
    action.endTime = action.startTime + action.configDuration
    if addon.debugEnabled(DSS_ACTION_NEW, action.ability.name) then
      addon.debug("[AN=]modified to %d, %s", action.configDuration, action:toLogString())
    end
  end
  -- 4. queue it
  l.queueAction(action)
  -- 5. replace saved
  if not action.flags.forGround then -- ground and channel action should not inherit old action effects
    ---@type adr.models.Action?
    ---@type adr.models.Action?
    local sameNameAction = l.getActionByNewAction(action)

    if not sameNameAction then
      if addon.debugEnabled(DSS_ACTION_MATCH, action.ability.name) then
        addon.debug("[AM-]none")
      end
    elseif sameNameAction.saved then
      sameNameAction = sameNameAction:getNewest()
      if addon.debugEnabled(DSS_ACTION_MATCH, sameNameAction.ability.name) then
        addon.debug("[AMA]%s", sameNameAction:toLogString())
      end
      sameNameAction.newAction = action
      action.effectList = {}
      for key, var in ipairs(sameNameAction.effectList) do
        if var.endTime > action.startTime + 500 then
          var.ignored = false
          table.insert(action.effectList, var)
        end
      end
      sameNameAction.effectList = {}
      action.lastEffectTime = sameNameAction.lastEffectTime
      action.stackEffect = sameNameAction.stackEffect
      action.stackEffect2 = sameNameAction.stackEffect2
      action.tickEffect = sameNameAction.tickEffect
      sameNameAction.stackEffect = nil
      action.oldAction = sameNameAction

      -- inherit fake property from ancestor to parent
      if sameNameAction.oldAction and sameNameAction.oldAction.fake then
        sameNameAction.fake = true
      end

      -- inherit duration
      if action.duration == 0 and sameNameAction.duration > 0 then
        action.inheritDuration = sameNameAction.duration
      elseif action.duration == 0 and sameNameAction.inheritDuration > 0 then
        action.inheritDuration = sameNameAction.inheritDuration
      elseif action.duration == 0 and sameNameAction.descriptionDuration and sameNameAction.descriptionDuration > 0 then
        action.inheritDuration = sameNameAction.descriptionDuration
      end
      local abilityAccepter = function(relatedAbility)
        if not action.ability.name:find(relatedAbility.name, 1, true) then
          table.insert(action.relatedAbilityList, relatedAbility)
          if addon.debugEnabled(DSS_ACTION_MATCH, action.ability.name) then
            addon.debug("[AMI] relating %s, total:%d", relatedAbility:toLogString(), #action.relatedAbilityList)
          end
        end
      end
      abilityAccepter(sameNameAction.ability)
      for key, var in ipairs(sameNameAction.relatedAbilityList) do
        abilityAccepter(var)
      end
      -- inherit effect matching cache from old action id to new action id
      if sameNameAction.ability.id ~= action.ability.id then
        local oldId = sameNameAction.ability.id
        local newId = action.ability.id
        local oldPrefix = oldId .. "/"
        local newPrefix = newId .. "/"
        for cacheKey, value in pairs(models.cacheOfActionMatchingEffect) do
          if cacheKey:find(oldPrefix, 1, true) == 1 then
            local newCacheKey = newPrefix .. cacheKey:sub(#oldPrefix + 1)
            models.cacheOfActionMatchingEffect[newCacheKey] = value
          end
        end
      end
      l.removeAction(sameNameAction) -- clear from registries
      l.saveAction(action)
    end
  end
  -- 6. save
  if
    not action.flags.forGround -- i.e. Scalding Rune ground action should not show the timer without effect
    and (
      (
        action.descriptionDuration
        and action.descriptionDuration < 3000
        and action.descriptionDuration > l.getSavedVars().coreMinimumDurationSeconds * 1000
      ) or (action.configDuration and action.configDuration > 0)
    )
  then
    -- 6.x save short without effects
    l.saveAction(action)
  end
end

---@type fun(eventCode: number)
l.onActionUpdateCooldowns = function(eventCode)
  local remain, duration = GetSlotCooldownInfo(GetCurrentQuickslot(), HOTBAR_CATEGORY_QUICKSLOT_WHEEL)
  if remain > 1000 and duration > 1000 and duration - remain < 100 then
    l.lastQuickslotTime = GetGameTimeMilliseconds()
  end
end

local flags = {}
---@type fun(eventCode: number, result: number, isError: boolean, abilityName: string, abilityGraphic: number, abilityActionSlotType: number, sourceName: string, sourceType: number, targetName: string, targetType: number, hitValue: number, powerType: number, damageType: number, log: boolean, sourceUnitId: number, targetUnitId: number, abilityId: number, overflow: number)
l.onCombatEvent = function(
  eventCode,
  result,
  isError,
  abilityName,
  abilityGraphic,
  abilityActionSlotType,
  sourceName,
  sourceType,
  targetName,
  targetType,
  hitValue,
  powerType,
  damageType,
  log,
  sourceUnitId,
  targetUnitId,
  abilityId,
  overflow
)
  local now = GetGameTimeMilliseconds()
  abilityName = zo_strformat("<<1>>", abilityName)
  abilityName = models.patchAbilityName(abilityName)
  local abilityIcon = GetAbilityIcon(abilityId)
  if addon.debugEnabled(DSS_COMBAT_EVENT, abilityName) then
    addon.debug(
      "[CE]|t24:24:%s|t%s(%s)@%.2f[%s]source:%s(%i:%i)target:%s(%i:%i)slot:%d,dmg:%d,overflow:%d,result:%d,power:%d,hit:%d",
      abilityIcon,
      abilityName,
      abilityId,
      now / 1000,
      abilityGraphic,
      sourceName,
      sourceType,
      sourceUnitId,
      targetName,
      targetType,
      targetUnitId,
      abilityActionSlotType,
      damageType,
      overflow,
      result,
      powerType,
      hitValue
    )
  end
  -- ACTION_RESULT_EFFECT_GAINED 2240
  -- ACTION_RESULT_EFFECT_GAINED_DURATION  2245
  -- 2240? TODO GetAbilityFrequencyMS
  if result == ACTION_RESULT_DIED_XP then --2262
    local _ = nil
    for key, var in pairs(l.idActionMap) do
      var:purgeEffectByTargetUnitId(targetUnitId)
    end
  end
  if result == ACTION_RESULT_EFFECT_FADED and abilityName ~= "" then --2250
    local ability = models.newAbility(abilityId, abilityName, abilityIcon)
    if addon.debugEnabled(DSS_COMBAT_FADE, abilityName) then
      addon.debug(
        "[C-]EFFECT_FADED,%s,target:%s(%d),source:%s(%d)",
        ability:toLogString(),
        targetName,
        targetUnitId,
        sourceName,
        sourceUnitId
      )
    end
    ---@type adr.models.Action?
    local action = l.idActionMap[abilityId]
    if action and action.channelUnitId == targetUnitId then
      if addon.debugEnabled(DSS_COMBAT_FADE, action.ability.name) then
        addon.debug("[C-c]cancel channeling %s", action:toLogString())
      end
      action.channelEndTime = now
      if #action.effectList == 0 then
        action.endTime = now
      end
    end
    for key, var in pairs(l.idActionMap) do
      local effect = nil
      if var.stackEffect2 and var.stackEffect2.combatEventId == abilityId then
        effect = var.stackEffect2
      elseif var.stackEffect and var.stackEffect.combatEventId == abilityId then
        effect = var.stackEffect
      end
      if effect ~= nil then
        action = var
        if l.isRecentCombatGrant(effect, now) then
          -- fade of the old buff instance right after a re-grant (re-cast replacement):
          -- keep the freshly granted stack
          if addon.debugEnabled(DSS_COMBAT_FADE, action.ability.name) then
            addon.debug("[CSf]ignored fade right after re-grant %s", action:toLogString())
          end
        else
          if addon.debugEnabled(DSS_COMBAT_FADE, action.ability.name) then
            addon.debug("[C-s]cancel stack %s", action:toLogString())
          end
          local oldEffect = action:purgeEffect(effect)
          if oldEffect then
            l.timeActionMap[oldEffect.startTime] = nil
          end
        end
      end
    end
    action = l.findActionByTick(abilityId, targetUnitId)
    if action and action.duration == 0 then
      if addon.debugEnabled(DSS_COMBAT_FADE, action.ability.name) then
        addon.debug("[C-t]cancel tick %s", action:toLogString())
      end
      l.removeAction(action)
    end
  end
end

-- Combat-event-driven stack consumption: proc damage abilityId -> stack buff abilityId.
-- Crystal Weapon family — "Encase your weapon in dark crystals for 6 seconds, causing your
-- next 3 Light or Heavy Attacks to deal additional damage and reduce the target's Armor by
-- 1000 for 5 seconds.":
--   46331  the 6s crystal buff holding 3 stacks (granted via EFFECT_GAINED with hitValue=count)
--   143804 proc damage of the empowered attack (first hit)
--   181056 proc damage of the empowered attack (subsequent hits)
--   143808 5s armor reduction debuff applied to the target per hit (see Models' TAIL_EFFECT_ABILITY_IDS)
l.stackConsumptionMap = {
  [143804] = 46331,
  [181056] = 46331,
}

-- reverse lookup: stack buff abilityIds whose stacks are consumed one by one
l.stackConsumptionBuffIds = {}
for _, buffId in pairs(l.stackConsumptionMap) do
  l.stackConsumptionBuffIds[buffId] = true
end

--- Whether the stack effect was granted via combat event within the last second: the fade
--- of an old buff instance (arrives right after a re-grant when re-casting) must not
--- purge the freshly granted stack
---@type fun(stackEffect: adr.models.Effect?, now: number): boolean
l.isRecentCombatGrant = function(stackEffect, now)
  return stackEffect ~= nil and stackEffect.combatGrantTime ~= nil and now - stackEffect.combatGrantTime < 1000
end

---@type fun(eventCode: number, result: number, isError: boolean, abilityName: string, abilityGraphic: number, abilityActionSlotType: number, sourceName: string, sourceType: number, targetName: string, targetType: number, hitValue: number, powerType: number, damageType: number, log: boolean, sourceUnitId: number, targetUnitId: number, abilityId: number, overflow: number)
l.onCombatEventFromPlayer = function(
  eventCode,
  result,
  isError,
  abilityName,
  abilityGraphic,
  abilityActionSlotType,
  sourceName,
  sourceType,
  targetName,
  targetType,
  hitValue,
  powerType,
  damageType,
  log,
  sourceUnitId,
  targetUnitId,
  abilityId,
  overflow
)
  --
  abilityName = zo_strformat("<<1>>", abilityName)
  abilityName = models.patchAbilityName(abilityName)
  local now = GetGameTimeMilliseconds()

  if
    result ~= ACTION_RESULT_EFFECT_GAINED
    and result ~= ACTION_RESULT_EFFECT_GAINED_DURATION
    and result ~= ACTION_RESULT_DAMAGE
    and result ~= ACTION_RESULT_CRITICAL_DAMAGE
  then
    return
  end

  -- filter by keywords
  if not l.checkAbilityIdAndNameOk(abilityId, abilityName) then
    return
  end

  -- handle stackCount2 consumption for triggered bonus stacks (e.g. Stone Giant, Flame Lash)
  if result == ACTION_RESULT_DAMAGE or result == ACTION_RESULT_CRITICAL_DAMAGE then
    for key, action in pairs(l.idActionMap) do
      local stackEffect2 = action:getStackEffect2()
      if
        stackEffect2
        and stackEffect2.stackCount
        and stackEffect2.stackCount > 0
        and stackEffect2.ability.id == abilityId
      then
        stackEffect2.stackCount = stackEffect2.stackCount - 1
        if addon.debugEnabled(DSS_COMBAT_STACK, action.ability.name) then
          addon.debug("[CS-]consumed %s:%d", action.ability.name, stackEffect2.stackCount)
        end
      end
    end
    -- unified stackEffect consumption: keyed by ability identity via l.stackConsumptionMap,
    -- not by stack count (count is dynamic and unreliable for classification)
    local stackAbilityId = l.stackConsumptionMap[abilityId]
    if stackAbilityId then
      for key, action in pairs(l.idActionMap) do
        local stackEffect = action.stackEffect
        if
          stackEffect
          and stackEffect.combatEventId == stackAbilityId
          and stackEffect.stackCount
          and stackEffect.stackCount > 0
        then
          stackEffect.stackCount = stackEffect.stackCount - 1
          action.stackCountMatch = stackEffect.stackCount >= 3 and action.descriptionNums[stackEffect.stackCount]
          if addon.debugEnabled(DSS_COMBAT_STACK, action.ability.name) then
            addon.debug("[CS-]consumed %s:%d", action.ability.name, stackEffect.stackCount)
          end
          if stackEffect.stackCount == 0 then
            -- all stacks consumed: drop the stack effect and clear the slot with nothing left
            action.stackEffect = nil
            action:recalcEffectLevels()
            local hasLiveEffect = false
            for _, e in ipairs(action.effectList) do
              if not e.ignored and e.endTime > now then
                hasLiveEffect = true
                break
              end
            end
            if hasLiveEffect then
              action.endTime = now
            else
              l.removeAction(action)
            end
          end
        end
      end
    end
  end

  -- pick effect with tick rate
  if result == ACTION_RESULT_EFFECT_GAINED and sourceType == targetType and sourceUnitId == targetUnitId then
    local tickRate = GetAbilityFrequencyMS(abilityId)
    if tickRate > l.getSavedVars().coreMinimumDurationSeconds * 1000 then
      local ability = models.newAbility(abilityId, abilityName, GetAbilityIcon(abilityId))
      local effect = models.newEffect(ability, "player", sourceUnitId, now, now, 0, tickRate)
      if addon.debugEnabled(DSS_COMBAT_TICK, effect.ability.name) then
        addon.debug("[CT]%s", effect:toLogString())
      end
      local action = l.findActionByNewEffect(effect) -- Models#Action
      if action then
        action:saveEffect(effect)
        l.saveAction(action)
        return
      end
    end
    -- for not saved actions, i.e. Extended Ritual
    for key, action in pairs(l.actionQueue) do
      local abilityOnBar = models.newAbility(
        GetSlotBoundId(action.slotNum, action.hotbarCategory),
        models.patchAbilityName(GetSlotName(action.slotNum, action.hotbarCategory)),
        GetSlotTexture(action.slotNum, action.hotbarCategory)
      )
      if
        action.ability.id == abilityId
        or action.ability.name == abilityName
        or abilityOnBar.id == abilityId
        or abilityOnBar.name == abilityName
      then
        local ability = models.newAbility(abilityId, abilityName, GetAbilityIcon(abilityId))
        -- cache action matching when abilityOnBar differs from action.ability
        if abilityOnBar.id ~= action.ability.id then
          l.cacheOfActionMatchingAction[abilityOnBar.id .. "/" .. action.ability.id] = true
          l.cacheOfActionMatchingAction[action.ability.id .. "/" .. abilityOnBar.id] = true
        end
        if addon.debugEnabled(DSS_COMBAT_STACK, abilityName) then
          addon.debug("[CS] hit:%d for %s", hitValue, action:toLogString())
        end
        local duration = action.duration
        -- 为那些ground或者area的 action补上效果
        if
          not action.saved
          and duration > l.getSavedVars().coreMinimumDurationSeconds * 1000
          and ((action.flags.forArea and now - action.startTime < 2000) or action.flags.forGround)
        then
          -- keep the original placement time before resetting startTime: the '@' activated
          -- marker measures the trigger delay from placement, not from the reset moment
          -- (e.g. Barbed Trap arms in 1.5s and triggers inside the forArea reset window)
          if not action.placementTime then
            action.placementTime = action.startTime
          end
          action.startTime = now
          action.endTime = now + duration
          if action.flags.forGround then
            -- record this to mark next effect as activated one
            action.groundFirstEffectId = -1
          end
          l.saveAction(action)
          return
          --
        elseif
          hitValue > 1
            -- 递增
            and (hitValue == (action.stackEffect and action.stackEffect.stackCount or 0) + 1)
          -- check if hitValue matches a descriptionNum (triggered bonus stacks)
          or (action.descriptionNums and action.descriptionNums[hitValue])
        then
          local effect = models.newEffect(abilityOnBar, "player", sourceUnitId, now, now, hitValue, 0)
          effect.combatEventId = abilityId
          if action:updateStackInfo(hitValue, effect) then
            -- stamp the grant time so the following fade of the OLD buff instance
            -- (re-cast replacement) can be distinguished from a real expiry fade in [C-s]
            effect.combatGrantTime = now
          end
          -- consumable stacks only count down: suppress the description-match caret (^)
          if l.stackConsumptionBuffIds[abilityId] then
            action.stackCountMatch = false
          end
          l.saveAction(action)
        end
      end
    end
  end
  -- justify recorded actions
  if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
    local _ = nil
    local ability = nil -- Models#Ability
    if addon.debugEnabled(DSS_COMBAT_DURATION, abilityName) then
      ability = models.newAbility(abilityId, abilityName, GetAbilityIcon(abilityId))
      addon.debug("[CD] %s duration %d ", ability:toLogString(), hitValue)
    end
    -- for not saved actions, i.e. ground action
    for key, action in pairs(l.actionQueue) do
      local abilityOnBar = models.newAbility(
        GetSlotBoundId(action.slotNum, action.hotbarCategory),
        models.patchAbilityName(GetSlotName(action.slotNum, action.hotbarCategory)),
        GetSlotTexture(action.slotNum, action.hotbarCategory)
      )
      if
        action.ability.id == abilityId
        or action.ability.name == abilityName
        or abilityOnBar.id == abilityId
        or abilityOnBar.name == abilityName
      then
        -- cache action matching when abilityOnBar differs from action.ability
        if abilityOnBar.id ~= action.ability.id then
          l.cacheOfActionMatchingAction[abilityOnBar.id .. "/" .. action.ability.id] = true
          l.cacheOfActionMatchingAction[action.ability.id .. "/" .. abilityOnBar.id] = true
        end
        -- 决定duration
        local duration = action.duration
        if duration == 0 and sourceType == targetType and sourceUnitId == targetUnitId then
          duration = hitValue
        end
        if duration > l.getSavedVars().coreMinimumDurationSeconds * 1000 then -- 给的duration相对合理
          local _ = nil
          -- 对于有些地面和aoe技能没有普通effect事件所以还没存
          if (action.flags.forArea and now - action.startTime < 2000) or action.flags.forGround then
            -- keep the original placement time before resetting startTime (see the other
            -- reset site above for the reason)
            if not action.placementTime then
              action.placementTime = action.startTime
            end
            action.startTime = now
            action.endTime = now + duration
            if action.flags.forGround then
              -- record this to mark next effect as activated one
              action.groundFirstEffectId = -1
            end
            l.saveAction(action)
            if addon.debugEnabled(DSS_COMBAT_DURATION, abilityName) then
              addon.debug("[CDg] %s ground duration %d for %s", ability:toLogString(), duration, action:toLogString())
            end
          end
          -- combat-event驱动的叠层用GAINED_DURATION的hitValue补/续期限（只延长不缩短）：
          -- 不用上面协商出的duration，因为action.duration可能属于别的效果，
          -- 例如Crystal Weapon的3s Weaver窗口会截短6s的叠层buff
          local stackEffect = action.stackEffect
          if
            stackEffect
            and stackEffect.combatEventId == abilityId
            and stackEffect.stackCount
            and stackEffect.stackCount > 0
            and stackEffect.endTime < now + hitValue
          then
            stackEffect.duration = hitValue
            stackEffect.endTime = now + hitValue
            stackEffect.startTime = now
            if l.getSavedVars().addonLogTrackedEffectsInChat then
              df(" |t24:24:%s|t%s (id: %d) %ds", GetAbilityIcon(abilityId), abilityName, abilityId, hitValue / 1000)
            end
            if addon.debugEnabled(DSS_COMBAT_DURATION, abilityName) then
              addon.debug("[CDs] %s stack duration %d for %s", ability:toLogString(), hitValue, action:toLogString())
            end
            return
          end
          -- 有些action还只有stackEffect2层数，而不知道层数的期限，例如龙骑的power lash
          local stackEffect2 = action:getStackEffect2()
          if stackEffect2 and stackEffect2.stackCount and stackEffect2.stackCount > 0 then
            local effect =
              models.newEffect(abilityOnBar, "player", sourceUnitId, now, now + duration, stackEffect2.stackCount, 0)
            effect.combatEventId = abilityId
            action:saveEffect(effect)
            l.saveAction(action)
            if addon.debugEnabled(DSS_COMBAT_DURATION, abilityName) then
              addon.debug("[CDs] %s stack duration %d for %s", ability:toLogString(), duration, action:toLogString())
            end
            return
          end
        end
      end
    end
    -- for saved actions, i.e. channel actions
    for key, action in pairs(l.idActionMap) do
      if action.channeled and (action.ability.id == abilityId or action.ability.name == abilityName) then
        local duration = action.duration
        if duration == 0 and sourceType == targetType and sourceUnitId == targetUnitId then
          duration = hitValue
          action.channelStartTime = now
          action.channelEndTime = now + duration
          action.channelUnitId = targetUnitId
          if addon.debugEnabled(DSS_COMBAT_DURATION, action.ability.name) then
            addon.debug("[CDc] %s channel duration %d for %s", ability:toLogString(), duration, action:toLogString())
          end
          return
        end
      end
      -- TODO if action not channeled, might need to update effect time, but this might be a duplicated action.
    end
  end
end

---@type fun(eventCode: number, changeType: number, effectSlot: number, effectName: string, unitTag: string, beginTimeSec: number, endTimeSec: number, stackCount: number, iconName: string, buffType: string, effectType: number, abilityType: number, statusEffectType: number, unitName: string, unitId: number, abilityId: number, sourceType: number)
l.onEffectChanged = function(
  eventCode,
  changeType,
  effectSlot,
  effectName,
  unitTag,
  beginTimeSec,
  endTimeSec,
  stackCount,
  iconName,
  buffType,
  effectType,
  abilityType,
  statusEffectType,
  unitName,
  unitId,
  abilityId,
  sourceType
)
  local now = GetGameTimeMilliseconds()
  effectName = effectName:gsub("^.*< (.*) >$", "%1"):gsub("%^%w", "")
  -- Map changeType to subswitch and prefix
  local changeTypeMap = {
    [EFFECT_RESULT_GAINED] = { "gain", "E+" },
    [EFFECT_RESULT_FADED] = { "fade", "E-" },
    [EFFECT_RESULT_UPDATED] = { "update", "E=" },
    [EFFECT_RESULT_FULL_REFRESH] = { "refresh", "E*" },
    [EFFECT_RESULT_TRANSFER] = { "transfer", "E/" },
  }
  local ctInfo = changeTypeMap[changeType] or { "unknown", "E?" }
  local effectAbiliy = models.newAbility(abilityId, effectName, iconName)
  if addon.debugEnabled({ DS_EFFECT, ctInfo[1] }, effectName) then
    addon.debug(
      "[%s%s]%s@%.2f<%.2f>[%s]for %s(%i:%s),type:%d,abType:%d,seType:%d,src:%d",
      ctInfo[2],
      stackCount > 0 and tostring(stackCount) or "",
      effectAbiliy:toLogString(),
      beginTimeSec > 0 and beginTimeSec or now / 1000,
      endTimeSec - beginTimeSec,
      iconName,
      unitTag ~= "" and unitTag or "none",
      unitId,
      unitName,
      effectType,
      abilityType,
      statusEffectType,
      sourceType
    )
  end

  -- ## The following mocking code block might be useful later
  --      if changeType~=2 and abilityId==61687  then -- TODO
  --        zo_callLater(function()
  --          d('<!!! mocking !!!')
  --          local old = ActionDurationReminder.debugLevels.all
  --          ActionDurationReminder.debugLevels.all = 2
  --          local t = GetGameTimeSeconds()
  --          l.onEffectChanged(eventCode,3,effectSlot,'Major Brutality','player',t,t+72,0,
  --          '/esoui/art/icons/ability_buff_major_brutality.dds',buffType,1,0,0,GetUnitName('player'),31865,61665,1)
  --          ActionDurationReminder.debugLevels.all = old
  --          d('!!! mocking over!!!>')
  --        end, 1)
  --      end

  -- ignore rubbish effects
  if l.ignoredIds[abilityId] then
    if addon.debugEnabled(DSS_FILTER_REJECT, effectName) then
      addon.debug("[FRI]%s(%d),%s", effectName, abilityId, l.ignoredIds[abilityId])
    end
    return
  end

  if not l.checkAbilityIdAndNameOk(abilityId, effectName) then
    if addon.debugEnabled(DSS_FILTER_REJECT, effectName) then
      addon.debug("[FRB]%s", effectName)
    end
    return
  end

  local notFoundKey = ("%d:%s:not found"):format(abilityId, effectName)
  local notFoundCount = l.ignoredCache:get(notFoundKey)
  if notFoundCount >= 3 then
    if addon.debugEnabled(DSS_FILTER_REJECT, effectName) then
      addon.debug("[FNC]%s", notFoundKey)
    end
    l.ignoredCache:mark(notFoundKey)
    return
  end

  local key = (changeType == EFFECT_RESULT_UPDATED)
      and ("%d:%s:%d*%d:update"):format(abilityId, effectName, stackCount, unitId)
    or ("%d:%s:%d:%d*%d"):format(abilityId, effectName, changeType, stackCount, unitId)
  local numMarks = l.ignoredCache:get(key)
  l.ignoredCache:mark(key)
  --  df(' |t24:24:%s|t%s (id: %d) mark: %d',iconName, effectName,abilityId,numMarks)
  if numMarks >= 12 then
    if addon.debugEnabled(DSS_FILTER_REJECT, effectName) then
      addon.debug("[FRN]%s", key)
    end
    return
  end

  -- 0. prepare
  -- ignore expedition on others
  if unitTag ~= "player" and iconName:find("buff_major_expedition", 1, true) then
    return
  end
  local ignoredIdsConfig = {
    ["ability_mage_062"] = "burning effect",
    ["ability_mage_039"] = "blight seed",
    ["death_recap_bleed_dot"] = "bleed dot",
    ["ability_healer_023"] = "sunlight",
  }
  for key, var in pairs(ignoredIdsConfig) do
    if not l.ignoredIds[key] and iconName:find(key, 1, true) then
      local info = "ignored " .. var
      l.ignoredIds[key] = info
      l.ignoredIds[abilityId] = info
      return
    end
  end

  if unitTag and string.find(unitTag, "group") then
    return
  end -- ignore effects on group members especially those same as player
  local startTime = math.floor(beginTimeSec * 1000)
  local endTime = math.floor(endTimeSec * 1000)
  local duration = endTime - startTime
  if duration > 150000 then
    return
  end -- ignore effects that last longer than 150 seconds
  if
    l.lastAction
    and not l.lastAction.flags.forGround
    and startTime
    and startTime - (l.lastAction.startTime + l.lastAction.castTime) > 2000
  then
    if addon.debugEnabled(DSS_ACTION_UNREF, l.lastAction.ability.name) then
      addon.debug("[AU]unref lastAction by time")
    end
    l.lastAction = nil
  end
  if l.lastEffectAction and startTime and startTime - l.lastEffectAction.lastEffectTime > 50 then
    l.lastEffectAction = nil
  end
  local ability = models.newAbility(abilityId, effectName, iconName)
  local effect = models.newEffect(ability, unitTag, unitId, startTime, endTime, stackCount, 0)
  if abilityId == models.POWER_LASH_GUIDE_ABILITY_ID then
    effect.stageInfo = "|t20:20:/esoui/art/icons/ability_warrior_025.dds|t"
    effect.stageInfoBlink = true
  end

  -- Handle crux effect globally (shared across all crux-consuming actions)
  if effect.isCrux then
    if changeType == EFFECT_RESULT_FADED then
      models.crux.setEffect(nil)
    else
      models.crux.setEffect(effect)
    end
    -- Ensure actions exist for all crux-consuming slots on the bar
    l.ensureCruxActions()
    return
  end

  -- 1. stack
  if stackCount > 0 then -- e.g. relentless focus
    local action = nil -- Models#Action
    if changeType == EFFECT_RESULT_FADED then
      action = l.findActionByOldEffect(effect)
      if not action then
        l.ignoredCache:mark(key)
        return
      end
      local currentStack = action.stackEffect
      if l.isRecentCombatGrant(currentStack, now) then
        -- fade of the old buff instance right after a combat-event re-grant (re-cast
        -- replacement, e.g. Crystal Weapon): keep the freshly granted stack
        if addon.debugEnabled(DSS_ACTION_STACK, action.ability.name) then
          addon.debug("[AKf]ignored fade right after re-grant %s", action:toLogString())
        end
        return
      end
      local stackInfoUpdated = action:updateStackInfo(0, effect)
      local oldEffect = action:purgeEffect(effect)
      l.timeActionMap[oldEffect.startTime] = nil
      if stackInfoUpdated then
        if addon.debugEnabled(DSS_ACTION_STACK, action.ability.name) then
          addon.debug("[AKC]purged stack info for %s", action:toLogString())
        end
        if
          action:getEndTime() <= now + 20
          and action:getStartTime() > now - 500 -- action trigger effect's end i.e. Crystal Fragment/Molten Whip
          and not action.oldAction -- check those with old action i.e. Assassin Will replacing Merciless Resolve
        then
          if addon.debugEnabled(DSS_ACTION_REMOVE, action.ability.name) then
            addon.debug(
              "[ARP]%s@%.2f~%.2f",
              action.ability:toLogString(),
              action.startTime / 1000,
              action:getEndTime() / 1000
            )
          end
          l.removeAction(action)
        end
      else
        if addon.debugEnabled(DSS_ACTION_STACK, action.ability.name) then
          addon.debug("[AKC]purged ignored stack info %s", action:toLogString())
        end
      end
    else
      action = l.findActionByNewEffect(effect, true)
      if not action then
        l.ignoredCache:mark(notFoundKey)
        if addon.debugEnabled(DSS_EFFECT_MATCH, effect.ability.name) then
          addon.debug("[]New stack effect action not found.")
        end
        return
      end
      if not l.checkAbilityIdAndNameOk(effect.ability.id, effect.ability.name) then
        if addon.debugEnabled(DSS_FILTER_REJECT, effect.ability.name) then
          addon.debug("[FRB]New stack effect filtered.")
        end
        return
      end
      if action.duration and action.duration > 0 then -- stackable actions with duration should ignore eso buggy effect time e.g. 20s Relentless Focus
        effect.startTime = action.startTime
        effect.duration = action.duration
        effect.endTime = action.endTime
      end
      local stackInfoUpdated = action:updateStackInfo(stackCount, effect)
      action:saveEffect(effect)
      if stackInfoUpdated then
        if addon.debugEnabled(DSS_ACTION_STACK, action.ability.name) then
          addon.debug("[AKU]updated stack info %s", action:toLogString())
        end
        l.saveAction(action)
      else
        if addon.debugEnabled(DSS_ACTION_STACK, action.ability.name) then
          addon.debug("[AK~]updated ignored stack info %s", action:toLogString())
        end
      end
    end
    return
  end

  -- check duration
  if duration > 0 and duration < l.getSavedVars().coreMinimumDurationSeconds * 1000 + 100 then
    return
  end
  -- check if it's a potion effect
  if effect.startTime - l.lastQuickslotTime < 100 and iconName:find("ability_buff_m", 1, true) then
    return
  end

  -- 2. gain
  if changeType == EFFECT_RESULT_GAINED then
    if duration == 0 then
      if iconName:find("ability_buff_major_evasion", 1, true) then
        -- patching for major evasion's initial zero duration event which will be updated right next
        duration = 6000
        endTime = startTime + duration
      else
        if addon.debugEnabled(DSS_FILTER_REJECT, effect.ability.name) then
          addon.debug("[FR0]New effect without duration.")
        end
        --      l.ignoredIds[abilityId] = 'new effect without duration' -- NOTE: This could happen very frequently
        return
      end
    end
    if not l.checkAbilityIdAndNameOk(effect.ability.id, effect.ability.name) then
      if addon.debugEnabled(DSS_FILTER_REJECT, effect.ability.name) then
        addon.debug("[FRB]New effect filtered.")
      end
      return
    end
    local action = l.findActionByNewEffect(effect)
    if not action then
      l.ignoredCache:mark(notFoundKey)
      if addon.debugEnabled(DSS_EFFECT_MISS, effect.ability.name) then
        addon.debug("[EM?]new effect action not found")
      end
      return
    end
    -- filter debuff if a bit longer than default duration
    if
      l.getSavedVars().coreIgnoreLongDebuff
      and action.duration
      and action.duration > 0
      and effect.duration > action.duration
      and effect.ability.icon:find("ability_debuff_", 1, true)
      --        and not action.descriptionNums[effect.duration/1000] -- This line should be commented out because it conflicts with option *coreIgnoreLongDebuff*
      and not action.ability.icon:find("ability_arcanist_011", 1, true) -- some debuff is useful, i.e. Rune of Edric Horror has a useful debuff
      and not action.ability.icon:find("ability_nightblade_016", 1, true) -- some debuff is useful, i.e. Aspect of Terror has a useful debuff
    then
      if addon.debugEnabled(DSS_FILTER_REJECT, effect.ability.name) then
        addon.debug("[FRD]ignore longer debuff %s for %s", effect:toLogString(), action:toLogString())
      end
      return
    end
    action:saveEffect(effect)
    -- patches
    -- weird patch
    local weird = effect.duration == 0
    if not weird then
      local firstSave = not action.saved
      l.saveAction(action)
      if firstSave then
        -- search player stack buff effects and save them in the newly saved action
        local numBuffs = GetNumBuffs("player")
        for i = 1, numBuffs do
          local buffName, timeStarted, timeEnding, buffSlot, stackCount, iconFilename, buffType, effectType, abilityType, statusEffectType, abilityId, canClickOff, castByPlayer =
            GetUnitBuffInfo("player", i)
          if timeStarted == timeEnding and stackCount > 0 then
            local startTime = math.floor(timeStarted * 1000)
            local ability = models.newAbility(abilityId, buffName, iconFilename)
            local effect = models.newEffect(ability, "player", 0, startTime, startTime, stackCount, 0)
            if action:matchesNewEffect(effect) then
              -- stackable actions with duration should ignore eso buggy effect time e.g. 20s Relentless Focus
              if action.duration and action.duration > 0 then
                effect.startTime = action.startTime
                effect.duration = action.duration
                effect.endTime = action.endTime
              end
              local stackInfoUpdated = action:updateStackInfo(stackCount, effect)
              if stackInfoUpdated then
                action:saveEffect(effect)
                l.saveAction(action)
                if addon.debugEnabled(DSS_ACTION_STACK, action.ability.name) then
                  addon.debug("[AKU]updated stack info %s", action:toLogString())
                end
              end
            end
          end
        end
      end
    end
    -- count for daedric mines
    local ofDaedricMines = iconName:find("daedric_mines", 1, true)
      or (iconName:find("mage_065", 1, true) and action.ability.icon:find("daedric_[mt][io][nm][eb]", 1, false)) -- this icon also appears in Wall of Element, we can filter by duration
    if ofDaedricMines then
      ability.type = abilityType
    end -- record area effect for daedric mines

    return
  end
  -- 3. update
  if changeType == EFFECT_RESULT_UPDATED then
    if not l.checkAbilityIdAndNameOk(effect.ability.id, effect.ability.name) then
      if addon.debugEnabled(DSS_FILTER_REJECT, effect.ability.name) then
        addon.debug("[FRB]Update effect filtered.")
      end
      return
    end
    -- find effect strictly if without duration or is buff
    local action, isNew =
      l.findActionByOldEffect(effect, effect.duration > 0 and not effect.ability.icon:find("ability_buff_", 1, true))
    if not action then
      l.ignoredCache:mark(notFoundKey)
      if addon.debugEnabled(DSS_EFFECT_MISS, effect.ability.name) then
        addon.debug("[EM?]update effect action not found")
      end
      return
    end
    if
      isNew
      and l.getSavedVars().coreIgnoreLongDebuff
      and action.duration
      and action.duration > 0
      and effect.duration > action.duration
      and effect.ability.icon:find("ability_debuff_", 1, true)
      and not action.ability.icon:find("ability_arcanist_011", 1, true) -- some debuff is useful, i.e. Rune of Edric Horror has a useful vulnerability
      and not action.ability.icon:find("ability_nightblade_016", 1, true) -- some debuff is useful, i.e. Aspect of Terror has a useful debuff
    then
      if addon.debugEnabled(DSS_FILTER_REJECT, effect.ability.name) then
        addon.debug("[FRD]ignore update long debuff %s for %s", effect:toLogString(), action:toLogString())
      end
      return
    end
    if isNew and effect.duration == 0 then
      if addon.debugEnabled(DSS_FILTER_REJECT, effect.ability.name) then
        addon.debug("[FR0]ignore 0ms effect %s for %s", effect:toLogString(), action:toLogString())
      end
      return
    end
    action:saveEffect(effect)
    l.saveAction(action)
    return
  end
  -- 4. fade
  if changeType == EFFECT_RESULT_FADED then
    local action = l.findActionByOldEffect(effect)
    if action then
      local currentStack = action.stackEffect
      if
        l.isRecentCombatGrant(currentStack, now)
        and currentStack.ability.id == effect.ability.id
        and (currentStack.unitId == effect.unitId or effect.unitId == 0)
      then
        -- fade of the old buff instance right after a combat-event re-grant (re-cast
        -- replacement, e.g. Crystal Weapon): keep the freshly granted stack
        if addon.debugEnabled(DSS_EFFECT_FADE, effect.ability.name) then
          addon.debug("[EFf]ignored fade right after re-grant %s", action:toLogString())
        end
        return
      end
      local oldEffect = action:purgeEffect(effect)
      if oldEffect then
        local clearTimeRecord = true
        for key, var in ipairs(action.effectList) do
          if var.startTime == oldEffect.startTime then
            clearTimeRecord = false
          end
        end
        if clearTimeRecord then
          l.timeActionMap[oldEffect.startTime] = nil
        end -- don't clear time record if other effect still exist
      end
      --  action trigger effect's end i.e. Crystal Fragment/Molten Whip
      if action.oldAction and action.oldAction.fake then
        if now < action:getStartTime() + 1100 then
          if addon.debugEnabled(DSS_ACTION_REMOVE, action.ability.name) then
            addon.debug("[ART]%s", action:toLogString())
          end
          l.removeAction(action)
        end
      end
      return
    end
    return
  end
end

---@type fun(eventCode: number, mounted: boolean)
l.onMountedStateChanged = function(eventCode, mounted)
  if mounted and l.gallopAction then
    local gallopEffect = l.gallopAction:optGallopEffect()
    if gallopEffect and gallopEffect.endTime > GetGameTimeMilliseconds() then
      l.saveAction(l.gallopAction)
      l.gallopAction = nil
    end
  end
end

---@type fun(eventCode: number, initial: boolean)
l.onPlayerActivated = function(eventCode, initial)
  -- check toggled actions
  ---@type adr.models.Action[]
  local tickedActions = {}
  for key, action in pairs(l.idActionMap) do
    if action.tickEffect then
      table.insert(tickedActions, action)
    end
  end
  ---@type table<number, boolean>
  local toggledIdInfo = {}
  local hotbarCategory = GetActiveHotbarCategory()
  for slotNum = 3, 8 do
    if IsSlotToggled(slotNum, hotbarCategory) then
      local abilityId = GetSlotBoundId(slotNum, hotbarCategory)
      if GetSlotType(slotNum, hotbarCategory) == ACTION_TYPE_CRAFTED_ABILITY then
        abilityId = GetAbilityIdForCraftedAbilityId(abilityId)
      end
      toggledIdInfo[abilityId] = true
    end
  end
  for key, action in ipairs(tickedActions) do
    if not toggledIdInfo[action.ability.id] then
      l.removeAction(action)
    end
  end
  -- bootstrap Nothing Wasted state after login/zone change with stacks already running:
  -- the hidden buff may not re-deliver EFFECT_CHANGED, so scan the buff list once.
  -- remaining window time is unknowable (API reports 0~0); assume a full window and let
  -- the next decay event correct it
  local numBuffs = GetNumBuffs("player")
  for i = 1, numBuffs do
    local _, _, _, _, stackCount, _, _, _, _, _, abilityId = GetUnitBuffInfo("player", i)
    if abilityId == models.NOTHING_WASTED_ABILITY_ID and stackCount > 0 then
      models.nothingWasted.update(stackCount, GetGameTimeMilliseconds() + models.NOTHING_WASTED_WINDOW_MS)
      l.ensureNothingWastedActions()
      break
    end
  end
end

---@type fun(eventCode: number, inCombat: boolean)
l.onPlayerCombatState = function(eventCode, inCombat)
  if not l.getSavedVars().coreClearAreaActionsOnCombatEnd then
    return
  end
  zo_callLater(function()
    if not IsUnitInCombat("player") then
      m.clearAreaActions()
    end
  end, 3000)
end

---@type fun(eventCode: number)
l.onReticleTargetChanged = function(eventCode)
  l.targetId = nil
  if not l.getSavedVars().coreMultipleTargetTracking then
    return
  end
  if not DoesUnitExist("reticleover") then
    return
  end
  -- 1. remove all enemy actions from self.idActionMap
  local ignoredEffectIds = {}
  for key, action in pairs(l.idActionMap) do
    if addon.debugEnabled(DSS_TARGET_TRACK, action.ability.name) then
      addon.debug(
        "[TC]processing %s,%s",
        action.ability.name,
        action.flags.onlyOneTarget and "onlyOneTarget" or "normal"
      )
    end
    if action.flags.onlyOneTarget then -- e.g. daedric curse, rune cage,  we do not switch on target changing
      for i, effect in ipairs(action.effectList) do
        ignoredEffectIds[effect.ability.id] = true
      end
    elseif action.flags.forEnemy then
      action.targetOut = true
      if not l.getSavedVars().coreMultipleTargetTrackingWithoutClearing then
        l.idActionMap[key] = nil
      end
      if addon.debugEnabled(DSS_TARGET_TRACK, action.ability.name) then
        addon.debug(
          "[TCO]%s@%.2f<%.2f>%s",
          action.ability:toLogString(),
          action:getStartTime() / 1000,
          action:getDuration() / 1000,
          action:getFlagsInfo()
        )
      end
    end
  end
  -- 2. scan all matched buffs
  local numBuffs = GetNumBuffs("reticleover")
  local numRestored = 0
  for i = 1, numBuffs do
    local buffName, timeStarted, timeEnding, buffSlot, stackCount, iconFilename, buffType, effectType, abilityType, statusEffectType, abilityId, canClickOff, castByPlayer =
      GetUnitBuffInfo("reticleover", i)
    if castByPlayer and not ignoredEffectIds[abilityId] and not l.ignoredIds[abilityId] then
      local startTime = math.floor(timeStarted * 1000)
      local action = l.timeActionMap[startTime]
      if action then
        local ability = models.newAbility(abilityId, buffName, iconFilename)
        local effect = models.newEffect(ability, "none", 0, startTime, startTime, 0, 0) -- only for match, no need to be precise timing
        if action:matchesOldEffect(effect) then
          action.targetOut = false
          l.idActionMap[action.ability.id] = action
          numRestored = numRestored + 1
          if addon.debugEnabled(DSS_TARGET_TRACK, action.ability.name) then
            addon.debug(
              "[TCI]%s@%.2f<%.2f>",
              action.ability:toLogString(),
              action:getStartTime() / 1000,
              action:getDuration() / 1000
            )
          end
          if action.flags.forEnemy and action.targetId and action.targetId > 0 then
            l.targetId = action.targetId
          end
        else
          if addon.debugEnabled(DSS_TARGET_TRACK, action.ability.name) then
            addon.debug(
              "[TCX]%s@%.2f<%.2f>",
              action.ability:toLogString(),
              action:getStartTime() / 1000,
              action:getDuration() / 1000
            )
          end
        end
      else
        if addon.debugEnabled(DSS_TARGET_TRACK, buffName) then
          addon.debug("[T?]%s(%i)@%.2f<%.2f> not found", buffName, abilityId, timeStarted, timeEnding - timeStarted)
        end
      end
    end
  end
end

---@type fun()
l.onStart = function()
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_ACTION_SLOT_ABILITY_USED, l.onActionSlotAbilityUsed)
  EVENT_MANAGER:RegisterForUpdate(addon.name, 100, l.onUpdate)
  EVENT_MANAGER:RegisterForUpdate(addon.name .. "_PowerLash", 200, l.onUpdateForPowerLash)
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_EFFECT_CHANGED, l.onEffectChanged)
  EVENT_MANAGER:AddFilterForEvent(
    addon.name,
    EVENT_EFFECT_CHANGED,
    REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE,
    COMBAT_UNIT_TYPE_PLAYER
  )
  -- Nothing Wasted (Necromancer's hidden stack buff): its EFFECT_CHANGED events are not
  -- delivered through the source-filtered registrations above, so listen unfiltered
  EVENT_MANAGER:RegisterForEvent(addon.name .. "_nothingWasted", EVENT_EFFECT_CHANGED, function(...)
    local abilityId = select(16, ...)
    if abilityId == models.NOTHING_WASTED_ABILITY_ID then
      local changeType = select(2, ...)
      if changeType == EFFECT_RESULT_FADED then
        models.nothingWasted.clear()
      else
        local unitTag = select(5, ...)
        if unitTag == "player" then
          local stackCount = select(8, ...)
          models.nothingWasted.update(stackCount, GetGameTimeMilliseconds() + models.NOTHING_WASTED_WINDOW_MS)
          l.ensureNothingWastedActions()
        end
      end
    end
  end)
  EVENT_MANAGER:RegisterForEvent(addon.name .. "_pet", EVENT_EFFECT_CHANGED, l.onEffectChanged)
  EVENT_MANAGER:AddFilterForEvent(
    addon.name .. "_pet",
    EVENT_EFFECT_CHANGED,
    REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE,
    COMBAT_UNIT_TYPE_PLAYER_PET
  )

  EVENT_MANAGER:RegisterForEvent(addon.name .. "_patch", EVENT_EFFECT_CHANGED, function(...)
    local sourceType = select(17, ...)
    if sourceType == COMBAT_UNIT_TYPE_NONE or sourceType == COMBAT_UNIT_TYPE_TARGET_DUMMY then
      local icon = select(9, ...)
      -- patch for Force Siphon, this skill effect can only be filtered by COMBAT_UNIT_TYPE_NONE
      if icon:find("minor_lifesteal", 1, true) then
        l.onEffectChanged(...)
      end
      -- patch for Restoring Aura, this skill effect can only be filtered by COMBAT_UNIT_TYPE_NONE
      if icon:find("minor_magickasteal", 1, true) then
        l.onEffectChanged(...)
      end
    end
  end)

  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_COMBAT_EVENT, l.onCombatEvent)
  EVENT_MANAGER:RegisterForEvent(addon.name .. "_fromPlayer", EVENT_COMBAT_EVENT, l.onCombatEventFromPlayer)
  EVENT_MANAGER:AddFilterForEvent(
    addon.name .. "_fromPlayer",
    EVENT_COMBAT_EVENT,
    REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE,
    COMBAT_UNIT_TYPE_PLAYER
  )
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_RETICLE_TARGET_CHANGED, l.onReticleTargetChanged)
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_PLAYER_COMBAT_STATE, l.onPlayerCombatState)
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_PLAYER_ACTIVATED, l.onPlayerActivated)
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_ACTION_UPDATE_COOLDOWNS, l.onActionUpdateCooldowns)
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_MOUNTED_STATE_CHANGED, l.onMountedStateChanged)
end

l.lastUpdateLog = 0
---@type fun()
l.onUpdate = function()
  l.refineActions()
  l.checkActionLeaks()
  addon.callExtension(m.EXTKEY_UPDATE)
end

-- Leak detection: warn and remove duplicate actions
addon.actionLeakLogInterval = 300 -- seconds
addon.actionLeakCntValve = 20 -- threshold for warning
l.lastLeakLog = 0

---@type fun()
l.checkActionLeaks = function()
  local savedVars = l.getSavedVars()
  local now = GetGameTimeSeconds()
  if now - l.lastLeakLog < addon.actionLeakLogInterval then
    return
  end

  -- count actions by ability id
  ---@type table<number, number>
  local cntMap = {}
  ---@type table<number, number>
  local maxSnMap = {}
  for sn, action in pairs(l.snActionMap) do
    cntMap[action.ability.id] = (cntMap[action.ability.id] or 0) + 1
    maxSnMap[action.ability.id] = math.max(maxSnMap[action.ability.id] or 0, action.sn)
  end

  local didLog = false
  for id, cnt in pairs(cntMap) do
    if cnt > addon.actionLeakCntValve then
      didLog = true
      if savedVars.addonLogTrackedEffectsInChat then
        df("[!ADR!] |t24:24:%s|t%s(%d) #%d", GetAbilityIcon(id), GetAbilityName(id), id, cnt)
      end
      -- remove potential leaked actions (keep the one with highest sn)
      ---@type adr.models.Action[]
      local toRemove = {}
      for sn, action in pairs(l.snActionMap) do
        if action.ability.id == id and sn < maxSnMap[id] then
          toRemove[#toRemove + 1] = action
        end
      end
      for _, action in ipairs(toRemove) do
        l.removeAction(action)
      end
    end
  end
  if didLog then
    l.lastLeakLog = now
  end
end

---@type fun(action: adr.models.Action)
l.queueAction = function(action)
  l.lastAction = action
  ---@type adr.models.Action[]
  local newQueue = {}
  newQueue[1] = action
  local now = GetGameTimeMilliseconds()
  for key, a in ipairs(l.actionQueue) do
    if not a.newAction and now - a.startTime < 3 * 1000 then
      table.insert(newQueue, a)
    end
  end
  l.actionQueue = newQueue
end

---@type fun()
l.refineActions = function()
  local now = GetGameTimeMilliseconds()
  local endLimit = now - l.getSavedVars().coreSecondsBeforeFade * 1000
  for key, action in pairs(l.idActionMap) do
    local endTime = action:isUnlimited() and endLimit + 1 or action:getEndTime()
    local stackEffect = action:getStackEffect()
    local stackCount = stackEffect and stackEffect.stackCount or 0
    if
      stackCount == 0 -- i.e. Grim Focus triggered by weapon attack
      and endTime < (action.fake and now or endLimit)
    then
      if addon.debugEnabled(DSS_ACTION_REMOVE, action.ability.name) then
        addon.debug("[ARR]%s,endTime:%.2f<endLimit:%.2f", action:toLogString(), endTime / 1000, endLimit / 1000)
      end
      l.removeAction(action)
      local gallopEffect = action:optGallopEffect()
      if gallopEffect and gallopEffect.endTime > now then
        l.gallopAction = action
      end
    end
  end
  endLimit = endLimit - 3000 -- timeActionMap remains a little longer to be found by further effect
  for key, action in pairs(l.timeActionMap) do
    if action:getEndTime() < endLimit then
      l.timeActionMap[key] = nil
      if addon.debugEnabled(DSS_ACTION_DELETE, action.ability.name) then
        addon.debug(
          "[ADT]%s@%.2f<%i>",
          action.ability:toLogString(),
          action.startTime / 1000,
          action:getDuration() / 1000
        )
      end
    end
  end
end

---@type fun(action: adr.models.Action): boolean
l.removeAction = function(action)
  local removed = false
  -- remove from idActionMap
  local old = l.idActionMap[action.ability.id]
  if old and old.sn == action.sn then
    l.idActionMap[action.ability.id] = nil
    removed = true
    if addon.debugEnabled(DSS_ACTION_DELETE, action.ability.name) then
      addon.debug("[ADI]idActionMap:%s", action:toLogString())
    end
  end
  -- remove from timeActionMap
  local times = {}
  for key, var in pairs(l.timeActionMap) do
    if var.sn == action.sn then
      times[#times + 1] = key
    end
  end
  for key, var in ipairs(times) do
    l.timeActionMap[var] = nil
  end
  -- remove from snActionMap
  l.snActionMap[action.sn] = nil
  -- remove fake/trigger actions from queue, otherwise next fake action will failed to recognize i.e. Crystal Fragment
  if action.oldAction and action.oldAction.fake then
    ---@type adr.models.Action[]
    local newQueue = {}
    for key, a in ipairs(l.actionQueue) do
      if a.ability.id ~= action.ability.id and a.ability.id ~= action.oldAction.ability.id then
        table.insert(newQueue, a)
      end
    end
    l.actionQueue = newQueue
  end
  --
  return removed
end

---检查玩家是否龙骑士(缓存)
---@type fun(): boolean
l.isPlayerDragonknight = function()
  if l.powerLashGuideState.isDragonknight == nil then
    l.powerLashGuideState.isDragonknight = GetUnitClassId("player") == models.DRAGONKNIGHT_CLASS_ID
  end
  return l.powerLashGuideState.isDragonknight
end

-- Check if target has Off Balance debuff
l.targetHasOffBalance = function()
  if not DoesUnitExist("reticleover") then
    return false
  end
  local numBuffs = GetNumBuffs("reticleover") or 0
  for i = 1, numBuffs do
    local _, _, _, _, _, iconFilename = GetUnitBuffInfo("reticleover", i)
    if iconFilename and iconFilename:find(models.OFF_BALANCE_ICON_KEYWORD, 1, true) then
      return true
    end
  end
  return false
end

---@type fun(show: string)
l.sendPowerLashGuide = function(show)
  -- Avoid sending same type repeatedly
  if l.powerLashGuideState.lastGuideType == (show and "show" or "hide") then
    return
  end
  l.powerLashGuideState.lastGuideType = show and "show" or "hide"

  local now = GetGameTimeMilliseconds()
  local nowSec = now / 1000

  if show then
    -- Show guide effect (GAINED) - unlimited duration using stackCount=1, duration=0
    if addon.debugEnabled(DSS_EFFECT_GAIN, "PowerLashGuide") then
      addon.debug("[E+]PowerLashGuide - Off Balance detected, use Power Lash!")
    end
    l.onEffectChanged(
      EVENT_EFFECT_CHANGED,
      EFFECT_RESULT_GAINED,
      0, -- effectSlot (fake)
      "Power Lash Guide", -- effectName
      "player", -- unitTag
      nowSec, -- beginTime
      nowSec, -- endTime (same as beginTime for duration=0)
      1, -- stackCount=1 for unlimited duration
      GetAbilityIcon(models.POWER_LASH_ABILITY_ID), -- iconName (Power Lash icon)
      0, -- buffType
      0, -- effectType
      0, -- abilityType
      0, -- statusEffectType
      GetUnitName("player"), -- unitName
      0, -- unitId
      models.POWER_LASH_GUIDE_ABILITY_ID, -- abilityId (fake)
      COMBAT_UNIT_TYPE_PLAYER -- sourceType
    )
  else
    -- Hide guide effect (FADED)
    if addon.debugEnabled(DSS_EFFECT_FADE, "PowerLashGuide") then
      addon.debug("[E-]PowerLashGuide - conditions no longer met")
    end
    l.onEffectChanged(
      EVENT_EFFECT_CHANGED,
      EFFECT_RESULT_FADED,
      0, -- effectSlot (fake)
      "Power Lash Guide", -- effectName
      "player", -- unitTag
      nowSec, -- beginTime
      nowSec, -- endTime
      0, -- stackCount
      GetAbilityIcon(models.POWER_LASH_ABILITY_ID), -- iconName
      0, -- buffType
      0, -- effectType
      0, -- abilityType
      0, -- statusEffectType
      GetUnitName("player"), -- unitName
      0, -- unitId
      models.POWER_LASH_GUIDE_ABILITY_ID, -- abilityId (fake)
      COMBAT_UNIT_TYPE_PLAYER -- sourceType
    )
  end
end

---@type fun()
l.onUpdateForPowerLash = function()
  -- Check if player is Dragonknight
  if not l.isPlayerDragonknight() then
    return
  end

  -- Check if player is in combat
  if not IsUnitInCombat("player") then
    l.sendPowerLashGuide(false)
    return
  end

  -- Find Flame Lash in hotbar
  local hotbarCategory, slotNum = l.findFlameLashSlot()
  if not hotbarCategory then
    -- No Flame Lash found, hide guide if was shown
    l.sendPowerLashGuide(false)
    return
  end

  -- Get Flame Lash action and check if in cooldown (20s)
  local flameLashAction = l.getActionBySlot(hotbarCategory, slotNum)
  if flameLashAction then
    local duration, durSource = flameLashAction:getDuration()
    -- If its prioritized effect duration is around 20 seconds (19000-21000ms), it's in Power Lash cooldown
    if durSource == models.DUR_SOURCE_PRIORITY and duration >= 19000 and duration <= 21000 then
      -- In Power Lash cooldown, hide guide if was shown
      l.sendPowerLashGuide(false)
      return
    end
  end

  -- Check if target has Off Balance
  if l.targetHasOffBalance() then
    -- Show guide: Flame Lash available and target has Off Balance
    l.sendPowerLashGuide(true)
  else
    -- Hide guide: target doesn't have Off Balance
    l.sendPowerLashGuide(false)
  end
end

---@type fun(action: adr.models.Action)
l.saveAction = function(action)
  l.lastEffectAction = action

  -- clear same name action that can have a different id
  local sameNameAction = l.getActionByNewAction(action)
  if sameNameAction and sameNameAction.sn ~= action.sn then
    l.removeAction(sameNameAction)
  end

  local old = l.idActionMap[action.ability.id]
  if old and old.sn == action.sn then
    old = nil
  end -- 没有旧的
  if old then
    l.removeAction(old)
  end

  l.idActionMap[action.ability.id] = action
  l.snActionMap[action.sn] = action
  action.saved = true
  for i, effect in ipairs(action.effectList) do
    l.timeActionMap[effect.startTime] = action
  end
  local getValueActionsInfo = function(t)
    local names = ""
    for key, var in pairs(t) do
      names = names .. " " .. var:toLogString_Short()
    end
    return names
  end
  local getKeyNames = function(t)
    local names = ""
    for key, var in pairs(t) do
      names = names .. " " .. key
    end
    return names
  end
  if addon.debugEnabled(DSS_ACTION_SAVE, action.ability.name) then
    addon.debug(
      "[AS]%s\n>idActionMap:%s\n>timeActionMap:%s\n>cacheOfActionMatchingAction:%s",
      action:toLogString(),
      getValueActionsInfo(l.idActionMap),
      getValueActionsInfo(l.timeActionMap),
      getKeyNames(l.cacheOfActionMatchingAction)
    )
  end
end

--========================================
--        m
--========================================
m.EXTKEY_UPDATE = "Core:update"

-- debug levels deprecated, use fine-grained settings instead

---@type fun(abilityId: number): adr.models.Action?
m.getActionByAbilityId = l.getActionByAbilityId

---@type fun(abilityName: string, strict?: boolean): adr.models.Action?
m.getActionByAbilityName = l.getActionByAbilityName

---@type fun(hotbarCategory: number, slotNum: number): adr.models.Action?
m.getActionBySlot = l.getActionBySlot

---@type fun()
m.clearActions = function()
  if addon.debugEnabled(DSS_ACTION_CLEAR) then
    addon.debug("[AC]")
  end
  l.actionQueue = {}
  l.idActionMap = {}
  l.timeActionMap = {}
  l.snActionMap = {}
end
addon.clearActions = m.clearActions
addon.clear = m.clearActions

---@type fun()
m.clearAreaActions = function()
  if addon.debugEnabled(DSS_ACTION_CLEAR) then
    addon.debug("[ACA]")
  end
  local newQueue = {}
  for key, var in ipairs(l.actionQueue) do
    if not var.flags.forArea and not var.flags.forGround then
      table.insert(newQueue, var)
    end
  end
  l.actionQueue = newQueue
  local newMap = {}
  for key, var in pairs(l.idActionMap) do
    if not var.flags.forArea and not var.flags.forGround then
      newMap[key] = var
    end
  end
  l.idActionMap = newMap
  newMap = {}
  for key, var in pairs(l.timeActionMap) do
    if not var.flags.forArea and not var.flags.forGround then
      newMap[key] = var
    end
  end
  l.timeActionMap = newMap
end
addon.clearAreaActions = m.clearAreaActions

---@type fun(): table<number, adr.models.Action>
m.getIdActionMap = function()
  return l.idActionMap
end
addon.getIdActionMap = m.getIdActionMap

---@type fun(): table<number, adr.models.Action>
m.getSnActionMap = function()
  return l.snActionMap
end
addon.getSnActionMap = m.getSnActionMap

---@type fun(): table<number, adr.models.Action>
m.getTimeActionMap = function()
  return l.timeActionMap
end
addon.getTimeActionMap = m.getTimeActionMap

--========================================
--        register
--========================================
addon.register("Core#M", m)

addon.register("Core", m)

addon.hookStart(l.onStart)

addon.extend(settings.EXTKEY_ADD_DEFAULTS, function()
  settings.addDefaults(coreSavedVarsDefaults)
end)

addon.extend(settings.EXTKEY_ADD_MENUS, function()
  settings.addMenuOptions({
    type = "submenu",
    name = addon.text("Core"),
    controls = {
      {
        type = "checkbox",
        name = addon.text("Multi-Target Tracking"),
        tooltip = addon.text("Track DoT timers on multiple targets simultaneously"),
        getFunc = function()
          return l.getSavedVars().coreMultipleTargetTracking
        end,
        setFunc = function(value)
          l.getSavedVars().coreMultipleTargetTracking = value
        end,
        width = "full",
        default = coreSavedVarsDefaults.coreMultipleTargetTracking,
      },
      {
        type = "checkbox",
        name = addon.text("Preserve Timers on Target Switch"),
        tooltip = addon.text(
          "Keep timers when switching targets (no target moment won't clear previous target's timers)"
        ),
        getFunc = function()
          return l.getSavedVars().coreMultipleTargetTrackingWithoutClearing
        end,
        setFunc = function(value)
          l.getSavedVars().coreMultipleTargetTrackingWithoutClearing = value
        end,
        width = "full",
        default = coreSavedVarsDefaults.coreMultipleTargetTrackingWithoutClearing,
        disabled = function()
          return not l.getSavedVars().coreMultipleTargetTracking
        end,
      },
      {
        type = "checkbox",
        name = addon.text("Clear Area Actions on Combat End"),
        tooltip = addon.text("Remove area/ground timers when combat ends"),
        getFunc = function()
          return l.getSavedVars().coreClearAreaActionsOnCombatEnd
        end,
        setFunc = function(value)
          l.getSavedVars().coreClearAreaActionsOnCombatEnd = value
        end,
        width = "full",
        default = coreSavedVarsDefaults.coreClearAreaActionsOnCombatEnd,
      },
      {
        type = "slider",
        name = addon.text("Post-Expiry Flash Duration"),
        tooltip = addon.text(
          "Show a flashing 0.0 for this many seconds after timer expires, reminding you the skill is ready to recast"
        ),
        min = 0,
        max = 10,
        step = 1,
        getFunc = function()
          return l.getSavedVars().coreSecondsBeforeFade
        end,
        setFunc = function(value)
          l.getSavedVars().coreSecondsBeforeFade = value
        end,
        width = "full",
        default = coreSavedVarsDefaults.coreSecondsBeforeFade,
      },
      {
        type = "slider",
        name = addon.text("Minimum Timer Duration"),
        tooltip = addon.text("Ignore effects with duration shorter than this"),
        min = 1,
        max = 10,
        step = 0.5,
        getFunc = function()
          return l.getSavedVars().coreMinimumDurationSeconds
        end,
        setFunc = function(value)
          l.getSavedVars().coreMinimumDurationSeconds = value
        end,
        width = "full",
        default = coreSavedVarsDefaults.coreMinimumDurationSeconds,
      },
      {
        type = "checkbox",
        name = addon.text("Ignore Mismatched Debuff Durations"),
        tooltip = addon.text(
          "Use skill's own duration when debuff duration is longer (handles buggy ESO debuff times)"
        ),
        getFunc = function()
          return l.getSavedVars().coreIgnoreLongDebuff
        end,
        setFunc = function(value)
          l.getSavedVars().coreIgnoreLongDebuff = value
        end,
        width = "full",
        default = coreSavedVarsDefaults.coreIgnoreLongDebuff,
      },
      {
        type = "editbox",
        name = addon.text("Whitelist Patterns"),
        tooltip = addon.text(
          "Skills to always track. One pattern per line. Use skill name substring or numeric ability ID"
        ),
        getFunc = function()
          return l.getSavedVars().coreKeyWords
        end,
        setFunc = function(text)
          l.getSavedVars().coreKeyWords = text
          l.idFilteringMap = {}
          l.idDurationMap = {}
        end,
        isMultiline = true,
        isExtraWide = true,
        width = "full",
        requiresReload = false,
        default = coreSavedVarsDefaults.coreKeyWords,
      },
      {
        type = "editbox",
        name = addon.text("Blacklist Patterns"),
        tooltip = addon.text(
          "Skills to never track. One pattern per line. Use skill name substring or numeric ability ID"
        ),
        getFunc = function()
          return l.getSavedVars().coreBlackKeyWords
        end,
        setFunc = function(text)
          l.getSavedVars().coreBlackKeyWords = text
          l.idFilteringMap = {}
        end,
        isMultiline = true,
        isExtraWide = true,
        width = "full",
        requiresReload = false,
        default = coreSavedVarsDefaults.coreBlackKeyWords,
      },
    },
  })
end)

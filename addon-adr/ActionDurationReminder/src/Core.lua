--========================================
--        vars
--========================================
local addon = ActionDurationReminder -- Addon#M
local utils = addon.load("Utils#M")
local settings = addon.load("Settings#M")
local models = addon.load("Models#M")
local l = {} -- #L
local m = {l=l} -- #M

local DS_ACTION = "action" -- debug switch for action
local DS_EFFECT = "effect" -- debug switch for effect
local DS_COMBAT = "combat" -- debug switch for combat events
local DS_TARGET = "target" -- debug switch for target
local DS_FILTER = "filter" -- debug switch for filter

-- DSS (Debug Switch + SubSwitch) constants for addon.debugEnabled
-- Filter
local DSS_FILTER_ACCEPT = {DS_FILTER, 'accept'}
local DSS_FILTER_REJECT = {DS_FILTER, 'reject'}
-- Action
local DSS_ACTION_FIND = {DS_ACTION, 'find'}
local DSS_ACTION_NEW = {DS_ACTION, 'new'}
local DSS_ACTION_MATCH = {DS_ACTION, 'match'}
local DSS_ACTION_UNREF = {DS_ACTION, 'unref'}
local DSS_ACTION_STACK = {DS_ACTION, 'stack'}
local DSS_ACTION_REMOVE = {DS_ACTION, 'remove'}
local DSS_ACTION_DELETE = {DS_ACTION, 'delete'}
local DSS_ACTION_SAVE = {DS_ACTION, 'save'}
local DSS_ACTION_CLEAR = {DS_ACTION, 'clear'}
-- Combat
local DSS_COMBAT_EVENT = {DS_COMBAT, 'event'}
local DSS_COMBAT_FADE = {DS_COMBAT, 'fade'}
local DSS_COMBAT_STACK = {DS_COMBAT, 'stack'}
local DSS_COMBAT_TICK = {DS_COMBAT, 'tick'}
local DSS_COMBAT_DURATION = {DS_COMBAT, 'duration'}
local DSS_COMBAT_CHANNEL = {DS_COMBAT, 'channel'}
-- Effect
local DSS_EFFECT_GAIN = {DS_EFFECT, 'gain'}
local DSS_EFFECT_FADE = {DS_EFFECT, 'fade'}
local DSS_EFFECT_UPDATE = {DS_EFFECT, 'update'}
local DSS_EFFECT_REFRESH = {DS_EFFECT, 'refresh'}
local DSS_EFFECT_TRANSFER = {DS_EFFECT, 'transfer'}
local DSS_EFFECT_MISS = {DS_EFFECT, 'miss'}
local DSS_EFFECT_MATCH = {DS_EFFECT, 'match'}
-- Target
local DSS_TARGET_TRACK = {DS_TARGET, 'track'}

---
--@type CoreSavedVars
local coreSavedVarsDefaults = {
  coreMultipleTargetTracking = true,
  coreMultipleTargetTrackingWithoutClearing = true,
  coreSecondsBeforeFade = 5,
  coreMinimumDurationSeconds = 2.5,
  coreIgnoreLongDebuff = true,
  coreKeyWords = '',
  coreBlackKeyWords = '',
  coreClearWhenCombatEnd = false,
  -- fine-grained debug options (default all true when logging enabled)
  -- DS_ACTION
  debugActionFind = true,
  debugActionNew = true,
  debugActionMatch = true,
  debugActionUnref = true,
  debugActionStack = true,
  debugActionRemove = true,
  debugActionDelete = true,
  debugActionSave = true,
  debugActionClear = true,
  -- DS_COMBAT
  debugCombatEvent = true,
  debugCombatFade = true,
  debugCombatStack = true,
  debugCombatTick = true,
  debugCombatDuration = true,
  debugCombatChannel = true,
  -- DS_EFFECT
  debugEffectGain = true,
  debugEffectFade = true,
  debugEffectUpdate = true,
  debugEffectRefresh = true,
  debugEffectTransfer = true,
  debugEffectMiss = true,
  -- DS_FILTER
  debugFilterAccept = true,
  debugFilterReject = true,
  -- DS_TARGET
  debugTargetTrack = true,
}

local GetGameTimeMilliseconds =GetGameTimeMilliseconds

local fStripBracket -- #(#string:origin)->(#string)
= function(origin)
  return origin:gsub("^[^<]+<%s*([^>]+)%s*>.*$","%1",1)
end

--========================================
--        l
--========================================
l.actionQueue = {} --#list<Models#Action>

l.idActionMap = {}--#map<#number,Models#Action>

l.idDurationMap = {} --#map<#number,#number>

l.idFilteringMap = {} --#map<#number,#boolean>

l.gallopAction = nil -- Models#Action

l.lastAction = nil -- Models#Action

l.lastEffectAction = nil -- Models#Action

l.lastQuickslotTime = 0 -- #number

l.ignoredCache = utils.newRecentCache(3000, 10)

l.ignoredIds = {} -- #map<#number,#boolean>

l.snActionMap = {} --#map<#number,Models#Action>

l.timeActionMap = {}--#map<#number,Models#Action>

l.targetId = nil -- #number

l.cacheOfActionMatchingAction = {} -- #map<#string:#boolean>

l.checkAbilityIdAndNameOk -- #(#number:abilityId, #string:abilityName)->(#boolean)
= function(abilityId, abilityName)
  local savedValue = l.idFilteringMap[abilityId]
  if savedValue ~= nil then return savedValue end

  -- check white list
  local keywords = l.getSavedVars().coreKeyWords:lower()
  local checked = false
  local checkOk = false
  for line in keywords:gmatch("[^\r\n]+") do
    line = line:match "^%s*(.-)%s*$"
    if line and #line>0 then
      local left,dur = line:match "^(.-)%s*=%s*(.-)$"
      if left then
        line = left
      end
      if not dur then checked = true end
      if line:match('^%d+$') then
        checkOk = tonumber(line) == abilityId
      else
        checkOk = zo_strformat("<<1>>", abilityName):lower():find(line,1,true)
      end
      if checkOk then
        if addon.debugEnabled(DSS_FILTER_ACCEPT,abilityName) then
          addon.debug('[FA]%s', left)
        end
        if dur then
          if addon.debugEnabled(DSS_FILTER_ACCEPT,abilityName) then
            addon.debug('[FA=]%s=%s', left, dur)
          end
          dur = tonumber(dur)
          if dur then
            l.idDurationMap[abilityId] = dur*1000
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
    line = line:match "^%s*(.-)%s*$"
    if line and #line>0 then
      local match = false
      if line:match('^%d+$') then
        local id = tonumber(line)
        match = id == abilityId
      else
        local name = zo_strformat("<<1>>", abilityName):lower()
        match = name:find(line,1,true)
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
addon.registerDebugSubSwitch(DS_ACTION, 'find', 'debugActionFind', 'Action Find [AF*]', 'Log action finding operations')
addon.registerDebugSubSwitch(DS_ACTION, 'new', 'debugActionNew', 'Action New [AN*]', 'Log action creation')
addon.registerDebugSubSwitch(DS_ACTION, 'match', 'debugActionMatch', 'Action Match [AM*]', 'Log action matching operations')
addon.registerDebugSubSwitch(DS_ACTION, 'unref', 'debugActionUnref', 'Action Unref [AU]', 'Log unref operations')
addon.registerDebugSubSwitch(DS_ACTION, 'stack', 'debugActionStack', 'Action Stack [AK*]', 'Log stack count updates')
addon.registerDebugSubSwitch(DS_ACTION, 'remove', 'debugActionRemove', 'Action Remove [AR*]', 'Log action removals')
addon.registerDebugSubSwitch(DS_ACTION, 'delete', 'debugActionDelete', 'Action Delete [AD*]', 'Log action deletions from maps')
addon.registerDebugSubSwitch(DS_ACTION, 'save', 'debugActionSave', 'Action Save [AS]', 'Log when actions are saved')
addon.registerDebugSubSwitch(DS_ACTION, 'clear', 'debugActionClear', 'Action Clear [AC*]', 'Log action clearing')

addon.registerDebugSwitch(DS_EFFECT, "Effect Debug")
addon.registerDebugSubSwitch(DS_EFFECT, 'gain', 'debugEffectGain', 'Effect Gain [E+]', 'Log effect gained events')
addon.registerDebugSubSwitch(DS_EFFECT, 'fade', 'debugEffectFade', 'Effect Fade [E-]', 'Log effect faded events')
addon.registerDebugSubSwitch(DS_EFFECT, 'update', 'debugEffectUpdate', 'Effect Update [E=]', 'Log effect updated events')
addon.registerDebugSubSwitch(DS_EFFECT, 'refresh', 'debugEffectRefresh', 'Effect Refresh [E*]', 'Log effect refresh events')
addon.registerDebugSubSwitch(DS_EFFECT, 'transfer', 'debugEffectTransfer')
addon.registerDebugSubSwitch(DS_EFFECT, 'miss', 'debugEffectMiss')

addon.registerDebugSwitch(DS_COMBAT, "Combat Debug")
addon.registerDebugSubSwitch(DS_COMBAT, 'event', 'debugCombatEvent', 'Combat Event [CE]', 'Log combat events')
addon.registerDebugSubSwitch(DS_COMBAT, 'fade', 'debugCombatFade', 'Combat Fade [C-]', 'Log combat fade/cancel')
addon.registerDebugSubSwitch(DS_COMBAT, 'stack', 'debugCombatStack', 'Combat Stack [CS-]', 'Log combat stack consumption')
addon.registerDebugSubSwitch(DS_COMBAT, 'tick', 'debugCombatTick', 'Combat Tick [CT]', 'Log tick effects')
addon.registerDebugSubSwitch(DS_COMBAT, 'duration', 'debugCombatDuration', 'Combat Duration [CD]', 'Log duration gained')
addon.registerDebugSubSwitch(DS_COMBAT, 'channel', 'debugCombatChannel', 'Combat Channel [CC]', 'Log channel duration')

addon.registerDebugSwitch(DS_FILTER, "Filter Debug")
addon.registerDebugSubSwitch(DS_FILTER, 'accept', 'debugFilterAccept', 'Filter Accept [FA*]', 'Log accepted effects/actions')
addon.registerDebugSubSwitch(DS_FILTER, 'reject', 'debugFilterReject', 'Filter Reject [FR*]', 'Log rejected effects/actions')

addon.registerDebugSwitch(DS_TARGET, "Target Debug")
addon.registerDebugSubSwitch(DS_TARGET, 'track', 'debugTargetTrack', 'Target Track', 'Log target tracking changes')

-- Register Core debug options for the settings menu

l.findActionByNewEffect --#(Models#Effect:effect, #boolean:stacking)->(Models#Action)
= function(effect,stacking)
  -- 0. cache to avoid repeated matching
  local notMatched = {} -- #map<#number,#bool>
  -- try last performed action
  if l.lastAction and l.lastAction.flags.forGround then
    if not notMatched[l.lastAction.sn] and l.lastAction:matchesNewEffect(effect) then
      if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
        addon.debug('[AFA]found last action by new match:%s@%.2f', l.lastAction.ability.name, l.lastAction.startTime/1000)
      end
      return l.lastAction
    end
    notMatched[l.lastAction.sn] = true
  end
  -- try last effect action
  if l.lastEffectAction and l.lastEffectAction.lastEffectTime+50>effect.startTime then
    if not notMatched[l.lastEffectAction.sn] and l.lastEffectAction.ability:matches(effect.ability,false) then
      if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
        addon.debug('[AFA]found last effect action by new match:%s@%.2f', l.lastEffectAction.ability.name, l.lastEffectAction.startTime/1000)
      end
      return l.lastEffectAction
    end
    notMatched[l.lastEffectAction.sn] = true
  end
  -- try performed actions
  for i = 1,#l.actionQueue do
    local action = l.actionQueue[i] --Models#Action
    if not notMatched[action.sn] and action:matchesNewEffect(effect) then
      if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
        addon.debug('[AFA]found one of queue by new match:%s', action:toLogString())
      end
      return action
    end
    notMatched[action.sn] = true
    if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
      addon.debug('[AFX]not found one of queue by new match:%s', action:toLogString())
    end
  end
  -- try saved actions
  for key, var in pairs(l.idActionMap) do
    local action=var --Models#Action
    if  not notMatched[action.sn] and action:matchesNewEffect(effect) then
      if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
        addon.debug('[AFA]found one of saved by new match:%s@%.2f', action.ability.name, action.startTime/1000)
      end
      return action
    end
    notMatched[action.sn] = true
    if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
      addon.debug('[AFX]not found one of saved by new match:%s@%.2f', action.ability.name, action.startTime/1000)
    end
  end
  -- try slotted actions for non minor buff effects
  if not effect.ability.icon:find('ability_buff_mi',1,true) then
    local action = l.findBarActionByNewEffect(effect, stacking)
    if action then return action end
  end
  -- not found
  if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
    addon.debug('[AF?]not found new match in %i actions, lastAction: %s, lastEffectAction: %s', #l.actionQueue, l.lastAction and l.lastAction.ability.name or 'nil',
      l.lastEffectAction and l.lastEffectAction.ability.name or 'nil')
  end
  return nil
end

l.findActionByOldEffect --#(Models#Effect:effect,#boolean:appending)->(Models#Action, #boolean)
= function(effect, appending)
  -- 1. find that existed
  for i = 1,#l.actionQueue do
    local action = l.actionQueue[i]
    if action:matchesOldEffect(effect) then
      if action.newAction then action = action:getNewest() end
      if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
        addon.debug('[AFA]found one of queue by old match:%s@%.2f', action.ability.name, action.startTime/1000)
      end
      return action
    end
  end
  for key, action in pairs(l.idActionMap) do
    if action:matchesOldEffect(effect) then
      if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
        addon.debug('[AFA]found one of saved by old match:%s@%.2f', action.ability.name, action.startTime/1000)
      end
      return action
    end
  end
  -- 2. appending
  if appending then
    for i = 1,#l.actionQueue do
      local action = l.actionQueue[i]
      if action:matchesNewEffect(effect) then
        if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
          addon.debug('[AFA]found one of queue by new match:%s@%.2f', action.ability.name, action.startTime/1000)
        end
        return action,true
      end
    end
  end
  if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
    addon.debug('[AF?]not found old match in %i actions, last:%s', #l.actionQueue, l.lastAction and l.lastAction.ability.name or 'nil')
  end
  return nil
end

l.findActionByTick --#(#number:tickEffectId, #number:unitId)->(Models#Action)
= function(tickEffectId, unitId)
  for key, action in pairs(l.idActionMap) do
    if action.tickEffect and action.tickEffect.ability.id == tickEffectId
      and action.tickEffect.unitId == unitId
    then
      if addon.debugEnabled(DSS_ACTION_FIND, action.ability.name) then
        addon.debug('[AFA]found action by tickEffectId:%s@%.2f', action.ability.name, action.startTime/1000)
      end
      return action
    end
  end
  return nil
end

l.findBarActionByNewEffect --#(Models#Effect:effect, #boolean:stacking)->(Models#Action)
= function(effect, stacking)
  -- check if it's a major buff/debuff, e.g. avoid abuse of Major Expedition or Off Balance
  if effect.ability.icon:find('ability_buff_ma',1,true) then return nil end
  if effect.ability.icon:find('ability_debuff_offb',1,true) then return nil end
  if effect.ability.icon:find('ability_rogue_030',1,true) then return nil end -- poison
  -- check if it's a potion effect
  if effect.startTime - l.lastQuickslotTime < 100 then return nil end
  -- check if it's a one word name effect e.g. burning, chilling, concussion
  -- or we are using chinese lang
  local isZh = GetCVar("language.2")=='zh'
  local checkDescription =  effect.ability.name:find(" ",1,true) or isZh
  checkDescription = checkDescription and (stacking or effect.duration >= 5000)
  --
  local matchSlotNum = nil
  local matchHotbarCategory = nil
  local currentHotbarCategory = GetActiveHotbarCategory()
  local indices = {currentHotbarCategory, HOTBAR_CATEGORY_PRIMARY, HOTBAR_CATEGORY_BACKUP}
  local isCrux =  effect.ability.icon:find("arcanist_crux",18,true)
  for i=1, 3 do
    local hotbarCategory = indices[i]
    for slotNum = 3,8 do
      local slotBoundId = GetSlotBoundId(slotNum,hotbarCategory)
      if GetSlotType(slotNum,hotbarCategory) == ACTION_TYPE_CRAFTED_ABILITY then
        slotBoundId = GetAbilityIdForCraftedAbilityId(slotBoundId)
      end
      local slotIcon = GetSlotTexture(slotNum,hotbarCategory)
      if slotBoundId >0 then
        if isCrux then
          if slotIcon:find('arcanist_002',18,true) or slotIcon:find('arcanist_003_b',18,true) then
            matchSlotNum = slotNum
            matchHotbarCategory = hotbarCategory
            break
          end
        else
          local slotName = fStripBracket(zo_strformat("<<1>>", GetSlotName(slotNum, hotbarCategory)))
          if (effect.ability.name== slotName)
            or checkDescription and zo_strformat("<<1>>", GetAbilityDescription(slotBoundId)):find(effect.ability.name,1,true)
          then
            matchSlotNum = slotNum
            matchHotbarCategory = hotbarCategory
            break
          end
        end
      end
    end
  end
  if matchSlotNum then
    local action = models.newAction(matchSlotNum,matchHotbarCategory)
    action.fake = true
    if addon.debugEnabled(DSS_ACTION_FIND, action.ability.name) then
      addon.debug('[AFA]found one by bar match:%s@%.2f', action.ability.name, action.startTime/1000)
    end
    return action
  end
  if addon.debugEnabled(DSS_ACTION_FIND, effect.ability.name) then
    addon.debug('[AF?]not found in bar actions')
  end
  return nil
end

l.getSavedVars -- #()->(#CoreSavedVars)
= function()
  return settings.getSavedVars()
end

l.getActionByAbilityId -- #(#number:abilityId)->(Models#Action)
= function(abilityId)
  local action = l.idActionMap[abilityId]
  if action then return action end
  for key, var in pairs(l.idActionMap) do
    if var:matchesAbilityId(abilityId) then return var end
  end
  return nil
end

l.getActionByAbilityName -- #(#string:abilityName, #boolean:strict)->(Models#Action)
= function(abilityName, strict)
  for id, action in pairs(l.idActionMap) do
    if action:matchesAbilityName(abilityName) then return action end
  end
  return nil
end

l.getActionByNewAction -- #(Models#Action:action)->(Models#Action)
= function(action)
  local abilityName = action.ability.name
  local matcher -- #(Models#Action:a)->(#boolean)
  = function(a)
    if a:getDuration() > 0 and a:getEndTime(false) < action.startTime then return false end
    if a.ability.id == action.ability.id then return true end
    -- check cache for non-trivial matches
    local cacheKey = a.ability.id .. '/' .. action.ability.id
    if l.cacheOfActionMatchingAction[cacheKey] then return true end
    local reverseKey = action.ability.id .. '/' .. a.ability.id
    -- i.e. Merciless Resolve name can match Assissin's Will action by its related ability list
    for key, var in ipairs(a.relatedAbilityList) do
      if abilityName:find(var.name,1,true) then
        if addon.debugEnabled(DSS_ACTION_MATCH, a.ability.name) then
          addon.debug('[AMI]related name')
        end
        l.cacheOfActionMatchingAction[cacheKey] = true
        l.cacheOfActionMatchingAction[reverseKey] = true
        return true
      end
    end
    if abilityName:find(a.ability.name,1,true) then
      l.cacheOfActionMatchingAction[cacheKey] = true
      l.cacheOfActionMatchingAction[reverseKey] = true
      return true
    end
    -- i.e. Assassin's Will name can match Merciless Resolve action by slot
    if action.hotbarCategory == a.hotbarCategory and action.slotNum == a.slotNum
      and a.inCombat and action.inCombat -- only match if both in combat (auto-swap)
    then
      if addon.debugEnabled(DSS_ACTION_MATCH, action.ability.name) then
        addon.debug('[AMI]slot')
      end
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
          if var.unitTag ~= 'player' then
            playerOnly = false
          end
        end
        if playerOnly then return a end
        return nil
      end
      return a
    end
  end
  return nil
end

l.getActionBySlot --#(#number:hotbarCategory, #number:slotNum)->(Models#Action)
= function(hotbarCategory, slotNum)
  for key, var in pairs(l.idActionMap) do
    if var.hotbarCategory == hotbarCategory and var.slotNum == slotNum then
      return var
    end
  end
  return nil
end

l.onActionSlotAbilityUsed -- #(#number:eventCode,#number:slotNum)->()
= function(eventCode,slotNum)
  -- 1. filter other actions
  if slotNum < 3 or slotNum > 8 then return end
  -- 2. create action
  local action = models.newAction(slotNum,GetActiveHotbarCategory())
  if addon.debugEnabled(DSS_ACTION_NEW, action.ability.name) then
    addon.debug('[AN]%s', action:toLogString())
  end
  if action.ability.icon:find('_curse',1,true) -- daedric curse, haunting curse, daedric prey
    or action.ability.icon:find('dark_haze',1,true) -- rune cage
    or action.ability.icon:find('dark_fog',1,true) -- rune prison
  then
    action.flags.onlyOneTarget = true
  end
  -- 3. filter by keywords
  if not l.checkAbilityIdAndNameOk(action.ability.id, action.ability.name) then
    if addon.debugEnabled(DSS_ACTION_NEW, action.ability.name) then
      addon.debug('[AN-]filtered by keywords')
    end
    return
  end

  if l.idDurationMap[action.ability.id] then
    action.configDuration = l.idDurationMap[action.ability.id]
    action.endTime = action.startTime + action.configDuration
    if addon.debugEnabled(DSS_ACTION_NEW, action.ability.name) then
      addon.debug('[AN=]modified to %d, %s', action.configDuration, action:toLogString())
    end
  end
  -- 4. queue it
  l.queueAction(action)
  -- 5. replace saved
  if not action.flags.forGround then -- ground and channel action should not inherit old action effects
    local sameNameAction = l.getActionByNewAction(action) -- Models#Action

    if not sameNameAction then
      if addon.debugEnabled(DSS_ACTION_MATCH, action.ability.name) then
        addon.debug('[AM-]none')
      end
    elseif sameNameAction.saved then
      sameNameAction = sameNameAction:getNewest()
      if addon.debugEnabled(DSS_ACTION_MATCH, sameNameAction.ability.name) then
        addon.debug('[AMA]%s', sameNameAction:toLogString())
      end
      sameNameAction.newAction = action
      action.effectList = {}
      for key, var in ipairs(sameNameAction.effectList) do
        if var.endTime> action.startTime+500 then
          var.ignored = false
          table.insert(action.effectList,var)
        end
      end
      sameNameAction.effectList = {}
      action.lastEffectTime = sameNameAction.lastEffectTime
      action.stackCount = sameNameAction.stackCount
      action.stackEffect = sameNameAction.stackEffect
      action.stackCount2 = sameNameAction.stackCount2
      action.stackEffect2 = sameNameAction.stackEffect2
      action.tickEffect = sameNameAction.tickEffect
      sameNameAction.stackEffect = nil
      action.oldAction = sameNameAction

      -- inherit fake property from ancestor to parent
      if sameNameAction.oldAction and sameNameAction.oldAction.fake then
        sameNameAction.fake = true
      end

      -- inherit duration
      if action.duration == 0 and sameNameAction.duration >0 then
        action.inheritDuration = sameNameAction.duration
      elseif action.duration == 0 and sameNameAction.inheritDuration >0 then
        action.inheritDuration = sameNameAction.inheritDuration
      end
      local abilityAccepter -- # (#Ability:relatedAbility)->()
      = function(relatedAbility)
        if not action.ability.name:find(relatedAbility.name,1,true) then
          table.insert(action.relatedAbilityList, relatedAbility)
          if addon.debugEnabled(DSS_ACTION_MATCH, action.ability.name) then
            addon.debug('[AMI]%s, total:%d', relatedAbility:toLogString(), #action.relatedAbilityList)
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
        local oldPrefix = oldId .. '/'
        local newPrefix = newId .. '/'
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
  if not action.flags.forGround -- i.e. Scalding Rune ground action should not show the timer without effect
    and
    (
    ( action.descriptionDuration and action.descriptionDuration<3000 and action.descriptionDuration>l.getSavedVars().coreMinimumDurationSeconds*1000)
    or
    (action.configDuration and action.configDuration>0)
    )

  then
    -- 6.x save short without effects
    l.saveAction(action)
  end
end

l.onActionUpdateCooldowns -- #(#number:eventCode)->()
= function(eventCode)
  local remain,duration = GetSlotCooldownInfo(GetCurrentQuickslot(),HOTBAR_CATEGORY_QUICKSLOT_WHEEL)
  if remain>1000 and duration>1000 and duration-remain<100 then
    l.lastQuickslotTime = GetGameTimeMilliseconds()
  end
end

local flags = {}
l.onCombatEvent -- #(#number:eventCode,#number:result,#boolean:isError,
--#string:abilityName,#number:abilityGraphic,#number:abilityActionSlotType,#string:sourceName,
--#number:sourceType,#string:targetName,#number:targetType,#number:hitValue,#number:powerType,
--#number:damageType,#boolean:log,#number:sourceUnitId,#number:targetUnitId,#number:abilityId,#number:overflow)->()
= function(eventCode,result,isError,abilityName,abilityGraphic,abilityActionSlotType,sourceName,sourceType,targetName,
  targetType,hitValue,powerType,damageType,log,sourceUnitId,targetUnitId,abilityId,overflow)
  local now = GetGameTimeMilliseconds()
  abilityName = zo_strformat("<<1>>", abilityName)
  if addon.debugEnabled(DSS_COMBAT_EVENT, abilityName) then
    addon.debug('[CE]|t24:24:%s|t%s(%s)@%.2f[%s]source:%s(%i:%i)target:%s(%i:%i)slot:%d,dmg:%d,overflow:%d,result:%d,power:%d,hit:%d',
      GetAbilityIcon(abilityId),
      abilityName,
      abilityId,
      now/1000,
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
    for key, var in pairs(l.idActionMap) do
      var:purgeEffectByTargetUnitId(targetUnitId)
  end
  end
  if result == ACTION_RESULT_EFFECT_FADED and abilityName~='' then --2250
    local _=nil
    if addon.debugEnabled(DSS_COMBAT_FADE, abilityName) then
      addon.debug('[C-]EFFECT_FADED,%s(%d),target:%s(%d),source:%s(%d)',
        abilityName, abilityId,targetName,targetUnitId, sourceName, sourceUnitId)
    end
    local action = l.idActionMap[abilityId]
    if action and action.channelUnitId == targetUnitId then
      if addon.debugEnabled(DSS_COMBAT_FADE, action.ability.name) then
        addon.debug('[C-]cancel channeling %s', action:toLogString())
      end
      action.channelStartTime = 0
      action.channelEndTime = 0
      if #action.effectList == 0 then
        action.endTime = now
      end
    end
    action = l.findActionByTick(abilityId, targetUnitId)
    if action and action.duration==0 then
      if addon.debugEnabled(DSS_COMBAT_FADE, action.ability.name) then
        addon.debug('[C-]cancel tick %s', action:toLogString())
      end
      l.removeAction(action)
    end
  end
end

l.onCombatEventFromPlayer -- #(#number:eventCode,#number:result,#boolean:isError,
--#string:abilityName,#number:abilityGraphic,#number:abilityActionSlotType,#string:sourceName,
--#number:sourceType,#string:targetName,#number:targetType,#number:hitValue,#number:powerType,
--#number:damageType,#boolean:log,#number:sourceUnitId,#number:targetUnitId,#number:abilityId,#number:overflow)->()
= function(eventCode,result,isError,abilityName,abilityGraphic,abilityActionSlotType,sourceName,sourceType,targetName,
  targetType,hitValue,powerType,damageType,log,sourceUnitId,targetUnitId,abilityId,overflow)
  --
  abilityName = zo_strformat("<<1>>", abilityName)
  local now = GetGameTimeMilliseconds()

  if result ~= ACTION_RESULT_EFFECT_GAINED
    and result ~= ACTION_RESULT_EFFECT_GAINED_DURATION
    and result ~= ACTION_RESULT_DAMAGE
    and result ~= ACTION_RESULT_CRITICAL_DAMAGE
  then return end

  -- filter by keywords
  if not l.checkAbilityIdAndNameOk(abilityId, abilityName) then
    return
  end

  -- handle stackCount2 consumption for triggered bonus stacks (e.g. Stone Giant, Flame Lash)
  if result == ACTION_RESULT_DAMAGE or result == ACTION_RESULT_CRITICAL_DAMAGE then
    for key, action in pairs(l.idActionMap) do
      if action.stackCount2 and action.stackCount2 > 0
        and action.stackEffect2 and action.stackEffect2.ability.id == abilityId
      then
        action.stackCount2 = action.stackCount2 - 1
        if action.stackEffect2.stackCount and action.stackEffect2.stackCount > 0 then
          action.stackEffect2.stackCount = action.stackEffect2.stackCount - 1
        end
        if addon.debugEnabled(DSS_COMBAT_STACK, action.ability.name) then
          addon.debug('[CS-]consumed %s:%d', action.ability.name, action.stackCount2)
        end
      end
    end
  end



  -- pick effect with tick rate
  if result==ACTION_RESULT_EFFECT_GAINED and sourceType==targetType and sourceUnitId == targetUnitId then
    local tickRate = GetAbilityFrequencyMS(abilityId)
    if tickRate > l.getSavedVars().coreMinimumDurationSeconds*1000 then
      local ability = models.newAbility(abilityId, abilityName, GetAbilityIcon(abilityId))
      local effect = models.newEffect(ability, 'player', sourceUnitId, now, now, 0, tickRate);
      if addon.debugEnabled(DSS_COMBAT_TICK, effect.ability.name) then
        addon.debug('[CT]%s', effect:toLogString())
      end
      local action = l.findActionByNewEffect(effect) -- Models#Action
      if action then
        action:saveEffect(effect)
        if not action.saved then
          l.saveAction(action)
          return
        end
      end
    end
    -- for not saved actions, i.e. Extended Ritual
    for key, action in pairs(l.actionQueue) do
      local abilityOnBar = models.newAbility(
        GetSlotBoundId(action.slotNum,action.hotbarCategory),
        GetSlotName(action.slotNum,action.hotbarCategory),
        GetSlotTexture(action.slotNum,action.hotbarCategory))
      if (
        action.ability.id == abilityId
        or action.ability.name == abilityName
        or abilityOnBar.id == abilityId
        or abilityOnBar.name == abilityName
        )
      then
        -- cache action matching when abilityOnBar differs from action.ability
        if abilityOnBar.id ~= action.ability.id then
          l.cacheOfActionMatchingAction[abilityOnBar.id .. '/' .. action.ability.id] = true
          l.cacheOfActionMatchingAction[action.ability.id .. '/' .. abilityOnBar.id] = true
        end
        if addon.debugEnabled(DSS_COMBAT_DURATION, abilityName) then
          df('[Activate Action] onBar: %s, inMem: %s',abilityOnBar:toLogString(), action:toLogString())
        end
        local duration = action.duration
        -- 为那些ground或者area的 action补上效果
        if not action.saved and duration > l.getSavedVars().coreMinimumDurationSeconds*1000
          and ((action.flags.forArea and now-action.startTime<2000) or action.flags.forGround ) then
          action.startTime = now
          action.endTime = now+duration
          if action.flags.forGround then
            -- record this to mark next effect as activated one
            action.groundFirstEffectId = -1
          end
          l.saveAction(action)
          return
          --
        elseif hitValue > 1 then -- hitValue如果大于1，那就是一个stack效果，匹配上就可以加上stack
          local effect = models.newEffect(abilityOnBar, 'player', sourceUnitId, now, now, hitValue, 0);
          action:updateStackInfo(hitValue,effect)
          if not action.saved then
            l.saveAction(action)
          end
        end
      end
    end
  end
  -- justify recorded actions
  if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
    local _ = nil
    if addon.debugEnabled(DSS_COMBAT_DURATION, abilityName) then
      addon.debug('[CD]%s(%d)+%d', abilityName, abilityId, hitValue)
    end
    -- for not saved actions, i.e. ground action
    for key, action in pairs(l.actionQueue) do
      local abilityOnBar = models.newAbility(
        GetSlotBoundId(action.slotNum,action.hotbarCategory),
        GetSlotName(action.slotNum,action.hotbarCategory),
        GetSlotTexture(action.slotNum,action.hotbarCategory))
      if addon.debugEnabled(DSS_COMBAT_DURATION, abilityName) then
        df('[Endure Action] onBar: %s, inMem: %s',abilityOnBar:toLogString(), action:toLogString())
      end
      if (
        action.ability.id == abilityId
        or action.ability.name == abilityName
        or abilityOnBar.id == abilityId
        or abilityOnBar.name == abilityName
        )
      then
        -- cache action matching when abilityOnBar differs from action.ability
        if abilityOnBar.id ~= action.ability.id then
          l.cacheOfActionMatchingAction[abilityOnBar.id .. '/' .. action.ability.id] = true
          l.cacheOfActionMatchingAction[action.ability.id .. '/' .. abilityOnBar.id] = true
        end
        -- 决定duration
        local duration = action.duration
        if duration == 0 and sourceType==targetType and sourceUnitId == targetUnitId
        then
          duration = hitValue
        end
        if duration > l.getSavedVars().coreMinimumDurationSeconds*1000 then -- 给的duration相对合理
          local _ = nil
          -- 对于有些地面和aoe技能没有普通effect事件所以还没存
          if  not action.saved and (
            (action.flags.forArea and now-action.startTime<2000)
            or action.flags.forGround
            ) then
            action.startTime = now
            action.endTime = now+duration
            if action.flags.forGround then
              -- record this to mark next effect as activated one
              action.groundFirstEffectId = -1
            end
            l.saveAction(action)
          end
          -- 有些action还只有纯层数，而不知道层数的期限，例如龙骑的power lash
          if action:isPureStack() then
            local effect = models.newEffect(abilityOnBar, 'player', sourceUnitId, now, now+duration, 0, 0);
            action:saveEffect(effect)
            return
          end
        end
      end
    end
    -- for saved actions, i.e. channel actions
    for key, action in pairs(l.idActionMap) do
      if action.channeled and (action.ability.id == abilityId or action.ability.name == abilityName) then
        local duration = action.duration
        if duration == 0  and sourceType==targetType and sourceUnitId == targetUnitId then
          duration = hitValue
          action.channelStartTime = now
          action.channelEndTime = now+duration
          action.channelUnitId = targetUnitId
          if addon.debugEnabled(DSS_COMBAT_CHANNEL, action.ability.name) then
            addon.debug('[CC]%s', action:toLogString())
          end
          return
        end
      end
      -- TODO if action not channeled, might need to update effect time, but this might be a duplicated action.
    end
  end
end

l.onEffectChanged -- #(#number:eventCode,#number:changeType,#number:effectSlot,#string:effectName,
-- #string:unitTag,#number:beginTimeSec,#number:endTimeSec,#number:stackCount,#string:iconName,#string:buffType,
-- #number:effectType,#number:abilityType,#number:statusEffectType,#string:unitName,
-- #number:unitId,#number:abilityId,#number:sourceType)->()
= function(eventCode,changeType,effectSlot,effectName,unitTag,beginTimeSec,endTimeSec,stackCount,iconName,buffType,
  effectType,abilityType,statusEffectType,unitName,unitId,abilityId,sourceType)
  local now = GetGameTimeMilliseconds()
  effectName = effectName:gsub('^.*< (.*) >$','%1'):gsub('%^%w','')
  -- Map changeType to subswitch and prefix
  local changeTypeMap = {
    [EFFECT_RESULT_GAINED] = {'gain','E+'},
    [EFFECT_RESULT_FADED] = {'fade','E-'},
    [EFFECT_RESULT_UPDATED] = {'update','E='},
    [EFFECT_RESULT_FULL_REFRESH] = {'refresh','E*'},
    [EFFECT_RESULT_TRANSFER] = {'transfer','E/'},
  }
  local ctInfo = changeTypeMap[changeType] or {'unknown','E?'}
  if addon.debugEnabled({DS_EFFECT, ctInfo[1]}, effectName) then
    addon.debug('[%s%s]%s(%s)@%.2f<%.2f>[%s]for %s(%i:%s),type:%d,abType:%d,seType:%d,src:%d',
      ctInfo[2],
      stackCount > 0 and tostring(stackCount) or '',
      effectName,
      abilityId,
      beginTimeSec > 0 and beginTimeSec or now/1000,
      endTimeSec-beginTimeSec,
      iconName,
      unitTag~='' and unitTag or 'none',
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
    if addon.debugEnabled(DSS_FILTER_REJECT,effectName) then
      addon.debug('[FRI]%s(%d),%s', effectName, abilityId, l.ignoredIds[abilityId])
    end
    return
  end

  if not l.checkAbilityIdAndNameOk(abilityId, effectName) then
    if addon.debugEnabled(DSS_FILTER_REJECT,effectName) then
      addon.debug('[FRB]%s', effectName)
    end
    return
  end

  local notFoundKey = ('%d:%s:not found'):format(abilityId,effectName)
  local notFoundCount = l.ignoredCache:get(notFoundKey)
  if notFoundCount>=3 then
    if addon.debugEnabled(DSS_FILTER_REJECT,effectName) then
      addon.debug('[FNC]%s', notFoundKey)
    end
    l.ignoredCache:mark(notFoundKey)
    return
  end

  local key =(changeType == EFFECT_RESULT_UPDATED) and  ('%d:%s:%d*%d:update'):format(abilityId,effectName,stackCount,unitId) or
    ('%d:%s:%d:%d*%d'):format(abilityId,effectName,changeType,stackCount, unitId)
  local numMarks = l.ignoredCache:get(key)
  l.ignoredCache:mark(key)
  --  df(' |t24:24:%s|t%s (id: %d) mark: %d',iconName, effectName,abilityId,numMarks)
  if numMarks>=12 then
    if addon.debugEnabled(DSS_FILTER_REJECT,effectName) then
      addon.debug('[FRN]%s', key)
    end
    return
  end

  -- 0. prepare
  -- ignore expedition on others
  if unitTag~='player' and iconName:find('buff_major_expedition',1,true) then return end
  local ignoredIdsConfig ={
    ['ability_mage_062']='burning effect',
    ['ability_mage_039']='blight seed',
    ['death_recap_bleed_dot']='bleed dot',
    ['ability_healer_023']='sunlight',
  }
  for key, var in pairs(ignoredIdsConfig) do
    if not l.ignoredIds[key] and iconName:find(key,1,true) then
      local info = 'ignored '..var --#string
      l.ignoredIds[key]=info
      l.ignoredIds[abilityId]=info
      return
    end
  end

  if unitTag and string.find(unitTag, 'group') then return end -- ignore effects on group members especially those same as player
  local startTime =  math.floor(beginTimeSec * 1000)
  local endTime =  math.floor(endTimeSec * 1000)
  local duration = endTime-startTime
  if duration > 150000 then return end -- ignore effects that last longer than 150 seconds
  if l.lastAction and not l.lastAction.flags.forGround and startTime and
    startTime - (l.lastAction.startTime + l.lastAction.castTime)>2000 then
    if addon.debugEnabled(DSS_ACTION_UNREF, l.lastAction.ability.name) then
      addon.debug('[AU]unref lastAction by time')
    end
    l.lastAction = nil
  end
  if l.lastEffectAction and startTime and startTime- l.lastEffectAction.lastEffectTime>50 then
    l.lastEffectAction = nil
  end
  local ability = models.newAbility(abilityId, effectName, iconName)
  local effect = models.newEffect(ability, unitTag, unitId, startTime, endTime, stackCount, 0);
  -- 1. stack
  if stackCount > 0 then -- e.g. relentless focus
    local action = nil -- Models#Action
    if changeType == EFFECT_RESULT_FADED then
      action = l.findActionByOldEffect(effect)
      if not action then
        l.ignoredCache:mark(key)
        return
      end
      local stackInfoUpdated = action:updateStackInfo(0, effect)
      local oldEffect = action:purgeEffect(effect)
      l.timeActionMap[oldEffect.startTime] = nil
      if stackInfoUpdated then
        if addon.debugEnabled(DSS_ACTION_STACK, action.ability.name) then
          addon.debug('[AKC]purged stack info %s (%s)%s', action.ability:toLogString(), action:hasEffect() and 'other effect exists' or 'no other effect',action:getEffectsInfo())
        end
        if action:getEndTime() <= now+20 and action:getStartTime()>now-500   -- action trigger effect's end i.e. Crystal Fragment/Molten Whip
          and not action.oldAction -- check those with old action i.e. Assassin Will replacing Merciless Resolve
        then
          if addon.debugEnabled(DSS_ACTION_REMOVE, action.ability.name) then
            addon.debug('[ARP]%s@%.2f~%.2f', action.ability:toLogString(), action.startTime/1000, action:getEndTime()/1000)
          end
          l.removeAction(action)
        end
      else
        if addon.debugEnabled(DSS_ACTION_STACK, action.ability.name) then
          addon.debug('[AKC]purged ignored stack info %s', action:toLogString())
        end
      end
    else
      action = l.findActionByNewEffect(effect, true)
      if not action then
        l.ignoredCache:mark(notFoundKey)
        if addon.debugEnabled(DSS_EFFECT_MATCH, effect.ability.name) then
          addon.debug('[]New stack effect action not found.')
        end
        return
      end
      if not l.checkAbilityIdAndNameOk(effect.ability.id, effect.ability.name) then
        if addon.debugEnabled(DSS_FILTER_REJECT, effect.ability.name) then
          addon.debug('[FRB]New stack effect filtered.')
        end
        return
      end
      if action.duration and action.duration > 0 then -- stackable actions with duration should ignore eso buggy effect time e.g. 20s Relentless Focus
        effect.startTime = action.startTime
        effect.duration = action.duration
        effect.endTime = action.endTime
      end
      local stackInfoUpdated = action:updateStackInfo(stackCount, effect)
      if l.getSavedVars().addonLogTrackedEffectsInChat and effect.duration>0 then
        df(' |t24:24:%s|t%s (id: %d) %ds',effect.ability.icon, effect.ability.name,effect.ability.id, effect.duration/1000)
      end
      action:saveEffect(effect)
      if stackInfoUpdated then
        if addon.debugEnabled(DSS_ACTION_STACK, action.ability.name) then
          addon.debug('[AKU]updated stack info %s', action:toLogString())
        end
        l.saveAction(action)
      else
        if addon.debugEnabled(DSS_ACTION_STACK, action.ability.name) then
          addon.debug('[AK~]updated ignored stack info %s', action:toLogString())
        end
      end
    end
    return
  end

  -- check duration
  if duration > 0 and duration < l.getSavedVars().coreMinimumDurationSeconds*1000 +100 then return end
  -- check if it's a potion effect
  if effect.startTime - l.lastQuickslotTime < 100 and iconName:find('ability_buff_m',1,true) then return end

  -- 2. gain
  if changeType == EFFECT_RESULT_GAINED then
    if duration == 0 then
      if iconName:find("ability_buff_major_evasion",1,true) then
        -- patching for major evasion's initial zero duration event which will be updated right next
        duration = 6000
        endTime = startTime+duration
      else
        if addon.debugEnabled(DSS_FILTER_REJECT, effect.ability.name) then
          addon.debug('[FR0]New effect without duration.')
        end
        --      l.ignoredIds[abilityId] = 'new effect without duration' -- NOTE: This could happen very frequently
        return
      end
    end
    if not l.checkAbilityIdAndNameOk(effect.ability.id, effect.ability.name) then
      if addon.debugEnabled(DSS_FILTER_REJECT, effect.ability.name) then
        addon.debug('[FRB]New effect filtered.')
      end
      return
    end
    local action = l.findActionByNewEffect(effect)
    if not action then
      l.ignoredCache:mark(notFoundKey)
      if addon.debugEnabled(DSS_EFFECT_MISS, effect.ability.name) then
        addon.debug('[EM?]new effect action not found')
      end
      return
    end
    -- filter debuff if a bit longer than default duration
    if l.getSavedVars().coreIgnoreLongDebuff and action.duration and action.duration >0 and effect.duration>action.duration
      and effect.ability.icon:find('ability_debuff_',1,true)
      --        and not action.descriptionNums[effect.duration/1000] -- This line should be commented out because it conflicts with option *coreIgnoreLongDebuff*
      and not action.ability.icon:find('ability_arcanist_011',1,true) -- some debuff is useful, i.e. Rune of Edric Horror has a useful vulnerability
    then
      if addon.debugEnabled(DSS_FILTER_REJECT,effect.ability.name) then
        addon.debug('[FRD]ignore longer debuff %s for %s',effect:toLogString(), action:toLogString())
      end
      return
    end
    if l.getSavedVars().addonLogTrackedEffectsInChat and effect.duration>0 then
      df(' |t24:24:%s|t%s (id: %d) %ds',effect.ability.icon, effect.ability.name,effect.ability.id, effect.duration/1000)
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
        local numBuffs = GetNumBuffs('player') -- #number
        for i = 1, numBuffs do
          local buffName,timeStarted,timeEnding,buffSlot,stackCount,iconFilename,buffType,effectType,abilityType,
            statusEffectType,abilityId,canClickOff,castByPlayer = GetUnitBuffInfo('player', i)
          if timeStarted==timeEnding and stackCount>0 then
            local startTime =  math.floor(timeStarted * 1000)
            local ability = models.newAbility(abilityId,buffName,iconFilename)
            local effect = models.newEffect(ability,'player',0,startTime,startTime,stackCount, 0)
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
                  addon.debug('[AKU]updated stack info %s', action:toLogString())
                end
              end
            end
          end
        end
      end
    end
    -- count for daedric mines
    local ofDaedricMines = iconName:find('daedric_mines',1,true)
      or (iconName:find('mage_065',1,true) and action.ability.icon:find('daedric_[mt][io][nm][eb]',1,false)) -- this icon also appears in Wall of Element, we can filter by duration
    if ofDaedricMines then ability.type = abilityType end -- record area effect for daedric mines

    return
  end
  -- 3. update
  if changeType == EFFECT_RESULT_UPDATED then
    if not l.checkAbilityIdAndNameOk(effect.ability.id, effect.ability.name) then
      if addon.debugEnabled(DSS_FILTER_REJECT, effect.ability.name) then
        addon.debug('[FRB]Update effect filtered.')
      end
      return
    end
    -- find effect strictly if without duration or is buff
    local action,isNew = l.findActionByOldEffect(effect, effect.duration>0 and not effect.ability.icon:find('ability_buff_',1,true))
    if not action then
      l.ignoredCache:mark(notFoundKey)
      if addon.debugEnabled(DSS_EFFECT_MISS, effect.ability.name) then
        addon.debug('[EM?]update effect action not found')
      end
      return
    end
    if isNew and l.getSavedVars().coreIgnoreLongDebuff and action.duration and action.duration >0 and effect.duration>action.duration
      and effect.ability.icon:find('ability_debuff_',1,true)
      and not action.ability.icon:find('ability_arcanist_011',1,true) -- some debuff is useful, i.e. Rune of Edric Horror has a useful vulnerability
    then
      if addon.debugEnabled(DSS_FILTER_REJECT,effect.ability.name) then
        addon.debug('[FRD]ignore update long debuff %s for %s',effect:toLogString(), action:toLogString())
      end
      return
    end
    if isNew and effect.duration==0 then
      if addon.debugEnabled(DSS_FILTER_REJECT,effect.ability.name) then
        addon.debug('[FR0]ignore 0ms effect %s for %s',effect:toLogString(), action:toLogString())
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
      local oldEffect = action:purgeEffect(effect)
      if oldEffect then
        local clearTimeRecord = true
        for key, var in ipairs(action.effectList) do
          if var.startTime == oldEffect.startTime then clearTimeRecord=false end
        end
        if clearTimeRecord then l.timeActionMap[oldEffect.startTime] = nil end -- don't clear time record if other effect still exist
      end
      --  action trigger effect's end i.e. Crystal Fragment/Molten Whip
      if action.oldAction and action.oldAction.fake then
        if now < action:getStartTime()+1100 then
          if addon.debugEnabled(DSS_ACTION_REMOVE, action.ability.name) then
            addon.debug('[ART]%s', action:toLogString())
          end
          l.removeAction(action)
        end
      end
      return
    end
    return
  end
end

l.onMountedStateChanged -- #(#number:eventCode,#boolean:mounted)->()
= function(eventCode,mounted)
  if mounted and l.gallopAction then
    local gallopEffect = l.gallopAction:optGallopEffect()
    if gallopEffect and gallopEffect.endTime>GetGameTimeMilliseconds() then
      l.saveAction(l.gallopAction)
      l.gallopAction = nil
    end
  end
end

l.onPlayerActivated -- #(#number:eventCode,#boolean:initial)->()
= function(eventCode,initial)
  -- check toggled actions
  local tickedActions = {} -- #list<Models#Action>
  for key,action in pairs(l.idActionMap) do
    if action.tickEffect then
      table.insert(tickedActions,action)
    end
  end
  local toggledIdInfo = {} -- #map<#number,#boolean>
  local hotbarCategory = GetActiveHotbarCategory()
  for slotNum=3, 8 do
    if IsSlotToggled(slotNum, hotbarCategory) then
      local abilityId = GetSlotBoundId(slotNum,hotbarCategory)
      if GetSlotType(slotNum,hotbarCategory) == ACTION_TYPE_CRAFTED_ABILITY then
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
end

l.onPlayerCombatState -- #(#number:eventCode,#boolean:inCombat)->()
= function(eventCode,inCombat)
  if not l.getSavedVars().coreClearWhenCombatEnd then return end
  zo_callLater(
    function()
      if not IsUnitInCombat('player') then
        for key,action in pairs(l.idActionMap) do
          l.idActionMap[key] = nil
          if addon.debugEnabled(DSS_ACTION_CLEAR) then
            addon.debug('[ACC]%s@%.2f<%.2f> %s', action.ability:toLogString(), action:getStartTime()/1000,
              action:getDuration()/1000, action:getFlagsInfo())
          end
        end
      end
    end,
    3000
  )
end

l.onReticleTargetChanged -- #(#number:eventCode)->()
= function(eventCode)
  l.targetId = nil
  if not l.getSavedVars().coreMultipleTargetTracking then return end
  if not DoesUnitExist('reticleover') then return end
  -- 1. remove all enemy actions from self.idActionMap
  local ignoredEffectIds = {}
  for key,action in pairs(l.idActionMap) do
    if addon.debugEnabled(DSS_TARGET_TRACK, action.ability.name) then
      addon.debug('[TC]processing %s,%s',action.ability.name, action.flags.onlyOneTarget and 'onlyOneTarget' or 'normal')
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
        addon.debug('[TCO]%s@%.2f<%.2f>%s', action.ability:toLogString(), action:getStartTime()/1000,
          action:getDuration()/1000, action:getFlagsInfo())
      end
    end
  end
  -- 2. scan all matched buffs
  local numBuffs = GetNumBuffs('reticleover') -- #number
  local numRestored = 0
  for i = 1, numBuffs do
    local buffName,timeStarted,timeEnding,buffSlot,stackCount,iconFilename,buffType,effectType,abilityType,
      statusEffectType,abilityId,canClickOff,castByPlayer = GetUnitBuffInfo('reticleover', i)
    if castByPlayer and not ignoredEffectIds[abilityId] and not l.ignoredIds[abilityId] then
      local startTime =  math.floor(timeStarted * 1000)
      local action = l.timeActionMap[startTime]
      if action then
        local ability = models.newAbility(abilityId,buffName,iconFilename)
        local effect = models.newEffect(ability,'none',0,startTime,startTime, 0, 0) -- only for match, no need to be precise timing
        if action:matchesOldEffect(effect) then
          action.targetOut = false
          l.idActionMap[action.ability.id] = action
          numRestored = numRestored+1
          if addon.debugEnabled(DSS_TARGET_TRACK, action.ability.name) then
            addon.debug('[TCI]%s@%.2f<%.2f>', action.ability:toLogString(), action:getStartTime()/1000, action:getDuration()/1000)
          end
          if action.flags.forEnemy and action.targetId and action.targetId>0 then
            l.targetId = action.targetId
          end
        else
          if addon.debugEnabled(DSS_TARGET_TRACK, action.ability.name) then
            addon.debug('[TCX]%s@%.2f<%.2f>', action.ability:toLogString(), action:getStartTime()/1000, action:getDuration()/1000)
          end
        end
      else
        if addon.debugEnabled(DSS_TARGET_TRACK, buffName) then
          addon.debug('[T?]%s(%i)@%.2f<%.2f> not found', buffName, abilityId, timeStarted,timeEnding-timeStarted)
        end
      end
    end
  end
end

l.onStart -- #()->()
= function()
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_ACTION_SLOT_ABILITY_USED, l.onActionSlotAbilityUsed)
  EVENT_MANAGER:RegisterForUpdate(addon.name, 100, l.onUpdate)
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_EFFECT_CHANGED, l.onEffectChanged)
  EVENT_MANAGER:AddFilterForEvent(addon.name, EVENT_EFFECT_CHANGED, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER)
  EVENT_MANAGER:RegisterForEvent(addon.name..'_pet', EVENT_EFFECT_CHANGED, l.onEffectChanged)
  EVENT_MANAGER:AddFilterForEvent(addon.name..'_pet', EVENT_EFFECT_CHANGED, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER_PET)

  EVENT_MANAGER:RegisterForEvent(addon.name..'_patch', EVENT_EFFECT_CHANGED, function(...)
    local sourceType = select(17, ... ) -- #string
    if sourceType == COMBAT_UNIT_TYPE_NONE or sourceType == COMBAT_UNIT_TYPE_TARGET_DUMMY then
      local icon = select(9, ...) -- #string
      -- patch for Force Siphon, this skill effect can only be filtered by COMBAT_UNIT_TYPE_NONE
      if icon:find('minor_lifesteal',1,true) then l.onEffectChanged(...) end
      -- patch for Restoring Aura, this skill effect can only be filtered by COMBAT_UNIT_TYPE_NONE
      if icon:find('minor_magickasteal',1,true) then l.onEffectChanged(...) end
    end
  end)


  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_COMBAT_EVENT, l.onCombatEvent  )
  EVENT_MANAGER:RegisterForEvent(addon.name..'_fromPlayer', EVENT_COMBAT_EVENT, l.onCombatEventFromPlayer  )
  EVENT_MANAGER:AddFilterForEvent(addon.name..'_fromPlayer', EVENT_COMBAT_EVENT, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER)
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_RETICLE_TARGET_CHANGED, l.onReticleTargetChanged  )
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_PLAYER_COMBAT_STATE, l.onPlayerCombatState)
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_PLAYER_ACTIVATED, l.onPlayerActivated )
  EVENT_MANAGER:RegisterForEvent(addon.name,  EVENT_ACTION_UPDATE_COOLDOWNS, l.onActionUpdateCooldowns  )
  EVENT_MANAGER:RegisterForEvent(addon.name,  EVENT_MOUNTED_STATE_CHANGED, l.onMountedStateChanged   )

end

l.lastUpdateLog = 0
l.onUpdate -- #()->()
= function()
  l.refineActions()
  addon.callExtension(m.EXTKEY_UPDATE)
  -- log
  local now = GetGameTimeMilliseconds()
  -- input: /script ActionDurationReminder.debugOnUpdate = true
  if addon.debugOnUpdate and now - l.lastUpdateLog>1000 then
    l.lastUpdateLog = now
    d('<<<<<----')
    for key, action in pairs(l.idActionMap) do
      d(key..':'..action.ability.name)
      local optEffect = action:optEffect()
      for ek, ev in ipairs(action.effectList) do
        d('effect:'..ev.ability.id..' '..ev.ability.name..', endTime-now'..(ev.endTime-now))
      end
      if optEffect then
        d('opt:'..optEffect.ability.id..', endTime-now:'..(optEffect.endTime-now))
      end
    end
    d('---->>>>')
  end
end

l.queueAction -- #(Models#Action:action)->()
= function(action)
  l.lastAction = action
  local newQueue = {} --#list<Models#Action>
  newQueue[1] = action
  local now = GetGameTimeMilliseconds()
  for key, a in ipairs(l.actionQueue) do
    if not a.newAction and now - a.startTime < 3 * 1000 then
      table.insert(newQueue,a)
    end
  end
  l.actionQueue = newQueue
end

l.refineActions -- #()->()
= function()
  local now = GetGameTimeMilliseconds()
  local endLimit = now - l.getSavedVars().coreSecondsBeforeFade * 1000
  for key,action in pairs(l.idActionMap) do
    local endTime = action:isUnlimited() and endLimit+1 or action:getEndTime()
    if action.stackCount==0 -- i.e. Grim Focus triggered by weapon attack
      and endTime < (action.fake and now or endLimit)
    then
      if addon.debugEnabled(DSS_ACTION_REMOVE, action.ability.name) then
        addon.debug('[ARR]%s,endTime:%d<endLimit:%d', action:toLogString(),
          endTime, endLimit)
      end
      l.removeAction(action)
      local gallopEffect = action:optGallopEffect()
      if gallopEffect and gallopEffect.endTime > now then l.gallopAction = action end
    end
  end
  endLimit = endLimit - 3000 -- timeActionMap remains a little longer to be found by further effect
  for key,action in pairs(l.timeActionMap) do
    if action:getEndTime() < endLimit then
      l.timeActionMap[key] = nil
      if addon.debugEnabled(DSS_ACTION_DELETE, action.ability.name) then
        addon.debug('[ADT]%s@%.2f<%i>',action.ability:toLogString(),action.startTime/1000, action:getDuration()/1000)
      end
    end
  end
end

l.removeAction -- #(Models#Action:action)->(#boolean)
= function(action)
  local removed = false
  -- remove from idActionMap
  local old = l.idActionMap[action.ability.id]
  if old and old.sn == action.sn then
    l.idActionMap[action.ability.id] = nil
    removed = true
    if addon.debugEnabled(DSS_ACTION_DELETE, action.ability.name) then
      addon.debug('[ADI]idActionMap:%s',action:toLogString())
    end
  end
  -- remove from timeActionMap
  local times = {}
  for key, var in pairs(l.timeActionMap) do
    if var.sn == action.sn then
      times[#times+1] = key
    end
  end
  for key, var in ipairs(times) do
    l.timeActionMap[var] = nil
  end
  -- remove from snActionMap
  l.snActionMap[action.sn] = nil
  -- remove fake/trigger actions from queue, otherwise next fake action will failed to recognize i.e. Crystal Fragment
  if action.oldAction and action.oldAction.fake then
    local newQueue = {} --#list<Models#Action>
    for key, a in ipairs(l.actionQueue) do
      if a.ability.id ~= action.ability.id and a.ability.id~= action.oldAction.ability.id then
        table.insert(newQueue,a)
      end
    end
    l.actionQueue = newQueue
  end
  --
  return removed
end

l.saveAction -- #(Models#Action:action)->()
= function(action)
  l.lastEffectAction = action

  -- clear same name action that can have a different id
  local sameNameAction = l.getActionByNewAction(action)
  if sameNameAction and sameNameAction.sn~=action.sn then
    l.removeAction(sameNameAction)
  end

  local old = l.idActionMap[action.ability.id]
  if old and old.sn == action.sn then old = nil end -- 没有旧的
  if old then l.removeAction(old) end

  l.idActionMap[action.ability.id] = action
  l.snActionMap[action.sn] = action
  action.saved = true
  for i, effect in ipairs(action.effectList) do
    l.timeActionMap[effect.startTime] = action
  end
  local getValueAbilityNames -- #(#map<#any,Models#Action>:t)->(#string)
  = function(t)
    local names = ''
    for key, var in pairs(t) do
      names = names..' '..var.ability:toLogString()
    end
    return names
  end
  local getKeyNames-- #(#map<#string,#any>:t)->(#string)
  = function(t)
    local names = ''
    for key, var in pairs(t) do
      names = names..' '..key
    end
    return names
  end
  if addon.debugEnabled(DSS_ACTION_SAVE,action.ability.name) then
    addon.debug('[AS]%s\n>idActionMap:%s\n>timeActionMap:%s\n>cacheOfActionMatchingAction:%s',
      action:toLogString(),
      getValueAbilityNames(l.idActionMap),
      getValueAbilityNames(l.timeActionMap),
      getKeyNames(l.cacheOfActionMatchingAction)
    )
  end
end


--========================================
--        m
--========================================
m.EXTKEY_UPDATE = "Core:update"

-- debug levels deprecated, use fine-grained settings instead

m.getActionByAbilityId = l.getActionByAbilityId -- #(#number:abilityId)->(Models#Action)

m.getActionByAbilityName = l.getActionByAbilityName-- #(#string:abilityName)->(Models#Action)

m.getActionBySlot = l.getActionBySlot-- #(#number:hotbarCategory,#number:slotNum)->(Models#Action)

m.clearActions -- #()->()
= function()
  if addon.debugEnabled(DSS_ACTION_CLEAR) then
    addon.debug('[AC]')
  end
  l.actionQueue = {}
  l.idActionMap = {}
  l.timeActionMap = {}
  l.snActionMap = {}
end
addon.clearActions = m.clearActions
addon.clear = m.clearActions

m.clearAreaActions -- #()->()
= function()
  if addon.debugEnabled(DSS_ACTION_CLEAR) then
    addon.debug('[ACA]')
  end
  local newQueue = {}
  for key, var in ipairs(l.actionQueue) do
    if not var.flags.forArea and not var.flags.forGround then table.insert(newQueue, var) end
  end
  l.actionQueue = newQueue
  local newMap = {}
  for key, var in pairs(l.idActionMap) do
    if not var.flags.forArea and not var.flags.forGround then newMap[key] = var end
  end
  l.idActionMap = newMap
  newMap = {}
  for key, var in pairs(l.timeActionMap) do
    if not var.flags.forArea and not var.flags.forGround then newMap[key] = var end
  end
  l.timeActionMap = newMap
end
addon.clearAreaActions = m.clearAreaActions

m.getIdActionMap -- #()->(#map<#number,Models#Action>)
= function()
  return l.idActionMap
end
addon.getIdActionMap = m.getIdActionMap

m.getSnActionMap -- #()->(#map<#number,Models#Action>)
= function()
  return l.snActionMap
end
addon.getSnActionMap = m.getSnActionMap

m.getTimeActionMap -- #()->(#map<#number,Models#Action>)
= function()
  return l.timeActionMap
end
addon.getTimeActionMap = m.getTimeActionMap

--========================================
--        register
--========================================
addon.register("Core#M",m)

addon.hookStart(l.onStart)

addon.extend(settings.EXTKEY_ADD_DEFAULTS, function()
  settings.addDefaults(coreSavedVarsDefaults)
end)

addon.extend(settings.EXTKEY_ADD_MENUS, function()
  settings.addMenuOptions(
    {
      type = "submenu",
      name = addon.text("Core"),
      controls = {
        {
          type = "checkbox",
          name = addon.text("Multi-Target Tracking"),
          tooltip = addon.text("Track DoT timers on multiple targets simultaneously"),
          getFunc = function() return l.getSavedVars().coreMultipleTargetTracking end,
          setFunc = function(value) l.getSavedVars().coreMultipleTargetTracking = value end,
          width = "full",
          default = coreSavedVarsDefaults.coreMultipleTargetTracking,
        },
        {
          type = "checkbox",
          name = addon.text("Preserve Timers on Target Switch"),
          tooltip = addon.text("Keep timers when switching targets (no target moment won't clear previous target's timers)"),
          getFunc = function() return l.getSavedVars().coreMultipleTargetTrackingWithoutClearing end,
          setFunc = function(value) l.getSavedVars().coreMultipleTargetTrackingWithoutClearing = value end,
          width = "full",
          default = coreSavedVarsDefaults.coreMultipleTargetTrackingWithoutClearing,
          disabled = function() return not l.getSavedVars().coreMultipleTargetTracking end,
        },
        {
          type = "checkbox",
          name = addon.text("Clear on Combat End"),
          tooltip = addon.text("Remove all timers when combat ends"),
          getFunc = function() return l.getSavedVars().coreClearWhenCombatEnd end,
          setFunc = function(value) l.getSavedVars().coreClearWhenCombatEnd = value end,
          width = "full",
          default = coreSavedVarsDefaults.coreClearWhenCombatEnd,
        },
        {
          type = "slider",
          name = addon.text("Post-Expiry Flash Duration"),
          tooltip = addon.text("Show a flashing 0.0 for this many seconds after timer expires, reminding you the skill is ready to recast"),
          min = 0, max = 10, step = 1,
          getFunc = function() return l.getSavedVars().coreSecondsBeforeFade end,
          setFunc = function(value) l.getSavedVars().coreSecondsBeforeFade = value end,
          width = "full",
          default = coreSavedVarsDefaults.coreSecondsBeforeFade,
        },
        {
          type = "slider",
          name = addon.text("Minimum Timer Duration"),
          tooltip = addon.text("Ignore effects with duration shorter than this"),
          min = 1, max = 10, step = 0.5,
          getFunc = function() return l.getSavedVars().coreMinimumDurationSeconds end,
          setFunc = function(value) l.getSavedVars().coreMinimumDurationSeconds = value end,
          width = "full",
          default = coreSavedVarsDefaults.coreMinimumDurationSeconds,
        },
        {
          type = "checkbox",
          name = addon.text("Ignore Mismatched Debuff Durations"),
          tooltip = addon.text("Use skill's own duration when debuff duration is longer (handles buggy ESO debuff times)"),
          getFunc = function() return l.getSavedVars().coreIgnoreLongDebuff end,
          setFunc = function(value) l.getSavedVars().coreIgnoreLongDebuff = value end,
          width = "full",
          default = coreSavedVarsDefaults.coreIgnoreLongDebuff,
        },
        {
          type = "editbox",
          name = addon.text("Whitelist Patterns"),
          tooltip = addon.text("Skills to always track. One pattern per line. Use skill name substring or numeric ability ID"),
          getFunc = function() return l.getSavedVars().coreKeyWords end,
          setFunc = function(text) l.getSavedVars().coreKeyWords = text l.idFilteringMap={} l.idDurationMap={} end,
          isMultiline = true,
          isExtraWide = true,
          width = "full",
          requiresReload = false,
          default = coreSavedVarsDefaults.coreKeyWords,
        },
        {
          type = "editbox",
          name = addon.text("Blacklist Patterns"),
          tooltip = addon.text("Skills to never track. One pattern per line. Use skill name substring or numeric ability ID"),
          getFunc = function() return l.getSavedVars().coreBlackKeyWords end,
          setFunc = function(text)
            l.getSavedVars().coreBlackKeyWords = text
            l.idFilteringMap = {}
          end,
          isMultiline = true,
          isExtraWide = true,
          width = "full",
          requiresReload = false,
          default = coreSavedVarsDefaults.coreBlackKeyWords,
        }
      }
    }
  )
end)
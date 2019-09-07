--========================================
--        vars
--========================================
local addon = ActionDurationReminder -- Addon#M
local settings = addon.load("Settings#M")
local models = addon.load("Models#M")
local l = {} -- #L
local m = {l=l} -- #M

-- In Game Debug Usage:
-- /script ActionDurationReminder.load('Core#M').debugLevels.action=2
-- /script ActionDurationReminder.load('Core#M').debugLevels.effect=2
-- /script ActionDurationReminder.load('Core#M').debugLevels.target=2
-- /script ActionDurationReminder.load('Core#M').debugLevels.all=2

local DS_ACTION = "action" -- debug switch for action
local DS_EFFECT = "effect" -- debug switch for effect
local DS_TARGET = "target" -- debug switch for target
local DS_ALL = "all" -- debug switch for all

local SPECIAL_ABILITY_IDS = {

    PURIFYING_LIGHT_TICK = 68581, -- ignore purifying light healing after main duration

    LIGHTINING_SPLASH = 23195, -- ignore this (n+1)s redundant effect

    HAUNTING_CURSE_1 = 24330, -- haunting curse first phase
}

---
--@type CoreSavedVars
local coreSavedVarsDefaults = {
  coreMultipleTargetTracking = true,
  coreSecondsBeforeFade = 5,
  coreMinimumDurationSeconds = 3,
  coreKeyWords = '',
  coreBlackKeyWords = '',
  coreClearWhenCombatEnd = true,
}

---
--@type WeaponPairInfo
--@field #number activeIndex
--@field #boolean ultimate

--========================================
--        l
--========================================
l.actionQueue = {} --#list<Models#Action>

l.idActionMap = {}--#map<#number,Models#Action>

l.lastAction = nil -- Models#Action
l.lastEffectAction = nil -- Models#Action

l.timeActionMap = {}--#map<#number,Models#Action>

l.weaponPairInfo -- #WeaponPairInfo
= {
  activeIndex = GetActiveWeaponPairInfo(),
  ultimate = false,
}

l.queueAction -- #(Models#Action:action)->()
= function(action)
  l.lastAction = action
  local newQueue = {} --#list<Models#Action>
  newQueue[1] = action
  for key, a in ipairs(l.actionQueue) do
    if a:getEndTime()+l.getSavedVars().coreSecondsBeforeFade*1000 > action.startTime then
      table.insert(newQueue,a)
    end
  end
  l.actionQueue = newQueue
end

l.debug -- #(#string:switch,#number:level)->(#(#string:format, #string:...)->())
=function(switch, level)
  return function(format, ...)
    if (m.debugLevels[switch] and m.debugLevels[switch]>=level) or
      (m.debugLevels[DS_ALL] and m.debugLevels[DS_ALL]>=level)
    then
      d(os.date()..'>', string.format(format, ...))
    end
  end
end

l.findActionByNewEffect --#(Models#Effect:effect)->(Models#Action)
= function(effect)
  -- try last performed action
  if l.lastAction and l.lastAction.flags.forGround then
    if l.lastAction:matchesNewEffect(effect) then
      l.debug(DS_ACTION,1)('[F]found last action by new match:%s@%.2f', l.lastAction.ability.name, l.lastAction.startTime/1000)
      return l.lastAction
    end
  end
  -- try last effect action
  if l.lastEffectAction and l.lastEffectAction.lastEffectTime+50>effect.startTime then
    if l.lastEffectAction.ability:matches(effect.ability,false) then
      l.debug(DS_ACTION,1)('[F]found last effect action by new match:%s@%.2f', l.lastEffectAction.ability.name, l.lastEffectAction.startTime/1000)
      return l.lastEffectAction
    end
  end
  -- try performed actions
  for i = 1,#l.actionQueue do
    local action = l.actionQueue[i]
    if action:matchesNewEffect(effect) then
      l.debug(DS_ACTION,1)('[F]found one by new match:%s@%.2f', action.ability.name, action.startTime/1000)
      return action
    else
      l.debug(DS_ACTION,1)('[F?]not found one by new match:%s@%.2f', action.ability.name, action.startTime/1000)
    end
  end
  -- try slotted actions
  local action = l.findBarActionByNewEffect(effect)
  if action then return action end
  -- not found
  l.debug(DS_ACTION,1)('[?]not found in %i actions, lastAction: %s, lastEffectAction: %s', #l.actionQueue, l.lastAction and l.lastAction.ability.name or 'nil',
    l.lastEffectAction and l.lastEffectAction.ability.name or 'nil')
  return nil
end

l.findActionByOldEffect --#(Models#Effect:effect)->(Models#Action)
= function(effect, oldFirst)
  -- 1. find that can
  for i = 1,#l.actionQueue do
    local action = l.actionQueue[i]
    if action:matchesOldEffect(effect) then
      if not oldFirst and action.newAction then action = action.newAction end
      l.debug(DS_ACTION,1)('[F]found one by old match:%s@%.2f', action.ability.name, action.startTime/1000)
      return action
    end
  end
  for i = 1,#l.actionQueue do
    local action = l.actionQueue[i]
    if action:matchesNewEffect(effect) then
      l.debug(DS_ACTION,1)('[F]found one by new match:%s@%.2f', action.ability.name, action.startTime/1000)
      return action
    end
  end
  l.debug(DS_ACTION,1)('[?]not found in %i actions, last:%s', #l.actionQueue, l.lastAction and l.lastAction.ability.name or 'nil')
  return nil
end

l.findBarActionByNewEffect --#(Models#Effect:effect)->(Models#Action)
= function(effect)
  local matchSlotNum = nil
  for slotNum = 3,8 do
    local slotBoundId = GetSlotBoundId(slotNum)
    if effect.ability.name:match(zo_strformat("<<1>>", GetSlotName(slotNum)),1)
      or zo_strformat("<<1>>", GetAbilityDescription(slotBoundId)):find(effect.ability.name,1,true)
    then
      matchSlotNum = slotNum
      break
    end
  end
  if matchSlotNum then
    local action = models.newAction(matchSlotNum,l.weaponPairInfo.activeIndex,l.weaponPairInfo.ultimate)
    action.fake = true
    l.debug(DS_ACTION,1)('[F]found one by bar match:%s@%.2f', action.ability.name, action.startTime/1000)
    return action
  end

  l.debug(DS_ACTION,1)('[?]not found in bar actions')
  return nil
end

l.getSavedVars -- #()->(#CoreSavedVars)
= function()
  return settings.getSavedVars()
end

l.getActionByAbilityId -- #(#number:abilityId)->(Models#Action)
= function(abilityId)
  return l.idActionMap[abilityId]
end

l.getActionByAbilityName -- #(#string:abilityName)->(Models#Action)
= function(abilityName)
  for id, action in pairs(l.idActionMap) do
    if abilityName:match(action.ability.name,1)
      -- i.e. Assassin's Will name can match Merciless Resolve action by its description
      or (abilityName:find(" ",1,true) and action.description:find(abilityName,1,true))
    then
      return action
    end
    -- i.e. Merciless Resolve name can match Assissin's Will action by its related ability list
    for key, var in ipairs(action.relatedAbilityList) do
      if abilityName:match(var.name,1) then return action end
    end
  end
  return nil
end

l.onActionSlotAbilityUsed -- #(#number:eventCode,#number:slotNum)->()
= function(eventCode,slotNum)
  -- 1. filter other actions
  if slotNum < 3 or slotNum > 8 then return end
  -- 2. create action
  local action = models.newAction(slotNum,l.weaponPairInfo.activeIndex, l.weaponPairInfo.ultimate)
  l.debug(DS_ACTION,1)('[a]%s@%.2f+%i++%.2f\n%s\n<%.2f~%.2f>', action.ability:toLogString(),
    action.startTime/1000, action.castTime, GetLatency()/1000, action:getFlagsInfo(),
    action:getStartTime()/1000, action:getEndTime()/1000)
  -- 3. filter by keywords
  local keywords = l.getSavedVars().coreKeyWords:lower()
  local checked = false
  local checkOk = false
  for line in keywords:gmatch("[^\r\n]+") do
    line = line:match "^%s*(.-)%s*$"
    if line then
      checked = true
      checkOk = action.ability.name:lower():match(line)
      if checkOk then break end
    end
  end
  if checked and not checkOk then return end
  keywords = l.getSavedVars().coreBlackKeyWords:lower()
  for line in keywords:gmatch("[^\r\n]+") do
    line = line:match "^%s*(.-)%s*$"
    if line and action.ability.name:lower():match(line) then return end
  end
  -- 3. queue it
  l.queueAction(action)
  -- 4. replace saved
  local sameNameAction = l.getActionByAbilityName(action.ability.name)
  if sameNameAction then
    sameNameAction = sameNameAction:getNewest()
    l.debug(DS_ACTION,1)('[aM]%s@%.2f\n%s\n<%.2f~%.2f>', sameNameAction.ability:toLogString(),
      sameNameAction.startTime/1000,  action:getFlagsInfo(), action:getStartTime()/1000, action:getEndTime()/1000)
    action.effectList = sameNameAction.effectList
    action.lastEffectTime = sameNameAction.lastEffectTime
    action.stackCount = sameNameAction.stackCount
    action.oldAction = sameNameAction
    local abilityAccepter -- # (#Ability:relatedAbility)->()
    = function(relatedAbility)
      if not action.ability.name:match(relatedAbility.name,1) then
        l.debug(DS_ACTION,1)('[aMs]%s', relatedAbility:toLogString())
        table.insert(action.relatedAbilityList, relatedAbility)
      end
    end
    abilityAccepter(sameNameAction.ability)
    for key, var in ipairs(sameNameAction.relatedAbilityList) do
      abilityAccepter(var)
    end
    l.saveAction(action)
  end
end

l.onActionSlotsAllHotbarsUpdated -- #(#number:eventCode)->()
= function(eventCode)
  local newPairIndex,_ = GetActiveWeaponPairInfo()
  local category = GetActiveHotbarCategory()

  if newPairIndex ~= l.weaponPairInfo.activeIndex then
    l.weaponPairInfo.activeIndex = newPairIndex
    l.weaponPairInfo.ultimate = false
  else
    l.weaponPairInfo.ultimate = category ~= HOTBAR_CATEGORY_PRIMARY and category ~= HOTBAR_CATEGORY_BACKUP
  end
end

l.onEffectChanged -- #(#number:eventCode,#number:changeType,#number:effectSlot,#string:effectName,
-- #string:unitTag,#number:beginTimeSec,#number:endTimeSec,#number:stackCount,#string:iconName,#string:buffType,
-- #number:effectType,#number:abilityType,#number:statusEffectType,#string:unitName,
-- #number:unitId,#number:abilityId,#number:sourceType)->()
= function(eventCode,changeType,effectSlot,effectName,unitTag,beginTimeSec,endTimeSec,stackCount,iconName,buffType,
  effectType,abilityType,statusEffectType,unitName,unitId,abilityId,sourceType)
  local now = GetGameTimeMilliseconds()
  l.debug(DS_EFFECT, 1)('[%s%s]%s(%s)@%.2f<%.2f>[%s] for %s(%i)',
    ({'+','-','=','*','/'})[changeType] or '?',
    stackCount > 0 and tostring(stackCount) or '',
    effectName,
    abilityId,
    beginTimeSec > 0 and beginTimeSec or now/1000,
    endTimeSec-beginTimeSec,
    iconName,
    unitTag~='' and unitTag or 'none',
    unitId
  )
  -- 0. prepare
  if abilityId == SPECIAL_ABILITY_IDS.PURIFYING_LIGHT_TICK then return end
  if abilityId == SPECIAL_ABILITY_IDS.LIGHTINING_SPLASH then return end
  if unitTag and string.find(unitTag, 'group') then return end -- ignore effects on group members especially those same as player
  local startTime =  math.floor(beginTimeSec * 1000)
  local endTime =  math.floor(endTimeSec * 1000)
  local duration = endTime-startTime
  if duration > 100000 then return end -- ignore effects that last longer than 100 seconds
  if l.lastAction and not l.lastAction.flags.forGround and startTime and
    startTime - (l.lastAction.startTime + l.lastAction.castTime)>2000 then
    l.debug(DS_ACTION,1)('[w] wipe lastAction by time')
    l.lastAction = nil
  end
  if l.lastEffectAction and startTime and startTime- l.lastEffectAction.lastEffectTime>50 then
    l.lastEffectAction = nil
  end
  local ability = models.newAbility(abilityId, effectName, iconName)
  local effect = models.newEffect(ability, unitTag, unitId, startTime, endTime);
  -- 1. stack
  if stackCount > 0 then -- e.g. relentless focus
    local action = nil -- Models#Action
    if changeType == EFFECT_RESULT_FADED then
      action = l.findActionByOldEffect(effect)
      if not action then return end
      action.stackCount = 0
      action:purgeEffect(effect)
      l.debug(DS_ACTION,1)('[cs] purged stack info %s (%s)', action.ability:toLogString(), action:hasEffect() and 'other effect exists' or 'no other effect')
      if action:getEndTime() <= now+20 then
        l.debug(DS_ACTION,1)('[P]%s@%.2f', action.ability:toLogString(), action.startTime/1000)
        if action:getStartTime()>now-500 then -- action trigger effect's end i.e. Crystal Fragment/Molten Whip
          l.removeAction(action)
        end
      end
    else
      action = l.findActionByNewEffect(effect)
      if not action then return end
      if action.duration > 0 then -- stackable actions with duration should ignore eso buggy effect time e.g. 20s Relentless Focus
        effect.startTime = action.startTime
        effect.duration = action.duration
        effect.endTime = action.endTime
      end
      action.stackCount = stackCount
      action:saveEffect(effect)
      l.debug(DS_ACTION,1)('[us] updated stack info %s (%.2f~%.2f)', action.ability:toLogString(), action:getStartTime(), action.endTime)
      l.saveAction(action)
    end
    return
  end
  if duration > 0 and duration < l.getSavedVars().coreMinimumDurationSeconds*1000 +100 then return end
  -- 2. gain
  if changeType == EFFECT_RESULT_GAINED then
    local action = l.findActionByNewEffect(effect)
    if action then
      action:saveEffect(effect)
      local weird = effect.duration == 0
      if not weird then l.saveAction(action) end
      return
    end
    l.debug(DS_EFFECT,1)('[]New effect action not found')
    return
  end
  -- 3. update
  if changeType == EFFECT_RESULT_UPDATED then
    local action = l.findActionByOldEffect(effect)
    if action then
      local old = action:saveEffect(effect)
      local weird = not old and effect.duration == 0
      if not weird then l.saveAction(action) end
      return
    end
    return
  end
  -- 4. fade
  if changeType == EFFECT_RESULT_FADED then
    local action = l.findActionByOldEffect(effect)
    if action then
      action:purgeEffect(effect)
      if action:getEndTime() <= now+20 then -- 20ms for latency maybe
        l.debug(DS_ACTION,1)('[P]%s@%.2f', action.ability:toLogString(), action.startTime/1000)
        if action:getStartTime()>now-500 then -- action trigger effect's end i.e. Crystal Fragment/Molten Whip
          l.removeAction(action)
        end
      end
      return
    end
    return
  end
end

l.onPlayerCombatState -- #(#number:eventCode,#boolean:inCombat)->()
= function(eventCode,inCombat)
  if not l.getSavedVars().coreClearWhenCombatEnd then return end
  if not inCombat then
    for key,action in pairs(l.idActionMap) do
      l.idActionMap[key] = nil
      l.debug(DS_TARGET,1)('[C!]%s@%.2f<%.2f> %s', action.ability:toLogString(), action:getStartTime()/1000,
        action:getDuration()/1000, action:getFlagsInfo())
    end
  end
end

l.onReticleTargetChanged -- #(#number:eventCode)->()
= function(eventCode)
  if not l.getSavedVars().coreMultipleTargetTracking then return end
  if not DoesUnitExist('reticleover') then return end
  -- 1. remove all non player and non playerpet effect actions from self.idActionMap
  for key,action in pairs(l.idActionMap) do
    if not action.flags.forGround and not action.flags.forArea and not action:isOnPlayer() and not action:isOnPlayerpet() then
      l.idActionMap[key] = nil
      l.debug(DS_TARGET,1)('[RC]%s@%.2f<%.2f> %s', action.ability:toLogString(), action:getStartTime()/1000,
        action:getDuration()/1000, action:getFlagsInfo())
    end
  end
  -- 2. scan all matched buffs
  local numBuffs = GetNumBuffs('reticleover')
  local numRestored = 0
  for i = 1, numBuffs do
    local buffName,timeStarted,timeEnding,buffSlot,stackCount,iconFilename,buffType,effectType,abilityType,
      statusEffectType,abilityId,canClickOff,castByPlayer = GetUnitBuffInfo('reticleover', i)
    if castByPlayer then
      local startTime =  math.floor(timeStarted * 1000)
      local action = l.timeActionMap[startTime]
      if action then
        local ability = models.newAbility(abilityId,buffName,iconFilename)
        local effect = models.newEffect(ability,'none',0,startTime,startTime) -- only for match, no need to be precise timing
        if action:matchesOldEffect(effect) then
          l.idActionMap[action.ability.id] = action
          numRestored = numRestored+1
          l.debug(DS_TARGET,1)('[VT]%s@%.2f<%.2f>', action.ability:toLogString(), action:getStartTime()/1000, action:getDuration()/1000)
        else
          l.debug(DS_TARGET,1)('[XT]%s@%.2f<%.2f>', action.ability:toLogString(), action:getStartTime()/1000, action:getDuration()/1000)
        end
      else
        l.debug(DS_TARGET, 1)('[?T]%s(%i)@%.2f<%.2f> action not found.', buffName, abilityId, timeStarted,timeEnding-timeStarted)
      end
    end
  end
end

l.onStart -- #()->()
= function()
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_ACTION_SLOT_ABILITY_USED, l.onActionSlotAbilityUsed)
  EVENT_MANAGER:RegisterForUpdate(addon.name, 100, l.onUpdate)
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_ACTION_SLOTS_ALL_HOTBARS_UPDATED, l.onActionSlotsAllHotbarsUpdated  )
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_EFFECT_CHANGED, l.onEffectChanged )
  EVENT_MANAGER:AddFilterForEvent(addon.name, EVENT_EFFECT_CHANGED, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER)
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_RETICLE_TARGET_CHANGED, l.onReticleTargetChanged  )
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_PLAYER_COMBAT_STATE, l.onPlayerCombatState)

end

l.onUpdate -- #()->()
= function()
  l.refineActions()
  addon.callExtension(m.EXTKEY_UPDATE)
end

l.refineActions -- #()->()
= function()
  local now = GetGameTimeMilliseconds()
  local endLimit = now - l.getSavedVars().coreSecondsBeforeFade * 1000
  for key,action in pairs(l.idActionMap) do
    local endTime = action:isUnlimited() and endLimit+1 or action:getEndTime()
    if endTime < (action.fake and now or endLimit) then
      l.removeAction(action)
    end
  end
  endLimit = endLimit - 3000 -- timeActionMap remains a little longer to be found by further effect
  for key,action in pairs(l.timeActionMap) do
    if action:getEndTime() < endLimit then
      l.timeActionMap[key] = nil
      l.debug(DS_ACTION, 1)('[dt]%s@%.2f<%i>',action.ability:toLogString(),action.startTime/1000, action:getDuration())
    end
  end
end

l.removeAction -- #(Models#Action:action)->(#boolean)
= function(action)
  if l.idActionMap[action.ability.id] then
    l.idActionMap[action.ability.id] = nil
    l.debug(DS_ACTION, 1)('[d]%s@%.2f~%.2f', action.ability:toLogString(), action.startTime/1000, action:getEndTime())
    return true
  end
  return false
end

l.saveAction -- #(Models#Action:action)->()
= function(action)
  l.lastEffectAction = action

  -- clear same name action that can have a different id
  local sameNameAction = l.getActionByAbilityName(action.ability.name)
  if sameNameAction then l.idActionMap[sameNameAction.ability.id] = nil end

  l.idActionMap[action.ability.id] = action
  for i, effect in ipairs(action.effectList) do
    l.timeActionMap[effect.startTime] = action
  end
  local len -- #(#map)->(#number)
  = function(t)
    local count = 0
    for key, var in pairs(t) do
      count=count+1
    end
    return count
  end
  l.debug(DS_ACTION,1)('[s]%s@%.2f,idActionMap(%i),timeActionMap(%i)', action.ability:toLogString(), action.startTime/1000,
    len(l.idActionMap),len(l.timeActionMap))
end

--========================================
--        m
--========================================
m.EXTKEY_UPDATE = "Core:update"

m.debugLevels = {} -- config by console e.g. /script ActionDurationReminder.load("Core#M").debugLevels.effect = 1

m.SPECIAL_ABILITY_IDS = SPECIAL_ABILITY_IDS

m.getActionByAbilityId = l.getActionByAbilityId -- #(#number:abilityId)->(Models#Action)

m.getActionByAbilityName = l.getActionByAbilityName-- #(#string:abilityName)->(Models#Action)

m.getIdActionMap -- #()->(#map<#number,Models#Action>)
= function()
  return l.idActionMap
end

m.getWeaponPairInfo -- #()->(#WeaponPairInfo)
= function()
  return l.weaponPairInfo
end

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
      type = "header",
      name = addon.text("Core"),
      width = "full",
    }, {
      type = "checkbox",
      name = addon.text("Multiple Target Tracking"),
      getFunc = function() return l.getSavedVars().coreMultipleTargetTracking end,
      setFunc = function(value) l.getSavedVars().coreMultipleTargetTracking = value end,
      width = "full",
      default = coreSavedVarsDefaults.coreMultipleTargetTracking,
    }, {
      type = "checkbox",
      name = addon.text("Clear When Combat End"),
      getFunc = function() return l.getSavedVars().coreClearWhenCombatEnd end,
      setFunc = function(value) l.getSavedVars().coreClearWhenCombatEnd = value end,
      width = "full",
      default = coreSavedVarsDefaults.coreClearWhenCombatEnd,
    },
    {
      type = "slider",
      name = addon.text("Seconds to Keep Timers After Timeout"),
      min = 0, max = 10, step = 1,
      getFunc = function() return l.getSavedVars().coreSecondsBeforeFade end,
      setFunc = function(value) l.getSavedVars().coreSecondsBeforeFade = value end,
      width = "full",
      default = coreSavedVarsDefaults.coreSecondsBeforeFade,
    },
    {
      type = "slider",
      name = addon.text("Seconds of Ignorable Short Timers"),
      min = 1, max = 5, step = 0.5,
      getFunc = function() return l.getSavedVars().coreMinimumDurationSeconds end,
      setFunc = function(value) l.getSavedVars().coreMinimumDurationSeconds = value end,
      width = "full",
      default = coreSavedVarsDefaults.coreMinimumDurationSeconds,
    },
    {
      type = "editbox",
      name = addon.text("Patterns of White List in line"), -- or string id or function returning a string
      getFunc = function() return l.getSavedVars().coreKeyWords end,
      setFunc = function(text) l.getSavedVars().coreKeyWords = text end,
      -- tooltip = "Editbox's tooltip text.", -- or string id or function returning a string (optional)
      isMultiline = true, --boolean (optional)
      isExtraWide = true, --boolean (optional)
      width = "full", --or "half" (optional)
      -- warning = "May cause permanent awesomeness.", -- or string id or function returning a string (optional)
      requiresReload = false, -- boolean, if set to true, the warning text will contain a notice that changes are only applied after an UI reload and any change to the value will make the "Apply Settings" button appear on the panel which will reload the UI when pressed (optional)
      default = coreSavedVarsDefaults.coreKeyWords, -- default value or function that returns the default value (optional)
    -- reference = "MyAddonEditbox" -- unique global reference to control (optional)
    },
    {
      type = "editbox",
      name = addon.text("Patterns of Black List in line"), -- or string id or function returning a string
      getFunc = function() return l.getSavedVars().coreBlackKeyWords end,
      setFunc = function(text) l.getSavedVars().coreBlackKeyWords = text end,
      -- tooltip = "Editbox's tooltip text.", -- or string id or function returning a string (optional)
      isMultiline = true, --boolean (optional)
      isExtraWide = true, --boolean (optional)
      width = "full", --or "half" (optional)
      -- warning = "May cause permanent awesomeness.", -- or string id or function returning a string (optional)
      requiresReload = false, -- boolean, if set to true, the warning text will contain a notice that changes are only applied after an UI reload and any change to the value will make the "Apply Settings" button appear on the panel which will reload the UI when pressed (optional)
      default = coreSavedVarsDefaults.coreBlackKeyWords, -- default value or function that returns the default value (optional)
    -- reference = "MyAddonEditbox" -- unique global reference to control (optional)
    }
  )
end)

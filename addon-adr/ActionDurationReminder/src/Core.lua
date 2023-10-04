--========================================
--        vars
--========================================
local addon = ActionDurationReminder -- Addon#M
local utils = addon.load("Utils#M")
local settings = addon.load("Settings#M")
local models = addon.load("Models#M")
local l = {} -- #L
local m = {l=l} -- #M

-- In Game Debug Usage:
-- /script ActionDurationReminder.debugLevels.action=2
-- /script ActionDurationReminder.debugLevels.effect=2
-- /script ActionDurationReminder.debugLevels.target=2
-- /script ActionDurationReminder.debugLevels.all=3
-- /script ActionDurationReminder.debugLevels.all=2

local DS_ACTION = "action" -- debug switch for action
local DS_EFFECT = "effect" -- debug switch for effect
local DS_TARGET = "target" -- debug switch for target
local DS_ALL = "all" -- debug switch for all

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
  coreLogTrackedEffectsInChat = false,
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

l.idFilteringMap = {} --#map<#number,#boolean>

l.gallopAction = nil -- Models#Action

l.lastAction = nil -- Models#Action

l.lastEffectAction = nil -- Models#Action

l.lastQuickslotTime = 0 -- #number

l.ignoredCache = utils.newRecentCache(1000, 10)

l.ignoredIds = {} -- #map<#number,#boolean>

l.timeActionMap = {}--#map<#number,Models#Action>

l.targetId = nil -- #number

l.queueAction -- #(Models#Action:action)->()
= function(action)
  l.lastAction = action
  local newQueue = {} --#list<Models#Action>
  newQueue[1] = action
  local now = GetGameTimeMilliseconds()
  for key, a in ipairs(l.actionQueue) do
    if not a.newAction and now < 3 * 1000 then
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

l.filterAbilityOk -- #(Models#Ability:ability)->(#boolean)
= function(ability)
  local savedValue = l.idFilteringMap[ability.id]
  if savedValue ~= nil then return savedValue end

  -- check white list
  local keywords = l.getSavedVars().coreKeyWords:lower()
  local checked = false
  local checkOk = false
  for line in keywords:gmatch("[^\r\n]+") do
    line = line:match "^%s*(.-)%s*$"
    if line and #line>0 then
      checked = true
      if line:match('%d+') then
        checkOk = tonumber(line) == ability.id
      else
        checkOk = zo_strformat("<<1>>", ability.name):lower():find(line,1,true)
      end
      if checkOk then break end
    end
  end
  if checked and not checkOk then
    l.idFilteringMap[ability.id] = false
    return false
  end
  -- check black list
  keywords = l.getSavedVars().coreBlackKeyWords:lower()
  for line in keywords:gmatch("[^\r\n]+") do
    line = line:match "^%s*(.-)%s*$"
    if line and #line>0 then
      local match = false
      if line:match('%d+') then
        local id = tonumber(line)
        match = id == ability.id
      else
        local name = zo_strformat("<<1>>", ability.name):lower()
        match = name:find(line,1,true)
      end
      if match then
        l.idFilteringMap[ability.id] = false
        return false
      end
    end
  end
  --
  l.idFilteringMap[ability.id] = true
  return true
end

l.findActionByNewEffect --#(Models#Effect:effect, #boolean:stacking)->(Models#Action)
= function(effect,stacking)
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
    local action = l.actionQueue[i] --Models#Action
    if action:matchesNewEffect(effect) then
      l.debug(DS_ACTION,1)('[F]found one of queue by new match:%s@%.2f', action.ability.name, action.startTime/1000)
      return action
    else
      l.debug(DS_ACTION,1)('[F?]not found one of queue by new match:%s@%.2f', action.ability.name, action.startTime/1000)
    end
  end
  -- try saved actions
  for key, var in pairs(l.idActionMap) do
    local action=var --Models#Action
    if action:matchesNewEffect(effect) then
      l.debug(DS_ACTION,1)('[F]found one of saved by new match:%s@%.2f', action.ability.name, action.startTime/1000)
      return action
    else
      l.debug(DS_ACTION,1)('[F?]not found one of saved by new match:%s@%.2f', action.ability.name, action.startTime/1000)
    end
  end
  -- try slotted actions for non minor buff effects
  if not effect.ability.icon:find('ability_buff_mi',1,true) then
    local action = l.findBarActionByNewEffect(effect, stacking)
    if action then return action end
  end
  -- not found
  l.debug(DS_ACTION,1)('[?]not found new match in %i actions, lastAction: %s, lastEffectAction: %s', #l.actionQueue, l.lastAction and l.lastAction.ability.name or 'nil',
    l.lastEffectAction and l.lastEffectAction.ability.name or 'nil')
  return nil
end

l.findActionByOldEffect --#(Models#Effect:effect,#boolean:appending)->(Models#Action, #boolean)
= function(effect, appending)
  -- 1. find that existed
  for i = 1,#l.actionQueue do
    local action = l.actionQueue[i]
    if action:matchesOldEffect(effect) then
      if action.newAction then action = action:getNewest() end
      l.debug(DS_ACTION,1)('[F]found one of queue by old match:%s@%.2f', action.ability.name, action.startTime/1000)
      return action
    end
  end
  for key, action in pairs(l.idActionMap) do
    if action:matchesOldEffect(effect) then
      l.debug(DS_ACTION,1)('[F]found one of saved by old match:%s@%.2f', action.ability.name, action.startTime/1000)
      return action
    end
  end
  -- 2. appending
  if appending then
    for i = 1,#l.actionQueue do
      local action = l.actionQueue[i]
      if action:matchesNewEffect(effect) then
        l.debug(DS_ACTION,1)('[F]found one of queue by new match:%s@%.2f', action.ability.name, action.startTime/1000)
        return action,true
      end
    end
  end
  l.debug(DS_ACTION,1)('[?]not found old match in %i actions, last:%s', #l.actionQueue, l.lastAction and l.lastAction.ability.name or 'nil')
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
  for i=1, 3 do
    local hotbarCategory = indices[i]
    for slotNum = 3,8 do
      local slotBoundId = GetSlotBoundId(slotNum,hotbarCategory)
      if slotBoundId >0 then
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
  if matchSlotNum then
    local action = models.newAction(matchSlotNum,matchHotbarCategory)
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
    if a.ability.id == action.ability.id then return true end
    -- i.e. Merciless Resolve name can match Assissin's Will action by its related ability list
    for key, var in ipairs(a.relatedAbilityList) do
      if abilityName:find(var.name,1,true) then
        l.debug(DS_ACTION,1)('[aM:related name]')
        return true
      end
    end
    if abilityName:find(a.ability.name,1,true) then return true end
    -- i.e. Assassin's Will name can match Merciless Resolve action by its description
    if action.hotbarCategory == a.hotbarCategory and action.slotNum == a.slotNum
      and not addon.isSimpleWord(abilityName) and a.description:find(abilityName,1,true) -- TODO test chinese version
    then
      l.debug(DS_ACTION,1)('[aM:slot]')
      return true
    end
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
      -- don't replace enemy actions, so that they can be traced seperately
      if action.flags.forEnemy then
        return nil
      end
      return a
    end
  end
  l.debug(DS_ACTION,1)('[aM:none]')
  return nil
end

l.onActionSlotAbilityUsed -- #(#number:eventCode,#number:slotNum)->()
= function(eventCode,slotNum)
  -- 1. filter other actions
  if slotNum < 3 or slotNum > 8 then return end
  -- 2. create action
  local action = models.newAction(slotNum,GetActiveHotbarCategory())
  l.debug(DS_ACTION,1)('[a]%s@%.2f+%.1f++%.2f\n%s\n<%.2f~%.2f>', action.ability:toLogString(),
    action.startTime/1000, action.castTime/1000, GetLatency()/1000, action:getFlagsInfo(),
    action:getStartTime()/1000, action:getEndTime()/1000)
  if action.ability.icon:find('_curse',1,true) -- daedric curse, haunting curse, daedric prey
    or action.ability.icon:find('dark_haze',1,true) -- rune cage
    or action.ability.icon:find('dark_fog',1,true) -- rune prison
  then
    action.flags.onlyOneTarget = true
  end
  -- 3. filter by keywords
  if not l.filterAbilityOk(action.ability) then
    l.debug(DS_EFFECT,1)('[]filtered')
    return
  end
  -- 4. queue it
  l.queueAction(action)
  -- 5. replace saved
  if not action.flags.forGround and action.channelTime==0 then -- ground and channel action should not inherit old action effects
    local sameNameAction = l.getActionByNewAction(action) -- Models#Action
    if sameNameAction and sameNameAction.saved then
      sameNameAction = sameNameAction:getNewest()
      l.debug(DS_ACTION,1)('[aM]%s@%.2f\n%s\n<%.2f~%.2f>, \nnewFlags:\n%s', sameNameAction.ability:toLogString(),
        sameNameAction.startTime/1000,  sameNameAction:getFlagsInfo(),
        sameNameAction:getStartTime()/1000, sameNameAction:getEndTime()/1000, action:getFlagsInfo())
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
      sameNameAction.stackEffect = nil
      action.oldAction = sameNameAction

      if action.duration == 0 and sameNameAction.duration >0 then
        action.inheritDuration = sameNameAction.duration
      elseif action.duration == 0 and sameNameAction.inheritDuration >0 then
        action.inheritDuration = sameNameAction.inheritDuration
      end
      local abilityAccepter -- # (#Ability:relatedAbility)->()
      = function(relatedAbility)
        if not action.ability.name:find(relatedAbility.name,1,true) then
          table.insert(action.relatedAbilityList, relatedAbility)
          l.debug(DS_ACTION,1)('[aMs]%s, total:%d', relatedAbility:toLogString(), #action.relatedAbilityList)
        end
      end
      abilityAccepter(sameNameAction.ability)
      for key, var in ipairs(sameNameAction.relatedAbilityList) do
        abilityAccepter(var)
      end
      l.saveAction(action)
    end
  end
  -- 6. save
  if not action.flags.forGround -- i.e. Scalding Rune ground action should not show the timer without effect
    and action.descriptionDuration and action.descriptionDuration<3000 and action.descriptionDuration>l.getSavedVars().coreMinimumDurationSeconds*1000 then
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
  l.debug(DS_EFFECT, 3)('[CE+]%s(%s)@%.2f[%s] source:%s(%i:%i) target:%s(%i:%i), abilityActionSlotType:%d,  damageType:%d, overflow:%d,result:%d,powerType:%d,hitvalue:%d',
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
  if result == ACTION_RESULT_DIED_XP then
    for key, var in pairs(l.idActionMap) do
      var:purgeEffectByTargetUnitId(targetUnitId)
    end
  end
  if result == ACTION_RESULT_EFFECT_FADED then
    local action = l.idActionMap[abilityId]
    if action and action.channelUnitType == targetType and action.channelUnitId == targetUnitId then
      action.endTime = now
    end
  end

end

l.onCombatEventFromPlayer -- #(#number:eventCode,#number:result,#boolean:isError,
--#string:abilityName,#number:abilityGraphic,#number:abilityActionSlotType,#string:sourceName,
--#number:sourceType,#string:targetName,#number:targetType,#number:hitValue,#number:powerType,
--#number:damageType,#boolean:log,#number:sourceUnitId,#number:targetUnitId,#number:abilityId,#number:overflow)->()
= function(eventCode,result,isError,abilityName,abilityGraphic,abilityActionSlotType,sourceName,sourceType,targetName,
  targetType,hitValue,powerType,damageType,log,sourceUnitId,targetUnitId,abilityId,overflow)
  if result ~= ACTION_RESULT_EFFECT_GAINED and result ~= ACTION_RESULT_EFFECT_GAINED_DURATION then return end
  local now = GetGameTimeMilliseconds()
  --  l.debug(DS_EFFECT, 3)('[CE+]%s(%s)@%.2f[%s] source:%s(%i:%i) target:%s(%i:%i), abilityActionSlotType:%d,  damageType:%d, overflow:%d,result:%d,powerType:%d,hitvalue:%d',
  --    abilityName,
  --    abilityId,
  --    now/1000,
  --    abilityGraphic,
  --    sourceName,
  --    sourceType,
  --    sourceUnitId,
  --    targetName,
  --    targetType,
  --    targetUnitId,
  --    abilityActionSlotType,
  --    damageType,
  --    overflow,
  --    result,
  --    powerType,
  --    hitValue
  --  )

  for key, action in pairs(l.actionQueue) do
    if not action.saved
      and (action.ability.id == abilityId or action.ability.name == abilityName)
    then
      local duration = action.duration
      -- use descript duration if action has channel time i.e. Arcanist FateCarver,
      if result == ACTION_RESULT_EFFECT_GAINED_DURATION and duration == 0 and action.channelTime>l.getSavedVars().coreMinimumDurationSeconds*1000
        and sourceType==targetType and sourceUnitId == targetUnitId
      then
        duration = hitValue
        action.channelUnitType = targetType
        action.channelUnitId = targetUnitId
      end
      --
      if  duration > l.getSavedVars().coreMinimumDurationSeconds*1000
        and ((action.flags.forArea and now-action.startTime<2000) or action.flags.forGround ) then
        action.startTime = now
        action.endTime = now+duration
        if action.flags.forGround then
          -- record this to mark next effect as activated one
          action.groundFirstEffectId = -1
        end
        l.saveAction(action)
      end
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
  l.debug(DS_EFFECT, 1)('[%s%s]%s(%s)@%.2f<%.2f>[%s] for %s(%i), effectType:%d, abilityType:%d, statusEffectType:%d',
    ({'+','-','=','*','/'})[changeType] or '?',
    stackCount > 0 and tostring(stackCount) or '',
    effectName,
    abilityId,
    beginTimeSec > 0 and beginTimeSec or now/1000,
    endTimeSec-beginTimeSec,
    iconName,
    unitTag~='' and unitTag or 'none',
    unitId,
    effectType,
    abilityType,
    statusEffectType
  )
  -- ignore rubbish effects
  if l.ignoredIds[abilityId] then
    l.debug(DS_ACTION,1)('[] '..effectName..' ignored by id:'..abilityId..', reason:'..l.ignoredIds[abilityId])
    return
  end
  local key =(changeType == EFFECT_RESULT_UPDATED) and  ('%d:%s:update'):format(abilityId,effectName) or ('%d:%s:%d:%d'):format(abilityId,effectName,changeType,stackCount)
  local numMarks = l.ignoredCache:get(key)
  --  df(' |t24:24:%s|t%s (id: %d) mark: %d',iconName, effectName,abilityId,numMarks)
  if numMarks>=4 then
    l.debug(DS_ACTION,1)('[] '..key..' ignored by cache counted '..numMarks)
    return
  end
  l.ignoredCache:mark(key)

  -- 0. prepare
  -- ignore expedition on others
  if unitTag~='player' and iconName:find('buff_major_expedition',1,true) then return end
  local ignoredIdsConfig ={
    ['ability_mage_062']='burning effect',
    ['ability_mage_039']='blight seed',
    ['arcanist_crux']='arcanist crux',
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
    l.debug(DS_ACTION,1)('[u] unref lastAction by time')
    l.lastAction = nil
  end
  if l.lastEffectAction and startTime and startTime- l.lastEffectAction.lastEffectTime>50 then
    l.lastEffectAction = nil
  end
  local ability = models.newAbility(abilityId, effectName, iconName)
  local effect = models.newEffect(ability, unitTag, unitId, startTime, endTime, stackCount);
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
        l.debug(DS_ACTION,1)('[cs] purged stack info %s (%s)%s', action.ability:toLogString(), action:hasEffect() and 'other effect exists' or 'no other effect',action:getEffectsInfo())
        if action:getEndTime() <= now+20 and action:getStartTime()>now-500   -- action trigger effect's end i.e. Crystal Fragment/Molten Whip
          and not action.oldAction -- check those with old action i.e. Assassin Will replacing Merciless Resolve
        then
          l.debug(DS_ACTION,1)('[P]%s@%.2f~%.2f', action.ability:toLogString(), action.startTime/1000, action:getEndTime()/1000)
          l.removeAction(action)
        end
      else
        l.debug(DS_ACTION,1)('[cs] purged ignored stack info %s (%s)', action.ability:toLogString(), action:hasEffect() and 'other effect exists' or 'no other effect')
      end
    else
      action = l.findActionByNewEffect(effect, true)
      if not action then
        l.ignoredCache:mark(key)
        l.debug(DS_EFFECT,1)('[]New stack effect action not found.')
        return
      end
      if not l.filterAbilityOk(effect.ability) then
        l.debug(DS_EFFECT,1)('[]New stack effect filtered.')
        return
      end
      if action.duration and action.duration > 0 then -- stackable actions with duration should ignore eso buggy effect time e.g. 20s Relentless Focus
        effect.startTime = action.startTime
        effect.duration = action.duration
        effect.endTime = action.endTime
      end
      local stackInfoUpdated = action:updateStackInfo(stackCount, effect)
      if l.getSavedVars().coreLogTrackedEffectsInChat and effect.duration>0 then
        df(' |t24:24:%s|t%s (id: %d) %ds',effect.ability.icon, effect.ability.name,effect.ability.id, effect.duration/1000)
      end
      action:saveEffect(effect)
      if stackInfoUpdated then
        l.debug(DS_ACTION,1)('[us] updated stack info %s', action:toLogString())
        l.saveAction(action)
      else
        l.debug(DS_ACTION,1)('[us] updated ignored stack info %s', action:toLogString())
      end
    end
    return
  end
  if duration > 0 and duration < l.getSavedVars().coreMinimumDurationSeconds*1000 +100 then return end
  -- 2. gain
  if changeType == EFFECT_RESULT_GAINED then
    if duration == 0 then
      l.debug(DS_EFFECT,1)('[]New effect without duration ignored.')
      --      l.ignoredIds[abilityId] = 'new effect without duration' -- NOTE: This could happen very frequently
      return
    end
    if not l.filterAbilityOk(effect.ability) then
      l.debug(DS_EFFECT,1)('[]New effect filtered.')
      return
    end
    local action = l.findActionByNewEffect(effect)
    if action then
      -- filter debuff if a bit longer than default duration
      if l.getSavedVars().coreIgnoreLongDebuff and action.duration and action.duration >0 and effect.duration>action.duration
        and effect.ability.icon:find('ability_debuff_',1,true)
--        and not action.descriptionNums[effect.duration/1000] -- This line should be commented out because it conflicts with option *coreIgnoreLongDebuff* 
        and effect.duration < 15000 -- some longer debuff is useful, i.e. Rune of Edric Horror has a 20sec duration need to be tracked
      then
        l.debug(DS_ACTION,1)('[!] ignore a bit longer debuff %s for %s',effect:toLogString(), action:toLogString())
        for key, effect in ipairs(action.effectList) do
          l.debug(DS_ACTION,1)('[+--e:]%s', effect:toLogString())
        end
        return
      end
      if l.getSavedVars().coreLogTrackedEffectsInChat and effect.duration>0 then
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
              local effect = models.newEffect(ability,'player',0,startTime,startTime,stackCount)
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
                  l.debug(DS_ACTION,1)('[us] updated stack info %s', action:toLogString())
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
    l.debug(DS_EFFECT,1)('[]New effect action not found')
    return
  end
  -- 3. update
  if changeType == EFFECT_RESULT_UPDATED then
    if not l.filterAbilityOk(effect.ability) then
      l.debug(DS_EFFECT,1)('[]Update effect filtered.')
      return
    end
    local action,isNew = l.findActionByOldEffect(effect, effect.duration>0)
    if action then
      if isNew and l.getSavedVars().coreIgnoreLongDebuff and action.duration and action.duration >0 and effect.duration>action.duration
        and effect.ability.icon:find('ability_debuff_',1,true)
      then
        l.debug(DS_ACTION,1)('[!] ignore newly update long debuff %s for %s',effect:toLogString(), action:toLogString())
        for key, effect in ipairs(action.effectList) do
          l.debug(DS_ACTION,1)('[+--e:]%s', effect:toLogString())
        end
        return
      end
      if isNew and effect.duration==0 then
        l.debug(DS_ACTION,1)('[!] ignore 0ms newly update effect %s for %s',effect:toLogString(), action:toLogString())
        return
      end
      action:saveEffect(effect)
      l.saveAction(action)
      return
    end
    return
  end
  -- 4. fade
  if changeType == EFFECT_RESULT_FADED then
    local action = l.findActionByOldEffect(effect)
    if action then
      local oldEffect = action:purgeEffect(effect)
      local clearTimeRecord = true
      for key, var in ipairs(action.effectList) do
        if var.startTime == oldEffect.startTime then clearTimeRecord=false end
      end
      if clearTimeRecord then l.timeActionMap[oldEffect.startTime] = nil end -- don't clear time record if other effect still there
      --  action trigger effect's end i.e. Crystal Fragment/Molten Whip
      if action.oldAction and action.oldAction.fake and action:getEndTime() <= now+20 and  action:getStartTime()>now-500 then
        l.debug(DS_ACTION,1)('[trg]%s', action:toLogString())
        l.removeAction(action)
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
end

l.onPlayerCombatState -- #(#number:eventCode,#boolean:inCombat)->()
= function(eventCode,inCombat)
  if not l.getSavedVars().coreClearWhenCombatEnd then return end
  zo_callLater(
    function()
      if not IsUnitInCombat('player') then
        for key,action in pairs(l.idActionMap) do
          l.idActionMap[key] = nil
          l.debug(DS_TARGET,1)('[C!]%s@%.2f<%.2f> %s', action.ability:toLogString(), action:getStartTime()/1000,
            action:getDuration()/1000, action:getFlagsInfo())
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
    l.debug(DS_TARGET,1)('processing action %s, %s',action.ability.name, action.flags.onlyOneTarget and 'onlyOneTarget' or 'normal')
    if action.flags.onlyOneTarget then -- e.g. daedric curse, rune cage,  we do not switch on target changing
      for i, effect in ipairs(action.effectList) do
        ignoredEffectIds[effect.ability.id] = true
    end
    elseif action.flags.forEnemy then
      action.targetOut = true
      if not l.getSavedVars().coreMultipleTargetTrackingWithoutClearing then
        l.idActionMap[key] = nil
      end
      l.debug(DS_TARGET,1)('[Tgt out]%s@%.2f<%.2f> %s', action.ability:toLogString(), action:getStartTime()/1000,
        action:getDuration()/1000, action:getFlagsInfo())
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
        local effect = models.newEffect(ability,'none',0,startTime,startTime,0) -- only for match, no need to be precise timing
        if action:matchesOldEffect(effect) then
          action.targetOut = false
          l.idActionMap[action.ability.id] = action
          numRestored = numRestored+1
          l.debug(DS_TARGET,1)('[Tgt in]%s@%.2f<%.2f>', action.ability:toLogString(), action:getStartTime()/1000, action:getDuration()/1000)
          if action.flags.forEnemy and action.targetId and action.targetId>0 then
            l.targetId = action.targetId
          end
        else
          l.debug(DS_TARGET,1)('[Tgt xx]%s@%.2f<%.2f>', action.ability:toLogString(), action:getStartTime()/1000, action:getDuration()/1000)
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
  EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_EFFECT_CHANGED, l.onEffectChanged)
  EVENT_MANAGER:AddFilterForEvent(addon.name, EVENT_EFFECT_CHANGED, REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER)

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

l.refineActions -- #()->()
= function()
  local now = GetGameTimeMilliseconds()
  local endLimit = now - l.getSavedVars().coreSecondsBeforeFade * 1000
  for key,action in pairs(l.idActionMap) do
    local endTime = action:isUnlimited() and endLimit+1 or action:getEndTime()
    if action.stackCount==0 -- i.e. Grim Focus triggered by weapon attack
      and endTime < (action.fake and now or endLimit)
    then
      l.debug(DS_ACTION,1)('[dr]%s, endTime:%d < endLimit:%d', action:toLogString(),
        endTime, endLimit)
      l.removeAction(action)
      local gallopEffect = action:optGallopEffect()
      if gallopEffect and gallopEffect.endTime > now then l.gallopAction = action end
    end
  end
  endLimit = endLimit - 3000 -- timeActionMap remains a little longer to be found by further effect
  for key,action in pairs(l.timeActionMap) do
    if action:getEndTime() < endLimit then
      l.timeActionMap[key] = nil
      l.debug(DS_ACTION, 1)('[dt]%s@%.2f<%i>',action.ability:toLogString(),action.startTime/1000, action:getDuration()/1000)
    end
  end
end

l.removeAction -- #(Models#Action:action)->(#boolean)
= function(action)
  local removed = false
  -- remove from idActionMap
  if l.idActionMap[action.ability.id] then
    l.idActionMap[action.ability.id] = nil
    removed = true
    l.debug(DS_ACTION, 1)('[d]%s@%.2f<%i>',action.ability:toLogString(),action.startTime/1000, action:getDuration()/1000)
  end
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
  if sameNameAction then l.idActionMap[sameNameAction.ability.id] = nil end

  l.idActionMap[action.ability.id] = action
  action.saved = true
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
  l.debug(DS_ACTION,1)('[s]%s,idActionMap(%i),timeActionMap(%i),#effectList:%d', action:toLogString(),
    len(l.idActionMap),len(l.timeActionMap), #action.effectList)
  for key, effect in ipairs(action.effectList) do
    l.debug(DS_ACTION,1)('[+--e:]%s', effect:toLogString())
  end
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


--========================================
--        m
--========================================
m.EXTKEY_UPDATE = "Core:update"

m.debugLevels = {} -- config by console e.g. /script ActionDurationReminder.load("Core#M").debugLevels.effect = 1
addon.debugLevels = m.debugLevels

m.getActionByAbilityId = l.getActionByAbilityId -- #(#number:abilityId)->(Models#Action)

m.getActionByAbilityName = l.getActionByAbilityName-- #(#string:abilityName)->(Models#Action)

m.getActionBySlot = l.getActionBySlot-- #(#number:hotbarCategory,#number:slotNum)->(Models#Action)

m.clearActions -- #()->()
= function()
  l.debug(DS_ACTION, 1)('[clear]')
  l.actionQueue = {}
  l.idActionMap = {}
  l.timeActionMap = {}
end
addon.clearActions = m.clearActions

m.clearAreaActions -- #()->()
= function()
  l.debug(DS_ACTION, 1)('[clear area]')
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

m.debug
= function() --#()->()
  for key, var in pairs(l.idActionMap) do
    df('%s(%d)@%d:%s',var.ability.name,var.ability.id,var.startTime,var:getEffectsInfo())
end
end
addon.debug = m.debug

m.getIdActionMap -- #()->(#map<#number,Models#Action>)
= function()
  return l.idActionMap
end
addon.getIdActionMap = m.getIdActionMap

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
      type = "checkbox",
      name = addon.text("Log Tracked Effects In Chat"),
      getFunc = function() return l.getSavedVars().coreLogTrackedEffectsInChat end,
      setFunc = function(value) l.getSavedVars().coreLogTrackedEffectsInChat = value end,
      width = "full",
      default = coreSavedVarsDefaults.coreLogTrackedEffectsInChat,
    }
  )
  settings.addMenuOptions(
    {
      type = "submenu",
      name = addon.text("Core"),
      controls = {
        {
          type = "checkbox",
          name = addon.text("Multiple Target Tracking"),
          getFunc = function() return l.getSavedVars().coreMultipleTargetTracking end,
          setFunc = function(value) l.getSavedVars().coreMultipleTargetTracking = value end,
          width = "full",
          default = coreSavedVarsDefaults.coreMultipleTargetTracking,
        },
        {
          type = "checkbox",
          name = addon.text("Multiple Target Tracking Without Clearing"),
          getFunc = function() return l.getSavedVars().coreMultipleTargetTrackingWithoutClearing end,
          setFunc = function(value) l.getSavedVars().coreMultipleTargetTrackingWithoutClearing = value end,
          width = "full",
          default = coreSavedVarsDefaults.coreMultipleTargetTrackingWithoutClearing,
          disabled = function() return not l.getSavedVars().coreMultipleTargetTracking end,
        },
        {
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
          min = 1, max = 10, step = 0.5,
          getFunc = function() return l.getSavedVars().coreMinimumDurationSeconds end,
          setFunc = function(value) l.getSavedVars().coreMinimumDurationSeconds = value end,
          width = "full",
          default = coreSavedVarsDefaults.coreMinimumDurationSeconds,
        },
        {
          type = "checkbox",
          name = addon.text("Ignore Debuff Timers If Longer Than Skill's"),
          getFunc = function() return l.getSavedVars().coreIgnoreLongDebuff end,
          setFunc = function(value) l.getSavedVars().coreIgnoreLongDebuff = value end,
          width = "full",
          default = coreSavedVarsDefaults.coreIgnoreLongDebuff,
        },
        {
          type = "editbox",
          name = addon.text("Patterns of White List in line"), -- or string id or function returning a string
          getFunc = function() return l.getSavedVars().coreKeyWords end,
          setFunc = function(text) l.getSavedVars().coreKeyWords = text l.idFilteringMap={} end,
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
          setFunc = function(text) l.getSavedVars().coreBlackKeyWords = text l.idFilteringMap={} end,
          -- tooltip = "Editbox's tooltip text.", -- or string id or function returning a string (optional)
          isMultiline = true, --boolean (optional)
          isExtraWide = true, --boolean (optional)
          width = "full", --or "half" (optional)
          -- warning = "May cause permanent awesomeness.", -- or string id or function returning a string (optional)
          requiresReload = false, -- boolean, if set to true, the warning text will contain a notice that changes are only applied after an UI reload and any change to the value will make the "Apply Settings" button appear on the panel which will reload the UI when pressed (optional)
          default = coreSavedVarsDefaults.coreBlackKeyWords, -- default value or function that returns the default value (optional)
        -- reference = "MyAddonEditbox" -- unique global reference to control (optional)
        }
      }
    }
  )
end)

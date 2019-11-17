--========================================
--        vars
--========================================
local addon = ActionDurationReminder -- Addon#M
local m = {} -- #M
local mAction = {} -- #Action
local mAbility = {} -- #Ability
local mEffect = {} -- #Effect

local SPECIAL_ABILITY_IDS = {
  TAUNT = 38541,
}

local fRefinePath -- #(#string:path)->(#string)
= function(path)
  if not path then return path end
  path = path:lower()
  local index = path:find(".dds",1,true)
  if index and index>1 then
    path = path:sub(1,index-1)
  end
  return path
end

local fMatchIconPath -- #(#string:path1,#string:path2)->(#boolean)
= function(path1, path2)
  if path1=='' or path1=='/' or path2=='' or path2=='/' then return false end
  if path1 == path2 then return true end -- fast check
  path1 = fRefinePath(path1)
  path2 = fRefinePath(path2)
  return path1:find(path2,1,true) or path2:find(path1,1,true)
end

local fStripBracket -- #(#string:origin)->(#string)
= function(origin)
  return origin:gsub("^[^<]+<%s*([^>]+)%s*>.*$","%1",1)
end

--========================================
--        m
--========================================
m.newAbility -- #(#number:id, #string:name, #string:icon)->(#Ability)
= function(id, name, icon)
  local ability = {} -- #Ability
  local getIconPath -- #(#string:icon)->(#string)
  = function(icon)
    return icon:sub(1,1)=='/' and icon or ('/'..icon)
  end
  icon = getIconPath(icon)
  ability.id = id -- #number
  ability.name = zo_strformat("<<1>>", name) --#string
  ability.icon = icon -- #string
  local icon2 = getIconPath(GetAbilityIcon(id))
  if icon2 ~= icon then
    ability.icon2 = icon2 -- #string
  end
  local hasProgression,progressionIndex = GetAbilityProgressionXPInfoFromAbilityId(id)
  ability.progressionName = hasProgression and GetAbilityProgressionInfo(progressionIndex) or nil
  if ability.progressionName and ability.progressionName ~= name then
    ability.progressionName =  zo_strformat("<<1>>", ability.progressionName)
  else
    ability.progressionName = nil
  end -- only keep different name
  ability.description = zo_strformat("<<1>>", GetAbilityDescription(id)) -- #string
  setmetatable(ability,{__index=mAbility})
  return ability
end


m.newAction -- #(#number:slotNum,#number:weaponPairIndex,#boolean:weaponPairUltimate)->(#Action)
= function(slotNum, weaponPairIndex, weaponPairUltimate)
  local action = {} -- #Action
  action.fake = false
  action.slotNum = slotNum --#number
  action.ability = m.newAbility(GetSlotBoundId(slotNum),fStripBracket(GetSlotName(slotNum)),GetSlotTexture(slotNum)) -- #Ability
  action.relatedAbilityList = {} --#list<#Ability> for matching
  local channeled,castTime,channelTime = GetAbilityCastInfo(action.ability.id)
  action.castTime = castTime or 0 --#number
  action.startTime = GetGameTimeMilliseconds() --#number
  action.duration = GetAbilityDuration(action.ability.id) --#number
  action.description = zo_strformat("<<1>>", GetAbilityDescription(action.ability.id)) --#string
  action.endTime = action.duration==0 and 0 or action.startTime + action.duration--#number
  action.lastEffectTime = 0 --#number
  action.oldAction = nil --#Action
  action.newAction = nil --#Action

  action.weaponPairIndex = weaponPairIndex --#number
  action.weaponPairUltimate = weaponPairUltimate --#boolean
  local target = GetAbilityTargetDescription(action.ability.id)
  local forArea = target==GetString(SI_ABILITY_TOOLTIP_TARGET_TYPE_AREA)
  local forGround = target==GetString(SI_ABILITY_TOOLTIP_TARGET_TYPE_GROUND)
  local forSelf = target== GetString(SI_ABILITY_TOOLTIP_RANGE_SELF)
  local forTank = GetAbilityRoles(action.ability.id)
  ---
  --@type ActionFlags
  action.flags
  = {
    forArea -- #boolean
    = forArea,
    forGround -- #boolean
    = forGround,
    forSelf -- #boolean
    = forSelf,
    forTank -- #boolean
    = forTank,
    shifted -- #boolean
    = false,
  }
  action.data = {} -- #table to store data in
  action.effectList = {} -- #list<#Effect>
  action.stackCount = 0
  setmetatable(action,{__index=mAction})
  return action
end

m.newEffect -- #(#Ability:ability, #string:unitTag, #number:unitId, #number:startTime, #number:endTime)->(#Effect)
=  function(ability, unitTag, unitId, startTime, endTime)
  local effect = {} -- #Effect
  effect.ability = ability --#Ability
  effect.unitTag = unitTag:find('player',1,true) and unitTag or 'others' -- #string player or playerpet or others
  effect.unitId = unitId -- #number
  effect.startTime = startTime -- #number
  effect.endTime = endTime -- #number
  effect.duration = endTime-startTime -- #number
  setmetatable(effect,{__index=mEffect})
  return effect
end

--========================================
--        mAbility
--========================================
mAbility.matches -- #(#Ability:self, #Ability:other, #boolean:strict)->(#boolean)
= function(self, other, strict)
  local matches = function(s1,s2) -- #(#string:s1,#string:s2)->(#boolean)
    if s1=='' or s2=='' then return false end
    if s1 == s2 then return true end
    if s1:find(s2, 1,true) or s2:find(s1, 1,true) then return true end
    
    return false
  end
  if self.id==other.id then return true end
  if fMatchIconPath(self.icon, other.icon) then return true end
  if other.icon2  then
    if  fMatchIconPath(self.icon, other.icon2) then return true end
  end
  if matches(self.name , other.name) then return true end
  if self.progressionName and matches(self.progressionName, other.name) then return true end
  if not strict
    and not addon.isSimpleWord(other.name) -- do not match a one word name in description
    and self.description
  then
    if matches(self.description, other.name) then return true end
    if self.description:find(other.name:gsub(" "," %%w+ %%w+ ")) then return true end -- i.e. match major sorcery in critical surge description: major brutality and sorcery
  end
  return false
end

mAbility.toLogString --#(#Ability:self)->(#string)
= function(self)
  return string.format("%s(%i)[%s]", self.name, self.id, self.icon)
end

--========================================
--        mAction
--========================================
mAction.getDuration -- #(#Action:self)->(#number)
= function(self)
  local optEffect = self:optEffect() -- #Effect
  return optEffect and optEffect.duration or self.duration
end

mAction.getEndTime -- #(#Action:self)->(#number)
= function(self)
  local optEffect = self:optEffect() -- #Effect
  return optEffect and optEffect.endTime or (self.endTime>0 and self.endTime or self.startTime)
end

mAction.getFlagsInfo -- #(#Action:self)->(#string)
= function(self)
  return string.format('forArea:%s,forGround:%s,forSelf:%s,forTank:%s',
    tostring(self.flags.forArea),
    tostring(self.flags.forGround),
    tostring(self.flags.forSelf),
    tostring(self.flags.forTank))
end

mAction.getNewest -- #(#Action:self)->(#Action)
= function(self)
  local walker = self
  while walker.newAction do
    walker = walker.newAction
  end
  return walker
end

mAction.getOldest -- #(#Action:self)->(#Action)
= function(self)
  local walker = self
  while walker.oldAction do
    walker = walker.oldAction
  end
  return walker
end

mAction.getStageInfo -- #(#Action:self)->(#string)
= function(self)
  local optEffect = self:optEffect()
  if not optEffect or not self.duration
  then
    return nil
  end
  -- 1/2 by same id, same start and <4/7 duration
  if optEffect.ability.id==self.ability.id
    and math.abs(optEffect.startTime-self.startTime)< 500
    and optEffect.duration * 7 < self.duration*4
  then
    return '1/2'
  end
  -- 1/2 by normal effect with long duration effect present
  local longDurationEffect = self:peekLongDurationEffect() -- #Effect
  if self.flags.forArea
    and not optEffect:isLongDuration()
    and longDurationEffect
  then
    self.data.firstStageId = optEffect.ability.id -- #number
    return '1/2'
  end
  -- 2/2 by same end and >2/5 duration and <4/5 duration
  if math.abs(optEffect.endTime-self.startTime-self.duration)<700 then
    if optEffect.duration*5 > self.duration *2 then
      if optEffect.duration*5 < self.duration *4 then
        return '2/2'
      end
    end
  end
  -- 2/2 by normal effect with firstStagedId and without long duration effect present
  if self.flags.forArea and self.data.firstStageId
    and self.data.firstStageId ~= optEffect.ability.id
    and not longDurationEffect
  then
    return '2/2'
  end
  return nil
end

mAction.getStartTime -- #(#Action:self)->(#number)
= function(self)
  local optEffect = self:optEffect()
  return optEffect and optEffect.startTime or self.startTime
end

mAction.hasEffect -- #(#Action:self)->(#boolean)
= function(self)
  return #self.effectList >0
end

mAction.isOnPlayer -- #(#Action:self)->(#boolean)
= function(self)
  if self.flags.forSelf then return true end
  for i, effect in ipairs(self.effectList) do
    if effect:isOnPlayer() then return true end
  end
  return false
end

mAction.isOnPlayerpet -- #(#Action:self)->(#boolean)
= function(self)
  if self.flags.forSelf then return true end
  for i, effect in ipairs(self.effectList) do
    if effect:isOnPlayerpet() then return true end
  end
  return false
end

mAction.isUnlimited -- #(#Action:self)->(#boolean)
= function(self)
  local optEffect = self:optEffect()
  return self.duration==0 and optEffect and optEffect.duration==0 and self.stackCount>0
end

mAction.matchesAbility -- #(#Action:self,#Ability:ability, #boolean:strict)->(#boolean)
= function(self, ability, strict)
  if self.ability:matches(ability, strict) then return true end
  -- check related
  for key, var in ipairs(self.relatedAbilityList) do
    local a = var -- #Ability
    if a:matches(ability, strict) then return true end
  end
end

mAction.matchesNewEffect -- #(#Action:self,#Effect:effect)->(#boolean)
= function(self, effect)
  -- 0. filter ended action
  if not self.flags.forGround and self.endTime > self.startTime and self.endTime + 300 < effect.startTime then
    return false
  end
  -- 1. taunt
  if effect.ability.id == SPECIAL_ABILITY_IDS.TAUNT and self.flags.forTank then
    return true
  end
  -- 2. fast check already matched effects
  local strict = effect.startTime > self.startTime + self.castTime + 2000
  strict = strict or (effect.duration>0 and effect.duration<5000)
  for i, var in ipairs(self.effectList) do
    local e = var --#Effect
    if effect.ability.id == e.ability.id then return true end
    -- already some recent and dalayed effect counted
    if e.startTime>=self.startTime and effect.startTime > e.startTime then strict = true end
  end
  -- 3. check ability match
  if self:matchesAbility(effect.ability, strict) then return true end
  --
  return false
end

mAction.matchesOldEffect -- #(#Action:self,#Effect:effect)->(#boolean)
= function(self, effect)
  -- 1. taunt
  if effect.ability.id==SPECIAL_ABILITY_IDS.TAUNT and self.flags.forTank then
    return true
  end
  -- 2. fast check already matched effects
  for i, e in ipairs(self.effectList) do
    if e.ability.id == effect.ability.id and (e.unitId == effect.unitId or effect.unitId==0) then
      return true
    end
  end
  return false
end

mAction.optEffect -- #(#Action:self)->(#Effect)
= function(self)
  local optEffect = nil --#Effect
  for i, effect in ipairs(self.effectList) do
    -- filter Major Gallop if not mount
    local ignored = false
    if effect.ability.icon:find("major_gallop",1,true) and not IsMounted() then ignored = true end
    if ignored then
    -- do nothing
    elseif not optEffect then
      optEffect = effect
    elseif self.flags.forArea and optEffect:isLongDuration() and not effect:isLongDuration() then -- opt normal duration
      optEffect = effect
    elseif self.flags.forArea and not optEffect:isLongDuration() and effect:isLongDuration() then -- opt normal duration
      optEffect = optEffect
    elseif optEffect.endTime < effect.endTime then -- opt last end
      optEffect = effect
    end
  end
  return optEffect
end

mAction.peekLongDurationEffect -- #(#Action:self)->(#Effect)
= function(self)
  for i, effect in ipairs(self.effectList) do
    if effect:isLongDuration() then return effect end
  end
  return nil
end

mAction.purgeEffect  -- #(#Action:self,#Effect:effect)->(#Effect)
= function(self, effect)
  local oldEffect = effect -- #Effect
  for i, e in ipairs(self.effectList) do
    if e.ability.id == effect.ability.id and e.unitId == effect.unitId then
      table.remove(self.effectList,i)
      oldEffect = e -- we need duration info to end action
      break
    end
  end
  local now = GetGameTimeMilliseconds()
  if not self:hasEffect() and oldEffect.duration > 0 then self.endTime =now end
  return oldEffect
end

mAction.saveEffect -- #(#Action:self, #Effect:effect)->(#Effect)
= function(self, effect)
  if self.duration and self.duration >=10000 and effect.duration > self.duration * 1.5 then return end -- ignore abnormal long duration effect
  if self.duration and self.duration > 0 and effect.duration == self.duration + 1000 then
    local existedEffect = self:optEffect()
    if existedEffect and existedEffect.duration == self.duration then -- adjust effect for covering i.e. lightning splash
      effect.endTime = effect.endTime - 1000
      effect.duration = effect.duration - 1000
    end
  end
  self.lastEffectTime = effect.startTime
  for i, e in ipairs(self.effectList) do
    if e.ability.id == effect.ability.id and e.unitId == effect.unitId then
      self.effectList[i] = effect
      return e
    end
  end
  table.insert(self.effectList, effect)
  return nil
end


--========================================
--        mEffect
--========================================
mEffect.isOnPlayer -- #(#Effect:self)->(#boolean)
= function(self)
  return self.unitTag == 'player'
end

mEffect.isOnPlayerpet -- #(#Effect:self)->(#boolean)
= function(self)
  return not not self.unitTag:find('playerpet', 1, true)
end

mEffect.isLongDuration  -- #(#Effect:self)->(#boolean)
= function(self)
  return self.duration > 30000
end
--========================================
--        register
--========================================
addon.register("Models#M", m)






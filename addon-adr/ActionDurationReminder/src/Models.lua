--========================================
--        vars
--========================================
local addon = ActionDurationReminder -- Addon#M
local m = {} -- #M
local mAction = {} -- #Action
local mAbility = {} -- #Ability
local mEffect = {} -- #Effect

local SPECIAL_DURATION_PATCH = {
  ['/esoui/art/icons/ability_warden_015_b.dds'] =6000
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

local fStripBracket -- #(#string:origin,#boolean:zh)->(#string)
= function(origin, zh)
  if zh then
    return origin:gsub("^%s*([^<]+)%s*<.*$","%1",1)
  else
    return origin:gsub("^[^<]+<%s*([^>]+)%s*>.*$","%1",1)
  end
end

--========================================
--        m
--========================================
m.cacheOfActionMatchingEffect = {} -- #map<#string:#boolean>
m.cacheOfActionMatchingAbilityName = {} -- #map<#string:#boolean>
m.newAbility -- #(#number:id, #string:name, #string:icon)->(#Ability)
= function(id, name, icon)
  local ability = {} -- #Ability
  local getIconPath -- #(#string:icon)->(#string)
  = function(icon)
    return icon:sub(1,1)=='/' and icon or ('/'..icon)
  end
  icon = getIconPath(icon)
  ability.id = id -- #number
  ability.type = 0
  ability.showName = zo_strformat("<<1>>", name) --#string
  ability.name= fStripBracket(ability.showName) --#string
  if ability.showName ~= ability.name then
    ability.showName = fStripBracket(ability.showName,true)
  end
  ability.icon = icon -- #string
  local icon2 = getIconPath(GetAbilityIcon(id))
  if icon2 ~= icon then
    ability.icon2 = icon2 -- #string
  end
  local hasProgression,progressionIndex = GetAbilityProgressionXPInfoFromAbilityId(id)
  ability.progressionName = hasProgression and GetAbilityProgressionInfo(progressionIndex) or nil
  if ability.progressionName and ability.progressionName ~= name then
    ability.progressionName =  zo_strformat("<<1>>", ability.progressionName)
    ability.progressionName = fStripBracket(ability.progressionName)
  else
    ability.progressionName = nil
  end -- only keep different name
  ability.description = GetAbilityDescription(id):gsub('%^%w','') -- #string
  setmetatable(ability,{__index=mAbility})
  return ability
end


m.newAction -- #(#number:slotNum,#number:weaponPairIndex,#boolean:weaponPairUltimate)->(#Action)
= function(slotNum, weaponPairIndex, weaponPairUltimate)
  local action = {} -- #Action
  action.fake = false
  action.targetOut = false
  action.slotNum = slotNum --#number
  action.ability = m.newAbility(GetSlotBoundId(slotNum),GetSlotName(slotNum),GetSlotTexture(slotNum)) -- #Ability
  action.relatedAbilityList = {} --#list<#Ability> for matching
  local channeled,castTime,channelTime = GetAbilityCastInfo(action.ability.id)
  action.castTime = castTime or 0 --#number
  action.startTime = GetGameTimeMilliseconds() --#number
  action.duration = SPECIAL_DURATION_PATCH[action.ability.icon] or GetAbilityDuration(action.ability.id) or 0 --#number
  if action.duration<1000 then action.duration = 0 end
  action.inheritDuration = 0 --#number
  action.description = zo_strformat("<<1>>", GetAbilityDescription(action.ability.id)) --#string

  -- look for XX seconds in description i.e. in eso 8.2.0 Dark Donvertion has 10s duration but a 20s description duration
  local pattern = zo_strformat(GetString(SI_TIME_FORMAT_SECONDS_DESC),2) --#string
  pattern = '.-('..pattern:gsub("2","([%%.,%%d]*%%d+).r")..').*'
  -- /script pattern = '.-('..zo_strformat(GetString(SI_TIME_FORMAT_SECONDS_DESC),2):gsub("2","([%%.,%%d]*%%d+).r")..').*'
  local numStr,n = action.description:gsub(pattern,'%2') --/script d(desc:gsub(pattern,'%2'))
  if n and n > 0 then
    action.descriptionDuration = tonumber((numStr:gsub(',','.')))*1000 --#number
  end

  action.endTime = action.duration==0 and 0 or action.startTime + action.duration--#number
  action.lastEffectTime = 0 --#number
  action.oldAction = nil --#Action
  action.newAction = nil --#Action

  action.weaponPairIndex = weaponPairIndex --#number
  action.weaponPairUltimate = weaponPairUltimate --#boolean
  local target = GetAbilityTargetDescription(action.ability.id)
  local radius = GetAbilityRadius(action.ability.id)
  local forArea = target==GetString(SI_ABILITY_TOOLTIP_TARGET_TYPE_AREA) and (radius==0 or radius>200)
  forArea = forArea or target==GetString(SI_ABILITY_TOOLTIP_TARGET_TYPE_CONE)
  local forEnemy =  target==GetString(SI_TARGETTYPE0)
  local forGround = target==GetString(SI_ABILITY_TOOLTIP_TARGET_TYPE_GROUND)
  local forSelf = target== GetString(SI_ABILITY_TOOLTIP_RANGE_SELF) or radius==500 or target=='自己' --[[汉化组修正翻译前的补丁]]
  local forTank = GetAbilityRoles(action.ability.id)
  ---
  --@type ActionFlags
  action.flags
  = {
    forArea -- #boolean
    = forArea,
    forEnemy -- #boolean
    = forEnemy,
    forGround -- #boolean
    = forGround,
    forSelf -- #boolean
    = forSelf,
    forTank -- #boolean
    = forTank,
    shifted -- #boolean
    = false,
    onlyOneTarget -- #boolean
    = false
  }
  action.data = {} -- #table to store data in
  action.effectList = {} -- #list<#Effect>
  action.stackCount = 0
  action.stackEffect = nil -- #Effect
  action.targetId = nil --#number
  setmetatable(action,{__index=mAction})
  return action
end

m.newEffect -- #(#Ability:ability, #string:unitTag, #number:unitId, #number:startTime, #number:endTime, #number:stackCount)->(#Effect)
=  function(ability, unitTag, unitId, startTime, endTime, stackCount)
  local effect = {} -- #Effect
  effect.ability = ability --#Ability
  effect.unitTag = unitTag:find('player',1,true) and unitTag or 'others' -- #string player or playerpet or others
  effect.unitId = unitId -- #number
  effect.startTime = startTime -- #number
  effect.endTime = endTime -- #number
  effect.duration = endTime-startTime -- #number
  effect.ignored = false -- #boolean
  effect.stackCount = stackCount -- #number
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
mAction.getAreaEffectCount -- #(#Action:self)->(#number)
= function(self)
  local count = 0
  for key, var in pairs(self.effectList) do
    if var.ability.type == ABILITY_TYPE_AREAEFFECT then count = count+1 end
  end
  return count > 0 and count or nil
end

mAction.getDuration -- #(#Action:self)->(#number)
= function(self)
  local optEffect = self:optEffect() -- #Effect
  return optEffect and optEffect.duration or self.duration or self.descriptionDuration
end

mAction.getEffectsInfo -- #(#Action:self)->(#string)
= function(self)
  local info = ''
  for key, var in ipairs(self.effectList) do
    info = info.. var.ability.id..'<'..var.duration..'>('..var.startTime..'~'..var.endTime..')'
    if var.ignored then
      info = info..'!ignored'
    end
    info = info..','
  end
  local oe = self:optEffect()
  if oe then
    info = info..'opt:'..oe.ability.id
  else
    info = info..'no opt effect'
  end
  return info
end

mAction.getEndTime -- #(#Action:self)->(#number)
= function(self)
  local optEffect = self:optEffect() -- #Effect
  if optEffect then return optEffect.endTime end
  if self.endTime>0 then return self.endTime end
  if self.descriptionDuration and self.descriptionDuration>0 then return self.startTime+self.descriptionDuration end
  return self.startTime
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
  -- 1/2 by firstStageId cache
  if self.data.firstStageId and self.data.firstStageId == optEffect.ability.id then
    return '1/2'
  end
  -- 1/2 by same id, same start, >1/5 and <4/7 duration
  if optEffect.ability.id==self.ability.id
    and math.abs(optEffect.startTime-self.startTime)< 500
    and optEffect.duration * 5 > self.duration
    and optEffect.duration * 7 < self.duration*4
  then
    self.data.firstStageId = optEffect.ability.id
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
  if self.data.firstStageId and self.data.firstStageId ~= optEffect.ability.id then
    -- 2/2 by same end
    if math.abs(optEffect.endTime-self.startTime-self.duration)<700 then
      -- 40%~80% duration
      if optEffect.duration*5 > self.duration *2 and
        optEffect.duration*5 < self.duration *4 then
        return '2/2'
      end
    end
    -- 2/2 by normal effect with firstStagedId and without long duration effect present
    if self.flags.forArea and not longDurationEffect
    then
      return '2/2'
    end
    -- 2/2 by non-action duration, e.g. Pierce Armor with Master 1H-1S
    if self.duration == 0 then
      return '2/2'
    end
  end
  -- activated stage e.g. Beast Trap and Scalding Rune
  if optEffect.activated then return '@' end
  if self.duration and self.duration>0 -- action with duration prop
    and (
    (
    -- triggered after a delay for non-ground
    not self.flags.forGround and  optEffect.startTime-self.startTime>1500
    )or
    (
    -- triggered after first ground effect
    self.flags.forGround and optEffect.ability.id ~= self.groundFirstEffectId
    )
    )
    and optEffect.duration%1000==0 -- with whole seconds duration
  then
    optEffect.activated = true
    return '@'
  end
  if self.targetOut then
    return '~'
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

mAction.matchesAbilityId -- #(#Action:self,#string:abilityId)->(#boolean)
= function(self, abilityId, strict)
  if self.ability.id == abilityId then return true end
  -- check related
  for key, var in ipairs(self.relatedAbilityList) do
    if var.id == abilityId then return true end
  end
end

mAction.matchesAbilityName -- #(#Action:self,#string:abilityName, #boolean:strict)->(#boolean)
= function(self, abilityName, strict)
  local key = self.ability.id..'/'..abilityName..'/'..(strict and 'y' or 'n')
  local value = m.cacheOfActionMatchingAbilityName[key]
  if value~=nil then return value end
  value = self:_matchesAbilityName(abilityName,strict)
  m.cacheOfActionMatchingAbilityName[key] = value
  return value
end
mAction._matchesAbilityName -- #(#Action:self,#string:abilityName, #boolean:strict)->(#boolean)
= function(self, abilityName, strict)
  if abilityName:find(self.ability.name,1,true)
    -- i.e. Assassin's Will name can match Merciless Resolve action by its description
    or (not strict and not addon.isSimpleWord(abilityName) and self.description:find(abilityName,1,true))
  then
    return true
  end
  -- i.e. Merciless Resolve name can match Assissin's Will action by its related ability list
  for key, var in ipairs(self.relatedAbilityList) do
    if abilityName:find(var.name,1,true) then return true end
  end
  return false
end

mAction.matchesNewEffect -- #(#Action:self,#Effect:effect)->(#boolean)
= function(self, effect)
  -- 0. filter ended action
  if not self.flags.forGround and self.endTime > self.startTime and self.endTime + 500 < effect.startTime then
    return false
  end
  -- 1. using cache to match
  local key = self.ability.id..'/'..effect.ability.id..'/'..effect.duration
  local value = m.cacheOfActionMatchingEffect[key]
  if value ~= nil then return value end
  value = self:_matchesNewEffect(effect)
  m.cacheOfActionMatchingEffect[key] = value
  return value
end

mAction._matchesNewEffect -- #(#Action:self,#Effect:effect)->(#boolean)
= function(self, effect)
  -- 1. taunt
  if effect.ability.icon:find('quest_shield_001',18,true) and self.flags.forTank then
    return true
  end
  -- 2. fast check already matched effects
  local strict = effect.startTime > self.startTime + self.castTime + 2000
  if strict and self.duration > 0 then -- try to accept continued effect
    if effect.startTime > self.endTime and effect.startTime < self.endTime + 500 then
      strict = false
  end
  end
  strict = strict or (effect.duration>0 and effect.duration<4000) -- Render Flesh has a 4 second Minor Defile
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
  if effect.ability.icon:find('quest_shield_001',18,true) and self.flags.forTank then
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
    local ignored = effect.ignored
    -- filter Major Gallop if not mount
    if effect.ability.icon:find("major_gallop",1,true) then
      if IsMounted() then return effect end
      ignored = true
    end
    -- filter after phase effect e.g. warden's Scorch ending brings some debuff effects
    if self.duration > 0 and self.startTime+self.duration-300 <= effect.startTime then
      -- only ignore if this duration is not equal to action duration e.g. warden's Subterrian Assault
      if self.duration ~= effect.duration then
        ignored = true
      end
    end
    -- filter old effects at new action beginning
    if effect.startTime < self.startTime and GetGameTimeMilliseconds()-self.startTime< 500 then
      ignored = true
    end

    if ignored then
    -- do nothing
    elseif not optEffect then
      optEffect = effect
    else
      optEffect = self:optEffectOf(optEffect,effect)
    end
  end
  return optEffect
end

mAction.optEffectOf -- #(#Action:self,#Effect:effect1,#Effect:effect2)->(#Effect)
= function(self,effect1, effect2)
  -- override long duration
  if self.flags.forArea and effect1:isLongDuration() ~= effect2:isLongDuration() then
    return effect1:isLongDuration() and effect2 or effect1 -- opt normal duration
  end
  -- check 1/2 phase
  if self.data.firstStageId then
    if self.data.firstStageId == effect1.ability.id then return effect1 end
    if self.data.firstStageId == effect2.ability.id then return effect2 end
  end
  if math.abs(effect1.startTime-effect2.startTime)<500 then
    local isEffect1Bigger = effect1.duration>effect2.duration
    local longEffect = isEffect1Bigger and effect1 or effect2 -- #Effect
    if self.stackEffect == longEffect then return longEffect end
    local shortDur = isEffect1Bigger and effect2.duration or effect1.duration
    local longDur = isEffect1Bigger and effect1.duration or effect2.duration
    local percent = shortDur*100/longDur
    local shortIcon = isEffect1Bigger and effect2.ability.icon or effect1.ability.icon -- #string
    local longIcon = isEffect1Bigger and effect1.ability.icon or effect2.ability.icon -- #string
    if shortDur>4900 --[[ filter trivia effects less than 5 sec ]]
      and percent > 32
      and percent < 65
      and not shortIcon:find('expedition',30,true) -- reject expedition buffs as 1/2 stage
    then
      self.data.firstStageId = isEffect1Bigger and effect2.ability.id or effect1.ability.id
      return isEffect1Bigger and effect2 or effect1
    end
    if longIcon:find('ability_buff_m',30,true) -- for Balance 4s healing and 30s major resolve
      and percent < 15
      and not shortIcon:find('ability_buff_m',30,true)
    then
      self.data.firstStageId = isEffect1Bigger and effect2.ability.id or effect1.ability.id
      return isEffect1Bigger and effect2 or effect1
    end
  end
  -- check priority
  -- including inherit duration e.g. activation of Bound Armaments
  local duration = self.duration > 0 and self.duration or self.inheritDuration --#number
  local role = GetSelectedLFGRole()
  local getPriority -- #(#Effect:effect)->(#number,#number)
  = function(effect)
    local px1=0
    local px2=0
    -- don't opt buffs which are remnant from old acitons
    if effect.startTime < self.startTime then return -1,-1 end
    -- don't opt buffs which have difference durations
    if self.duration and self.duration >0 and effect.duration ~= self.duration and effect.ability.icon:find('ability_buff_m',1,true) then return -1,-1 end
    -- opt non-player effect for dps, if not area effect
    if (role==LFG_ROLE_DPS or self.flags.forEnemy) and not self.flags.forArea and not effect:isOnPlayer() and effect.duration>0 then px1=2 end
    -- opt player effect for tank
    if role==LFG_ROLE_TANK and effect:isOnPlayer() then px1=2 end
    -- opt player effect for healer, if not area effect, e.g. Regeneration can be applied on player or ally
    if role== LFG_ROLE_HEAL and not self.flags.forArea and effect:isOnPlayer() then px1 =2 end
    -- opt stack effect
    if px1<2 and effect.duration>3000 and self.stackEffect and effect.ability.id == self.stackEffect.ability.id then px1 = 3 end
    -- opt same id effect
    if effect.ofActionId or effect.duration== self.duration and effect.ability.id == self.ability.id then
      effect.ofActionId = true
      px1 = 4
    end

    -- opt major effect that matches action duration
    if duration > 0 and effect.duration-duration ==0 then px2= 1 end
    -- opt long effect for healer
    if role== LFG_ROLE_HEAL and duration>0 and effect.duration>duration then px2=2 end
    return px1,px2
  end
  local p11,p12 = getPriority(effect1)
  local p21,p22 = getPriority(effect2)
  if p11~=p21 then
    local majorEffect = p11>p21 and effect1 or effect2
    local minorEffect = p11>p21 and effect2 or effect1
    minorEffect.ignored = true -- widen its scope if major fades earlier
    return majorEffect
  end
  if p12~=p22 then
    local majorEffect = p12>p22 and effect1 or effect2 -- #Effect
    local minorEffect = p12>p22 and effect2 or effect1 -- #Effect
    -- ignore same start minor e.g.
    if math.abs(majorEffect.startTime - minorEffect.startTime) <300 then minorEffect.ignored = true end
    -- ignore long overriden minor e.g. Bound Armaments 40s major effect duration override 10s light/heavy attack effect
    if GetGameTimeMilliseconds() - minorEffect.startTime > 500 then minorEffect.ignored = true end
    return majorEffect
  end
  return effect1.duration < effect2.duration and effect2 or effect1 -- opt longer duration
end

mAction.optGallopEffect -- #(#Action:self)->(#Effect)
= function(self)
  for i, effect in ipairs(self.effectList) do
    -- filter Major Gallop if not mount
    if effect.ability.icon:find("major_gallop",1,true) then
      return effect
    end
  end
  return false
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
  local availableEffectCount = 0
  for key, var in pairs(self.effectList) do
    if not var.ignored then availableEffectCount = availableEffectCount+1 end
  end
  if availableEffectCount==0 and oldEffect.duration > 0 and -- last duration effect has faded
    (
    -- the old effect SHOULD be brought by this action rather than an old one, or this might be a renew rather than end
    (oldEffect.startTime>= self.startTime)
    or
    (
    -- or the old one is fake, so a real action now is triggered and we should do a purge
    self.oldAction and self.oldAction.fake
    )
    )
  then
    self.endTime =now
  end
  return oldEffect
end

mAction.saveEffect -- #(#Action:self, #Effect:effect)->(#Effect)
= function(self, effect)
  -- ignore abnormal long duration effect
  if self.duration and self.duration >=10000
    and effect.duration > self.duration * 1.5
    and effect.duration ~= self.descriptionDuration
  then
    return
  end
  -- adjust effect for covering i.e. lightning splash
  if self.duration and self.duration > 0 and effect.duration == self.duration + 1000 then
    local existedEffect = self:optEffect() -- #Effect:effect
    if existedEffect and existedEffect.duration == self.duration then
      effect.endTime = effect.endTime - 1000
      effect.duration = effect.duration - 1000
    end
  end
  -- adjust effect for explosive duration i.e. unstable wall
  if self.duration and self.duration >0 and effect.duration > self.duration and effect.duration < self.duration+500 and effect.startTime< self.startTime+900 then
    effect.duration = self.duration
    local existedEffect = nil
    for key, var in ipairs(self.effectList) do
      if var.startTime>self.startTime and var.startTime< self.startTime+500 then existedEffect = var end
    end
    if existedEffect then
      effect.startTime = existedEffect.startTime
    end
    effect.endTime = effect.startTime + effect.duration
  end
  -- TODO temp modify for Unnerving Boneyard skill
  if self.ability.icon:find('necromancer_004',1,true) and effect.duration>10000 then
    --    df('[ADR Debug] Ignored %s(%d)<%d>@%s:%s',effect.ability.name, effect.ability.id, effect.duration, effect.unitTag,effect.ability.icon )
    return
  end

  self.lastEffectTime = effect.startTime
  for i, e in ipairs(self.effectList) do
    if e.ability.id == effect.ability.id and e.unitId == effect.unitId then
      self.effectList[i] = effect
      return e
    end
  end
  table.insert(self.effectList, effect)
  -- record targetId for enemy actions
  if self.flags.forEnemy and effect.unitId>0 then
    self.targetId = effect.unitId
  end
  -- record first ground effect id for triggering recognition
  if #self.effectList == 1 and self.flags.forGround then
    self.groundFirstEffectId = effect.ability.id -- #number
  end
  return nil
end

mAction.updateStackInfo --#(#Action:self, #number:stackCount, #Effect:effect)->(#boolean)
= function(self, stackCount, effect)
  local canAdd = false
  if not self.stackEffect then
    canAdd = true
    -- filter sudden big stack at action beginning
    if stackCount>=2
      and not self.fake -- fake actions are always newly created and without an old stack effect
    then
      canAdd = false
    end
  elseif self.stackEffect.ability.id == effect.ability.id then
    canAdd = true
    --  else
    --    df('old id is %d, new is %d', self.stackEffect.ability.id, effect.ability.id)
  end
  if canAdd then
    self.stackCount = stackCount
    self.stackEffect = effect
    return true
  end

  return false
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
  return self.duration > 39000
end
--========================================
--        register
--========================================
addon.register("Models#M", m)

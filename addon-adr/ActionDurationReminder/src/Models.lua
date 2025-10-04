--========================================
--        vars
--========================================
local addon = ActionDurationReminder -- Addon#M
local l = {} -- #L
local m = {l=l} -- #M
local mAction = {} -- #Action
local mAbility = {} -- #Ability
local mEffect = {} -- #Effect

-- /script ActionDurationReminder.debugLevels.model=2
-- /script ActionDurationReminder.debugLevels.all=2

local DS_MODEL = "model" -- debug switch for model
local DS_ALL = "all" -- debug switch for all



local SPECIAL_DURATION_PATCH = {
  ['/esoui/art/icons/ability_warden_015_b.dds'] =6000
}

local fRefinePath -- #(#string:path)->(#string)
= function(path)
  if not path then return path end
  path = path:lower()
  -- 过滤三个数字后的部分，例如 "/esoui/art/icons/ability_werewolf_002_rend_b.dds"
  -- 变为"/esoui/art/icons/ability_werewolf_002"
  path = path:match("(.-[0-9][0-9][0-9])") or path
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
--        l
--========================================
l.debug -- #(#string:switch,#number:level)->(#(#string:format, #string:...)->())
=function(switch, level)
  return function(format, ...)
    if l.debugEnabled(switch,level) then
      d(os.date()..'>', string.format(format, ...))
    end
  end
end

l.debugEnabled -- #(#string:switch,#number:level)->(#boolean)
= function(switch, level)
  return (addon.debugLevels[switch] and addon.debugLevels[switch]>=level) or
    (addon.debugLevels[DS_ALL] and addon.debugLevels[DS_ALL]>=level)
end

--========================================
--        m
--========================================
m.cacheOfActionMatchingEffect = {} -- #map<#string:#boolean>
m.cacheOfActionMatchingAbilityName = {} -- #map<#string:#boolean>
m.cacheOfActionMatchingAbilityIcon = {} -- #map<#string:#boolean>
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
  if hasProgression and progressionIndex then
    local _,icon3,_ = GetAbilityProgressionAbilityInfo(progressionIndex,0,1)
    if icon3 ~= icon then
      ability.icon3 = icon3 -- #string
    end
  end
  ability.description = GetAbilityDescription(id):gsub('%^%w','') -- #string
  setmetatable(ability,{__index=mAbility})
  return ability
end

local seed = 0
local nextSeed = function()
  seed = seed+1
  return seed
end
m.newAction -- #(#number:slotNum,#number:hotbarCategory)->(#Action)
= function(slotNum, hotbarCategory)
  local action = {} -- #Action
  action.fake = false
  action.sn = nextSeed() --#number
  action.targetOut = false
  action.slotNum = slotNum --#number
  local abilityId = GetSlotBoundId(slotNum, hotbarCategory)
  local slotType = GetSlotType(slotNum,hotbarCategory)
  action.crafted = false
  if slotType == ACTION_TYPE_CRAFTED_ABILITY then
    action.crafted = true
    action.craftedId = abilityId -- #number
    abilityId = GetAbilityIdForCraftedAbilityId(abilityId)
  end
  action.ability = m.newAbility(abilityId, GetSlotName(slotNum,hotbarCategory),GetSlotTexture(slotNum, hotbarCategory)) -- #Ability
  action.relatedAbilityList = {} --#list<#Ability> for matching
  local channeled,castTime = GetAbilityCastInfo(action.ability.id)
  action.channeled = channeled --#boolean
  action.castTime = castTime or 0 --#number
  action.startTime = GetGameTimeMilliseconds() --#number
  action.duration = SPECIAL_DURATION_PATCH[action.ability.icon] or GetAbilityDuration(action.ability.id) or 0 --#number
  action.configDuration = nil --#number
  if action.duration<1000 then action.duration = 0 end
  action.inheritDuration = 0 --#number
  action.showCrux = action.ability.icon:find('arcanist_002',18,true) or action.ability.icon:find('arcanist_003_b',18,true)
  local description = action.ability.description
  if action.crafted then
    local sid1,sid2,sid3 = GetCraftedAbilityActiveScriptIds(action.craftedId)
    description = description..'\n'..GetCraftedAbilityScriptDescription(action.craftedId, sid1)
      ..'\n'..GetCraftedAbilityScriptDescription(action.craftedId, sid2)
      ..'\n'..GetCraftedAbilityScriptDescription(action.craftedId, sid3)
  end
  action.description = zo_strformat("<<1>>", description) --#string
  action.ability.description = action.description
  action.effectEndTimes = {} --#list<#number>

  -- look for XX seconds in description i.e. in eso 8.2.0 Dark Donvertion has 10s duration but a 20s description duration
  local pattern = zo_strformat(GetString(SI_TIME_FORMAT_SECONDS_DESC),2) --#string
  if GetCVar("language.2")=='zh' then pattern = '2秒' end
  pattern = '.-('..pattern:gsub("2","([%%.,%%d]*%%d+).r")..')'
  -- /script pattern = '.-('..zo_strformat(GetString(SI_TIME_FORMAT_SECONDS_DESC),2):gsub("2","([%%.,%%d]*%%d+).r")..')'
  local offset = 1
  local num = 0
  while true do
    local i,j,seg,numStr = action.description:find(pattern,offset)
    if not i then break end
    offset = j
    local n =  tonumber((numStr:gsub(',','.')))*1000
    if num ==0 or n<30000 and n>num then -- only overide if n<30s and n > num e.g. in DK's Deep Breath description there are 2 sec and 2.5 sec segments
      num = n
    end
  end
  if num > 0 then
    action.descriptionDuration = num --#number
  end
  -- find number for stack times
  action.descriptionNums = {} -- #map<#number, #boolean>
  pattern = '.-([%.,%d]*%d+).r'
  offset=1
  while true do
    local i,j,numStr = action.description:find(pattern,offset)
    if not i then break end
    offset = j
    local n =  tonumber((numStr:gsub(',','.')))
    if not n then break end
    if (n*1000)%1000==0 then
      action.descriptionNums[n] = true
    end
  end

  action.endTime = action.duration==0 and 0 or action.startTime + action.duration--#number
  action.inCombat = IsUnitInCombat('player') --#boolean
  action.lastEffectTime = 0 --#number
  action.channelStartTime = 0 --#number
  action.channelEndTime = 0 --#number
  action.channelUnitId = 0 --#number
  action.oldAction = nil --#Action
  action.newAction = nil --#Action

  action.hotbarCategory = hotbarCategory --#number
  local target = GetAbilityTargetDescription(action.ability.id)
  local radius = GetAbilityRadius(action.ability.id)
  local forArea = target==GetString(SI_ABILITY_TOOLTIP_TARGET_TYPE_AREA) and (radius==0 or radius>200)
  forArea = forArea or target==GetString(SI_ABILITY_TOOLTIP_TARGET_TYPE_CONE)
  local forEnemy =  target==GetString(SI_TARGETTYPE0)
  local forGround = target==GetString(SI_ABILITY_TOOLTIP_TARGET_TYPE_GROUND)
  local forSelf = target== GetString(SI_ABILITY_TOOLTIP_RANGE_SELF) or radius==500 or target=='自己' --[[汉化组修正翻译前的补丁]]
  local forTank = GetAbilityRoles(action.ability.id)
    -- Frost Clench can taunt
    or action.ability.icon:find('destructionstaff_005_a',18,true)

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
  action.stackCount2 = 0
  action.stackEffect = nil -- #Effect
  action.stackEffect2 = nil -- #Effect
  action.tickEffect = nil -- #Effect
  action.tickEffectDoubled = false -- #boolean
  action.targetId = nil --#number
  setmetatable(action,{__index=mAction})
  return action
end

m.newEffect -- #(#Ability:ability, #string:unitTag, #number:unitId, #number:startTime, #number:endTime, #number:stackCount)->(#Effect)
=  function(ability, unitTag, unitId, startTime, endTime, stackCount, tickRate)
  local effect = {} -- #Effect
  effect.ability = ability --#Ability
  if effect.ability.icon:find('arcanist_crux',18,true) then
    effect.isCrux = true --#boolean
  end
  effect.unitTag = unitTag:find('player',1,true) and unitTag or 'others' -- #string player or playerpet or others
  effect.unitId = unitId -- #number
  effect.startTime = startTime -- #number
  effect.endTime = endTime -- #number
  effect.duration = endTime-startTime -- #number
  effect.ignored = false -- #boolean
  effect.ignorableDebuff = false -- #boolean
  effect.stackCount = stackCount or 0 -- #number
  effect.tickRate = tickRate or 0 -- #number
  setmetatable(effect,{__index=mEffect})
  return effect
end

local function matchFunc(s1, s2, full)
  if s1=='' or s2=='' then return false end
  if s1 == s2 then return true end
  if not full and (s1:find(s2, 1,true) or s2:find(s1, 1,true)) then return true end
  return false
end

-- bStrict => {id1 + idOffset * id2 { ret } }
local matchesMemo = {}
matchesMemo[false] = {}
matchesMemo[true] = {}

local idOffset = 100000000

local function getIdHash(inId1, inId2)
  return inId1 + (idOffset * inId2)
end

local function memoizeMatch(idHash, bStrict, result)
  matchesMemo[bStrict or false][idHash] = result
end

--========================================
--        mAbility
--========================================
mAbility.matches -- #(#Ability:self, #Ability:other, #boolean:strict)->(#boolean)
= function(self, other, strict)
  local idHash = getIdHash(self.id, other.id or 0)
  local stringMatchRes = matchesMemo[strict or false][idHash]
  if stringMatchRes ~= nil then
    return stringMatchRes
  end

  if self.id==other.id then
    memoizeMatch(idHash, strict, true)
    return true
  end
  if fMatchIconPath(self.icon, other.icon) then
    memoizeMatch(idHash, strict, true)
    return true
  end
  if other.icon2  then
    if fMatchIconPath(self.icon, other.icon2) then
      memoizeMatch(idHash, strict, true)
      return true
    end
  end
  if self.icon3 then
    if fMatchIconPath(self.icon3, other.icon) then
      memoizeMatch(idHash, strict, true)
      return true
    end
  end
  if matchFunc(self.name , other.name, true) then
    memoizeMatch(idHash, strict, true)
    return true
  end
  if self.progressionName and matchFunc(self.progressionName, other.name, true) then
    memoizeMatch(idHash, strict, true)
    return true
  end
  if not strict
    and not addon.isSimpleWord(other.name) -- do not match a one word name in description
    and self.description
  then
    if matchFunc(self.description, other.name) then
      memoizeMatch(idHash, strict, true)
      return true
    end
    if self.description:find(other.name:gsub(" "," %%w+ %%w+ ")) then
      memoizeMatch(idHash, strict, true)
      return true
    end -- i.e. match major sorcery in critical surge description: major brutality and sorcery
  end

  memoizeMatch(idHash, strict, false)
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
  if self.tickEffect and self.duration==0 then
    return self.tickEffect.tickRate
  end
  if self.channelStartTime>0 and self.channelEndTime>0 then
    return self.channelEndTime - self.channelStartTime
  end
  if self.configDuration then return self.configDuration end
  local optEffect,reason = self:optEffect() -- #Effect
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

mAction.getEndTime -- #(#Action:self,#boolean:debugging)->(#number)
= function(self, debugging)
  if self.tickEffect and self.duration==0 then
    local start = self.tickEffect.startTime
    local now = GetGameTimeMilliseconds()
    local span = now - start
    local offset = span - span % self.tickEffect.tickRate
    return start + offset + self.tickEffect.tickRate
  end
  if self.channelEndTime >0 then return self.channelEndTime end
  if self.configDuration then return self.startTime + self.configDuration end
  local optEffect,reason = self:optEffect() -- #Effect
  reason = reason or 'nil'
  local now = GetGameTimeMilliseconds()
  if optEffect then
    if debugging and optEffect.endTime-self.endTime<1000 then
      self:optEffect(true)
    end
    if optEffect.ignorableDebuff and optEffect.endTime> self.endTime and self.endTime>GetGameTimeMilliseconds() then
      self.data.firstStageId = self.ability.id
      return self.endTime
    end
    return optEffect.endTime
  end
  if self.endTime>0 then return self.endTime end
  local maxEffectEndTime = 0
  for key, var in ipairs(self.effectEndTimes) do
    if var > maxEffectEndTime then maxEffectEndTime = var end
  end
  if maxEffectEndTime > 0 then return maxEffectEndTime end
  if self.descriptionDuration and self.descriptionDuration>0 then return self.startTime+self.descriptionDuration end
  return self.startTime
end

mAction.getFullEndTime -- #(#Action:self)->(#number)
= function(self)
  if self.configDuration then return self.startTime+self.configDuration end
  local endTime = 0;
  for key, var in ipairs(self.effectList) do
    if not var.ignored then
      endTime = math.max(endTime,var.endTime)
    end
  end
  if endTime >0 then return endTime end
  if self.endTime>0 then return self.endTime end
  if self.descriptionDuration and self.descriptionDuration>0 then return self.startTime+self.descriptionDuration end
  return self.startTime
end

mAction.getFlagsInfo -- #(#Action:self)->(#string)
= function(self)
  return string.format('forArea:%s,forGround:%s,forSelf:%s,forTank:%s,forEnemy:%s',
    tostring(self.flags.forArea),
    tostring(self.flags.forGround),
    tostring(self.flags.forSelf),
    tostring(self.flags.forTank),
    tostring(self.flags.forEnemy)
  )
end

mAction.getMaxOriginEffectDuration -- #(#Action:self)->(#number)
= function(self)
  local max = self.duration -- #number
  for key, var in ipairs(self.effectList) do
    if math.abs(var.startTime - self.startTime)<500 then
      max = math.max(max,var.duration)
    end
  end
  return max
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
  if self.tickEffect then
    if not self.duration or self.duration ==0 then
      return '∞'
    end
    local dur = self:getDuration()
    local total = math.floor(dur/ self.tickEffect.tickRate+0.95)
    local remain = math.ceil((self:getEndTime()-GetGameTimeMilliseconds())/self.tickEffect.tickRate)
    return string.format('%d/%d',math.max(1,total-remain), total)
  end
  local optEffect = self:optEffect()
  if not optEffect or not self.duration then
    return nil
  end
  -- 1/2 by firstStageId cache
  if self.data.firstStageId and (self.data.firstStageId == optEffect.ability.id
    -- staged by default duration and a longer debuff
    or optEffect.ignorableDebuff and self.data.firstStageId==self.ability.id and GetGameTimeMilliseconds()<self.endTime) then
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
  -- 1/2 by same start, same duration but with another long buff
  if math.abs(optEffect.startTime-self.startTime)< 500
    and optEffect.duration== self.duration
    and optEffect.duration +3000 <= self:getMaxOriginEffectDuration() then
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
    -- 2/2 by cache
    if self.data.secondStageId == optEffect.ability.id then
      return '2/2'
    end
    if not self.data.secondStageId then
      -- 2/2 by same end
      if math.abs(optEffect.endTime-self.startTime-self.duration)<700 then
        -- 40%~80% duration
        if optEffect.duration*5 > self.duration *2 and
          optEffect.duration*5 < self.duration *4 then
          self.data.secondStageId = optEffect.ability.id
          return '2/2'
        end
      end
      -- 2/2 by normal effect with firstStagedId and without long duration effect present
      if self.flags.forArea and not longDurationEffect
      then
        self.data.secondStageId = optEffect.ability.id
        return '2/2'
      end
      -- 2/2 by non-action duration, e.g. Pierce Armor with Master 1H-1S
      if self.duration == 0 then
        self.data.secondStageId = optEffect.ability.id
        return '2/2'
      end
      -- 2/2 by duration longer than action's e.g. 5s Resolving Vigor has a 20s Minor Resolve
      if self.duration< optEffect.duration then
        self.data.secondStageId = optEffect.ability.id
        return '2/2'
      end
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
    -- triggered after first ground effect and delay
    self.flags.forGround and optEffect.ability.id ~= self.groundFirstEffectId
    and  optEffect.startTime-self.startTime>900
    )
    )
    and optEffect.duration%1000==0 -- with whole seconds duration
  then
    optEffect.activated = true
    return '@'
  end
  if self.targetOut then
    return '#'
  end
  -- tail effect
  local duration = self.duration or 0
  if duration == 0 then duration = self.descriptionDuration or 0 end
  if duration > 0 and self:getEndTime() > self.startTime + duration+1000 then
    return '>'
  end
  return nil
end

mAction.getStageInfo2 -- #(#Action:self)->(#number)
= function(self)
  -- fixed value
  if self.stackCount2 and self.stackCount2>0 then
    return self.stackCount2
  end
  -- cached value
  if self.flags.forArea then
    local now = GetGameTimeMilliseconds()
    if not self.getStageInfo2_Stamp or now - self.getStageInfo2_Stamp > 1000 then
      -- calc: max unit counts of single ability
      self.getStageInfo2_Stamp = now
      self.getStageInfo2_Cache = nil
      local abilityUnits = {}
      for key, var in ipairs(self.effectList) do
        local abilityId = var.ability.id
        local units = abilityUnits[abilityId]
        if units ==nil then
          units = {}
          units[-1]=0
          abilityUnits[abilityId] = units
        end
        local unitId = var.unitId
        if not units[unitId] then
          units[unitId] = true
          units[-1] = units[-1] + 1
        end
      end
      local maxCount = 0
      for key, var in pairs(abilityUnits) do
        if var[-1] > maxCount then
          maxCount = var[-1]
        end
      end
      if maxCount>1 then
        self.getStageInfo2_Cache = maxCount
      end
    end
    return self.getStageInfo2_Cache
  end
  return nil
end

mAction.getStartTime -- #(#Action:self)->(#number)
= function(self)
  if self.tickEffect and self.duration==0 then
    local start = self.tickEffect.startTime
    local now = GetGameTimeMilliseconds()
    local span = now - start
    local offset = span - span % self.tickEffect.tickRate
    return start + offset
  end
  if self.channelStartTime>0 then return self.channelStartTime end
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

mAction.isShowingCruxDuration -- #(#Action:self)->(#boolean)
= function(self)
  local optEffect = self:optEffect()
  if optEffect and optEffect.isCrux -- opt effect is crux?
    and self.channelStartTime==0 -- not showing channel time
  then
    return true end
  return false
end

mAction.isUnlimited -- #(#Action:self)->(#boolean)
= function(self)
  local optEffect = self:optEffect()
  return self.duration==0 and self.stackCount>0 and
    (
    optEffect and optEffect.duration==0
    or not optEffect
    )
    -- should not remove newly created covering action
    or (self.oldAction and not optEffect and #self.effectList>0 and GetGameTimeMilliseconds()-self.startTime<1000)
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

mAction.matchesAbilityIcon -- #(#Action:self,#string:abilityIcon, #boolean:strict)->(#boolean)
= function(self, abilityIcon, strict)
  local key = self.ability.id..'/'..abilityIcon..'/'..(strict and 'y' or 'n')
  local value = m.cacheOfActionMatchingAbilityIcon[key]
  if value~=nil then return value end
  value = self:_matchesAbilityIcon(abilityIcon,strict)
  m.cacheOfActionMatchingAbilityIcon[key] = value
  return value
end
mAction._matchesAbilityIcon -- #(#Action:self,#string:abilityIcon, #boolean:strict)->(#boolean)
= function(self, abilityIcon, strict)
  local stripIcon -- #(#string:icon)->(#string)
  = function(icon)
    return icon:gsub("^(.+%d+).+","%1",1)
  end
  local m -- #(#Ability:a)->(#boolean)
  = function(a)
    return (a.icon and abilityIcon:find(stripIcon(a.icon),1,true))
      or (a.icon2 and abilityIcon:find(stripIcon(a.icon2),1, true))
  end
  if m(self.ability) then
    return true
  end
  -- i.e. Merciless Resolve can match Assissin's Will action by its related ability list
  for key, var in ipairs(self.relatedAbilityList) do
    if m(var) then return true end
  end
  return false
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
  -- 1. crux
  if self.showCrux and effect.isCrux then
    return true
  end
  -- 2. tank skills can taunt
  if effect.ability.icon:find('quest_shield_001',18,true) and self.flags.forTank then
    return true
  end
  -- 3. fast check already matched effects unless it is a buff effect
  local isBuff = effect.ability.icon:find('ability_buff_m',1,true)
  if not isBuff then
    for i, var in ipairs(self.effectList) do
      local e = var --#Effect
      if effect.ability.id == e.ability.id then return true end
    end
  end

  local strict = effect.startTime > self.startTime + self.castTime + 2000
  -- 4.0.x if it is minor debuff, it could be non-strict
  if effect.ability.icon:find('ability_debuff_min',1,true) then
    strict = false
  end
  -- 4.0.x if it is following other effect's timeEnds, it could be non-strict
  if strict then -- try to accept continued effect
    local matchEffectsEnd = false
    for key, var in ipairs(self.effectEndTimes) do
      if math.abs(effect.startTime-var) < 500 then
        strict = false
      end
    end
  end
  strict = strict or (effect.duration>0 and effect.duration<4000) -- Render Flesh has a 4 second Minor Defile

  -- 5. check ability match
  if self:matchesAbility(effect.ability, strict) then
    -- 5.a filter non-integer duration effect i.e. Merciless Charge has same icon but 10.9s duration
    if strict and effect.duration%1000>0 and self.duration >0
      and effect.ability.name ~= self.ability.name
      and math.floor(effect.duration/1000+0.5)~= math.floor(self.duration/1000+0.5)
    then
      return false
    end
    --
    return true
  end
  --
  return false
end

mAction.matchesOldEffect -- #(#Action:self,#Effect:effect)->(#boolean)
= function(self, effect)
  -- 1. crux
  if self.showCrux and effect.isCrux then
    return true
  end
  -- 2. taunt
  if effect.ability.icon:find('quest_shield_001',18,true) and self.flags.forTank then
    return true
  end
  -- 3. tick effect
  if self.tickEffect and self.tickEffect.ability.id == effect.ability.id then
    return true
  end
  -- 3. fast check already matched effects
  for i, e in ipairs(self.effectList) do
    if e.ability.id == effect.ability.id and (e.unitId == effect.unitId or effect.unitId==0) then
      return true
    end
  end
  -- 4 stack effect
  if self.stackEffect and self.stackEffect.ability.id == effect.ability.id and (self.stackEffect.unitId== effect.unitId or effect.unitId==0) then
    return true
  end
  if self.stackEffect2 and self.stackEffect2.ability.id == effect.ability.id and (self.stackEffect2.unitId== effect.unitId or effect.unitId==0) then
    return true
  end
  return false
end

local debuggingLastTime = 0 --#number
mAction.optEffect -- #(#Action:self,#boolean:debugging)->(#Effect,#string)
= function(self, debugging)
  if debugging then -- 1 sec threshold
    local now = GetGameTimeMilliseconds()
    if now - debuggingLastTime > 1000 then
      debuggingLastTime = now
    else
      debugging = false
    end
  end
  local optEffect = nil --#Effect
  local reason = ''
  local now = GetGameTimeMilliseconds()
  for i, effect in ipairs(self.effectList) do
    effect.ignored = effect.ignored or now > effect.endTime
    local ignored = effect.ignored
    -- filter Major Gallop if not mount
    if effect.ability.icon:find("major_gallop",1,true) then
      if IsMounted() then return effect,'gallop' end
      reason = reason..'ignored gallop,'
      ignored = true
    end
    -- filter after phase effect e.g. warden's Scorch ending brings some debuff effects
    if self.duration > 3000 and self.startTime+self.duration-300 <= effect.startTime then
      -- only ignore if this duration is not equal to action duration e.g. warden's Subterrian Assault
      if self.duration ~= effect.duration then
        reason = reason..'ignored following duration,'
        ignored = true
      end
    end
    -- filter old effects at new action beginning
    if effect.startTime+1000 < self.startTime -- plus 1000 to improve fault tolerance i.e. Crystal Fragments Proc may have happened in 1000ms
      and now-self.startTime< 300 then
      reason = reason..'ignored previous effect temporaly,'
      ignored = true
    end

    if ignored then
    -- do nothing
    elseif not optEffect then
      optEffect = effect
      reason = reason..'only one'
    else
      if debugging then
        df('[DBG] Comparing %s with %s', optEffect:toLogString(), effect:toLogString())
      end
      optEffect,reason = self:optEffectOf(optEffect,effect)
      if debugging then
        df('[DBG] Opt %s, reason:%s', optEffect:toLogString(), reason)
      end
    end
  end
  return optEffect,reason
end

mAction.optEffectOf -- #(#Action:self,#Effect:effect1,#Effect:effect2)->(#Effect,#string)
= function(self,effect1, effect2)
  -- lower crux priority
  if effect1.isCrux then return effect2 end
  if effect2.isCrux then return effect1 end
  -- override long duration
  if self.flags.forArea and effect1:isLongDuration() ~= effect2:isLongDuration() then
    return effect1:isLongDuration() and effect2 or effect1, "normal prior to long" -- opt normal duration
  end
  -- check 1/2 phase
  if self.data.firstStageId then
    if self.data.firstStageId == effect1.ability.id then return effect1,"first stage" end
    if self.data.firstStageId == effect2.ability.id then return effect2,"first stage" end
  end
  if math.abs(effect1.startTime-effect2.startTime)<500 then
    local isEffect1Bigger = effect1.duration>effect2.duration
    local longEffect = isEffect1Bigger and effect1 or effect2 -- #Effect
    if self.stackEffect == longEffect then return longEffect,'stack effect' end
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
      return isEffect1Bigger and effect2 or effect1,"first stage"
    end
    if longIcon:find('ability_buff_m',30,true) -- for Balance 4s healing and 30s major resolve
      and percent < 15
      and not shortIcon:find('ability_buff_m',30,true)
    then
      self.data.firstStageId = isEffect1Bigger and effect2.ability.id or effect1.ability.id
      return isEffect1Bigger and effect2 or effect1, "prior to major/minor buffs"
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
    -- don't opt buffs which are remnant from old acitons unless it has same duration with action e.g. Bound Armaments
    if effect.startTime < self.startTime and effect.duration~=self.duration and effect.duration~=self.inheritDuration then
      return -1,-1
    end
    -- don't opt buffs which have difference durations
    if self.duration and self.duration >0 and effect.duration ~= self.duration and effect.ability.icon:find('ability_buff_m',1,true) then return -1,-1 end
    -- opt non-player effect for dps, if not area effect
    if (role==LFG_ROLE_DPS or self.flags.forEnemy) and not self.flags.forArea and not effect:isOnPlayer() and effect.duration>0 then px1=2 end
    -- opt player effect for tank
    if role==LFG_ROLE_TANK and effect:isOnPlayer() then px1=2 end
    -- opt player effect for healer, if not area effect, e.g. Regeneration can be applied on player or ally
    if role== LFG_ROLE_HEAL and not self.flags.forArea and effect:isOnPlayer() then px1 =2 end
    -- opt stack effect
    if px1<2 and effect.duration>=math.max(self.duration,self.inheritDuration) and self.stackEffect and effect.ability.id == self.stackEffect.ability.id then px1 = 3 end
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
    local majorEffect = p11>p21 and effect1 or effect2 -- #Effect
    local minorEffect = p11>p21 and effect2 or effect1 -- #Effect
    return majorEffect,"px1"
  end
  if p12~=p22 then
    local majorEffect = p12>p22 and effect1 or effect2 -- #Effect
    local minorEffect = p12>p22 and effect2 or effect1 -- #Effect
    -- ignore same start minor e.g.
    if math.abs(majorEffect.startTime - minorEffect.startTime) <300 then
      l.debug(DS_MODEL,1)("[m.ignore] %s<%d>(%d), px2:%d(%d) ",minorEffect.ability.name, minorEffect.duration,
        minorEffect.ability.id, math.min(p12,p22),math.max(p12,p22))
      minorEffect.ignored = true
    end
    return majorEffect,"px2"
  end
  if effect1.duration~=effect2.duration then
    return effect1.duration < effect2.duration and effect2 or effect1,"longer" -- opt longer duration
  end
  return effect1.endTime < effect2.endTime and effect2 or effect1,"later" -- opt longer duration
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

mAction.purgeEffectByTargetUnitId  -- #(#Action:self,#Effect:effect)->()
= function(self, targetUnitId)
  local purgedEffect = nil -- #Effect
  for key, var in ipairs(self.effectList) do
    if var.unitId == targetUnitId then
      purgedEffect = self:purgeEffect(var)
    end
  end
  if self.flags.forEnemy and purgedEffect then
    -- also purge
    for key, var in ipairs(self.effectList) do
      if math.abs(var.startTime-purgedEffect.startTime)<100 then
        self:purgeEffect(var)
      end
    end
  end
end

mAction.purgeEffect  -- #(#Action:self,#Effect:effect)->(#Effect)
= function(self, effect)
  local oldEffect = effect -- #Effect
  local now = GetGameTimeMilliseconds()
  -- process tickEffect
  if self.tickEffect and self.tickEffect.ability.id==oldEffect.ability.id then
    if self.tickEffectDoubled then
      self.tickEffectDoubled = false
      l.debug(DS_MODEL,1)("[m.purged double tick] %s",  self:toLogString())
      return
    end
    oldEffect = self.tickEffect
    self.tickEffect = nil
    l.debug(DS_MODEL,1)("[m.purged tick] %s",  self:toLogString())
    return
  end
  -- process effectList
  for i, e in ipairs(self.effectList) do
    if e.ability.id == effect.ability.id and e.unitId == effect.unitId then
      local withOldFake = self.oldAction and self.oldAction.fake
      -- if not purging a fake old action and purging earlier than expected (i.e. Minor Breach cut by POL)
      -- or the new action just inherited some old effects that is being cut now
      if not withOldFake and ( e.endTime > now+1000 or e.startTime< self.startTime  ) then
        -- sometimes, effects such as Minor Breach are purged and added when major action effect ends, so we should saved that for a little while
        if not effect.purgingTime then
          effect.purgingTime = now
          -- do it later
          zo_callLater(function() self:purgeEffect(effect) end, 50)
          if l.debugEnabled(DS_MODEL,1) then
            l.debug(DS_MODEL,1)("[m.purging] %s, from %s, #effectList:%d(-1)", e:toLogString(),self:toLogString(), #self.effectList)
          end
          return e
        elseif e.saveTime and e.saveTime >= effect.purgingTime then
          if l.debugEnabled(DS_MODEL,1) then
            l.debug(DS_MODEL,1)("[m.purge-renewed] %s, in %s",  e:toLogString(), self:toLogString())
          end
          return e
        end
      end
      table.remove(self.effectList,i)
      if l.debugEnabled(DS_MODEL,1) then
        l.debug(DS_MODEL,1)("[m.purged] %s, from %s",e:toLogString(), self:toLogString())
      end
      oldEffect = e -- we need duration info to end action
      break
    end
  end
  if self.stackEffect and self.stackEffect.ability.id == effect.ability.id and self.stackEffect.unitId==effect.unitId then
    oldEffect = self.stackEffect
    self.stackEffect = nil
  end
  if self.stackEffect2 and self.stackEffect2.ability.id == effect.ability.id and self.stackEffect2.unitId==effect.unitId then
    oldEffect = self.stackEffect2
    self.stackEffect2 = nil
  end
  local availableEffectCount = 0
  local reason = ''
  for key, var in pairs(self.effectList) do
    if not var.ignored then
      local ok = true
      if self.flags.forEnemy and oldEffect
        and var.ability.id~=oldEffect.ability.id -- count if this effect has same id
        and var.unitId~=oldEffect.unitId -- count if this effect has same unit id
        and math.abs(oldEffect.startTime-var.startTime)<100 -- count if this effect comes at a different time
      then
        ok = false
        reason = reason .. string.format('not counted as available:%s\n',var:toLogString())
      end
      if ok then
        availableEffectCount = availableEffectCount+1
      end
    else
      reason = reason.. string.format('%s is ignored and not counted\n',var.ability.name)
    end
  end
  if availableEffectCount==0 and oldEffect.duration > 0 and -- last duration effect has faded
    (
    -- the old effect SHOULD be brought by this action rather than an old one, or this might be a renew rather than end
    (oldEffect.startTime>= self.startTime)
    or
    (
    -- either the current one or the old one is fake, so a real action now is triggered and we should do a purge
    self.fake or (self.oldAction and self.oldAction.fake)
    )
    )
  then
    l.debug(DS_MODEL,1)("[m.purge end] %s, %s", reason, self:toLogString())
    self.endTime = now
  else
    l.debug(DS_MODEL,1)("[m.purge not end] %s, %s", reason, self:toLogString())
  end
  return oldEffect
end

mAction.saveEffect -- #(#Action:self, #Effect:effect)->(#Effect)
= function(self, effect)
  if effect.drop then return end
  -- ignore pure stack effect, they should have been saved using updateStackInfo
  if effect.stackCount>0 and effect.duration==0 then
    return
  end

  -- process effect with tickRate
  if effect.tickRate >0 then
    if self.tickEffect and self.tickEffect.ability.id == effect.ability.id then
      self.tickEffectDoubled = true
      return
    end
    self.tickEffect = effect
    return
  end
  
  -- debuff longer than default duration BUT: people think debuf is usefly i.e. Mass Hysteria
  if self.duration and self.duration >0 and effect.duration>self.duration
    and effect.ability.icon:find('ability_debuff_',1,true)
  then
    effect.ignorableDebuff = true
  end

  -- ignore abnormal long duration effect
  if self.duration and self.duration >=10000
    and effect.duration > self.duration * 3  -- changed from 1.5 to 3 because of Everlasting Sweep could extend the duration based enemies hit
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
  -- modified for Unnerving Boneyard skill
  if self.ability.icon:find('necromancer_004',1,true) and effect.duration>10000 then
    return
  end

  self.lastEffectTime = effect.startTime
  for i, e in ipairs(self.effectList) do
    if e.ability.id == effect.ability.id and e.unitId == effect.unitId then
      local now = GetGameTimeMilliseconds()
      if math.abs(e.endTime-effect.endTime)>1000 then
        self.effectList[i] = effect
        -- save effect end time to aid judgement on the strictness of following effects
        if self.effectEndTimes[#self.effectEndTimes]~= effect.endTime then
          self.effectEndTimes[#self.effectEndTimes+1] = effect.endTime
        end
      end
      self.effectList[i].saveTime = now -- #number
      return e
    end
  end
  table.insert(self.effectList, effect)
  -- save effect end time to aid judgement on the strictness of following effects
  if self.effectEndTimes[#self.effectEndTimes]~= effect.endTime then
    self.effectEndTimes[#self.effectEndTimes+1] = effect.endTime
  end
  -- record targetId for enemy actions
  if self.flags.forEnemy and effect.unitId>0 then
    self.targetId = effect.unitId
  end
  -- record first ground effect id for triggering recognition
  if #self.effectList == 1 and self.flags.forGround
    and (self.groundFirstEffectId~=-1 or self.ability.id==effect.ability.id)then
    self.groundFirstEffectId = effect.ability.id -- #number
  end
  return nil
end

mAction.toLogString --#(#Action:self)->(#string)
= function(self)
  local effectListLog = #self.effectList>0 and ':' or ''
  for key, effect in ipairs(self.effectList) do
    effectListLog= effectListLog ..'\n+ [e] '.. effect:toLogString()
  end
  local tickEffectLog = self.tickEffect and string.format('\n+ [t] %s',self.tickEffect:toLogString()) or ''
  return string.format("$Action%d%s-%s@%s%.2f~%.2f(%.2f)<%.2f>%s bar%dslot%d\n%s%s%s%s",
    self.sn,
    self.fake and '(fake)' or '',
    self.ability:toLogString(),
    self.channelStartTime>0 and string.format('channeling(%d)@',self.channelUnitId or 0) or '',
    self.startTime/1000,
    self:getEndTime()/1000, self.endTime/1000,self:getDuration()/1000,
    self.stackCount==0 and '' or string.format("#stackCount:%d",self.stackCount),
    self.hotbarCategory,self.slotNum,
    self:getFlagsInfo(),
    self.oldAction and string.format("\noldAction:$Action%d-%s@%.2f~%.2f(%.2f)<%.2f>%s",self.oldAction.sn, self.oldAction.ability:toLogString(), self.oldAction.startTime/1000,
      self.oldAction:getEndTime()/1000, self.oldAction.endTime/1000,self.oldAction:getDuration()/1000,
      self.oldAction.fake and 'fake,' or '') or '\nwithoutOld',
    effectListLog,
    tickEffectLog
  )
end

mAction.updateStackInfo --#(#Action:self, #number:stackCount, #Effect:effect)->(#boolean)
= function(self, stackCount, effect)
  if l.debugEnabled(DS_MODEL,1) then
    l.debug(DS_MODEL,1)('[m.us]updating stackCount to %d from %s in %s',stackCount, effect:toLogString(), self:toLogString());
  end
  local addType = 0
  if not self.stackEffect then
    addType = 1
    -- filter sudden big stack at action beginning
    if stackCount>=2 -- filter sudden stack like Stone Giant
      and GetGameTimeMilliseconds()-self.startTime<500 -- in the beginning
      and not self.fake -- not for fake actions
    then
      addType = 2
      if self.stackEffect2 and self.stackEffect2.ability.id~= effect.ability.id then
        addType = 0
        l.debug(DS_MODEL,1)('[m.us.filtered] ingored because old stackEffect2 existed: %s ',self.stackEffect2:toLogString());
      end
    end
  elseif self.stackEffect.ability.id == effect.ability.id then
    addType = 1
  elseif not self.stackEffect2 or self.stackEffect2.ability.id == effect.ability.id then
    addType = 2
  end
  if addType == 1 then
    self.stackCount = stackCount
    self.stackEffect = effect
    self.stackCountMatch = false -- #boolean
    self.stackCountMatch = stackCount>=3 and #self.effectList==0 and self.descriptionNums[stackCount]
    return true
  elseif addType == 2 then
    self.stackCount2 = stackCount
    self.stackEffect2 = effect
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

mEffect.toLogString --#(#Effect:self)->(#string)
= function(self)
  return string.format("%s, %.2f~%.2f<%d>, stack:%d, %s, unit:%s(%d) %s",  self.ability:toLogString(),self.startTime/1000, self.endTime/1000,
    self.duration/1000, self.stackCount, self.tickRate==0 and '' or string.format('tickRate:%d',self.tickRate),self.unitTag, self.unitId,
    self.ignored and ' [ignored]' or '')
end
--========================================
--        register
--========================================
addon.register("Models#M", m)

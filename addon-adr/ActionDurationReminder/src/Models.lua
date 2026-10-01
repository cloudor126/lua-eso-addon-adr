--========================================
--        vars
--========================================
---@type adr.addon.M
local addon = ActionDurationReminder
---@type adr.settings.M
local settings = addon.load("Settings#M")
local l = {}
---@type adr.models.M
local m = { l = l }
---@type adr.models.Action
local mAction = {}
---@type adr.models.Ability
local mAbility = {}
---@type adr.models.Effect
local mEffect = {}

--========================================
--        types
--========================================
---主键槽位动作(面板技能)运行时对象，构造于m.newAction，setmetatable({},{__index=mAction})
---@class adr.models.Action
---@field fake? boolean
---@field sn? number
---@field targetOut? boolean
---@field slotNum? number
---@field crafted? boolean
---@field craftedId? number
---@field ability? adr.models.Ability
---@field relatedAbilityList? adr.models.Ability[]
---@field channeled? boolean
---@field castTime? number
---@field startTime? number
---@field placementTime? number 布放时间：forArea/forGround重置startTime前记录的原始值，供'@'激活判定测延迟
---@field duration? number
---@field configDuration? number
---@field inheritDuration? number
---@field showCrux? number 仅作真值用
---@field showNothingWasted? number 仅作真值用
---@field description? string
---@field effectEndTimes? number[]
---@field descriptionDuration? number
---@field descriptionNums? table<number, boolean>
---@field endTime? number
---@field inCombat? boolean
---@field lastEffectTime? number
---@field channelStartTime? number
---@field channelEndTime? number
---@field channelUnitId? number
---@field oldAction? adr.models.Action
---@field newAction? adr.models.Action
---@field hotbarCategory? number
---@field flags? adr.models.ActionFlags
---@field data? table
---@field effectList? adr.models.Effect[]
---@field stackEffect? adr.models.Effect
---@field stackEffect2? adr.models.Effect 触发加成层数
---@field tickEffect? adr.models.Effect
---@field tickEffectDoubled? boolean
---@field mainEffectPurged? boolean
---@field targetId? number
---@field saved? boolean
---@field alertSkipResult? boolean
---@field groundFirstEffectId? number
---@field getStageInfo2_Stamp? number
---@field getStageInfo2_Cache? number
---@field stackCountMatch? number|boolean
---@field getAreaEffectCount? fun(self: adr.models.Action): number?
---@field getDuration? fun(self: adr.models.Action): number, string
---@field getEndTime? fun(self: adr.models.Action, debugging?: boolean): number
---@field getFullEndTime? fun(self: adr.models.Action): number
---@field getFlagsInfo? fun(self: adr.models.Action): string
---@field getMaxOriginEffectDuration? fun(self: adr.models.Action): number?
---@field getNewest? fun(self: adr.models.Action): adr.models.Action?
---@field getOldest? fun(self: adr.models.Action): adr.models.Action?
---@field getStageInfo? fun(self: adr.models.Action): string?
---@field getStageInfo2? fun(self: adr.models.Action): number?
---@field getStartTime? fun(self: adr.models.Action): number?
---@field getStackEffect? fun(self: adr.models.Action): adr.models.Effect?
---@field getStackEffect2? fun(self: adr.models.Action): adr.models.Effect?
---@field needEndingAlert? fun(self: adr.models.Action): boolean
---@field hasEffect? fun(self: adr.models.Action): boolean
---@field isOnPlayer? fun(self: adr.models.Action): boolean
---@field isOnPlayerpet? fun(self: adr.models.Action): boolean
---@field isUnlimited? fun(self: adr.models.Action): boolean?
---@field matchesAbility? fun(self: adr.models.Action, ability: adr.models.Ability, strict?: boolean): boolean?
---@field matchesAbilityId? fun(self: adr.models.Action, abilityId: number, strict?: any): boolean?
---@field matchesAbilityIcon? fun(self: adr.models.Action, abilityIcon: string, strict?: boolean): boolean
---@field _matchesAbilityIcon? fun(self: adr.models.Action, abilityIcon: string, strict?: boolean): boolean
---@field matchesAbilityName? fun(self: adr.models.Action, abilityName: string, strict?: boolean): boolean
---@field _matchesAbilityName? fun(self: adr.models.Action, abilityName: string, strict?: boolean): boolean
---@field matchesNewEffect? fun(self: adr.models.Action, effect: adr.models.Effect): boolean
---@field _matchesNewEffect? fun(self: adr.models.Action, effect: adr.models.Effect): boolean
---@field matchesOldEffect? fun(self: adr.models.Action, effect: adr.models.Effect): boolean
---@field calclevel? fun(self: adr.models.Action, effect: adr.models.Effect): number
---@field sortEffectList? fun(self: adr.models.Action)
---@field recalcEffectLevels? fun(self: adr.models.Action)
---@field isFilteredByDynamic? fun(self: adr.models.Action, effect: adr.models.Effect, now: number): boolean
---@field optEffect? fun(self: adr.models.Action, debugging?: boolean): adr.models.Effect?, string
---@field optGallopEffect? fun(self: adr.models.Action): adr.models.Effect|false
---@field peekLongDurationEffect? fun(self: adr.models.Action): adr.models.Effect?
---@field purgeEffectByTargetUnitId? fun(self: adr.models.Action, effect: adr.models.Effect)
---@field purgeEffect? fun(self: adr.models.Action, effect: adr.models.Effect): adr.models.Effect|false?
---@field saveEffect? fun(self: adr.models.Action, effect: adr.models.Effect): adr.models.Effect?
---@field toLogString? fun(self: adr.models.Action): string
---@field toLogString_Short? fun(self: adr.models.Action): string
---@field toLogString_SingleLine? fun(self: adr.models.Action): string
---@field updateStackInfo? fun(self: adr.models.Action, stackCount: number, effect: adr.models.Effect): boolean
---@field isSpecialStackEffect? fun(self: adr.models.Action, effect: adr.models.Effect): boolean

---技能静态信息对象，构造于m.newAbility，setmetatable({},{__index=mAbility})
---@class adr.models.Ability
---@field id? number
---@field type? number
---@field showName? string
---@field name? string
---@field icon? string
---@field icon2? string
---@field progressionName? string
---@field icon3? string
---@field description? string
---@field matches? fun(self: adr.models.Ability, other: adr.models.Ability, strict: boolean): boolean
---@field toLogString? fun(self: adr.models.Ability): string

---效果(玩家/目标身上的buff、dot、tick)运行时对象，构造于m.newEffect，setmetatable({},{__index=mEffect})
---@class adr.models.Effect
---@field ability? adr.models.Ability
---@field isCrux? boolean
---@field unitTag? string player|playerpet|others
---@field unitId? number
---@field startTime? number
---@field endTime? number
---@field duration? number
---@field ignored? boolean
---@field ignorableDebuff? boolean
---@field stackCount? number
---@field tickRate? number
---@field combatEventId? number 可追踪的特定战斗事件
---@field combatGrantTime? number combat事件授层时间戳，用于[C-s]区分换实例消退与真到期消退
---@field level? number
---@field levelIsLow? boolean
---@field stageInfo? string
---@field stageInfoBlink? boolean
---@field activated? boolean
---@field saveTime? number
---@field purgingTime? number
---@field drop? boolean
---@field isOnPlayer? fun(self: adr.models.Effect): boolean
---@field isOnPlayerpet? fun(self: adr.models.Effect): boolean
---@field isLongDuration? fun(self: adr.models.Effect): boolean
---@field isMajorMinorBuff? fun(self: adr.models.Effect): boolean
---@field isMinorBuff? fun(self: adr.models.Effect): boolean
---@field toLogString? fun(self: adr.models.Effect): string

---动作标志位集合(见m.newAction构造)
---@class adr.models.ActionFlags
---@field forArea? boolean
---@field forEnemy? boolean
---@field forGround? boolean
---@field forSelf? boolean
---@field forTank? boolean
---@field shifted? boolean
---@field isShifted? boolean
---@field onlyOneTarget? boolean

---魔核(crux)管理器
---@class adr.models.Crux
---@field effect? adr.models.Effect
---@field getEffect? fun(): adr.models.Effect
---@field setEffect? fun(effect: adr.models.Effect)

---Nothing Wasted(死灵隐藏叠层buff)管理器：纯事件驱动，12秒窗口由自身维护
---@class adr.models.NothingWasted
---@field effect? adr.models.Effect
---@field getEffect? fun(): adr.models.Effect?
---@field update? fun(stackCount: number, windowEndTime: number)
---@field clear? fun()

---Models模块公开表(addon.register("Models#M"))
---@class adr.models.M
---@field DRAGONKNIGHT_CLASS_ID? number
---@field FLAME_LASH_ICON_KEYWORD? string
---@field OFF_BALANCE_ICON_KEYWORD? string
---@field POWER_LASH_ABILITY_ID? number
---@field POWER_LASH_GUIDE_ABILITY_ID? number
---@field NOTHING_WASTED_ABILITY_ID? number
---@field NOTHING_WASTED_WINDOW_MS? number
---@field DUR_SOURCE_TICK? string
---@field DUR_SOURCE_CHANNEL? string
---@field DUR_SOURCE_FILTER? string
---@field DUR_SOURCE_PRIORITY? string
---@field DUR_SOURCE_SELF? string
---@field DUR_SOURCE_DESC? string
---@field DUR_SOURCE_NONE? string
---@field crux? adr.models.Crux
---@field nothingWasted? adr.models.NothingWasted
---@field cacheOfActionMatchingEffect? table<string, boolean>
---@field cacheOfActionMatchingAbilityName? table<string, boolean>
---@field cacheOfActionMatchingAbilityIcon? table<string, boolean>
---@field patchAbilityName? fun(name: string): string
---@field newAbility? fun(id: number, name: string, icon: string): adr.models.Ability
---@field newAction? fun(slotNum: number, hotbarCategory: number): adr.models.Action
---@field newEffect? fun(ability: adr.models.Ability, unitTag: string, unitId: number, startTime: number, endTime: number, stackCount: number, tickRate: number): adr.models.Effect

local DS_MODEL = "model" -- debug switch for model

-- DSS (Debug Switch + SubSwitch) constants for addon.debugEnabled
local DSS_MODEL_STACK = { DS_MODEL, "stack" }
local DSS_MODEL_PURGE = { DS_MODEL, "purge" }

--========================================
--        Effect Priority Levels
--========================================
-- Lower number = higher priority
local LEVEL_ACTION_ID_MATCH = 1 -- effect.ability.id matches action.ability.id with matching duration
local LEVEL_STACK_EFFECT = 2 -- effect is action.stackEffect
local LEVEL_STACK_EFFECT_2 = 3 -- effect is action.stackEffect2
local LEVEL_ROLE_PREFERRED = 4 -- DPS: non-player effect; Tank/Healer: player effect
local LEVEL_DURATION_MATCH = 5 -- effect.duration matches action.duration
local LEVEL_LONGER_DURATION = 6 -- normal longer duration effect
local LEVEL_TAIL_EFFECT = 7 -- effect significantly longer than action (tail effect, secondary)
local LEVEL_MAJOR_MINOR_BUFF = 8 -- major/minor buff as side effect
local LEVEL_CRUX = 9 -- Crux effect (lowest priority)

local LEVEL_THRESHOLD_LOW = LEVEL_TAIL_EFFECT -- effects at this level or lower shown with brackets []

--========================================
--        Game Constants
--========================================
m.DRAGONKNIGHT_CLASS_ID = 1
m.FLAME_LASH_ICON_KEYWORD = "dragonknight_001_a"
m.OFF_BALANCE_ICON_KEYWORD = "ability_debuff_offbalance"
m.POWER_LASH_ABILITY_ID = 20824 -- Power Lash
m.POWER_LASH_GUIDE_ABILITY_ID = -999001 -- fake ability id for Power Lash guide effect

--========================================
--        Duration Source Constants
--========================================
m.DUR_SOURCE_TICK = "T" -- from Tick effect
m.DUR_SOURCE_CHANNEL = "C" -- from Channel
m.DUR_SOURCE_FILTER = "F" -- from Filter (configDuration)
m.DUR_SOURCE_PRIORITY = "P" -- from Priority effect (optEffect)
m.DUR_SOURCE_SELF = "S" -- from Self (action.duration)
m.DUR_SOURCE_DESC = "D" -- from Description
m.DUR_SOURCE_NONE = "" -- no duration

--========================================
--        Global Crux Registry
--========================================
---@type adr.models.Crux
local mCrux = {} -- private table for crux management
m.crux = mCrux -- expose to public

mCrux.effect = nil -- current active crux effect
---@type fun(): adr.models.Effect
mCrux.getEffect = function()
  return mCrux.effect
end

---@type fun(effect: adr.models.Effect)
mCrux.setEffect = function(effect)
  if effect then
    effect.level = LEVEL_CRUX
    effect.levelIsLow = true
  end
  mCrux.effect = effect
end

--========================================
--        Global Nothing Wasted Registry (Necromancer)
--========================================
m.NOTHING_WASTED_ABILITY_ID = 263461
m.NOTHING_WASTED_WINDOW_MS = 12000 -- the buff API reports no timing (0~0), window maintained from events

---@type adr.models.NothingWasted
local mNW = {}
m.nothingWasted = mNW

---@type fun(): adr.models.Effect?
mNW.getEffect = function()
  local effect = mNW.effect
  if effect and effect.stackCount > 0 and effect.endTime > GetGameTimeMilliseconds() then
    return effect
  end
  return nil
end

---@type fun(stackCount: number, windowEndTime: number)
mNW.update = function(stackCount, windowEndTime)
  if not mNW.effect then
    local ability = m.newAbility(
      m.NOTHING_WASTED_ABILITY_ID,
      GetAbilityName(m.NOTHING_WASTED_ABILITY_ID),
      GetAbilityIcon(m.NOTHING_WASTED_ABILITY_ID)
    )
    mNW.effect = m.newEffect(ability, "player", 0, GetGameTimeMilliseconds(), windowEndTime, stackCount, 0)
  else
    mNW.effect.stackCount = stackCount
    mNW.effect.endTime = windowEndTime
    mNW.effect.duration = windowEndTime - mNW.effect.startTime
  end
  mNW.effect.level = LEVEL_CRUX
  mNW.effect.levelIsLow = true
end

---@type fun()
mNW.clear = function()
  mNW.effect = nil
end

local SPECIAL_DURATION_PATCH = {
  ["/esoui/art/icons/ability_warden_015_b.dds"] = 6000,
}

-- 中文技能名补丁：修正ESO翻译错别字
local NAME_PATCH_ZH = {
  ["鞭挞"] = "鞭笞",
}

-- 应用技能名补丁，返回修正后的名称
---@type fun(name: string): string
m.patchAbilityName = function(name)
  if GetCVar("language.2") ~= "zh" then
    return name
  end
  for wrong, right in pairs(NAME_PATCH_ZH) do
    if name:find(wrong, 1, true) then
      return (name:gsub(wrong, right)) -- 括号截断gsub第二返回值，统一单返回
    end
  end
  return name
end

---@type fun(path: string): string
local fRefinePath = function(path)
  if not path then
    return path
  end
  path = path:lower()
  -- 过滤三个数字后的部分，例如 "/esoui/art/icons/ability_werewolf_002_rend_b.dds"
  -- 变为"/esoui/art/icons/ability_werewolf_002"
  path = path:match("(.-[0-9][0-9][0-9])") or path
  local index = path:find(".dds", 1, true)
  if index and index > 1 then
    path = path:sub(1, index - 1)
  end
  return path
end

---@type fun(path: string): string?
local fSkillIconName = function(path)
  if not path then
    return nil
  end
  local name = path:match("([^/]+)%.") or path
  name = name:gsub("_[ab]$", "")
  return name:lower()
end

---@type fun(path1: string, path2: string): boolean|number?
local fMatchIconPath = function(path1, path2)
  if path1 == "" or path1 == "/" or path2 == "" or path2 == "/" then
    return false
  end
  if path1 == path2 then
    return true
  end -- fast check
  path1 = fRefinePath(path1)
  path2 = fRefinePath(path2)
  return path1:find(path2, 1, true) or path2:find(path1, 1, true)
end

---@type fun(origin: string, zh?: boolean): string, integer
local fStripBracket = function(origin, zh)
  if zh then
    return origin:gsub("^%s*([^<]+)%s*<.*$", "%1", 1)
  else
    return origin:gsub("^[^<]+<%s*([^>]+)%s*>.*$", "%1", 1)
  end
end

--========================================
--        l
--========================================

--========================================
--        m
--========================================
---@type table<string, boolean>
m.cacheOfActionMatchingEffect = {}
---@type table<string, boolean>
m.cacheOfActionMatchingAbilityName = {}
---@type table<string, boolean>
m.cacheOfActionMatchingAbilityIcon = {}
---@type fun(id: number, name: string, icon: string): adr.models.Ability
m.newAbility = function(id, name, icon)
  ---@type adr.models.Ability
  local ability = {}
  ---@type fun(icon: string): string
  local getIconPath = function(icon)
    return icon:sub(1, 1) == "/" and icon or ("/" .. icon)
  end
  icon = getIconPath(icon)
  ability.id = id
  ability.type = 0
  ability.showName = zo_strformat("<<1>>", name)
  ability.name = fStripBracket(ability.showName)
  if ability.showName ~= ability.name then
    ability.showName = fStripBracket(ability.showName, true)
  end
  ability.icon = icon
  local icon2 = getIconPath(GetAbilityIcon(id))
  if icon2 ~= icon then
    ability.icon2 = icon2
  end
  local hasProgression, progressionIndex = GetAbilityProgressionXPInfoFromAbilityId(id)
  ability.progressionName = hasProgression and GetAbilityProgressionInfo(progressionIndex) or nil
  if ability.progressionName and ability.progressionName ~= name then
    ability.progressionName = zo_strformat("<<1>>", ability.progressionName)
    ability.progressionName = fStripBracket(ability.progressionName)
  else
    ability.progressionName = nil
  end -- only keep different name
  if hasProgression and progressionIndex then
    local _, icon3, _ = GetAbilityProgressionAbilityInfo(progressionIndex, 0, 1)
    if icon3 ~= icon then
      ability.icon3 = icon3
    end
  end
  ability.description = GetAbilityDescription(id):gsub("%^%w", "")
  setmetatable(ability, { __index = mAbility })
  return ability
end

local seed = 0
local nextSeed = function()
  seed = seed + 1
  return seed
end
---@type fun(slotNum: number, hotbarCategory: number): adr.models.Action
m.newAction = function(slotNum, hotbarCategory)
  ---@type adr.models.Action
  local action = {}
  action.fake = false
  action.sn = nextSeed()
  action.targetOut = false
  action.slotNum = slotNum
  local abilityId = GetSlotBoundId(slotNum, hotbarCategory)
  local slotType = GetSlotType(slotNum, hotbarCategory)
  action.crafted = false
  if slotType == ACTION_TYPE_CRAFTED_ABILITY then
    action.crafted = true
    action.craftedId = abilityId
    abilityId = GetAbilityIdForCraftedAbilityId(abilityId)
  end
  ---@type adr.models.Ability
  action.ability = m.newAbility(
    abilityId,
    m.patchAbilityName(GetSlotName(slotNum, hotbarCategory)),
    GetSlotTexture(slotNum, hotbarCategory)
  )
  ---for matching
  ---@type adr.models.Ability[]
  action.relatedAbilityList = {}
  local channeled, castTime = GetAbilityCastInfo(action.ability.id)
  action.channeled = channeled
  action.castTime = castTime or 0
  action.startTime = GetGameTimeMilliseconds()
  action.duration = SPECIAL_DURATION_PATCH[action.ability.icon] or GetAbilityDuration(action.ability.id) or 0
  action.configDuration = nil
  if action.duration < 1000 then
    action.duration = 0
  end
  action.inheritDuration = 0
  action.showCrux = action.ability.icon:find("arcanist_002", 18, true)
    or action.ability.icon:find("arcanist_003_b", 18, true)
  action.showNothingWasted = action.ability.icon:find("necromancer_005", 18, true)
  local description = action.ability.description
  if action.crafted then
    local sid1, sid2, sid3 = GetCraftedAbilityActiveScriptIds(action.craftedId)
    description = description
      .. "\n"
      .. GetCraftedAbilityScriptDescription(action.craftedId, sid1)
      .. "\n"
      .. GetCraftedAbilityScriptDescription(action.craftedId, sid2)
      .. "\n"
      .. GetCraftedAbilityScriptDescription(action.craftedId, sid3)
  end
  action.description = zo_strformat("<<1>>", description)
  action.ability.description = action.description
  ---@type number[]
  action.effectEndTimes = {}

  -- look for XX seconds in description i.e. in eso 8.2.0 Dark Donvertion has 10s duration but a 20s description duration
  local pattern = zo_strformat(GetString(SI_TIME_FORMAT_SECONDS_DESC), 2)
  if GetCVar("language.2") == "zh" then
    pattern = "2秒"
  end
  pattern = ".-(" .. pattern:gsub("2", "([%%.,%%d]*%%d+).r") .. ")"
  -- /script pattern = '.-('..zo_strformat(GetString(SI_TIME_FORMAT_SECONDS_DESC),2):gsub("2","([%%.,%%d]*%%d+).r")..')'
  ---@type number? offset可为find返回的nil
  local offset = 1
  local num = 0
  while true do
    local i, j, seg, numStr = action.description:find(pattern, offset)
    if not i then
      break
    end
    offset = j
    local n = tonumber((numStr:gsub(",", "."))) * 1000
    if num == 0 or n < 30000 and n > num then -- only overide if n<30s and n > num e.g. in DK's Deep Breath description there are 2 sec and 2.5 sec segments
      num = n
    end
  end
  if num > 0 then
    action.descriptionDuration = num
  end
  -- find number for stack times
  ---@type table<number, boolean>
  action.descriptionNums = {}
  pattern = ".-([%.,%d]*%d+).r"
  ---@type number? offset可为find返回的nil
  offset = 1
  while true do
    local i, j, numStr = action.description:find(pattern, offset)
    if not i then
      break
    end
    offset = j
    local n = tonumber((numStr:gsub(",", ".")))
    if not n then
      break
    end
    if (n * 1000) % 1000 == 0 then
      action.descriptionNums[n] = true
    end
  end

  action.endTime = action.duration == 0 and 0 or action.startTime + action.duration
  action.inCombat = IsUnitInCombat("player")
  action.lastEffectTime = 0
  action.channelStartTime = 0
  action.channelEndTime = 0
  action.channelUnitId = 0
  ---@type adr.models.Action
  action.oldAction = nil
  ---@type adr.models.Action
  action.newAction = nil

  action.hotbarCategory = hotbarCategory
  local target = GetAbilityTargetDescription(action.ability.id)
  local radius = GetAbilityRadius(action.ability.id)
  local forArea = target == GetString(SI_ABILITY_TOOLTIP_TARGET_TYPE_AREA) and (radius == 0 or radius > 200)
  forArea = forArea or target == GetString(SI_ABILITY_TOOLTIP_TARGET_TYPE_CONE)
  local forEnemy = target == GetString(SI_TARGETTYPE0)
  local forGround = target == GetString(SI_ABILITY_TOOLTIP_TARGET_TYPE_GROUND)
  local forSelf = target == GetString(SI_ABILITY_TOOLTIP_RANGE_SELF) or radius == 500 or target == "自己" --[[汉化组修正翻译前的补丁]]
  local forTank = GetAbilityRoles(action.ability.id)
    -- Frost Clench can taunt
    or action.ability.icon:find("destructionstaff_005_a", 18, true)

  ---@type adr.models.ActionFlags
  action.flags = {
    forArea = forArea,
    forEnemy = forEnemy,
    forGround = forGround,
    forSelf = forSelf,
    forTank = forTank,
    shifted = false,
    onlyOneTarget = false,
  }
  action.data = {} --to store data in
  ---@type adr.models.Effect[]
  action.effectList = {}
  ---@type adr.models.Effect
  action.stackEffect = nil
  ---for triggered bonus stacks
  ---@type adr.models.Effect
  action.stackEffect2 = nil
  ---@type adr.models.Effect
  action.tickEffect = nil
  action.tickEffectDoubled = false
  action.mainEffectPurged = false
  action.targetId = nil
  setmetatable(action, { __index = mAction })
  return action
end

---@type fun(ability: adr.models.Ability, unitTag: string, unitId: number, startTime: number, endTime: number, stackCount: number, tickRate: number): adr.models.Effect
m.newEffect = function(ability, unitTag, unitId, startTime, endTime, stackCount, tickRate)
  ---@type adr.models.Effect
  local effect = {}
  ---@type adr.models.Ability
  effect.ability = ability
  if effect.ability.icon:find("arcanist_crux", 18, true) then
    effect.isCrux = true
  end
  effect.unitTag = unitTag:find("player", 1, true) and unitTag or "others" --player or playerpet or others
  effect.unitId = unitId
  effect.startTime = startTime
  effect.endTime = endTime
  effect.duration = endTime - startTime
  effect.ignored = false
  effect.ignorableDebuff = false
  effect.stackCount = stackCount or 0
  effect.tickRate = tickRate or 0
  effect.combatEventId = nil --can be used to track one more special combat event
  effect.level = 99
  effect.levelIsLow = true
  setmetatable(effect, { __index = mEffect })
  return effect
end

local function matchFunc(s1, s2, full)
  if s1 == "" or s2 == "" then
    return false
  end
  if s1 == s2 then
    return true
  end
  if not full and (s1:find(s2, 1, true) or s2:find(s1, 1, true)) then
    return true
  end
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
---@type fun(self: adr.models.Ability, other: adr.models.Ability, strict: boolean): boolean
mAbility.matches = function(self, other, strict)
  local idHash = getIdHash(self.id, other.id or 0)
  local stringMatchRes = matchesMemo[strict or false][idHash]
  if stringMatchRes ~= nil then
    return stringMatchRes
  end

  if self.id == other.id then
    memoizeMatch(idHash, strict, true)
    return true
  end
  if fMatchIconPath(self.icon, other.icon) then
    memoizeMatch(idHash, strict, true)
    return true
  end
  if other.icon2 then
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
  if matchFunc(self.name, other.name, true) then
    memoizeMatch(idHash, strict, true)
    return true
  end
  if self.progressionName and matchFunc(self.progressionName, other.name, true) then
    memoizeMatch(idHash, strict, true)
    return true
  end
  if
    not strict
    and not addon.isSimpleWord(other.name) -- do not match a one word name in description
    and self.description
  then
    if matchFunc(self.description, other.name) then
      memoizeMatch(idHash, strict, true)
      return true
    end
    if self.description:find(other.name:gsub(" ", " %%w+ %%w+ ")) then
      memoizeMatch(idHash, strict, true)
      return true
    end -- i.e. match major sorcery in critical surge description: major brutality and sorcery
  end

  memoizeMatch(idHash, strict, false)
  return false
end

---@type fun(self: adr.models.Ability): string
mAbility.toLogString = function(self)
  return string.format("|t24:24:%s|t %s(%i/%s)", self.icon, self.name, self.id, self.icon:match("([^/]+)%.%w+$"))
end

--========================================
--        mAction
--========================================
---@type fun(self: adr.models.Action): number?
mAction.getAreaEffectCount = function(self)
  local count = 0
  for key, var in pairs(self.effectList) do
    if var.ability.type == ABILITY_TYPE_AREAEFFECT then
      count = count + 1
    end
  end
  return count > 0 and count or nil
end

---@type fun(self: adr.models.Action): number, string
mAction.getDuration = function(self)
  if self.tickEffect and self.duration == 0 then
    return self.tickEffect.tickRate, m.DUR_SOURCE_TICK
  end
  if self.channelStartTime > 0 and self.channelEndTime > 0 then
    return self.channelEndTime - self.channelStartTime, m.DUR_SOURCE_CHANNEL
  end
  if self.configDuration then
    return self.configDuration, m.DUR_SOURCE_FILTER
  end
  ---@type adr.models.Effect
  local optEffect, reason = self:optEffect()
  if optEffect then
    return optEffect.duration, m.DUR_SOURCE_PRIORITY
  end
  if self.showCrux and not self:getStackEffect() then
    return 0, m.DUR_SOURCE_NONE
  end
  if self.duration and self.duration > 0 then
    return self.duration, m.DUR_SOURCE_SELF
  end
  if self.descriptionDuration and self.descriptionDuration > 0 then
    return self.descriptionDuration, m.DUR_SOURCE_DESC
  end
  return 0, m.DUR_SOURCE_NONE
end

---@type fun(self: adr.models.Action, debugging?: boolean): number
mAction.getEndTime = function(self, debugging)
  if self.tickEffect and self.duration == 0 then
    local start = self.tickEffect.startTime
    local now = GetGameTimeMilliseconds()
    local span = now - start
    local offset = span - span % self.tickEffect.tickRate
    return start + offset + self.tickEffect.tickRate
  end
  if self.channelEndTime > 0 then
    return self.channelEndTime
  end
  if self.configDuration then
    return self.startTime + self.configDuration
  end
  ---@type adr.models.Effect
  local optEffect, reason = self:optEffect()
  reason = reason or "nil"
  local now = GetGameTimeMilliseconds()
  if optEffect then
    if debugging and optEffect.endTime - self.endTime < 1000 then
      self:optEffect(true)
    end
    if optEffect.ignorableDebuff and optEffect.endTime > self.endTime and self.endTime > GetGameTimeMilliseconds() then
      self.data.firstStageId = self.ability.id
      return self.endTime
    end
    return optEffect.endTime
  end
  if self.endTime > 0 then
    return self.endTime
  end
  if self.showCrux and not optEffect and not self:getStackEffect() then
    return self.startTime
  end -- 可能曾经有crux单现在一无所有
  local maxEffectEndTime = 0
  for key, var in ipairs(self.effectEndTimes) do
    if var > maxEffectEndTime then
      maxEffectEndTime = var
    end
  end
  if maxEffectEndTime > 0 then
    return maxEffectEndTime
  end
  if self.descriptionDuration and self.descriptionDuration > 0 then
    return self.startTime + self.descriptionDuration
  end
  return self.startTime
end

---@type fun(self: adr.models.Action): number
mAction.getFullEndTime = function(self)
  if self.configDuration then
    return self.startTime + self.configDuration
  end
  local endTime = 0
  for key, var in ipairs(self.effectList) do
    if not var.ignored then
      endTime = math.max(endTime, var.endTime)
    end
  end
  if endTime > 0 then
    return endTime
  end
  if self.endTime > 0 then
    return self.endTime
  end
  if self.descriptionDuration and self.descriptionDuration > 0 then
    return self.startTime + self.descriptionDuration
  end
  return self.startTime
end

---@type fun(self: adr.models.Action): string
mAction.getFlagsInfo = function(self)
  return string.format(
    "forArea:%s,forGround:%s,forSelf:%s,forTank:%s,forEnemy:%s",
    tostring(self.flags.forArea),
    tostring(self.flags.forGround),
    tostring(self.flags.forSelf),
    tostring(self.flags.forTank),
    tostring(self.flags.forEnemy)
  )
end

---@type fun(self: adr.models.Action): number?
mAction.getMaxOriginEffectDuration = function(self)
  local max = self.duration
  for key, var in ipairs(self.effectList) do
    if math.abs(var.startTime - self.startTime) < 500 then
      max = math.max(max, var.duration)
    end
  end
  return max
end

---@type fun(self: adr.models.Action): adr.models.Action?
mAction.getNewest = function(self)
  local walker = self
  while walker.newAction do
    walker = walker.newAction
  end
  return walker
end

---@type fun(self: adr.models.Action): adr.models.Action?
mAction.getOldest = function(self)
  local walker = self
  while walker.oldAction do
    walker = walker.oldAction
  end
  return walker
end

---@type fun(self: adr.models.Action): string?
mAction.getStageInfo = function(self)
  -- Power Lash Guide: show Power Lash icon
  if self.stackEffect and self.stackEffect.stageInfo then
    return self.stackEffect.stageInfo
  end
  if self.tickEffect then
    if not self.duration or self.duration == 0 then
      return "∞"
    end
    local dur = self:getDuration()
    local total = math.floor(dur / self.tickEffect.tickRate + 0.95)
    local remain = math.ceil((self:getEndTime() - GetGameTimeMilliseconds()) / self.tickEffect.tickRate)
    return string.format("%d/%d", math.max(1, total - remain), total)
  end
  local optEffect = self:optEffect()
  if not optEffect or not self.duration then
    return nil
  end
  -- 1/2 by firstStageId cache
  if
    self.data.firstStageId
    and (
      self.data.firstStageId == optEffect.ability.id
      -- staged by default duration and a longer debuff
      or optEffect.ignorableDebuff
        and self.data.firstStageId == self.ability.id
        and GetGameTimeMilliseconds() < self.endTime
    )
  then
    return "1/2"
  end
  -- 1/2 by same id, same start, >1/5 and <4/7 duration
  if
    optEffect.ability.id == self.ability.id
    and math.abs(optEffect.startTime - self.startTime) < 500
    and optEffect.duration * 5 > self.duration
    and optEffect.duration * 7 < self.duration * 4
  then
    self.data.firstStageId = optEffect.ability.id
    return "1/2"
  end
  -- 1/2 by same start, same duration but with another long buff
  if
    math.abs(optEffect.startTime - self.startTime) < 500
    and optEffect.duration == self.duration
    and optEffect.duration + 3000 <= self:getMaxOriginEffectDuration()
  then
    self.data.firstStageId = optEffect.ability.id
    return "1/2"
  end
  -- 1/2 by normal effect with long duration effect present
  ---@type adr.models.Effect
  local longDurationEffect = self:peekLongDurationEffect()
  if self.flags.forArea and not optEffect:isLongDuration() and longDurationEffect then
    self.data.firstStageId = optEffect.ability.id
    return "1/2"
  end
  if self.data.firstStageId and self.data.firstStageId ~= optEffect.ability.id then
    -- 2/2 by cache
    if self.data.secondStageId == optEffect.ability.id then
      return "2/2"
    end
    if not self.data.secondStageId then
      -- 2/2 by same end
      if math.abs(optEffect.endTime - self.startTime - self.duration) < 700 then
        -- 40%~80% duration
        if optEffect.duration * 5 > self.duration * 2 and optEffect.duration * 5 < self.duration * 4 then
          self.data.secondStageId = optEffect.ability.id
          return "2/2"
        end
      end
      -- 2/2 by normal effect with firstStagedId and without long duration effect present
      if self.flags.forArea and not longDurationEffect then
        self.data.secondStageId = optEffect.ability.id
        return "2/2"
      end
      -- 2/2 by non-action duration, e.g. Pierce Armor with Master 1H-1S
      if self.duration == 0 then
        self.data.secondStageId = optEffect.ability.id
        return "2/2"
      end
      -- 2/2 by duration longer than action's e.g. 5s Resolving Vigor has a 20s Minor Resolve
      if self.duration < optEffect.duration then
        self.data.secondStageId = optEffect.ability.id
        return "2/2"
      end
    end
  end
  -- activated stage e.g. Beast Trap and Scalding Rune: '@' marks the timer as coming from
  -- the activated state (trap triggered) rather than the initial placement/cast;
  -- strict condition: the activated effect's duration must match the action's duration
  if optEffect.activated then
    return "@"
  end
  if
    self.duration
    and self.duration > 0 -- action with duration prop
    and optEffect.duration == self.duration -- strict: activated timer must match action duration
    and (
      (
                -- triggered after a delay for non-ground, measured from the original placement
        -- (forArea actions may have startTime reset when the trap triggers inside the window)
not self.flags.forGround and optEffect.startTime - (self.placementTime or self.startTime) > 1500
      )
      or (
                -- triggered after first ground effect and delay
self.flags.forGround
        and optEffect.ability.id ~= self.groundFirstEffectId
        and optEffect.startTime - (self.placementTime or self.startTime) > 900
      )
    )
  then
    optEffect.activated = true
    return "@"
  end
  if self.targetOut then
    return "#"
  end
  -- note: the former tail-effect marker '>' was removed: tail-driven timers are now
  -- consistently displayed in the low-priority style (brackets via levelIsLow)
  return nil
end

---@type fun(self: adr.models.Action): number?
mAction.getStageInfo2 = function(self)
  -- fixed value from stackEffect2
  local stackEffect2 = self:getStackEffect2()
  if stackEffect2 and stackEffect2.stackCount and stackEffect2.stackCount > 0 then
    return stackEffect2.stackCount
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
        if units == nil then
          units = {}
          units[-1] = 0
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
      if maxCount > 1 then
        self.getStageInfo2_Cache = maxCount
      end
    end
    return self.getStageInfo2_Cache
  end
  return nil
end

---@type fun(self: adr.models.Action): number?
mAction.getStartTime = function(self)
  if self.tickEffect and self.duration == 0 then
    local start = self.tickEffect.startTime
    local now = GetGameTimeMilliseconds()
    local span = now - start
    local offset = span - span % self.tickEffect.tickRate
    return start + offset
  end
  if self.channelStartTime > 0 then
    return self.channelStartTime
  end
  local optEffect = self:optEffect()
  return optEffect and optEffect.startTime or self.startTime
end

---@type fun(self: adr.models.Action): adr.models.Effect?
mAction.getStackEffect = function(self)
  -- For crux-consuming actions, return global crux effect if no local stackEffect
  if self.showCrux then
    local cruxEffect = m.crux.getEffect()
    if
      cruxEffect
      and (cruxEffect.duration == 0 or cruxEffect.endTime > GetGameTimeMilliseconds())
      and (not self.stackEffect or self.stackEffect.duration == 0)
    then
      return cruxEffect
    end
  end
  -- For Nothing Wasted displaying actions, return the global effect if no local stackEffect
  if self.showNothingWasted then
    local nwEffect = m.nothingWasted.getEffect()
    if nwEffect and (not self.stackEffect or self.stackEffect.duration == 0) then
      return nwEffect
    end
  end
  if self.stackEffect and (self.stackEffect.duration == 0 or self.stackEffect.endTime > GetGameTimeMilliseconds()) then
    -- Permanent stack effect (e.g. Fire Keeper's tracker buff) goes stale when
    -- the action's real timed effects have all faded. Skip this for pure
    -- permanent-stack abilities (action.duration == 0, e.g. Grim Focus).
    if self.stackEffect.duration == 0 and self.duration > 0 then
      local now = GetGameTimeMilliseconds()
      for _, e in ipairs(self.effectList) do
        if e.duration > 0 and e.endTime > now and not e.ignored then
          return self.stackEffect
        end
      end
      return nil
    end
    return self.stackEffect
  end
  return nil
end

---@type fun(self: adr.models.Action): adr.models.Effect?
mAction.getStackEffect2 = function(self)
  if
    self.stackEffect2 and (self.stackEffect2.duration == 0 or self.stackEffect2.endTime > GetGameTimeMilliseconds())
  then
    return self.stackEffect2
  end
  return nil
end

---@type fun(self: adr.models.Action): boolean
mAction.needEndingAlert = function(self)
  -- tick/channel skills don't benefit from ending alerts (automatic or requring crux, not re-cast)
  return not self.tickEffect and not (self.channelStartTime and self.channelStartTime > 0)
end

---@type fun(self: adr.models.Action): boolean
mAction.hasEffect = function(self)
  return #self.effectList > 0
end

---@type fun(self: adr.models.Action): boolean
mAction.isOnPlayer = function(self)
  if self.flags.forSelf then
    return true
  end
  for i, effect in ipairs(self.effectList) do
    if effect:isOnPlayer() then
      return true
    end
  end
  return false
end

---@type fun(self: adr.models.Action): boolean
mAction.isOnPlayerpet = function(self)
  if self.flags.forSelf then
    return true
  end
  for i, effect in ipairs(self.effectList) do
    if effect:isOnPlayerpet() then
      return true
    end
  end
  return false
end

---@type fun(self: adr.models.Action): boolean?
mAction.isUnlimited = function(self)
  local optEffect = self:optEffect()
  local stackEffect = self:getStackEffect()
  local stackCount = stackEffect and stackEffect.stackCount or 0
  return self.duration == 0 and stackCount > 0 and (optEffect and optEffect.duration == 0 or not optEffect)
    -- should not remove newly created covering action
    or (self.oldAction and not optEffect and #self.effectList > 0 and GetGameTimeMilliseconds() - self.startTime < 1000)
end

---@type fun(self: adr.models.Action, ability: adr.models.Ability, strict?: boolean): boolean?
mAction.matchesAbility = function(self, ability, strict)
  if self.ability:matches(ability, strict) then
    return true
  end
  -- check related
  for key, var in ipairs(self.relatedAbilityList) do
    ---@type adr.models.Ability
    local a = var
    if a:matches(ability, strict) then
      return true
    end
  end
end

---@type fun(self: adr.models.Action, abilityId: number, strict?: any): boolean?
mAction.matchesAbilityId = function(self, abilityId, strict)
  if self.ability.id == abilityId then
    return true
  end
  -- check related
  for key, var in ipairs(self.relatedAbilityList) do
    if var.id == abilityId then
      return true
    end
  end
end

---@type fun(self: adr.models.Action, abilityIcon: string, strict?: boolean): boolean
mAction.matchesAbilityIcon = function(self, abilityIcon, strict)
  local key = self.ability.id .. "/" .. abilityIcon .. "/" .. (strict and "y" or "n")
  local value = m.cacheOfActionMatchingAbilityIcon[key]
  if value ~= nil then
    return value
  end
  value = self:_matchesAbilityIcon(abilityIcon, strict)
  m.cacheOfActionMatchingAbilityIcon[key] = value
  return value
end
---@type fun(self: adr.models.Action, abilityIcon: string, strict?: boolean): boolean
mAction._matchesAbilityIcon = function(self, abilityIcon, strict)
  local stripIcon = function(icon)
    return icon:gsub("^(.+%d+).+", "%1", 1)
  end
  local m = function(a)
    return (a.icon and abilityIcon:find(stripIcon(a.icon), 1, true))
      or (a.icon2 and abilityIcon:find(stripIcon(a.icon2), 1, true))
  end
  if m(self.ability) then
    return true
  end
  -- i.e. Merciless Resolve can match Assissin's Will action by its related ability list
  for key, var in ipairs(self.relatedAbilityList) do
    if m(var) then
      return true
    end
  end
  return false
end

---@type fun(self: adr.models.Action, abilityName: string, strict?: boolean): boolean
mAction.matchesAbilityName = function(self, abilityName, strict)
  local key = self.ability.id .. "/" .. abilityName .. "/" .. (strict and "y" or "n")
  local value = m.cacheOfActionMatchingAbilityName[key]
  if value ~= nil then
    return value
  end
  value = self:_matchesAbilityName(abilityName, strict)
  m.cacheOfActionMatchingAbilityName[key] = value
  return value
end
---@type fun(self: adr.models.Action, abilityName: string, strict?: boolean): boolean
mAction._matchesAbilityName = function(self, abilityName, strict)
  if
    abilityName:find(self.ability.name, 1, true)
    -- i.e. Assassin's Will name can match Merciless Resolve action by its description
    or (not strict and not addon.isSimpleWord(abilityName) and self.description:find(abilityName, 1, true))
  then
    return true
  end
  -- i.e. Merciless Resolve name can match Assissin's Will action by its related ability list
  for key, var in ipairs(self.relatedAbilityList) do
    if abilityName:find(var.name, 1, true) then
      return true
    end
  end
  return false
end

---@type fun(self: adr.models.Action, effect: adr.models.Effect): boolean
mAction.matchesNewEffect = function(self, effect)
  -- 0. filter ended action
  if not self.flags.forGround and self.endTime > self.startTime and self.endTime + 500 < effect.startTime then
    return false
  end
  -- 1. using cache to match
  local key = self.ability.id .. "/" .. effect.ability.id .. "/" .. effect.duration
  local value = m.cacheOfActionMatchingEffect[key]
  if value ~= nil then
    return value
  end
  value = self:_matchesNewEffect(effect)
  m.cacheOfActionMatchingEffect[key] = value
  return value
end

---@type fun(self: adr.models.Action, effect: adr.models.Effect): boolean
mAction._matchesNewEffect = function(self, effect)
  -- 1. tank skills can taunt
  if effect.ability.icon:find("quest_shield_001", 18, true) and self.flags.forTank then
    return true
  end
  -- 2. fast check already matched effects unless it is a buff effect
  local isBuff = effect.ability.icon:find("ability_buff_m", 1, true)
  if not isBuff then
    for i, var in ipairs(self.effectList) do
      ---@type adr.models.Effect
      local e = var
      if effect.ability.id == e.ability.id then
        return true
      end
    end
  end

  local strict = effect.startTime > self.startTime + self.castTime + 2000
  -- 4.0.x if it is minor debuff, it could be non-strict
  if effect.ability.icon:find("ability_debuff_min", 1, true) then
    strict = false
  end
  -- 4.0.x if it is offbalance debuff, it could also be non-strict
  if effect.ability.icon:find("ability_debuff_offbalance", 1, true) then
    strict = false
  end
  -- 4.0.x if it is following other effect's timeEnds, it could be non-strict
  if strict then -- try to accept continued effect
    local matchEffectsEnd = false
    for key, var in ipairs(self.effectEndTimes) do
      if math.abs(effect.startTime - var) < 500 then
        strict = false
      end
    end
  end
  strict = strict or (effect.duration > 0 and effect.duration < 4000) -- Render Flesh has a 4 second Minor Defile

  -- 5. check ability match
  if self:matchesAbility(effect.ability, strict) then
    -- 5.a filter non-integer duration effect i.e. Merciless Charge has same icon but 10.9s duration
    if
      strict
      and effect.duration % 1000 > 0
      and self.duration > 0
      and effect.ability.name ~= self.ability.name
      and math.floor(effect.duration / 1000 + 0.5) ~= math.floor(self.duration / 1000 + 0.5)
    then
      return false
    end
    --
    return true
  end
  --
  return false
end

---@type fun(self: adr.models.Action, effect: adr.models.Effect): boolean
mAction.matchesOldEffect = function(self, effect)
  -- 1. taunt
  if effect.ability.icon:find("quest_shield_001", 18, true) and self.flags.forTank then
    return true
  end
  -- 2. tick effect
  if self.tickEffect and self.tickEffect.ability.id == effect.ability.id then
    return true
  end
  -- 3. fast check already matched effects
  for i, e in ipairs(self.effectList) do
    if e.ability.id == effect.ability.id and (e.unitId == effect.unitId or effect.unitId == 0) then
      return true
    end
  end
  -- 4 stack effect
  if
    self.stackEffect
    and self.stackEffect.ability.id == effect.ability.id
    and (self.stackEffect.unitId == effect.unitId or effect.unitId == 0)
  then
    return true
  end
  if
    self.stackEffect2
    and self.stackEffect2.ability.id == effect.ability.id
    and (self.stackEffect2.unitId == effect.unitId or effect.unitId == 0)
  then
    return true
  end
  return false
end

--========================================
--        Effect Priority Level Methods
--========================================

-- Data-driven tail demotion: known proc side-effects are secondary and must not outrank
-- main effects via the role-preferred shortcut. Same skill family as Core.lua's
-- l.stackConsumptionMap.
-- Skill description: "Encase your weapon in dark crystals for 6 seconds, causing your next
-- 3 Light or Heavy Attacks to deal additional damage and reduce the target's Armor by 1000
-- for 5 seconds."
local TAIL_EFFECT_ABILITY_IDS = {
  -- Crystal Weapon: the 5s "reduce the target's Armor by 1000" debuff applied to the
  -- target by each empowered Light/Heavy Attack; refreshed per hit, may outlast the buff
  [143808] = true,
}

---@type fun(self: adr.models.Action, effect: adr.models.Effect): number
mAction.calclevel = function(self, effect)
  local duration = self.duration > 0 and self.duration or self.inheritDuration
  if duration == 0 then
    duration = self.descriptionDuration or 0
  end

  -- Level 1: actionId match + duration match
  if effect.ability.id == self.ability.id and effect.duration == duration then
    return LEVEL_ACTION_ID_MATCH
  end

  -- Major/minor buff as side effect: demote to low priority
  if effect:isMajorMinorBuff() then
    if self.mainEffectPurged and effect:isMinorBuff() then
      return LEVEL_MAJOR_MINOR_BUFF
    end
    -- demote unless it's a same-source side effect: same duration AND started together
    -- (Fire Keeper's Minor Fortitude/Heroism keep refreshing every tick, so their
    -- startTime drifts past action.startTime + 1s and they get demoted)
    if self.duration == 0 or effect.duration ~= self.duration or math.abs(effect.startTime - self.startTime) > 1000 then
      return LEVEL_MAJOR_MINOR_BUFF
    end
  end

  -- Level 2: stackEffect
  if self.stackEffect and effect.ability.id == self.stackEffect.ability.id then
    return LEVEL_STACK_EFFECT
  end

  -- Level 3: stackEffect2
  if self.stackEffect2 and effect.ability.id == self.stackEffect2.ability.id then
    return LEVEL_STACK_EFFECT_2
  end

  -- Data-driven tail demotion before the role-preferred shortcut
  if TAIL_EFFECT_ABILITY_IDS[effect.ability.id] then
    return LEVEL_TAIL_EFFECT
  end

  -- Level 4: role preferred
  local role = GetSelectedLFGRole()
  if (role == LFG_ROLE_DPS or self.flags.forEnemy) and not self.flags.forArea then
    if not effect:isOnPlayer() and effect.duration > 0 then
      return LEVEL_ROLE_PREFERRED
    end
  elseif role == LFG_ROLE_TANK then
    if effect:isOnPlayer() then
      return LEVEL_ROLE_PREFERRED
    end
  elseif role == LFG_ROLE_HEAL and not self.flags.forArea then
    if effect:isOnPlayer() then
      return LEVEL_ROLE_PREFERRED
    end
  end

  -- Level 5: duration match
  if duration > 0 and effect.duration == duration then
    return LEVEL_DURATION_MATCH
  end

  -- Level 7: tail effect (significantly longer than action duration) TODO
  if duration > 0 and effect.duration > duration * 2 and effect.duration > 10000 then
    return LEVEL_TAIL_EFFECT
  end

  -- Level 6: default (longer duration)
  return LEVEL_LONGER_DURATION
end

---@type fun(self: adr.models.Action)
mAction.sortEffectList = function(self)
  table.sort(self.effectList, function(a, b)
    if a.level ~= b.level then
      return a.level < b.level
    end
    -- Same level: prefer longer duration
    if a.duration ~= b.duration then
      return a.duration > b.duration
    end
    -- Same duration: prefer later end time
    return a.endTime > b.endTime
  end)
end

---@type fun(self: adr.models.Action)
mAction.recalcEffectLevels = function(self)
  -- Recalculate static level for all effects
  for _, effect in ipairs(self.effectList) do
    effect.level = self:calclevel(effect)
    effect.levelIsLow = effect.level >= LEVEL_THRESHOLD_LOW
  end
  -- Re-sort the list
  self:sortEffectList()
end

---@type fun(self: adr.models.Action, effect: adr.models.Effect, now: number): boolean
mAction.isFilteredByDynamic = function(self, effect, now)
  -- Filter 1: expired effect
  if now > effect.endTime then
    effect.ignored = true
    return true
  end

  -- Filter 2: Major Gallop when not mounted
  if effect.ability.icon:find("major_gallop", 1, true) then
    if not IsMounted() then
      return true
    end
  end

  -- Filter 3: after-phase effect (e.g. warden's Scorch ending brings some debuff effects)
  if self.duration > 3000 and self.startTime + self.duration - 300 <= effect.startTime then
    if self.duration ~= effect.duration then
      return true
    end
  end

  -- Filter 4: old effects at new action beginning (temporary ignore)
  if effect.startTime + 1000 < self.startTime and now - self.startTime < 300 then
    return true
  end

  return false
end

local debuggingLastTime = 0
---@type fun(self: adr.models.Action, debugging?: boolean): adr.models.Effect?, string
mAction.optEffect = function(self, debugging)
  if debugging then -- 1 sec threshold
    local now = GetGameTimeMilliseconds()
    if now - debuggingLastTime > 1000 then
      debuggingLastTime = now
    else
      debugging = false
    end
  end

  local now = GetGameTimeMilliseconds()
  local reason = ""

  local lowLevelStackEffect = nil
  local stackEffect = self:getStackEffect()
  if stackEffect and stackEffect.duration > 0 then
    if stackEffect.levelIsLow then
      lowLevelStackEffect = stackEffect
    else
      return stackEffect, "stackEffect"
    end
  end
  local stackEffect2 = self:getStackEffect2()
  if stackEffect2 and stackEffect2.duration > 0 then
    if stackEffect2.levelIsLow then
      lowLevelStackEffect = stackEffect2
    else
      return stackEffect2, "stackEffect"
    end
  end

  for i, effect in ipairs(self.effectList) do
    -- Special case: Major Gallop when mounted - return immediately
    if effect.ability.icon:find("major_gallop", 1, true) then
      if IsMounted() then
        return effect, "gallop"
      end
    end

    -- Dynamic filter check
    if not self:isFilteredByDynamic(effect, now) then
      if debugging then
        df("[DBG] optEffect: %s, level=%d", effect:toLogString(), effect.level or 0)
      end
      return effect, "level:" .. (effect.level or 0)
    end
  end

  if lowLevelStackEffect then
    return lowLevelStackEffect, "level: low stack"
  end

  -- Check global crux effect (lowest priority)
  if self.showCrux then
    local cruxEffect = m.crux.getEffect()
    if cruxEffect then
      if now <= cruxEffect.endTime then
        return cruxEffect, "crux"
      end
    end
  end

  -- Check global Nothing Wasted effect (lowest priority)
  if self.showNothingWasted then
    local nwEffect = m.nothingWasted.getEffect()
    if nwEffect then
      return nwEffect, "nothingWasted"
    end
  end

  return nil, "none"
end

---@type fun(self: adr.models.Action): adr.models.Effect|false
mAction.optGallopEffect = function(self)
  for i, effect in ipairs(self.effectList) do
    -- filter Major Gallop if not mount
    if effect.ability.icon:find("major_gallop", 1, true) then
      return effect
    end
  end
  return false
end

---@type fun(self: adr.models.Action): adr.models.Effect?
mAction.peekLongDurationEffect = function(self)
  for i, effect in ipairs(self.effectList) do
    if effect:isLongDuration() then
      return effect
    end
  end
  return nil
end

---@type fun(self: adr.models.Action, effect: adr.models.Effect)
mAction.purgeEffectByTargetUnitId = function(self, targetUnitId)
  ---@type adr.models.Effect
  ---@type adr.models.Effect|false?
  local purgedEffect = nil
  for key, var in ipairs(self.effectList) do
    if var.unitId == targetUnitId then
      purgedEffect = self:purgeEffect(var)
    end
  end
  if self.flags.forEnemy and purgedEffect then
    -- also purge
    for key, var in ipairs(self.effectList) do
      if math.abs(var.startTime - purgedEffect.startTime) < 100 then
        self:purgeEffect(var)
      end
    end
  end
end

---@type fun(self: adr.models.Action, effect: adr.models.Effect): adr.models.Effect|false?
mAction.purgeEffect = function(self, effect)
  ---@type adr.models.Effect
  local oldEffect = effect
  local now = GetGameTimeMilliseconds()
  -- process tickEffect
  if self.tickEffect and self.tickEffect.ability.id == oldEffect.ability.id then
    if self.tickEffectDoubled then
      self.tickEffectDoubled = false
      if addon.debugEnabled(DSS_MODEL_PURGE) then
        addon.debug("[MPd]purged double tick %s", self:toLogString())
      end
      return
    end
    oldEffect = self.tickEffect
    self.tickEffect = nil
    if addon.debugEnabled(DSS_MODEL_PURGE) then
      addon.debug("[MPt]purged tick %s", self:toLogString())
    end
    return
  end
  -- process effectList
  for i, e in ipairs(self.effectList) do
    if e.ability.id == effect.ability.id and e.unitId == effect.unitId then
      local withOldFake = self.oldAction and self.oldAction.fake
      -- if not purging a fake old action and purging earlier than expected (i.e. Minor Breach cut by POL)
      -- or the new action just inherited some old effects that is being cut now
      if not withOldFake and (e.endTime > now + 1000 or e.startTime < self.startTime) then
        -- sometimes, effects such as Minor Breach are purged and added when major action effect ends, so we should saved that for a little while
        if not effect.purgingTime then
          effect.purgingTime = now
          -- do it later
          zo_callLater(function()
            self:purgeEffect(effect)
          end, 50)
          if addon.debugEnabled(DSS_MODEL_PURGE, e.ability.name) then
            addon.debug(
              "[MP~]purging %s, from %s, #effectList:%d(-1)",
              e:toLogString(),
              self:toLogString(),
              #self.effectList
            )
          end
          return e
        elseif e.saveTime and e.saveTime >= effect.purgingTime then
          if addon.debugEnabled(DSS_MODEL_PURGE, e.ability.name) then
            addon.debug("[MP!]purge-renewed %s, in %s", e:toLogString(), self:toLogString())
          end
          return e
        end
      end
      table.remove(self.effectList, i)
      if addon.debugEnabled(DSS_MODEL_PURGE, e.ability.name) then
        addon.debug("[MP-]purged %s, from %s", e:toLogString(), self:toLogString())
      end
      if not self.mainEffectPurged and e.endTime > now + 1000 then
        local purgedName = fSkillIconName(e.ability.icon)
        local actionName = fSkillIconName(self.ability.icon)
        if purgedName and actionName and purgedName == actionName then
          self.mainEffectPurged = true
        end
      end
      oldEffect = e -- we need duration info to end action
      break
    end
  end
  if
    self.stackEffect
    and self.stackEffect.ability.id == effect.ability.id
    and self.stackEffect.unitId == effect.unitId
  then
    oldEffect = self.stackEffect
    self.stackEffect = nil
    -- Recalculate levels and sort since stackEffect changed
    self:recalcEffectLevels()
    if addon.debugEnabled(DSS_MODEL_PURGE, oldEffect.ability.name) then
      addon.debug("[MPS]purged stackEffect %s \n from %s", oldEffect:toLogString(), self:toLogString())
    end
  end
  if
    self.stackEffect2
    and self.stackEffect2.ability.id == effect.ability.id
    and self.stackEffect2.unitId == effect.unitId
  then
    oldEffect = self.stackEffect2
    self.stackEffect2 = nil
    if oldEffect.ability.id == self.ability.id then
      -- 例如龙骑Power Lash的20秒冷却，当五鞭子层数消失后，应该继续记录冷却
      oldEffect.stackCount = 0
      self:saveEffect(oldEffect)
      if addon.debugEnabled(DSS_MODEL_PURGE, oldEffect.ability.name) then
        addon.debug("[MPd]purged and downgraded stackEffect %s \n from %s", oldEffect:toLogString(), self:toLogString())
      end
      return
    end
    -- Recalculate levels and sort since stackEffect2 changed
    self:recalcEffectLevels()
    if addon.debugEnabled(DSS_MODEL_PURGE, oldEffect.ability.name) then
      addon.debug("[MPs]purged stackEffect2 %s \n from %s", oldEffect:toLogString(), self:toLogString())
    end
  end
  local availableEffectCount = 0
  local nonMinorBuffCount = 0
  local reason = ""
  for key, var in pairs(self.effectList) do
    if not var.ignored then
      local ok = true
      if
        self.flags.forEnemy
        and oldEffect
        and var.ability.id ~= oldEffect.ability.id -- count if this effect has same id
        and var.unitId ~= oldEffect.unitId -- count if this effect has same unit id
        and math.abs(oldEffect.startTime - var.startTime) < 100 -- count if this effect comes at a different time
      then
        ok = false
        reason = reason .. string.format("not counted as available:%s\n", var:toLogString())
      end
      if ok then
        availableEffectCount = availableEffectCount + 1
        if not var:isMinorBuff() then
          nonMinorBuffCount = nonMinorBuffCount + 1
        end
      end
    else
      reason = reason .. string.format("%s is ignored and not counted\n", var.ability.name)
    end
  end
  if
    availableEffectCount == 0
    and oldEffect.duration > 0 -- last duration effect has faded
    and (
            -- the old effect SHOULD be brought by this action rather than an old one, or this might be a renew rather than end
(oldEffect.startTime >= self.startTime)
      or (
                -- either the current one or the old one is fake, so a real action now is triggered and we should do a purge
self.fake or (self.oldAction and self.oldAction.fake)
      )
    )
  then
    if addon.debugEnabled(DSS_MODEL_PURGE) then
      addon.debug("[MPe]purged and action is end %s, %s", reason, self:toLogString())
    end
    self.endTime = now
  else
    if addon.debugEnabled(DSS_MODEL_PURGE) then
      addon.debug("[MPn]purged and action is not end %s, %s", reason, self:toLogString())
    end
    if self.mainEffectPurged and nonMinorBuffCount == 0 and availableEffectCount > 0 then
      self:recalcEffectLevels()
      if addon.debugEnabled(DSS_MODEL_PURGE) then
        addon.debug("[MPm]main effect purged, all remaining are minor buffs, demoted %s", self:toLogString())
      end
    end
  end
  return oldEffect
end

---@type fun(self: adr.models.Action, effect: adr.models.Effect): adr.models.Effect?
mAction.saveEffect = function(self, effect)
  if effect.drop then
    return
  end
  -- ignore pure stack effect, they should have been saved using updateStackInfo
  if effect.stackCount > 0 and effect.duration == 0 then
    return
  end
  -- update stack effect duration (only when same target; multi-target DoTs e.g. Carve bleed must not cross-contaminate)
  if self.stackEffect and effect.ability.id == self.stackEffect.ability.id then
    if self.stackEffect.unitId == effect.unitId then
      if effect.duration > 0 then
        self.stackEffect.duration = effect.duration
        self.stackEffect.endTime = effect.endTime
        self.stackEffect.startTime = effect.startTime
        -- tracked-effect chat log: the effect is absorbed into stackEffect here, so this
        -- is the only place it can be surfaced for blacklist id discovery
        if settings.getSavedVars().addonLogTrackedEffectsInChat then
          df(
            " |t24:24:%s|t%s (id: %d) %ds",
            effect.ability.icon,
            effect.ability.name,
            effect.ability.id,
            effect.duration / 1000
          )
        end
      end
      return
    end
  elseif self.stackEffect2 and effect.ability.id == self.stackEffect2.ability.id then
    if self.stackEffect2.unitId == effect.unitId then
      if effect.duration > 0 then
        self.stackEffect2.duration = effect.duration
        self.stackEffect2.endTime = effect.endTime
        self.stackEffect2.startTime = effect.startTime
      end
      return
    end
  end

  -- process effect with tickRate
  if effect.tickRate > 0 then
    if self.tickEffect and self.tickEffect.ability.id == effect.ability.id then
      self.tickEffectDoubled = true
      return
    end
    self.tickEffect = effect
    return
  end

  -- debuff longer than default duration BUT: people think debuf is usefly i.e. Mass Hysteria
  if
    self.duration
    and self.duration > 0
    and effect.duration > self.duration
    and effect.ability.icon:find("ability_debuff_", 1, true)
  then
    effect.ignorableDebuff = true
  end

  -- ignore abnormal long duration effect
  if
    self.duration
    and self.duration >= 10000
    and effect.duration > self.duration * 3 -- changed from 1.5 to 3 because of Everlasting Sweep could extend the duration based enemies hit
    and effect.duration ~= self.descriptionDuration
  then
    return
  end
  -- adjust effect for covering i.e. lightning splash
  if self.duration and self.duration > 0 and effect.duration == self.duration + 1000 then
    ---@type adr.models.Effect
    local existedEffect = self:optEffect()
    if existedEffect and existedEffect.duration == self.duration then
      effect.endTime = effect.endTime - 1000
      effect.duration = effect.duration - 1000
    end
  end
  -- adjust effect for explosive duration i.e. unstable wall
  if
    self.duration
    and self.duration > 0
    and effect.duration > self.duration
    and effect.duration < self.duration + 500
    and effect.startTime < self.startTime + 900
  then
    effect.duration = self.duration
    local existedEffect = nil
    for key, var in ipairs(self.effectList) do
      if var.startTime > self.startTime and var.startTime < self.startTime + 500 then
        existedEffect = var
      end
    end
    if existedEffect then
      effect.startTime = existedEffect.startTime
    end
    effect.endTime = effect.startTime + effect.duration
  end
  -- modified for Unnerving Boneyard skill
  if self.ability.icon:find("necromancer_004", 1, true) and effect.duration > 10000 then
    return
  end

  -- unified tracked-effect chat log: single chokepoint covering every path an effect
  -- enters the effectList (effect events, combat events, buff polling), so players can
  -- discover ability ids for the core blacklist
  if settings.getSavedVars().addonLogTrackedEffectsInChat and effect.duration > 0 then
    df(
      " |t24:24:%s|t%s (id: %d) %ds",
      effect.ability.icon,
      effect.ability.name,
      effect.ability.id,
      effect.duration / 1000
    )
  end
  self.lastEffectTime = effect.startTime
  -- Reset mainEffectPurged when a main effect (icon-matching) is saved
  if self.mainEffectPurged then
    local effectIconName = fSkillIconName(effect.ability.icon)
    local actionIconName = fSkillIconName(self.ability.icon)
    if effectIconName and actionIconName and effectIconName == actionIconName then
      self.mainEffectPurged = false
    end
  end
  -- Calculate static level before inserting
  effect.level = self:calclevel(effect)
  effect.levelIsLow = effect.level >= LEVEL_THRESHOLD_LOW
  for i, e in ipairs(self.effectList) do
    if e.ability.id == effect.ability.id and e.unitId == effect.unitId then
      local now = GetGameTimeMilliseconds()
      if math.abs(e.endTime - effect.endTime) > 1000 then
        self.effectList[i] = effect
        -- save effect end time to aid judgement on the strictness of following effects
        if self.effectEndTimes[#self.effectEndTimes] ~= effect.endTime then
          self.effectEndTimes[#self.effectEndTimes + 1] = effect.endTime
        end
        -- Sort effect list by priority
        self:sortEffectList()
      end
      self.effectList[i].saveTime = now
      return e
    end
  end
  table.insert(self.effectList, effect)
  -- save effect end time to aid judgement on the strictness of following effects
  if self.effectEndTimes[#self.effectEndTimes] ~= effect.endTime then
    self.effectEndTimes[#self.effectEndTimes + 1] = effect.endTime
  end
  -- Sort effect list by priority
  self:sortEffectList()
  -- record targetId for enemy actions
  if self.flags.forEnemy and effect.unitId > 0 then
    self.targetId = effect.unitId
  end
  -- record first ground effect id for triggering recognition
  if
    #self.effectList == 1
    and self.flags.forGround
    and (self.groundFirstEffectId ~= -1 or self.ability.id == effect.ability.id)
  then
    self.groundFirstEffectId = effect.ability.id
  end
  return nil
end

---@type fun(self: adr.models.Action): string
mAction.toLogString = function(self)
  local effectListLog = #self.effectList > 0 and ":" or ""
  local stackEffect = self:getStackEffect()
  if stackEffect then
    effectListLog = effectListLog .. "\n+ [se] " .. stackEffect:toLogString()
  end
  if self.stackEffect2 then
    effectListLog = effectListLog .. "\n+ [se2] " .. self.stackEffect2:toLogString()
  end
  for key, effect in ipairs(self.effectList) do
    effectListLog = effectListLog .. "\n+ [e] " .. effect:toLogString()
  end
  local tickEffectLog = self.tickEffect and string.format("\n+ [t] %s", self.tickEffect:toLogString()) or ""
  local stackCount = stackEffect and stackEffect.stackCount or 0
  local dur, durSource = self:getDuration()
  return string.format(
    "A%d%s-%s@%s%.2f~%.2f(%.2f)<%.2f%s>%s bar%dslot%d\n%s%s%s%s",
    self.sn,
    self.fake and "(fake)" or "",
    self.ability:toLogString(),
    self.channelStartTime > 0 and string.format("channeling(%d)@", self.channelUnitId or 0) or "",
    self.startTime / 1000,
    self:getEndTime() / 1000,
    self.endTime / 1000,
    dur / 1000,
    durSource,
    stackCount == 0 and "" or string.format("#stackCount:%d", stackCount),
    self.hotbarCategory,
    self.slotNum,
    self:getFlagsInfo(),
    self.oldAction and string.format("\noldAction:%s", self.oldAction:toLogString_SingleLine()) or "\nwithoutOld",
    effectListLog,
    tickEffectLog
  )
end

---@type fun(self: adr.models.Action): string
mAction.toLogString_Short = function(self)
  return string.format(
    "A%d%s-%s@%.2f<%.2f>",
    self.sn,
    self.fake and "(fake)" or "",
    self.ability:toLogString(),
    self.startTime / 1000,
    self:getDuration() / 1000
  )
end

---@type fun(self: adr.models.Action): string
mAction.toLogString_SingleLine = function(self)
  local stackEffect = self:getStackEffect()
  local stackCount = stackEffect and stackEffect.stackCount or 0
  return string.format(
    "A%d%s-%s@%s%.2f~%.2f(%.2f)<%.2f>%s bar%dslot%d",
    self.sn,
    self.fake and "(fake)" or "",
    self.ability:toLogString(),
    self.channelStartTime > 0 and string.format("channeling(%d)@", self.channelUnitId or 0) or "",
    self.startTime / 1000,
    self:getEndTime() / 1000,
    self.endTime / 1000,
    self:getDuration() / 1000,
    stackCount == 0 and "" or string.format("#stackCount:%d", stackCount),
    self.hotbarCategory,
    self.slotNum,
    self:getFlagsInfo()
  )
end

---Placeholder for future special-case stack routing (e.g. triggered bonus stacks that are
---consumed one by one, like Stone Giant or Flame Lash). Returning false routes every stack
---effect to the unified stackEffect slot.
---Note: stackCount is deliberately NOT a parameter — it is dynamic and unreliable for
---classification; future special logic should key on ability/effect identity instead.
---@type fun(self: adr.models.Action, effect: adr.models.Effect): boolean
mAction.isSpecialStackEffect = function(self, effect)
  return false
end

---@type fun(self: adr.models.Action, stackCount: number, effect: adr.models.Effect): boolean
mAction.updateStackInfo = function(self, stackCount, effect)
  if addon.debugEnabled(DSS_MODEL_STACK, effect.ability.name) then
    addon.debug("[MS~]updating stackCount to %d from %s in %s", stackCount, effect:toLogString(), self:toLogString())
  end
  -- stackEffect/stackCount: unified slot for all stack effects, whether accumulated
  -- gradually (e.g. Grim Focus, Bound Armaments) or granted at once
  -- stackEffect2/stackCount2: reserved for special cases flagged by isSpecialStackEffect
  -- (currently a placeholder), e.g. triggered bonus stacks consumed one by one
  local addType = 0
  if self:isSpecialStackEffect(effect) then
    if not self.stackEffect2 or self.stackEffect2.ability.id == effect.ability.id then
      addType = 2
    else
      if addon.debugEnabled(DSS_MODEL_STACK, effect.ability.name) then
        addon.debug("[MSx]ignored because old stackEffect2 existed: %s ", self.stackEffect2:toLogString())
      end
    end
  elseif not self.stackEffect then
    addType = 1
  elseif self.stackEffect.ability.id == effect.ability.id then
    -- multi-target stacking DoT (e.g. Carve bleed on boss + adds): keep the
    -- higher-stack instance, don't let a fresh low-stack add overwrite the boss.
    if
      self.stackEffect.unitId == effect.unitId
      or effect.stackCount > self.stackEffect.stackCount
      or (self.stackEffect.duration > 0 and self.stackEffect.endTime <= GetGameTimeMilliseconds())
    then
      addType = 1
    else
      addType = 0
      if addon.debugEnabled(DSS_MODEL_STACK, effect.ability.name) then
        addon.debug(
          "[MS>]preserve stackEffect %d over new %d from %s",
          self.stackEffect.stackCount,
          stackCount,
          effect:toLogString()
        )
      end
    end
  else
    -- non-special stack effect from a different ability while the unified slot is
    -- occupied: ignored for now, candidate for future isSpecialStackEffect logic
    if addon.debugEnabled(DSS_MODEL_STACK, effect.ability.name) then
      addon.debug(
        "[MSi]ignored %s because stackEffect occupied by %s",
        effect:toLogString(),
        self.stackEffect:toLogString()
      )
    end
  end
  if addType == 1 then
    -- carry over a live expiry when a fresh combat-granted stack effect (duration 0)
    -- replaces the current one, e.g. re-casting while the buff is still active: the
    -- GAINED re-grant does not repeat GAINED_DURATION, so the expiry would be lost
    -- and getStackEffect would treat the stack as stale (count display disappears)
    if
      effect.duration == 0
      and effect.combatEventId ~= nil
      and self.stackEffect
      and self.stackEffect.duration > 0
      and self.stackEffect.endTime > GetGameTimeMilliseconds()
    then
      effect.duration = self.stackEffect.duration
      effect.endTime = self.stackEffect.endTime
      effect.startTime = self.stackEffect.startTime
    end
    self.stackEffect = effect
    self.stackCountMatch = false
    self.stackCountMatch = stackCount >= 3 and self.descriptionNums[stackCount]
  elseif addType == 2 then
    self.stackEffect2 = effect
  end
  if addType > 0 then
    local cacheKey = self.ability.id .. "/" .. effect.ability.id .. "/" .. effect.duration
    m.cacheOfActionMatchingEffect[cacheKey] = true
    effect.level = self:calclevel(effect)
    effect.levelIsLow = effect.level > LEVEL_THRESHOLD_LOW
    return true
  end

  return false
end

--========================================
--        mEffect
--========================================
---@type fun(self: adr.models.Effect): boolean
mEffect.isOnPlayer = function(self)
  return self.unitTag == "player"
end

---@type fun(self: adr.models.Effect): boolean
mEffect.isOnPlayerpet = function(self)
  return not not self.unitTag:find("playerpet", 1, true)
end

---@type fun(self: adr.models.Effect): boolean
mEffect.isLongDuration = function(self)
  return self.duration > 39000
end

---@type fun(self: adr.models.Effect): boolean
mEffect.isMajorMinorBuff = function(self)
  local icon = self.ability.icon
  return not not (icon and (icon:find("ability_buff_ma", 1, true) or icon:find("ability_buff_mi", 1, true)))
end

---@type fun(self: adr.models.Effect): boolean
mEffect.isMinorBuff = function(self)
  local icon = self.ability.icon
  return not not (icon and icon:find("ability_buff_mi", 1, true))
end

---@type fun(self: adr.models.Effect): string
mEffect.toLogString = function(self)
  return string.format(
    "%s, %.2f~%.2f<%d>, L%d, S%d, %sUnit:%s(%d)%s",
    self.ability:toLogString(),
    self.startTime / 1000,
    self.endTime / 1000,
    self.duration / 1000,
    self.level,
    self.stackCount,
    self.tickRate == 0 and "" or string.format("tickRate:%d, ", self.tickRate),
    self.unitTag,
    self.unitId,
    self.ignored and " [ignored]" or ""
  )
end
--========================================
--        register
--========================================
addon.register("Models#M", m)

addon.register("Models", m)

-- Register Models debug switches
addon.registerDebugSwitch(DS_MODEL, "Model Debug")
addon.registerDebugSubSwitch(DSS_MODEL_STACK, "Model Stack [MS]", "Log stack count updates")
addon.registerDebugSubSwitch(DSS_MODEL_PURGE, "Model Purge [MP]", "Log effect purge operations")

# Action Duration Reminder — Public API

Other addons can consume ADR's tracking data (slotted ability durations,
buffs, DoTs, stacks) through a documented runtime API instead of copying
source code. This document defines the **public** API surface.

## Compatibility policy

- `ActionDurationReminder.apiVersion` is a number (currently `3`), equal to
  ADR's major version.
- Everything documented here is **stable within one apiVersion**: fields and
  functions keep their names and semantics; changes are additive only.
- Breaking changes happen only when `apiVersion` increases, and are called
  out in the changelog with an `[API]` tag.
- Anything **not** documented here is internal and may change without
  notice. In particular: private tables (`module.l`), undocumented fields,
  and internal method names.
- Treat every object you receive as **read-only**. Never mutate actions,
  effects, or maps, and do not cache table references across UI reloads.

Feature-gate like this:

```lua
local ADR = ActionDurationReminder
if ADR and ADR.apiVersion >= 3 then
  -- safe to use the API described here
end
```

## Two ways to integrate

1. **Hard dependency** (simplest): `## DependsOn: ActionDurationReminder`
   in your manifest. ADR is guaranteed to be fully loaded before your files.
2. **Optional dependency with embedded fallback**: your addon works with or
   without ADR installed by embedding the ADR core. See `EMBED.md` shipped
   in the release zip (`ActionDurationReminder/embedded/EMBED.md`).

## The addon table

The global `ActionDurationReminder` table exposes:

| Member | Signature | Description |
| --- | --- | --- |
| `version` | `string` | Addon version, e.g. `"3.164"`. |
| `apiVersion` | `number` | API compatibility level, e.g. `3`. |
| `embedded` | `boolean?` | `true` when running from an embedded copy (see EMBED.md). |
| `load(name)` | `fun(name: string): any` | Returns a module's public table, e.g. `load("Core")`. |
| `hookStart(fn)` | `fun(fn: fun())` | Runs `fn` once ADR is started (immediately if already started). |
| `extend(key, fn)` | `fun(key: string, fn: fun(...))` | Registers a handler for an extension key. |

> Legacy note: `load("Core#M")` (with the `#M` suffix) is the old spelling
> kept for existing consumers. New code should use `load("Core")`.

## Core module — queries

```lua
local core = ActionDurationReminder.load("Core")
```

| Function | Returns | Description |
| --- | --- | --- |
| `getActionByAbilityId(abilityId)` | `Action?` | Action for an ability id (also matches related abilities). |
| `getActionByAbilityName(name, strict?)` | `Action?` | Action whose ability name matches. |
| `getActionBySlot(hotbarCategory, slotNum)` | `Action?` | Action currently bound to a hotbar slot. |
| `getIdActionMap()` | `table<number, Action>` | All tracked actions, keyed by ability id. |
| `getSnActionMap()` | `table<number, Action>` | Keyed by action serial number (`action.sn`). |
| `getTimeActionMap()` | `table<number, Action>` | Keyed by effect start time (ms). |

These are snapshots of live data; maps are re-built as actions come and go.
Iterate defensively (entries may be removed between ticks) and do not hold
onto them.

## Core module — update tick

```lua
ActionDurationReminder.extend(ActionDurationReminder.load("Core").EXTKEY_UPDATE, function()
  -- called every ~100ms while the addon runs
end)
```

Register inside `hookStart` or after ADR started. Keep handlers cheap.

## Data contract

### Ability (`action.ability`)

| Member | Type | Description |
| --- | --- | --- |
| `id` | `number` | Ability id. |
| `name` | `string` | Ability name. |
| `icon` | `string` | Texture path for the ability icon. |
| `toLogString()` | `fun(): string` | Debug representation (format not stable). |

### Action

| Member | Type | Description |
| --- | --- | --- |
| `ability` | `Ability` | The ability this action was created for. |
| `slotNum` / `hotbarCategory` | `number` | Hotbar binding, when tracked on a slot. |
| `startTime` / `endTime` | `number` | Milliseconds on the `GetGameTimeMilliseconds()` clock. |
| `duration` | `number` | Best-known duration in ms. |
| `channeled` | `boolean` | Whether the action is a channel. |
| `flags` | `table` | Classification flags: `forArea`, `forGround`, `forSelf`, `forEnemy`, `forTank`, ... |
| `stackEffect` / `tickEffect` | `Effect?` | Attached stack / tick effect, when present. |
| `getDuration()` | `fun(): number, string` | Duration in ms plus source marker: `"T"` tick, `"C"` channel, `"F"` configured, `"P"` priority effect, `"S"` self, `"D"` description, `""` none. |
| `getEffectList()` | `fun(): Effect[]` | Effects currently matched to this action. May be empty. |
| `hasEffect()` | `fun(): boolean` | `#effectList > 0`. |
| `isOnPlayer()` | `fun(): boolean` | Whether the action currently affects the player. |
| `getStackEffect()` | `fun(): Effect?` | Primary stack effect. |
| `toLogString()` | `fun(): string` | Debug representation (format not stable). |

### Effect (entries of `action:getEffectList()`)

| Member | Type | Description |
| --- | --- | --- |
| `ability` | `Ability` | The effect's ability. |
| `unitTag` | `string` | Where it runs: `"player"`, `"playerpet"`, or `"others"` (any other unit). |
| `unitId` | `number` | Numeric id of the unit the effect is on (`0` = unknown); distinct targets get distinct Effect entries. |
| `startTime` / `endTime` / `duration` | `number` | Timing on the same millisecond clock. |
| `stackCount` | `number` | Current stacks. |
| `tickRate` | `number` | Tick interval in ms for ticking effects, `0` otherwise. |
| `isOnPlayer()` | `fun(): boolean` | Convenience check. |
| `toLogString()` | `fun(): string` | Debug representation (format not stable). |

## Example: most urgent tracked ability

```lua
local ADR = ActionDurationReminder
if not ADR or ADR.apiVersion < 3 then return end

local core = ADR.load("Core")

local function findMostUrgent()
  local best, bestRemaining, now = nil, math.huge, GetGameTimeMilliseconds()
  for _, action in pairs(core.getIdActionMap()) do
    local remaining = action.endTime - now
    if remaining > 0 and remaining < bestRemaining then
      best, bestRemaining = action, remaining
    end
  end
  return best, bestRemaining -- remaining in ms; best.ability.icon for display
end

ADR.hookStart(function()
  ADR.extend(core.EXTKEY_UPDATE, function()
    local action, remaining = findMostUrgent()
    -- ...render action.ability.icon and remaining...
  end)
end)
```

## Changelog

API-relevant changes are tagged `[API]` in the addon changelog.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Action Duration Reminder is an Elder Scrolls Online (ESO) addon that tracks ability cooldowns, buff durations, and DoT timers. It displays countdown timers on the action bar and can show popup alerts when effects expire.

## Build Commands

```bash
# Build distribution zip
./gradlew distZip

# Install to ESO Live directory (requires gradle.properties)
./gradlew installToLive

# Install to ESO PTS directory (requires gradle.properties)
./gradlew installToPTS

# Upload to esoui.com (requires API token in gradle.properties)
./gradlew upload
```

The `gradle.properties` file must define:
- `ESO_LIVE_ADDONS_DIR` - path to ESO live addons folder
- `ESO_PTS_ADDONS_DIR` - path to ESO PTS addons folder
- `com.esoui.apiToken` - API token for esoui.com uploads

Version numbers are extracted from the first line of `changelog`.

## Architecture

### Module System

The addon uses a consistent module pattern. Each module file follows this structure:

```lua
local addon = ActionDurationReminder
local l = {}  -- private table
local m = {l=l}  -- public table
-- ... implementation ...
addon.register("ModuleName#M", m)
```

### Extension Points

Modules communicate through an extension system:

```lua
-- Define extension key
m.EXTKEY_UPDATE = "Core:update"

-- Register extension handler
addon.extend(settings.EXTKEY_ADD_DEFAULTS, function()
  settings.addDefaults(defaults)
end)

-- Call extensions
addon.callExtension(m.EXTKEY_UPDATE)
```

### Key Extension Keys

- `Settings:addDefaults` - Add default saved variable values
- `Settings:addMenus` - Add settings menu options
- `Core:update` - Called every frame update (100ms interval)

### Load Order (from ActionDurationReminder.txt)

1. `Addon.lua` - Framework, module registration, start hooks
2. `Utils.lua` - RecentCache for filtering repeated events
3. `i18n/*.lua` - Localization (en, zh, de, fr, etc.)
4. `Settings.lua` - LibAddonMenu-2.0 integration
5. `Models.lua` - Ability, Action, Effect data structures
6. `Core.lua` - Combat event handling, action/effect matching
7. `Views.lua` - Widget and Cooldown UI components
8. `Bar.lua` - Timer bar display on action slots
9. `Alert.lua` - Popup alerts before effects expire
10. `Patch.lua` - UI patches (auto-move attribute bars)

### Data Models

- **Ability** - Skill info (id, name, icon, description)
- **Action** - A performed skill with timing (startTime, duration, endTime, effectList, stackCount)
- **Effect** - A buff/debuff instance (ability, unitTag, startTime, endTime, stackCount)

### Saved Variables

Stored in `ADRSV` with account-wide option. Each module adds its defaults via the extension system.

## Debugging

Debug logging is controlled via the Settings menu under Debug section:
- Enable "Debug Logging" master switch
- Use "Ability Name Filter" to filter by ability name (Lua pattern)
- Enable/disable individual debug sub-switches

Debug switches and sub-switches are defined in Core.lua and Models.lua:
- `DS_ACTION` - Action debug (find, new, match, unref, stack, remove, delete, save, clear)
- `DS_EFFECT` - Effect debug (gain, fade, update, refresh, transfer, miss, match)
- `DS_COMBAT` - Combat debug (event, fade, stack, tick, duration, channel)
- `DS_FILTER` - Filter debug (accept, reject)
- `DS_TARGET` - Target debug (track)
- `DS_MODEL` - Model debug (stack, purge)

Log format: `[XX*]` where XX is the debug marker (e.g., `[AFA]` = Action Find Action found)

## Key Files

- `Core.lua:1250-1280` - Event registration and main update loop
- `Models.lua:123-245` - Action creation and ability matching
- `Bar.lua:73-193` - Timer bar update logic
- `Alert.lua:55-111` - Alert popup display

## Localization

Language files in `i18n/` use `put(key, translation)` pattern. Files are named by language code (en, zh, de, fr, es, ja, pt, ru). The manifest loads `$(language).lua` dynamically based on client language.

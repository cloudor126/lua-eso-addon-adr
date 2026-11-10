# AGENTS.md

This file provides guidance to AI coding agents when working with code in this
repository.

## Project Overview

Action Duration Reminder is an Elder Scrolls Online (ESO) addon that tracks
ability cooldowns, buff durations, and DoT timers. It displays countdown timers
on the action bar and can show popup alerts when effects expire.

## Build Commands

There is no Gradle wrapper in the repo; use the system `gradle` command.

```bash
# Build distribution zip
gradle distZip

# Build the embedded/ distribution (guarded, UI-less core sources)
gradle buildEmbedded

# Install to ESO Live directory (requires gradle.properties)
gradle installToLive

# Install to ESO PTS directory (requires gradle.properties)
gradle installToPTS

# Upload to esoui.com (requires API token in gradle.properties)
gradle upload
```

The `gradle.properties` file must define (may live at user level,
`~/.gradle/gradle.properties`, as on this machine):

- `ESO_LIVE_ADDONS_DIR` - path to ESO live addons folder
- `ESO_PTS_ADDONS_DIR` - path to ESO PTS addons folder
- `com.esoui.apiToken` - API token for esoui.com uploads

Build tool notes:

- Cold daemon start on Windows takes 30-60s legitimately (JVM + antivirus
  scan); `gradle --status` shows an idle daemon.
- Client disconnect does not stop the daemon - after an abort, a re-run
  reporting `UP-TO-DATE` proves the previous run completed.
- `test/ADRHostTest/libs/` is gitignored; refresh it with
  `cp -r build/embedded test/ADRHostTest/libs/ADR` after `buildEmbedded`.

Version numbers are extracted from the first line of `changelog`.

## Architecture

### Module System

The addon uses a consistent module pattern. Each module file follows this
structure:

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
- **Action** - A performed skill with timing (startTime, duration, endTime,
  effectList, stackCount)
- **Effect** - A buff/debuff instance (ability, unitTag, startTime, endTime,
  stackCount)

### Saved Variables

Stored in `ADRSV` with account-wide option. Each module adds its defaults via
the extension system.

## Debugging

Debug logging is controlled via the Settings menu under Debug section:

- Enable "Debug Logging" master switch
- Use "Ability Name Filter" to filter by ability name (Lua pattern)
- Enable/disable individual debug sub-switches

Debug switches and sub-switches are defined in Core.lua and Models.lua:

- `DS_ACTION` - Action debug (find, new, match, unref, stack, remove, delete,
  save, clear)
- `DS_EFFECT` - Effect debug (gain, fade, update, refresh, transfer, miss,
  match)
- `DS_COMBAT` - Combat debug (event, fade, stack, tick, duration, channel)
- `DS_FILTER` - Filter debug (accept, reject)
- `DS_TARGET` - Target debug (track)
- `DS_MODEL` - Model debug (stack, purge)

Log format: `[XX*]` where XX is the debug marker (e.g., `[AFA]` = Action Find
Action found)

## Key Files

- `Core.lua:1250-1280` - Event registration and main update loop
- `Models.lua:123-245` - Action creation and ability matching
- `Bar.lua:73-193` - Timer bar update logic
- `Alert.lua:55-111` - Alert popup display

## Localization

Language files in `i18n/` use `put(key, translation)` pattern. Files are named
by language code (en, zh, de, fr, es, ja, pt, ru). The manifest loads
`$(language).lua` dynamically based on client language.

## ESO UI Interop Lessons (BackBar & beyond)

Hard-won during v3.170 double-bar development. Read before touching anything
that overrides or fights the native action bar UI. The meta-rule:
**every fix must name its blast radius; undocumented overrides WILL produce
follow-up bugs.**

### The state-ownership contract

Every place we override native UI state needs a written contract, or it WILL
break later (each of these caused real incident chains):

- WHAT we change (anchors, dims, visibility, template)
- WHEN the native system re-applies it (template replay comes via BOTH a Lua
  path (`ApplyTemplateToControl`, hookable) AND a C-internal path (invisible
  to Lua hooks); swap/platform/keybind chains re-apply at unpredictable times)
- WHEN we re-assert (same frame via PostHook, or heartbeat guard as backstop)
- WHEN we stand down (leaving a preset/platform must DISARM - see the
  `exitStatic` disarm of `nativeUltResized`, which was causing our own armed
  reapply hook to tamper the re-parented 1-5/T labels in static)

Latched one-shot guards (`if adjusted then return end`) assume "set once,
stays" — in ESO that assumption is false. Either pair them with a re-assert
after every known replay path, or use a full-match heartbeat guard
(verify anchor == exactly ours: single anchor + correct relativeTo + correct
relativePoint; comparing only relativeTo misses tampering that keeps the
parent but changes the point).

### Proven-stable patterns (prefer these over fighting)

0. **Zero-coupling module add-ons** (v3.172 MiniBar pattern): a new preset that is
   architecturally "mainonly + self-contained add-on" must not entangle the
   existing pipeline. MiniBar loads only Settings/Core/Models, self-observes
   its inputs via the Core heartbeat (preset/enable/scale changes detected
   within 100ms - no menu callbacks), and Bar/MiniBar hold zero references to
   each other; the only shared thing is the `barPreset` value domain
   (`PRESET_VALUES`). If you find yourself adding "notify the other module"
   hooks, make the other module poll its inputs instead.

1. **Re-parent** (`SetParent` out of the native subtree): the native template
   replay finds controls by GLOBAL NAME REGISTRY, so re-anchoring is never
   enough — it will find and re-anchor your control wherever it lives.
   Re-parenting to our own container/`ZO_ActionBar1` removes it from the
   replay's subtree... note name-lookup can STILL reach it via C paths; keep
   the heartbeat guard. After re-parenting, `GetNamedChild` no longer finds
   the control — always store the reference (see `pinnedKeybindTexts`,
   `pinnedQsLabel`, `pinnedUltLk/Rk`).
2. **Template selection over pixel transcription**: "make native slot X look
   like slot Y" = `ApplyStyle(ZO_GetPlatformTemplate("ZO_Y_Template"))` —
   platform-adaptive, zero literals. Hand-coded pixels (`SetDimensions(61)`,
   ±4 anchors) must each be reversed on every transition — historically
   produced mixed keyboard/gamepad residue states. ONE caveat: applying a
   template resets EVERYTHING that template defines (including ButtonText
   anchors other code had adjusted) — audit all consumers after the
   application site (the `setNativeKeybindOffset` re-assert after
   `applyNativeAbilityStyle` exists for exactly this).
3. **Platform-aware arming**: any native-mutation machinery (resize hooks,
   template re-application) must early-return on the platform where it does
   not apply, and disarm when leaving that platform. An armed hook in the
   wrong preset/platform is a time bomb.
4. **Single truth for value domains, fail-open for behavior branches**: if
   two independent literal lists/derivations describe the same domain
   (legal preset values, current slot size, anchor constants), they WILL
   drift — v3.172 had the preset validator silently resetting the new
   `mini`/`mainonly` values back to `dynamic` on every load because the
   dropdown list and the validation whitelist were separate literals
   (`PRESET_VALUES` is the fix; the swap-animation size bug was the same
   disease: four paths re-deriving platform dims until `currentSlotSize`
   became the one truth). Rule: value domains get ONE code-level table that
   every consumer references — a "register new presets here" COMMENT is
   not a source of truth. Behavioral per-value branches may stay
   distributed, but every one must fail OPEN (unknown value falls through
   to a safe default branch), never fail closed (validate-then-reset user
   data). When a "truth" is invisible (template-injected draw triples),
   don't guess it — dump it (`GetDrawLayer/Tier/Level`) and observe.

### ESO API facts (verified against esoui source, not guessed)

- **Draw order (empirically mapped, v3.171 z-order work)**: `layer → tier → level → tree order (depth-first + creation order)`. Layer/tier/level are GLOBAL comparators within the layer; tree order only breaks exact ties. Template chains inject triples (gamepad icon = 0/1/1, native border BD = 0/1/0; negative tiers clamp to 0). To sink a whole subtree below another sibling subtree: parent it under an EARLIER XML child (we use `ZO_ActionBar1WeaponSwap` — children order KeybindBG→WeaponSwap→slot buttons; KeybindBG is hidden in gamepad so unusable) and make every control inside tie-or-below the native counterparts' triples (`setCloneSize` zeroes border-ish children, sinks icons to 0/1/0). To stay above the sibling icon but below the foreign subtree: full triple PARITY with the icon (tie → creation order wins locally, tree order loses globally). Never absolute layer buckets (`DL_TEXT`/`DL_CONTROLS`) inside a subtree that must sink — they jump the tree order entirely.
- **The sink trick is for draggable rows only.** The native back row (ActionBarTimer slots) renders ABOVE the native slots (late children of ZO_ActionBar1) - its capsule is designed to overlap the bar and float on it. Sinking a fixed native-replica row buries it (invisible on gamepad's taller/tighter slots). Match the interaction semantics, not the superficial "second row" similarity.
- **Hidden parents hide the entire subtree.** `WeaponSwap` and `KeybindBG` are natively PERMANENTLY HIDDEN in gamepad - never parent a row container under them unless you also un-hide them (BackBar does, deliberately, in dynamic mode). `QuickslotButton`/`ZO_ActionBar1` itself are always-visible hosts.
- **Control names go into the GLOBAL name registry.** `CreateControl("Icon", ...)` collides on the second slot ("Duplicate name"). Anonymous children (`nil` name) + stored references; `GetNamedChild` no longer finds them (that's fine, you have the refs).
- **Virtual template names must be verified, never assumed.** `CreateControlFromVirtual(nil, parent, "ZO_StatusBar")` fails - no such virtual. The keyboard back-row fill bar is a BARE `CT_STATUSBAR` (no template inheritance in the XML; only the gamepad override inherits `ZO_GamepadStatusBarMedium`).
- **DDS art-layer semantics are black boxes.** Back-row art trio: `Frame` = decorative capsule border; `BG(BLANK)` = a FULL-COVER panel that erases everything beneath it (including the Frame border) - NOT a corner mask; `Overlay` = the desaturation veil AND the source of the native resting "border" feel. Three rounds of wrong inference (mask theory → cover theory → border-origin theory) were settled only by the user's eyes on the live native feature. Art questions are settled empirically or not at all.
- **Platform-switch hooks: use `ZO_PlatformStyle:New(callback)`** (the repo's proven mechanism - Bar/BackBar use it; fires once immediately at creation and again at the correct point in the native platform chain). A raw `EVENT_GAMEPAD_PREFERRED_MODE_CHANGED` + `zo_callLater` handler proved unreliable (garbled layout after switching back).
- **Every platform-dependent creation value must be re-applied by relayout.** The full list for a row: control dims, anchors, art FILES, **TextureCoords** (keyboard and gamepad arts occupy different atlas regions - stale coords corrupt the art while all geometry checks green), child anchors (fill bar, icons), scale. A broken-vs-healthy dump diff with IDENTICAL geometry points straight at render state (texture sampling, layers) that geometry dumps can't see.
- `ActionSlotHasActivationHighlight(slot, hotbar)` returns STALE values for
  the inactive hotbar (engine only maintains active-bar slot state; swap
  refreshes it). No public API gives live truth for inactive bars; FAB does
  not render clone highlights at all. We poll `UpdateActivationHighlight`
  and accept stale-until-swap (glow prompts usage; unused-glow stuck is the
  accepted rare case).
- `ApplySwapAnimationStyle` reads the CURRENT FlipCard dims to set the SIZE
  animation's start/end. It runs inside `ApplyStyle` BEFORE any PostHook
  shrink — always re-call it after resizing FlipCard, or the flip animation
  interpolates to the old template size.
- `PlayUltimateReadyAnimations`: while `g_activeWeaponSwapInProgress` the
  burst (and its OnPlay sound) is skipped — only the silent loop starts; and
  since the loop is LOOP_INDEFINITELY, later burst attempts are blocked while
  it plays. Deterministic swap-to-ready sound = call `nb:UpdateUltimateMeter()`
  ~50ms after the swap animation completes and let native decide.
- `EVENT_KEYBIND_DISPLAY_MODE_CHANGED` (NOT `EVENT_INTERFACE_SETTING_CHANGED`)
  fires for the Keybind Display Mode setting (it lives in the Gameplay panel
  but is stored as SETTING_TYPE_GAMEPAD > GAMEPAD_SETTING_KEYBIND_DISPLAY_MODE).
  Full label-refresh chain: keybindingutils.lua registers labels for
  KEYBINDING_SET/CLEARED/LOADED, GAMEPAD_PREFERRED_MODE_CHANGED,
  INPUT_TYPE_CHANGED, KEYBIND_DISPLAY_MODE_CHANGED.
- Weapon-swap fires EVENT_ACTION_SLOTS_ACTIVE_HOTBAR_UPDATED **multiple
  times** per swap (first didActiveHotbarChange=true, rest false). Any
  per-swap logic must gate on the parameter (the 7x stacked sound bug).
- `ZO_Keybindings_ShouldShowGamepadKeybind()` is the correct gamepad-keybind
  visibility check (gamepad UI mode alone is NOT enough — there is a separate
  keybind display setting).
- `GetAbilityCost` does not exist; use `GetSlotAbilityCost(slot, mechanic,
  hotbar)` (what native `UpdateCurrentUltimateMax` uses).
- Lua 5.1: no `\x` escapes in string literals; `#` on holey tables (keys
  3-8) returns an implementation-defined border — can be 8! Never use `#`/
  numeric-for on non-sequential tables; iterate explicit key ranges or
  `ipairs` over a wrapper.
- Destruction-staff ability icons follow the CURRENT weapon (game bug), even
  the abilityId readback changes; memory keyed by hotbar:slot with texture
  capture-while-active is the workaround (abilityId comparison is useless).
- `ZO_PostHook` on a method that our own hook chain re-invokes WILL recurse
  (ApplyStyle → our hook → ApplySwapAnimationStyle → our hook → ...) —
  re-entrancy latch required.

### Debugging methodology (enforced by the maintainer, for good reason)

1. NEVER patch from theory. Read the esoui source (local dump at
   `C:\Users\Cloudor\Downloads\eso-ui-src\`, full repo via zread/GitHub
   `esoui/esoui`) or demand a dump first.
2. `/adrbackbar` prints one-line-per-slot sizes (D3/D8/N3/N8), keybind label
   states (KB3-8, Q), and activation-highlight queries. Extend it rather than
   adding chat spam.
3. For "who changed this state" questions, wrap the suspect global
   (`PlaySound`, `ApplyTemplateToControl`) with a before/after comparator +
   `debug.traceback()` — one reproduction identifies the culprit chain. The
   C-internal path will NOT show; that's itself diagnostic evidence.
4. A "state that needs constant re-assertion" is a design smell — the correct
   fix is usually structural (re-parent / template selection / disarm), not
   another re-assertion site.
5. Each fix commit must state its blast radius in the message; if you touched
   a template application site, enumerate every consumer of the state that
   template resets.

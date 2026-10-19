# Embedding the ADR tracking core

This folder contains the **tracking core of Action Duration Reminder (ADR)**
without any UI modules (no bars, alerts, patches). It lets your addon use
ADR's action/effect tracking:

- **If the player already has ADR installed**, your addon automatically uses
  the running standalone ADR - the files below stay dormant.
- **If the player does not have ADR**, your embedded copy becomes active and
  provides the same tracking data through the same API (see `API.md`).

Every module file in this folder has this guard line automatically
prepended at build time - keep it intact:

```lua
if _G.ADR_EMBED_SKIP then return end
```

## Files

| File          | Required | Notes                                            |
| ------------- | -------- | ------------------------------------------------ |
| EmbedAdr.lua  | yes      | Bootstrap. Must be the FIRST ADR file in your manifest. |
| Utils.lua     | yes      | Shared helpers.                                  |
| i18n/en.lua   | yes      | English strings.                                 |
| i18n/xx.lua   | optional | Additional languages; add after en.lua.          |
| Settings.lua  | yes      | Saved variables; degrades gracefully without LibAddonMenu-2.0. |
| Models.lua    | yes      | Ability/Action/Effect data structures.           |
| Core.lua      | yes      | Combat/effect event handling and matching.       |
| Debug.lua     | yes      | Debug logging support (useful for bug reports).  |

## How to embed

1. Copy the files above into your addon, e.g. `YourAddon/libs/ADR/`.
2. Add to `YourAddon.txt` (manifest):

   ```
   ## OptionalDependsOn: ActionDurationReminder
   ## SavedVariables: YourAddonADRSV

   libs/ADR/EmbedAdr.lua
   libs/ADR/Utils.lua
   libs/ADR/i18n/en.lua
   libs/ADR/Settings.lua
   libs/ADR/Models.lua
   libs/ADR/Core.lua
   libs/ADR/Debug.lua
   ```

   Replace `YourAddonADRSV` with a name unique to your addon (e.g.
   `TellMeNowADRSV`) and list your own saved-variable names alongside it as
   usual. The file order matters: `EmbedAdr.lua` first, `Core.lua` before
   `Debug.lua`.

3. In any of your files loaded after `EmbedAdr.lua` (typically your main
   file), start the embedded copy when ADR is absent:

   ```lua
   if ADR_EMBED then
     -- 2nd argument = the saved-variables name from your manifest
     ADR_EMBED.activate("YourAddon", "YourAddonADRSV")
   end
   ```

   The call is safe in every scenario: if standalone ADR (or another host's
   embedded copy) is already running, `activate` is a no-op.

4. Use the API exactly as documented in `API.md`:

   ```lua
   local ADR = ActionDurationReminder
   local core = ADR.load("Core")
   local action = core and core.getActionBySlot(HOTBAR_CATEGORY_BACKBAR, 3)
   ```

## Coexistence rules

- **`## OptionalDependsOn: ActionDurationReminder` is mandatory.** It
  guarantees the standalone ADR loads first, so the embedded files can
  detect it and stay dormant. Without it the load order is undefined and
  both copies may end up half-initialized.
- **First one wins.** If standalone ADR is installed, it always takes
  precedence - even if your embedded copy is newer. Check versions and ask
  the player to update ADR instead:

  ```lua
  if ActionDurationReminder and not ActionDurationReminder.embedded
    and ActionDurationReminder.apiVersion < 3 then
    -- warn: installed ADR is too old for feature X
  end
  ```

- If several addons embed this core and ADR is absent, the first embedded
  copy to load becomes active; the others reuse it automatically.

## Saved variables and LibAddonMenu

- Declare `## SavedVariables: YourAddonADRSV` (a name unique to your addon)
  and pass the same name as the 2nd argument of `ADR_EMBED.activate()`. The
  embedded core stores its settings there. Do NOT declare `ADRSV` itself:
  two addons declaring the same saved-variable name makes both
  SavedVariables files fight over one global. Without the declaration (or
  the 2nd argument) the embedded copy falls back to defaults on every
  reload.
- LibAddonMenu-2.0 is NOT required. Without it, the embedded core runs fine
  and simply has no settings panel.

## Updating

Copy the files from the `embedded/` folder of a **released ADR zip** (or an
installed copy of ADR from `Elder Scrolls Online/live/AddOns/`). Do not
copy from the GitHub source tree - version placeholders are only replaced
in release builds. Replace all files at once; the files are matched by
version and must not be mixed across releases.

## Attribution

Keep the file headers and this notice intact. Please credit
"Action Duration Reminder by Cloudor" in your addon description and link
its ESOUI page (https://www.esoui.com/downloads/info1536-ActionDurationReminder.html).

# ADR embedded core - in-game test checklist

`ADRHostTest` is a throwaway host addon for verifying the embedded core.
Its `libs/ADR/` is a copy of `build/embedded/` (refresh it with
`gradle buildEmbedded` + the copy command below if the build changes).

```bash
cp -r build/embedded test/ADRHostTest/libs/ADR
```

Copy `test/ADRHostTest` into
`Elder Scrolls Online/live/AddOns/` and run through the scenarios.

Commands: `/adrtest` (state dump), `/adrtesttick` (per-tick most-urgent report).

## A) Standalone ADR only (baseline)

1. Ensure `ActionDurationReminder` is installed (installToLive already did).
2. Login, no `ADRHostTest` yet (or skip it): no Lua errors, bars work.
3. `/script d(ActionDurationReminder.apiVersion)` -> `3`.
   `d(ActionDurationReminder.embedded)` -> `nil`.
4. New in 3.165: Settings -> Alert -> "Text Color" picker: pick a color,
   trigger an alert (let a tracked buff expire) -> alert text uses the
   chosen color; `/reloadui` -> setting persists.

## B) Embedded fallback (real ADR absent)

1. Rename `AddOns/ActionDurationReminder` to `ActionDurationReminder.off`.
2. Login with `ADRHostTest` present. No Lua errors on load.
3. `/adrtest`:
   - `ADR_EMBED: v3.165 apiVersion=3 sv=ADRHostTestADRSV`
   - `ADR: version=3.165 apiVersion=3 embedded=true`
   - `tracked actions:` grows after casting slotted skills with durations.
   - `effects=` counts > 0 for self-buffs.
4. `/adrtesttick` -> cast skills, "urgent:" lines appear every ~100ms.
5. Persistence: `/reloadui`, re-run `/adrtest` - no errors, tracking works
   again. `/script d(ADRSV)` -> `nil` (embedded copy never touches ADRSV;
   its settings live in `ADRHostTestADRSV`).

## C) Coexistence (real ADR + host) - the critical scenario

1. Rename `ActionDurationReminder.off` back, keep `ADRHostTest`.
2. Login. No Lua errors, exactly ONE tracking copy (no duplicated bars -
   embedded core has no UI anyway).
3. `/adrtest`:
   - `embedded=nil` or `false` -> the REAL ADR won (first-wins).
   - `/adrtesttick` still works (host consumes the real ADR's API).
4. Settings persistence: change an ADR setting (e.g. Alert "Text Color"),
   `/reloadui`, verify it persisted. (The embedded copy now uses its own
   `ADRHostTestADRSV` name, so no shared-name risk remains - this step is
   just a regression check.)

## D) Optional: second host (multi-embed, only if curious)

Duplicate `ADRHostTest` as `ADRHostTest2` (rename Title/folder/main file and
slash commands). With real ADR absent, first-loaded host's embedded copy
wins; second host reuses it (`/adrtest` on both shows same `embedded=true`).

Pass criteria: A/B/C green. D is a bonus.

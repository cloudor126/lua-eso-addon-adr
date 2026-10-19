-- ADRHostTest: smoke-test host for the ADR embedded core. Dev tool only.
--
-- Commands:
--   /adrtest      dump ADR API state (version, apiVersion, embedded, tracked actions)
--   /adrtesttick  toggle per-tick "most urgent ability" report (Core:update extension)
--
-- Expected results per scenario (see test/README.md):
--   A) real ADR installed:  embedded=false, actions tracked by the real ADR
--   B) real ADR removed:    embedded=true,  actions tracked by the embedded copy
--   C) reload & settings persistence in both scenarios

local ADDON_NAME = "ADRHostTest"

-- bootstrap the embedded copy when standalone ADR is absent (no-op otherwise)
if ADR_EMBED then
  ADR_EMBED.activate(ADDON_NAME, "ADRHostTestADRSV")
end

local function dump()
  local ADR = _G.ActionDurationReminder
  d("=== ADRHostTest ===")
  if ADR_EMBED then
    d(string.format("ADR_EMBED: v%s apiVersion=%s sv=%s", tostring(ADR_EMBED.version), tostring(ADR_EMBED.apiVersion), tostring(_G.ADR_EMBED_SV_NAME)))
  else
    d("ADR_EMBED: nil (!!)")
  end
  if not ADR then
    d("!! ActionDurationReminder global is nil")
    return
  end
  d(string.format("ADR: version=%s apiVersion=%s embedded=%s", tostring(ADR.version), tostring(ADR.apiVersion), tostring(ADR.embedded)))
  local core = ADR.load("Core")
  if not core then
    d("!! Core module is nil (did activate() run?)")
    return
  end
  local idActionMap = core.getIdActionMap()
  local n = 0
  for _ in pairs(idActionMap) do
    n = n + 1
  end
  d("tracked actions: " .. n)
  local now = GetGameTimeMilliseconds()
  local shown = 0
  for id, action in pairs(idActionMap) do
    if shown < 8 then
      d(string.format(
        "  [%d] %s remaining=%.1fs effects=%d",
        id,
        action.ability.name,
        (action.endTime - now) / 1000,
        #action:getEffectList()
      ))
      shown = shown + 1
    end
  end
end

local tickOn = false
local tickRegistered = false
SLASH_COMMANDS["/adrtest"] = dump
SLASH_COMMANDS["/adrtesttick"] = function()
  local ADR = _G.ActionDurationReminder
  local core = ADR and ADR.load("Core")
  if not core then
    d("ADRHostTest: no Core module")
    return
  end
  if not tickRegistered then
    tickRegistered = true
    ADR.extend(core.EXTKEY_UPDATE, function()
      if not tickOn then
        return
      end
      local best, bestRemaining = nil, math.huge
      local now = GetGameTimeMilliseconds()
      for _, action in pairs(core.getIdActionMap()) do
        local remaining = action.endTime - now
        if remaining > 0 and remaining < bestRemaining then
          best, bestRemaining = action, remaining
        end
      end
      if best then
        d(string.format("urgent: %s %.1fs", best.ability.name, bestRemaining / 1000))
      end
    end)
  end
  tickOn = not tickOn
  d("ADRHostTest tick " .. (tickOn and "ON" or "OFF"))
end

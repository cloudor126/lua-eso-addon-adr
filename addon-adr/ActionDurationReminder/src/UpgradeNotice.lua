--========================================
--        vars
--========================================
---@type adr.addon.M
local addon = ActionDurationReminder
---@type adr.settings.M
local settings = addon.load("Settings#M")
local l = {}
local m = { l = l }

--========================================
--        l
--========================================
local DIALOG_NAME = "ADR_BAR_PRESET_NOTICE"
local ACCOUNT_FLAG = "barPresetNoticeShown"

---账号级一次性升级提示：3.170 引入技能栏三种风格预设。
---旗标存账号级存档(与"账号级配置"开关无关)，整个账户只弹一次；
---全新安装(从未见过 ChatAlert 欢迎提示的账号)跳过本提示，避免新装连弹两窗
---@type fun()
l.showOnce = function()
  local accountSv = settings.getAccountSavedVars()
  if accountSv[ACCOUNT_FLAG] then
    return
  end
  -- 全新安装判定：旧功能提示旗标(ChatAlert 欢迎窗)从未置位 = 本账号首次使用 ADR
  if accountSv.chatAlertPromptShown == nil then
    accountSv[ACCOUNT_FLAG] = true
    return
  end
  -- 展示即置旗(即使关闭回调缺失也不会重复弹出)
  accountSv[ACCOUNT_FLAG] = true
  ESO_Dialogs[DIALOG_NAME] = {
    canQueue = true,
    title = { text = addon.text("Bar Style Presets Upgrade Notice") },
    mainText = { text = addon.text("Upgrade notice body: three bar presets") },
    buttons = {
      { text = SI_DIALOG_CLOSE },
    },
  }
  -- 登录完成后再弹(加载屏幕期间弹窗可能丢失)，稍作延迟避免与其他弹窗抢占
  zo_callLater(function()
    ZO_Dialogs_ShowDialog(DIALOG_NAME)
  end, 1500)
end

--========================================
--        register
--========================================
addon.register("UpgradeNotice#M", m)

addon.register("UpgradeNotice", m)

-- 存档加载完成后监听登录完成事件(一次性)
addon.hookStart(function()
  local EM = GetEventManager()
  local name = "ADRUpgradeNotice"
  EM:RegisterForEvent(name, EVENT_PLAYER_ACTIVATED, function()
    EM:UnregisterForEvent(name, EVENT_PLAYER_ACTIVATED)
    l.showOnce()
  end)
end)

--========================================
--        vars
--========================================

---@type adr.addon.M
local addon = ActionDurationReminder
---@type adr.utils.M
local m = {}
---@type adr.utils.RecentCache
local mRecentCache = {}

--========================================
--        types
--========================================
---近期计数缓存(滑动窗口)对象，构造于m.newRecentCache，setmetatable({},{__index=mRecentCache})
---@class adr.utils.RecentCache
---@field num? number 窗口槽数
---@field unit? number 每槽时长(ms)
---@field offset? number 当前窗口序号
---@field data? table<number, table<any, number>> 各槽计数
---@field get? fun(self: adr.utils.RecentCache, key: any): number
---@field mark? fun(self: adr.utils.RecentCache, key: any)
---@field roll? fun(self: adr.utils.RecentCache)

---Utils模块公开表(addon.register("Utils#M"))
---@class adr.utils.M
---@field newRecentCache? fun(duration: number, num: number): adr.utils.RecentCache

--========================================
--        m
--========================================

---@type fun(duration: number, num: number): adr.utils.RecentCache
m.newRecentCache = function(duration, num)
  ---@type adr.utils.RecentCache
  local recentCache = {}
  recentCache.num = num
  recentCache.unit = math.floor(duration / num)
  recentCache.offset = 0
  recentCache.data = {}
  setmetatable(recentCache, { __index = mRecentCache })
  return recentCache
end

--========================================
--        mRecentCache
--========================================
---@type fun(self: adr.utils.RecentCache, key: any): number
mRecentCache.get = function(self, key)
  self:roll()
  local result = 0
  for index = 1, self.num do
    local slot = self.data[index]
    if slot and slot[key] then
      result = result + slot[key]
    end
  end
  return result
end

---@type fun(self: adr.utils.RecentCache, key: any)
mRecentCache.mark = function(self, key)
  self:roll()
  self.data[1] = self.data[1] or {}
  local slot = self.data[1]
  if slot[key] then
    slot[key] = slot[key] + 1
  else
    slot[key] = 1
  end
end

---@type fun(self: adr.utils.RecentCache)
mRecentCache.roll = function(self)
  local newOffset = math.floor(GetGameTimeMilliseconds() / self.unit)

  local shift = newOffset - self.offset
  if shift > 0 then
    for i = self.num, 1, -1 do
      local from = i - shift
      self.data[i] = from > 0 and self.data[from] or nil
    end
    self.offset = newOffset
  end
end

--========================================
--        register
--========================================
addon.register("Utils#M", m)

addon.register("Utils", m)

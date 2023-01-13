--========================================
--        vars
--========================================

local addon = ActionDurationReminder -- Addon#M
local m = {} -- #M
local mRecentCache = {} -- #RecentCache

--========================================
--        m
--========================================

m.newRecentCache -- #(#number:duration,#number:num)->(#RecentCache)
= function(duration, num)
  local recentCache = {} -- #RecentCache
  recentCache.num = num --#number
  recentCache.unit = math.floor(duration/num) --#number
  recentCache.offset = 0
  recentCache.data = {}
  setmetatable(recentCache,{__index=mRecentCache})
  return recentCache
end

--========================================
--        mRecentCache
--========================================
mRecentCache.get -- #(#RecentCache:self, #any:key)->(#number)
= function(self, key)
  self:roll()
  local result = 0
  for index=1, self.num do
    local slot = self.data[index]
    if slot and slot[key] then result = result + slot[key] end
  end
  return result
end

mRecentCache.mark -- #(#RecentCache:self, #any:key)->()
= function(self, key)
  self:roll()
  self.data[1] = self.data[1] or {}
  local slot = self.data[1]
  if slot[key] then
    slot[key] = slot[key]+1
  else
    slot[key] = 1
  end
end

mRecentCache.roll -- #(#RecentCache:self)->()
= function(self)
  local newOffset = math.floor(GetGameTimeMilliseconds()/self.unit)

  local shift = newOffset-self.offset
  if shift>0 then
    for i=self.num,1,-1 do
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

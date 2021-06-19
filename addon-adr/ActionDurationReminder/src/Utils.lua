--========================================
--        vars
--========================================

local addon = ActionDurationReminder -- Addon#M
local m = {} -- #M
local mRecentCache = {} -- #RecentCache

--========================================
--        m
--========================================

m.newRecentCache -- #(#number:numSeconds)->(#RecentCache)
= function(numSeconds)
  local recentCache = {} -- #RecentCache
  recentCache.numSeconds = numSeconds -- #number
  recentCache.now = 0
  recentCache.data = {}
  setmetatable(recentCache,{__index=mRecentCache})
  return recentCache
end

--========================================
--        mRecentCache
--========================================
mRecentCache.countMark -- #(#RecentCache:self, #any:key)->(#number)
= function(self, key)
  self:roll()
  local result = 0
  for index=1, self.numSeconds do
    local slot = self.data[index]
    if slot and slot[key] then result = result + slot[key] end
  end
  return result
end

mRecentCache.get -- #(#RecentCache:self, #any:key)->(#any)
= function(self, key)
  self:roll()
  local result = {}
  for index=1, self.numSeconds do
    local slot = self.data[index]
    if slot and slot[key] then table.insert(result,slot[key]) end
  end
  if #result>1 then return result else return nil end
end

mRecentCache.getCurrentSlot -- #(#RecentCache:self)->(#any)
= function(self)
  self:roll()
  self.data[1] = self.data[1] or {}
  return self.data[1]
end

mRecentCache.mark -- #(#RecentCache:self, #any:key)->()
= function(self, key)
  self:roll()
  local slot = self:getCurrentSlot()
  if slot[key] then
    slot[key] = slot[key]+1
  else
    slot[key] = 1
  end
end

mRecentCache.roll -- #(#RecentCache:self)->()
= function(self)
  local now = math.floor(GetGameTimeSeconds())
  if now>self.now then
    local shift = now-self.now
    for i=1, self.numSeconds do
      local index = 1+self.numSeconds - i
      if index+shift<=self.numSeconds then -- copy away
        self.data[index+shift]=self.data[index]
      end
      if index-shift <1 then
        self.data[index] = {} -- reset
      end
    end
    self.now = now
  end
end

mRecentCache.save -- #(#RecentCache:self, #any:key, #any:value)->()
= function(self, key, value)
  self:roll()
  self:getCurrentSlot()[key] = value
end



--========================================
--        register
--========================================
addon.register("Utils#M", m)

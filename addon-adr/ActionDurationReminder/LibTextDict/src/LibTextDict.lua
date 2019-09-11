local lib = {} -- #LibTextDict
lib.version = '1.1'
lib.versionNumber = tonumber(lib.version:gsub('(%d+%.%d+).-$','%1'),10)
if LibTextDict and LibTextDict.versionNumber and LibTextDict.versionNumber > lib.versionNumber then return end
LibTextDict = lib
 
local dictProto = {} -- #LibTextDict
do
  dictProto.getText  -- #(#Dict:self,#string:key,#any:...)->(#string)
  = function(self, key, ...)
    local text = self.map[key] or key
    if select("#", ...) > 0 then return zo_strformat(text, ...) end
    return text
  end

  dictProto.setText -- #(#Dict:self,#string:key,#string:translation)->()
  = function (self, key, translation)
    self.map[key] = translation
  end
end

do
  lib.dictMap = {} -- #map<#string, #Dict>
  lib.newDict -- #()->(#Dict)
  = function()
    local dict = {} --#Dict
    dict.map = {} -- #map<#string,#string>
    dict.text = function(key,...) return dict:getText(key,...) end -- #(#string:key,#any:...)->(#string)
    dict.put = function(key,translation) dict:setText(key,translation) end -- #(#string:key, #string:translation)->()
    setmetatable(dict,{__index=dictProto})
    return dict
  end
  lib.getAddonDict  -- #(#LibTextDict:self, #string:addon)->(#Dict)
  = function(self, addon)
    if(not self.dictMap[addon]) then
      self.dictMap[addon] = self.newDict()
    end
    return self.dictMap[addon]
  end
end

---
-- @callof #LibTextDict
-- @param #string addonName
-- @return #Dict the dict

setmetatable(lib, { __call = lib.getAddonDict })

local lib = {} -- #LibTypeRegistry
lib.version = '1.0'
lib.versionNumber = tonumber(lib.version:gsub('(%d+%.%d+).-$','%1'),10)
if LibTypeRegistry and LibTypeRegistry.versionNumber and LibTypeRegistry.versionNumber > lib.versionNumber then return end
LibTypeRegistry = lib

local registryProto ={} -- #Registry
do
  registryProto.put -- #(#Registry:self,#string:typeName,#table:typeProto)->()
  = function(self, typeName, typeProto)
    if typeProto then self.typeMap[typeName] = typeProto end
  end

  registryProto.get -- #(#Registry:self,#string:typeName)->($2)
  = function(self, typeName)
    return self.typeMap[typeName]
  end
end

do
  lib.addonToRegistry = {} -- #map<#string,#Registry>
  lib.newRegistry -- #()->(#Registry)
  = function()
    local registry = {} -- #Registry
    registry.typeMap = {} -- #map<#string, #table>
    setmetatable(registry,{__index = registryProto})
    return registry
  end
  lib.getInstance -- #(#Registry:self, #string:addon)->(#Registry)
  = function(self, addon)
    if not addon then return nil end
    if(not self.addonToRegistry[addon]) then
      self.addonToRegistry[addon] = self.newRegistry()
    end
    return self.addonToRegistry[addon]
  end
end

---
-- @callof #LibTypeRegistry
-- @param #string addonName
-- @return #Registry the registry

setmetatable(lib, { __call = lib.getInstance })

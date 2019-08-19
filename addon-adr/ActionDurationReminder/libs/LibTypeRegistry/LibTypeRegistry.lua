local lib = LibStub:NewLibrary("LibTypeRegistry", 1) -- #Lib
if not lib then
  return  -- already loaded and no upgrade necessary
end

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

  ---
  -- @callof #Lib
  -- @return #Registry the registry
  setmetatable(lib, { __call = lib.getInstance })
end

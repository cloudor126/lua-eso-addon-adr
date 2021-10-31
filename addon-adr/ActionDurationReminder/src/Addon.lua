--========================================
--        vars
--========================================
local l = {} -- #L private table for local use
local m = {l=l} -- #M public table for module use
local NAME = 'ActionDurationReminder'
local VERSION = '@@ADDON_VERSION@@'

--========================================
--        l
--========================================
l.actionMap = {} -- #map<#string,#()->()> store actions for bindings
l.dict = {} --#map<#string,#string>
l.extensionMap = {} -- #map<#string,#list<#()->()>> store extensions for types
l.registry = {} --#map<#string,#any>
l.started = false
l.startListeners = {} -- #list<#()->()> store start listeners for initiation

l.onAddonStarted -- #(#number:eventCode,#string:addonName)->()
= function(eventCode, addonName)
  if NAME ~= addonName then return end
  EVENT_MANAGER:UnregisterForEvent(addonName, eventCode)
  l.start()
end

l.start -- #()->()
= function()
  if l.started then return end
  l.started = true
  while #l.startListeners > 0 do
    table.remove(l.startListeners,1)()
  end
--  if HodorReflexes and HodorReflexes.users then
--    HodorReflexes.users["@Cloudor"] = {"Cloudor", "|cfffe00Cloudor|r", "ActionDurationReminder/src/cloudor.dds"}
--  end
end

--========================================
--        m
--========================================
m.name = NAME -- #string
m.version = VERSION -- #string

m.addAction -- #(#string:key,#()->():action)->()
= function(key, action)
  l.actionMap[key] = action
end

m.callExtension -- #(#string:key,#any:...)->()
= function(key, ...)
  local list = l.extensionMap[key] or {}
  for key, var in ipairs(list) do
    var(...)
  end
end

m.doAction -- #(#string:key,#any:...)->()
= function(key,...)
  local targetAction = l.actionMap[key]
  targetAction(...)
end

m.extend -- #(#string:key, #()->():extension)->()
= function(key, extension)
  local list = l.extensionMap[key]
  if not list then
    list = {}
    l.extensionMap[key] = list
  end
  table.insert(list, extension)
end

m.hookStart -- #(#()->():listener)->()
= function(listener)
  if l.started then listener() end
  table.insert(l.startListeners, listener)
end

m.isSimpleWord -- #(#stirng:s)->(#boolean)
= function(s)
  if s:find(' ',1,true) then return false end
  if s:find('(',1,true) then return false end
  if s:byte(1) and s:byte(1)>128 then return s:len()<=6 end
  return true
end

m.load -- #(#string:typeName)->($1)
= function(typeName)
  return l.registry[typeName]
end

m.putText -- #(#string:key, #string:value)->()
= function(key, value)
  l.dict[key] = value
end

m.register -- #(#string:typeName, #any:typeProto)->()
= function(typeName, typeProto)
  l.registry[typeName]=typeProto
end

m.text -- #(#string:key, #any:...)->(#string)
= function(key,...)
  if select('#',...) ==0 then
    return l.dict[key] or key
  end
  return l.dict[key] and string.format(l.dict[key],...) or string.format(key,...)
end

--========================================
--        register
--========================================
_G[NAME] = m
EVENT_MANAGER:RegisterForEvent(m.name, EVENT_ADD_ON_LOADED, l.onAddonStarted)

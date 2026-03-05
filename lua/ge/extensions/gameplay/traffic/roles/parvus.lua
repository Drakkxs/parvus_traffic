-- lua/ge/extensions/gameplay/traffic/roles/parvusRole.lua

local standardFactory = require('/lua/ge/extensions/gameplay/traffic/roles/standard')
return function(...)
  local role = standardFactory(...)
  local old = role.onRefresh
  role.onRefresh = function(self, ...)
    if old then old(self, ...) end
    if self.veh and self.veh.isAi then
      local obj = getObjectByID(self.veh.id)
      if obj then obj:queueLuaCommand('ai.driveInLane("off")') end
    end
  end
  return role
end
-- lua/ge/extensions/gameplay/traffic/roles/parvus.lua

local random = math.random
local max = math.max

local standardFactory = require('/lua/ge/extensions/gameplay/traffic/roles/standard')
local parvusUtils = require('ge/extensions/parvus/traffic/parvusUtils')
return function(...)
  local role = standardFactory(...)

  local oldinit = role.init
  role.init = function(self)
    if oldinit then oldinit(self) end

    self.parvus_vehData = {
      actionCooldown = 0,
      deadlockTimer = 0,
      lastHornState = true,
      minMovingSpeed = 4,
      hornActive = false
    }
    self.parvus_logTag = 'parvusTraffic'
  end

  local oldRefresh = role.onRefresh
  role.onRefresh = function(self, ...)
    if oldRefresh then oldRefresh(self, ...) end
    if self.veh and self.veh.isAi then
      local obj = getObjectByID(self.veh.id)
      if obj then obj:queueLuaCommand('ai.driveInLane("off")') end
    end
  end

  -- A Deadlock is a situation where the vehicle has been stuck in a traffic jam for too long
  role.parvus_onDeadLock = function(self)
    if self.state == 'disabled' then return end
    -- patient drivers are harder to make honk, and aggresive drivers honk longer.
    if random() > (self.driver.personality.patience + random()) then self.veh:honkHorn(max(0.25, square(random()))) end
  end

  role.parvus_checkVehicle = function(self)
    local parvus_vehData = self.parvus_vehData
    if (parvus_vehData.actionCooldown or 0) > 0 then parvus_vehData.actionCooldown = ((parvus_vehData.actionCooldown or 0) - 1) end

    if self.veh and self.veh.isAi then
      local deadlockTimer = parvus_vehData.deadlockTimer
      if (deadlockTimer or 0) > 5 then
        self:onDeadLock()
        log('D', self.parvus_logTag, '(' .. self.veh.id .. ') Was made to honk to clear a deadlock ')
        parvus_vehData.deadlockTimer = 0
      end
    end

    local objMap = map and map.objects[self.veh.id]
    if not objMap or not objMap.states then return end

    local currentHorn = objMap.states.horn and true or false

    local prevHorn = parvus_vehData.lastHornState or false

    -- horn just turned on
    if currentHorn and not prevHorn then
      return true
    end

    -- the current state for the next check
    parvus_vehData.lastHornState = currentHorn

    return false
  end

  return role
end

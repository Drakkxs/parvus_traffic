-- lua/ge/extensions/parvus/parvusTraffic.lua

-- Traffic with aggression based actions
-- Includes cleanup for crashes
-- Made By Parvus
local M, P = {}, {}
M.dependencies = { 'gameplay_traffic' }
local logTag = 'parvusTraffic'

-- [[REQUIRE]]
local parvusUtils = require('ge/extensions/parvus/traffic/parvusUtils')

-- mathlib
local random = math.random
local floor = math.floor
local min = math.min
local max = math.max

-- [[DATA]]
local trafficIdsSorted = {}
local parvusAuxData = {        -- additional data for traffic
    _overlayInstalled = false, -- is the role overlay installed
    queuedVehicle = 0,         -- current traffic vehicle index
    vehDataTable = {},         -- { 'vehID' = {actionCooldown = 0, lastHornState = false}}
    minMovingSpeed = 4,        -- The minimum speed a vehicle has to be going above to be considered moving

    -- deadlock happens when no vehicles are available to honk to clear obstructions
    -- ai.lua dictates that traffic vehicles only honk once when 'forced to stop' and otherwise will wait indefinitely
    -- this creates a 'deadlock' when no vehicle feels 'forced to stop' and the only one left to fix this is the player
    deadlockTimer = 0
}

-- [[SWITCHBOARDS]]
local tAggresion = { resolution = 2, skew = 2, baseAggression = 0.3, maxAggression = 2, startchance = 1, decay = 0.1, threshold = 2 }
local tSpeeder = { aggressionThreshold = 0.5, startchance = 1, decay = 0.05, threshold = 2 }
local tToughness = { aggressionThreshold = 1, startchance = 1, decay = 0.1, threshold = 2 }
local tReckless = { aggressionThreshold = 1.9, startchance = 1, decay = 0.1, threshold = 2 }

-- when extension loaded
local function onExtensionLoaded()
    log('D', logTag, "Extension Loaded")
end

-- updates every frame
local function onUpdate(dtReal, dtSim)
    -- Only During Traffic
    if gameplay_traffic.getState() ~= "on" then return end
    -- only when sim is actually running
    if dtSim <= 0 then return end
    local stoppedAiVehCount, vehCount, vehCountAi = 0, 0, 0
    for i, id in ipairs(trafficIdsSorted) do -- ensures consistent order of vehicles
        vehCount = vehCount + 1
        local veh = gameplay_traffic.getTrafficData()[id]
        if veh then
            if veh.isAi then
                vehCountAi = vehCountAi + 1
                if veh.speed < parvusAuxData.minMovingSpeed then
                    stoppedAiVehCount = stoppedAiVehCount + 1
                end
            end

            ---@diagnostic disable-next-line: undefined-field
            if be:getObjectActive(id) then
                if i == parvusAuxData.queuedVehicle then -- checks one vehicle per frame, as an optimization
                    if veh.roleName == 'parvus' then
                        veh.role:parvus_checkVehicle()
                    end
                end
            end
        end
    end


    parvusAuxData.queuedVehicle = parvusAuxData.queuedVehicle + 1
    if parvusAuxData.queuedVehicle > vehCount then
        parvusAuxData.queuedVehicle = 1
    end

    if stoppedAiVehCount < (vehCountAi * 0.6) then
        -- decrease deadlockTimer
        if (parvusAuxData.deadlockTimer or 0) > 0 then
            parvusAuxData.deadlockTimer = max(0, parvusAuxData.deadlockTimer or 0) - dtSim
        end
    else
        -- indecrease deadlockTimer
        parvusAuxData.deadlockTimer = (parvusAuxData.deadlockTimer or 0) + dtSim
    end
end

-- local function installRoleOverlay()
--     -- Find any traffic vehicle instance so we can access the shared prototype (__index)
--     local traffic = gameplay_traffic.getTrafficData()
--     local sampleVeh
--     for _, v in pairs(traffic) do
--         sampleVeh = v
--         break
--     end
--     if not sampleVeh then return false end

--     local mt = getmetatable(sampleVeh)
--     local proto = mt and mt.__index
--     if not proto then return false end

--     if proto._parvusRoleOverlayInstalled then
--         return true
--     end
--     proto._parvusRoleOverlayInstalled = true

--     local oldSetRole = proto.setRole
--     proto.setRole = function(self, roleName)
--         -- call vanilla behavior first
--         oldSetRole(self, roleName)

--         -- overlay: runs after ANY role is applied
--         if self and self.isAi then
--             log('D', 'parvusTraffic', string.format('[overlay] role=%s applied to id=%d', tostring(roleName), self.id))

--             -- IMPORTANT: run in the vehicle VM through queuedFuncs.vLua
--             -- also: delay a bit because traffic roles often call setAiMode / reset plan
--             self.queuedFuncs.parvusOverlayDriveInLaneOff = {
--                 timer = 2,
--                 vLua = [[
--           if ai and ai.driveInLane then
--             ai.driveInLane("off")
--           end
--         ]]
--             }
--         end
--     end

--     log('I', 'parvusTraffic', '[overlay] installed role overlay (wrap setRole)')
--     return true
-- end

-- Past threshold the chances begin to drop
local function probabilityWithinValue(value, startChance, decay, threshold)
    -- Get amount of active traffic vehicles
    local N = value

    local chance
    if N <= threshold then
        chance = startChance
    else
        chance = startChance / (1 + decay * (N - threshold))
    end

    return chance
end

local function parvus_TrafficSetupAggression(id)
    local targetVeh = gameplay_traffic.getTrafficData()[id]
    if not targetVeh then return end
    if random() < probabilityWithinValue(gameplay_traffic.getTrafficAmount(true), tAggresion.startchance, tAggresion.decay, tAggresion.threshold) then
        -- Aggression
        local res = 10 ^ tAggresion.resolution -- [0,1,2,3,4,5,6] allowed resolutions
        local maxr = tAggresion.maxAggression
        local minr = gameplay_traffic.getTrafficVars().baseAggression or tAggresion.baseAggression
        local aggression = (
            ((random(0, res) / res) ^ tAggresion.skew) * (maxr - minr) + minr
        ) -- lower skew between 0.35 and 2

        -- set personality
        local role, driver, personality = P.getDriverPersonality(id)
        local minBound, maxBound = 0.1, 1
        local basePersonality = { aggression = 0.5, patience = 0.5, bravery = 0.5 }
        if role and driver and personality then
            personality.aggression = max(min(aggression, maxBound), minBound)

            local newPatience = basePersonality.patience / aggression
            personality.patience = max(min(newPatience, maxBound), minBound)

            local newBravery = basePersonality.bravery * aggression
            personality.bravery = max(min(newBravery, maxBound), minBound)
            driver.personality = personality
            log('D', logTag, '(' .. id .. ') Set Personality (' .. dumps(driver.personality) .. ')')
        end

        local obj = getObjectByID(id)
        if not obj then return end
        obj:queueLuaCommand('ai.setAggression(' .. aggression .. ')')
        log('D', logTag, '(' .. id .. ') Queued Aggression: (' .. aggression .. ')')

        -- Tougher Driver
        local damageLimits = { 50, 1000, 30000 }
        local function toughenDriver(agr, mod)
            for i, v in ipairs(damageLimits) do
                targetVeh.damageLimits[i] = floor(max(v, (v * agr) + (mod or 0)))
            end
            log('D', logTag, 'Damage Limits: (' .. dumps(targetVeh.damageLimits) .. ')')
            log('D', logTag, '(' .. id .. ') Tougher Driver Spawned (Aggression=' .. aggression .. ')')
        end
        if aggression > tToughness.aggressionThreshold and damageLimits and random() < probabilityWithinValue(gameplay_traffic.getTrafficAmount(true), tToughness.startchance, tToughness.decay, tToughness.threshold) then
            toughenDriver(aggression)
        end

        -- Emergency vehicles will not have their ai parameters affected beyond aggression to preserve any complex logic
        if targetVeh and targetVeh.roleName and (targetVeh.roleName == 'police' or targetVeh.roleName == 'emergency') then return end

        -- [[Begin Role Injection]]

        -- -- try to install once traffic vehicles exist
        -- if not parvusAuxData._overlayInstalled then
        --     parvusAuxData._overlayInstalled = installRoleOverlay()
        -- end

        -- [[End Role Injection]]

        -- -- Speeders
        -- if aggression > tSpeeder.aggressionThreshold and random() < probabilityWithinValue(gameplay_traffic.getTrafficAmount(true), tSpeeder.startchance, tSpeeder.decay, tSpeeder.threshold) then
        --     toughenDriver(aggression, 4000)
        --     targetVeh.queuedFuncs.parvusTrafficSetSpeedMode = {
        --         timer = 2,
        --         args = { id },
        --         func = function(tid)
        --             local tv = getObjectByID(tid)
        --             if not tv then return end
        --             tv:queueLuaCommand('ai.setSpeedMode("off")')
        --         end
        --     }
        --     log('D', logTag, '(' .. id .. ') Speeder Spawned (Aggression=' .. aggression .. ')')
        -- end

        -- Reckless
        -- if aggression > tReckless.aggressionThreshold and random() < probabilityWithinValue(gameplay_traffic.getTrafficAmount(true), tReckless.startchance, tReckless.decay, tReckless.threshold) then
        --     toughenDriver(aggression, 6000)
        --     targetVeh.queuedFuncs.parvusTrafficSetRandom = {
        --         timer = 2,
        --         vLua = [[
        --             ai.setMode("random")
        --             ai.setAvoidCars("on")
        --             local ok, err = pcall(function()
        --             log('D', 'parvusTraffic', "PARVUS: queueLuaCommand reached vehicle VM, vid:", obj:getId())
        --             end)
        --             if not ok then print("PARVUS: ERROR:", err) end
        --         ]],
        --     }
        --     log('D', logTag, '(' .. id .. ') Reckless Spawned (Aggression=' .. aggression .. ')')
        -- end

        -- Distracted
        -- if aggression > tReckless.aggressionThreshold and random() < probabilityWithinValue(gameplay_traffic.getTrafficAmount(true), tReckless.startchance, tReckless.decay, tReckless.threshold) then
        --     toughenDriver(aggression, 6000)
        --     targetVeh.queuedFuncs.parvusTrafficSetDistracted = {
        --         timer = 4,
        --         vLua = [[
        --             ai.setAvoidCars("off")
        --             local ok, err = pcall(function()
        --             log('D', 'parvusTraffic', "PARVUS: queueLuaCommand reached vehicle VM, vid:", obj:getId())
        --             end)
        --             if not ok then print("PARVUS: ERROR:", err) end
        --         ]],
        --     }
        --     log('D', logTag, '(' .. id .. ') Distracted Spawned (Aggression=' .. aggression .. ')')
        -- end

        -- Wander
        -- if true then
        --     -- if aggression > tReckless.aggressionThreshold and random() < probabilityWithinValue(gameplay_traffic.getTrafficAmount(true), tReckless.startchance, tReckless.decay, tReckless.threshold) then
        --     toughenDriver(aggression, 6000)
        --     targetVeh.queuedFuncs.parvusTrafficSetWander = {
        --         timer = 2,
        --         vLua = [[
        --             -- ai.driveInLane("off")
        --             ai.setAvoidCars("on")
        --             ai.driveInLaneFlag = "off"
        --             log('D','parvusTraffic','PARVUS: reached VM, vid='..tostring(obj:getId()))
        --             log('D', 'parvusTraffic', 'PARVUS: ('.. tostring(obj:getId()) ..') Wander Spawned (Aggression='.. tostring(ai.extAggression) ..')')
        --         ]],
        --     }
        --     -- log('D', logTag, '(' .. id .. ') Wander Spawned (Aggression=' .. aggression .. ')')
        -- end
    end
end

local function onVehicleResetted(id)
    -- Only During Traffic
    if gameplay_traffic.getState() ~= "on" then return end
    local veh = gameplay_traffic.getTrafficData()[id]
    if veh and veh.isAi then
        parvus_TrafficSetupAggression(id)
    end
end

-- -- on traffic action change role
-- -- extensions.hook('onTrafficAction', self.id, 'changeRole', {targetId = self.role.targetId or 0, name = roleName, prevName = prevName, data = {}})
-- local function onTrafficAction(id, name, data)
--     if name ~= 'changeRole' then return end
--     if gameplay_traffic.getState() ~= "on" then return end
--     local veh = gameplay_traffic.getTrafficData()[id]
--     if veh and veh.isAi then
--         P.setupVehData(id)
--         parvusTrafficSetupAggression(id)
--     end
-- end

local function onTrafficAction(id, name, data)
    if name ~= 'changeRole' then return end
    if gameplay_traffic.getState() ~= "on" then return end
    if not data then return end

    local veh = gameplay_traffic.getTrafficData()[id]
    if not veh or not veh.isAi then return end

    -- Vehicle guard (most reliable)
    if veh._parvusRedirectingRole then return end

    if data.name == 'standard' then
        veh._parvusRedirectingRole = true
        veh:setRole('parvus')
        veh._parvusRedirectingRole = nil
    end
end

local function onTrafficVehicleAdded(id)
    trafficIdsSorted = tableKeysSorted(gameplay_traffic.getTrafficData())
end

local function onTrafficVehicleRemoved(id)
    trafficIdsSorted = tableKeysSorted(gameplay_traffic.getTrafficData())
end

-- parvusTraffic interface
M.parvus_TrafficSetupAggression = parvus_TrafficSetupAggression

-- interface
M.onUpdate = onUpdate
M.onTrafficAction = onTrafficAction
M.onTrafficVehicleAdded = onTrafficVehicleAdded
M.onTrafficVehicleRemoved = onTrafficVehicleRemoved
M.onExtensionLoaded = onExtensionLoaded
M.onVehicleResetted = onVehicleResetted
return M

-- Aggression based traffic
local M = {}
M.dependencies = { 'gameplay_traffic' }

local logTag = 'parvus_traffic'

-- mathlib
local random = math.random
local floor = math.floor
local min = math.min
local max = math.max

-- traffic interface
local trafficAmount = gameplay_traffic.getTrafficAmount -- traffic amount
local trafficData = gameplay_traffic.getTrafficData     -- traffic table data
local trafficGetState = gameplay_traffic.getState       -- state
local trafficVars = gameplay_traffic.getTrafficVars  -- started

-- [[SWITCHBOARDS]]
local tAggresion = {}
local tToughness = {}
local tOutlaw = {}

local function parvus_traffic_resetAllBoards()
    tAggresion = { resolution = 100, skew = 2, baseAggression = 0.3, maxAggression = 2, startchance = 0.8, decay = 0.05, threshold = 2 }
    tToughness = { aggressionThreshold = 1, startchance = 0.8, decay = 0.05, threshold = 2 }
    tOutlaw = { aggressionThreshold = 1.5, startchance = 0.8, decay = 0.05, threshold = 2 }
end
parvus_traffic_resetAllBoards()

-- when extension loaded
local function onExtensionLoaded()
    log('D', logTag, "Extension Loaded")
end

-- when a vehicle is reset
local function onVehicleResetted(id)
    -- Only During Traffic
    if trafficGetState() ~= "on" then return end
    local trafficVeh = trafficData()[id]
    if trafficVeh and trafficVeh.isAi then
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

        if random() > probabilityWithinValue(trafficAmount(true), tAggresion.startchance, tAggresion.decay, tAggresion.threshold) then
            -- Vehicle Object
            local obj = getObjectByID(id)
            local res = tAggresion.resolution
            local maxr = tAggresion.maxAggression
            local minr = trafficVars().baseAggression or tAggresion.baseAggression
            local aggression = (
                ((random(0, res) / res) ^ tAggresion.skew) * (maxr - minr) + minr
            ) -- lower skew between 0.35 and 2
            log('D', logTag, '(' .. id .. ') Set Aggression: (' .. aggression .. ')')
            obj:queueLuaCommand('ai.setAggression(' .. aggression .. ')')

            local damageLimits = trafficVeh.damageLimits
            if aggression > tToughness.aggressionThreshold and damageLimits and random() > probabilityWithinValue(trafficAmount(true), tToughness.startchance, tToughness.decay, tToughness.threshold) then
                for i = 1, #damageLimits do
                    damageLimits[i] = floor(v * aggression)
                end
                log('D', logTag,'(' .. id .. ') Tougher Vehicle Spawned (DamageLimits=' .. table.concat(damageLimits, " ") .. ')')
            end

            if aggression > tOutlaw.aggressionThreshold and random() > probabilityWithinValue(trafficAmount(true), tOutlaw.startchance, tOutlaw.decay, tOutlaw.threshold) then
                -- 20% chance of outlaw if aggression is high
                obj:queueLuaCommand('ai.setSpeedMode("off")')
                log('D', logTag, '(' .. id .. ') Outlaw driver Spawned (Aggression=' .. aggression .. ')')
            end
        end
    end
end

-- parvus_traffic interface
M.parvus_traffic_resetAllBoards = parvus_traffic_resetAllBoards

-- interface
M.onExtensionLoaded = onExtensionLoaded
M.onVehicleResetted = onVehicleResetted
return M

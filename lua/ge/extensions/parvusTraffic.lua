-- Simplistic traffic variety
local M = {}
M.dependencies = { 'gameplay_traffic' }

local logTag = 'parvus_traffic'
local random = math.random
local floor = math.floor
local min = math.min
local max = math.max
local trafficAmount = gameplay_traffic.getTrafficAmount -- traffic amount
local trafficData = gameplay_traffic.getTrafficData     -- traffic table data

-- when extension loaded
local function onExtensionLoaded()
    log('D', logTag, "Extension Loaded")
end

-- when a vehicle is reset
local function onVehicleResetted(id)
    -- Only During Traffic
    if gameplay_traffic.getState() ~= "on" then return end
    local trafficVeh = trafficData()[id]
    if trafficVeh and trafficVeh.isAi then
        local obj = getObjectByID(id)

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

        if random() < probabilityWithinValue(trafficAmount(true), 0.8, 0.05, 12) then

            -- Aggression
            local baseAggression = trafficVeh.vars.baseAggression or 0.35
            local aggression = min(max(random() * random() * 1.65 + 0.35, baseAggression), 2) -- lower skew between 0.35 and 2
            log('D', logTag, '(' .. id .. ') Set Aggression: (' .. aggression .. ')')
            trafficVeh.vars.baseAggression = aggression
            obj:queueLuaCommand('ai.setAggression(' .. aggression .. ')')

            -- Tough traffic has higher damage limits
            local damageLimits = trafficVeh.damageLimits
            if damageLimits and aggression > 1 and random() < probabilityWithinValue(trafficAmount(true), 0.8, 0.1, 12) then
                for i, v in ipairs(damageLimits) do
                    damageLimits[i] = floor(v * aggression)
                end
                log('D', logTag, '('.. id ..') Tougher Vehicle Spawned (DamageLimits='.. table.concat(damageLimits, " ") ..')')
            end

            -- 
            if aggression > 1.5 and random() < probabilityWithinValue(trafficAmount(true), 0.8, 0.1, 12) then
                -- 20% chance of outlaw if aggression is high
                obj:queueLuaCommand('ai.setSpeedMode("off")')
                log('D', logTag, '(' .. id .. ') Outlaw driver Spawned (Aggression=' .. aggression .. ')')
            end
        end
    end
end

-- interface
M.onExtensionLoaded = onExtensionLoaded
M.onVehicleResetted = onVehicleResetted
return M

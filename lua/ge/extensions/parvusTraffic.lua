-- Simplistic traffic variety
local M = {}
M.dependencies = { 'gameplay_traffic' }

local logTag = 'parvus_traffic'
local random = math.random
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
        local veh = getObjectByID(id)
        local function probabilityWithinTraffic(activeOnly, startChance, decay, threshold)
            -- Get amount of active traffic vehicles
            local N = trafficAmount(activeOnly)

            local chance
            if N <= threshold then
                chance = startChance
            else
                chance = startChance / (1 + decay * (N - threshold))
            end

            return chance
        end

        -- Past 12 cars the chances of aggressive drives begin to drop
        if random() < probabilityWithinTraffic(true, 0.8, 0.05, 12) then
            local aggression = random() * random() * 1.65 + 0.35 -- lower skew between 0.35 and 2
            log('D', logTag, '(' .. id .. ') Set Aggression: (' .. aggression .. ')')
            veh:queueLuaCommand('ai.setAggression(' .. aggression .. ')')

            -- Past 12 cars the chances begin to drop
            local outlawChance = probabilityWithinTraffic(true, 0.8, 0.1, 12)
            if aggression > 1.5 and math.random() < outlawChance then
                -- 20% chance of outlaw if aggression is high
                veh:queueLuaCommand('ai.setSpeedMode("off")')
                log('D', logTag, '(' .. id .. ') Outlaw driver spawned (Aggression=' .. aggression .. ')')
            end
        end
    end
end

-- interface
M.onExtensionLoaded = onExtensionLoaded
M.onVehicleResetted = onVehicleResetted
return M

-- Aggression based traffic
local M = {}
M.dependencies = { 'gameplay_traffic' }
local P = {}

local logTag = 'parvusTraffic'

-- mathlib
local random = math.random
local floor = math.floor
local min = math.min
local max = math.max

-- traffic interface
local trafficAmount = gameplay_traffic.getTrafficAmount -- traffic amount
local traffic = gameplay_traffic.getTrafficData         -- traffic table data
local trafficGetState = gameplay_traffic.getState       -- state
local trafficVars = gameplay_traffic.getTrafficVars     -- started

-- [[DATA]]
local trafficIdsSorted = {}
local auxiliaryData = { -- additional data for traffic
    queuedVehicle = 0   -- current traffic vehicle index
}

-- [[SWITCHBOARDS]]
local tAggresion = {}
local tToughness = {}
local tOutlaw = {}

local function parvusTrafficResetAllBoards()
    tAggresion = { resolution = 2, skew = 3, baseAggression = 0.3, maxAggression = 2, startchance = 0.8, decay = 0.1, threshold = 2 }
    tToughness = { aggressionThreshold = 1, startchance = 0.8, decay = 0.1, threshold = 2 }
    tOutlaw = { aggressionThreshold = 1.5, startchance = 0.8, decay = 0.1, threshold = 2 }
end
parvusTrafficResetAllBoards()

-- when extension loaded
local function onExtensionLoaded()
    log('D', logTag, "Extension Loaded")
end

function P:checkTargetVisible(self, targetId) -- checks if the other vehicle is visible (static raycast)
    local visible = false
    local targetVeh = targetId and traffic()[targetId]
    if targetVeh then
        visible = self:checkRayCast(targetVeh.pos + vec3(0, 0, 1))
    end
    logTag('D', logTag, '(' .. targetID .. ') Is not visble to (' .. targetVeh .. ')')
    return visible
end

function P:getTrafficInfront(pos, filters) -- filters are functions to test the traffic
    filters = filters or {}
    -- If 'pos' is not provided, we use the self vehicle's position.
    local callerPos = pos or self.pos

    local bestId
    local bestDist = math.huge

    for _, targetID in ipairs(trafficIdsSorted) do
        local targetVeh = traffic()[targetID]

        local required_check =
            (be:getObjectActive(targetID)) and
            -- (P.checkTargetVisible(self, targetID)) and
            (self.dirVec:dot(targetVeh.pos - self.pos) > 0)

        if not required_check then
            goto continue_loop -- Skip vehicles that are behind or inactive
        end

        local passed_custom_filters = true

        -- The filters table is expected to contain functions { [1] = func1, [2] = func2, ...}
        for _, filter_func in ipairs(filters) do
            if not filter_func(targetVeh) then
                passed_custom_filters = false
                break
            end
        end

        if passed_custom_filters then
            local otherPos = targetVeh.pos
            local dist = callerPos:squaredDistance(otherPos)

            if dist < bestDist then
                bestId = targetID
                bestDist = dist
            end
        end

        ::continue_loop::
    end

    return bestId, math.sqrt(bestDist) -- Return the final ID and the actual distance
end

-- when horn electronic is true
function P:parvusTrafficHonkHorn()
    log('D', logTag, '(' .. self.id .. ') Vehicle is honking')
    local targetId, dist = P.getTrafficInfront(self, self.pos)
    if not targetId then return end
    log('D', logTag, 'Target: (' .. targetId .. ') Distance: (' .. dist .. ')')
end

-- begins tracking vehicle
function P:parvusTrafficTracking()
    local objMap = map and map.objects[self.id]
    if not objMap or not objMap.states then return end

    -- honkState
    local horn = objMap.states.horn and true or false
    if horn then P.parvusTrafficHonkHorn(self) end
end

-- updates every frame
local function onUpdate(dt, dtSim)
    -- Only During Traffic
    if trafficGetState() ~= "on" then return end
    local vehCount = 0
    for i, id in ipairs(trafficIdsSorted) do -- ensures consistent order of vehicles
        vehCount = vehCount + 1
        local veh = traffic()[id]
        if veh then
            if be:getObjectActive(id) then
                if i == auxiliaryData.queuedVehicle then -- checks one vehicle per frame, as an optimization
                    P.parvusTrafficTracking(veh)
                end
            end
        end
    end

    auxiliaryData.queuedVehicle = auxiliaryData.queuedVehicle + 1
    if auxiliaryData.queuedVehicle > vehCount then
        auxiliaryData.queuedVehicle = 1
    end
end

-- when a vehicle is reset
local function onVehicleResetted(id)
    -- Only During Traffic
    if trafficGetState() ~= "on" then return end
    local trafficVeh = traffic()[id]
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

            -- Aggression
            local res = 10 ^ tAggresion.resolution -- [0,1,2,3,4,5,6] allowed resolutions
            local maxr = tAggresion.maxAggression
            local minr = trafficVars().baseAggression or tAggresion.baseAggression
            local aggression = (
                ((random(0, res) / res) ^ tAggresion.skew) * (maxr - minr) + minr
            ) -- lower skew between 0.35 and 2
            log('D', logTag, '(' .. id .. ') Set Aggression: (' .. aggression .. ')')
            obj:queueLuaCommand('ai.setAggression(' .. aggression .. ')')

            -- Tougher Driver
            local damageLimits = trafficVeh.damageLimits
            if aggression > tToughness.aggressionThreshold and damageLimits and random() > probabilityWithinValue(trafficAmount(true), tToughness.startchance, tToughness.decay, tToughness.threshold) then
                log('D', logTag, '(' .. id .. ') Tougher Driver Spawned (Aggression=' .. aggression .. ')')
                for i = 1, #damageLimits do
                    damageLimits[i] = floor(damageLimits[i] * min(1, aggression))
                end
                log('D', logTag, 'Damage Limits: (' .. dumps(damageLimits) .. ')')
            end

            -- Outlaws
            if aggression > tOutlaw.aggressionThreshold and random() > probabilityWithinValue(trafficAmount(true), tOutlaw.startchance, tOutlaw.decay, tOutlaw.threshold) then
                obj:queueLuaCommand('ai.setSpeedMode("off")')
                log('D', logTag, '(' .. id .. ') Outlaw Spawned (Aggression=' .. aggression .. ')')
            end
        end
    end
end

local function onTrafficVehicleAdded(id)
    trafficIdsSorted = tableKeysSorted(traffic())
end

local function onTrafficVehicleRemoved(id)
    trafficIdsSorted = tableKeysSorted(traffic())
end

-- parvusTraffic interface
M.parvusTrafficResetAllBoards = parvusTrafficResetAllBoards

-- interface
M.onUpdate = onUpdate
M.onTrafficVehicleAdded = onTrafficVehicleAdded
M.onTrafficVehicleRemoved = onTrafficVehicleRemoved
M.onExtensionLoaded = onExtensionLoaded
M.onVehicleResetted = onVehicleResetted
return M

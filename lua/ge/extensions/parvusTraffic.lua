-- Aggression based traffic
local M = {}
local P = {}
M.dependencies = { 'gameplay_traffic' }

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
local auxiliaryData = {}

-- [[SWITCHBOARDS]]
local tAggresion = {}
local tToughness = {}
local tOutlaw = {}
local tReckless = {}

local auxiliaryData = {      -- additional data for traffic
    queuedVehicle = 0,       -- current traffic vehicle index
    queuedHonkedVehicle = 0, -- current vehicle that's been honked at tracker
    lastHornState = {},

    queuedInteraction = 0,   -- index for staggering the honkedInteractions list
    honkedInteractions = {}, -- { {callerID, targetID}, {callerID, targetID}, ... }
    vehData = {},            -- { 'targetID' = {obstructionCooldown = 0, obstructions = {{callerID, targetID}}}}
}

local function parvusTrafficResetAllBoards()
    tAggresion = { resolution = 2, skew = 3, baseAggression = 0.3, maxAggression = 2, startchance = 0.8, decay = 0.1, threshold = 2 }
    tToughness = { aggressionThreshold = 1, startchance = 0.8, decay = 0.1, threshold = 2 }
    tOutlaw = { aggressionThreshold = 1.5, startchance = 0.8, decay = 0.1, threshold = 2 }
    tReckless = { aggressionThreshold = 1.9, startchance = 0.5, decay = 0.1, threshold = 2 }
end
parvusTrafficResetAllBoards()

-- when extension loaded
local function onExtensionLoaded()
    log('D', logTag, "Extension Loaded")
end

function P.checkTargetVisible(id, targetId) -- checks if the other vehicle is visible (static raycast)
    local veh = traffic()[id]
    local visible = false
    local targetVeh = targetId and traffic()[targetId]
    if targetVeh then
        visible = veh:checkRayCast(targetVeh.pos + vec3(0, 0, 1))
    end
    log('D', logTag, '(' .. targetId .. ') Is not visble to (' .. id .. ')')
    return visible
end

function P.getTrafficInfront(id, pos, distance, filters) -- filters are functions to test the traffic
    local veh = traffic()[id]
    filters = filters or {}
    -- If 'pos' is not provided, we use the vehicle's position.
    local callerPos = pos or veh.pos

    local bestId
    local bestDist = math.huge
    -- convert the meter distance to systematic units
    local maxDistLimitSq = distance and (distance * distance) or math.huge

    for _, targetID in ipairs(trafficIdsSorted) do
        local targetVeh = traffic()[targetID]

        local distSq = callerPos:squaredDistance(targetVeh.pos)

        if distSq > maxDistLimitSq then
            goto continue_loop
        end

        local required_check =
            (be:getObjectActive(targetID)) and
            (P.checkTargetVisible(id, targetID)) and
            (veh.dirVec:dot(targetVeh.pos - veh.pos) > 0)

        if not required_check then
            goto continue_loop -- Skip vehicles that are behind or invisible
        end

        local passed_custom_filters = true
        -- The filters table is expected to contain functions { [1] = func1, [2] = func2, ...}
        for _, filter_func in ipairs(filters) do
            if not filter_func(targetVeh) or targetVeh.filter_func then
                passed_custom_filters = false
                break
            end
        end

        if passed_custom_filters then
            if distSq < bestDist then
                bestId = targetID
                bestDist = distSq
            end
        end

        ::continue_loop::
    end

    return bestId, math.sqrt(bestDist) -- Return the final ID and the actual distance
end

-- when horn electronic is true
function P.parvusTrafficHonkHorn(id)
    local veh = traffic()[id]
    log('D', logTag, '(' .. id .. ') Vehicle is honking')

    -- Get the current speed (in m/s)
    local speed = veh.speed or 0

    -- dynamic honking distance (D = min(max(V * 2, 10), 50))
    local dynaDist = math.min(math.max(speed * 2, 30), 60)
    local targetId, dist = P.getTrafficInfront(id, veh.pos, dynaDist)

    if not targetId then return end
    log('D', logTag, 'Target: (' .. targetId .. ') Distance: (' .. dist .. ') HonkDistance: (' .. dynaDist .. ')')

    table.insert(auxiliaryData.honkedInteractions, { id, targetId })
end

-- begins tracking vehicle
function P.parvusTrafficTracking(id)
    if not auxiliaryData.vehData[id] then auxiliaryData.vehData[id] = {} end
    local vehData = auxiliaryData.vehData[id]
    if not vehData.obstructionCooldown then vehData.obstructionCooldown = 0 end
    if not vehData.obstructions then vehData.obstructions = {} end
    if not vehData.lastObstuctionPos then
        vec3()
        vehData.lastObstuctionPos = traffic()[id].pos
    end

    local objMap = map and map.objects[id]
    if not objMap or not objMap.states then return end

    local currentHorn = objMap.states.horn and true or false

    local prevHorn = auxiliaryData.lastHornState[id] or false

    -- horn just turned on
    if currentHorn and not prevHorn then
        P.parvusTrafficHonkHorn(id)
    end

    -- the current state for the next check
    auxiliaryData.lastHornState[id] = currentHorn
    if vehData.obstructionCooldown > 0 then vehData.obstructionCooldown = vehData.obstructionCooldown - 1 end
end

function P.processHonkedAtVehicles(callerID, targetID)
    local targetVeh = traffic()[targetID]
    if targetVeh then
        local vehData = auxiliaryData.vehData[targetID]
        local function modifyCooldown(v, add)
            if not v then return end
            v.obstructionCooldown = v.obstructionCooldown + (add or 0)
        end
        if vehData and vehData.obstructionCooldown > 0 then return end
        modifyCooldown(vehData, 10) -- cooldown

        log('D', logTag, 'Honk Process: Caller (' .. callerID .. ')  Target:  (' .. targetID .. ')')

        if not targetVeh.isAi then
            log('D', logTag, '(' .. targetID .. ') Not AI')
            return
        end

        -- Get the current speed (in m/s)
        local speed = targetVeh.speed or 0

        if targetVeh and speed > 3 then
            log('D', logTag, '(' .. targetID .. ') Is Moving (' .. speed .. ')')
            return
        end

        -- honk incase a vehicle is infront of this one
        targetVeh.queuedFuncs.parvusTrafficHonk = {
            timer = min(1, square(random())),
            func = function()
                if targetVeh then targetVeh:honkHorn(max(0.25, square(random()))) end
            end,
            args = {}
        }

        -- reset obstructions when vehicle moves
        if targetVeh.pos:squaredDistance(vehData.lastObstuctionPos) > square(5) then
            log('D', logTag, '(' .. targetID .. ') Target Moved, clearing obstructions')
            table.clear(vehData.obstructions)
            -- update position
            vehData.lastObstuctionPos = targetVeh.pos
        end

        table.insert(vehData.obstructions, { callerID, targetID })
        local strikes = #vehData.obstructions


        if strikes > 2 then
            targetVeh.queuedFuncs.parvusTrafficRemoveStuck = {
                timer = 10.00,
                func = function(id, lastPos, distance)
                    local veh = traffic()[id]
                    if veh and veh.speed < 2 and veh.pos:squaredDistance(lastPos) < distance then
                        veh:modifyRespawnValues(-10)
                        if veh.respawn.activeRadius > 80 then
                            log('D', logTag, '(' .. id .. ') Vehicle is still active')
                            return
                        end
                        veh:fade(5, true)
                        log('D', logTag, '(' .. id .. ') Vehicle is still obstructing')
                        return
                    end
                    log('D', logTag, '(' .. id .. ') Vehicle is no longer obstructing')
                end,
                args = { targetID, targetVeh.pos, 1 }
            }
            log('D', logTag, '(' .. targetID .. ') Obstruction Clear Queued')
            return
        end

        if strikes > 1 then
            -- honk incase a vehicle is infront of this one
            targetVeh.queuedFuncs.parvusTrafficHonkBeforeRandom = {
                timer = min(1, square(random()) * 1.5),
                func = function()
                    if targetVeh then targetVeh:honkHorn(max(0.25, square(random()))) end
                end,
                args = {}
            }

            targetVeh.queuedFuncs.parvusTrafficSetAIRandom = {
                timer = 0.25,
                vLua = string.format('ai.setMode("random")') -- this is called to allow AI to make drastic efforts to get through
            }
            log('D', logTag, '(' .. targetID .. ') Queued AI to Random')

            targetVeh.queuedFuncs.parvusTrafficSetAITraffic = {
                timer = max(2.25, square(random()) * strikes),
                vLua = string.format('ai.setMode("traffic")')
            }
            log('D', logTag, '(' .. targetID .. ') Queued AI to Traffic')
            return
        elseif strikes > 0 then
            targetVeh.queuedFuncs.parvusTrafficResetAI = {
                timer = 0.25,
                vLua = string.format('ai.reset()'), -- this is called to reset the AI plan
            }
            log('D', logTag, '(' .. targetID .. ') Queued AI Rest')
            return
        end
    end
end

-- updates every frame
local function onUpdate(dt, dtSim)
    -- Only During Traffic
    if trafficGetState() ~= "on" then return end
    if trafficGetState() ~= "on" then return end
    local vehCount = 0
    for i, id in ipairs(trafficIdsSorted) do -- ensures consistent order of vehicles
        vehCount = vehCount + 1
        local veh = traffic()[id]
        if veh then
            if be:getObjectActive(id) then
                if i == auxiliaryData.queuedVehicle then -- checks one vehicle per frame, as an optimization
                    P.parvusTrafficTracking(id)
                end
            end
        end
    end

    auxiliaryData.queuedVehicle = auxiliaryData.queuedVehicle + 1
    if auxiliaryData.queuedVehicle > vehCount then
        auxiliaryData.queuedVehicle = 1
    end

    local interactionCount = 0
    for i, interaction in ipairs(auxiliaryData.honkedInteractions) do
        interactionCount = interactionCount + 1
        if interaction then
            local callerID = interaction[1]
            local targetID = interaction[2]

            P.processHonkedAtVehicles(callerID, targetID)
            table.remove(auxiliaryData.honkedInteractions, i)
        end
    end
end


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

local function parvusTrafficSetupAggression(id)
    local targetVeh = traffic()[id]

    if random() > probabilityWithinValue(trafficAmount(true), tAggresion.startchance, tAggresion.decay, tAggresion.threshold) then
        -- Aggression
        local res = 10 ^ tAggresion.resolution -- [0,1,2,3,4,5,6] allowed resolutions
        local maxr = tAggresion.maxAggression
        local minr = trafficVars().baseAggression or tAggresion.baseAggression
        local aggression = (
            ((random(0, res) / res) ^ tAggresion.skew) * (maxr - minr) + minr
        ) -- lower skew between 0.35 and 2

        local function roleSetAggression(c, a)
            if random() > probabilityWithinValue(trafficAmount(true), tAggresion.startchance, tAggresion.decay, tAggresion.threshold) then
                local veh = traffic()[id]
                c = c or 0
                if c > 1 then return end
                if veh and veh.role then
                    veh.role.driver.aggression = aggression
                    log('D', logTag, '(' .. id .. ') Set Role Aggression: (' .. a .. ')')
                    return
                end
                log('D', logTag, '(' .. id .. ') Failed to set aggression: (' .. a .. ')')
            end
        end

        -- self.queuedFuncs = {}  keys: timer, func, args, vLua (vLua string overrides func and args)
        roleSetAggression(0, aggression)
        targetVeh.queuedFuncs.parvusTrafficSetAggression = {
            timer = 0.25,
            vLua = 'ai.setAggression(' .. aggression .. ')'
        }
        log('D', logTag, '(' .. id .. ') Queued Aggression: (' .. aggression .. ')')


        -- Tougher Driver
        local damageLimits = targetVeh.damageLimits
        if aggression > tToughness.aggressionThreshold and damageLimits and random() > probabilityWithinValue(trafficAmount(true), tToughness.startchance, tToughness.decay, tToughness.threshold) then
            log('D', logTag, '(' .. id .. ') Tougher Driver Spawned (Aggression=' .. aggression .. ')')
            for i, v in ipairs(damageLimits) do
                targetVeh.damageLimits[i] = floor(max(v, v * aggression))
            end
            log('D', logTag, 'Damage Limits: (' .. dumps(targetVeh.damageLimits) .. ')')
        end

        -- Outlaws
        if aggression > tOutlaw.aggressionThreshold and random() > probabilityWithinValue(trafficAmount(true), tOutlaw.startchance, tOutlaw.decay, tOutlaw.threshold) then
            targetVeh.queuedFuncs.parvusTrafficsetSpeedMode = {
                timer = 0.25,
                vLua = string.format('ai.setSpeedMode("off")'),
            }
            log('D', logTag, '(' .. id .. ') Outlaw Spawned (Aggression=' .. aggression .. ')')

            -- Reckless Outlaw
            if aggression > tReckless.aggressionThreshold and random() > probabilityWithinValue(trafficAmount(true), tReckless.startchance, tReckless.decay, tReckless.threshold) then
                targetVeh.queuedFuncs.parvusTrafficSetAIRandom = {
                    timer = 2.25,
                    vLua = string.format('ai.setMode("random")')
                }
                log('D', logTag, '(' .. id .. ') Reckless Outlaw Spawned (Aggression=' .. aggression .. ')')
            end
        end
    end
end

-- when a vehicle is reset
local function onVehicleResetted(id)
    -- Only During Traffic
    if trafficGetState() ~= "on" then return end
    local targetVeh = traffic()[id]
    if targetVeh and targetVeh.isAi then
        parvusTrafficSetupAggression(id)
    end
end

local function onTrafficVehicleAdded(id)
    trafficIdsSorted = tableKeysSorted(traffic())
end

local function onTrafficVehicleRemoved(id)
    trafficIdsSorted = tableKeysSorted(traffic())
    parvusTrafficResetAllBoards()
end

-- parvusTraffic interface
M.parvusTrafficResetAllBoards = parvusTrafficResetAllBoards
M.parvusTrafficSetupAggression = parvusTrafficSetupAggression

-- interface
M.onUpdate = onUpdate
M.onTrafficVehicleAdded = onTrafficVehicleAdded
M.onTrafficVehicleRemoved = onTrafficVehicleRemoved
M.onExtensionLoaded = onExtensionLoaded
M.onVehicleResetted = onVehicleResetted
return M

-- Traffic with aggression based actions
-- Includes cleanup for crashes
-- Made By Parvus
local M, P = {}, {}
M.dependencies = { 'gameplay_traffic' }

local logTag = 'parvusTraffic'

-- mathlib
local random = math.random
local floor = math.floor
local min = math.min
local max = math.max

-- [[DATA]]
local trafficIdsSorted = {}
local parvusAuxData = { -- additional data for traffic
    queuedVehicle = 0,  -- current traffic vehicle index
    vehDataTable = {},  -- { 'vehID' = {actionCooldown = 0, lastHornState = false}}
    minMovingSpeed = 4, -- The minimum speed a vehicle has to be going above to be considered moving

    -- deadlock happens when no vehicles are available to honk to clear obstructions
    -- ai.lua dictates that traffic vehicles only honk once when 'forced to stop' and otherwise will wait indefinitely
    -- this creates a 'deadlock' when no vehicle feels 'forced to stop' and the only one left to fix this is the player
    deadlockTimer = 0
}

-- [[SWITCHBOARDS]]
local tAggresion = { resolution = 2, skew = 3, baseAggression = 0.3, maxAggression = 2, startchance = 0.9, decay = 0.1, threshold = 2 }
local tToughness = { aggressionThreshold = 1, startchance = 0.9, decay = 0.1, threshold = 2 }
local tOutlaw = { aggressionThreshold = 1.5, startchance = 0.9, decay = 0.1, threshold = 2 }
local tReckless = { aggressionThreshold = 1.9, startchance = 0.9, decay = 0.1, threshold = 2 }

-- when extension loaded
local function onExtensionLoaded()
    log('D', logTag, "Extension Loaded")
end

-- returns role, driver, and personality or nil for each
function P.getDriverPersonality(id)
    local veh = gameplay_traffic.getTrafficData()[id]
    local role, driver, personality;
    if veh then
        role = veh.role
        if role then
            driver = role.driver
            if driver then
                personality = driver.personality
            end
        end
    end
    return role, driver, personality
end

function P.checkTargetVisible(id, targetId) -- checks if the other vehicle is visible (static raycast)
    local veh = gameplay_traffic.getTrafficData()[id]
    local visible = false
    local targetVeh = targetId and gameplay_traffic.getTrafficData()[targetId]
    if targetVeh then
        visible = veh:checkRayCast(targetVeh.pos + vec3(0, 0, 1))
    end
    return visible
end

function P.getTrafficInfront(id, pos, distance, Aionly) -- filters are functions to test the traffic
    local veh = gameplay_traffic.getTrafficData()[id]
    -- If 'pos' is not provided, we use the vehicle's position.
    local callerPos = pos or veh.pos

    local bestId
    local bestDist = math.huge
    -- convert the meter distance to systematic units
    local maxDistLimitSq = distance and (distance * distance) or math.huge

    for _, ctID in ipairs(trafficIdsSorted) do
        local ctVeh = gameplay_traffic.getTrafficData()[ctID]

        local distSq = callerPos:squaredDistance(ctVeh.pos)

        if distSq < maxDistLimitSq then
            if -- required checks
                (not Aionly or ctVeh.isAi)
                ---@diagnostic disable-next-line: undefined-field
                and (be:getObjectActive(ctID))
                and (P.checkTargetVisible(id, ctID))
                and (veh.dirVec:dot(ctVeh.pos - veh.pos) > 0)
            then
                if distSq < bestDist then
                    bestId = ctID
                    bestDist = distSq
                end
            end
        end
    end

    return bestId, math.sqrt(bestDist) -- Return the final ID and the actual distance
end

-- when horn electronic is true
function P.hornActive(callerID)
    local veh = gameplay_traffic.getTrafficData()[callerID]
    log('D', logTag, '(' .. callerID .. ') Vehicle is honking')

    -- Get the current speed (in m/s)
    local targetID, dist = P.getTrafficInfront(callerID, veh.pos, 60, true)

    if not targetID then return end
    log('D', logTag, 'Target: (' .. targetID .. ') Distance: (' .. dist .. ')')

    local targetVeh = gameplay_traffic.getTrafficData()[targetID]
    if not targetVeh then return end
    local vehData = P.getVehData(targetID)

    -- a cooldown on how often a vehicle's honks will cause actions
    if (vehData.actionCooldown or 0) > 0 then return end
    vehData.actionCooldown = (vehData.actionCooldown or 0) + 10

    log('D', logTag, 'Honk Process: Caller (' .. callerID .. ')  Target:  (' .. targetID .. ')')

    if not targetVeh.isAi then
        log('D', logTag, '(' .. targetID .. ') Not Ai')
        return
    end

    local speed = targetVeh.speed
    if targetVeh and speed > parvusAuxData.minMovingSpeed then
        log('D', logTag, '(' .. targetID .. ') Is NOT Obstructing: MOVING (' .. speed .. ')')
        return
    end

    targetVeh:honkHorn(max(0.25, square(random()))) -- feedback

    local honkeeObj = getObjectByID(targetID)
    if not honkeeObj then return end
    honkeeObj:queueLuaCommand('ai.reset()')
    log('D', logTag, '(' .. targetID .. ') Queued Ai Reset')

    P.queueObstructionClear(callerID, targetID)
end

function P.getVehData(id)
    local v = parvusAuxData.vehDataTable[id]
    if v then
        return v
    else
        return P.setupVehData(id)
    end
end

function P.setupVehData(id)
    local newtable = {}
    parvusAuxData.vehDataTable[id] = newtable
    return newtable
end

function P.queueObstructionClear(callerID, targetID)
    local targetVeh = gameplay_traffic.getTrafficData()[targetID]
    if targetVeh.queuedFuncs.parvusTrafficRemoveStuck then return end
    targetVeh.queuedFuncs.parvusTrafficRemoveStuck = {
        timer = 60.00,
        args = { callerID, targetID, targetVeh.pos, 3 },
        func = function(cid, tid, lp, dst)
            local tv = gameplay_traffic.getTrafficData()[tid]
            local cv = gameplay_traffic.getTrafficData()[cid]
            if tv and tv.isAi then tv:honkHorn(max(0.25, square(random()))) end
            if cv and cv.isAi then cv:honkHorn(max(0.25, square(random()))) end
            if not tv then return end
            if tv.speed <= 1 and tv.pos:squaredDistance(lp) < dst then
                tv:modifyRespawnValues(-10)
                if tv.respawn.activeRadius > 80 then
                    log('D', logTag, '(' .. tv.id .. ') Vehicle is still active')
                    return
                end
                tv:fade(5, true)
                log('D', logTag, '(' .. tv.id .. ') Vehicle is still obstructing')
                return
            end
            log('D', logTag, '(' .. tv.id .. ') Vehicle is no longer obstructing')
        end
    }
    log('D', logTag, '(' .. targetID .. ') Obstruction Clear Queued')
end

function P.checkVehicle(id)
    local vehData = P.getVehData(id)
    if (vehData.actionCooldown or 0) > 0 then vehData.actionCooldown = (vehData.actionCooldown or 0) - 1 end

    local tv = gameplay_traffic.getTrafficData()[id]
    if tv and tv.isAi then
        local deadlockTimer = parvusAuxData.deadlockTimer
        if (deadlockTimer or 0) > 60 then
            -- there is a deadlock
            log('D', logTag, '(' .. id .. ') Deadlock is active')
            local _, _, personality = P.getDriverPersonality(id)
            if
                personality and
                random() > (personality.patience + random())                      -- patience drivers are harder to make honk
            then
                tv:honkHorn(max(0.25, square(random()) + personality.aggression)) -- aggresive drivers honk longer
                log('D', logTag, '(' .. id .. ') Was made to honk to clear a deadlock ')
                parvusAuxData.deadlockTimer = 0
            end
        end
    end

    local objMap = map and map.objects[id]
    if not objMap or not objMap.states then return end

    local currentHorn = objMap.states.horn and true or false

    local prevHorn = vehData.lastHornState or false

    -- horn just turned on
    if currentHorn and not prevHorn then
        P.hornActive(id)
    end

    -- the current state for the next check
    vehData.lastHornState = currentHorn
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
                    P.checkVehicle(id)
                end
            end
        end
    end

    parvusAuxData.queuedVehicle = parvusAuxData.queuedVehicle + 1
    if parvusAuxData.queuedVehicle > vehCount then
        parvusAuxData.queuedVehicle = 1
    end

    if stoppedAiVehCount < vehCountAi then
        -- decrease deadlockTimer
        if (parvusAuxData.deadlockTimer or 0) > 0 then
            parvusAuxData.deadlockTimer = max(0, parvusAuxData.deadlockTimer or 0) - dtSim
        end
    else
        -- indecrease deadlockTimer
        parvusAuxData.deadlockTimer = (parvusAuxData.deadlockTimer or 0) + dtSim
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


        -- Outlaws
        if aggression > tOutlaw.aggressionThreshold and random() < probabilityWithinValue(gameplay_traffic.getTrafficAmount(true), tOutlaw.startchance, tOutlaw.decay, tOutlaw.threshold) then
            toughenDriver(aggression, 4000)
            targetVeh.queuedFuncs.parvusTrafficSetSpeedMode = {
                timer = 2,
                vLua = 'ai.setSpeedMode("off")'
            }
            log('D', logTag, '(' .. id .. ') Outlaw Spawned (Aggression=' .. aggression .. ')')

            -- Reckless Outlaw
            if aggression > tReckless.aggressionThreshold and random() < probabilityWithinValue(gameplay_traffic.getTrafficAmount(true), tReckless.startchance, tReckless.decay, tReckless.threshold) then
                toughenDriver(aggression, 6000)
                targetVeh.queuedFuncs.parvusTrafficSetReckless = {
                    timer = 2,
                    vLua = 'ai.setMode("random")'
                }
                log('D', logTag, '(' .. id .. ') Reckless Outlaw Spawned (Aggression=' .. aggression .. ')')
            end
        end
    end
end

local function onVehicleResetted(id)
    -- Only During Traffic
    if gameplay_traffic.getState() ~= "on" then return end
    local veh = gameplay_traffic.getTrafficData()[id]
    if veh and veh.isAi then
        P.setupVehData(id)
        parvusTrafficSetupAggression(id)
    end
end

-- on traffic action change role
-- extensions.hook('onTrafficAction', self.id, 'changeRole', {targetId = self.role.targetId or 0, name = roleName, prevName = prevName, data = {}})
local function onTrafficAction(id, name, data)
    if name ~= 'changeRole' then return end
    if gameplay_traffic.getState() ~= "on" then return end
    local veh = gameplay_traffic.getTrafficData()[id]
    if veh and veh.isAi then
        P.setupVehData(id)
        parvusTrafficSetupAggression(id)
    end
end

local function onTrafficVehicleAdded(id)
    trafficIdsSorted = tableKeysSorted(gameplay_traffic.getTrafficData())
end

local function onTrafficVehicleRemoved(id)
    trafficIdsSorted = tableKeysSorted(gameplay_traffic.getTrafficData())
    parvusAuxData.vehDataTable[id] = nil
end

-- parvusTraffic interface
M.parvusTrafficSetupAggression = parvusTrafficSetupAggression

-- interface
M.onUpdate = onUpdate
M.onTrafficAction = onTrafficAction
M.onTrafficVehicleAdded = onTrafficVehicleAdded
M.onTrafficVehicleRemoved = onTrafficVehicleRemoved
M.onExtensionLoaded = onExtensionLoaded
M.onVehicleResetted = onVehicleResetted
return M

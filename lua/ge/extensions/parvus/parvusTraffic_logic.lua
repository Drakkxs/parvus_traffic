-- lua\ge\extensions\parvus\parvusTraffic_logic.lua
local L = {}

-- mathlib locals (same as before)
local random = math.random
local floor = math.floor
local min = math.min
local max = math.max

local state = require('ge/extensions/parvus/parvusTraffic_state')

-- helper: probability curve
local function probabilityWithinValue(value, startChance, decay, threshold)
    local N = value
    if N <= threshold then return startChance end
    return startChance / (1 + decay * (N - threshold))
end

function L.getDriverPersonality(id)
    local veh = gameplay_traffic.getTrafficData()[id]
    local role, driver, personality
    if veh and veh.role and veh.role.driver then
        role = veh.role
        driver = role.driver
        personality = driver.personality
    end
    return role, driver, personality
end

function L.checkTargetVisible(id, targetId)
    local veh = gameplay_traffic.getTrafficData()[id]
    local targetVeh = targetId and gameplay_traffic.getTrafficData()[targetId]
    if veh and targetVeh then
        return veh:checkRayCast(targetVeh.pos + vec3(0, 0, 1))
    end
    return false
end

function L.getTrafficInfront(id, pos, distance, Aionly, trafficIdsSorted)
    local veh = gameplay_traffic.getTrafficData()[id]
    if not veh then return nil, math.huge end

    local callerPos = pos or veh.pos
    local bestId, bestDistSq
    local maxDistSq = distance and (distance * distance) or math.huge

    for _, ctID in ipairs(trafficIdsSorted) do
        local ctVeh = gameplay_traffic.getTrafficData()[ctID]
        local distSq = callerPos:squaredDistance(ctVeh.pos)
        if distSq < maxDistSq then
            -- cheap “in front” test before raycast
            if veh and ctVeh and veh.dirVec:dot(ctVeh.pos - callerPos) > 0 then
                ---@diagnostic disable-next-line: undefined-field
                if be:getObjectActive(ctID) then
                    if (not bestDistSq) or distSq < bestDistSq then
                        -- expensive raycast last
                        if L.checkTargetVisible(id, ctID) then
                            bestId = ctID
                            bestDistSq = distSq
                        end
                    end
                end
            end
        end
    end

    return bestId, bestDistSq and math.sqrt(bestDistSq) or math.huge
end

function L.getVehData(aux, id)
    local v = aux.vehDataTable[id]
    if v then return v end
    local t = {}
    aux.vehDataTable[id] = t
    return t
end

function L.queueObstructionClear(logTag, callerID, targetID)
    local targetVeh = gameplay_traffic.getTrafficData()[targetID]
    if targetVeh and targetVeh.queuedFuncs then
        if targetVeh.queuedFuncs.parvusTrafficRemoveStuck then return end

        targetVeh.queuedFuncs.parvusTrafficRemoveStuck = {
            timer = 10,
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
end

function L.hornActive(callerID)
    local logTag = state.logTag
    local aux = state.aux

    local veh = gameplay_traffic.getTrafficData()[callerID]
    if not veh then return end
    log('D', logTag, '(' .. callerID .. ') Vehicle is honking')

    local targetID, dist = L.getTrafficInfront(callerID, veh.pos, 60, true, state.trafficIdsSorted)
    if not targetID then return end

    log('D', logTag, 'Target: (' .. targetID .. ') Distance: (' .. dist .. ')')

    local targetVeh = gameplay_traffic.getTrafficData()[targetID]
    if not targetVeh then return end

    local vehData = L.getVehData(aux, targetID)
    if (vehData.actionCooldown or 0) > 0 then return end
    vehData.actionCooldown = (vehData.actionCooldown or 0) + 10

    if not targetVeh.isAi then
        log('D', logTag, '(' .. targetID .. ') Not Ai')
        return
    end

    if targetVeh.speed > aux.minMovingSpeed then
        log('D', logTag, '(' .. targetID .. ') Is NOT Obstructing: MOVING (' .. targetVeh.speed .. ')')
        return
    end

    targetVeh:honkHorn(max(0.25, square(random())))

    local honkeeObj = getObjectByID(targetID)
    if not honkeeObj then return end
    honkeeObj:queueLuaCommand('ai.reset()')
    log('D', logTag, '(' .. targetID .. ') Queued Ai reset')

    L.queueObstructionClear(logTag, callerID, targetID)
end

function L.checkVehicle(id)
    local aux = state.aux
    local logTag = state.logTag

    local vehData = L.getVehData(aux, id)
    if (vehData.actionCooldown or 0) > 0 then vehData.actionCooldown = (vehData.actionCooldown or 0) - 1 end

    local tv = gameplay_traffic.getTrafficData()[id]
    if not tv then return end
    if tv.isAi then
        if (aux.deadlockTimer or 0) > 5 then
            local _, _, personality = L.getDriverPersonality(id)
            if personality and random() > (personality.patience + random()) then
                tv:honkHorn(max(0.25, square(random()) + personality.aggression))
                log('D', logTag, '(' .. id .. ') Was made to honk to clear a deadlock ')
            end
            aux.deadlockTimer = 0
        end
    end

    local objMap = map and map.objects[id]
    if not objMap or not objMap.states then return end

    local currentHorn = objMap.states.horn and true or false
    local prevHorn = vehData.lastHornState or false

    if currentHorn and not prevHorn then
        L.hornActive(id)
    end

    vehData.lastHornState = currentHorn
end

function L.setupAggression(id)
    local logTag = state.logTag
    local aux = state.aux
    local tAggresion = state.tAggresion
    local tToughness = state.tToughness

    local targetVeh = gameplay_traffic.getTrafficData()[id]
    if not targetVeh then return end

    if random() >= probabilityWithinValue(gameplay_traffic.getTrafficAmount(true), tAggresion.startchance, tAggresion.decay, tAggresion.threshold) then
        return
    end

    local res = 10 ^ tAggresion.resolution
    local maxr = tAggresion.maxAggression
    local minr = gameplay_traffic.getTrafficVars().baseAggression or tAggresion.baseAggression
    local aggression = (((random(0, res) / res) ^ tAggresion.skew) * (maxr - minr) + minr)

    local role, driver, personality = L.getDriverPersonality(id)
    if role and driver and personality then
        local minBound, maxBound = 0.1, 1
        personality.aggression   = max(min(aggression, maxBound), minBound)
        personality.patience     = max(min(0.5 / aggression, maxBound), minBound)
        personality.bravery      = max(min(0.5 * aggression, maxBound), minBound)
        driver.personality       = personality
        log('D', logTag, '(' .. id .. ') Set Personality (' .. dumps(driver.personality) .. ')')
    end

    local obj = getObjectByID(id)
    if obj then
        obj:queueLuaCommand('ai.setAggression(' .. aggression .. ')')
        log('D', logTag, '(' .. id .. ') Queued Aggression: (' .. aggression .. ')')
    end

    local damageLimits = { 50, 1000, 30000 }
    local function toughenDriver(agr, mod)
        for i, v in ipairs(damageLimits) do
            targetVeh.damageLimits[i] = floor(max(v, (v * agr) + (mod or 0)))
        end
        log('D', logTag, 'Damage Limits: (' .. dumps(targetVeh.damageLimits) .. ')')
        log('D', logTag, '(' .. id .. ') Tougher Driver Spawned (Aggression=' .. aggression .. ')')
    end

    if aggression > tToughness.aggressionThreshold
        and random() < probabilityWithinValue(gameplay_traffic.getTrafficAmount(true), tToughness.startchance, tToughness.decay, tToughness.threshold)
    then
        toughenDriver(aggression)
    end
end

return L

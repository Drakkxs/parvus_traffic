-- lua/ge/extensions/parvus/traffic/parvusUtils.lua
local C = {}

-- returns role, driver, and personality or nil for each
function C:getDriverPersonality(id)
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

function C:checkTargetVisible(id, targetId) -- checks if the other vehicle is visible (static raycast)
    local veh = gameplay_traffic.getTrafficData()[id]
    local visible = false
    local targetVeh = targetId and gameplay_traffic.getTrafficData()[targetId]
    if targetVeh then
        visible = veh:checkRayCast(targetVeh.pos + vec3(0, 0, 1))
    end
    return visible
end

function C:getTrafficInfront(id, pos, distance, Aionly, trafficIdsSorted) -- filters are functions to test the traffic
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
                and (self.checkTargetVisible(id, ctID))
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

return function(...)
  local o = ... or {}
  setmetatable(o, C)
  C.__index = C
  o:init(o.id)
  return o.model and o -- returns nil if invalid object
end
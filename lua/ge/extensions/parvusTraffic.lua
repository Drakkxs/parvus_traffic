-- Simplistic traffic variety
local M = {}
M.dependencies = { 'gameplay_traffic' }

local logTag = 'parvus_traffic'
local random = math.random

-- when extension loaded
local function onExtensionLoaded()
    log('D', logTag, "Extension Loaded")
end

local function dump(t)
    -- remove: local t = { foo = 1, bar = function() end }
    local parts = {}
    for k, v in pairs(t) do
        table.insert(parts, tostring(k) .. "=" .. tostring(v))
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- when a vehicle is reset
local function onVehicleResetted(id)
    -- Only During Traffic
    if gameplay_traffic.getState() ~= "on" then return end

    -- Only Ai Traffic
    local veh = gameplay_traffic.getTrafficData()[id]
    if veh and (veh.isAi or tonumber(veh.isTraffic) == 1) then
        print(table.concat({ logTag, "Vehicle:", dump(veh), "Vars:", dump(veh.vars) }, " "))
        local aggression = random() * random() * 1.65 + 0.35 -- between 0.35 and 2
        log('D', logTag, '(' .. id .. ') Set Aggression: (' .. aggression .. ')')
        getObjectByID(id):queueLuaCommand('ai.setAggression(' .. aggression .. ')')
    end
end

-- interface
M.onExtensionLoaded = onExtensionLoaded
M.onVehicleResetted = onVehicleResetted
return M

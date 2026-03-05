-- lua\ge\extensions\parvus\parvusTraffic.lua
local M = {}
M.dependencies = { 'gameplay_traffic' }

local state = require('ge/extensions/parvus/parvusTraffic_state')
local L = require('ge/extensions/parvus/parvusTraffic_logic')

local function onExtensionLoaded()
    log('D', state.logTag, "Extension Loaded")
end

local function onUpdate(dtReal, dtSim)
    if gameplay_traffic.getState() ~= "on" then return end
    if dtSim <= 0 then return end

    if state.aux.queuedVehicle == 0 then
        state.aux.queuedVehicle = 1
    end

    local stoppedAiVehCount, vehCount, vehCountAi = 0, 0, 0

    for i, id in ipairs(state.trafficIdsSorted) do
        vehCount = vehCount + 1
        local veh = gameplay_traffic.getTrafficData()[id]
        if veh then
            if veh.isAi then
                vehCountAi = vehCountAi + 1
                if veh.speed < state.aux.minMovingSpeed then
                    stoppedAiVehCount = stoppedAiVehCount + 1
                end
            end

            ---@diagnostic disable-next-line: undefined-field
            if be:getObjectActive(id) then
                if i == state.aux.queuedVehicle then
                    L.checkVehicle(state, id)
                end
            end
        end
    end

    if vehCount == 0 then
        state.aux.queuedVehicle = 1
        return
    end

    state.aux.queuedVehicle = state.aux.queuedVehicle + 1
    if state.aux.queuedVehicle > vehCount then
        state.aux.queuedVehicle = 1
    end

    if stoppedAiVehCount < (vehCountAi * 0.6) then
        if (state.aux.deadlockTimer or 0) > 0 then
            state.aux.deadlockTimer = math.max(0, state.aux.deadlockTimer - dtSim)
        end
    else
        state.aux.deadlockTimer = (state.aux.deadlockTimer or 0) + dtSim
    end
end

local function onVehicleResetted(id)
    if gameplay_traffic.getState() ~= "on" then return end
    local veh = gameplay_traffic.getTrafficData()[id]
    if veh and veh.isAi then
        state.aux.vehDataTable[id] = {} -- reset per-vehicle data
        L.setupAggression(state, id)
    end
end

local function onTrafficAction(id, name, data)
    if name ~= 'changeRole' then return end
    if gameplay_traffic.getState() ~= "on" then return end
    if not data then return end

    local veh = gameplay_traffic.getTrafficData()[id]
    if not veh or not veh.isAi then return end
    if veh._parvusRedirectingRole then return end

    if data.name == 'standard' then
        veh._parvusRedirectingRole = true
        veh:setRole('parvus')
        veh._parvusRedirectingRole = nil
    end
end

local function onTrafficVehicleAdded(id)
    state.trafficIdsSorted = tableKeysSorted(gameplay_traffic.getTrafficData())
end

local function onTrafficVehicleRemoved(id)
    state.trafficIdsSorted = tableKeysSorted(gameplay_traffic.getTrafficData())
    state.aux.vehDataTable[id] = nil
end

M.onExtensionLoaded = onExtensionLoaded
M.onUpdate = onUpdate
M.onTrafficAction = onTrafficAction
M.onTrafficVehicleAdded = onTrafficVehicleAdded
M.onTrafficVehicleRemoved = onTrafficVehicleRemoved
M.onVehicleResetted = onVehicleResetted

return M

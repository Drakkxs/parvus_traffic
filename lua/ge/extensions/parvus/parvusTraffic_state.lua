-- lua\ge\extensions\parvus\parvusTraffic_state.lua
local M = {}

M.logTag = 'parvusTraffic'

M.trafficIdsSorted = {}

M.aux = {
  queuedVehicle = 0,
  vehDataTable = {},
  minMovingSpeed = 4,
  deadlockTimer = 0,
}

M.tAggresion = { resolution = 2, skew = 2, baseAggression = 0.3, maxAggression = 2, startchance = 1, decay = 0.1, threshold = 2 }
M.tSpeeder = { aggressionThreshold = 0.5, startchance = 1, decay = 0.05, threshold = 2 }
M.tToughness = { aggressionThreshold = 1, startchance = 1, decay = 0.1, threshold = 2 }
M.tReckless = { aggressionThreshold = 1.9, startchance = 1, decay = 0.1, threshold = 2 }

return M

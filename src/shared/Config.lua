--!strict
--[[
	Config — every tuning knob for Steal a Fish lives here.
	Change numbers here, not in code. All values are server-authoritative.
]]

local Config = {}

-- Plots (player aquariums)
Config.MaxPlots = 8 -- one per player, 8-player server to start
Config.SlotsPerPlot = 12 -- fish display slots per aquarium

-- Spawning (the "river" conveyor)
Config.SpawnInterval = 4 -- seconds between fish spawns
Config.MaxRiverFish = 12 -- cap of unclaimed fish swimming

-- Income
Config.IncomeTickRate = 1 -- seconds between income ticks

-- Stealing
Config.StealChannelTime = 3 -- seconds holding E to steal
Config.StealCooldown = 10 -- seconds before the same fish can be stolen again
Config.BaseLockDuration = 60 -- seconds a base lock lasts (game pass extends)

-- Data
Config.AutosaveInterval = 120 -- seconds between autosaves
Config.DataStoreName = "StealAFish_PlayerData_v1"

return Config

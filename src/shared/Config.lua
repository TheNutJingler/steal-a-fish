--!strict
--[[
	Config — every tuning knob for Steal a Fish lives here.
	Change numbers here, not in code. All values are server-authoritative.

	NOTE: fish economy numbers live in FishRegistry.lua — do not rebalance
	those without asking. This file is for system tuning only.
]]

local Config = {}

-- Plots (player aquariums) — vertically expanding, theme-park-tycoon style.
-- Ground floor is always available; upper floors unlock via aquarium upgrades.
Config.MaxPlots = 8 -- one per player, 8-player server to start (4 per riverbank)
Config.SlotsPerPlot = 12 -- fish display slots on the ground floor (slots 1-12)
Config.Floor2Slots = 8 -- slots 13-20
Config.Floor3Slots = 8 -- slots 21-28
Config.MaxFloors = 3

-- Aquarium upgrades: each row unlocks floors + multiplies income.
-- Data-driven: add rows for more levels. Costs in coins.
Config.AquariumUpgrades = table.freeze({
	{
		Level = 2,
		Cost = 5000,
		FloorsUnlocked = 2,
		IncomeMultiplier = 1.5,
		DisplayName = "Second Floor",
	},
	{
		Level = 3,
		Cost = 50000,
		FloorsUnlocked = 3,
		IncomeMultiplier = 2.0,
		DisplayName = "Sky Aquarium",
	},
})

-- Spawning (the "river" conveyor)
Config.SpawnInterval = 4 -- seconds between fish spawns
Config.MaxRiverFish = 12 -- cap of unclaimed fish swimming
Config.FishSwimSpeed = 8 -- studs/second along the river path
Config.PityThreshold = 25 -- every Nth spawn forces at least PityMinRarity
Config.PityMinRarity = "Epic" -- rarity id floor for pity spawns

-- Claiming (grabbing fish from the river)
Config.MaxClaimDistance = 14 -- studs; server re-validates distance on every claim

-- Income
Config.IncomeTickRate = 1 -- seconds between income ticks
Config.CodexTierBonus = 0.05 -- +5% global income per completed rarity tier
Config.AfkCoveBonus = 1.25 -- income multiplier while standing in the AFK cove
Config.AfkCheckInterval = 5 -- seconds between AFK-cove presence checks

-- Offline earnings
Config.OfflineEarningsCapHours = 8 -- max hours of offline earnings
Config.OfflineEarningsRate = 0.5 -- 50% rate (100% with AFK Boost pass)

-- Stealing
Config.StealChannelTime = 3 -- seconds holding E to steal
Config.StealCooldown = 10 -- seconds before the same fish can be stolen again
Config.StealMaxDistance = 14 -- must be within this of the slot pedestal to steal
Config.CarryWalkSpeed = 9.6 -- thief movespeed while carrying (~40% slower than 16)
Config.BaseLockDuration = 60 -- seconds a base lock lasts (game pass extends)
Config.BankCheckInterval = 0.5 -- seconds between carry-bank region checks
Config.DropCheckInterval = 0.25 -- seconds between carrier bump checks

-- Rate limits: {MaxCalls, WindowSeconds} per player, per remote
Config.RateLimit_ClaimPlot = { Max = 5, Window = 10 }
Config.RateLimit_Steal = { Max = 10, Window = 10 }
Config.RateLimit_Lock = { Max = 5, Window = 30 }

-- Data
Config.AutosaveInterval = 120 -- seconds between autosaves
Config.DataStoreName = "StealAFish_PlayerData_v1"
Config.ProfileTemplateVersion = 1

-- World layout (studs)
Config.MapHalfSize = 200 -- playable half-extent; rock barrier sits beyond this
Config.RiverHalfWidth = 12 -- river is 24 studs wide
Config.PlotSize = 44 -- plots are 44x44 single-level platforms
Config.PlotsPerBank = 4

return Config

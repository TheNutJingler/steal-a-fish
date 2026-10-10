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
Config.SlotsPerPlot = 8 -- fish display slots on the ground floor (slots 1-8), one row along the back wall
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
Config.SpawnInterval = 5 -- seconds between fish spawns (slower early game)
Config.MaxRiverFish = 10 -- cap of unclaimed fish swimming
Config.FishSwimSpeed = 8 -- studs/second along the river path
Config.PityThreshold = 60 -- every Nth spawn forces at least PityMinRarity
Config.PityMinRarity = "Rare" -- rarity id floor for pity spawns

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

-- World layout (studs) — mirrors WorldService constants.
Config.MapHalfSize = 700 -- playable half-extent; rock barrier sits beyond this
Config.RiverHalfWidth = 15 -- river is 30 studs wide
Config.PlotSize = 60 -- ground platform is 60x60 inside a 150x150 lot
Config.PlotsPerBank = 4

-- Land expansion: buyable tycoon-style lot growth. Each tier pushes the
-- fences out and adds 4 ground slots in the new land (slots 29-40).
-- Data-driven: add rows for more tiers.
Config.ExpansionSlotsPerTier = 4
Config.MaxExpansionTier = 3
Config.LandExpansions = table.freeze({
	{
		Tier = 1,
		Cost = 10000,
		LotSize = 210,
		DisplayName = "Land Grant I",
	},
	{
		Tier = 2,
		Cost = 60000,
		LotSize = 270,
		DisplayName = "Land Grant II",
	},
	{
		Tier = 3,
		Cost = 250000,
		LotSize = 330,
		DisplayName = "Land Grant III",
	},
})

return Config

-- Tycoon: tank upgrades + rebirth.
Config.TankMaxLevel = 5 -- per-tank levels; each level above 1 adds TankBonusPerLevel income
Config.TankBonusPerLevel = 0.25 -- +25% fish income per level (Lv5 = 2x)
Config.TankUpgradeBaseCost = 2500 -- level-up cost = base * 2^(level-1)
Config.RebirthBaseCost = 500000 -- first rebirth cost; doubles each rebirth
Config.RebirthMultiplier = 1.5 -- income x1.5 per rebirth, stacking

-- Aquarium: buildable on each land tier. +20% global income each.
Config.AquariumCost = 40000
Config.AquariumBonusPer = 0.20

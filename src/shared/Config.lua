--!strict
--[[
	Config — every tunable number in the game lives here.

	Rules:
	- Nothing in this file may be nil at runtime. All values are set BEFORE
	  the single `return Config` at the bottom.
	- To add a tunable: add it here with a comment, in the right section.
	- Services read from Config; they never hardcode numbers.
]]

local Config = {}

--------------------------------------------------
-- Data
--------------------------------------------------
Config.DataStoreName = "StealAFish_Data"
Config.AutosaveInterval = 300 -- seconds

--------------------------------------------------
-- World
--------------------------------------------------
Config.MapSize = 1400 -- total play area (square)
Config.PlotCount = 8 -- player bases around the map

--------------------------------------------------
-- Fish spawning
--------------------------------------------------
Config.SpawnInterval = 5 -- seconds between river spawns
Config.MaxClaimDistance = 12 -- studs; server re-validates pickup distance

--------------------------------------------------
-- Steal
--------------------------------------------------
Config.StealMaxDistance = 14 -- studs; server-measured at commit time
Config.StealCooldown = 30 -- seconds before a stolen fish can be re-stolen
Config.CarryWalkSpeed = 10 -- slowed walk speed while carrying

--------------------------------------------------
-- Tycoon: tank upgrades
--------------------------------------------------
Config.TankMaxLevel = 5 -- per-tank levels
Config.TankBonusPerLevel = 0.25 -- +25% fish income per level above 1 (Lv5 = 2x)
Config.TankUpgradeBaseCost = 2500 -- level-up cost = base * 2^(level-1)

--------------------------------------------------
-- Tycoon: rebirth
--------------------------------------------------
Config.RebirthBaseCost = 500000 -- first rebirth cost; doubles each rebirth
Config.RebirthMultiplier = 1.5 -- income x1.5 per rebirth, stacking

--------------------------------------------------
-- Tycoon: aquarium building
--------------------------------------------------
Config.AquariumCost = 40000 -- per land tier
Config.AquariumBonusPer = 0.20 -- +20% global income each (additive)

--------------------------------------------------
-- Tycoon: land expansion
--------------------------------------------------
-- (tiers defined in BuildCatalog; costs here for single source of truth)
Config.ExpansionSlotsPerTier = 4 -- extra tank slots per land tier

--------------------------------------------------
-- Build system
--------------------------------------------------
Config.BuildGridSize = 12 -- 12x12 tile grid per plot
Config.BuildTileSize = 8 -- studs per tile

--------------------------------------------------
-- Rate limits (Max requests per Window seconds, per player)
--------------------------------------------------
Config.RateLimit_Steal = { Max = 5, Window = 10 }
Config.RateLimit_Build = { Max = 10, Window = 5 }
Config.RateLimit_Tycoon = { Max = 10, Window = 5 }

--------------------------------------------------
-- AFK
--------------------------------------------------
Config.AfkCoveMultiplier = 0.5 -- income multiplier in the AFK cove
Config.OfflineEarnHours = 8 -- max offline earnings window
Config.OfflineEarnRate = 0.5 -- 50% of normal rate while offline

return Config

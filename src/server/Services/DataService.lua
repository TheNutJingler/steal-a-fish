--!strict
--[[
	DataService — player data ownership.

	Owns: ProfileStore profiles, the player data template, save/load,
	autosave, offline earnings calculation.

	Exposes:
	- Init()
	- GetProfile(player) -> profile?
	- GetBaseIncomePerSecond(profile) -> number  (with tank upgrades)
	- GetDisplayRate(player, profile) -> number  (ALL multipliers, single source)
	- RebirthCost(profile) -> number
	- RebirthMultiplier(profile) -> number
	- GetAquariumBonus(profile) -> number
	- GetCodexBonus(player) -> number
	- RegisterCodexEntry(player, speciesId, variantId)
	- PlayerReady (BindableEvent): (player, profile)
	- PlayerLeaving (BindableEvent): (player)

	Step 2 will fill this in.
]]

local DataService = {}

function DataService.Init()
	print("[DataService] init (scaffold)")
end

function DataService.GetProfile(_player: Player): any
	return nil
end

-- THE single source of truth for income math. Every HUD update, purchase
-- check, and display calls this. Never inline multiplier math elsewhere.
-- Step 6 will fill this in.
function DataService.GetDisplayRate(_player: Player, _profile: any): number
	return 0
end

return DataService

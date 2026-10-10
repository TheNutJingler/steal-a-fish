--!strict
--[[
	Types — shared Luau type definitions.

	Keep this in sync with DataService.TEMPLATE. If you add a field to the
	player data template, add its type here.
]]

export type FishRecord = {
	Uid: string,
	SpeciesId: string,
	VariantId: string,
	Slot: number?, -- nil while being carried
}

export type PlayerData = {
	Coins: number,
	LifetimeCoins: number,
	IncomeMultiplier: number,
	Fish: { FishRecord },
	Codex: { [string]: boolean }, -- ["SpeciesId:VariantId"] = true
	CodexTierBonus: { [string]: boolean }, -- [RarityId] = true
	LastLogout: number,
	AfkBoost: boolean,
	Rebirths: number,
	ExpansionTier: number, -- land expansion tier owned; 0 = base lot
	TankUpgrades: { [string]: number }, -- [tostring(slotIndex)] = level 1-5
	Aquariums: { [string]: boolean }, -- [tostring(tier)] = true
	BuildItems: { { Id: string, TX: number, TZ: number, Rot: number } },
	SchemaVersion: number,
}

return nil

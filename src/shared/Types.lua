--!strict
--[[
	Types — shared type exports for Steal a Fish.
	Server owns all of these at runtime; the client only reads what the
	server replicates (attributes, remote payloads, leaderstats).
]]

export type FishInstanceData = {
	Uid: string,
	SpeciesId: string,
	VariantId: string,
	IncomePerSecond: number,
}

-- An owned fish as stored in the player profile.
export type OwnedFish = {
	Uid: string,
	SpeciesId: string,
	VariantId: string,
	Slot: number?, -- plot slot index (1..SlotsPerPlot); nil = in inventory, unplaced
}

export type PlayerProfileData = {
	Coins: number,
	LifetimeCoins: number,
	IncomeMultiplier: number,
	Fish: { OwnedFish },
	Codex: { [string]: boolean }, -- ["SpeciesId:VariantId"] = true
	CodexTierBonus: { [string]: boolean }, -- [RarityId] = true when tier complete
	LastLogout: number, -- os.time() of last session end; 0 = never
	AfkBoost: boolean, -- game pass flag (future)
	Rebirths: number,
	AquariumLevel: number, -- highest aquarium upgrade owned; 1 = ground floor only
	SchemaVersion: number,
}

return nil

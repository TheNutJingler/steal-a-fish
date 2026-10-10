--!strict
--[[
	FishRegistry — data-driven fish definitions.

	Adding a fish = adding a row. Adding a variant = adding a row.
	Services never hardcode species; they call FishRegistry.GetFish().

	Fields per fish:
	- SpeciesId: unique string key
	- DisplayName: shown in UI
	- Rarity: "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"
	- IncomePerSecond: base $/s before multipliers
	- SpawnWeight: relative spawn chance in the river

	Fields per variant (applied on top of the species):
	- VariantId: unique string key
	- DisplayName
	- IncomeMultiplier: multiplies the species IncomePerSecond
	- Color: primary body color
]]

local FishRegistry = {}

export type FishDef = {
	SpeciesId: string,
	DisplayName: string,
	Rarity: string,
	IncomePerSecond: number,
	SpawnWeight: number,
}

export type VariantDef = {
	VariantId: string,
	DisplayName: string,
	IncomeMultiplier: number,
	Color: Color3,
}

-- Step 4 will fill this in. Scaffold keeps the API stable.
local FISH: { [string]: FishDef } = {
	-- Example (to be replaced in Step 4):
	-- ["Minnow"] = {
	-- 	SpeciesId = "Minnow",
	-- 	DisplayName = "Minnow",
	-- 	Rarity = "Common",
	-- 	IncomePerSecond = 2,
	-- 	SpawnWeight = 100,
	-- },
}

local VARIANTS: { [string]: VariantDef } = {
	["Normal"] = {
		VariantId = "Normal",
		DisplayName = "",
		IncomeMultiplier = 1,
		Color = Color3.fromRGB(100, 150, 200),
	},
}

function FishRegistry.GetFish(speciesId: string, variantId: string): (FishDef, VariantDef)
	local fish = FISH[speciesId]
	assert(fish, `Unknown species: {speciesId}`)
	local variant = VARIANTS[variantId] or VARIANTS["Normal"]
	return fish, variant
end

function FishRegistry.GetIncomePerSecond(speciesId: string, variantId: string): number
	local fish, variant = FishRegistry.GetFish(speciesId, variantId)
	return fish.IncomePerSecond * variant.IncomeMultiplier
end

function FishRegistry.AllSpecies(): { FishDef }
	local out = {}
	for _, def in FISH do
		table.insert(out, def)
	end
	return out
end

return FishRegistry

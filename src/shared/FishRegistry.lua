--!strict
--[[
	FishRegistry — the single source of truth for every fish in Steal a Fish.

	DESIGN: every fish = a BASELINE SPECIES + a VARIANT.
	- Baseline species: the fish itself (Bluegill, Bass, Catfish...). Holds base income,
	  a rarity tier, and a habitat. Rarity climbs Starter -> Mythic; spawn weight
	  falls as rarity rises; the top tiers are ocean species.
	- Variant: a modifier layered on top (Normal, Golden, Diamond...). Multiplies income.

	To add MORE FISH: add a row to SPECIES in the right rarity tier (keep weights
	decreasing as rarity rises). To add MORE VARIANTS: add a row to VARIANTS.
	Everything else (spawner, shop, codex, saving) reads from this one module.

	Example fish: Species "BluefinTuna" + Variant "Diamond" = "Diamond Bluefin Tuna".
]]

export type SpeciesId = string
export type VariantId = string
export type RarityId = "Starter" | "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"
export type HabitatId = "Freshwater" | "Ocean"

export type Species = {
	Id: SpeciesId,
	DisplayName: string,
	Rarity: RarityId,
	Habitat: HabitatId,
	BaseIncome: number, -- coins per second at Normal variant
	Weight: number, -- spawn weight; higher = more common. Falls as rarity rises.
	Color: Color3, -- body tint applied to the fish model
}

export type Variant = {
	Id: VariantId,
	DisplayName: string,
	Prefix: string, -- shown in front of the species name, e.g. "Golden"
	IncomeMultiplier: number, -- multiplies the species' BaseIncome
	Weight: number, -- roll weight; higher = more common
	GlowColor: Color3?, -- optional glow tint for rare variants
}

export type Fish = {
	Species: Species,
	Variant: Variant,
	IncomePerSecond: number,
	DisplayName: string,
}

local FishRegistry = {}

-- Rarity ladder, weakest to strongest. Used by the codex, shop filters, nameplates.
FishRegistry.RARITY_ORDER = {
	"Starter",
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
} :: { RarityId }

-- UI color per rarity tier.
FishRegistry.RARITY_COLORS = {
	Starter = Color3.fromRGB(160, 160, 160),
	Common = Color3.fromRGB(90, 200, 90),
	Uncommon = Color3.fromRGB(80, 140, 230),
	Rare = Color3.fromRGB(170, 90, 230),
	Epic = Color3.fromRGB(230, 110, 200),
	Legendary = Color3.fromRGB(255, 190, 40),
	Mythic = Color3.fromRGB(230, 60, 60),
} :: { [RarityId]: Color3 }

-- Variants: rarer variant = bigger multiplier. Weights are relative.
FishRegistry.VARIANTS = {
	Normal = {
		Id = "Normal",
		DisplayName = "Normal",
		Prefix = "",
		IncomeMultiplier = 1,
		Weight = 70,
		GlowColor = nil,
	},
	Silver = {
		Id = "Silver",
		DisplayName = "Silver",
		Prefix = "Silver",
		IncomeMultiplier = 2,
		Weight = 15,
		GlowColor = Color3.fromRGB(192, 192, 192),
	},
	Golden = {
		Id = "Golden",
		DisplayName = "Golden",
		Prefix = "Golden",
		IncomeMultiplier = 5,
		Weight = 8,
		GlowColor = Color3.fromRGB(255, 215, 0),
	},
	Diamond = {
		Id = "Diamond",
		DisplayName = "Diamond",
		Prefix = "Diamond",
		IncomeMultiplier = 12,
		Weight = 4,
		GlowColor = Color3.fromRGB(185, 242, 255),
	},
	Crystal = {
		Id = "Crystal",
		DisplayName = "Crystal",
		Prefix = "Crystal",
		IncomeMultiplier = 20,
		Weight = 3,
		GlowColor = Color3.fromRGB(230, 250, 255),
	},
	Rainbow = {
		Id = "Rainbow",
		DisplayName = "Rainbow",
		Prefix = "Rainbow",
		IncomeMultiplier = 30,
		Weight = 2,
		GlowColor = Color3.fromRGB(255, 105, 180),
	},
	Shadow = {
		Id = "Shadow",
		DisplayName = "Shadow",
		Prefix = "Shadow",
		IncomeMultiplier = 75,
		Weight = 1,
		GlowColor = Color3.fromRGB(75, 0, 130),
	},
} :: { [VariantId]: Variant }

-- Baseline species, ordered by rarity. Freshwater pond at the bottom,
-- open ocean at the top. Higher rarity = lower weight = rarer.
FishRegistry.SPECIES = {
	-- STARTER: the pond basics. Everyone starts here.
	Bluegill = {
		Id = "Bluegill",
		DisplayName = "Bluegill",
		Rarity = "Starter",
		Habitat = "Freshwater",
		BaseIncome = 1,
		Weight = 30,
		Color = Color3.fromRGB(90, 140, 90),
	},
	LargemouthBass = {
		Id = "LargemouthBass",
		DisplayName = "Largemouth Bass",
		Rarity = "Starter",
		Habitat = "Freshwater",
		BaseIncome = 5,
		Weight = 25,
		Color = Color3.fromRGB(60, 110, 60),
	},
	ChannelCatfish = {
		Id = "ChannelCatfish",
		DisplayName = "Channel Catfish",
		Rarity = "Starter",
		Habitat = "Freshwater",
		BaseIncome = 12,
		Weight = 20,
		Color = Color3.fromRGB(70, 70, 80),
	},
	-- COMMON
	Crappie = {
		Id = "Crappie",
		DisplayName = "Crappie",
		Rarity = "Common",
		Habitat = "Freshwater",
		BaseIncome = 25,
		Weight = 14,
		Color = Color3.fromRGB(150, 150, 160),
	},
	RainbowTrout = {
		Id = "RainbowTrout",
		DisplayName = "Rainbow Trout",
		Rarity = "Common",
		Habitat = "Freshwater",
		BaseIncome = 45,
		Weight = 10,
		Color = Color3.fromRGB(120, 160, 190),
	},
	-- UNCOMMON
	BrownTrout = {
		Id = "BrownTrout",
		DisplayName = "Brown Trout",
		Rarity = "Uncommon",
		Habitat = "Freshwater",
		BaseIncome = 70,
		Weight = 8,
		Color = Color3.fromRGB(130, 100, 60),
	},
	SmallmouthBass = {
		Id = "SmallmouthBass",
		DisplayName = "Smallmouth Bass",
		Rarity = "Uncommon",
		Habitat = "Freshwater",
		BaseIncome = 110,
		Weight = 6,
		Color = Color3.fromRGB(110, 95, 60),
	},
	-- RARE
	BrookTrout = {
		Id = "BrookTrout",
		DisplayName = "Brook Trout",
		Rarity = "Rare",
		Habitat = "Freshwater",
		BaseIncome = 160,
		Weight = 5,
		Color = Color3.fromRGB(90, 130, 120),
	},
	LakeTrout = {
		Id = "LakeTrout",
		DisplayName = "Lake Trout",
		Rarity = "Rare",
		Habitat = "Freshwater",
		BaseIncome = 220,
		Weight = 4,
		Color = Color3.fromRGB(100, 110, 130),
	},
	StripedBass = {
		Id = "StripedBass",
		DisplayName = "Striped Bass",
		Rarity = "Rare",
		Habitat = "Freshwater",
		BaseIncome = 260,
		Weight = 4,
		Color = Color3.fromRGB(100, 120, 130),
	},
	FlatheadCatfish = {
		Id = "FlatheadCatfish",
		DisplayName = "Flathead Catfish",
		Rarity = "Rare",
		Habitat = "Freshwater",
		BaseIncome = 300,
		Weight = 3,
		Color = Color3.fromRGB(80, 70, 60),
	},
	-- EPIC: freshwater apex + first taste of the ocean
	AlligatorGar = {
		Id = "AlligatorGar",
		DisplayName = "Alligator Gar",
		Rarity = "Epic",
		Habitat = "Freshwater",
		BaseIncome = 450,
		Weight = 2,
		Color = Color3.fromRGB(50, 60, 50),
	},
	BluefinTuna = {
		Id = "BluefinTuna",
		DisplayName = "Bluefin Tuna",
		Rarity = "Epic",
		Habitat = "Ocean",
		BaseIncome = 700,
		Weight = 2,
		Color = Color3.fromRGB(40, 70, 120),
	},
	-- LEGENDARY: open ocean
	Swordfish = {
		Id = "Swordfish",
		DisplayName = "Swordfish",
		Rarity = "Legendary",
		Habitat = "Ocean",
		BaseIncome = 1100,
		Weight = 1,
		Color = Color3.fromRGB(50, 80, 140),
	},
	BlueMarlin = {
		Id = "BlueMarlin",
		DisplayName = "Blue Marlin",
		Rarity = "Legendary",
		Habitat = "Ocean",
		BaseIncome = 1600,
		Weight = 1,
		Color = Color3.fromRGB(30, 60, 130),
	},
	-- MYTHIC: open ocean
	Megalodon = {
		Id = "Megalodon",
		DisplayName = "Megalodon",
		Rarity = "Mythic",
		Habitat = "Ocean",
		BaseIncome = 2500,
		Weight = 1,
		Color = Color3.fromRGB(40, 50, 70),
	},
} :: { [SpeciesId]: Species }

-- Build a concrete fish from a species + variant id. Errors on bad ids (fail loud).
function FishRegistry.GetFish(speciesId: SpeciesId, variantId: VariantId): Fish
	local species = FishRegistry.SPECIES[speciesId]
	assert(species, `Unknown species id: {speciesId}`)
	local variant = FishRegistry.VARIANTS[variantId]
	assert(variant, `Unknown variant id: {variantId}`)

	local displayName = species.DisplayName
	if variant.Prefix ~= "" then
		displayName = `{variant.Prefix} {species.DisplayName}`
	end

	return {
		Species = species,
		Variant = variant,
		IncomePerSecond = species.BaseIncome * variant.IncomeMultiplier,
		DisplayName = displayName,
	}
end

-- Weighted roll of a species id. Used by the spawner.
function FishRegistry.RollSpecies(rng: Random): SpeciesId
	local total = 0
	for _, species in FishRegistry.SPECIES do
		total += species.Weight
	end
	local roll = rng:NextNumber() * total
	for id, species in FishRegistry.SPECIES do
		roll -= species.Weight
		if roll <= 0 then
			return id
		end
	end
	return "Bluegill" -- fallback; unreachable unless weights are all zero
end

-- Weighted roll of a variant id. Used by the spawner.
function FishRegistry.RollVariant(rng: Random): VariantId
	local total = 0
	for _, variant in FishRegistry.VARIANTS do
		total += variant.Weight
	end
	local roll = rng:NextNumber() * total
	for id, variant in FishRegistry.VARIANTS do
		roll -= variant.Weight
		if roll <= 0 then
			return id
		end
	end
	return "Normal"
end

-- All species in a rarity tier, for the codex, shop filters, spawn tables.
function FishRegistry.GetSpeciesByRarity(rarity: RarityId): { Species }
	local out = {}
	for _, species in FishRegistry.SPECIES do
		if species.Rarity == rarity then
			table.insert(out, species)
		end
	end
	return out
end

return FishRegistry

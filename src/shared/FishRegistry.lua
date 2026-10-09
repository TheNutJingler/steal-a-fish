--!strict
--[[
	FishRegistry — the single source of truth for every fish in Steal a Fish.

	DESIGN: every fish = a BASELINE SPECIES + a VARIANT.
	- Baseline species: the fish itself (Bluegill, Bass, Catfish...). Holds base income.
	- Variant: a modifier layered on top (Normal, Golden, Diamond...). Multiplies income.

	To add MORE FISH: add a row to SPECIES. That's it — spawner, shop, codex,
	and saving all read from this module, so new fish just work.
	To add MORE VARIANTS: add a row to VARIANTS.

	Example fish: Species "LargemouthBass" + Variant "Golden" = "Golden Largemouth Bass".
]]

export type SpeciesId = string
export type VariantId = string

export type Species = {
	Id: SpeciesId,
	DisplayName: string,
	BaseIncome: number, -- coins per second at Normal variant
	Weight: number, -- spawn weight; higher = more common
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

-- Baseline species: common -> legendary. Add rows here to add more fish.
FishRegistry.SPECIES = {
	Bluegill = {
		Id = "Bluegill",
		DisplayName = "Bluegill",
		BaseIncome = 1,
		Weight = 30,
		Color = Color3.fromRGB(90, 140, 90),
	},
	Crappie = {
		Id = "Crappie",
		DisplayName = "Crappie",
		BaseIncome = 3,
		Weight = 22,
		Color = Color3.fromRGB(150, 150, 160),
	},
	LargemouthBass = {
		Id = "LargemouthBass",
		DisplayName = "Largemouth Bass",
		BaseIncome = 8,
		Weight = 18,
		Color = Color3.fromRGB(60, 110, 60),
	},
	ChannelCatfish = {
		Id = "ChannelCatfish",
		DisplayName = "Channel Catfish",
		BaseIncome = 20,
		Weight = 12,
		Color = Color3.fromRGB(70, 70, 80),
	},
	RainbowTrout = {
		Id = "RainbowTrout",
		DisplayName = "Rainbow Trout",
		BaseIncome = 50,
		Weight = 8,
		Color = Color3.fromRGB(120, 160, 190),
	},
	SmallmouthBass = {
		Id = "SmallmouthBass",
		DisplayName = "Smallmouth Bass",
		BaseIncome = 110,
		Weight = 5,
		Color = Color3.fromRGB(110, 95, 60),
	},
	AlligatorGar = {
		Id = "AlligatorGar",
		DisplayName = "Alligator Gar",
		BaseIncome = 300,
		Weight = 2,
		Color = Color3.fromRGB(50, 60, 50),
	},
	StripedBass = {
		Id = "StripedBass",
		DisplayName = "Striped Bass",
		BaseIncome = 70,
		Weight = 6,
		Color = Color3.fromRGB(100, 120, 130),
	},
	FlatheadCatfish = {
		Id = "FlatheadCatfish",
		DisplayName = "Flathead Catfish",
		BaseIncome = 150,
		Weight = 3,
		Color = Color3.fromRGB(80, 70, 60),
	},
	Megalodon = {
		Id = "Megalodon",
		DisplayName = "Megalodon",
		BaseIncome = 1000,
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

return FishRegistry

--!strict
--[[
	BuildCatalog — buyable base items for the Build tab.
	SizeTiles = {w, d} footprint in grid tiles (5 studs each).
	Rotation swaps w/d. Prices in coins.
]]

export type BuildItemDef = {
	Id: string,
	Name: string,
	Category: string, -- "Security" | "Decor"
	Price: number,
	SizeTiles: { number },
	Description: string,
}

local BuildCatalog = {}

BuildCatalog.ITEMS = {
	{
		Id = "SecurityGate",
		Name = "Security Gate",
		Category = "Security",
		Price = 15000,
		SizeTiles = { 2, 1 },
		Description = "Steal-a-Brainrot style laser gate. Seals shut for everyone but you while your base is locked.",
	},
	{
		Id = "Wall",
		Name = "Wall",
		Category = "Security",
		Price = 750,
		SizeTiles = { 1, 1 },
		Description = "Sturdy wall segment. Build mazes, vaults and chokepoints.",
	},
	{
		Id = "Stairs",
		Name = "Stairs",
		Category = "Decor",
		Price = 300,
		SizeTiles = { 1, 1 },
		Description = "A solid step. Stack them to reach new heights.",
	},
	{
		Id = "PathTile",
		Name = "Path Tile",
		Category = "Decor",
		Price = 150,
		SizeTiles = { 1, 1 },
		Description = "Decorative floor tile. Pave your base in style.",
	},
	{
		Id = "LampPost",
		Name = "Lamp Post",
		Category = "Decor",
		Price = 500,
		SizeTiles = { 1, 1 },
		Description = "Lights up your base. Pure style.",
	},
}

local byId: { [string]: BuildItemDef } = {}
for _, item in BuildCatalog.ITEMS do
	byId[item.Id] = item
end

function BuildCatalog.Get(id: string): BuildItemDef?
	return byId[id]
end

function BuildCatalog.ByCategory(cat: string): { BuildItemDef }
	local out: { BuildItemDef } = {}
	for _, item in BuildCatalog.ITEMS do
		if item.Category == cat then
			table.insert(out, item)
		end
	end
	return out
end

return BuildCatalog

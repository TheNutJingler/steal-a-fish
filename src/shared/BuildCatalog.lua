--!strict
--[[
	BuildCatalog — buildable items.

	Adding an item = adding a row. The server validates price, size, and
	placement; the client reads this for the build tab UI.

	Fields:
	- Id: unique string key
	- Name: display name
	- Price: coin cost
	- SizeTiles: {w, d} footprint in grid tiles
	- Category: "Security" | "Decor" | "Land"
	- Description: tooltip text

	Step 10 will fill this in.
]]

local BuildCatalog = {}

export type ItemDef = {
	Id: string,
	Name: string,
	Price: number,
	SizeTiles: { number },
	Category: string,
	Description: string,
}

local ITEMS: { [string]: ItemDef } = {}

function BuildCatalog.Get(itemId: string): ItemDef?
	return ITEMS[itemId]
end

function BuildCatalog.All(): { ItemDef }
	local out = {}
	for _, def in ITEMS do
		table.insert(out, def)
	end
	return out
end

function BuildCatalog.ByCategory(category: string): { ItemDef }
	local out = {}
	for _, def in ITEMS do
		if def.Category == category then
			table.insert(out, def)
		end
	end
	return out
end

return BuildCatalog

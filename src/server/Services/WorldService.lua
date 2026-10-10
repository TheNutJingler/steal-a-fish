--!strict
--[[
	WorldService — builds the map.

	Owns: procedural world generation (ground, river, rocks, pond, waterfall,
	spawn pad, plot platforms). Returns the layout table that other services
	use to position things.

	Exposes:
	- Init() -> Layout

	Step 3 will fill this in.
]]

local WorldService = {}

function WorldService.Init(): any
	print("[WorldService] init (scaffold)")
	return {}
end

return WorldService

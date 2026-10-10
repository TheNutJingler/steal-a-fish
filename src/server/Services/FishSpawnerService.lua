--!strict
--[[
	FishSpawnerService — the river conveyor.

	Owns: spawning fish in the river, moving them along the path,
	despawning at the end, touch-to-pickup prompts.

	Exposes:
	- Init(worldService, plotService, dataService, layout, stealService)

	Step 4 will fill this in.
]]

local FishSpawnerService = {}

function FishSpawnerService.Init(
	_worldService: any,
	_plotService: any,
	_dataService: any,
	_layout: any,
	_stealService: any
)
	print("[FishSpawnerService] init (scaffold)")
end

return FishSpawnerService

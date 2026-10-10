--!strict
--[[
	BuildService — player base building.

	Owns: tile grid placement (ghost preview validated client-side, commit
	validated server-side), build catalog items, security gates (collision
	groups), aquariums, build persistence.

	Exposes:
	- Init(dataService, plotService)
	- PlaceItem(player, itemId, tx, tz, rot) -> (boolean, string)
	- BuildAquarium(player, tier) -> (boolean, string)
	- RebuildPlot(player, plot)
	- ClearPlot(plot)
	- RefreshGates()

	Step 10 will fill this in.
]]

local BuildService = {}

function BuildService.Init(_dataService: any, _plotService: any)
	print("[BuildService] init (scaffold)")
end

return BuildService

--!strict
--[[
	PlotService — player bases.

	Owns: plot claiming, tank slots, fish visuals in tanks, base locking,
	tank upgrades, rebirth, land expansion. The plot is the player's tycoon.

	Exposes:
	- Init(dataService, worldService, layout)
	- SetStealService(stealService)
	- SetBuildService(buildService)
	- GetPlot(player) -> plot?
	- GetPlotByIndex(index) -> plot?
	- ClaimPlot(player, plotIndex) -> (boolean, string)
	- IsLocked(plot) -> boolean
	- MaxSlotsFor(plot) -> number
	- FreeSlotCount(plot) -> number
	- TakeFishFromSlot(plot, slotIndex) -> fishData?
	- ReturnFishToSlot(plot, fishData, preferSlot) -> slotIndex?
	- PlaceCarriedFish(player, slotIndex) -> (boolean, string)
	- MoveFishToPlayer(fishData, fromPlayer, toPlayer) -> boolean
	- UpgradeTank(player, slotIndex) -> (boolean, string)
	- RequestRebirth(player) -> (boolean, string)
	- TryExpand(player) -> (boolean, string)

	Step 5 will fill this in.
]]

local PlotService = {}

function PlotService.Init(_dataService: any, _worldService: any, _layout: any)
	print("[PlotService] init (scaffold)")
end

function PlotService.SetStealService(_stealService: any)
end

function PlotService.SetBuildService(_buildService: any)
end

function PlotService.GetPlot(_player: Player): any
	return nil
end

return PlotService

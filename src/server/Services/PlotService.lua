--!strict
--[[
	PlotService — owns aquarium plots: claiming, slot layout, fish placement.
	One plot per player (Config.MaxPlots). Slots hold owned fish (species+variant).
	Expose: ClaimPlot(player), GetPlot(player), PlaceFish(player, fishData, slot).
	STATUS: stub — plot claiming + slot logic come with the world pass.
]]

local PlotService = {}

function PlotService.Init(_dataService)
	-- TODO: build/claim plots on join, restore owned fish from profile.
	print("[PlotService] init (stub)")
end

return PlotService

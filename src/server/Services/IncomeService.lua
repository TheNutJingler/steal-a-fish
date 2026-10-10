--!strict
--[[
	IncomeService — the money tick.

	Owns: 1-second income loop, coin deposits, leaderstats, AFK cove
	detection, offline earnings grant on join.

	Uses DataService.GetDisplayRate() — the single source of truth for
	income math. Never computes multipliers inline.

	Exposes:
	- Init(dataService, layout)

	Step 6 will fill this in.
]]

local IncomeService = {}

function IncomeService.Init(_dataService: any, _layout: any)
	print("[IncomeService] init (scaffold)")
end

return IncomeService

--!strict
--[[
	HudController — coins display, income rate, buttons.

	Owns: top-bar HUD (coins, $/s), Build tab button, codex button.
	Listens to StatsUpdateRemote.

	Exposes:
	- Init()
]]

local HudController = {}

function HudController.Init()
	print("[HudController] init (scaffold)")
end

return HudController

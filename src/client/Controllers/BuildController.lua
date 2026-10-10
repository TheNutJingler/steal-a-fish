--!strict
--[[
	BuildController — build tab and placement ghost.

	Owns: Build tab GUI (Security / Decor / Land / Tanks / Rebirth tabs),
	ghost preview, tile picking, rotation. Client-side validation only —
	the server re-validates everything on commit.

	Exposes:
	- Init()
]]

local BuildController = {}

function BuildController.Init()
	print("[BuildController] init (scaffold)")
end

return BuildController

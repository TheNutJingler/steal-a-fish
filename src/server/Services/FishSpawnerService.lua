--!strict
--[[
	FishSpawnerService — the "river": spawns fish on a timer for players to grab.
	Rolls species + variant via FishRegistry. Server owns ALL spawn knowledge —
	never replicate the spawn table to the client (bot prevention).
	Expose: none public yet; fires RemoteEvents on spawn/claim.
	STATUS: stub — spawner loop comes with the world pass.
]]

local FishSpawnerService = {}

function FishSpawnerService.Init(_plotService)
	-- TODO: spawn loop (Config.SpawnInterval), cap (Config.MaxRiverFish),
	-- claim handling, pity timer for rare variants.
	print("[FishSpawnerService] init (stub)")
end

return FishSpawnerService

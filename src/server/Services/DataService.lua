--!strict
--[[
	DataService — owns ALL player data. Nothing else touches the DataStore.
	Uses ProfileStore (session locking, no silent cross-server data loss).
	Expose: GetProfile(player) -> profile. All saves go through here.
	STATUS: stub — ProfileStore wiring comes with the data pass.
]]

local DataService = {}

function DataService.Init()
	-- TODO: load ProfileStore, hook PlayerAdded/PlayerRemoving,
	-- autosave loop (Config.AutosaveInterval), BindToClose flush.
	print("[DataService] init (stub)")
end

function DataService.GetProfile(_player: Player)
	-- TODO: return the player's profile table
	return nil
end

return DataService

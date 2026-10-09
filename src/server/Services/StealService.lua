--!strict
--[[
	StealService — THE trust boundary. Every steal is validated server-side:
	recompute distance, ownership, session legitimacy at commit time.
	Never trust the client's claim that a steal succeeded.
	Expose: RequestSteal(player, targetPlayer, slot) via RemoteEvent.
	STATUS: stub — steal flow comes with the interaction pass.
]]

local StealService = {}

function StealService.Init(_dataService, _plotService)
	-- TODO: RemoteEvent handler with full server-side validation,
	-- channel time (Config.StealChannelTime), cooldowns, base locks.
	print("[StealService] init (stub)")
end

return StealService

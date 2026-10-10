--!strict
--[[
	StealService — THE trust boundary.

	Every steal is validated server-side at commit time. The client sends
	intent; the server recomputes distance, ownership, lock state, cooldowns.
	Never trust the client's word.

	Owns: steal validation, carry state (visual, slow, drop), pickup of
	river fish.

	Exposes:
	- Init(dataService, plotService, layout)
	- TrySteal(player, plotIndex, slotIndex) -> (boolean, string)
	- PickupFish(player, speciesId, variantId) -> (boolean, string)
	- GetCarry(player) -> carryState?
	- ClearCarry(player)
	- ResolveDrop(player, context)
	- NoteBanked(uid)

	Step 8 will fill this in.
]]

local StealService = {}

function StealService.Init(_dataService: any, _plotService: any, _layout: any)
	print("[StealService] init (scaffold)")
end

function StealService.GetCarry(_player: Player): any
	return nil
end

function StealService.ClearCarry(_player: Player)
end

return StealService

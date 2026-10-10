--!strict
--[[
	RateLimit — per-player action throttling.

	Usage:
		local limiter = RateLimit.new(maxRequests, windowSeconds)
		if not limiter:Check(player.UserId) then
			return false, "Slow down."
		end
]]

local RateLimit = {}
RateLimit.__index = RateLimit

export type Limiter = {
	Check: (self: Limiter, key: number | string) -> boolean,
}

function RateLimit.new(max: number, window: number): Limiter
	return setmetatable({
		_max = max,
		_window = window,
		_hits = {} :: { [number | string]: { number } },
	}, RateLimit)
end

function RateLimit:Check(key: number | string): boolean
	local now = os.clock()
	local hits = self._hits[key]
	if not hits then
		hits = {}
		self._hits[key] = hits
	end
	-- Drop expired.
	local fresh = {}
	for _, t in hits do
		if now - t < self._window then
			table.insert(fresh, t)
		end
	end
	self._hits[key] = fresh
	if #fresh >= self._max then
		return false
	end
	table.insert(fresh, now)
	return true
end

return RateLimit

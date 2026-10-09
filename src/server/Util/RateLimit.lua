--!strict
--[[
	RateLimit — per-player sliding-window rate limiter (server-side only).
	From the coding study §4.5. Derive thresholds from legitimate max usage
	times headroom. Policy: silent reject; the caller decides escalation.
]]

local RateLimit = {}
RateLimit.__index = RateLimit

export type RateLimit = typeof(setmetatable(
	{} :: {
		max: number,
		window: number,
		hits: { [number]: { number } },
	},
	RateLimit
))

function RateLimit.new(maxCalls: number, windowSec: number): RateLimit
	return setmetatable({
		max = maxCalls,
		window = windowSec,
		hits = {},
	} :: {
		max: number,
		window: number,
		hits: { [number]: { number } },
	}, RateLimit)
end

function RateLimit.Check(self: RateLimit, userId: number): boolean
	local now = os.clock()
	local fresh: { number } = {}
	local prior: { number } = self.hits[userId] or {}
	for _, t in prior do
		if now - t < self.window then
			table.insert(fresh, t)
		end
	end
	if #fresh >= self.max then
		self.hits[userId] = fresh
		return false
	end
	table.insert(fresh, now)
	self.hits[userId] = fresh
	return true
end

function RateLimit.Forget(self: RateLimit, userId: number)
	self.hits[userId] = nil
end

return RateLimit

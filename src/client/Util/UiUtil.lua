--!strict
--[[
	UiUtil — shared client UI helpers.

	Owns: button factory, panel factory, formatting helpers.

	Exposes:
	- MakeButton(parent, text, onClick) -> TextButton
	- FormatCoins(n) -> string
]]

local UiUtil = {}

function UiUtil.FormatCoins(n: number): string
	if n >= 1_000_000 then
		return string.format("%.1fM", n / 1_000_000)
	elseif n >= 1_000 then
		return string.format("%.1fK", n / 1_000)
	else
		return tostring(math.floor(n))
	end
end

return UiUtil

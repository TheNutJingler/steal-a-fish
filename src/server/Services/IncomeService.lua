--!strict
--[[
	IncomeService — the 1-second income tick.

	Coins accrue server-side in the profile (float precision); leaderstats
	are a floored mirror for the HUD. Multipliers stack:
	  base fish $/s × aquarium upgrades × codex tiers × AFK cove (1.25x).

	AFK cove presence is checked every 5s by distance (not by any client
	claim — the server measures). Clients get AfkCoveChanged for the badge.

	Expose: Init(dataService, layout)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = Shared:WaitForChild("Remotes")

local StatsUpdateRemote = Remotes:WaitForChild("StatsUpdate") :: RemoteEvent
local AfkCoveChangedRemote = Remotes:WaitForChild("AfkCoveChanged") :: RemoteEvent

local IncomeService = {}

local DataService: any = nil
local CoveCenter: Vector3 = Vector3.new()
local CoveRadius: number = 17
local InCove: { [Player]: boolean } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function currentRate(player: Player, profile: any): number
	local base = DataService.GetBaseIncomePerSecond(profile)
	local mult = profile.Data.IncomeMultiplier or 1
	mult *= DataService.GetCodexBonus(player)
	mult *= DataService.RebirthMultiplier(profile)
	if InCove[player] then
		mult *= Config.AfkCoveMultiplier
	end
	return base * mult
end

local function ensureLeaderstats(player: Player)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		return
	end
	stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = 0
	coins.Parent = stats
end

function IncomeService.Init(dataService: any, layout: any)
	DataService = dataService
	CoveCenter = layout.CoveCenter
	CoveRadius = layout.CoveRadius

	DataService.PlayerReady:Connect(function(player: Player, profile: any, _grant: any)
		ensureLeaderstats(player)
		InCove[player] = false
		local stats = player:WaitForChild("leaderstats")
		local coinsValue = stats:WaitForChild("Coins") :: IntValue
		coinsValue.Value = math.floor(profile.Data.Coins)
	end)

	DataService.PlayerLeaving:Connect(function(player: Player)
		InCove[player] = nil
	end)

	-- 1s income tick.
	task.spawn(function()
		while true do
			task.wait(Config.IncomeTick)
			for _, player in Players:GetPlayers() do
				local profile = DataService.GetProfile(player)
				if not profile then
					continue
				end
				local rate = currentRate(player, profile)
				if rate > 0 then
					profile.Data.Coins += rate * Config.IncomeTick
					profile.Data.LifetimeCoins += rate * Config.IncomeTick
				end
				local stats = player:FindFirstChild("leaderstats")
				if stats then
					local coinsValue = stats:FindFirstChild("Coins")
					if coinsValue and coinsValue:IsA("IntValue") then
						coinsValue.Value = math.floor(profile.Data.Coins)
					end
				end
			end
		end
	end)

	-- 5s HUD sync + AFK cove detection.
	task.spawn(function()
		while true do
			task.wait(5)
			for _, player in Players:GetPlayers() do
				local profile = DataService.GetProfile(player)
				if not profile then
					continue
				end
				-- AFK cove: server-measured distance.
				local inside = false
				local root = rootOf(player)
				if root then
					local flat = Vector3.new(root.Position.X, 0, root.Position.Z)
						- Vector3.new(CoveCenter.X, 0, CoveCenter.Z)
					inside = flat.Magnitude <= CoveRadius
				end
				if inside ~= (InCove[player] or false) then
					InCove[player] = inside
					AfkCoveChangedRemote:FireClient(player, inside)
				end
				StatsUpdateRemote:FireClient(
					player,
					math.floor(profile.Data.Coins),
					currentRate(player, profile)
				)
			end
		end
	end)

	print("[IncomeService] init")
end

return IncomeService

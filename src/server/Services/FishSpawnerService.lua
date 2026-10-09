--!strict
--[[
	FishSpawnerService — the "river" conveyor.

	Server owns ALL spawn knowledge: species/variant rolls, pity timer, and
	the live fish table never leave the server. Clients only see the fish
	models themselves (appearance for rendering) — never weights, tables,
	or future spawns. No free bot APIs.

	Fish move kinematically along the river path (anchored models, CFrame
	math — cheap at scale, fully server-authoritative). Grabbing is
	touch-based: the server re-validates distance on every claim.

	Expose: Init(worldService, plotService, dataService)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

local server = ServerScriptService:WaitForChild("StealAFish")
local Util = server:WaitForChild("Util")
local FishVisual = require(Util:WaitForChild("FishVisual"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local FishRegistry = require(Shared:WaitForChild("FishRegistry"))

type RiverFish = {
	Uid: string,
	SpeciesId: string,
	VariantId: string,
	Model: Model,
	Body: BasePart,
	Distance: number, -- studs traveled along the path
	Claimed: boolean,
	TouchConn: RBXScriptConnection?,
}

local FishSpawnerService = {}

local PlotService: any = nil

local RiverFishByUid: { [string]: RiverFish } = {}
local RiverFishList: { RiverFish } = {}

local rng = Random.new()
local spawnsSincePity = 0

-- Precomputed path data.
local PathPoints: { Vector3 } = {}
local SegmentLengths: { number } = {}
local TotalPathLength = 0

local RARITY_FLOOR = { -- rarity -> order index
	Starter = 1,
	Common = 2,
	Uncommon = 3,
	Rare = 4,
	Epic = 5,
	Legendary = 6,
	Mythic = 7,
}

local function buildPathData(points: { Vector3 })
	PathPoints = points
	SegmentLengths = {}
	TotalPathLength = 0
	for i = 1, #points - 1 do
		local len = (points[i + 1] - points[i]).Magnitude
		table.insert(SegmentLengths, len)
		TotalPathLength += len
	end
end

local function pathPosition(distance: number): (Vector3, Vector3)
	-- Returns (position, lookDirection) at `distance` along the path.
	local d = math.clamp(distance, 0, TotalPathLength)
	for i, segLen in SegmentLengths do
		if d <= segLen then
			local a = PathPoints[i]
			local b = PathPoints[i + 1]
			local t = if segLen > 0 then d / segLen else 0
			local dir = (b - a).Unit
			return a:Lerp(b, t), dir
		end
		d -= segLen
	end
	local last = PathPoints[#PathPoints]
	local prev = PathPoints[#PathPoints - 1]
	return last, (last - prev).Unit
end

-- Weighted roll restricted to species at/above a rarity floor (pity spawns).
local function rollSpeciesAtOrAbove(minRarity: string): string
	local floorIdx = RARITY_FLOOR[minRarity] or 1
	local total = 0
	for _, species in FishRegistry.SPECIES do
		if (RARITY_FLOOR[species.Rarity] or 1) >= floorIdx then
			total += species.Weight
		end
	end
	local roll = rng:NextNumber() * total
	for id, species in FishRegistry.SPECIES do
		if (RARITY_FLOOR[species.Rarity] or 1) >= floorIdx then
			roll -= species.Weight
			if roll <= 0 then
				return id
			end
		end
	end
	return "BluefinTuna"
end

local function rollFish(): (string, string)
	spawnsSincePity += 1
	local speciesId: string
	if spawnsSincePity >= Config.PityThreshold then
		speciesId = rollSpeciesAtOrAbove(Config.PityMinRarity)
		spawnsSincePity = 0
	else
		speciesId = FishRegistry.RollSpecies(rng)
		local species = FishRegistry.SPECIES[speciesId]
		if species and (RARITY_FLOOR[species.Rarity] or 1) >= (RARITY_FLOOR[Config.PityMinRarity] or 5) then
			spawnsSincePity = 0 -- natural rare reset the pity clock
		end
	end
	local variantId = FishRegistry.RollVariant(rng)
	return speciesId, variantId
end

local function despawnFish(fish: RiverFish)
	if fish.TouchConn then
		fish.TouchConn:Disconnect()
		fish.TouchConn = nil
	end
	RiverFishByUid[fish.Uid] = nil
	for i = #RiverFishList, 1, -1 do
		if RiverFishList[i] == fish then
			table.remove(RiverFishList, i)
			break
		end
	end
	if fish.Model then
		fish.Model:Destroy()
	end
end

local function tryClaimFish(fish: RiverFish, player: Player)
	if fish.Claimed then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	-- Server re-validates distance: Touched can be spoofed at range.
	if (root.Position - fish.Body.Position).Magnitude > Config.MaxClaimDistance then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	fish.Claimed = true -- commit first: no double-claims
	local slot = PlotService.PlaceFish(player, fish.SpeciesId, fish.VariantId)
	if not slot then
		fish.Claimed = false -- release; plot full or no plot
		return
	end
	print(`[FishSpawner] {player.Name} grabbed {fish.SpeciesId} ({fish.VariantId}) -> slot {slot}`)
	despawnFish(fish)
end

local function spawnFish(parent: Instance)
	local speciesId, variantId = rollFish()
	local uid = HttpService:GenerateGUID(false)

	local model = FishVisual.Build(speciesId, variantId, 1.0, uid)
	local body = model.PrimaryPart :: BasePart
	body.CanTouch = true -- grab detection (server-side only)

	local pos, dir = pathPosition(0)
	model:PivotTo(CFrame.new(pos, pos + dir))
	model.Parent = parent

	local fish: RiverFish = {
		Uid = uid,
		SpeciesId = speciesId,
		VariantId = variantId,
		Model = model,
		Body = body,
		Distance = 0,
		Claimed = false,
		TouchConn = nil,
	}
	fish.TouchConn = body.Touched:Connect(function(hit: BasePart)
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if player then
			tryClaimFish(fish, player)
		end
	end)

	RiverFishByUid[uid] = fish
	table.insert(RiverFishList, fish)
end

function FishSpawnerService.Init(worldService: any, plotService: any, _dataService: any, layout: any)
	PlotService = plotService

	buildPathData(layout.RiverPath)

	local fishFolder = Instance.new("Folder")
	fishFolder.Name = "RiverFish"
	fishFolder.Parent = workspace:WaitForChild("StealAFishWorld")

	-- Kinematic movement: one Heartbeat loop for all river fish.
	RunService.Heartbeat:Connect(function(dt: number)
		local step = Config.FishSwimSpeed * math.min(dt, 0.25)
		for i = #RiverFishList, 1, -1 do
			local fish = RiverFishList[i]
			if fish.Claimed then
				continue
			end
			fish.Distance += step
			if fish.Distance >= TotalPathLength then
				despawnFish(fish) -- swam past the end uncaught
				continue
			end
			local pos, dir = pathPosition(fish.Distance)
			-- Gentle bob so the river feels alive.
			local bob = math.sin(os.clock() * 3 + fish.Distance * 0.2) * 0.35
			fish.Model:PivotTo(CFrame.new(pos + Vector3.new(0, bob, 0), pos + dir))
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.SpawnInterval)
			if #RiverFishList < Config.MaxRiverFish then
				local packed = table.pack(pcall(spawnFish, fishFolder))
				if not packed[1] then
					warn(`[FishSpawner] spawn failed: {packed[2]}`)
				end
			end
		end
	end)

	print("[FishSpawner] init")
end

return FishSpawnerService

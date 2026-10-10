--!strict
--[[
	BuildService — the tycoon build system.

	Players buy base items (security gate, walls, stairs, paths, lamps)
	from the Build tab and place them on a 12x12 tile grid covering their
	60x60 ground platform (5 studs per tile). The server validates every
	placement (ownership, bounds, occupancy, funds) — the client ghost is
	cosmetic only.

	Security Gate (Steal-a-Brainrot style): a laser barrier linked to the
	base lock. While the base is locked the barrier is solid for everyone
	except the plot owner (per-owner collision groups); unlocked, it opens.

	Build items persist in the profile (Data.BuildItems) and rebuild on
	claim/rejoin. PlotService calls RebuildPlot/ClearPlot.

	Expose: Init(dataService, plotService)
		RebuildPlot(player, plot)
		ClearPlot(plot)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BuildCatalog = require(Shared:WaitForChild("BuildCatalog"))
local Remotes = Shared:WaitForChild("Remotes")

local server = ServerScriptService:WaitForChild("StealAFish")
local Util = server:WaitForChild("Util")
local RateLimit = require(Util:WaitForChild("RateLimit"))

local RequestPlaceItemRemote = Remotes:WaitForChild("RequestPlaceItem") :: RemoteEvent
local PlaceItemResultRemote = Remotes:WaitForChild("PlaceItemResult") :: RemoteEvent
local BuildPlotInfoRemote = Remotes:WaitForChild("BuildPlotInfo") :: RemoteEvent
local RequestBuildAquariumRemote = Remotes:WaitForChild("RequestBuildAquarium") :: RemoteEvent
local BuildAquariumResultRemote = Remotes:WaitForChild("BuildAquariumResult") :: RemoteEvent

local BuildService = {}

local DataService: any = nil
local PlotService: any = nil

local TILE = 5
local GRID = 12 -- 12x12 tiles over the 60x60 platform
local PLATFORM_TOP = 2

local placeLimiter = RateLimit.new(10, 5)

-- plot -> { ["tx,tz"] = true }
local Occupancy: { [any]: { [string]: boolean } } = {}
-- plot -> { barrier parts }
local GateBarriers: { [any]: { BasePart } } = {}

-- Standard part factory.
local function mkPart(parent: Instance, name: string, size: Vector3, cf: CFrame,
	color: Color3, material: Enum.Material, canCollide: boolean): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = canCollide
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function tileKey(tx: number, tz: number): string
	return tx .. "," .. tz
end

-- Tiles that base furniture already occupies (tank row, fountain, spawn, sign).
local function reservedTiles(plot: any): { [string]: boolean }
	local L = plot.Layout
	local res: { [string]: boolean } = {}
	local function rect(tx0: number, tz0: number, tx1: number, tz1: number)
		for tx = tx0, tx1 do
			for tz = tz0, tz1 do
				res[tileKey(tx, tz)] = true
			end
		end
	end
	-- Tank row column (tanks + stands).
	if L.RiverDirX == -1 then
		rect(9, 0, 10, 11)
	else
		rect(1, 0, 2, 11)
	end
	rect(5, 5, 6, 6) -- fountain
	rect(5, 8, 6, 9) -- spawn pad
	if L.RiverDirX == -1 then
		rect(1, 1, 3, 3) -- sign (river-side corner)
	else
		rect(8, 1, 10, 3)
	end
	return res
end

local function footprintTiles(tx: number, tz: number, w: number, d: number): { string }
	local out: { string } = {}
	for x = tx, tx + w - 1 do
		for z = tz, tz + d - 1 do
			table.insert(out, tileKey(x, z))
		end
	end
	return out
end

-- Per-owner collision group so gate barriers block everyone but the owner.
local function ensureOwnerGroup(userId: number): string
	local gname = `Owner_{userId}`
	pcall(function()
		PhysicsService:RegisterCollisionGroup(gname)
	end)
	PhysicsService:CollisionGroupSetCollidable(gname, "Default", true)
	return gname
end

local function applyOwnerGroup(player: Player)
	local gname = ensureOwnerGroup(player.UserId)
	local char = player.Character
	if not char then
		return
	end
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = gname
		end
	end
	-- Catch accessories / parts added after spawn.
	char.DescendantAdded:Connect(function(d: Instance)
		if d:IsA("BasePart") then
			d.CollisionGroup = gname
		end
	end)
end

-- Builds the visual for one item. Returns the folder holding its parts.
local function buildVisual(plot: any, def: any, tx: number, tz: number, rot: number): Instance
	local L = plot.Layout
	local folder: Instance = L.Folder:FindFirstChild("BuildItems")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "BuildItems"
		folder.Parent = L.Folder
	end
	local w, d = def.SizeTiles[1], def.SizeTiles[2]
	if rot == 90 then
		w, d = d, w
	end
	local wx = L.Center.X - 30 + (tx + w / 2) * TILE
	local wz = L.Center.Z - 30 + (tz + d / 2) * TILE
	local itemFolder = Instance.new("Folder")
	itemFolder.Name = `Build_{def.Id}_{tx}_{tz}`
	itemFolder.Parent = folder

	if def.Id == "SecurityGate" then
		-- Two pillars + top beam + laser barrier between them.
		local alongX = w >= d
		local half = (if alongX then w else d) * TILE / 2
		local px = if alongX then wx - half else wx
		local pz = if alongX then wz else wz - half
		local qx = if alongX then wx + half else wx
		local qz = if alongX then wz else wz + half
		mkPart(itemFolder, "PillarA", Vector3.new(1.5, 8, 1.5),
			CFrame.new(px, PLATFORM_TOP + 4, pz),
			Color3.fromRGB(90, 95, 110), Enum.Material.Concrete, true)
		mkPart(itemFolder, "PillarB", Vector3.new(1.5, 8, 1.5),
			CFrame.new(qx, PLATFORM_TOP + 4, qz),
			Color3.fromRGB(90, 95, 110), Enum.Material.Concrete, true)
		local beamSize = if alongX then Vector3.new(w * TILE + 1.5, 1, 1.5)
			else Vector3.new(1.5, 1, d * TILE + 1.5)
		mkPart(itemFolder, "Beam", beamSize,
			CFrame.new(wx, PLATFORM_TOP + 8, wz),
			Color3.fromRGB(60, 65, 80), Enum.Material.Concrete, true)
		-- The barrier: solid for everyone but the owner while locked.
		local bname = `GatePlot_{L.Index}`
		pcall(function()
			PhysicsService:RegisterCollisionGroup(bname)
		end)
		PhysicsService:CollisionGroupSetCollidable(bname, "Default", true)
		if plot.Owner then
			local gname = ensureOwnerGroup(plot.Owner.UserId)
			PhysicsService:CollisionGroupSetCollidable(bname, gname, false)
		end
		local barSize = if alongX then Vector3.new(w * TILE, 5, 0.5)
			else Vector3.new(0.5, 5, d * TILE)
		local barrier = mkPart(itemFolder, "GateBarrier", barSize,
			CFrame.new(wx, PLATFORM_TOP + 2.5, wz),
			Color3.fromRGB(255, 60, 60), Enum.Material.Neon, false)
		barrier.Transparency = 0.85
		barrier.CollisionGroup = bname
		local list = GateBarriers[plot]
		if not list then
			list = {}
			GateBarriers[plot] = list
		end
		table.insert(list, barrier)
	elseif def.Id == "Wall" then
		local size = if w >= d then Vector3.new(w * TILE, 6, 1)
			else Vector3.new(1, 6, d * TILE)
		mkPart(itemFolder, "Wall", size,
			CFrame.new(wx, PLATFORM_TOP + 3, wz),
			Color3.fromRGB(125, 125, 135), Enum.Material.Concrete, true)
	elseif def.Id == "Stairs" then
		mkPart(itemFolder, "Step", Vector3.new(TILE, 2.5, TILE),
			CFrame.new(wx, PLATFORM_TOP + 1.25, wz),
			Color3.fromRGB(150, 150, 165), Enum.Material.Concrete, true)
	elseif def.Id == "PathTile" then
		mkPart(itemFolder, "Path", Vector3.new(TILE - 0.2, 0.2, TILE - 0.2),
			CFrame.new(wx, PLATFORM_TOP + 0.1, wz),
			Color3.fromRGB(70, 75, 90), Enum.Material.Slate, false)
	elseif def.Id == "LampPost" then
		mkPart(itemFolder, "Pole", Vector3.new(0.8, 6, 0.8),
			CFrame.new(wx, PLATFORM_TOP + 3, wz),
			Color3.fromRGB(50, 50, 60), Enum.Material.Metal, true)
		local head = mkPart(itemFolder, "Head", Vector3.new(2, 1, 2),
			CFrame.new(wx, PLATFORM_TOP + 6.5, wz),
			Color3.fromRGB(255, 230, 150), Enum.Material.Neon, false)
		head.Transparency = 0.2
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 220, 150)
		light.Range = 25
		light.Brightness = 2
		light.Parent = head
	end
	return itemFolder
end

-- Aquarium pavilion on a land tier's new ground. Fixed position, off to the
-- side of the tier's tank row. Decorative trophy shark inside.
local function buildAquariumVisual(plot: any, tier: number)
	local L = plot.Layout
	local folder: Instance = L.Folder:FindFirstChild("Aquariums")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Aquariums"
		folder.Parent = L.Folder
	end
	-- Position: same row as the tier's tanks (u = lotHalf + 20), offset in v.
	local lotHalf = 75 + tier * 30
	local u = lotHalf + 20
	local wx = L.Center.X + L.RiverDirX * -1 * (u - 30)
	local wz = L.Center.Z + 55
	local aq = Instance.new("Folder")
	aq.Name = `Aquarium_{tier}`
	aq.Parent = folder
	-- Base slab.
	mkPart(aq, "Base", Vector3.new(24, 1, 20), CFrame.new(wx, 0.5, wz),
		Color3.fromRGB(120, 120, 135), Enum.Material.Concrete, true)
	-- Corner pillars.
	for _, sx in { -11, 11 } do
		for _, sz in { -9, 9 } do
			mkPart(aq, "Pillar", Vector3.new(1.5, 9, 1.5),
				CFrame.new(wx + sx, 5.5, wz + sz),
				Color3.fromRGB(90, 95, 110), Enum.Material.Concrete, true)
		end
	end
	-- Glass walls.
	local glass = Color3.fromRGB(180, 220, 255)
	for _, sz in { -9.75, 9.75 } do
		local wall = mkPart(aq, "Glass", Vector3.new(22, 8, 0.5),
			CFrame.new(wx, 5, wz + sz), glass, Enum.Material.Glass, true)
		wall.Transparency = 0.6
	end
	for _, sx in { -11.75, 11.75 } do
		local wall = mkPart(aq, "Glass", Vector3.new(0.5, 8, 18),
			CFrame.new(wx + sx, 5, wz), glass, Enum.Material.Glass, true)
		wall.Transparency = 0.6
	end
	-- Roof.
	mkPart(aq, "Roof", Vector3.new(26, 1, 22), CFrame.new(wx, 10, wz),
		Color3.fromRGB(60, 65, 80), Enum.Material.Concrete, true)
	-- Central display tank (decorative).
	local tank = mkPart(aq, "DisplayTank", Vector3.new(10, 6, 8),
		CFrame.new(wx, 4, wz), glass, Enum.Material.Glass, false)
	tank.Transparency = 0.6
	local water = mkPart(aq, "DisplayWater", Vector3.new(9.4, 5, 7.4),
		CFrame.new(wx, 3.8, wz), Color3.fromRGB(40, 130, 210), Enum.Material.Water, false)
	water.Transparency = 0.35
	-- Sign.
	local sign = mkPart(aq, "Sign", Vector3.new(14, 3, 0.5),
		CFrame.new(wx, 8, wz - 10.2), Color3.fromRGB(30, 60, 90), Enum.Material.SmoothPlastic, false)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- faces the platform (-z)
	gui.CanvasSize = Vector2.new(400, 90)
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(150, 220, 255)
	label.Text = "AQUARIUM"
	label.Parent = gui
	print(`[BuildService] Aquarium built on plot {L.Index} tier {tier}`)
end

function BuildService.PlaceItem(player: Player, itemId: unknown, tx: unknown, tz: unknown, rot: unknown): (boolean, string)
	if typeof(itemId) ~= "string" then
		return false, "Bad item."
	end
	if typeof(tx) ~= "number" or typeof(tz) ~= "number" then
		return false, "Bad tile."
	end
	tx = math.floor(tx)
	tz = math.floor(tz)
	rot = if rot == 90 then 90 else 0
	if not placeLimiter:Check(player.UserId) then
		return false, "Slow down."
	end
	local plot = PlotService.GetPlot(player)
	if not plot then
		return false, "Claim a base first."
	end
	local def = BuildCatalog.Get(itemId)
	if not def then
		return false, "Unknown item."
	end
	local w, d = def.SizeTiles[1], def.SizeTiles[2]
	if rot == 90 then
		w, d = d, w
	end
	if tx < 0 or tz < 0 or tx + w > GRID or tz + d > GRID then
		return false, "Out of bounds."
	end
	local occ = Occupancy[plot]
	if not occ then
		occ = {}
		Occupancy[plot] = occ
	end
	local reserved = reservedTiles(plot)
	for _, key in footprintTiles(tx, tz, w, d) do
		if occ[key] or reserved[key] then
			return false, "Tile occupied."
		end
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "Data not loaded."
	end
	if (profile.Data.Coins or 0) < def.Price then
		return false, "Not enough coins."
	end
	profile.Data.Coins -= def.Price
	for _, key in footprintTiles(tx, tz, w, d) do
		occ[key] = true
	end
	if typeof(profile.Data.BuildItems) ~= "table" then
		profile.Data.BuildItems = {}
	end
	table.insert(profile.Data.BuildItems, { Id = itemId, TX = tx, TZ = tz, Rot = rot })
	buildVisual(plot, def, tx, tz, rot)
	print(`[BuildService] {player.Name} placed {itemId} at ({tx},{tz})`)
	return true, `{def.Name} placed!`
end

-- Buy + build an aquarium on an owned land tier. +20% global income each.
function BuildService.BuildAquarium(player: Player, tier: unknown): (boolean, string)
	if typeof(tier) ~= "number" or tier ~= math.floor(tier) or tier < 1 or tier > 3 then
		return false, "Bad tier."
	end
	if not placeLimiter:Check(player.UserId) then
		return false, "Slow down."
	end
	local plot = PlotService.GetPlot(player)
	if not plot then
		return false, "Claim a base first."
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "Data not loaded."
	end
	if (profile.Data.ExpansionTier or 0) < tier then
		return false, "Buy that land first."
	end
	if typeof(profile.Data.Aquariums) ~= "table" then
		profile.Data.Aquariums = {}
	end
	if profile.Data.Aquariums[tostring(tier)] then
		return false, "Aquarium already built."
	end
	if (profile.Data.Coins or 0) < Config.AquariumCost then
		return false, "Not enough coins."
	end
	profile.Data.Coins -= Config.AquariumCost
	profile.Data.Aquariums[tostring(tier)] = true
	buildAquariumVisual(plot, tier)
	print(`[BuildService] {player.Name} built aquarium tier {tier}`)
	return true, `Aquarium built! +{math.floor(Config.AquariumBonusPer * 100)}% income.`
end

-- Rebuild a player's saved items onto their (freshly claimed) plot.
function BuildService.RebuildPlot(player: Player, plot: any)
	BuildService.ClearPlot(plot)
	local profile = DataService.GetProfile(player)
	local items = profile and profile.Data.BuildItems
	if typeof(items) == "table" then
		for _, rec in items do
			if typeof(rec) == "table" then
				local def = BuildCatalog.Get(rec.Id)
				if def then
					local w, d = def.SizeTiles[1], def.SizeTiles[2]
					local rot = if rec.Rot == 90 then 90 else 0
					if rot == 90 then
						w, d = d, w
					end
					local occ = Occupancy[plot]
					if not occ then
						occ = {}
						Occupancy[plot] = occ
					end
					local blocked = false
					local reserved = reservedTiles(plot)
					for _, key in footprintTiles(rec.TX, rec.TZ, w, d) do
						if occ[key] or reserved[key] then
							blocked = true
							break
						end
					end
					if not blocked then
						for _, key in footprintTiles(rec.TX, rec.TZ, w, d) do
							occ[key] = true
						end
						buildVisual(plot, def, rec.TX, rec.TZ, rot)
					end
				end
			end
		end
	end
	-- Rebuild aquariums.
	local profile2 = DataService.GetProfile(player)
	local aqs = profile2 and profile2.Data.Aquariums
	if typeof(aqs) == "table" then
		for tierKey in aqs do
			local tier = tonumber(tierKey)
			if tier and tier >= 1 and tier <= 3 then
				local old = plot.Layout.Folder:FindFirstChild("Aquariums")
				local exists = old and old:FindFirstChild(`Aquarium_{tier}`)
				if not exists then
					buildAquariumVisual(plot, tier)
				end
			end
		end
	end
	-- Tell the client the platform rect for placement + owned land tier.
	local tier = (profile and profile.Data.ExpansionTier) or 0
	BuildPlotInfoRemote:FireClient(player, plot.Layout.Center.X, plot.Layout.Center.Z, tier)
end

function BuildService.ClearPlot(plot: any)
	Occupancy[plot] = nil
	GateBarriers[plot] = nil
	local folder = plot.Layout.Folder:FindFirstChild("BuildItems")
	if folder then
		folder:Destroy()
	end
	local aqs = plot.Layout.Folder:FindFirstChild("Aquariums")
	if aqs then
		aqs:Destroy()
	end
end

-- Sync gate barriers to the base lock state (called every second).
function BuildService.RefreshGates()
	for plot, barriers in GateBarriers do
		local locked = PlotService.IsLocked(plot)
		for _, b in barriers do
			if b and b.Parent then
				b.CanCollide = locked
				b.Transparency = if locked then 0.25 else 0.85
			end
		end
	end
end

function BuildService.Init(dataService: any, plotService: any)
	DataService = dataService
	PlotService = plotService

	-- Owner collision groups on spawn.
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function(_char: Model)
			if PlotService.GetPlot(player) then
				applyOwnerGroup(player)
			end
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(_char: Model)
			if PlotService.GetPlot(player) then
				applyOwnerGroup(player)
			end
		end)
	end

	RequestPlaceItemRemote.OnServerEvent:Connect(function(player: Player, itemId: unknown, tx: unknown, tz: unknown, rot: unknown)
		local ok, msg = BuildService.PlaceItem(player, itemId, tx, tz, rot)
		PlaceItemResultRemote:FireClient(player, ok, msg)
	end)
	RequestBuildAquariumRemote.OnServerEvent:Connect(function(player: Player, tier: unknown)
		local ok, msg = BuildService.BuildAquarium(player, tier)
		BuildAquariumResultRemote:FireClient(player, ok, msg)
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			BuildService.RefreshGates()
		end
	end)

	print("[BuildService] init")
end

return BuildService

--!strict
--[[
	WorldService — builds the entire Steal a Fish world in code (server-side).
	All geometry is procedural so the map lives in git, not in a binary place.

	Layout (studs, Y-up, river runs north→south along X=0):
	- Rock barrier ring at radius ~275 (20 segments) + invisible collision walls.
	- Pond built into the north rocks at (0, -230), waterfall feeding the river.
	- Central river: 30 wide, z=-200 to z=+215, bed+water recessed below grade
	  in a real channel cut through the ground (grass can't phase through it).
	- Sand banks run the FULL river length on both sides.
	- 8 plots (4 per bank) at x=±95, z in {-157,-52,52,157}. Each plot owns a
	  76x76 fenced lot with the 44x44 platform in the middle: room to expand
	  on every side. Ground floor built here; upper floors via BuildUpperFloor.
	- AFK cove: sandy disc south-east at (170, 195). Neutral spawn pad at (0, 248).
	- At Init, WORLD_Y is detected from the builder's own baseplate/terrain
	  and the whole world is lifted to sit on it (never buried).

	Exposes:
	  WorldService.Init() -> Layout
	  WorldService.BuildUpperFloor(plot, floorNum)
	Layout.Plots[i] = { Index, Center, Bank, Folder, SignLabel, SlotAnchors,
	                    FloorTopY, UpperBuilt }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local WorldService = {}

-- Vertical offset (studs) applied to the whole generated world at Init.
-- Detected from the builder's own baseplate/terrain so our world sits ON it
-- instead of assuming y=0 (a taller baseplate would bury every plot).
local WORLD_Y: number = 0

-- World layout constants (studs, pre-WORLD_Y lift).
local GROUND_HALF = 280 -- ground extends ±280 in X and Z
local RIVER_HALF_W = 15 -- water half-width; channel cut through the ground
local RIVER_Z0 = -200 -- river north end (tucks under the pond's south lip)
local RIVER_Z1 = 215 -- river south end
local BANK_W = 12 -- sand bank width on each river side
local PLOT_X = 95 -- plot center distance from the middle
local PLOT_LOT = 76 -- fenced lot size: room for the base to expand
local PLOT_PLATFORM = 44 -- built platform size
local PLOT_ZS = { -157, -52, 52, 157 }

export type PlotLayout = {
	Index: number,
	Center: Vector3,
	Bank: string, -- "East" | "West"
	Folder: Folder,
	SignLabel: TextLabel,
	SpawnLocation: SpawnLocation,
	SlotAnchors: { [number]: Vector3 }, -- [slotIndex] -> world pos of pedestal top
	FloorTopY: { [number]: number }, -- [floorNum] -> platform top Y
	UpperBuilt: { [number]: boolean },
	RiverDirX: number, -- -1 for east plots (river is -X), +1 for west plots
}

export type Layout = {
	Plots: { [number]: PlotLayout },
	RiverPath: { Vector3 },
	CoveCenter: Vector3,
	CoveRadius: number,
}

-- Standard part factory: anchored, configured, parented LAST.
local function mkPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	canCollide: boolean
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
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

local function buildGround(world: Folder)
	local grass = Color3.fromRGB(95, 160, 95)
	-- Two slabs with a channel left open for the river: there is no ground
	-- under the river, so grass can never phase through the water.
	for _, side in { -1, 1 } do
		local w = GROUND_HALF - RIVER_HALF_W
		local cx = side * (RIVER_HALF_W + w / 2)
		mkPart(world, if side < 0 then "GroundW" else "GroundE",
			Vector3.new(w, 2, GROUND_HALF * 2),
			CFrame.new(cx, -1, 0),
			grass, Enum.Material.Grass, true)
	end
end

local function buildRockBarrier(world: Folder)
	local folder = Instance.new("Folder")
	folder.Name = "RockBarrier"
	folder.Parent = world

	local rockColor = Color3.fromRGB(112, 102, 96)
	local rockDark = Color3.fromRGB(88, 80, 76)
	local segments = 20
	local radius = 278

	for i = 0, segments - 1 do
		local angle = (i / segments) * math.pi * 2
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius
		-- Deterministic pseudo-variation so the ring doesn't look stamped.
		local h = 52 + ((i * 37) % 17)
		local w = 86 + ((i * 53) % 13)

		local seg = mkPart(
			folder,
			`Rock_{i}`,
			Vector3.new(w, h, 26),
			CFrame.new(x, h / 2 - 2, z) * CFrame.Angles(0, -angle + math.pi / 2, 0),
			if i % 2 == 0 then rockColor else rockDark,
			Enum.Material.Rock,
			true
		)
		seg.CanQuery = true -- rocks block raycasts (camera collision)

		-- Cap rock: smaller boulder on top for silhouette variety.
		mkPart(
			folder,
			`RockCap_{i}`,
			Vector3.new(w * 0.55, 14, 18),
			seg.CFrame * CFrame.new(0, h / 2 + 5, 0) * CFrame.Angles(0, (i * 0.7) % 1.2, 0),
			rockDark,
			Enum.Material.Rock,
			true
		)
	end

	-- Invisible collision walls just inside the rocks: nothing escapes, ever.
	local wallFolder = Instance.new("Folder")
	wallFolder.Name = "InvisibleWalls"
	wallFolder.Parent = world
	local ext = 258
	local wallH = 70
	mkPart(wallFolder, "WallN", Vector3.new(ext * 2 + 4, wallH, 2),
		CFrame.new(0, wallH / 2, -ext), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, true)
	mkPart(wallFolder, "WallS", Vector3.new(ext * 2 + 4, wallH, 2),
		CFrame.new(0, wallH / 2, ext), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, true)
	mkPart(wallFolder, "WallW", Vector3.new(2, wallH, ext * 2 + 4),
		CFrame.new(-ext, wallH / 2, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, true)
	mkPart(wallFolder, "WallE", Vector3.new(2, wallH, ext * 2 + 4),
		CFrame.new(ext, wallH / 2, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, true)
	for _, wall in wallFolder:GetChildren() do
		if wall:IsA("BasePart") then
			wall.Transparency = 1
		end
	end
end

local function buildPondAndWaterfall(world: Folder)
	local folder = Instance.new("Folder")
	folder.Name = "Pond"
	folder.Parent = world

	local pondCenter = Vector3.new(0, 0, -230)

	-- Sand bed under the pond (cylinder axis is X; rotate to lie flat).
	local bed = Instance.new("Part")
	bed.Name = "PondBed"
	bed.Shape = Enum.PartType.Cylinder
	bed.Size = Vector3.new(2, 82, 82)
	bed.CFrame = CFrame.new(pondCenter.X, 0.1, pondCenter.Z) * CFrame.Angles(0, 0, math.pi / 2)
	bed.Color = Color3.fromRGB(215, 195, 145)
	bed.Material = Enum.Material.Sand
	bed.Anchored = true
	bed.CanCollide = false
	bed.CanTouch = false
	bed.CanQuery = false
	bed.TopSurface = Enum.SurfaceType.Smooth
	bed.BottomSurface = Enum.SurfaceType.Smooth
	bed.Parent = folder

	-- Water disc (rotated flat like the bed).
	local water = Instance.new("Part")
	water.Name = "PondWater"
	water.Shape = Enum.PartType.Cylinder
	water.Size = Vector3.new(1.2, 68, 68)
	water.CFrame = CFrame.new(pondCenter.X, 0.35, pondCenter.Z) * CFrame.Angles(0, 0, math.pi / 2)
	water.Color = Color3.fromRGB(35, 130, 210)
	water.Material = Enum.Material.Water
	water.Transparency = 0.15
	water.Anchored = true
	water.CanCollide = false
	water.CanTouch = false
	water.CanQuery = false
	water.TopSurface = Enum.SurfaceType.Smooth
	water.BottomSurface = Enum.SurfaceType.Smooth
	water.Parent = folder

	-- Cliff the waterfall pours over (north edge, against the rocks).
	mkPart(folder, "FallCliff", Vector3.new(46, 34, 12),
		CFrame.new(0, 17, -262), Color3.fromRGB(105, 98, 92), Enum.Material.Rock, true)

	-- The falls: white-blue sheet.
	local falls = mkPart(folder, "Waterfall", Vector3.new(14, 30, 1.6),
		CFrame.new(0, 15, -255), Color3.fromRGB(200, 235, 255), Enum.Material.Water, false)
	falls.Transparency = 0.25

	-- Foam chunks at the base.
	for i = -1, 1 do
		local foam = mkPart(folder, `Foam_{i}`, Vector3.new(5, 1.5, 5),
			CFrame.new(i * 6, 0.8, -246), Color3.fromRGB(240, 250, 255),
			Enum.Material.SmoothPlastic, false)
		foam.Transparency = 0.3
	end
end

local function buildRiver(world: Folder): { Vector3 }
	local folder = Instance.new("Folder")
	folder.Name = "River"
	folder.Parent = world

	local zLen = RIVER_Z1 - RIVER_Z0
	local zMid = (RIVER_Z0 + RIVER_Z1) / 2

	-- Riverbed: recessed below grade so the channel reads as dug in.
	mkPart(folder, "Riverbed", Vector3.new(RIVER_HALF_W * 2 + 4, 1, zLen),
		CFrame.new(0, -2.5, zMid), Color3.fromRGB(170, 155, 115), Enum.Material.Sand, false)

	-- Water surface: below grass level, so no phasing is possible.
	local water = mkPart(folder, "RiverWater", Vector3.new(RIVER_HALF_W * 2, 1, zLen),
		CFrame.new(0, -1, zMid), Color3.fromRGB(35, 130, 210), Enum.Material.Water, false)
	water.Transparency = 0.12

	-- Dirt lining on the channel's cut faces (overlaps the banks slightly so
	-- no two faces are coplanar: never any z-fighting).
	for _, side in { -1, 1 } do
		mkPart(folder, if side < 0 then "ChannelW" else "ChannelE",
			Vector3.new(1.5, 2, zLen),
			CFrame.new(side * (RIVER_HALF_W + 0.75), -1, zMid),
			Color3.fromRGB(134, 96, 67), Enum.Material.Ground, false)
	end

	-- Sand riverbank running the FULL length of the river on both sides,
	-- sitting slightly proud of the grass.
	for _, side in { -1, 1 } do
		mkPart(folder, if side < 0 then "BankW" else "BankE",
			Vector3.new(BANK_W, 1.5, zLen),
			CFrame.new(side * (RIVER_HALF_W + BANK_W / 2), -0.4, zMid),
			Color3.fromRGB(220, 200, 150), Enum.Material.Sand, true)
	end

	-- The conveyor path: waterfall base -> gentle S-curve -> south end.
	-- Fish ride just above the water surface (water top is y=-0.5).
	return {
		Vector3.new(0, 0.25 + WORLD_Y, RIVER_Z0 + 24),
		Vector3.new(3, 0.25 + WORLD_Y, -80),
		Vector3.new(-3, 0.25 + WORLD_Y, -20),
		Vector3.new(3, 0.25 + WORLD_Y, 40),
		Vector3.new(-2, 0.25 + WORLD_Y, 100),
		Vector3.new(0, 0.25 + WORLD_Y, RIVER_Z1 - 20),
	}
end

-- Slot anchor math (shared by pedestal building + logic).
-- slotIndex: 1-12 ground, 13-20 floor 2, 21-28 floor 3.
local function slotLocal(slotIndex: number): (number, number, number)
	-- returns (floorNum, u [away from river], v [along river])
	if slotIndex <= Config.SlotsPerPlot then
		local t = math.floor((slotIndex - 1) / 4) -- row 0..2
		local p = (slotIndex - 1) % 4 -- col 0..3
		return 1, 8 + t * 12, -16.5 + p * 11
	elseif slotIndex <= Config.SlotsPerPlot + Config.Floor2Slots then
		local i = slotIndex - Config.SlotsPerPlot - 1
		local t = math.floor(i / 4)
		local p = i % 4
		return 2, 10 + t * 14, -16.5 + p * 11
	else
		local i = slotIndex - Config.SlotsPerPlot - Config.Floor2Slots - 1
		local t = math.floor(i / 4)
		local p = i % 4
		return 3, 10 + t * 14, -16.5 + p * 11
	end
end

local function slotWorld(plotCenter: Vector3, riverDirX: number, floorTopY: { [number]: number }, slotIndex: number): Vector3
	local floorNum, u, v = slotLocal(slotIndex)
	-- East plots (center +44): river is -X, so u extends +X. West: mirrored.
	local x = plotCenter.X + riverDirX * -1 * (u - 22) -- u measured from river edge (plot edge at 22 from center)
	local y = floorTopY[floorNum] + 3.2 -- pedestal top
	return Vector3.new(x, y, plotCenter.Z + v)
end

local function buildStairs(parent: Instance, base: Vector3, dirV: number, width: number, rise: number, steps: number)
	-- Straight staircase rising `rise` studs over `steps` steps, running in +V or -V.
	local runPer = 1.6
	for s = 1, steps do
		mkPart(parent, `Stair_{s}`, Vector3.new(width, 1, runPer + 0.2),
			CFrame.new(base.X, base.Y + (s - 0.5) * (rise / steps), base.Z + dirV * (s - 0.5) * runPer),
			Color3.fromRGB(150, 140, 130), Enum.Material.WoodPlanks, true)
	end
end

local function buildPlot(world: Folder, index: number, centerX: number, centerZ: number, bank: string): PlotLayout
	local folder = Instance.new("Folder")
	folder.Name = `Plot{index}`
	folder.Parent = world

	local center = Vector3.new(centerX, WORLD_Y, centerZ)
	local riverDirX = if bank == "East" then -1 else 1 -- direction FROM plot TO river

	-- Main platform (top at y=2), centered in the lot.
	mkPart(folder, "Platform", Vector3.new(PLOT_PLATFORM, 2, PLOT_PLATFORM),
		CFrame.new(centerX, 1, centerZ), Color3.fromRGB(178, 178, 190), Enum.Material.SmoothPlastic, true)
	-- Trim slab.
	mkPart(folder, "Trim", Vector3.new(PLOT_PLATFORM + 2, 1, PLOT_PLATFORM + 2),
		CFrame.new(centerX, 0.5, centerZ), Color3.fromRGB(120, 120, 135), Enum.Material.SmoothPlastic, true)

	-- Fences at the LOT boundary (76x76): the 44x44 platform sits in the
	-- middle with room to expand on every side. River side stays open
	-- as the entrance; fences sit on grass (y 0..4).
	local fenceColor = Color3.fromRGB(140, 105, 72)
	local halfLot = PLOT_LOT / 2
	-- North / south fences (along X at z edges).
	mkPart(folder, "FenceN", Vector3.new(PLOT_LOT, 4, 1),
		CFrame.new(centerX, 2, centerZ - halfLot + 0.5), fenceColor, Enum.Material.WoodPlanks, true)
	mkPart(folder, "FenceS", Vector3.new(PLOT_LOT, 4, 1),
		CFrame.new(centerX, 2, centerZ + halfLot - 0.5), fenceColor, Enum.Material.WoodPlanks, true)
	-- Back fence (away from river) with an 8-stud gap in the middle = land approach.
	local backX = centerX + (if bank == "East" then halfLot - 0.5 else -(halfLot - 0.5))
	local backSegLen = (PLOT_LOT - 8) / 2
	local backSegOff = 4 + backSegLen / 2
	mkPart(folder, "FenceBackA", Vector3.new(1, 4, backSegLen),
		CFrame.new(backX, 2, centerZ - backSegOff), fenceColor, Enum.Material.WoodPlanks, true)
	mkPart(folder, "FenceBackB", Vector3.new(1, 4, backSegLen),
		CFrame.new(backX, 2, centerZ + backSegOff), fenceColor, Enum.Material.WoodPlanks, true)

	-- Sign post + board at the river-side corner.
	local signX = centerX + (if bank == "East" then -19 else 19)
	mkPart(folder, "SignPost", Vector3.new(1.5, 7, 1.5),
		CFrame.new(signX, 5.5, centerZ - 18), fenceColor, Enum.Material.WoodPlanks, true)
	local board = mkPart(folder, "SignBoard", Vector3.new(12, 5, 1),
		CFrame.new(signX, 10, centerZ - 18), Color3.fromRGB(90, 65, 45), Enum.Material.WoodPlanks, true)
	-- Face the board toward the river.
	board.CFrame = CFrame.new(signX, 10, centerZ - 18)
		* CFrame.Angles(0, if bank == "East" then -math.pi / 2 else math.pi / 2, 0)

	local signGui = Instance.new("SurfaceGui")
	signGui.Name = "SignGui"
	signGui.Face = Enum.NormalId.Front
	signGui.CanvasSize = Vector2.new(400, 170)
	signGui.Parent = board
	local signLabel = Instance.new("TextLabel")
	signLabel.Name = "Title"
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.BackgroundTransparency = 1
	signLabel.Font = Enum.Font.GothamBlack
	signLabel.TextScaled = true
	signLabel.TextColor3 = Color3.fromRGB(255, 240, 210)
	signLabel.TextStrokeTransparency = 0.5
	signLabel.Text = "UNCLAIMED"
	signLabel.Parent = signGui

	-- SpawnLocation on the plot (disabled until claimed; PlotService enables).
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlotSpawn"
	spawn.Size = Vector3.new(8, 2, 8)
	spawn.CFrame = CFrame.new(centerX, 3, centerZ + 14)
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Enabled = false
	spawn.Neutral = false
	spawn.AllowTeamChangeOnTouch = false
	spawn.Parent = folder

	local floorTopY = { [1] = 2 + WORLD_Y, [2] = 14 + WORLD_Y, [3] = 26 + WORLD_Y }

	-- Slot anchors for all 28 slots (upper floors' anchors valid once built).
	local anchors: { [number]: Vector3 } = {}
	local totalSlots = Config.SlotsPerPlot + Config.Floor2Slots + Config.Floor3Slots
	for i = 1, totalSlots do
		anchors[i] = slotWorld(Vector3.new(centerX, 0, centerZ), riverDirX, floorTopY, i)
	end

	-- Ground-floor slot pedestals now; upper floors' come with BuildUpperFloor.
	for i = 1, Config.SlotsPerPlot do
		WorldService._buildPedestal(folder, anchors[i], i)
	end

	return {
		Index = index,
		Center = center,
		Bank = bank,
		Folder = folder,
		SignLabel = signLabel,
		SpawnLocation = spawn,
		SlotAnchors = anchors,
		FloorTopY = floorTopY,
		UpperBuilt = { [2] = false, [3] = false },
		RiverDirX = riverDirX,
	}
end

-- Pedestal: squat cylinder + glass tank. Fish floats inside the tank.
-- (Cylinder axis is X; rotate Z by 90° to stand upright.)
function WorldService._buildPedestal(parent: Instance, anchor: Vector3, slotIndex: number)
	local base = Instance.new("Part")
	base.Name = `Pedestal_{slotIndex}`
	base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(5.5, 5, 5)
	base.CFrame = CFrame.new(anchor.X, anchor.Y - 2.75, anchor.Z) * CFrame.Angles(0, 0, math.pi / 2)
	base.Color = Color3.fromRGB(100, 110, 125)
	base.Material = Enum.Material.SmoothPlastic
	base.Anchored = true
	base.CanCollide = true
	base.CanTouch = false
	base.CanQuery = false
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	base.Parent = parent

	-- Glass tank.
	local tank = Instance.new("Part")
	tank.Name = `Tank_{slotIndex}`
	tank.Size = Vector3.new(5, 4, 5)
	tank.CFrame = CFrame.new(anchor.X, anchor.Y + 2, anchor.Z)
	tank.Color = Color3.fromRGB(180, 220, 255)
	tank.Transparency = 0.65
	tank.Material = Enum.Material.Glass
	tank.Anchored = true
	tank.CanCollide = false
	tank.CanTouch = false
	tank.CanQuery = false
	tank.TopSurface = Enum.SurfaceType.Smooth
	tank.BottomSurface = Enum.SurfaceType.Smooth
	tank.Parent = parent

	-- Water inside the tank.
	local water = Instance.new("Part")
	water.Name = `TankWater_{slotIndex}`
	water.Size = Vector3.new(4.4, 3.2, 4.4)
	water.CFrame = CFrame.new(anchor.X, anchor.Y + 1.8, anchor.Z)
	water.Color = Color3.fromRGB(40, 130, 210)
	water.Transparency = 0.35
	water.Material = Enum.Material.Water
	water.Anchored = true
	water.CanCollide = false
	water.CanTouch = false
	water.CanQuery = false
	water.TopSurface = Enum.SurfaceType.Smooth
	water.BottomSurface = Enum.SurfaceType.Smooth
	water.Parent = parent
end

-- Builds an upper floor: platform, pillars, railings, stairs, slot pedestals.
function WorldService.BuildUpperFloor(plot: PlotLayout, floorNum: number)
	assert(floorNum == 2 or floorNum == 3, `bad floor {floorNum}`)
	if plot.UpperBuilt[floorNum] then
		return
	end
	plot.UpperBuilt[floorNum] = true

	local folder = plot.Folder
	local cx, cz = plot.Center.X, plot.Center.Z
	local topY = plot.FloorTopY[floorNum] -- 14 or 26
	local baseColor = Color3.fromRGB(168, 168, 182)

	-- Platform.
	mkPart(folder, `Platform_F{floorNum}`, Vector3.new(44, 2, 44),
		CFrame.new(cx, topY - 1, cz), baseColor, Enum.Material.SmoothPlastic, true)

	-- Corner pillars down to the floor below.
	local belowTop = plot.FloorTopY[floorNum - 1]
	local pillarH = topY - 2 - belowTop
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			mkPart(folder, `Pillar_F{floorNum}_{sx}_{sz}`, Vector3.new(2, pillarH, 2),
				CFrame.new(cx + sx * 20, belowTop + pillarH / 2, cz + sz * 20),
				Color3.fromRGB(120, 120, 135), Enum.Material.SmoothPlastic, true)
		end
	end

	-- Railings (3 tall) on all sides except the stair opening (back edge).
	local railColor = Color3.fromRGB(140, 105, 72)
	mkPart(folder, `RailN_F{floorNum}`, Vector3.new(44, 3, 1),
		CFrame.new(cx, topY + 1.5, cz - 21.5), railColor, Enum.Material.WoodPlanks, true)
	mkPart(folder, `RailS_F{floorNum}`, Vector3.new(44, 3, 1),
		CFrame.new(cx, topY + 1.5, cz + 21.5), railColor, Enum.Material.WoodPlanks, true)
	local riverX = cx + plot.RiverDirX * 21.5
	mkPart(folder, `RailRiver_F{floorNum}`, Vector3.new(1, 3, 44),
		CFrame.new(riverX, topY + 1.5, cz), railColor, Enum.Material.WoodPlanks, true)
	-- Back railing split for the stair opening (8-stud gap in the middle).
	local backX = cx - plot.RiverDirX * 21.5
	mkPart(folder, `RailBackA_F{floorNum}`, Vector3.new(1, 3, 18),
		CFrame.new(backX, topY + 1.5, cz - 13), railColor, Enum.Material.WoodPlanks, true)
	mkPart(folder, `RailBackB_F{floorNum}`, Vector3.new(1, 3, 18),
		CFrame.new(backX, topY + 1.5, cz + 13), railColor, Enum.Material.WoodPlanks, true)

	-- Stairs from the floor below to this one, along the back edge.
	local stairBaseY = belowTop
	local stairX = backX - plot.RiverDirX * 3 -- just inside the back edge
	buildStairs(folder, Vector3.new(stairX, stairBaseY, cz - 8), 1, 6, topY - belowTop, 12)

	-- Slot pedestals for this floor.
	local startSlot = if floorNum == 2
		then Config.SlotsPerPlot + 1
		else Config.SlotsPerPlot + Config.Floor2Slots + 1
	local endSlot = if floorNum == 2
		then Config.SlotsPerPlot + Config.Floor2Slots
		else Config.SlotsPerPlot + Config.Floor2Slots + Config.Floor3Slots
	for i = startSlot, endSlot do
		WorldService._buildPedestal(folder, plot.SlotAnchors[i], i)
	end

	print(`[WorldService] Plot {plot.Index} floor {floorNum} built`)
end

local function buildCove(world: Folder): (Vector3, number)
	local folder = Instance.new("Folder")
	folder.Name = "AfkCove"
	folder.Parent = world

	local center = Vector3.new(170, WORLD_Y, 195)
	local radius = 17

	local disc = Instance.new("Part")
	disc.Name = "CoveDisc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(1, radius * 2, radius * 2)
	disc.CFrame = CFrame.new(center.X, 0.25, center.Z) * CFrame.Angles(0, 0, math.pi / 2)
	disc.Color = Color3.fromRGB(235, 215, 165)
	disc.Material = Enum.Material.Sand
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanTouch = false
	disc.CanQuery = false
	disc.TopSurface = Enum.SurfaceType.Smooth
	disc.BottomSurface = Enum.SurfaceType.Smooth
	disc.Parent = folder

	-- Palm-ish decor: trunk + leaf ball (cheap, no meshes).
	mkPart(folder, "PalmTrunk", Vector3.new(2, 14, 2),
		CFrame.new(center.X + 10, 7, center.Z + 8) * CFrame.Angles(0, 0, 0.15),
		Color3.fromRGB(130, 95, 60), Enum.Material.Wood, true)
	local leaves = mkPart(folder, "PalmLeaves", Vector3.new(10, 4, 10),
		CFrame.new(center.X + 11.2, 15, center.Z + 8),
		Color3.fromRGB(70, 160, 70), Enum.Material.Grass, false)
	leaves.Shape = Enum.PartType.Ball

	-- Sign.
	mkPart(folder, "CoveSignPost", Vector3.new(1.5, 7, 1.5),
		CFrame.new(center.X - 12, 3.5, center.Z - 10), Color3.fromRGB(140, 105, 72),
		Enum.Material.WoodPlanks, true)
	local board = mkPart(folder, "CoveSign", Vector3.new(14, 5, 1),
		CFrame.new(center.X - 12, 8, center.Z - 10), Color3.fromRGB(90, 65, 45),
		Enum.Material.WoodPlanks, true)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(460, 170)
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 240, 210)
	label.TextStrokeTransparency = 0.5
	label.Text = "AFK COVE\n+25% income here"
	label.Parent = gui

	return center, radius
end

local function buildSpawnPad(world: Folder): Vector3
	local pos = Vector3.new(0, 0, 248)
	mkPart(world, "SpawnPad", Vector3.new(26, 2, 26),
		CFrame.new(pos.X, 1, pos.Z), Color3.fromRGB(150, 150, 165),
		Enum.Material.SmoothPlastic, true)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "NeutralSpawn"
	spawn.Size = Vector3.new(20, 2, 20)
	spawn.CFrame = CFrame.new(pos.X, 2.5, pos.Z)
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Enabled = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0
	spawn.Parent = world
	return pos
end

function WorldService.Init(): Layout
	-- The stock Baseplate template ships a SpawnLocation that would compete
	-- with our NeutralSpawn (players could spawn in the river). Ours is built
	-- below, so remove any pre-existing ones first.
	for _, d in workspace:GetDescendants() do
		if d:IsA("SpawnLocation") then
			d:Destroy()
		end
	end

	-- Detect the builder's own ground (baseplate/terrain top) BEFORE building:
	-- nothing of ours exists yet, so the first hit from above is their surface.
	-- Our world is then lifted to sit on it instead of assuming y=0.
	local groundHit = workspace:Raycast(Vector3.new(0, 2000, 0), Vector3.new(0, -4000, 0))
	if groundHit then
		WORLD_Y = groundHit.Position.Y + 0.05
	else
		WORLD_Y = 0
	end

	local world = Instance.new("Folder")
	world.Name = "StealAFishWorld"
	world.Parent = workspace

	buildGround(world)
	buildRockBarrier(world)
	buildPondAndWaterfall(world)
	local riverPath = buildRiver(world)
	local coveCenter, coveRadius = buildCove(world)
	buildSpawnPad(world)

	-- Plots: 4 per bank, mirrored z positions, spread out with room to expand.
	local plots: { [number]: PlotLayout } = {}
	local index = 0
	for _, z in PLOT_ZS do
		index += 1
		plots[index] = buildPlot(world, index, -PLOT_X, z, "West")
	end
	for _, z in PLOT_ZS do
		index += 1
		plots[index] = buildPlot(world, index, PLOT_X, z, "East")
	end

	print("[WorldService] world built: 8 plots, river, pond, cove")

	-- Lift every generated part onto the detected ground. (Layout values
	-- already include WORLD_Y at their construction sites above.)
	if WORLD_Y ~= 0 then
		local lift = Vector3.new(0, WORLD_Y, 0)
		for _, d in world:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = d.CFrame + lift
			end
		end
	end

	return {
		Plots = plots,
		RiverPath = riverPath,
		CoveCenter = coveCenter,
		CoveRadius = coveRadius,
	}
end

return WorldService

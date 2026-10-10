--!strict
--[[
	WorldService — builds the map.

	Owns: grass ground (1400x1400), rock/mountain barrier ring around the
	outside. Built on the baseplate — we don't destroy it, we build on it.

	Exposes:
	- Init() -> Layout
]]

local WorldService = {}

export type Layout = {
	Center: Vector3,
	MapHalf: number, -- 700 (1400x1400 play area)
	Folder: Folder, -- "StealAFishWorld" in Workspace
}

local MAP_HALF = 700
local WORLD_Y = 0.2 -- top of the grass; sits just above the baseplate (y=0) to avoid z-fighting

local function mkPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	canCollide: boolean
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = canCollide
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- 1400x1400 grass slab on top of the baseplate.
local function buildGrass(world: Folder)
	mkPart(
		world,
		"Grass",
		Vector3.new(MAP_HALF * 2, 2, MAP_HALF * 2),
		CFrame.new(0, WORLD_Y - 1, 0),
		Color3.fromRGB(85, 170, 85),
		Enum.Material.Grass,
		true
	)
end

-- Mountain barrier: invisible solid wall (collision) + jagged mountain
-- visuals on top. Looks like a natural range, but no one gets through.
local function buildRockBarrier(world: Folder)
	local rng = Random.new(12345) -- fixed seed: same mountains every server
	local rockColor = Color3.fromRGB(110, 110, 115)
	local darkRock = Color3.fromRGB(85, 85, 90)
	local mossRock = Color3.fromRGB(95, 120, 90)

	-- INVISIBLE WALL: the real barrier. 50 tall, no gaps.
	local wallH = 50
	local wallT = 8
	local ext = MAP_HALF + 4
	for _, cfg in {
		{ size = Vector3.new(ext * 2, wallH, wallT), pos = Vector3.new(0, WORLD_Y + wallH / 2, -MAP_HALF) },
		{ size = Vector3.new(ext * 2, wallH, wallT), pos = Vector3.new(0, WORLD_Y + wallH / 2, MAP_HALF) },
		{ size = Vector3.new(wallT, wallH, ext * 2), pos = Vector3.new(-MAP_HALF, WORLD_Y + wallH / 2, 0) },
		{ size = Vector3.new(wallT, wallH, ext * 2), pos = Vector3.new(MAP_HALF, WORLD_Y + wallH / 2, 0) },
	} do
		local wall = mkPart(world, "BarrierWall", cfg.size, CFrame.new(cfg.pos),
			darkRock, Enum.Material.Rock, true)
		wall.Transparency = 1 -- invisible; mountains below are the visual
	end

	-- MOUNTAIN RIDGE: wide overlapping segments forming a SOLID wall.
	-- Each segment overlaps the next by 30+ studs — no see-through gaps.
	-- Varying height and tilt so it looks like mountains, not boxes.
	local function mountainRange(half: number, count: number)
		local perimeter = half * 8 -- total length around the square
		local segW = perimeter / count -- width per segment
		for i = 1, count do
			local t = (i - 1) / count * 4
			local side = math.floor(t)
			local f = t - side
			local x, z: number
			if side == 0 then
				x, z = -half + f * half * 2, -half
			elseif side == 1 then
				x, z = half, -half + f * half * 2
			elseif side == 2 then
				x, z = half - f * half * 2, half
			else
				x, z = -half, half - f * half * 2
			end

			-- Wide segment with heavy overlap.
			local w = segW * 1.8 -- 80% overlap with neighbors
			local h = rng:NextNumber(45, 75)
			local d = rng:NextNumber(20, 35)
			mkPart(world, "Mountain",
				Vector3.new(w, h, d),
				CFrame.new(
					x + rng:NextNumber(-8, 8),
					WORLD_Y + h / 2 - 5,
					z + rng:NextNumber(-8, 8))
					* CFrame.Angles(
						rng:NextNumber(-0.1, 0.1),
						rng:NextNumber(-0.3, 0.3),
						rng:NextNumber(-0.08, 0.08)),
				if rng:NextNumber() < 0.3 then mossRock
				elseif rng:NextNumber() < 0.5 then darkRock
				else rockColor,
				Enum.Material.Rock, true)

			-- Jagged peak on top for silhouette.
			local peakW = w * rng:NextNumber(0.3, 0.5)
			local peakH = rng:NextNumber(15, 30)
			mkPart(world, "Mountain",
				Vector3.new(peakW, peakH, d * 0.8),
				CFrame.new(
					x + rng:NextNumber(-w * 0.2, w * 0.2),
					WORLD_Y + h - 5 + peakH / 2,
					z + rng:NextNumber(-5, 5))
					* CFrame.Angles(
						rng:NextNumber(-0.15, 0.15),
						rng:NextNumber(0, math.pi * 2),
						rng:NextNumber(-0.15, 0.15)),
				darkRock, Enum.Material.Rock, true)
		end
	end

	-- Dense overlapping ridge on the wall line.
	mountainRange(MAP_HALF + 2, 40)
	-- Backdrop giants further out for depth.
	mountainRange(MAP_HALF + 100, 20)
		for i = 1, count do
			-- Walk the perimeter of the square.
			local t = (i - 1) / count * 4
			local side = math.floor(t)
			local f = t - side -- 0..1 along this side
			local x, z: number
			if side == 0 then
				x, z = -half + f * half * 2, -half
			elseif side == 1 then
				x, z = half, -half + f * half * 2
			elseif side == 2 then
				x, z = half - f * half * 2, half
			else
				x, z = -half, half - f * half * 2
			end
			-- Jitter so it doesn't look like a perfect square.
			x += rng:NextNumber(-25, 25)
			z += rng:NextNumber(-25, 25)
			local s = rng:NextNumber(minS, maxS)
			local h = s * rng:NextNumber(1.2, 2.2)
			mkPart(
				world,
				"Rock",
				Vector3.new(s, h, s * rng:NextNumber(0.8, 1.2)),
				CFrame.new(x, yBase + h / 2 - 2, z)
					* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				if rng:NextNumber() < 0.5 then rockColor else darkRock,
				Enum.Material.Rock,
				true
			)
		end
	end

function WorldService.Init(): Layout
	-- Idempotent: clear any previous world (hot-reload safety).
	local oldWorld = workspace:FindFirstChild("StealAFishWorld")
	if oldWorld then
		oldWorld:Destroy()
	end

	local world = Instance.new("Folder")
	world.Name = "StealAFishWorld"
	world.Parent = workspace

	buildGrass(world)
	buildRockBarrier(world)

	print("[WorldService] World built: 1400x1400 grass + rock ring.")
	return {
		Center = Vector3.new(0, 0, 0),
		MapHalf = MAP_HALF,
		Folder = world,
	}
end

return WorldService

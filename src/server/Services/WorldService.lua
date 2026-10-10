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

-- Rock/mountain ring around the outside. Two layers for depth:
-- inner boulders + outer peaks. Same style as the last map.
local function buildRockBarrier(world: Folder)
	local rng = Random.new(12345) -- fixed seed: same mountains every server
	local rockColor = Color3.fromRGB(110, 110, 115)
	local darkRock = Color3.fromRGB(85, 85, 90)

	local function rockRing(half: number, count: number, minS: number, maxS: number, yBase: number)
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

	-- Inner boulders (playable boundary).
	rockRing(MAP_HALF + 15, 48, 18, 35, WORLD_Y)
	-- Outer peaks (backdrop mountains).
	rockRing(MAP_HALF + 90, 32, 40, 80, WORLD_Y)
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

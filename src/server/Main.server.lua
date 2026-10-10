--!strict
--[[
	Main.server — server entry point. Requires services in dependency order
	and boots them. Services live in src/server/Services/.

	Boot order:
	  1. DataService (profiles, sessions)
	  2. WorldService (builds the map, returns layout)
	  3. PlotService (claims, slots, tycoon)
	  4. BuildService (placement, gates)
	  5. StealService (steal validation, carry)
	  6. FishSpawnerService (river conveyor)
	  7. IncomeService (money tick)

	Dependencies are wired via Set* methods after Init, so services never
	require each other at module scope (no circular requires).
]]

local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local server = ServerScriptService:WaitForChild("StealAFish")
local Services = server:WaitForChild("Services")

local DataService = require(Services:WaitForChild("DataService"))
local WorldService = require(Services:WaitForChild("WorldService"))
local PlotService = require(Services:WaitForChild("PlotService"))
local BuildService = require(Services:WaitForChild("BuildService"))
local StealService = require(Services:WaitForChild("StealService"))
local FishSpawnerService = require(Services:WaitForChild("FishSpawnerService"))
local IncomeService = require(Services:WaitForChild("IncomeService"))

DataService.Init()
local layout = WorldService.Init()

-- Fast walk for world testing (Nathan). Tune later.
Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function(char: Model)
		local humanoid = char:WaitForChild("Humanoid") :: Humanoid
		humanoid.WalkSpeed = 60
	end)
end)

PlotService.Init(DataService, WorldService, layout)
BuildService.Init(DataService, PlotService)
PlotService.SetBuildService(BuildService)
StealService.Init(DataService, PlotService, layout)
PlotService.SetStealService(StealService)
FishSpawnerService.Init(WorldService, PlotService, DataService, layout, StealService)
IncomeService.Init(DataService, layout)

print("[StealAFish] Server booted.")

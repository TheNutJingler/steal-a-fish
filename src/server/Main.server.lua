--!strict
--[[
	Main.server — server entry point. Requires services in dependency order
	and boots them. Services live in src/server/Services/.

	Boot order:
	  1. DataService (profiles, sessions, offline earnings)
	  2. WorldService (builds the map, returns the layout)
	  3. PlotService (claims, slots, locks, upgrades)
	  4. FishSpawnerService (river conveyor)
	  5. StealService (steal validation, carry, bank, drop)
	  6. IncomeService (1s tick, leaderstats, AFK cove)
]]

local ServerScriptService = game:GetService("ServerScriptService")
local server = ServerScriptService:WaitForChild("StealAFish")
local Services = server:WaitForChild("Services")

local DataService = require(Services:WaitForChild("DataService"))
local WorldService = require(Services:WaitForChild("WorldService"))
local PlotService = require(Services:WaitForChild("PlotService"))
local FishSpawnerService = require(Services:WaitForChild("FishSpawnerService"))
local StealService = require(Services:WaitForChild("StealService"))
local IncomeService = require(Services:WaitForChild("IncomeService"))
local BuildService = require(Services:WaitForChild("BuildService"))

DataService.Init()
local layout = WorldService.Init()
PlotService.Init(DataService, WorldService, layout)
BuildService.Init(DataService, PlotService)
PlotService.SetBuildService(BuildService)
FishSpawnerService.Init(WorldService, PlotService, DataService, layout)
StealService.Init(DataService, PlotService, layout)
IncomeService.Init(DataService, layout)

print("[StealAFish] Server booted.")

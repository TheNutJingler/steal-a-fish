--!strict
--[[
	Main.server — server entry point. Requires services in dependency order
	and boots them. Services live in src/server/Services/.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local server = ServerScriptService:WaitForChild("StealAFish")
local Services = server:WaitForChild("Services")

local DataService = require(Services:WaitForChild("DataService"))
local PlotService = require(Services:WaitForChild("PlotService"))
local FishSpawnerService = require(Services:WaitForChild("FishSpawnerService"))
local StealService = require(Services:WaitForChild("StealService"))

-- Boot order matters: data first, then plots, then spawner, then stealing.
DataService.Init()
PlotService.Init(DataService)
FishSpawnerService.Init(PlotService)
StealService.Init(DataService, PlotService)

print("[StealAFish] Server booted.")

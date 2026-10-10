--!strict
--[[
	Main.client — client entry point. The client is a renderer + input
	device: it NEVER owns game state. It listens for RemoteEvents and
	renders UI.

	Boot order: HudController -> PlotController -> BuildController ->
	CodexController.
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local client = script.Parent
local Controllers = client:WaitForChild("Controllers")

local HudController = require(Controllers:WaitForChild("HudController"))
local PlotController = require(Controllers:WaitForChild("PlotController"))
local BuildController = require(Controllers:WaitForChild("BuildController"))
local CodexController = require(Controllers:WaitForChild("CodexController"))

HudController.Init()
PlotController.Init()
BuildController.Init()
CodexController.Init()

print(`[StealAFish] Client booted for {player.Name}.`)

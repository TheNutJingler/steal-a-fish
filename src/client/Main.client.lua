--!strict
--[[
	Main.client — client entry point. The client is a renderer + input device:
	it NEVER owns game state. It listens for RemoteEvents and renders UI.
	STATUS: stub — UI wiring comes with the interface pass.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")

-- TODO: require UI controllers, hook RemoteEvents, render HUD.

print(`[StealAFish] Client booted for {player.Name}.`)

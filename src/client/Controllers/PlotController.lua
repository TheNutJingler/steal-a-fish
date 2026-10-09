--!strict
--[[
	PlotController — decides which ProximityPrompts the local player sees.

	The server creates every prompt; the client only toggles .Enabled
	locally (never replicated, never trusted):
	  - Claim prompt:  visible on unclaimed plots while the player is plotless.
	  - Steal prompts:  visible on rivals' tanks (hidden while locked).
	  - Lock/upgrade:   visible only on the player's own plot sign.

	Locks are tracked client-side with a 1s refresh so steal prompts
	re-enable when a lock expires.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local myName = player.Name
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = Shared:WaitForChild("Remotes")

local PlotAssignedRemote = Remotes:WaitForChild("PlotAssigned") :: RemoteEvent
local PlotOwnerChangedRemote = Remotes:WaitForChild("PlotOwnerChanged") :: RemoteEvent
local LockChangedRemote = Remotes:WaitForChild("LockChanged") :: RemoteEvent

local PlotController = {}

local owners: { [number]: string? } = {} -- [plotIndex] = owner name or nil
local lockUntil: { [number]: number } = {} -- [plotIndex] = os.clock() unlock time
local myPlot: number? = nil

type PromptSet = {
	Claim: ProximityPrompt?,
	Lock: ProximityPrompt?,
	Upgrade: ProximityPrompt?,
	Expand: ProximityPrompt?,
	Steal: { ProximityPrompt },
}
local prompts: { [number]: PromptSet } = {}

local function plotLocked(plotIndex: number): boolean
	return (lockUntil[plotIndex] or 0) > os.clock()
end

local function refreshPlot(plotIndex: number)
	local set = prompts[plotIndex]
	if not set then
		return
	end
	local ownerName = owners[plotIndex]
	local isMine = myPlot == plotIndex
	local locked = plotLocked(plotIndex)

	if set.Claim then
		set.Claim.Enabled = (ownerName == nil) and (myPlot == nil)
	end
	if set.Lock then
		set.Lock.Enabled = isMine and not locked
	end
	if set.Upgrade then
		set.Upgrade.Enabled = isMine
	end
	if set.Expand then
		set.Expand.Enabled = isMine
	end
	for _, steal in set.Steal do
		steal.Enabled = (ownerName ~= nil) and (ownerName ~= myName) and not locked
	end
end

local function refreshAll()
	for plotIndex in prompts do
		refreshPlot(plotIndex)
	end
end

local function ensureSet(plotIndex: number): PromptSet
	local set = prompts[plotIndex]
	if not set then
		set = { Claim = nil, Lock = nil, Upgrade = nil, Expand = nil, Steal = {} }
		prompts[plotIndex] = set
	end
	return set
end

local function registerPrompt(prompt: ProximityPrompt)
	local plotIndex = prompt:GetAttribute("PlotIndex")
	if typeof(plotIndex) ~= "number" then
		-- Sign prompts: find the plot folder by ancestry.
		local ancestor = prompt:FindFirstAncestorOfClass("Folder")
		while ancestor and not string.match(ancestor.Name, "^Plot%d+$") do
			ancestor = ancestor:FindFirstAncestorOfClass("Folder")
		end
		if not ancestor then
			return
		end
		plotIndex = tonumber(string.sub(ancestor.Name, 5))
	end
	if typeof(plotIndex) ~= "number" then
		return
	end
	local set = ensureSet(plotIndex :: number)
	if prompt.Name == "StealPrompt" then
		table.insert(set.Steal, prompt)
	elseif string.find(prompt.ActionText, "Claim") then
		set.Claim = prompt
	elseif string.find(prompt.ActionText, "Lock") then
		set.Lock = prompt
	elseif string.find(prompt.ActionText, "Upgrade") then
		set.Upgrade = prompt
	elseif string.find(prompt.ActionText, "Expand") then
		set.Expand = prompt
	end
	refreshPlot(plotIndex :: number)
end

function PlotController.Init()
	local worldFolder = workspace:WaitForChild("StealAFishWorld")

	for _, descendant in worldFolder:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			registerPrompt(descendant)
		end
	end
	worldFolder.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("ProximityPrompt") then
			registerPrompt(descendant)
		end
	end)

	PlotAssignedRemote.OnClientEvent:Connect(function(plotIndex: number)
		myPlot = plotIndex
		refreshAll()
	end)

	PlotOwnerChangedRemote.OnClientEvent:Connect(function(plotIndex: number, ownerName: string?)
		owners[plotIndex] = ownerName
		refreshAll()
	end)

	LockChangedRemote.OnClientEvent:Connect(function(plotIndex: number, unlockUnix: number)
		-- Server sends os.time()-based; convert to os.clock() scale approximately.
		lockUntil[plotIndex] = os.clock() + math.max(0, unlockUnix - os.time())
		refreshAll()
	end)

	-- Re-enable steal prompts as locks expire.
	task.spawn(function()
		while true do
			task.wait(1)
			refreshAll()
		end
	end)

	print("[PlotController] init")
end

return PlotController

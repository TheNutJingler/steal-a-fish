--!strict
--[[
	HudController — top bar (coins, $/s), AFK badge, carry banner, toasts,
	offline-earnings welcome-back modal. Pure renderer: reads RemoteEvents
	and leaderstats, never writes game state.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = Shared:WaitForChild("Remotes")

local UiUtil = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("UiUtil"))

local StatsUpdateRemote = Remotes:WaitForChild("StatsUpdate") :: RemoteEvent
local AfkCoveChangedRemote = Remotes:WaitForChild("AfkCoveChanged") :: RemoteEvent
local OfflineEarningsRemote = Remotes:WaitForChild("OfflineEarnings") :: RemoteEvent
local StealResultRemote = Remotes:WaitForChild("StealResult") :: RemoteEvent
local CarryChangedRemote = Remotes:WaitForChild("CarryChanged") :: RemoteEvent
local LockChangedRemote = Remotes:WaitForChild("LockChanged") :: RemoteEvent
local PlotAssignedRemote = Remotes:WaitForChild("PlotAssigned") :: RemoteEvent
local PlotUpgradedRemote = Remotes:WaitForChild("PlotUpgraded") :: RemoteEvent

local HudController = {}

local CodexController: any = nil

local coinsLabel: TextLabel? = nil
local incomeLabel: TextLabel? = nil
local afkBadge: TextLabel? = nil
local carryBanner: TextLabel? = nil
local toastLayer: Instance? = nil

local function toast(text: string, color: Color3?)
	if toastLayer then
		UiUtil.Toast(toastLayer, text, color)
	end
end

local function formatCoins(n: number): string
	if n >= 1_000_000 then
		return string.format("%.1fM", n / 1_000_000)
	elseif n >= 10_000 then
		return string.format("%.1fK", n / 1_000)
	elseif n >= 1_000 then
		return string.format("%.2fK", n / 1_000)
	else
		return tostring(math.floor(n))
	end
end

local function showOfflineEarnings(coins: number, secondsAway: number)
	local gui = UiUtil.ScreenGui("OfflineEarningsGui")
	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dim.BackgroundTransparency = 0.4
	dim.Parent = gui
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(0.6, 0.4)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(28, 40, 55)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.08, 0)
	corner.Parent = panel
	panel.Parent = gui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.9, 0, 0.25, 0)
	title.Position = UDim2.new(0.05, 0, 0.05, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 220, 100)
	title.Text = "Welcome back!"
	title.Parent = panel

	local hours = secondsAway / 3600
	local body = Instance.new("TextLabel")
	body.Size = UDim2.new(0.9, 0, 0.35, 0)
	body.Position = UDim2.new(0.05, 0, 0.32, 0)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.GothamBold
	body.TextScaled = true
	body.TextColor3 = Color3.fromRGB(255, 255, 255)
	body.Text = `Your fish earned {formatCoins(coins)} coins\nwhile you were away ({string.format("%.1f", hours)}h)`
	body.Parent = panel

	local collect = UiUtil.Button(panel, "Collect", UDim2.new(0.5, 0, 0.82, 0), UDim2.fromScale(0.5, 0.18))
	collect.Activated:Connect(function()
		gui:Destroy()
	end)
end

function HudController.Init(codexController: any)
	CodexController = codexController

	local gui = UiUtil.ScreenGui("HudGui")

	-- Top-center: coins + income pills.
	coinsLabel = UiUtil.Pill(gui, "🪙 0", UDim2.new(0.38, 0, 0.02, 0), UDim2.new(0.2, 0, 0.07, 0))
	incomeLabel = UiUtil.Pill(gui, "$0/s", UDim2.new(0.62, 0, 0.02, 0), UDim2.new(0.2, 0, 0.07, 0))

	-- AFK badge (hidden until in the cove).
	afkBadge = UiUtil.Pill(gui, "🌴 AFK +25%", UDim2.new(0.5, 0, 0.1, 0), UDim2.new(0.18, 0, 0.055, 0))
	local afkBg = afkBadge.Parent :: Frame
	afkBg.Visible = false

	-- Carry banner (hidden unless carrying).
	carryBanner = UiUtil.Pill(gui, "", UDim2.new(0.5, 0, 0.17, 0), UDim2.new(0.4, 0, 0.06, 0))
	local carryBg = carryBanner.Parent :: Frame
	carryBg.Visible = false

	-- Toast layer.
	toastLayer = Instance.new("Frame")
	toastLayer.Name = "Toasts"
	toastLayer.Size = UDim2.fromScale(1, 1)
	toastLayer.BackgroundTransparency = 1
	toastLayer.Parent = gui

	-- Codex button (top-right).
	local codexBtn = UiUtil.Button(gui, "📖 Codex", UDim2.new(0.93, 0, 0.055, 0), UDim2.new(0.12, 0, 0.07, 0))
	codexBtn.Activated:Connect(function()
		CodexController.Toggle()
	end)

	-- Coins from leaderstats (authoritative mirror).
	local stats = player:WaitForChild("leaderstats")
	local coinsValue = stats:WaitForChild("Coins") :: IntValue
	local function refreshCoins()
		if coinsLabel then
			coinsLabel.Text = `🪙 {formatCoins(coinsValue.Value)}`
		end
	end
	coinsValue.Changed:Connect(refreshCoins)
	refreshCoins()

	-- Income rate from the server tick.
	StatsUpdateRemote.OnClientEvent:Connect(function(coins: number, rate: number)
		if incomeLabel then
			incomeLabel.Text = `{formatCoins(rate)}/s`
		end
		if coinsLabel then
			coinsLabel.Text = `🪙 {formatCoins(coins)}`
		end
	end)

	AfkCoveChangedRemote.OnClientEvent:Connect(function(inside: boolean)
		afkBg.Visible = inside
		if inside then
			toast("AFK Cove: +25% income!", Color3.fromRGB(120, 255, 120))
		end
	end)

	OfflineEarningsRemote.OnClientEvent:Connect(function(coins: number, secondsAway: number)
		showOfflineEarnings(coins, secondsAway)
	end)

	StealResultRemote.OnClientEvent:Connect(function(ok: boolean, message: string)
		toast(message, if ok then Color3.fromRGB(120, 255, 120) else Color3.fromRGB(255, 120, 120))
	end)

	CarryChangedRemote.OnClientEvent:Connect(function(isCarrying: boolean, fishName: string, context: string)
		if isCarrying then
			if carryBanner then
				carryBanner.Text = `🐟 Carrying {fishName} — get to your plot!`
			end
			carryBg.Visible = true
		else
			carryBg.Visible = false
			if context == "banked" then
				toast(`Banked {fishName}!`, Color3.fromRGB(120, 255, 120))
			elseif context == "stolen" then
				toast(`⚠️ Your {fishName} was stolen!`, Color3.fromRGB(255, 120, 120))
			elseif string.find(context, "dropped") then
				toast("You dropped the fish!", Color3.fromRGB(255, 200, 100))
			end
		end
	end)

	LockChangedRemote.OnClientEvent:Connect(function(plotIndex: number, _unlockAt: number)
		toast(`Plot {plotIndex} locked!`, Color3.fromRGB(255, 200, 100))
	end)

	PlotAssignedRemote.OnClientEvent:Connect(function(plotIndex: number)
		toast(`Aquarium {plotIndex} is yours!`, Color3.fromRGB(120, 255, 120))
	end)

	PlotUpgradedRemote.OnClientEvent:Connect(function(_plotIndex: number, _level: number, displayName: string)
		toast(`🎉 {displayName} unlocked!`, Color3.fromRGB(255, 220, 100))
	end)

	print("[HudController] init")
end

return HudController

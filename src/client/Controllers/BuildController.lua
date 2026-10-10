--!strict
--[[
	BuildController — the Build tab: buy base items and land, place items
	on the plot's tile grid.

	Tabs: Security | Decor | Land.
	Security/Decor: pick an item -> placement mode (ghost follows the
	  mouse on the platform grid, click to place, R rotates, Esc cancels).
	Land: tier cards -> Buy fires the existing RequestExpand.

	The server validates everything; the ghost is cosmetic.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildCatalog = require(Shared:WaitForChild("BuildCatalog"))
local Config = require(Shared:WaitForChild("Config"))
local Remotes = Shared:WaitForChild("Remotes")
local UiUtil = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("UiUtil"))

local RequestPlaceItemRemote = Remotes:WaitForChild("RequestPlaceItem") :: RemoteEvent
local PlaceItemResultRemote = Remotes:WaitForChild("PlaceItemResult") :: RemoteEvent
local BuildPlotInfoRemote = Remotes:WaitForChild("BuildPlotInfo") :: RemoteEvent
local RequestExpandRemote = Remotes:WaitForChild("RequestExpand") :: RemoteEvent
local ExpandResultRemote = Remotes:WaitForChild("ExpandResult") :: RemoteEvent
local PlotExpandedRemote = Remotes:WaitForChild("PlotExpanded") :: RemoteEvent
local RequestUpgradeTankRemote = Remotes:WaitForChild("RequestUpgradeTank") :: RemoteEvent
local UpgradeTankResultRemote = Remotes:WaitForChild("UpgradeTankResult") :: RemoteEvent
local TycoonSyncRemote = Remotes:WaitForChild("TycoonSync") :: RemoteEvent
local RequestRebirthRemote = Remotes:WaitForChild("RequestRebirth") :: RemoteEvent
local RebirthResultRemote = Remotes:WaitForChild("RebirthResult") :: RemoteEvent

local TILE = 5
local GRID = 12

local BuildController = {}

local plotCX: number? = nil
local plotCZ: number? = nil

local placing: BuildCatalog.BuildItemDef? = nil
local placeRot = 0
local ghost: BasePart? = nil
local ghostValid = false
local ghostTX = 0
local ghostTZ = 0

local panel: Frame? = nil
local panelOpen = false
local toastLayer: Instance? = nil
local ownedTiers: { [number]: boolean } = {}
local tankMaxSlot = 8
local tankUpgrades: { [string]: number } = {}
local rebirths = 0

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

-- Placement ghost -----------------------------------------------

local function clearGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	placing = nil
	ghostValid = false
end

local function footprint(): (number, number)
	if not placing then
		return 1, 1
	end
	local w, d = placing.SizeTiles[1], placing.SizeTiles[2]
	if placeRot == 90 then
		w, d = d, w
	end
	return w, d
end

local function updateGhost()
	if not placing or not plotCX or not plotCZ then
		return
	end
	if not ghost then
		ghost = Instance.new("Part")
		ghost.Name = "BuildGhost"
		ghost.Anchored = true
		ghost.CanCollide = false
		ghost.CanTouch = false
		ghost.CanQuery = false
		ghost.Transparency = 0.5
		ghost.TopSurface = Enum.SurfaceType.Smooth
		ghost.BottomSurface = Enum.SurfaceType.Smooth
		ghost.Parent = workspace
	end
	local w, d = footprint()
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000)
	ghostValid = false
	if result then
		local pos = result.Position
		local cx = plotCX :: number
		local cz = plotCZ :: number
		-- Must hit near the platform top.
		if pos.Y > -2 and pos.Y < 12
			and pos.X >= cx - 30 and pos.X <= cx + 30
			and pos.Z >= cz - 30 and pos.Z <= cz + 30 then
			local tx = math.floor((pos.X - (cx - 30)) / TILE)
			local tz = math.floor((pos.Z - (cz - 30)) / TILE)
			if tx >= 0 and tz >= 0 and tx + w <= GRID and tz + d <= GRID then
				ghostTX, ghostTZ = tx, tz
				ghost.Size = Vector3.new(w * TILE, 1, d * TILE)
				ghost.CFrame = CFrame.new(
					cx - 30 + (tx + w / 2) * TILE,
					2.5,
					cz - 30 + (tz + d / 2) * TILE)
				ghost.Color = Color3.fromRGB(80, 220, 100)
				ghostValid = true
			end
		end
	end
	if not ghostValid then
		ghost.Color = Color3.fromRGB(220, 80, 80)
		-- Park it under the mouse anyway.
		if result then
			ghost.Size = Vector3.new(w * TILE, 1, d * TILE)
			ghost.CFrame = CFrame.new(result.Position + Vector3.new(0, 2, 0))
		end
	end
end

local function enterPlacement(def: BuildCatalog.BuildItemDef)
	placing = def
	placeRot = 0
	if panel then
		panel.Visible = false
	end
	toast(`Placing {def.Name} — click to place, R rotates, Esc cancels`,
		Color3.fromRGB(150, 220, 255))
end

local function exitPlacement()
	clearGhost()
	if panel and panelOpen then
		panel.Visible = true
	end
end

-- Build panel ----------------------------------------------------

local function makeCard(parent: Instance, title: string, sub: string,
	buttonText: string, onClick: () -> ()): Frame
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, 86)
	card.BackgroundColor3 = Color3.fromRGB(32, 44, 60)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = card
	card.Parent = parent

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.62, 0, 0.38, 0)
	nameLabel.Position = UDim2.new(0.03, 0, 0.06, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Text = title
	nameLabel.Parent = card

	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.new(0.62, 0, 0.5, 0)
	subLabel.Position = UDim2.new(0.03, 0, 0.42, 0)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.Gotham
	subLabel.TextScaled = true
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.TextYAlignment = Enum.TextYAlignment.Top
	subLabel.TextColor3 = Color3.fromRGB(180, 195, 210)
	subLabel.Text = sub
	subLabel.Parent = card

	local btn = UiUtil.Button(card, buttonText,
		UDim2.new(0.83, 0, 0.5, 0), UDim2.new(0.3, 0, 0.7, 0))
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.MouseButton1Click:Connect(onClick)
	return card
end

local function buildPanel(): Frame
	local gui = UiUtil.ScreenGui("BuildGui")
	toastLayer = Instance.new("Frame")
	toastLayer.Name = "ToastLayer"
	toastLayer.Size = UDim2.fromScale(1, 1)
	toastLayer.BackgroundTransparency = 1
	toastLayer.Parent = gui

	-- Toggle button.
	local toggle = UiUtil.Button(gui, "🔨 Build",
		UDim2.new(0.94, 0, 0.88, 0), UDim2.new(0.11, 0, 0.07, 0))

	local p = Instance.new("Frame")
	p.Name = "BuildPanel"
	p.Size = UDim2.fromScale(0.42, 0.62)
	p.Position = UDim2.fromScale(0.5, 0.5)
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.BackgroundColor3 = Color3.fromRGB(22, 32, 46)
	p.Visible = false
	local pcorner = Instance.new("UICorner")
	pcorner.CornerRadius = UDim.new(0.03, 0)
	pcorner.Parent = p
	p.Parent = gui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.9, 0, 0.09, 0)
	title.Position = UDim2.new(0.05, 0, 0.02, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = "Build"
	title.Parent = p

	-- Tabs.
	local tabs = { "Security", "Decor", "Land", "Tanks", "Rebirth" }
	local tabButtons: { TextButton } = {}
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(0.94, 0, 0.76, 0)
	list.Position = UDim2.new(0.03, 0, 0.2, 0)
	list.BackgroundTransparency = 1
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = list
	list.Parent = p

	local function showTab(cat: string)
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		if cat == "Tanks" then
			for slot = 1, tankMaxSlot do
				local level = tankUpgrades[tostring(slot)] or 1
				local bonusPct = math.floor((1 + 0.25 * (level - 1)) * 100)
				local maxed = level >= 5
				local cost = 2500 * (2 ^ (level - 1))
				makeCard(list,
					`Tank {slot} — Lv {level} ({bonusPct}% income)`,
					if maxed then "Max level — this tank earns double."
					else `Upgrade: +25% fish income. Cost {formatCoins(cost)} coins.`,
					if maxed then "MAX" else "Upgrade",
					function()
						if not maxed then
							RequestUpgradeTankRemote:FireServer(slot)
						end
					end)
			end
		elseif cat == "Rebirth" then
			local mult = (1.5 ^ rebirths)
			local multText = string.format("%.2fx", mult)
			local cost = 500000 * (2 ^ rebirths)
			makeCard(list,
				`Rebirths: {rebirths} ({multText} income)`,
				`Cost {formatCoins(cost)} coins. Resets coins, fish and tank upgrades. Keeps your base, buildings, land and codex.`,
				"REBIRTH",
				function()
					RequestRebirthRemote:FireServer()
				end)
		elseif cat == "Land" then
			for _, tier in Config.LandExpansions do
				local owned = ownedTiers[tier.Tier]
				makeCard(list,
					`{tier.DisplayName}`,
					if owned then "Owned" else `{formatCoins(tier.Cost)} coins · lot {tier.LotSize}x{tier.LotSize} · +4 tank slots`,
					if owned then "Owned" else "Buy",
					function()
						if not owned then
							RequestExpandRemote:FireServer()
						end
					end)
			end
		else
			for _, def in BuildCatalog.ByCategory(cat) do
				makeCard(list,
					`{def.Name} — {formatCoins(def.Price)}`,
					def.Description,
					"Place",
					function()
						enterPlacement(def)
					end)
			end
		end
	end

	for i, cat in tabs do
		local tb = UiUtil.Button(p, cat,
			UDim2.new(0.03 + (i - 1) * 0.185, 0, 0.145, 0),
			UDim2.new(0.17, 0, 0.05, 0))
		tb.AnchorPoint = Vector2.new(0, 0.5)
		tb.BackgroundColor3 = Color3.fromRGB(45, 60, 80)
		tb.MouseButton1Click:Connect(function()
			for _, b in tabButtons do
				b.BackgroundColor3 = Color3.fromRGB(45, 60, 80)
			end
			tb.BackgroundColor3 = Color3.fromRGB(45, 120, 200)
			showTab(cat)
		end)
		table.insert(tabButtons, tb)
		if i == 1 then
			tb.BackgroundColor3 = Color3.fromRGB(45, 120, 200)
		end
	end
	showTab("Security")

	toggle.MouseButton1Click:Connect(function()
		exitPlacement()
		panelOpen = not panelOpen
		p.Visible = panelOpen
	end)
	return p
end

function BuildController.Init()
	panel = buildPanel()

	BuildPlotInfoRemote.OnClientEvent:Connect(function(cx: number, cz: number, tier: number)
		plotCX, plotCZ = cx, cz
		for t = 1, tier do
			ownedTiers[t] = true
		end
	end)

	PlaceItemResultRemote.OnClientEvent:Connect(function(ok: boolean, msg: string)
		toast(msg, if ok then Color3.fromRGB(140, 255, 140) else Color3.fromRGB(255, 140, 140))
		if ok then
			exitPlacement()
		end
	end)

	ExpandResultRemote.OnClientEvent:Connect(function(ok: boolean, msg: string)
		toast(msg, if ok then Color3.fromRGB(140, 255, 140) else Color3.fromRGB(255, 140, 140))
	end)

	PlotExpandedRemote.OnClientEvent:Connect(function(_plotIndex: number, tier: number, _name: string)
		ownedTiers[tier] = true
	end)

	TycoonSyncRemote.OnClientEvent:Connect(function(maxSlot: number, upgrades: any, rb: number)
		tankMaxSlot = maxSlot
		tankUpgrades = if typeof(upgrades) == "table" then upgrades else {}
		rebirths = rb
	end)

	UpgradeTankResultRemote.OnClientEvent:Connect(function(ok: boolean, msg: string)
		toast(msg, if ok then Color3.fromRGB(140, 255, 140) else Color3.fromRGB(255, 140, 140))
	end)

	RebirthResultRemote.OnClientEvent:Connect(function(ok: boolean, msg: string)
		toast(msg, if ok then Color3.fromRGB(255, 220, 100) else Color3.fromRGB(255, 140, 140))
	end)

	-- Placement input.
	mouse.Move:Connect(updateGhost)
	mouse.Button1Down:Connect(function()
		if placing and ghostValid and panel and not panel.Visible then
			RequestPlaceItemRemote:FireServer(placing.Id, ghostTX, ghostTZ, placeRot)
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, gpe: boolean)
		if gpe then
			return
		end
		if not placing then
			return
		end
		if input.KeyCode == Enum.KeyCode.R then
			placeRot = if placeRot == 0 then 90 else 0
			updateGhost()
		elseif input.KeyCode == Enum.KeyCode.Escape then
			exitPlacement()
		end
	end)
	-- Right-click cancels placement.
	mouse.Button2Down:Connect(function()
		if placing then
			exitPlacement()
		end
	end)
end

return BuildController

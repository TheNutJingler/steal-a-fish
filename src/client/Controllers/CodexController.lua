--!strict
--[[
	CodexController — the fish collection UI.

	CodexSync delivers the owned set ("SpeciesId:VariantId" keys) plus
	completed rarity tiers. This renders a scrollable collection grid:
	every species grouped by rarity, with variant dots lit for owned
	combos. Renderer only — the server owns the data.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FishRegistry = require(Shared:WaitForChild("FishRegistry"))
local Remotes = Shared:WaitForChild("Remotes")

local UiUtil = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("UiUtil"))

local CodexSyncRemote = Remotes:WaitForChild("CodexSync") :: RemoteEvent

local CodexController = {}

local holder: Frame? = nil
local panel: Frame? = nil
local listLayout: UIListLayout? = nil
local owned: { [string]: boolean } = {}
local tiers: { [string]: boolean } = {}
local visible = false

local RARITY_ORDER = { "Starter", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
local VARIANT_ORDER = { "Normal", "Golden", "Diamond", "Crystal", "Rainbow", "Shadow", "Frost" }

local function rarityColor(rarity: string): Color3
	-- Match FishRegistry rarity colors.
	local map: { [string]: Color3 } = {
		Starter = Color3.fromRGB(150, 150, 150),
		Common = Color3.fromRGB(120, 200, 120),
		Uncommon = Color3.fromRGB(90, 160, 255),
		Rare = Color3.fromRGB(170, 90, 255),
		Epic = Color3.fromRGB(255, 140, 60),
		Legendary = Color3.fromRGB(255, 210, 60),
		Mythic = Color3.fromRGB(255, 80, 120),
	}
	return map[rarity] or Color3.fromRGB(255, 255, 255)
end

local function rebuild()
	if not panel then
		return
	end
	for _, child in panel:GetChildren() do
		if child:IsA("Frame") and child.Name == "Row" then
			child:Destroy()
		end
	end
	for _, rarity in RARITY_ORDER do
		local speciesList = FishRegistry.GetSpeciesByRarity(rarity)
		if #speciesList == 0 then
			continue
		end
		-- Rarity header.
		local header = Instance.new("Frame")
		header.Name = "Row"
		header.Size = UDim2.new(1, 0, 0, 30)
		header.BackgroundTransparency = 1
		header.LayoutOrder = #panel:GetChildren()
		header.Parent = panel
		local headerLabel = Instance.new("TextLabel")
		headerLabel.Size = UDim2.fromScale(1, 1)
		headerLabel.BackgroundTransparency = 1
		headerLabel.Font = Enum.Font.GothamBlack
		headerLabel.TextScaled = true
		headerLabel.TextXAlignment = Enum.TextXAlignment.Left
		headerLabel.TextColor3 = rarityColor(rarity)
		local tierMark = if tiers[rarity] then " ✓ (+5%)" else ""
		headerLabel.Text = `{rarity}{tierMark}`
		headerLabel.Parent = header

		for _, species in speciesList do
			local row = Instance.new("Frame")
			row.Name = "Row"
			row.Size = UDim2.new(1, 0, 0, 44)
			row.BackgroundColor3 = Color3.fromRGB(24, 34, 46)
			row.BackgroundTransparency = 0.15
			local rc = Instance.new("UICorner")
			rc.CornerRadius = UDim.new(0.2, 0)
			rc.Parent = row
			row.Parent = panel

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(0.45, 0, 1, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextScaled = true
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
			nameLabel.Text = `  {species.DisplayName}`
			nameLabel.Parent = row

			-- Variant dots.
			local dots = Instance.new("Frame")
			dots.Size = UDim2.new(0.55, 0, 1, 0)
			dots.Position = UDim2.new(0.45, 0, 0, 0)
			dots.BackgroundTransparency = 1
			dots.Parent = row
			local dotLayout = Instance.new("UIListLayout")
			dotLayout.FillDirection = Enum.FillDirection.Horizontal
			dotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
			dotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			dotLayout.Padding = UDim.new(0, 6)
			dotLayout.Parent = dots
			for _, vid in VARIANT_ORDER do
				local variant = FishRegistry.VARIANTS[vid]
				local dot = Instance.new("Frame")
				dot.Size = UDim2.new(0, 22, 0, 22)
				local dc = Instance.new("UICorner")
				dc.CornerRadius = UDim.new(0.5, 0)
				dc.Parent = dot
				if owned[`{species.Id}:{vid}`] then
					dot.BackgroundColor3 = variant.Color
				else
					dot.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
					dot.BackgroundTransparency = 0.4
				end
				dot.Parent = dots
			end
		end
	end
	if listLayout then
		listLayout:ApplyLayout()
	end
end

function CodexController.Toggle()
	visible = not visible
	if holder then
		holder.Visible = visible
	end
end

function CodexController.Init()

	local gui = UiUtil.ScreenGui("CodexGui")
	gui.Enabled = true

	local holderFrame = Instance.new("Frame")
	holderFrame.Name = "Holder"
	holderFrame.Size = UDim2.fromScale(0.42, 0.8)
	holderFrame.Position = UDim2.fromScale(0.57, 0.1)
	holderFrame.BackgroundColor3 = Color3.fromRGB(16, 24, 34)
	holderFrame.BackgroundTransparency = 0.1
	holderFrame.Visible = false
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(0.03, 0)
	hc.Parent = holderFrame
	holderFrame.Parent = gui
	holder = holderFrame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 40)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 220, 100)
	title.Text = "🐟 Fish Codex"
	title.Parent = holderFrame

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -16, 1, -56)
	scroll.Position = UDim2.new(0, 8, 0, 48)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = holderFrame

	panel = Instance.new("Frame")
	panel.Name = "List"
	panel.Size = UDim2.new(1, 0, 1, 0)
	panel.BackgroundTransparency = 1
	panel.Parent = scroll
	listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = panel

	CodexSyncRemote.OnClientEvent:Connect(function(keys: { string }, completedTiers: { string })
		owned = {}
		for _, k in keys do
			owned[k] = true
		end
		tiers = {}
		for _, t in completedTiers do
			tiers[t] = true
		end
		rebuild()
	end)

	print("[CodexController] init")
end

return CodexController

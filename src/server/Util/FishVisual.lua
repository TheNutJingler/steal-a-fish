--!strict
--[[
	FishVisual — builds fish models in code (server-side only).
	One builder for river fish, plot slot fish, and carried fish so every
	fish in the game looks consistent. Body tint comes from the species,
	rare variants get a neon material so they read as special at a glance.

	Fish are kinematic display models: Anchored, CanCollide=false,
	CanTouch=false (river fish opt back into CanTouch for grab detection).
	Attributes set on the PrimaryPart: Uid, SpeciesId, VariantId.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FishRegistry = require(Shared:WaitForChild("FishRegistry"))

local FishVisual = {}

-- Rarity tiers that get the neon "special" treatment.
local NEON_VARIANTS = {
	Diamond = true,
	Crystal = true,
	Rainbow = true,
	Shadow = true,
}

--[[
	Builds a fish Model.
	@param speciesId FishRegistry species id
	@param variantId FishRegistry variant id
	@param scale number — 1.0 = river size, ~0.55 = tank size
	@param uid string? — stamped as an attribute when the fish needs identity
]]
function FishVisual.Build(speciesId: string, variantId: string, scale: number, uid: string?): Model
	local fish = FishRegistry.GetFish(speciesId, variantId)

	local model = Instance.new("Model")
	model.Name = fish.DisplayName

	-- Body: squashed ball, tinted by species.
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(2.4 * scale, 1.4 * scale, 1.1 * scale)
	body.Color = fish.Species.Color
	body.Material = if NEON_VARIANTS[variantId]
		then Enum.Material.Neon
		else Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.CanTouch = false
	body.CanQuery = false
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.Parent = model

	-- Tail: wedge fin at the back.
	local tail = Instance.new("WedgePart")
	tail.Name = "Tail"
	tail.Size = Vector3.new(1.1 * scale, 1.2 * scale, 0.5 * scale)
	tail.Color = fish.Species.Color
	tail.Material = body.Material
	tail.Anchored = true
	tail.CanCollide = false
	tail.CanTouch = false
	tail.CanQuery = false
	tail.TopSurface = Enum.SurfaceType.Smooth
	tail.BottomSurface = Enum.SurfaceType.Smooth
	-- Wedge slopes toward -X; sit it behind the body (-X is "back").
	tail.CFrame = body.CFrame * CFrame.new(-1.6 * scale, 0, 0)
	tail.Parent = model

	-- Dorsal fin: small wedge on top for silhouette.
	local fin = Instance.new("WedgePart")
	fin.Name = "Fin"
	fin.Size = Vector3.new(0.9 * scale, 0.7 * scale, 0.4 * scale)
	fin.Color = fish.Species.Color
	fin.Material = body.Material
	fin.Anchored = true
	fin.CanCollide = false
	fin.CanTouch = false
	fin.CanQuery = false
	fin.TopSurface = Enum.SurfaceType.Smooth
	fin.BottomSurface = Enum.SurfaceType.Smooth
	fin.CFrame = body.CFrame * CFrame.new(0.1 * scale, 0.85 * scale, 0)
	fin.Parent = model

	-- Weld everything rigid; body is the assembly root.
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part ~= body then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = part
			weld.Parent = body
		end
	end
	model.PrimaryPart = body

	-- Identity attributes (replicated; clients read these, never the spawn table).
	body:SetAttribute("SpeciesId", speciesId)
	body:SetAttribute("VariantId", variantId)
	if uid then
		body:SetAttribute("Uid", uid)
	end

	-- Nameplate: name + income. Clients could build this, but the server
	-- building it keeps one code path; it carries no secret data.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "FishTag"
	billboard.Size = UDim2.fromOffset(120 * scale, 40 * scale)
	billboard.StudsOffset = Vector3.new(0, 2.2 * scale, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 60

	local rarityColor = FishRegistry.RARITY_COLORS[fish.Species.Rarity]

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.fromScale(1, 0.55)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = rarityColor
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Text = fish.DisplayName
	nameLabel.Parent = billboard

	local incomeLabel = Instance.new("TextLabel")
	incomeLabel.Name = "Income"
	incomeLabel.Size = UDim2.fromScale(1, 0.45)
	incomeLabel.Position = UDim2.fromScale(0, 0.55)
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.Font = Enum.Font.Gotham
	incomeLabel.TextScaled = true
	incomeLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
	incomeLabel.TextStrokeTransparency = 0.4
	incomeLabel.Text = `$ {FishVisual.FormatIncome(fish.IncomePerSecond)}/s`
	incomeLabel.Parent = billboard

	billboard.Parent = body
	billboard.Adornee = body

	return model
end

-- Compact income formatting: 1500 -> "1.5K", 2500000 -> "2.5M".
function FishVisual.FormatIncome(income: number): string
	if income >= 1_000_000_000 then
		return string.format("%.1fB", income / 1_000_000_000)
	elseif income >= 1_000_000 then
		return string.format("%.1fM", income / 1_000_000)
	elseif income >= 10_000 then
		return string.format("%.1fK", income / 1_000)
	elseif income >= 1_000 then
		return string.format("%.2fK", income / 1_000)
	else
		return string.format("%d", math.floor(income))
	end
end

return FishVisual

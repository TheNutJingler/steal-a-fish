--!strict
--[[
	StealService — THE trust boundary.

	Every steal is validated server-side at commit time: the client sends
	intent (prompt trigger), the server recomputes distance, ownership,
	lock state, and cooldowns. Never trust the client's word.

	Flow: hold-E on a rival's tank (3s channel) -> server validates ->
	carry (slowed ~40%) -> bank by reaching your own plot -> fish is yours.
	Bump into a carrier and they drop it (returns to the victim's plot).

	Expose: Init(dataService, plotService)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local server = ServerScriptService:WaitForChild("StealAFish")
local Util = server:WaitForChild("Util")
local FishVisual = require(Util:WaitForChild("FishVisual"))
local RateLimit = require(Util:WaitForChild("RateLimit"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = Shared:WaitForChild("Remotes")

local RequestStealRemote = Remotes:WaitForChild("RequestSteal") :: RemoteEvent
local StealResultRemote = Remotes:WaitForChild("StealResult") :: RemoteEvent
local CarryChangedRemote = Remotes:WaitForChild("CarryChanged") :: RemoteEvent

type CarryState = {
	Fish: { [string]: any }, -- {Uid, SpeciesId, VariantId}
	Victim: Player?, -- nil for river pickups
	Source: string, -- "River" | "Steal"

	OriginPlotIndex: number,
	OriginSlot: number,
	Visual: Model?,
	PrevWalkSpeed: number,
}

local StealService = {}

local DataService: any = nil
local PlotService: any = nil

local Carrying: { [Player]: CarryState } = {}
local lastDeny: { [Player]: number } = {} -- pickup-denial toast cooldown
local StealCooldowns: { [string]: number } = {} -- [fishUid] = os.clock() when stealable
local stealLimiter = RateLimit.new(Config.RateLimit_Steal.Max, Config.RateLimit_Steal.Window)

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function alive(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function notify(player: Player, ok: boolean, message: string)
	StealResultRemote:FireClient(player, ok, message)
end

function StealService.GetCarry(player: Player): any
	return Carrying[player]
end

-- Resolve a carry: restore speed, destroy the visual, clear state.
local function clearCarry(player: Player)
	local carry = Carrying[player]
	if not carry then
		return
	end
	Carrying[player] = nil
	if carry.Visual then
		carry.Visual:Destroy()
	end
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = carry.PrevWalkSpeed
		end
	end
end

function StealService.ClearCarry(player: Player)
	clearCarry(player)
end

-- Mark a banked stolen fish as recently stolen (re-steal cooldown).
function StealService.NoteBanked(uid: string)
	StealCooldowns[uid] = os.clock() + Config.StealCooldown
end

-- The fish goes home: victim's origin slot if free, else back-most free.
local function returnFishToVictim(carry: CarryState, context: string)
	if carry.Source == "River" or not carry.Victim then
		return -- wild fish: nothing to return to
	end
	local victimPlot = PlotService.GetPlot(carry.Victim)
	if victimPlot then
		local slot = PlotService.ReturnFishToSlot(victimPlot, carry.Fish, carry.OriginSlot)
		if slot then
			StealCooldowns[carry.Fish.Uid] = os.clock() + Config.StealCooldown
		end
	end
	CarryChangedRemote:FireClient(carry.Victim, false, "", `recovered ({context})`)
end

local function attachCarryVisual(player: Player, speciesId: string, variantId: string): Model?
	local character = player.Character
	if not character then
		return nil
	end
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local model = FishVisual.Build(speciesId, variantId, 0.7, nil)
	model:PivotTo(head.CFrame * CFrame.new(0, 2.2, 0))
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = head
			weld.Part1 = part
			weld.Parent = head
		end
	end
	model.Parent = character
	return model
end

function StealService.TrySteal(player: Player, plotIndex: unknown, slotIndex: unknown): (boolean, string)
	-- 1. Rate limit.
	if not stealLimiter:Check(player.UserId) then
		return false, "Slow down."
	end
	-- 2. Type + NaN guard.
	if typeof(plotIndex) ~= "number" or typeof(slotIndex) ~= "number" then
		return false, "Bad request."
	end
	local pi = math.floor(plotIndex :: number)
	local si = math.floor(slotIndex :: number)
	if pi ~= pi or si ~= si then -- NaN
		return false, "Bad request."
	end
	-- 3. State: thief must be free-handed, alive, and have a live data session.
	if Carrying[player] then
		return false, "Already carrying a fish."
	end
	local ownPlot = PlotService.GetPlot(player)
	if not ownPlot or PlotService.FreeSlotCount(ownPlot) < 1 then
		return false, "You need a free tank first."
	end
	if not alive(player) then
		return false, "You must be alive to steal."
	end
	if not DataService.GetProfile(player) then
		return false, "Data not loaded yet."
	end
	-- 4. Target plot: exists, owned by someone else, not locked.
	local targetPlot = PlotService.GetPlotByIndex(pi)
	if not targetPlot or not targetPlot.Owner then
		return false, "No such aquarium."
	end
	if targetPlot.Owner == player then
		return false, "That's your own fish."
	end
	if PlotService.IsLocked(targetPlot) then
		return false, "That aquarium is locked!"
	end
	-- 5. The fish must actually be there.
	local uid = targetPlot.Slots[si]
	if not uid then
		return false, "Nothing in that tank."
	end
	if (StealCooldowns[uid] or 0) > os.clock() then
		return false, "That fish was just stolen — give it a moment."
	end
	-- 6. Server-measured distance (prompts can be triggered at range).
	local anchor = targetPlot.Layout.SlotAnchors[si]
	local root = rootOf(player)
	if not root then
		return false, "No character."
	end
	if (root.Position - anchor).Magnitude > Config.StealMaxDistance then
		return false, "Too far away."
	end

	-- COMMIT.
	local fish = PlotService.TakeFishFromSlot(targetPlot, si)
	if not fish then
		return false, "Fish is gone."
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local prevSpeed = if humanoid then humanoid.WalkSpeed else 16
	if humanoid then
		humanoid.WalkSpeed = Config.CarryWalkSpeed
	end
	local visual = attachCarryVisual(player, fish.SpeciesId, fish.VariantId)
	Carrying[player] = {
		Source = "Steal",
		Fish = fish,
		Victim = targetPlot.Owner,
		OriginPlotIndex = pi,
		OriginSlot = si,
		Visual = visual,
		PrevWalkSpeed = prevSpeed,
	}
	CarryChangedRemote:FireClient(player, true, fish.SpeciesId, "carrying")
	CarryChangedRemote:FireClient(targetPlot.Owner, false, fish.SpeciesId, "stolen")
	-- Watch for death while carrying.
	if humanoid then
		humanoid.Died:Once(function()
			StealService.ResolveDrop(player, "died")
		end)
	end
	print(`[StealService] {player.Name} stole {fish.SpeciesId} from {targetPlot.Owner.Name}`)
	return true, "Fish stolen! Get it home!"
end

-- Pick up a wild river fish. Carry it to one of your tanks to place it.
function StealService.PickupFish(player: Player, speciesId: string, variantId: string): (boolean, string)
	local function deny(msg: string): (boolean, string)
		-- Cooldown: touches fire repeatedly while wading through the river.
		if (lastDeny[player] or 0) + 3 < os.clock() then
			lastDeny[player] = os.clock()
			notify(player, false, msg)
		end
		return false, msg
	end
	if Carrying[player] then
		return deny("Already carrying a fish.")
	end
	if not alive(player) then
		return deny("You must be alive.")
	end
	local plot = PlotService.GetPlot(player)
	if not plot then
		return deny("Claim a base first.")
	end
	if PlotService.FreeSlotCount(plot) < 1 then
		return deny("Your tanks are full.")
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local prevSpeed = humanoid and humanoid.WalkSpeed or 16
	if humanoid then
		humanoid.WalkSpeed = Config.CarryWalkSpeed
	end
	local visual = attachCarryVisual(player, speciesId, variantId)
	Carrying[player] = {
		Source = "River",
		Fish = { SpeciesId = speciesId, VariantId = variantId },
		Victim = nil,
		OriginPlotIndex = 0,
		OriginSlot = 0,
		Visual = visual,
		PrevWalkSpeed = prevSpeed,
	}
	CarryChangedRemote:FireClient(player, true, speciesId, "carrying")
	if humanoid then
		humanoid.Died:Once(function()
			StealService.ResolveDrop(player, "died")
		end)
	end
	print(`[StealService] {player.Name} picked up {speciesId} ({variantId})`)
	return true, "Carrying! Place it in a tank."
end

function StealService.ResolveDrop(player: Player, context: string)
	local carry = Carrying[player]
	if not carry then
		return
	end
	returnFishToVictim(carry, context)
	clearCarry(player)
	CarryChangedRemote:FireClient(player, false, "", `dropped ({context})`)
	print(`[StealService] {player.Name} dropped {carry.Fish.SpeciesId} ({context})`)
end

local function dropCheck()
	for carrier in Carrying do
		local carrierRoot = rootOf(carrier)
		if not carrierRoot then
			continue
		end
		for _, other in Players:GetPlayers() do
			if other == carrier then
				continue
			end
			if not alive(other) then
				continue
			end
			local otherRoot = rootOf(other)
			if otherRoot and (otherRoot.Position - carrierRoot.Position).Magnitude < 6 then
				StealService.ResolveDrop(carrier, "bumped")
				break
			end
		end
	end
end



function StealService.Init(dataService: any, plotService: any, layout: any)
	DataService = dataService
	PlotService = plotService

	-- Hook every steal prompt PlotService created (they live in the world).
	-- Upper floors' prompts arrive later via DescendantAdded.
	local worldFolder = workspace:WaitForChild("StealAFishWorld")
	local function hookPrompt(prompt: ProximityPrompt)
		if prompt:GetAttribute("PlotIndex") == nil then
			return
		end
		local pi = prompt:GetAttribute("PlotIndex")
		local si = prompt:GetAttribute("SlotIndex")
		prompt.Triggered:Connect(function(player: Player)
			local ok, msg = StealService.TrySteal(player, pi, si)
			notify(player, ok, msg)
		end)
	end
	for _, descendant in worldFolder:GetDescendants() do
		if descendant:IsA("ProximityPrompt") and descendant.Name == "StealPrompt" then
			hookPrompt(descendant)
		end
	end
	worldFolder.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("ProximityPrompt") and descendant.Name == "StealPrompt" then
			hookPrompt(descendant)
		end
	end)

	RequestStealRemote.OnServerEvent:Connect(function(player: Player, plotIndex: unknown, slotIndex: unknown)
		local ok, msg = StealService.TrySteal(player, plotIndex, slotIndex)
		notify(player, ok, msg)
	end)

	-- Carrier leaves or their victim leaves: resolve the carry.
	DataService.PlayerLeaving:Connect(function(player: Player)
		if Carrying[player] then
			-- Carrier left: fish goes home.
			local carry = Carrying[player]
			returnFishToVictim(carry, "carrier left")
			Carrying[player] = nil
		end
		for carrier, carry in Carrying do
			if carry.Victim == player and carry.Source == "Steal" then
				-- Victim left: the fish is yours now — place it in a tank.
				local profile = DataService.GetProfile(carrier)
				if profile then
					table.insert(profile.Data.Fish, {
						Uid = carry.Fish.Uid,
						SpeciesId = carry.Fish.SpeciesId,
						VariantId = carry.Fish.VariantId,
						Slot = nil,
					})
					DataService.RegisterCodexEntry(carrier, carry.Fish.SpeciesId, carry.Fish.VariantId)
				end
				carry.Victim = nil
				carry.Source = "River" -- no one to return it to
				CarryChangedRemote:FireClient(carrier, true, carry.Fish.SpeciesId, "carrying")
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.DropCheckInterval)
			pcall(dropCheck)
		end
	end)

	print("[StealService] init")
end

return StealService

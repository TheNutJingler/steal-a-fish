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
	Victim: Player,
	OriginPlotIndex: number,
	OriginSlot: number,
	Visual: Model?,
	PrevWalkSpeed: number,
}

local StealService = {}

local DataService: any = nil
local PlotService: any = nil

local Carrying: { [Player]: CarryState } = {}
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

-- The fish goes home: victim's origin slot if free, else back-most free.
local function returnFishToVictim(carry: CarryState, context: string)
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

-- Bank: carrier reached their own plot -> the fish is theirs.
local function tryBank(player: Player)
	local carry = Carrying[player]
	if not carry then
		return
	end
	local ownPlot = PlotService.GetPlot(player)
	if not ownPlot then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	if (root.Position - ownPlot.Layout.Center).Magnitude > 26 then
		return
	end
	-- Ownership transfers to the thief at bank time.
	if not PlotService.MoveFishToPlayer(carry.Fish, carry.Victim, player) then
		returnFishToVictim(carry, "transfer failed")
		clearCarry(player)
		CarryChangedRemote:FireClient(player, false, "", "bank failed")
		return
	end
	local slot = PlotService.ReturnFishToSlot(ownPlot, carry.Fish, nil)
	if not slot then
		-- Plot full (rare): the fish slips back to the victim.
		returnFishToVictim(carry, "thief plot full")
		clearCarry(player)
		CarryChangedRemote:FireClient(player, false, "", "bank failed")
		return
	end
	StealCooldowns[carry.Fish.Uid] = os.clock() + Config.StealCooldown
	local profile = DataService.GetProfile(player)
	if profile then
		DataService.RegisterCodexEntry(player, carry.Fish.SpeciesId, carry.Fish.VariantId)
	end
	clearCarry(player)
	CarryChangedRemote:FireClient(player, false, carry.Fish.SpeciesId, "banked")
	print(`[StealService] {player.Name} banked {carry.Fish.SpeciesId} in slot {slot}`)
end

-- Drop: someone bumped the carrier -> the fish goes home.
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

local function bankCheck()
	for carrier in Carrying do
		if alive(carrier) then
			tryBank(carrier)
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
			if carry.Victim == player then
				-- Victim left: thief keeps it — bank it now.
				tryBank(carrier)
				if Carrying[carrier] then
					-- Couldn't bank (no plot?); drop the visual, keep server state clean.
					clearCarry(carrier)
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.BankCheckInterval)
			pcall(bankCheck)
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

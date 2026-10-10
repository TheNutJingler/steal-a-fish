--!strict
--[[
	PlotService — owns aquarium plots: claiming, slot layout, fish placement,
	base locks, and aquarium upgrades (vertical expansion).

	Plots are server-owned. One per player. Slot indices:
	  1-12 ground floor, 13-20 floor 2, 21-28 floor 3, 29-40 land expansion.
	New fish always go to the highest-index free slot the owner's aquarium
	level unlocks (back-most / top-most = hardest to steal).

	Expose:
	  Init(dataService, worldService)
	  GetPlot(player) -> plot?
	  GetPlotByIndex(i) -> plot?
	  MaxSlotsFor(plot) -> number
		  TakeFishFromSlot(plot, slotIndex) -> fishData?
	  ReturnFishToSlot(plot, fishData, preferSlot) -> slotIndex?
	  IsLocked(plot) -> boolean
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

local ClaimPlotRemote = Remotes:WaitForChild("ClaimPlot") :: RemoteEvent
local RequestLockRemote = Remotes:WaitForChild("RequestLock") :: RemoteEvent
local RequestUpgradeRemote = Remotes:WaitForChild("RequestUpgrade") :: RemoteEvent
local RequestExpandRemote = Remotes:WaitForChild("RequestExpand") :: RemoteEvent
local PlotAssignedRemote = Remotes:WaitForChild("PlotAssigned") :: RemoteEvent
local PlotOwnerChangedRemote = Remotes:WaitForChild("PlotOwnerChanged") :: RemoteEvent
local PlotUpgradedRemote = Remotes:WaitForChild("PlotUpgraded") :: RemoteEvent
local PlotExpandedRemote = Remotes:WaitForChild("PlotExpanded") :: RemoteEvent
local ExpandResultRemote = Remotes:WaitForChild("ExpandResult") :: RemoteEvent
local RequestUpgradeTankRemote = Remotes:WaitForChild("RequestUpgradeTank") :: RemoteEvent
local RequestPlaceFishRemote = Remotes:WaitForChild("RequestPlaceFish") :: RemoteEvent
local PlaceFishResultRemote = Remotes:WaitForChild("PlaceFishResult") :: RemoteEvent
local UpgradeTankResultRemote = Remotes:WaitForChild("UpgradeTankResult") :: RemoteEvent
local TycoonSyncRemote = Remotes:WaitForChild("TycoonSync") :: RemoteEvent
local RequestRebirthRemote = Remotes:WaitForChild("RequestRebirth") :: RemoteEvent
local RebirthResultRemote = Remotes:WaitForChild("RebirthResult") :: RemoteEvent
local LockChangedRemote = Remotes:WaitForChild("LockChanged") :: RemoteEvent
local StatsUpdateRemote = Remotes:WaitForChild("StatsUpdate") :: RemoteEvent

type PlotRuntime = {
	Layout: any, -- WorldService.PlotLayout
	Owner: Player?,
	Slots: { [number]: string? }, -- [slotIndex] = fishUid
	FishModels: { [number]: Model? }, -- [slotIndex] = visual
	LockUntil: number, -- os.clock() timestamp; 0 = unlocked
	ClaimPrompt: ProximityPrompt,
	LockPrompt: ProximityPrompt,
	UpgradePrompt: ProximityPrompt,
}

local PlotService = {}

local DataService: any = nil
local WorldService: any = nil
local BuildService: any = nil
local StealServiceRef: any = nil

function PlotService.SetStealService(stealService: any)
	StealServiceRef = stealService
end

function PlotService.SetBuildService(buildService: any)
	BuildService = buildService
end

local Plots: { [number]: PlotRuntime } = {}
local claimLimiter = RateLimit.new(Config.RateLimit_ClaimPlot.Max, Config.RateLimit_ClaimPlot.Window)
local lockLimiter = RateLimit.new(Config.RateLimit_Lock.Max, Config.RateLimit_Lock.Window)
local upgradeLimiter = RateLimit.new(5, 30)
local tycoonLimiter = RateLimit.new(20, 30) -- tank upgrades + rebirth

local function totalSlots(): number
	return Config.SlotsPerPlot + Config.Floor2Slots + Config.Floor3Slots
		+ Config.MaxExpansionTier * Config.ExpansionSlotsPerTier
end

function PlotService.MaxSlotsFor(plot: PlotRuntime): number
	local owner = plot.Owner
	if not owner then
		return Config.SlotsPerPlot
	end
	local profile = DataService.GetProfile(owner)
	local level = if profile then profile.Data.AquariumLevel or 1 else 1
	local expansion = if profile then profile.Data.ExpansionTier or 0 else 0
	local max = Config.SlotsPerPlot
	if level >= 2 then
		max += Config.Floor2Slots
	end
	if level >= 3 then
		max += Config.Floor3Slots
	end
	max += expansion * Config.ExpansionSlotsPerTier
	return max
end

function PlotService.GetPlot(player: Player): PlotRuntime?
	for _, plot in Plots do
		if plot.Owner == player then
			return plot
		end
	end
	return nil
end

function PlotService.GetPlotByIndex(index: number): PlotRuntime?
	return Plots[index]
end

function PlotService.IsLocked(plot: PlotRuntime): boolean
	return os.clock() < plot.LockUntil
end

local function makePrompt(actionText: string, holdTime: number, maxDist: number): ProximityPrompt
	-- NOTE: does NOT parent. Callers set attributes/name BEFORE parenting so
	-- DescendantAdded observers (StealService, PlotController) see the final state.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.HoldDuration = holdTime
	prompt.MaxActivationDistance = maxDist
	prompt.RequiresLineOfSight = false
	return prompt
end

local function addStealPrompt(plotLayout: any, slotIndex: number)
	local tank = plotLayout.Folder:WaitForChild(`Tank_{slotIndex}`)
	if tank:FindFirstChild("StealPrompt") then
		return -- already has one (rejoin rebuilds, re-claims)
	end
	local stealPrompt = makePrompt("Steal Fish", Config.StealChannelTime, Config.StealMaxDistance)
	stealPrompt:SetAttribute("PlotIndex", plotLayout.Index)
	stealPrompt:SetAttribute("SlotIndex", slotIndex)
	stealPrompt.Name = "StealPrompt"
	stealPrompt.Parent = tank
	-- Place prompt: set down the fish you're carrying.
	if not tank:FindFirstChild("PlacePrompt") then
		local placePrompt = makePrompt("Place Fish", 0, 10)
		placePrompt:SetAttribute("PlotIndex", plotLayout.Index)
		placePrompt:SetAttribute("SlotIndex", slotIndex)
		placePrompt.Name = "PlacePrompt"
		placePrompt.Triggered:Connect(function(player: Player)
			local ok, msg = PlotService.PlaceCarriedFish(player, slotIndex)
			PlaceFishResultRemote:FireClient(player, ok, msg)
		end)
		placePrompt.Parent = tank
	end
end

local function broadcastOwners()
	for _, plot in Plots do
		local ownerName: string? = if plot.Owner then plot.Owner.Name else nil
		PlotOwnerChangedRemote:FireAllClients(plot.Layout.Index, ownerName)
	end
end

local function refreshSign(plot: PlotRuntime)
	if plot.Owner then
		plot.Layout.SignLabel.Text = `{plot.Owner.DisplayName}'s\nAQUARIUM`
	else
		plot.Layout.SignLabel.Text = "UNCLAIMED"
	end
end

-- Highest-index free slot at or below the owner's unlock ceiling.
local function backMostFreeSlot(plot: PlotRuntime): number?
	local max = PlotService.MaxSlotsFor(plot)
	for i = max, 1, -1 do
		if plot.Slots[i] == nil then
			return i
		end
	end
	return nil
end

function PlotService.FreeSlotCount(plot: PlotRuntime): number
	local n = 0
	for i = 1, PlotService.MaxSlotsFor(plot) do
		if plot.Slots[i] == nil then
			n += 1
		end
	end
	return n
end

local function placeVisual(plot: PlotRuntime, slotIndex: number, speciesId: string, variantId: string, uid: string)
	PlotService.ClearVisual(plot, slotIndex)
	local anchor = plot.Layout.SlotAnchors[slotIndex]
	local model = FishVisual.Build(speciesId, variantId, 0.55, uid)
	model:PivotTo(CFrame.new(anchor))
	model.Parent = plot.Layout.Folder
	plot.FishModels[slotIndex] = model
end

function PlotService.ClearVisual(plot: PlotRuntime, slotIndex: number)
	local old = plot.FishModels[slotIndex]
	if old then
		old:Destroy()
		plot.FishModels[slotIndex] = nil
	end
end

-- Place the fish you're carrying into a specific tank.
function PlotService.PlaceCarriedFish(player: Player, slotIndex: unknown): (boolean, string)
	if typeof(slotIndex) ~= "number" or slotIndex ~= math.floor(slotIndex) then
		return false, "Bad tank."
	end
	local plot = PlotService.GetPlot(player)
	if not plot then
		return false, "You have no plot."
	end
	if slotIndex < 1 or slotIndex > PlotService.MaxSlotsFor(plot) then
		return false, "No such tank."
	end
	if plot.Slots[slotIndex] ~= nil then
		return false, "Tank is occupied."
	end
	if not StealServiceRef then
		return false, "Not ready."
	end
	local carry = StealServiceRef.GetCarry(player)
	if not carry then
		return false, "You're not carrying a fish."
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "No data."
	end
	if carry.Source == "River" then
		local uid = game:GetService("HttpService"):GenerateGUID(false)
		table.insert(profile.Data.Fish, {
			Uid = uid,
			SpeciesId = carry.Fish.SpeciesId,
			VariantId = carry.Fish.VariantId,
			Slot = slotIndex,
		})
		plot.Slots[slotIndex] = uid
		placeVisual(plot, slotIndex, carry.Fish.SpeciesId, carry.Fish.VariantId, uid)
		DataService.RegisterCodexEntry(player, carry.Fish.SpeciesId, carry.Fish.VariantId)
	else
		if carry.Victim then
			if not PlotService.MoveFishToPlayer(carry.Fish, carry.Victim, player) then
				return false, "Transfer failed."
			end
		end
		local placed = PlotService.ReturnFishToSlot(plot, carry.Fish, slotIndex)
		if not placed then
			return false, "Couldn't place."
		end
		StealServiceRef.NoteBanked(carry.Fish.Uid)
		DataService.RegisterCodexEntry(player, carry.Fish.SpeciesId, carry.Fish.VariantId)
	end
	StealServiceRef.ClearCarry(player)
	print(`[PlotService] {player.Name} placed {carry.Fish.SpeciesId} in tank {slotIndex}`)
	return true, "Fish placed!"
end

-- Moves a fish record from one player's profile to another's (steal).
function PlotService.MoveFishToPlayer(
	fishData: { [string]: any },
	fromPlayer: Player,
	toPlayer: Player
): boolean
	local fromProfile = DataService.GetProfile(fromPlayer)
	local toProfile = DataService.GetProfile(toPlayer)
	if not fromProfile or not toProfile then
		return false
	end
	local removed = false
	for i = #fromProfile.Data.Fish, 1, -1 do
		if fromProfile.Data.Fish[i].Uid == fishData.Uid then
			table.remove(fromProfile.Data.Fish, i)
			removed = true
			break
		end
	end
	if not removed then
		return false
	end
	table.insert(toProfile.Data.Fish, {
		Uid = fishData.Uid,
		SpeciesId = fishData.SpeciesId,
		VariantId = fishData.VariantId,
		Slot = nil,
	})
	return true
end

-- Takes a fish out of a slot (steal): clears the slot + visual, returns the
-- fish data. The profile record moves to the thief at place time.
function PlotService.TakeFishFromSlot(plot: PlotRuntime, slotIndex: number): { [string]: any }?
	local uid = plot.Slots[slotIndex]
	if not uid then
		return nil
	end
	plot.Slots[slotIndex] = nil
	PlotService.ClearVisual(plot, slotIndex)
	local owner = plot.Owner
	if not owner then
		return nil
	end
	local profile = DataService.GetProfile(owner)
	if not profile then
		return nil
	end
	for _, fish in profile.Data.Fish do
		if fish.Uid == uid then
			return { Uid = fish.Uid, SpeciesId = fish.SpeciesId, VariantId = fish.VariantId }
		end
	end
	return nil
end

-- Puts a fish (from TakeFishFromSlot) back into a plot: preferred slot if free,
-- else the back-most free slot. Returns the slot used, or nil if plot is full.
function PlotService.ReturnFishToSlot(plot: PlotRuntime, fishData: { [string]: any }, preferSlot: number?): number?
	local owner = plot.Owner
	if not owner then
		return nil
	end
	local profile = DataService.GetProfile(owner)
	if not profile then
		return nil
	end
	local max = PlotService.MaxSlotsFor(plot)
	local slot: number? = nil
	if preferSlot and preferSlot >= 1 and preferSlot <= max and plot.Slots[preferSlot] == nil then
		slot = preferSlot
	else
		slot = backMostFreeSlot(plot)
	end
	if not slot then
		return nil
	end
	-- Re-attach the profile entry.
	for _, fish in profile.Data.Fish do
		if fish.Uid == fishData.Uid then
			fish.Slot = slot
			break
		end
	end
	plot.Slots[slot] = fishData.Uid
	placeVisual(plot, slot, fishData.SpeciesId, fishData.VariantId, fishData.Uid)
	return slot
end

function PlotService.ClaimPlot(player: Player, plotIndex: number): (boolean, string)
	if typeof(plotIndex) ~= "number" or plotIndex ~= plotIndex then
		return false, "Bad plot."
	end
	if not claimLimiter:Check(player.UserId) then
		return false, "Slow down."
	end
	local plot = Plots[math.floor(plotIndex)]
	if not plot then
		return false, "No such plot."
	end
	if plot.Owner then
		return false, "Plot is taken."
	end
	if PlotService.GetPlot(player) then
		return false, "You already have a plot."
	end
	plot.Owner = player
	plot.LockUntil = 0
	refreshSign(plot)
	plot.Layout.SpawnLocation.Enabled = true
	-- Spawn (and respawn) at the claimed base, not a random plot.
	player.RespawnLocation = plot.Layout.SpawnLocation
	if BuildService then
		BuildService.RebuildPlot(player, plot)
	end
	-- Respawn at the new plot.
	task.defer(function()
		if player:IsDescendantOf(Players) then
			player:LoadCharacterAsync()
		end
	end)
	PlotAssignedRemote:FireClient(player, plot.Layout.Index)
	broadcastOwners()
	print(`[PlotService] {player.Name} claimed plot {plot.Layout.Index}`)
	return true, "Plot claimed!"
end

local function freePlot(player: Player)
	for _, plot in Plots do
		if plot.Owner == player then
			plot.Owner = nil
			plot.LockUntil = 0
			plot.Layout.SpawnLocation.Enabled = false
			if BuildService then
				BuildService.ClearPlot(plot)
			end
			-- Clear slot visuals (fish stay in the profile, slots cleared).
			for slotIndex in plot.Slots do
				plot.Slots[slotIndex] = nil
				PlotService.ClearVisual(plot, slotIndex)
			end
			local profile = DataService.GetProfile(player)
			if profile then
				for _, fish in profile.Data.Fish do
					fish.Slot = nil
				end
			end
			refreshSign(plot)
		end
	end
	broadcastOwners()
end

function PlotService.SetLock(player: Player): (boolean, string)
	if not lockLimiter:Check(player.UserId) then
		return false, "Slow down."
	end
	local plot = PlotService.GetPlot(player)
	if not plot then
		return false, "You have no plot."
	end
	if PlotService.IsLocked(plot) then
		return false, "Already locked."
	end
	plot.LockUntil = os.clock() + Config.BaseLockDuration
	LockChangedRemote:FireAllClients(plot.Layout.Index, os.time() + Config.BaseLockDuration)
	print(`[PlotService] {player.Name} locked plot {plot.Layout.Index}`)
	return true, `Locked for {Config.BaseLockDuration}s!`
end

function PlotService.TryUpgrade(player: Player): (boolean, string)
	if not upgradeLimiter:Check(player.UserId) then
		return false, "Slow down."
	end
	local plot = PlotService.GetPlot(player)
	if not plot then
		return false, "You have no plot."
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "No data."
	end
	local level: number = profile.Data.AquariumLevel or 1
	local next = nil
	for _, row in Config.AquariumUpgrades do
		if row.Level == level + 1 then
			next = row
			break
		end
	end
	if not next then
		return false, "Aquarium maxed out!"
	end
	if profile.Data.Coins < next.Cost then
		return false, `Need ${next.Cost} coins.`
	end
	profile.Data.Coins -= next.Cost
	profile.Data.AquariumLevel = next.Level
	profile.Data.IncomeMultiplier = (profile.Data.IncomeMultiplier or 1) * next.IncomeMultiplier

	WorldService.BuildUpperFloor(plot.Layout, next.FloorsUnlocked)

	-- Steal prompts for the new floor's tanks.
	local floorStart = if next.FloorsUnlocked == 2
		then Config.SlotsPerPlot + 1
		else Config.SlotsPerPlot + Config.Floor2Slots + 1
	local floorEnd = if next.FloorsUnlocked == 2
		then Config.SlotsPerPlot + Config.Floor2Slots
		else Config.SlotsPerPlot + Config.Floor2Slots + Config.Floor3Slots
	for slotIndex = floorStart, floorEnd do
		addStealPrompt(plot.Layout, slotIndex)
	end

	PlotUpgradedRemote:FireAllClients(plot.Layout.Index, next.Level, next.DisplayName)
	-- Push fresh stats so the HUD updates immediately.
	local rate = DataService.GetBaseIncomePerSecond(profile)
		* (profile.Data.IncomeMultiplier or 1)
	StatsUpdateRemote:FireClient(player, math.floor(profile.Data.Coins), rate)
	print(`[PlotService] {player.Name} upgraded to {next.DisplayName}`)
	return true, `{next.DisplayName} unlocked! +{Config.Floor2Slots} slots.`
end

-- Land expansion purchase: pushes the lot fences out and plants 4 new
-- tank slots in the claimed ring. Tycoon-style plot growth.
-- Push tank/rebirth state to the client's Build tab.
function PlotService.SyncTycoon(player: Player)
	local plot = PlotService.GetPlot(player)
	local profile = DataService.GetProfile(player)
	if not plot or not profile then
		return
	end
	TycoonSyncRemote:FireClient(player,
		PlotService.MaxSlotsFor(plot),
		profile.Data.TankUpgrades or {},
		profile.Data.Rebirths or 0,
		profile.Data.Aquariums or {})
end

-- Upgrade one tank's level (1..TankMaxLevel). Bonus: +25% fish income/level.
function PlotService.UpgradeTank(player: Player, slotIndex: unknown): (boolean, string)
	if typeof(slotIndex) ~= "number" or slotIndex ~= math.floor(slotIndex) then
		return false, "Bad tank."
	end
	if not tycoonLimiter:Check(player.UserId) then
		return false, "Slow down."
	end
	local plot = PlotService.GetPlot(player)
	if not plot then
		return false, "You have no plot."
	end
	if slotIndex < 1 or slotIndex > PlotService.MaxSlotsFor(plot) then
		return false, "No such tank."
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "No data."
	end
	if typeof(profile.Data.TankUpgrades) ~= "table" then
		profile.Data.TankUpgrades = {}
	end
	local key = tostring(slotIndex)
	local level = profile.Data.TankUpgrades[key] or 1
	if level >= Config.TankMaxLevel then
		return false, "Tank is max level."
	end
	local cost = Config.TankUpgradeBaseCost * (2 ^ (level - 1))
	if (profile.Data.Coins or 0) < cost then
		return false, "Not enough coins."
	end
	profile.Data.Coins -= cost
	profile.Data.TankUpgrades[key] = level + 1
	PlotService.SyncTycoon(player)
	StatsUpdateRemote:FireClient(player, math.floor(profile.Data.Coins),
		DataService.GetBaseIncomePerSecond(profile) * DataService.RebirthMultiplier(profile)
			* DataService.GetCodexBonus(player))
	print(`[PlotService] {player.Name} upgraded tank {slotIndex} to Lv {level + 1}`)
	return true, `Tank {slotIndex} -> Lv {level + 1}!`
end

-- Rebirth: reset coins/fish/tank upgrades for a stacking 1.5x income multiplier.
-- Keeps the base, buildings, aquarium, land, and codex.
function PlotService.RequestRebirth(player: Player): (boolean, string)
	if not tycoonLimiter:Check(player.UserId) then
		return false, "Slow down."
	end
	local plot = PlotService.GetPlot(player)
	if not plot then
		return false, "You have no plot."
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "No data."
	end
	local cost = DataService.RebirthCost(profile)
	if (profile.Data.Coins or 0) < cost then
		return false, `Need {cost} coins to rebirth.`
	end
	profile.Data.Coins = 0
	profile.Data.Fish = {}
	profile.Data.TankUpgrades = {}
	profile.Data.Rebirths = (profile.Data.Rebirths or 0) + 1
	-- Clear the tanks.
	for slotIndex in plot.Slots do
		plot.Slots[slotIndex] = nil
		PlotService.ClearVisual(plot, slotIndex)
	end
	PlotService.SyncTycoon(player)
	StatsUpdateRemote:FireClient(player, 0,
		DataService.GetBaseIncomePerSecond(profile) * DataService.RebirthMultiplier(profile)
			* DataService.GetCodexBonus(player))
	local mult = DataService.RebirthMultiplier(profile)
	print(`[PlotService] {player.Name} rebirthed (x{mult} income)`)
	return true, `Reborn! {mult}x income forever.`
end

function PlotService.TryExpand(player: Player): (boolean, string)
	if not upgradeLimiter:Check(player.UserId) then
		return false, "Slow down."
	end
	local plot = PlotService.GetPlot(player)
	if not plot then
		return false, "You have no plot."
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "No data."
	end
	local tier: number = profile.Data.ExpansionTier or 0
	local next = nil
	for _, row in Config.LandExpansions do
		if row.Tier == tier + 1 then
			next = row
			break
		end
	end
	if not next then
		return false, "Land fully expanded!"
	end
	if profile.Data.Coins < next.Cost then
		return false, `Need ${next.Cost} coins.`
	end
	profile.Data.Coins -= next.Cost
	profile.Data.ExpansionTier = next.Tier

	WorldService.BuildExpansion(plot.Layout, next.Tier, next.LotSize)

	-- Steal prompts for the new ring's tanks.
	local baseSlots = Config.SlotsPerPlot + Config.Floor2Slots + Config.Floor3Slots
	local startSlot = baseSlots + (next.Tier - 1) * Config.ExpansionSlotsPerTier + 1
	for slotIndex = startSlot, startSlot + Config.ExpansionSlotsPerTier - 1 do
		addStealPrompt(plot.Layout, slotIndex)
	end

	PlotExpandedRemote:FireAllClients(plot.Layout.Index, next.Tier, next.DisplayName)
	local rate = DataService.GetBaseIncomePerSecond(profile)
		* (profile.Data.IncomeMultiplier or 1)
	StatsUpdateRemote:FireClient(player, math.floor(profile.Data.Coins), rate)
	print(`[PlotService] {player.Name} expanded land to {next.DisplayName}`)
	return true, `{next.DisplayName} claimed! +{Config.ExpansionSlotsPerTier} land slots.`
end

-- Restore a returning player's fish into their (freshly claimed) plot.
local function restoreFish(player: Player, plot: PlotRuntime)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local max = PlotService.MaxSlotsFor(plot)
	-- Clear any stale slot refs (e.g. upgrades changed capacity).
	for _, fish in profile.Data.Fish do
		fish.Slot = nil
	end
	for slotIndex in plot.Slots do
		plot.Slots[slotIndex] = nil
		PlotService.ClearVisual(plot, slotIndex)
	end
	-- Re-place from the back.
	for _, fish in profile.Data.Fish do
		local slot = backMostFreeSlot(plot)
		if not slot then
			break
		end
		-- Only restore up to the unlock ceiling.
		if slot > max then
			break
		end
		fish.Slot = slot
		plot.Slots[slot] = fish.Uid
		placeVisual(plot, slot, fish.SpeciesId, fish.VariantId, fish.Uid)
		DataService.RegisterCodexEntry(player, fish.SpeciesId, fish.VariantId)
	end
end

function PlotService.Init(dataService: any, worldService: any, layout: any)
	DataService = dataService
	WorldService = worldService

	for index, plotLayout in layout.Plots do
		local runtime: PlotRuntime = {
			Layout = plotLayout,
			Owner = nil,
			Slots = {},
			FishModels = {},
			LockUntil = 0,
			ClaimPrompt = nil :: any,
			LockPrompt = nil :: any,
			UpgradePrompt = nil :: any,
			}
		-- Prompts live on the sign board (parented last).
		local board = plotLayout.Folder:WaitForChild("SignBoard")
		runtime.ClaimPrompt = makePrompt("Claim Plot", 0.5, 14)
		runtime.ClaimPrompt.Parent = board
		runtime.ClaimPrompt.Triggered:Connect(function(player: Player)
			local ok, msg = PlotService.ClaimPlot(player, index)
			if not ok then
				warn(`[PlotService] claim rejected for {player.Name}: {msg}`)
			end
		end)
		runtime.LockPrompt = makePrompt(`Lock Base ({Config.BaseLockDuration}s)`, 0, 14)
		runtime.LockPrompt.Parent = board
		runtime.LockPrompt.Triggered:Connect(function(player: Player)
			PlotService.SetLock(player)
		end)
		runtime.UpgradePrompt = makePrompt("Upgrade Aquarium", 0, 14)
		runtime.UpgradePrompt.Parent = board
		runtime.UpgradePrompt.Triggered:Connect(function(player: Player)
			PlotService.TryUpgrade(player)
		end)
		-- Steal prompts on every ground-floor pedestal tank (client toggles visibility).
		-- Upper floors get theirs in TryUpgrade when built.
		for slotIndex = 1, Config.SlotsPerPlot do
			addStealPrompt(plotLayout, slotIndex)
		end
		Plots[index] = runtime
		refreshSign(runtime)
	end

	-- Remotes (also reachable via prompts; remotes let UI buttons use them).
	ClaimPlotRemote.OnServerEvent:Connect(function(player: Player, plotIndex: unknown)
		if typeof(plotIndex) == "number" then
			PlotService.ClaimPlot(player, plotIndex)
		end
	end)
	RequestLockRemote.OnServerEvent:Connect(function(player: Player)
		PlotService.SetLock(player)
	end)
	RequestUpgradeRemote.OnServerEvent:Connect(function(player: Player)
		PlotService.TryUpgrade(player)
	end)
	RequestExpandRemote.OnServerEvent:Connect(function(player: Player)
		local ok, msg = PlotService.TryExpand(player)
		ExpandResultRemote:FireClient(player, ok, msg)
	end)
	RequestUpgradeTankRemote.OnServerEvent:Connect(function(player: Player, slotIndex: unknown)
		local ok, msg = PlotService.UpgradeTank(player, slotIndex)
		UpgradeTankResultRemote:FireClient(player, ok, msg)
	end)
	RequestPlaceFishRemote.OnServerEvent:Connect(function(player: Player, slotIndex: unknown)
		local ok, msg = PlotService.PlaceCarriedFish(player, slotIndex)
		PlaceFishResultRemote:FireClient(player, ok, msg)
	end)
	RequestRebirthRemote.OnServerEvent:Connect(function(player: Player)
		local ok, msg = PlotService.RequestRebirth(player)
		RebirthResultRemote:FireClient(player, ok, msg)
	end)

	-- Auto-claim + restore on player ready.
	DataService.PlayerReady:Connect(function(player: Player, profile: any, _grant: any)
		-- Rebuild previously unlocked floors BEFORE restoring fish.
		local level: number = profile.Data.AquariumLevel or 1
		-- First free plot.
		local plot: PlotRuntime? = nil
		for _, p in Plots do
			if p.Owner == nil then
				plot = p
				break
			end
		end
		if not plot then
			warn(`[PlotService] no free plot for {player.Name}`)
			return
		end
		plot.Owner = player
		refreshSign(plot)
		plot.Layout.SpawnLocation.Enabled = true
		player.RespawnLocation = plot.Layout.SpawnLocation
		if level >= 2 then
			WorldService.BuildUpperFloor(plot.Layout, 2)
		end
		if level >= 3 then
			WorldService.BuildUpperFloor(plot.Layout, 3)
		end
		-- Rebuild previously purchased land expansions.
		local expansion: number = profile.Data.ExpansionTier or 0
		for _, row in Config.LandExpansions do
			if row.Tier <= expansion then
				WorldService.BuildExpansion(plot.Layout, row.Tier, row.LotSize)
			end
		end
		-- (Re)attach steal prompts for every unlocked non-ground slot.
		for slotIndex = Config.SlotsPerPlot + 1, PlotService.MaxSlotsFor(plot) do
			addStealPrompt(plot.Layout, slotIndex)
		end
		restoreFish(player, plot)
		if BuildService then
			BuildService.RebuildPlot(player, plot)
		end
		PlotService.SyncTycoon(player)
		PlotAssignedRemote:FireClient(player, plot.Layout.Index)
		broadcastOwners()
		task.defer(function()
			if player:IsDescendantOf(Players) then
				player:LoadCharacterAsync() -- spawn at plot
			end
		end)
	end)

	DataService.PlayerLeaving:Connect(freePlot)

	print("[PlotService] init: 8 plots")
end

return PlotService

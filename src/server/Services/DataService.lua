--!strict
--[[
	DataService — owns ALL player data. Nothing else touches the DataStore.

	Uses the vendored ProfileStore (session locking, autosave, ordered
	retries, BindToClose flushing). Exposes:
	  DataService.GetProfile(player) -> profile | nil
	  DataService.PlayerReady      -> BindableEvent (player, profile, offlineGrant)
	  DataService.PlayerLeaving    -> BindableEvent (player)

	offlineGrant = { Coins: number, SecondsAway: number } | nil — computed
	on load from LastLogout; granted immediately so the client can pop the
	"welcome back" UI.

	STUDIO FALLBACK: if the DataStore session can't start (e.g. Studio API
	access off), the player gets an in-memory mock profile and a loud
	warning. Mock profiles NEVER save — failed loads must never overwrite
	real data with defaults.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local server = ServerScriptService:WaitForChild("StealAFish")
local Packages = server:WaitForChild("Packages")
local ProfileStore = require(Packages:WaitForChild("ProfileStore"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local FishRegistry = require(Shared:WaitForChild("FishRegistry"))
local Remotes = Shared:WaitForChild("Remotes")

local OfflineEarningsRemote = Remotes:WaitForChild("OfflineEarnings") :: RemoteEvent

local DataService = {}

local TEMPLATE: { [string]: any } = {
	Coins = 0,
	LifetimeCoins = 0,
	IncomeMultiplier = 1,
	Fish = {}, -- { {Uid, SpeciesId, VariantId, Slot} }
	Codex = {}, -- ["SpeciesId:VariantId"] = true
	CodexTierBonus = {}, -- [RarityId] = true
	LastLogout = 0,
	AfkBoost = false,
	Rebirths = 0,
	AquariumLevel = 1, -- highest aquarium upgrade owned; 1 = ground floor only
	SchemaVersion = 1,
}

local PlayerStore = nil :: any
local Profiles: { [Player]: any } = {}

local PlayerReadyEvent = Instance.new("BindableEvent")
local PlayerLeavingEvent = Instance.new("BindableEvent")
DataService.PlayerReady = PlayerReadyEvent.Event
DataService.PlayerLeaving = PlayerLeavingEvent.Event

-- Deep-copy the template so sessions never share table references.
local function freshTemplate(): { [string]: any }
	local copy: { [string]: any } = {}
	for k, v in TEMPLATE do
		if typeof(v) == "table" then
			copy[k] = table.clone(v)
		else
			copy[k] = v
		end
	end
	return copy
end

function DataService.GetProfile(player: Player): any
	return Profiles[player]
end

-- Income/sec from owned fish only (no multipliers — IncomeService layers those).
function DataService.GetBaseIncomePerSecond(profile: any): number
	local total = 0
	for _, fish in profile.Data.Fish do
		local ok, built = pcall(FishRegistry.GetFish, fish.SpeciesId, fish.VariantId)
		if ok then
			total += built.IncomePerSecond
		end
	end
	return total
end

-- Codex: owning a species × variant registers it. Completing every
-- species × variant in a rarity tier grants a permanent +5% income bonus.
local CodexSyncRemote = Remotes:WaitForChild("CodexSync") :: RemoteEvent

function DataService.RegisterCodexEntry(player: Player, speciesId: string, variantId: string)
	local profile = Profiles[player]
	if not profile then
		return
	end
	local key = `{speciesId}:{variantId}`
	if profile.Data.Codex[key] then
		return -- already registered
	end
	profile.Data.Codex[key] = true

	-- Tier completion check for this fish's rarity.
	local ok, fish = pcall(FishRegistry.GetFish, speciesId, variantId)
	if ok then
		local rarity = fish.Species.Rarity
		if not profile.Data.CodexTierBonus[rarity] then
			local complete = true
			for _, species in FishRegistry.GetSpeciesByRarity(rarity) do
				for vid in FishRegistry.VARIANTS do
					if not profile.Data.Codex[`{species.Id}:{vid}`] then
						complete = false
						break
					end
				end
				if not complete then
					break
				end
			end
			if complete then
				profile.Data.CodexTierBonus[rarity] = true
				print(`[DataService] {player.Name} completed {rarity} codex tier (+5%)`)
			end
		end
	end

	local keys: { string } = {}
	for k in profile.Data.Codex do
		table.insert(keys, k)
	end
	local tiers: { string } = {}
	for t in profile.Data.CodexTierBonus do
		table.insert(tiers, t)
	end
	CodexSyncRemote:FireClient(player, keys, tiers)
end

-- 1 + 0.05 per completed rarity tier.
function DataService.GetCodexBonus(player: Player): number
	local profile = Profiles[player]
	if not profile then
		return 1
	end
	local count = 0
	for _ in profile.Data.CodexTierBonus do
		count += 1
	end
	return 1 + count * Config.CodexTierBonus
end

type OfflineGrant = {
	Coins: number,
	SecondsAway: number,
}

local function computeOfflineEarnings(profile: any): OfflineGrant?
	local lastLogout: number = profile.Data.LastLogout
	if lastLogout <= 0 then
		return nil
	end
	local now = os.time()
	local secondsAway = now - lastLogout
	if secondsAway <= 60 then
		return nil -- ignore blips; also guards clock weirdness
	end
	local cap = Config.OfflineEarningsCapHours * 3600
	local counted = math.min(secondsAway, cap)
	local rate = if profile.Data.AfkBoost
		then 1.0
		else Config.OfflineEarningsRate
	local baseIps = DataService.GetBaseIncomePerSecond(profile)
		* (profile.Data.IncomeMultiplier or 1)
	local coins = math.floor(baseIps * counted * rate)
	if coins <= 0 then
		return nil
	end
	profile.Data.Coins += coins
	profile.Data.LifetimeCoins += coins
	return { Coins = coins, SecondsAway = counted }
end

local function onPlayerAdded(player: Player)
	-- Session start. Cancel if the player left while we were loading.
	local profile = PlayerStore:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return not player:IsDescendantOf(Players)
		end,
	})

	if not profile then
		-- DataStore unreachable (Studio without API access, outage, etc.).
		-- In-memory mock: playable, NEVER saved.
		warn(
			`[DataService] Session failed for {player.Name} — using NON-PERSISTENT mock profile. `
				.. `Enable Studio API access (Game Settings > Security) for real saves.`
		)
		profile = {
			Data = freshTemplate(),
			Mock = true,
			IsActive = function()
				return player:IsDescendantOf(Players)
			end,
			EndSession = function() end,
			Reconcile = function() end,
		}
	else
		profile:Reconcile() -- schema migration: fills new template fields
		profile:AddUserId(player.UserId) -- GDPR deletion support
		profile:ListenToRelease(function()
			Profiles[player] = nil
			PlayerLeavingEvent:Fire(player)
			if player:IsDescendantOf(Players) then
				player:Kick("Data session ended elsewhere. Please rejoin.")
			end
		end)
	end

	if player:IsDescendantOf(Players) then
		Profiles[player] = profile
	else
		-- Left before load finished; don't leak the session.
		if not profile.Mock then
			profile:EndSession()
		end
		return
	end

	-- Offline earnings BEFORE anyone else reads the profile.
	local grant = computeOfflineEarnings(profile)
	profile.Data.LastLogout = 0 -- clear; set again on leave

	PlayerReadyEvent:Fire(player, profile, grant)

	if grant then
		OfflineEarningsRemote:FireClient(player, grant.Coins, grant.SecondsAway)
	end
end

local function onPlayerRemoving(player: Player)
	local profile = Profiles[player]
	Profiles[player] = nil
	PlayerLeavingEvent:Fire(player)
	if profile then
		if profile.Mock then
			-- Nothing to save.
		else
			profile.Data.LastLogout = os.time()
			profile:EndSession() -- final save + unlock
		end
	end
end

function DataService.Init()
	PlayerStore = ProfileStore.New(Config.DataStoreName, TEMPLATE)

	ProfileStore.OnError:Connect(function(message, storeName, profileKey)
		warn(`[DataService] ProfileStore error ({storeName}/{profileKey}): {message}`)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	-- Late-start safety: sweep players already here (Studio playtest edge).
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Autosave with jitter so servers don't flush simultaneously.
	task.spawn(function()
		task.wait(Config.AutosaveInterval + math.random() * 60)
		while true do
			task.wait(Config.AutosaveInterval)
			for player, profile in Profiles do
				if not profile.Mock and profile:IsActive() then
					profile:Save()
				end
			end
		end
	end)

	-- BindToClose: flush every real session in parallel (~30s budget).
	game:BindToClose(function()
		for player, profile in Profiles do
			if not profile.Mock then
				profile.Data.LastLogout = os.time()
				task.spawn(function()
					profile:EndSession()
				end)
			end
		end
		-- Give EndSession calls a moment; ProfileStore also hooks BindToClose.
		task.wait(4)
	end)

	print("[DataService] init")
end

return DataService

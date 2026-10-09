# Steal a Fish — Game Design

## The pitch
A steal-em-up: rare fish ride the river, you stock your aquarium, and you steal
trophy fish straight out of rival tanks. Tied to the Skunked Or Stacked fishing
channel — every video is an ad for the game, every player a potential viewer.

## Core loop
1. Claim an aquarium plot.
2. Grab fish off the river — rarer fish spawn rarer.
3. Fish earn coins passively, forever.
4. Steal fish from other players' tanks (server-validated, always).
5. Spend coins on upgrades → bigger income → rarer fish → rebirth → repeat.

## Fish system
17 species across 7 rarity tiers (Starter → Mythic), 7 variants (Normal → Shadow).
Top tiers are ocean species. Full table lives in `src/shared/FishRegistry.lua` —
add rows, get fish. Nothing else to wire.

## Progression — built LONG on purpose
Retention and session length are what Roblox pays for, so the climb never really ends:

- **Aquarium upgrades** (many levels): each level adds display slots and multiplies
  income. Costs scale steeply — the grind IS the game.
- **Rebirth**: at lifetime-coin milestones, reset fish + coins for a permanent
  income multiplier stack AND access to an exclusive reborn-only fish pool.
  Multiple rebirth tiers keep the top end moving.
- **Fish Codex**: owning each species × variant fills the codex. Completing a full
  rarity tier grants +5% global income. Completionists stay for months.
- **Daily streaks**: login rewards that grow with consecutive days — the
  come-back-tomorrow engine.

## AFK — two layers
- **AFK Cove** (in-game zone): park yourself there and income keeps ticking plus
  a small luck bonus. The player stays connected, so session time accrues —
  this is the layer the engagement payouts reward.
- **Offline earnings**: fish earn while you're logged out, capped at 8 hours,
  50% rate (100% with the AFK Boost pass). This is the come-back-tomorrow layer.

## Money spine
- 2x Coins / 2x Luck timed boosts (repeat-buyable — the proven engine for this genre)
- AFK Boost pass (full offline earnings + AFK luck bonus)
- Extra aquarium slots, exclusive rebirth fish access
- Creator Rewards stack on top, paid by the retention all of the above creates

## Fair-play pillars (learned from the teardowns)
- Server recomputes every steal at commit time. Never trust the client's word.
- Never replicate the spawn table to clients. No free bot APIs.
- Validate movement server-side. Rate-limit every remote.

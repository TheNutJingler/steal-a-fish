# Steal a Fish — Easy Setup

No terminal. No commands. No GitHub. Two steps, then you're done forever.

## Step 1: Run the setup (double-click, do once)

Double-click **`SETUP.bat`**. It installs Rojo, installs the Studio plugin,
links your folder to Tony's code, and turns on auto-update. Takes a minute or two.

## Step 2: That's it. Seriously.

From now on the flow is:

1. **You text Tony** what you want changed or added.
2. **New code appears** in `steal-a-fish\src` on its own within a few minutes.
3. **To build:** double-click **`SERVE.bat`** (grabs the latest, starts syncing —
   leave the black window open), open Studio, Plugins tab → **Rojo** → **Connect**.

Your 3D world lives in your Studio place file — Tony's code never touches it.
The code lives in these files — your world-building never touches it.
They meet when you hit Connect.

## What's what

- `SETUP.bat` — one-time setup. Run once. (Safe to run again if anything ever looks off.)
- `SERVE.bat` — start building. Grabs latest code + starts Rojo.
- `PULL.bat` — made by SETUP.bat. The auto-updater. You never touch this.
- `rojo/` — the Rojo tool (SETUP.bat installs it for you).
- `Rojo.rbxm` — the Studio plugin (SETUP.bat installs it for you).
- `steal-a-fish/` — the game code:
  - `src/shared/FishRegistry.lua` — **the fish list.** Baseline species + variants.
    Add a row = add a fish.
  - `src/shared/Config.lua` — all the tuning numbers in one place.
  - `src/server/` — game logic. `src/client/` — UI and input only.

## If something looks wrong

Tell Tony exactly what you see — copy the text from the black window if there is one.

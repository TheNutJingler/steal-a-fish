# Steal a Fish — Easy Setup

No terminal. No commands. No GitHub. Three steps.

## Step 1: Run the setup (double-click, do once)

Double-click **`SETUP.bat`**. It installs Rojo, installs the Studio plugin,
and checks the project builds. Takes about 30 seconds.

## Step 2: Get code updates from Tony (whenever he sends them)

Tony does all the code. When he has an update, he'll send you a download link:

1. Download the zip.
2. Extract it **into your `steal-a-fish-starter` folder** — let it replace the files.
   (Only the code gets replaced. Your Studio place file is separate and safe.)

That's it. No accounts, no syncing tools, no learning curve.

## Step 3: Connect Studio (every time you build)

1. Double-click **`SERVE.bat`** → a black window opens. Leave it open.
   (That's Rojo syncing your code. Close it when you're done building.)
2. Open Roblox Studio → your Steal a Fish place.
3. Plugins tab → **Rojo** button → **Connect**.

Now the code in `steal-a-fish/src/` shows up in Studio live.
**Edit code in a code editor (VS Code is free), never in Studio's script editor** —
Studio edits get overwritten on the next sync. (Honestly, just let Tony handle code.)

## What's what

- `SETUP.bat` — one-time setup. Run once.
- `SERVE.bat` — start syncing. Run every build session.
- `rojo/` — the Rojo tool itself (SETUP.bat installs it for you).
- `Rojo.rbxm` — the Studio plugin (SETUP.bat installs it for you).
- `steal-a-fish/` — the actual game. All code lives under `src/`.
  - `src/shared/FishRegistry.lua` — **the fish list.** Baseline species + variants.
    Add a row = add a fish.
  - `src/shared/Config.lua` — all the tuning numbers in one place.
  - `src/server/` — game logic. `src/client/` — UI and input only.

## The one rule

Your **place file** (the 3D world — aquariums, river, decorations) is yours and
lives in Studio. The **code** is Tony's and lives in these files. The zip only
ever replaces code. They meet when you hit Connect.

## If something looks wrong

Tell Tony exactly what you see — copy the text from the black window if there is one.

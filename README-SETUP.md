# Steal a Fish — Setup Guide

Everything you need to go from zero to coding in Roblox Studio.

## What's in this zip

- `rojo/` — the Rojo command-line tool (Windows). This syncs code files into Studio.
- `Rojo.rbxm` — the Rojo Studio plugin. This is the Studio side of the sync.
- `steal-a-fish/` — the game project. All the code lives here.
- `README-SETUP.md` — this file.

## Step 1: Install Rojo (the sync tool)

1. Open the `rojo/` folder. You'll see `rojo.exe`.
2. Easiest path: copy `rojo.exe` somewhere permanent, like `C:\Rojo\rojo.exe`.
3. Add it to your PATH so you can run `rojo` from anywhere:
   - Search Windows for "environment variables" → Environment Variables → Path → Edit → New → `C:\Rojo` → OK.
   - Or skip this and just open a terminal inside the folder each time. Your call.
4. Test it: open a terminal (Win+R → `cmd`) and run `rojo --version`. You should see `Rojo 7.7.0`.

## Step 2: Install the Rojo plugin in Studio

Pick ONE:

- **Easy:** with `rojo` on your PATH, run `rojo plugin install` in a terminal. Done.
- **Manual:** in Studio, go to the Plugins tab → click "Plugins Folder" → copy `Rojo.rbxm` into that folder → restart Studio.
- **Marketplace:** install "Rojo 7" from the Roblox plugin marketplace (search "Rojo").

## Step 3: GitHub (so Tony's code reaches you)

Tony can't create the repo on your account — this part's yours, two minutes:

1. Go to https://github.com/new → name it `steal-a-fish` → Create repository (keep it private).
2. In a terminal inside the `steal-a-fish/` folder, run:
   ```
   git init
   git add .
   git commit -m "initial scaffold"
   git branch -M main
   git remote add origin https://github.com/YOUR-USERNAME/steal-a-fish.git
   git push -u origin main
   ```
   (Replace YOUR-USERNAME with your GitHub username.)
3. From now on: Tony writes code → pushes to this repo → you `git pull` → the new code is on your machine.

Don't want the terminal? Install **GitHub Desktop** (https://desktop.github.com) — same thing with buttons.

## Step 4: Connect it all and see it work

1. Open Roblox Studio → new Baseplate (or your Steal a Fish place).
2. In a terminal inside `steal-a-fish/`, run: `rojo serve`
   - Leave that terminal running. That's the sync server.
3. In Studio: Plugins tab → click the **Rojo** button → **Connect**.
   - It connects to `localhost:34872` by default. Leave it.
4. Watch the magic: open `steal-a-fish/src/shared/FishRegistry.lua`, change a fish name, save — it appears in Studio instantly.

## The daily workflow

1. `git pull` — grab Tony's latest code.
2. `rojo serve` — start syncing.
3. Build/test in Studio. Play-test with the Play button.
4. Commit + push anything you change.

## Project layout

```
steal-a-fish/
├── default.project.json      ← Rojo's map: which folders go where in Studio
└── src/
    ├── server/               ← ServerScriptService: game logic (never trust the client)
    │   ├── Main.server.lua   ← boots everything
    │   └── Services/         ← DataService, PlotService, FishSpawnerService, StealService
    ├── shared/               ← ReplicatedStorage: both sides can read
    │   ├── FishRegistry.lua  ← THE fish list: baseline species + variants. Add rows = add fish.
    │   └── Config.lua        ← all tuning numbers in one place
    └── client/               ← StarterPlayerScripts: UI + input only, no game state
        └── Main.client.lua
```

## The fish system (your design)

Every fish = **baseline species** + **variant**. Baseline is the fish (Bluegill, Bass…),
variant is the modifier (Normal, Golden, Diamond…) that multiplies income.
To add a fish: add one row to `SPECIES` in FishRegistry.lua.
To add a variant: add one row to `VARIANTS`. The spawner, shop, and codex all read from here.

## Rules of the road

- **Code lives in files, not in Studio.** Edit in VS Code (or any editor), never in Studio's script editor — Studio edits get overwritten on next sync.
- **Server owns everything.** If the client says "I stole that fish," the server re-checks. Always.
- **Commit early, commit often.** GitHub is the bridge between you and Tony.

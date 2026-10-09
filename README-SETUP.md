# Steal a Fish — Easy Setup

No terminal. No commands. Three steps.

## Step 1: Run the setup (double-click)

Double-click **`SETUP.bat`**. It installs Rojo, installs the Studio plugin,
and checks the project builds. Takes about 30 seconds.

## Step 2: Put it on GitHub (2 minutes, all clicking)

Tony can't create the repo on your account, so this one's yours:

1. Go to **https://github.com/new** → name it `steal-a-fish` → Create repository.
2. Install **GitHub Desktop**: https://desktop.github.com → open it and sign in.
3. In GitHub Desktop: **File → Add Local Repository** → choose the `steal-a-fish`
   folder from this zip → **Publish repository**.

Done. From now on, Tony's code comes through GitHub: open GitHub Desktop,
hit **Fetch origin** whenever you want his latest.

## Step 3: Connect Studio (every time you build)

1. Double-click **`SERVE.bat`** → a black window opens. Leave it open.
   (That's Rojo syncing your code. Close it when you're done building.)
2. Open Roblox Studio → your Steal a Fish place.
3. Plugins tab → **Rojo** button → **Connect**.

Now edit any file in `steal-a-fish/src/` — it appears in Studio instantly.
**Edit code in a code editor (VS Code is free), never in Studio's script editor** —
Studio edits get overwritten on the next sync.

## What's what

- `SETUP.bat` — one-time setup. Run once.
- `SERVE.bat` — start syncing. Run every build session.
- `rojo/` — the Rojo tool itself (SETUP.bat installs it for you).
- `Rojo.rbxm` — the Studio plugin (SETUP.bat installs it for you).
- `steal-a-fish/` — the actual game. All code lives under `src/`.
  - `src/shared/FishRegistry.lua` — **the fish list.** Baseline species + variants.
    Add a row = add a fish. This is where your "more fish, more variants" idea lives.
  - `src/shared/Config.lua` — all the tuning numbers in one place.
  - `src/server/` — game logic. `src/client/` — UI and input only.

## If something looks wrong

Tell Tony exactly what you see — copy the text from the black window if there is one.

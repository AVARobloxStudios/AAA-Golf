# AAA Golf — Developer Setup Guide

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Roblox Studio | Latest | Game engine |
| Rojo | 7.x | File sync (Studio ↔ filesystem) |
| Wally | 0.3.x | Package manager (ProfileService, ReplicaService) |
| Selene | Latest | Lua linter |
| StyLua | Latest | Lua formatter |
| VS Code + Luau LSP | Latest | Editor + type checking |

### Install Rojo
```
aftman add UpliftGames/rojo@7
```

### Install Wally
```
aftman add UpliftGames/wally@0.3
```

## First-Time Setup

1. **Clone the repo**
   ```
   git clone <repo-url>
   cd AAA-Golf
   ```

2. **Install packages**
   ```
   wally install
   ```
   This creates `Packages/` (ReplicaService) and `ServerPackages/` (ProfileService).

3. **Start the Rojo server**
   ```
   rojo serve
   ```

4. **Connect in Roblox Studio**
   - Open the Rojo plugin in Studio
   - Connect to `localhost:34872`
   - Confirm the sync — all folders should appear

5. **Verify the structure**
   - `ReplicatedStorage/Shared/Modules/` — 8 ModuleScripts
   - `ReplicatedStorage/Network/RemoteEvents/` — 7 events
   - `ReplicatedStorage/Network/RemoteFunctions/` — 4 functions
   - `ServerScriptService/Core/` — 7 server scripts
   - `StarterPlayer/StarterPlayerScripts/Controllers/` — 7 local scripts

## Workflow

- **All Lua code** lives under `src/`. Never edit scripts inside Studio — changes won't persist.
- **Assets** (models, sounds, images) are imported directly in Studio and committed via the `.rbxl` or via Rojo model files.
- **Format before commit**: `stylua src/`
- **Lint before commit**: `selene src/`

## Folder Map (TDD §02)

```
src/
├── ReplicatedStorage/        — shared modules, network, asset configs
├── ServerScriptService/      — all server-side logic (authoritative)
├── StarterPlayer/            — client scripts (controllers + char scripts)
├── StarterGui/               — UI ScreenGui containers
└── Workspace/Courses/        — course + hole folder hierarchy
```

## Branch Conventions

- `main` — always releasable (Sprint DoD must be met before merge)
- `sprint/S0`, `sprint/S1`, … — sprint work branches
- `fix/issue-number` — bug fix branches

## Bug Labels (GitHub Issues)

| Label | Meaning |
|-------|---------|
| `P0` | Crash / data loss / blocks sprint DoD |
| `P1` | Wrong behaviour, workaround exists |
| `P2` | Polish / nice-to-have |
| `GP` | Gameplay Programmer task |
| `VA` | Visual & Audio Dev task |
| `MR` | Market Research / CM task |

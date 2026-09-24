# BobloNEXT

BobloNEXT is a Roblox UI library project focused on a compact single-file runtime, executor-friendly usage, and a UI/UX direction that will diverge from the usual Rayfield-style script hub layout.

## Status

Early development baseline.

Current goals:

- keep the full feature set we decide to carry forward;
- remove runtime branding and internal names inherited from VVind / NullUI;
- keep the base runtime self-contained: no third-party icon/font downloads;
- keep the final runtime simple to load from one `src.lua`;
- redesign the shell/navigation later without wasting time stripping working features first.

## Upstream / Credits

BobloNEXT is being developed from ideas and implementation work originating in:

- **Vind Ui Reborn / VVind-UI** — by **Skinny-yz**  
  https://github.com/Skinny-yz/VVind-UI
- **WindUI** — by **Footagesus**  
  https://github.com/Footagesus/WindUI

Vind Ui Reborn is treated here as the direct upstream reference, with WindUI as its upstream/original lineage.

BobloNEXT does not claim authorship of upstream work. Attribution to both projects and their authors must remain in this repository.

See [NOTICE.md](NOTICE.md) for provenance details and [LICENSE-WINDUI](LICENSE-WINDUI) for the MIT license shipped by WindUI.

## Planned runtime

Target usage:

```lua
local BobloNEXT = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/bobloscript/BobloNEXT/main/src.lua"
))()
```

The public API is not frozen yet.

## Runtime independence

The base `src.lua` is now self-contained with respect to UI resources:

- Material, Lucide, Phosphor, Phosphor Filled, and SF icon lookup tables are embedded directly in `src.lua`;
- BobloNEXT no longer downloads icon-map Lua files from another GitHub repository;
- fonts use Roblox-native Figtree with Gotham fallback, so no `.ttf` files are downloaded;
- there are no hardcoded upstream asset-repository URLs in the base runtime.

Optional features can still make network requests **only when you configure/use them**, for example Feedback Webhook, CloudService, AI providers, or remote Spotify artwork supplied by a configured bridge. Those endpoints are not tied to VVind's or WindUI's repositories.

The embedded icon tables map names to Roblox asset IDs. The actual icon images are still Roblox-hosted assets; they are not bundled as image files inside BobloNEXT.

## AI / LLM development instructions

Before modifying BobloNEXT with an AI coding agent, read [AGENTS.md](AGENTS.md). It documents the current architecture, compatibility rules, theme system, executor constraints, testing checklist, and upstream-attribution requirements.

## Development direction

For now we are **not** spending time deleting working VVind features just to make the code smaller.

The first structural work is:

1. establish BobloNEXT as its own repository;
2. preserve upstream attribution;
3. rename VVind / NullUI runtime branding to BobloNEXT;
4. keep third-party runtime asset repositories out of the base library;
5. keep a single-file executor-friendly build;
6. then redesign the visual shell/navigation while retaining useful controls and systems.


## Third-party icon data

The embedded icon lookup tables were mirrored from the asset data used by Vind Ui Reborn. That mirror identifies **Nebula-Softworks/Nebula-Icon-Library** as the source of the lookup tables.

See `NOTICE.md` and `LICENSE-NEBULA-ICONS` for attribution and license information.

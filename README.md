# BobloNEXT

BobloNEXT is a Roblox UI library project focused on a compact single-file runtime, executor-friendly usage, and a UI/UX direction that will diverge from the usual Rayfield-style script hub layout.

## Status

Early development baseline.

Current goals:

- keep the full feature set we decide to carry forward;
- remove runtime branding and internal names inherited from VVind / NullUI;
- remove third-party runtime dependencies over time;
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

## Development direction

For now we are **not** spending time deleting working VVind features just to make the code smaller.

The first structural work is:

1. establish BobloNEXT as its own repository;
2. preserve upstream attribution;
3. rename VVind / NullUI runtime branding to BobloNEXT;
4. remove dependency on third-party runtime asset repositories;
5. keep a single-file executor-friendly build;
6. then redesign the visual shell/navigation while retaining useful controls and systems.

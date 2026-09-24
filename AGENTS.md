# BobloNEXT — LLM / Coding Agent Instructions

This file is the canonical instruction set for AI coding agents working on BobloNEXT.

Read this file **before modifying the repository**. Then inspect the exact functions you plan to change in `src.lua` and the matching usage in `example.lua` / `Example-Color.lua`.

---

## 1. Project mission

BobloNEXT is a **single-file, executor-friendly Roblox/Luau UI library**.

The project currently starts from Vind Ui Reborn / VVind-UI and the WindUI lineage, but BobloNEXT is intended to evolve into its own UI/UX direction.

Primary goals:

- preserve the useful existing feature set;
- keep the runtime usable from one `src.lua`;
- keep the base runtime self-contained;
- support desktop and mobile;
- maintain a clean, modern UI;
- move away from generic Rayfield-like visual patterns over time;
- allow real runtime theming instead of decorative color pickers that only print values;
- avoid rebuilding the project into a large multi-module dependency tree unless explicitly requested.

Do **not** spend time deleting working features just because they look unnecessary. Removal must be explicitly requested.

---

## 2. Repository map

### `src.lua`
The source of truth.

It contains the entire runtime library in one file, including:

- lifecycle / cleanup;
- acrylic blur;
- executor capability detection;
- embedded icon lookup tables;
- responsive UI scaling;
- theme system;
- notifications / dialogs / modals;
- windows / tabs / subtabs / search;
- dock buttons and panel tabs;
- Spotify panel;
- chat panel;
- cloud panel;
- global chat panel;
- labels / sections / dividers / paragraphs;
- ratings;
- buttons / cards / changelog / loadouts;
- info grids / system info / active users / leaderboard;
- gradient cards;
- toggles / sliders / dropdowns / textboxes;
- color picker / keybind;
- console / tables / card grids;
- flags and local configs;
- CloudService;
- AI assistant;
- unload logic.

At the time this instruction was written, `src.lua` is roughly 22k+ lines. Do not treat it like a small file and do not blindly rewrite or reformat it.

### `example.lua`
The large integration/showcase example.

Use this to understand intended public API usage and to regression-test many features together.

### `Example-Color.lua`
The theme regression playground.

Use this whenever you touch:

- colors;
- surfaces;
- borders;
- text colors;
- tabs;
- toggles;
- sliders;
- dropdowns;
- inputs;
- runtime `SetTheme()` behavior.

### `README.md`
High-level project description and runtime policy.

### `NOTICE.md`
Upstream provenance and attribution. Do not remove it.

### `LICENSE-WINDUI`
WindUI MIT license.

### `LICENSE-NEBULA-ICONS`
License information for the embedded icon lookup source.

---

## 3. Non-negotiable constraints

### Keep the runtime single-file

The public runtime must remain loadable as:

```lua
local BobloNEXT = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/bobloscript/BobloNEXT/main/src.lua"
))()
```

Do not introduce required runtime `require(...)` calls to repository files.

Do not introduce Wally, Rojo, Fusion, React, Roact, npm, external package managers, or Studio-only build dependencies unless the user explicitly changes the architecture.

Development helper files are allowed, but `src.lua` must remain independently usable.

### No hidden third-party runtime dependency

The base library must not fetch code, icon maps, fonts, or mandatory assets from upstream repositories.

Do not add hardcoded runtime downloads from:

- VVind / Vind Ui Reborn;
- NullUI-Assets;
- WindUI;
- arbitrary GitHub repositories;
- arbitrary CDNs.

Embedded icon lookup tables are intentional.

Fonts currently use Roblox-native Figtree with Gotham fallback. Do not restore downloadable `.ttf` files unless explicitly requested.

Optional network features are allowed only when they are explicitly configured by the script developer/user, for example:

- Feedback webhook URL;
- CloudService backend;
- AI provider endpoint;
- Spotify bridge / artwork URL.

Those optional endpoints must not become required for the base UI to load.

### Do not remove existing features by default

The current direction is **not** to strip VVind features for size.

If a change concerns appearance, theme, layout, or architecture, preserve unrelated features.

### Preserve attribution

Never remove or weaken the attribution in:

- the header of `src.lua`;
- `README.md`;
- `NOTICE.md`;
- license files.

Important: the public VVind-UI repository did not expose a recognized license when BobloNEXT was initialized. Do not claim that all BobloNEXT / VVind-derived code is MIT merely because WindUI is MIT.

Runtime branding may be BobloNEXT, but provenance must remain documented.

---

## 4. Current architecture you must understand before editing

### Lifecycle

A previous instance is unloaded through the global hook:

```lua
__BobloNEXT_Unload
```

The library creates a single `ScreenGui` named `BobloNEXT` and destroys a stale one on reload.

Cleanup is split between:

- `Janitor` instances owned by windows/components;
- `LibJanitor` for library-wide connections/instances;
- acrylic controller cleanup;
- `BobloNEXT:Unload()`.

If you add a long-lived connection, task, instance, or controller, make sure it is cleaned up.

Do not create reload leaks.

### Root GUI

The root prefers `gethui()` when available and otherwise uses `PlayerGui`.

Keep executor capability checks defensive. Executor-specific APIs may not exist.

### Acrylic blur

Acrylic uses a camera-attached glass part plus a `DepthOfFieldEffect`.

Do not casually rewrite this subsystem while working on unrelated controls.

Any acrylic change must be tested for:

- open;
- minimize;
- reopen;
- resize;
- fullscreen;
- window destroy;
- library unload;
- camera replacement.

### Responsive scaling

The library has its own UI scale logic and exposes:

```lua
BobloNEXT:SetScaleRange(minScale, maxScale)
```

Internal layout code often converts `AbsoluteSize` / `AbsolutePosition` through `GetUIScale()`.

Do not mix scaled and unscaled pixel coordinates without checking the surrounding code.

Mobile is handled separately from desktop. A desktop fix must not silently break touch interaction.

### Popup ownership

Only one active popup should generally be open.

Use the existing popup machinery:

- `RegisterPopupOpen`;
- `RegisterPopupClose`;
- `CloseAnyOpenPopup`;
- `MakePopupBackdrop`.

Escape closes the active popup.

Do not create an unrelated popup lifecycle unless necessary.

### Keybind capture

`KeybindCapturing` prevents global shortcuts from firing while a keybind is being captured.

Do not break this behavior when editing keyboard input or window toggle logic.

---

## 5. Theme system

The theme is not just a table of decorative values. Runtime theme changes must actually update existing UI.

Current important keys include:

```lua
Background
Surface
SurfaceHigh
Border

Text
TextDim
TextSoft
Neutral

Accent
AccentSoft
OnAccent

Success
SuccessSoft
Danger

Font
FontRegular
MeasureFont

CornerRadius
CornerRadiusSm
Margin
AnimFast
AnimSlow
```

The public runtime API is:

```lua
BobloNEXT:SetTheme({
    Background = ...,
    Surface = ...,
    SurfaceHigh = ...,
    Border = ...,
    Text = ...,
    TextDim = ...,
    Accent = ...,
    AccentSoft = ...,
})
```

`Primary` aliases `Accent` and `Secondary` aliases `AccentSoft`.

### Use `ThemeBind` for persistent themed properties

If an existing instance must update when `SetTheme()` is called, bind the property:

```lua
ThemeBind(frame, "BackgroundColor3", "SurfaceHigh")
ThemeBind(label, "TextColor3", "Text")
ThemeBind(icon, "ImageColor3", "TextDim")
```

For state-dependent colors, use a resolver:

```lua
ThemeBind(toggleFrame, "BackgroundColor3", function(theme)
    return state and theme.Accent or theme.SurfaceHigh
end)
```

Resolvers are also appropriate for values such as `ColorSequence`.

### Do not confuse creation-time theme reads with live theming

This:

```lua
label.TextColor3 = BobloNEXT.Theme.Text
```

uses the current value only when the instance is created.

If the property is supposed to recolor live, use `ThemeBind`.

A hover callback that reads `BobloNEXT.Theme.Text` at event time is usually fine because it resolves the current theme when the event fires.

### Avoid random hardcoded UI colors

The codebase still contains historical hardcoded whites/grays.

Do not add more generic visual colors such as:

```lua
Color3.new(1, 1, 1)
Color3.fromRGB(255, 255, 255)
Color3.fromRGB(40, 40, 40)
```

when the value should semantically be one of:

- Surface;
- SurfaceHigh;
- Border;
- Text;
- TextDim;
- Accent;
- AccentSoft;
- OnAccent;
- Neutral;
- Success;
- Danger.

Hardcoded colors are acceptable when they are deliberately semantic and not theme colors, for example:

- a black modal backdrop;
- a hue/saturation picker technical overlay;
- explicit user-provided gradient colors;
- a product/brand-specific color such as Spotify green;
- a status color that is intentionally fixed.

Do not mechanically replace every white/black literal. Inspect context first.

### When adding a new theme key

Also update:

- the default `BobloNEXT.Theme` table;
- `SetTheme()` compatibility if needed;
- `Example-Color.lua` if the key is visually important;
- any relevant README/example documentation.

---

## 6. Public API compatibility

Avoid breaking existing script hubs.

Important library methods currently include:

```lua
BobloNEXT:SetBlurEnabled(...)
BobloNEXT:SetTheme(...)
BobloNEXT:GetIcon(...)
BobloNEXT:PreloadIcons(...)
BobloNEXT:SetScaleRange(...)

BobloNEXT:Notify(...)
BobloNEXT:Confirm(...)
BobloNEXT:Modal(...)

BobloNEXT:CreateWindow(...)

BobloNEXT:GetConfig()
BobloNEXT:SetConfig(...)
BobloNEXT:ListUIElements()
BobloNEXT:SetUIElementValue(...)

BobloNEXT:SaveConfig(...)
BobloNEXT:LoadConfig(...)
BobloNEXT:GetConfigMeta(...)
BobloNEXT:GetSavedConfig(...)
BobloNEXT:ListConfigs()
BobloNEXT:DeleteConfig(...)
BobloNEXT:RenameConfig(...)

BobloNEXT:CreateSnapshot()
BobloNEXT:RestoreSnapshot(...)

BobloNEXT:CloudService(...)
BobloNEXT:CreateAIAssistant(...)
BobloNEXT:Unload()
```

Important window methods include:

```lua
Window:SetTitle(...)
Window:IsOpen()
Window:Open()
Window:Close()
Window:Toggle()
Window:ToggleFullscreen()
Window:Destroy()

Window:AddTab(...)
Window:AddPrivateTab(...)
Window:SelectTab(...)
Window:JumpToElement(...)

Window:AddDockButton(...)
Window:AddPanelTab(...)
Window:AddSpotifyPanel(...)
Window:AddChatPanel(...)
Window:AddCloudPanel(...)
Window:AddGlobalChatPanel(...)
```

Important tab/subtab controls include:

```lua
AddSubTab
SelectSubTab
SelectSubTabByName

AddLabel
AddSection
AddDivider
AddLineText
AddParagraph

AddRating
AddButton
AddCard
AddChangelogEntry
AddLoadoutGroup
AddInfoGrid
AddSystemInfoGrid
AddActiveUsersGrid
AddLeaderboard
AddGradientCard

AddToggle
AddSlider
AddDropdown
AddTextbox
AddColorPicker
AddKeybind
AddConsole
AddTable
AddCardGrid
```

Do not rename public methods or option names casually.

Prefer additive changes.

If you intentionally change an API, update both examples and documentation in the same change.

---

## 7. Stateful control contract

Stateful controls generally participate in the flag/config system.

The shared helper is:

```lua
RegisterFlag(opts, api, kind)
```

When `opts.Flag` is present, the control is stored in:

```lua
BobloNEXT.Flags[opts.Flag]
```

and receives metadata:

- `Flag`;
- `Kind`;
- `Label`.

A stateful control should normally expose the appropriate subset of:

- `Instance`;
- `Set(...)`;
- `Get()`;
- `OnChanged(...)`;
- `Destroy()`;
- control-specific methods such as `SetRange`, `SetOptions`, `Refresh`.

Callbacks are generally spawned so they do not block UI animation.

Do not silently change callback argument shapes.

### Config serialization caveat

Current config serialization explicitly supports:

- primitive values;
- `Color3`;
- `EnumItem`;
- array-like tables.

The table serializer uses `ipairs`. Do not assume arbitrary dictionary tables are preserved.

If you change serialization, treat it as a compatibility/migration change and test existing configs.

---

## 8. UI component rules

### Search integration

User-facing controls that should be searchable should call:

```lua
self._window:_RegisterSearchable(self, title, instance)
```

Do not forget search registration for new normal controls.

### Text layout

Long descriptions are intentionally supported.

When changing control width, reserve space for right-side controls and re-check wrapped descriptions.

Do not fix clipping by simply turning off wrapping.

### Sliders

The slider has explicit drag ownership to prevent multiple sliders from fighting for input.

Preserve:

- mouse support;
- touch support;
- snapping to `Increment`;
- visual smoothing;
- cleanup on focus loss / destroy.

### Dropdowns

Dropdowns use a root-level popup so they are not clipped by the content scrolling frame.

Preserve:

- multi-select;
- single-select;
- outside-click close;
- Escape close;
- popup repositioning while the window moves;
- scrolling for long option lists.

### Textboxes

Textbox pills resize according to text/placeholder width.

Preserve focus behavior and do not let global keybinds interfere with text entry.

### Color picker

The color picker contains technical HSV colors that should not be blindly replaced with theme colors.

### Keybinds

Respect `KeybindCapturing`.

### Tables and card grids

These are complex controls. Avoid broad visual refactors that accidentally break:

- sorting;
- search;
- pagination;
- dynamic height;
- refresh/fetch callbacks;
- scroll behavior.

---

## 9. Executor compatibility

Do not assume every executor implements every function.

The library detects capabilities such as:

- `gethui`;
- `readfile`;
- `writefile`;
- `makefolder`;
- `isfolder`;
- `isfile`;
- `delfile`;
- `listfiles`;
- `getcustomasset` / `getsynasset`;
- `identifyexecutor` / `getexecutorname`;
- `syn.request` / `http_request` / `request`.

Optional features must fail gracefully when a capability is missing.

Do not turn an optional filesystem/network capability into a hard startup requirement.

Do not introduce Studio-only APIs without an executor fallback.

---

## 10. Embedded icons

Material, Lucide, Phosphor, Phosphor Filled, and SF lookup tables are embedded directly in `src.lua`.

They are intentionally large.

Rules:

- do not reformat the entire icon-data block;
- do not move it back to a remote loader;
- do not fetch it at runtime;
- do not remove its provenance/license documentation;
- do not regenerate all icon data for a change that only needs one UI fix.

The tables contain name -> Roblox asset ID mappings. The underlying image binaries remain Roblox-hosted assets.

`PreloadIcons()` remains as a compatibility API even though the maps are already embedded.

---

## 11. Optional integrations

The library intentionally retains advanced features.

### Feedback
`SendFeedbackWebhook` uses an explicitly supplied webhook URL.

### CloudService
`CloudService({ BaseUrl = ..., Script = ... })` uses a developer-configured backend.

### AI assistant
`CreateAIAssistant` uses developer-provided providers/endpoints/API keys.

Never hardcode a real API key into the repository.

### Spotify
Spotify bridge/connect/artwork behavior is optional and must remain inactive when not configured.

Do not remove these systems unless explicitly asked.

Do not make them mandatory for ordinary UI use.

---

## 12. Naming and upstream cleanup

Runtime-facing naming should be BobloNEXT.

Do not reintroduce `NullUI`, `VVind`, or Vind branding into runtime paths, globals, GUI names, config folders, API headers, or new examples.

Upstream names are still required in attribution/documentation.

There may still be old showcase-only identifiers or labels left from the initial import. When touching those exact areas, prefer BobloNEXT naming while preserving credits in `NOTICE.md`.

---

## 13. How to modify this large file safely

Do not perform a blind whole-file rewrite.

For every task:

1. Identify the exact public method/component involved.
2. Read that whole function plus adjacent shared helpers.
3. Search for every caller/reference.
4. Check whether a shared helper affects other controls.
5. Make the smallest coherent patch.
6. Preserve unrelated behavior.
7. Update the relevant example.
8. Run the regression checklist below.

For theme work, inspect both normal state and hover/pressed/focused state.

For lifecycle work, inspect cleanup paths before adding new connections/tasks.

For mobile work, inspect desktop behavior too.

Avoid formatting the embedded icon block or unrelated sections; doing so creates huge noisy diffs.

---

## 14. Regression checklist

Before considering a meaningful change complete, test the relevant subset of the following.

### Reload/lifecycle

- run the library;
- execute it again;
- old GUI is removed;
- no duplicate blur/DOF artifacts remain;
- `BobloNEXT:Unload()` cleans up.

### Window

- drag;
- resize;
- minimize;
- reopen;
- fullscreen;
- close;
- RightShift/default toggle behavior;
- mobile toggle behavior where applicable.

### Navigation

- tabs;
- subtabs;
- default tab;
- hidden/private tabs if touched;
- search button;
- Ctrl/Cmd + K;
- `JumpToElement`.

### Popups

- dropdown opens;
- outside click closes;
- Escape closes;
- popup follows window movement;
- long lists scroll.

### Core controls

- button;
- toggle;
- slider;
- dropdown;
- textbox;
- color picker;
- keybind.

### Theme

Run `Example-Color.lua` and verify visible changes to:

- window background;
- surfaces;
- borders;
- active tab;
- toggle;
- slider;
- dropdown;
- textbox;
- text;
- icons.

Then call `SetTheme()` **after the UI already exists** and confirm bound elements update live.

### Configs

When filesystem functions are available:

- save;
- list;
- load;
- rename;
- delete;
- restore snapshot;
- verify callbacks respect the `silent` argument.

### Optional systems

Only test Spotify / Cloud / AI / webhook code when valid test endpoints are intentionally configured.

---

## 15. GitHub raw cache during development

Raw GitHub may temporarily serve an older file.

When manually testing development builds, use cache busting:

```lua
local url = "https://raw.githubusercontent.com/bobloscript/BobloNEXT/main/src.lua"
local BobloNEXT = loadstring(game:HttpGet(
    url .. "?v=" .. tostring(os.clock())
))()
```

Do not diagnose a code regression until you have ruled out stale raw content.

For stable releases, a pinned tag/commit is preferable to random cache-busting URLs.

---

## 16. Required behavior when an LLM receives a task

Before editing, briefly determine:

- which public API is affected;
- which shared helpers are affected;
- whether the change can affect mobile;
- whether it can affect runtime theme updates;
- whether it can affect config flags;
- whether it introduces any new external dependency;
- whether cleanup/unload needs updating.

Then implement the smallest correct change.

Do not invent missing behavior from memory. Read the current repository version first.

Do not replace a working subsystem merely because a different architecture is cleaner.

Do not remove advanced features as “cleanup”.

Do not make the codebase modular just for architectural aesthetics.

Do not claim a change is tested if it was only statically inspected.

---

## 17. Definition of done

A BobloNEXT change is complete when:

- it solves the requested problem;
- existing public API remains compatible unless an API change was explicitly requested;
- no hidden runtime dependency was introduced;
- runtime theme behavior remains correct;
- desktop/mobile behavior was considered;
- connections/tasks are cleaned up;
- relevant example(s) were updated;
- attribution and license files remain intact;
- no unrelated feature was removed;
- the diff is focused and understandable.

# BobloNEXT — LLM Usage Prompt

Use this prompt when you want an LLM to build a Roblox executor script UI with BobloNEXT.

---

## Prompt

You are writing a Roblox executor script that uses **BobloNEXT** as its UI library.

Your job is to USE the library correctly. Do not modify BobloNEXT itself unless I explicitly ask you to.

Repository:
https://github.com/bobloscript/BobloNEXT

Main runtime:
https://raw.githubusercontent.com/bobloscript/BobloNEXT/main/src.lua

Full public showcase:
https://github.com/bobloscript/BobloNEXT/blob/main/example.lua

Theme example:
https://github.com/bobloscript/BobloNEXT/blob/main/Example-Color.lua

Before writing code:

1. Read the current `example.lua`.
2. Read the relevant methods in `src.lua` if you are unsure about an API.
3. Do not invent methods or option names.
4. Prefer the existing BobloNEXT API instead of creating custom UI objects manually.
5. Keep the script executor-friendly.
6. Do not introduce Rojo, Wally, Fusion, React, Roact, npm, or Studio-only dependencies.
7. Do not edit BobloNEXT internals unless I explicitly ask for a library change.

---

## Loading BobloNEXT

Normal usage:

```lua
local BobloNEXT = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/bobloscript/BobloNEXT/main/src.lua"
))()
```

During active development, GitHub raw caching can serve an older file. Use cache busting:

```lua
local SOURCE_URL = "https://raw.githubusercontent.com/bobloscript/BobloNEXT/main/src.lua"

local BobloNEXT = loadstring(game:HttpGet(
    SOURCE_URL .. "?v=" .. tostring(os.clock())
))()
```

Do not load any other UI library unless I explicitly ask you to.

---

## Recommended script structure

Use this general order:

1. services / game references;
2. BobloNEXT loader;
3. optional theme;
4. window;
5. tabs / subtabs;
6. UI controls;
7. game logic;
8. callbacks wired to that logic;
9. config loading if needed.

Example:

```lua
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local SOURCE_URL = "https://raw.githubusercontent.com/bobloscript/BobloNEXT/main/src.lua"

local BobloNEXT = loadstring(game:HttpGet(
    SOURCE_URL .. "?v=" .. tostring(os.clock())
))()

local Window = BobloNEXT:CreateWindow({
    Title = "My Script",
    Subtitle = "Game Name",
    Icon = "Lucide:zap",
    Size = UDim2.fromOffset(620, 440),
    MinSize = Vector2.new(480, 340),
    Draggable = true,
    Resizable = true,
    UseBlur = true,
    DefaultTab = "Main",
})

local Main = Window:AddTab({
    Name = "Main",
    Icon = "Lucide:house",
})
```

---

## Theme

Use `BobloNEXT:SetTheme({...})`.

Example:

```lua
BobloNEXT:SetTheme({
    Background  = Color3.fromRGB(17, 17, 24),
    Surface     = Color3.fromRGB(26, 26, 36),
    SurfaceHigh = Color3.fromRGB(37, 37, 48),
    Border      = Color3.fromRGB(55, 55, 70),

    Text         = Color3.fromRGB(255, 255, 255),
    TextDim      = Color3.fromRGB(156, 163, 175),
    TextSoft     = Color3.fromRGB(160, 160, 168),
    Neutral      = Color3.fromRGB(160, 160, 175),

    Accent       = Color3.fromRGB(184, 169, 255),
    AccentSoft   = Color3.fromRGB(196, 181, 253),
    OnAccent     = Color3.fromRGB(17, 17, 24),

    Success      = Color3.fromRGB(74, 222, 128),
    SuccessSoft  = Color3.fromRGB(110, 231, 183),
})
```

`Primary` may be used as an alias for `Accent`.
`Secondary` may be used as an alias for `AccentSoft`.

Apply the theme before creating the UI when possible.

BobloNEXT also supports changing the theme after the UI already exists:

```lua
BobloNEXT:SetTheme({
    Accent = Color3.fromRGB(255, 80, 140),
})
```

---

## Window

Create a window with:

```lua
local Window = BobloNEXT:CreateWindow({
    Title = "Script Name",
    Subtitle = "Optional subtitle",
    Icon = "Lucide:zap",

    Size = UDim2.fromOffset(620, 440),
    MinSize = Vector2.new(480, 340),

    Draggable = true,
    Resizable = true,
    UseBlur = true,

    DefaultTab = "Main",

    -- Optional:
    -- ToggleKeybind = Enum.KeyCode.RightShift,
})
```

Useful window methods:

```lua
Window:SetTitle("New Title", "New Subtitle")
Window:IsOpen()
Window:Open()
Window:Close()
Window:Toggle()
Window:ToggleFullscreen()
Window:Destroy()

Window:SelectTab("Main")
Window:JumpToElement("Auto Farm")
```

---

## Tabs

Create tabs:

```lua
local Main = Window:AddTab({
    Name = "Main",
    Icon = "Lucide:house",
})

local Farming = Window:AddTab({
    Name = "Farming",
    Icon = "Lucide:wheat",
})

local Player = Window:AddTab({
    Name = "Player",
    Icon = "Lucide:user",
})
```

Private tab:

```lua
local Admin = Window:AddPrivateTab({
    Name = "Admin",
    Icon = "Lucide:lock",
    Password = "1234",
})
```

Hidden tabs are supported through:

```lua
Hidden = true
```

---

## Subtabs

Create subtabs inside a tab:

```lua
local General = Main:AddSubTab({
    Name = "General",
    Icon = "Lucide:settings",
})

local Advanced = Main:AddSubTab({
    Name = "Advanced",
    Icon = "Lucide:sliders-horizontal",
})
```

Select them with:

```lua
Main:SelectSubTab(1)
Main:SelectSubTabByName("General")
```

Controls can be added to tabs or subtabs using the same API.

---

## Sections

```lua
Main:AddSection("Farming", "Lucide:wheat")
```

Divider:

```lua
Main:AddDivider()
```

Line with centered text:

```lua
Main:AddLineText("Advanced")
```

Label:

```lua
Main:AddLabel("Small informational text")
```

Paragraph:

```lua
Main:AddParagraph({
    Title = "Information",
    Icon = "Lucide:info",
    Text = "Longer text can go here.",
})
```

---

## Button

```lua
Main:AddButton({
    Text = "Teleport to Spawn",
    Description = "Teleports your character to spawn",
    Icon = "Lucide:map-pin",

    Callback = function()
        print("Button clicked")
    end,
})
```

Use buttons for one-time actions.

---

## Toggle

```lua
local AutoFarmToggle = Main:AddToggle({
    Text = "Auto Farm",
    Description = "Automatically farms selected targets",
    Icon = "Lucide:repeat-2",

    Flag = "autoFarm",
    Default = false,

    Callback = function(enabled)
        print("Auto Farm:", enabled)
    end,
})
```

Typical methods:

```lua
AutoFarmToggle:Set(true)
local enabled = AutoFarmToggle:Get()

AutoFarmToggle:OnChanged(function(value)
    print("Changed:", value)
end)

AutoFarmToggle:SetLocked(true)
AutoFarmToggle:Destroy()
```

Use a `Flag` when the setting should participate in configs.

---

## Slider

```lua
local DistanceSlider = Main:AddSlider({
    Text = "Farm Distance",
    Description = "Distance from the selected target",
    Icon = "Lucide:move-horizontal",

    Flag = "farmDistance",

    Min = 0,
    Max = 100,
    Default = 25,
    Increment = 1,
    Suffix = " studs",

    Callback = function(value)
        print("Distance:", value)
    end,
})
```

Useful methods:

```lua
DistanceSlider:Set(50)
local value = DistanceSlider:Get()

DistanceSlider:SetRange(0, 200)

DistanceSlider:OnChanged(function(value)
    print(value)
end)
```

---

## Dropdown

Single-select:

```lua
local TargetDropdown = Main:AddDropdown({
    Text = "Target",
    Description = "Choose a target",
    Icon = "Lucide:crosshair",

    Flag = "target",

    Options = {
        "Nearest",
        "Strongest",
        "Boss",
    },

    Default = "Nearest",

    Callback = function(value)
        print("Target:", value)
    end,
})
```

Multi-select:

```lua
local ESPDropdown = Main:AddDropdown({
    Text = "ESP Targets",
    Options = {
        "Players",
        "Mobs",
        "Items",
    },

    MultiSelect = true,
    Default = { "Players", "Mobs" },

    Callback = function(values)
        print(table.concat(values, ", "))
    end,
})
```

Useful methods:

```lua
TargetDropdown:Set("Boss")
local value = TargetDropdown:Get()

TargetDropdown:SetOptions({
    "Nearest",
    "Boss",
    "Quest NPC",
})

TargetDropdown:Refresh({
    "Nearest",
    "Boss",
})

TargetDropdown:OnChanged(function(value)
    print(value)
end)
```

Do not assume `Get()` returns a string when `MultiSelect = true`; it returns a list.

---

## Textbox

```lua
local NameInput = Main:AddTextbox({
    Text = "Player Name",
    Description = "Enter a username",
    Icon = "Lucide:user",

    Flag = "playerName",

    Placeholder = "Username...",
    Default = "",

    Callback = function(text, enterPressed)
        print(text, enterPressed)
    end,
})
```

Useful methods:

```lua
NameInput:Set("Builderman")
local text = NameInput:Get()

NameInput:OnChanged(function(text, enterPressed)
    print(text)
end)
```

---

## Color picker

```lua
local ESPColor = Main:AddColorPicker({
    Text = "ESP Color",
    Description = "Choose ESP color",
    Icon = "Lucide:palette",

    Flag = "espColor",

    Default = Color3.fromRGB(255, 255, 255),

    Callback = function(color)
        print(color)
    end,
})
```

Use the returned `Color3` directly.

---

## Keybind

```lua
local FlyKey = Main:AddKeybind({
    Text = "Fly Key",
    Description = "Key used to toggle fly",
    Icon = "Lucide:keyboard",

    Flag = "flyKey",

    Default = Enum.KeyCode.F,

    Callback = function(key, kind)
        print(key and key.Name, kind)

        if kind == "press" then
            print("Pressed")
        end
    end,
})
```

Do not create a separate global input listener for the same action unless necessary.

---

## Cards

Basic card:

```lua
Main:AddCard({
    Title = "Player",
    Description = "Current player information",
    Icon = "Lucide:user",
})
```

Card with Roblox avatar:

```lua
Main:AddCard({
    UserId = LocalPlayer.UserId,
    Title = LocalPlayer.DisplayName,
    Description = "Current account",
})
```

Gradient card:

```lua
Main:AddGradientCard({
    Title = "Premium Feature",
    Description = "Gradient card example",

    ColorA = Color3.fromRGB(184, 169, 255),
    ColorB = Color3.fromRGB(196, 181, 253),

    Callback = function()
        print("Clicked")
    end,
})
```

---

## Changelog

```lua
Main:AddChangelogEntry({
    Version = "1.2.0",
    Date = "2026-09-24",

    Changes = {
        { Type = "Added", Text = "Auto Farm" },
        { Type = "Changed", Text = "Improved UI" },
        { Type = "Fixed", Text = "Dropdown issue" },
    },
})
```

---

## Notifications

```lua
BobloNEXT:Notify({
    Title = "Loaded",
    Text = "Script loaded successfully",
    Type = "success",
    Duration = 4,
})
```

Custom color:

```lua
BobloNEXT:Notify({
    Title = "Custom",
    Text = "Custom notification",
    Color = Color3.fromRGB(184, 169, 255),
    Duration = 4,
})
```

Do not spam notifications for every toggle change.

---

## Confirm dialog

```lua
BobloNEXT:Confirm({
    Title = "Reset Config",
    Text = "Are you sure?",

    ConfirmText = "Reset",
    CancelText = "Cancel",

    Danger = true,
    Window = Window,

    Callback = function(confirmed)
        if confirmed then
            print("Confirmed")
        end
    end,
})
```

Use `Confirm` for yes/no decisions.

---

## Modal with fields

Use `BobloNEXT:Modal({...})` when multiple user inputs are required.

Read the current `example.lua` before generating a complex Modal because field definitions may evolve.

---

## Console

```lua
local Console = Main:AddConsole({
    Title = "Logs",
    Height = 180,
    MaxLogs = 100,
})
```

Use the returned console API shown in `example.lua`.

---

## Table

```lua
local Table = Main:AddTable({
    Title = "Players",
    Description = "Current server players",

    Columns = {
        { Key = "Name", Label = "Name" },
        { Key = "Level", Label = "Level" },
    },

    Height = 240,
    RowHeight = 30,
    Sortable = true,
    Striped = true,
})
```

When using `AddTable`, read the current `example.lua` for the current row/update methods instead of inventing names.

---

## Card grid

Use `AddCardGrid` for searchable/sortable collections of cards.

Important options include:

```lua
Title
Height
Columns
MinColumns
MaxColumns
CardWidth
CardMinWidth
CardHeight
CardPadding
OuterPadding
PageSize
Search
SearchPlaceholder
Sorts
DefaultSort
Fetch
Render
AutoLoad
```

Because `AddCardGrid` has a larger API surface, inspect the current `example.lua` and `src.lua` before writing a non-trivial implementation.

Do not guess the expected item structure.

---

## Config flags

For stateful controls, use unique flags:

```lua
Flag = "autoFarm"
Flag = "farmDistance"
Flag = "selectedTarget"
Flag = "espColor"
Flag = "flyKey"
```

Do not reuse the same flag for two unrelated controls.

Get current UI state:

```lua
local data = BobloNEXT:GetConfig()
```

Set state:

```lua
BobloNEXT:SetConfig(data)
```

List registered controls:

```lua
local elements = BobloNEXT:ListUIElements()
```

Set one control by flag:

```lua
BobloNEXT:SetUIElementValue("autoFarm", true)
```

---

## Saving configs

When the executor supports file APIs:

```lua
BobloNEXT:SaveConfig("default", {
    Description = "Main config",
    Tags = { "farm", "main" },
})
```

Load:

```lua
BobloNEXT:LoadConfig("default")
```

Other config methods:

```lua
BobloNEXT:GetConfigMeta("default")
BobloNEXT:GetSavedConfig("default")
BobloNEXT:ListConfigs()
BobloNEXT:DeleteConfig("default")
BobloNEXT:RenameConfig("default", "main")
```

Snapshots:

```lua
local snapshot = BobloNEXT:CreateSnapshot()

-- later
BobloNEXT:RestoreSnapshot(snapshot)
```

Do not assume filesystem APIs exist on every executor. Handle failures when config persistence is important.

---

## Search

Normal controls are searchable through the window search system.

Users can use the search button or Ctrl/Cmd + K.

Programmatic jump:

```lua
Window:JumpToElement("Auto Farm")
```

Use clear human-readable control names so search is useful.

---

## Dock buttons and panels

BobloNEXT supports dock buttons and panel tabs.

Example:

```lua
local Dock = Window:AddDockButton({
    Name = "Tools",
    Icon = "Lucide:wrench",

    Callback = function()
        print("Dock clicked")
    end,
})
```

Use the current `example.lua` as the source of truth for complex panel APIs.

---

## Optional advanced systems

BobloNEXT currently includes:

- Spotify panel;
- chat panel;
- cloud panel;
- global chat panel;
- CloudService;
- AI assistant;
- feedback/rating webhook support;
- active users grid;
- leaderboard.

These are optional.

Do not configure external endpoints unless I explicitly provide them.

Never invent API keys, webhook URLs, cloud backends, Spotify bridge URLs, or AI credentials.

If no endpoint is provided, keep those features disabled or omit them.

---

## Icons

BobloNEXT has embedded icon lookup tables for:

- Lucide;
- Material;
- Phosphor;
- Phosphor Filled;
- SF Symbols.

Examples:

```lua
Icon = "Lucide:house"
Icon = "Material:settings"
Icon = "Phosphor:gear"
Icon = "SF:gear"
```

If you are unsure whether an icon exists, use a common Lucide icon or inspect the embedded icon table instead of inventing a name.

Do not fetch a separate icon library.

---

## Mobile / responsive usage

Do not hardcode the UI around one monitor resolution.

Prefer the built-in responsive system.

Use a reasonable window size such as:

```lua
Size = UDim2.fromOffset(620, 440)
MinSize = Vector2.new(480, 340)
```

Let BobloNEXT handle its mobile sizing.

Avoid custom absolute-position overlays unless necessary.

For a normal script hub, prefer tabs/subtabs and BobloNEXT controls over manually creating extra ScreenGuis.

---

## Code-generation rules for the LLM

When I ask you to create or convert a Roblox script to BobloNEXT:

1. Preserve the script's actual game logic.
2. Replace only the UI layer unless I ask for broader changes.
3. Keep callbacks connected to the original variables/functions.
4. Do not rename game-specific variables/functions unnecessarily.
5. Do not invent unsupported BobloNEXT APIs.
6. Use `Flag` for settings that should be saved.
7. Use meaningful tab/control names.
8. Keep descriptions short and useful.
9. Avoid excessive sections and visual clutter.
10. Do not add AI, Cloud, Spotify, webhooks, ratings, or leaderboards unless requested.
11. Do not add a second UI library.
12. Do not copy old Rayfield/Orion APIs and pretend they are BobloNEXT.
13. Do not directly edit `src.lua`.
14. If an API is uncertain, inspect current `example.lua` or `src.lua` first.
15. Return a complete executable script unless I ask for a partial patch.

---

## Preferred UI organization for ordinary Roblox scripts

For small scripts:

```text
Main
Settings
```

For medium scripts:

```text
Main
Farming
Combat
Player
Visuals
Settings
```

For large scripts, use subtabs instead of creating an excessive number of top-level tabs.

Example:

```text
Farming
  General
  Bosses
  Quests

Player
  Movement
  Teleports

Visuals
  ESP
  World
```

Do not create a section for every two controls.

---

## Minimal complete example

```lua
local SOURCE_URL = "https://raw.githubusercontent.com/bobloscript/BobloNEXT/main/src.lua"

local BobloNEXT = loadstring(game:HttpGet(
    SOURCE_URL .. "?v=" .. tostring(os.clock())
))()

BobloNEXT:SetTheme({
    Background  = Color3.fromRGB(17, 17, 24),
    Surface     = Color3.fromRGB(26, 26, 36),
    SurfaceHigh = Color3.fromRGB(37, 37, 48),
    Text         = Color3.fromRGB(255, 255, 255),
    TextDim      = Color3.fromRGB(156, 163, 175),
    Accent       = Color3.fromRGB(184, 169, 255),
    AccentSoft   = Color3.fromRGB(196, 181, 253),
})

local Window = BobloNEXT:CreateWindow({
    Title = "Example Hub",
    Subtitle = "BobloNEXT",
    Icon = "Lucide:zap",
    Size = UDim2.fromOffset(620, 440),
    MinSize = Vector2.new(480, 340),
    Draggable = true,
    Resizable = true,
    UseBlur = true,
    DefaultTab = "Main",
})

local Main = Window:AddTab({
    Name = "Main",
    Icon = "Lucide:house",
})

Main:AddSection("Automation", "Lucide:repeat-2")

local AutoFarm = Main:AddToggle({
    Text = "Auto Farm",
    Description = "Automatically farms targets",
    Icon = "Lucide:repeat-2",
    Flag = "autoFarm",
    Default = false,

    Callback = function(enabled)
        print("Auto Farm:", enabled)
    end,
})

local Distance = Main:AddSlider({
    Text = "Farm Distance",
    Icon = "Lucide:move-horizontal",
    Flag = "farmDistance",
    Min = 0,
    Max = 100,
    Default = 25,
    Increment = 1,
    Suffix = " studs",

    Callback = function(value)
        print("Distance:", value)
    end,
})

local Target = Main:AddDropdown({
    Text = "Target",
    Icon = "Lucide:crosshair",
    Flag = "target",
    Options = {
        "Nearest",
        "Strongest",
        "Boss",
    },
    Default = "Nearest",

    Callback = function(value)
        print("Target:", value)
    end,
})

Main:AddButton({
    Text = "Teleport to Spawn",
    Icon = "Lucide:map-pin",

    Callback = function()
        print("Teleport")
    end,
})

local Settings = Window:AddTab({
    Name = "Settings",
    Icon = "Lucide:settings",
})

Settings:AddButton({
    Text = "Save Config",
    Icon = "Lucide:save",

    Callback = function()
        local ok, err = BobloNEXT:SaveConfig("default")
        BobloNEXT:Notify({
            Title = ok and "Saved" or "Error",
            Text = ok and "Config saved." or tostring(err),
            Type = ok and "success" or "error",
            Duration = 3,
        })
    end,
})

Settings:AddButton({
    Text = "Load Config",
    Icon = "Lucide:folder-open",

    Callback = function()
        local ok, err = BobloNEXT:LoadConfig("default")
        BobloNEXT:Notify({
            Title = ok and "Loaded" or "Error",
            Text = ok and "Config loaded." or tostring(err),
            Type = ok and "success" or "error",
            Duration = 3,
        })
    end,
})
```

---

## Final instruction

When generating a BobloNEXT script, prioritize:

- correct game logic;
- correct current BobloNEXT API;
- compact UI structure;
- working callbacks;
- executor compatibility;
- mobile usability;
- useful flags/configs;
- no invented library methods;
- no unnecessary external dependencies.

If the requested feature is not clearly demonstrated in `example.lua`, inspect `src.lua` before using it.

-- BobloNEXT Example-Color
-- Palette:
-- #a0a0af - #111118
-- #b8a9ff - #c4b5fd
-- #ffffff
-- #9ca3af - #a0a0a8
-- #4ade80 - #6ee7b7
-- #1a1a24 - #252530

local BobloNEXT = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/bobloscript/BobloNEXT/main/src.lua"
))()

local Colors = {
    Neutral     = Color3.fromRGB(160, 160, 175), -- #a0a0af
    Background  = Color3.fromRGB(17, 17, 24),    -- #111118

    Purple      = Color3.fromRGB(184, 169, 255), -- #b8a9ff
    PurpleSoft  = Color3.fromRGB(196, 181, 253), -- #c4b5fd

    White       = Color3.fromRGB(255, 255, 255), -- #ffffff

    TextMuted   = Color3.fromRGB(156, 163, 175), -- #9ca3af
    TextSoft    = Color3.fromRGB(160, 160, 168), -- #a0a0a8

    Green       = Color3.fromRGB(74, 222, 128),  -- #4ade80
    GreenSoft   = Color3.fromRGB(110, 231, 183), -- #6ee7b7

    Surface     = Color3.fromRGB(26, 26, 36),    -- #1a1a24
    SurfaceHigh = Color3.fromRGB(37, 37, 48),    -- #252530
}

-- Apply the palette before creating the window.
BobloNEXT.Theme.Background = Colors.Background
BobloNEXT.Theme.Surface = Colors.Surface
BobloNEXT.Theme.Text = Colors.White
BobloNEXT.Theme.TextDim = Colors.TextMuted
BobloNEXT.Theme.Accent = Colors.Purple
BobloNEXT.Theme.Danger = Colors.Neutral

local Window = BobloNEXT:CreateWindow({
    Title = "Example-Color",
    Subtitle = "BobloNEXT palette test",
    Icon = "Lucide:palette",
    Size = UDim2.fromOffset(620, 440),
    MinSize = Vector2.new(480, 340),
    Draggable = true,
    Resizable = true,
    UseBlur = true,
    DefaultTab = "Main",
})

local Main = Window:AddTab({
    Name = "Main",
    Icon = "Lucide:palette",
})

Main:AddSection("Controls", "Lucide:sliders-horizontal")

Main:AddToggle({
    Text = "Example Toggle",
    Description = "Simple placeholder toggle",
    Icon = "Lucide:toggle-right",
    Default = true,
    Callback = function(value)
        print("Example Toggle:", value)
    end,
})

Main:AddSlider({
    Text = "Example Slider",
    Description = "Simple placeholder slider",
    Icon = "Lucide:sliders-horizontal",
    Min = 0,
    Max = 100,
    Default = 50,
    Increment = 1,
    Callback = function(value)
        print("Example Slider:", value)
    end,
})

Main:AddDropdown({
    Text = "Example Dropdown",
    Description = "Simple placeholder dropdown",
    Icon = "Lucide:chevrons-up-down",
    Options = { "Option A", "Option B", "Option C" },
    Default = "Option A",
    Callback = function(value)
        print("Example Dropdown:", value)
    end,
})

Main:AddTextbox({
    Text = "Example Input",
    Description = "Simple placeholder input",
    Icon = "Lucide:text-cursor-input",
    Placeholder = "Type something...",
    Default = "",
    Callback = function(text, enterPressed)
        print("Example Input:", text, enterPressed)
    end,
})

Main:AddButton({
    Text = "Example Button",
    Description = "Shows a test notification",
    Icon = "Lucide:mouse-pointer-click",
    Callback = function()
        BobloNEXT:Notify({
            Title = "Example-Color",
            Text = "The palette is active.",
            Type = "success",
            Color = Colors.Green,
            Duration = 3,
        })
    end,
})

Main:AddSection("Palette", "Lucide:swatch-book")

Main:AddGradientCard({
    Title = "Purple Accent",
    Description = "#b8a9ff → #c4b5fd",
    ColorA = Colors.Purple,
    ColorB = Colors.PurpleSoft,
})

Main:AddGradientCard({
    Title = "Green Accent",
    Description = "#4ade80 → #6ee7b7",
    ColorA = Colors.Green,
    ColorB = Colors.GreenSoft,
})

Main:AddGradientCard({
    Title = "Dark Surfaces",
    Description = "#1a1a24 → #252530",
    ColorA = Colors.Surface,
    ColorB = Colors.SurfaceHigh,
})

Main:AddParagraph({
    Title = "Text colors",
    Icon = "Lucide:type",
    Text = "#ffffff primary · #9ca3af muted · #a0a0a8 soft · #a0a0af neutral",
})

BobloNEXT:Notify({
    Title = "Example-Color",
    Text = "Color example loaded.",
    Type = "success",
    Color = Colors.Green,
    Duration = 3,
})

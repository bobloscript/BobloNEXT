-- BobloNEXT
-- Derived from Vind Ui Reborn / VVind-UI by Skinny-yz
-- Upstream lineage includes WindUI by Footagesus
-- See README.md and NOTICE.md for attribution and licensing notes.

--!nonstrict
local TweenService      = game:GetService("TweenService")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TextService       = game:GetService("TextService")
local Lighting          = game:GetService("Lighting")
local HttpService       = game:GetService("HttpService")
local GuiService        = game:GetService("GuiService")
 
local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")
 
local IsMobileDevice = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
 
local BobloNEXT = {}
BobloNEXT.__index = BobloNEXT
BobloNEXT.Version = "2.8.1"
BobloNEXT.Flags = {}
BobloNEXT._Windows = {}
 
local function GetGlobalTable()
	local ok, g = pcall(function()
		if getgenv then return getgenv() end
		return _G
	end)
	return (ok and g) or _G
end
 
do
	local globalTable = GetGlobalTable()
	local previousUnload = globalTable.__BobloNEXT_Unload
	globalTable.__BobloNEXT_Unload = nil
	if type(previousUnload) == "function" then
		pcall(previousUnload)
	end
end
 
local Janitor = {}
Janitor.__index = Janitor
 
function Janitor.new()
	return setmetatable({ _items = {}, _dead = false }, Janitor)
end
 
function Janitor:Add(item)
	if self._dead then
		if typeof(item) == "RBXScriptConnection" then
			item:Disconnect()
		elseif typeof(item) == "Instance" then
			item:Destroy()
		end
		return item
	end
	table.insert(self._items, item)
	return item
end
 
function Janitor:Destroy()
	if self._dead then return end
	self._dead = true
	for i = #self._items, 1, -1 do
		local item = self._items[i]
		self._items[i] = nil
		local t = typeof(item)
		if t == "RBXScriptConnection" then
			pcall(function() item:Disconnect() end)
		elseif t == "Instance" then
			pcall(function() item:Destroy() end)
		elseif t == "function" then
			pcall(item)
		elseif t == "table" and type(item.Destroy) == "function" then
			pcall(function() item:Destroy() end)
		end
	end
end
 
local LibJanitor = Janitor.new()
 
local function MakeSignal()
	local listeners = {}
	return {
		Fire = function(...)
			for _, fn in ipairs(table.clone(listeners)) do
				task.spawn(fn, ...)
			end
		end,
		Connect = function(fn)
			table.insert(listeners, fn)
			return {
				Disconnect = function()
					local i = table.find(listeners, fn)
					if i then table.remove(listeners, i) end
				end,
			}
		end,
		Clear = function()
			table.clear(listeners)
		end,
	}
end
 
local function SafeClamp(value, lo, hi)
	if hi < lo then return lo end
	return math.clamp(value, lo, hi)
end
 
local function SafeAlpha(value, min, max)
	local range = max - min
	if range == 0 then return 0 end
	return math.clamp((value - min) / range, 0, 1)
end
 
local function SnapToIncrement(raw, min, max, increment)
	if increment <= 0 then increment = 1 end
	local snapped = math.floor((raw - min) / increment + 0.5) * increment + min
	snapped = math.clamp(snapped, min, max)
	local decimals = 0
	local probe = increment
	while decimals < 6 and math.abs(probe - math.floor(probe + 0.5)) > 1e-9 do
		probe = probe * 10
		decimals = decimals + 1
	end
	local factor = 10 ^ decimals
	return math.floor(snapped * factor + (snapped >= 0 and 0.5 or -0.5)) / factor
end
 
local function FormatNumber(v)
	if math.abs(v - math.floor(v + 0.5)) < 1e-9 then
		return tostring(math.floor(v + 0.5))
	end
	return string.format("%.4g", v)
end
 
local ACRYLIC_DOF_NAME = "BobloNEXT_AcrylicDOF"
local ACRYLIC_DISTANCE = 0.001
local ACRYLIC_TRANSPARENCY = 0.98
local AcrylicDOF = nil
local AcrylicControllers = {}
local CameraConnections = {}
local AcrylicShuttingDown = false
 
BobloNEXT.Config = { Blur = true, MaxNotifications = 5 }
 
local function DisconnectCameraSignals()
	for i = #CameraConnections, 1, -1 do
		CameraConnections[i]:Disconnect()
		CameraConnections[i] = nil
	end
end
 
local function EnsureAcrylicDOF()
	if AcrylicDOF and AcrylicDOF.Parent then return AcrylicDOF end
	local stale = Lighting:FindFirstChild(ACRYLIC_DOF_NAME)
	if stale then stale:Destroy() end
 
	local dof = Instance.new("DepthOfFieldEffect")
	dof.Name = ACRYLIC_DOF_NAME
	dof.FarIntensity = 0
	dof.FocusDistance = 0.05
	dof.InFocusRadius = 0.1
	dof.NearIntensity = 1
	dof.Enabled = false
	dof.Parent = Lighting
	AcrylicDOF = dof
	LibJanitor:Add(dof)
	return dof
end
 
local function RefreshAcrylicEffect()
	if AcrylicShuttingDown then return end
	local dof = EnsureAcrylicDOF()
	dof.Enabled = BobloNEXT.Config.Blur ~= false and #AcrylicControllers > 0
end
 
local function UpdateAllAcrylic()
	for index = #AcrylicControllers, 1, -1 do
		local controller = AcrylicControllers[index]
		if controller.Destroyed then
			table.remove(AcrylicControllers, index)
		else
			controller:Update()
		end
	end
end
 
local function BindAcrylicCamera(camera)
	DisconnectCameraSignals()
	if not camera then return end
 
	local function connect(property)
		table.insert(CameraConnections,
			camera:GetPropertyChangedSignal(property):Connect(UpdateAllAcrylic))
	end
	connect("CFrame")
	connect("ViewportSize")
	connect("FieldOfView")
	UpdateAllAcrylic()
end
 
local function CreateWindowAcrylic(guiObject)
	local folder = Instance.new("Folder")
	folder.Name = "BobloNEXT_AcrylicWindow"
 
	local part = Instance.new("Part")
	part.Name = "Glass"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Material = Enum.Material.Glass
	part.Color = Color3.new(0, 0, 0)
	part.Reflectance = 0
	part.Size = Vector3.new(1, 1, 0.001)
	part.Transparency = 1
	part.Parent = folder
 
	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "AcrylicMesh"
	mesh.MeshType = Enum.MeshType.Brick
	mesh.Offset = Vector3.new(0, 0, -0.000001)
	mesh.Scale = Vector3.new(1, 1, 0.001)
	mesh.Parent = part
 
	local controller = {
		Gui = guiObject,
		Folder = folder,
		Part = part,
		Mesh = mesh,
		Connections = {},
		Destroyed = false,
	}
 
	function controller:Update()
		if self.Destroyed then return end
		local camera = workspace.CurrentCamera
		local gui = self.Gui
		if not camera or not gui or not gui.Parent then
			self.Part.Transparency = 1
			return
		end
 
		if self.Folder.Parent ~= camera then
			self.Folder.Parent = camera
		end
 
		local size = gui.AbsoluteSize
		local visible = BobloNEXT.Config.Blur ~= false
			and gui.Visible and size.X > 2 and size.Y > 2
		self.Part.Transparency = visible and ACRYLIC_TRANSPARENCY or 1
		if not visible then return end
 
		local edgeInset = math.clamp(camera.ViewportSize.Y * 0.012, 8, 18)
		local position = gui.AbsolutePosition + Vector2.new(edgeInset, edgeInset)
		local panelSize = Vector2.new(
			math.max(1, size.X - edgeInset * 2),
			math.max(1, size.Y - edgeInset * 2)
		)
 
		local function ScreenToWorld(point)
			local ray = camera:ScreenPointToRay(point.X, point.Y)
			return ray.Origin + ray.Direction * ACRYLIC_DISTANCE
		end
 
		local topLeft3D = ScreenToWorld(position)
		local topRight3D = ScreenToWorld(position + Vector2.new(panelSize.X, 0))
		local bottomRight3D = ScreenToWorld(position + panelSize)
		local width = (topRight3D - topLeft3D).Magnitude
		local height = (bottomRight3D - topRight3D).Magnitude
		local renderCFrame = camera:GetRenderCFrame()
 
		self.Part.CFrame = CFrame.fromMatrix(
			(topLeft3D + bottomRight3D) / 2,
			renderCFrame.XVector,
			renderCFrame.YVector,
			renderCFrame.ZVector
		)
		self.Mesh.Scale = Vector3.new(width, height, 0.001)
	end
 
	function controller:Destroy()
		if self.Destroyed then return end
		self.Destroyed = true
		for _, connection in ipairs(self.Connections) do
			connection:Disconnect()
		end
		table.clear(self.Connections)
		local index = table.find(AcrylicControllers, self)
		if index then table.remove(AcrylicControllers, index) end
		if self.Folder then self.Folder:Destroy() end
		RefreshAcrylicEffect()
	end
 
	for _, property in ipairs({ "AbsolutePosition", "AbsoluteSize", "Visible" }) do
		table.insert(controller.Connections,
			guiObject:GetPropertyChangedSignal(property):Connect(function()
				controller:Update()
			end))
	end
	table.insert(controller.Connections, guiObject.AncestryChanged:Connect(function()
		if not guiObject.Parent then controller:Destroy() end
	end))
 
	table.insert(AcrylicControllers, controller)
	RefreshAcrylicEffect()
	controller:Update()
	return controller
end
 
BindAcrylicCamera(workspace.CurrentCamera)
LibJanitor:Add(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	BindAcrylicCamera(workspace.CurrentCamera)
end))
LibJanitor:Add(function()
	DisconnectCameraSignals()
end)
 
function BobloNEXT:SetBlurEnabled(enabled)
	BobloNEXT.Config.Blur = enabled and true or false
	RefreshAcrylicEffect()
	UpdateAllAcrylic()
end
 
local function DestroyAllAcrylicControllers()
	for index = #AcrylicControllers, 1, -1 do
		AcrylicControllers[index]:Destroy()
	end
	table.clear(AcrylicControllers)
end
 
local ASSETS_FOLDER = "BobloNEXT/Assets"
 
local function hasFn(name)
	local ok, fn = pcall(function()
		if getgenv then
			local v = getgenv()[name]
			if type(v) == "function" then return v end
		end
		if getfenv then
			local v = getfenv(1)[name]
			if type(v) == "function" then return v end
		end
		return _G[name]
	end)
	if ok and type(fn) == "function" then return fn end
	return nil
end
 
local fn_isfolder    = hasFn("isfolder")
local fn_makefolder  = hasFn("makefolder")
local fn_isfile      = hasFn("isfile")
local fn_writefile   = hasFn("writefile")
local fn_readfile    = hasFn("readfile")
local fn_delfile     = hasFn("delfile")
local fn_listfiles   = hasFn("listfiles")
local fn_customasset = hasFn("getcustomasset") or hasFn("getsynasset")
 
local function EnsureAssetsFolder()
	if not (fn_isfolder and fn_makefolder) then return false end
	local ok = pcall(function()
		if not fn_isfolder("BobloNEXT") then fn_makefolder("BobloNEXT") end
		if not fn_isfolder(ASSETS_FOLDER) then fn_makefolder(ASSETS_FOLDER) end
	end)
	return ok
end
 
local function PrivateTabFlagPath(name)
	local safe = tostring(name or ""):gsub("[^%w_%-]", "_")
	return "BobloNEXT/PrivateTab_" .. safe .. ".remember"
end
 
local function IsPrivateTabRemembered(name)
	if not fn_isfile then return false end
	local ok, exists = pcall(fn_isfile, PrivateTabFlagPath(name))
	return ok and exists == true
end
 
local function SetPrivateTabRemembered(name, remember)
	local path = PrivateTabFlagPath(name)
	if remember then
		if not fn_writefile then return end
		EnsureAssetsFolder()
		pcall(fn_writefile, path, "1")
	else
		if not (fn_isfile and fn_delfile) then return end
		local ok, exists = pcall(fn_isfile, path)
		if ok and exists then pcall(fn_delfile, path) end
	end
end
 
local RunCountPath = "BobloNEXT/RunCount.txt"
 
local function BumpRunCount()
	local count = 1
	if fn_isfile and fn_readfile and fn_isfile(RunCountPath) then
		local ok, data = pcall(fn_readfile, RunCountPath)
		local n = ok and tonumber(data)
		if n then count = math.floor(n) + 1 end
	end
	if fn_writefile then
		EnsureAssetsFolder()
		pcall(fn_writefile, RunCountPath, tostring(count))
	end
	return count
end
 
local function GetExecutorName()
	local ok, name, version = pcall(function()
		if identifyexecutor then return identifyexecutor() end
		if getexecutorname then return getexecutorname() end
		if syn and syn.get_executor_name then return syn.get_executor_name() end
		return nil
	end)
	if ok and name and name ~= "" then
		return version and version ~= "" and (tostring(name) .. " " .. tostring(version)) or tostring(name)
	end
	return "Unknown"
end
 
local function FormatClock(minutesAfterMidnight)
	minutesAfterMidnight = minutesAfterMidnight or 0
	local h = math.floor(minutesAfterMidnight / 60) % 24
	local m = math.floor(minutesAfterMidnight % 60)
	local suffix = h >= 12 and "PM" or "AM"
	local h12 = h % 12
	if h12 == 0 then h12 = 12 end
	return string.format("%02d:%02d %s", h12, m, suffix)
end
 
local function LoadFonts()
	-- BobloNEXT intentionally uses Roblox-native fonts only.
	-- No font files are downloaded at runtime.
	local ok, native = pcall(function()
		return {
			Regular  = Font.new("rbxasset://fonts/families/Figtree.json", Enum.FontWeight.Regular,  Enum.FontStyle.Normal),
			SemiBold = Font.new("rbxasset://fonts/families/Figtree.json", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),
		}
	end)
	if ok and native then return native end

	return {
		Regular  = Font.fromEnum(Enum.Font.Gotham),
		SemiBold = Font.fromEnum(Enum.Font.GothamSemibold),
	}
end

local Fonts = LoadFonts()
 
BobloNEXT.Theme = {
	Background     = Color3.fromRGB(16, 16, 16),
	Surface        = Color3.fromRGB(24, 24, 24),
	SurfaceHigh    = Color3.fromRGB(37, 37, 48),
	Border         = Color3.fromRGB(62, 62, 74),

	Text           = Color3.fromRGB(240, 240, 240),
	TextDim        = Color3.fromRGB(150, 150, 155),
	TextSoft       = Color3.fromRGB(170, 170, 178),
	Neutral        = Color3.fromRGB(160, 160, 175),

	Accent         = Color3.fromRGB(255, 255, 255),
	AccentSoft     = Color3.fromRGB(205, 205, 210),
	OnAccent       = Color3.fromRGB(18, 18, 18),

	Success        = Color3.fromRGB(74, 222, 128),
	SuccessSoft    = Color3.fromRGB(110, 231, 183),
	Danger         = Color3.fromRGB(205, 205, 210),

	Font           = Fonts.SemiBold,
	FontRegular    = Fonts.Regular,
	MeasureFont    = Enum.Font.GothamSemibold,

	CornerRadius   = 16,
	CornerRadiusSm = 8,
	Margin         = 14,
	AnimFast       = 0.15,
	AnimSlow       = 0.32,
}

-- Theme bindings keep controls synchronized when SetTheme() is called at runtime.
local ThemeBindings = setmetatable({}, { __mode = "k" })

local function ResolveThemeBinding(binding)
	if type(binding) == "function" then
		return binding(BobloNEXT.Theme)
	end
	return BobloNEXT.Theme[binding]
end

local function ThemeBind(instance, property, binding)
	if not instance then return instance end
	local props = ThemeBindings[instance]
	if not props then
		props = {}
		ThemeBindings[instance] = props
	end
	props[property] = binding

	local value = ResolveThemeBinding(binding)
	if value ~= nil then
		pcall(function() instance[property] = value end)
	end
	return instance
end

function BobloNEXT:SetTheme(values)
	if type(values) ~= "table" then return self.Theme end

	if values.Primary ~= nil and values.Accent == nil then
		values.Accent = values.Primary
	end
	if values.Secondary ~= nil and values.AccentSoft == nil then
		values.AccentSoft = values.Secondary
	end

	for key, value in pairs(values) do
		if self.Theme[key] ~= nil then
			self.Theme[key] = value
		end
	end

	for instance, props in pairs(ThemeBindings) do
		local alive = false
		pcall(function() alive = instance.Parent ~= nil end)
		if alive then
			for property, binding in pairs(props) do
				local value = ResolveThemeBinding(binding)
				if value ~= nil then
					pcall(function() instance[property] = value end)
				end
			end
		else
			ThemeBindings[instance] = nil
		end
	end

	return self.Theme
end

local Z = {
	Glass    = 0,
	Window   = 1,
	Content  = 2,
	Backdrop = 390,
	Popup    = 400,
	PopupTop = 410,
	Toast    = 600,
	Modal    = 800,
	ModalTop = 810,
}
 
local function Tween(instance, props, duration, style, direction)
	local t = TweenService:Create(
		instance,
		TweenInfo.new(
			math.max(duration or 0.25, 0),
			style or Enum.EasingStyle.Quint,
			direction or Enum.EasingDirection.Out
		),
		props
	)
	t:Play()
	return t
end
 
local function Corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or BobloNEXT.Theme.CornerRadius)
	c.Parent = parent
	return c
end
 
local function Stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(1, 1, 1)
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0.9
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end
 
local function GlassLayer(parent, radius, transparency)
	local glass = Instance.new("Frame")
	glass.Name = "Glass"
	glass.Size = UDim2.fromScale(1, 1)
	glass.BackgroundColor3 = BobloNEXT.Theme.SurfaceHigh
	glass.BackgroundTransparency = transparency or 0.985
	glass.BorderSizePixel = 0
	glass.ZIndex = Z.Glass
	glass.Parent = parent
	ThemeBind(glass, "BackgroundColor3", "SurfaceHigh")
	Corner(glass, radius)
	return glass
end
 
local function AddScrollbar(scroll)
	scroll.ScrollBarThickness = 0
	scroll.ScrollBarImageTransparency = 1
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.None
	scroll.HorizontalScrollBarInset = Enum.ScrollBarInset.None
end
 
local function AddContentScrollThumb(scroll, listLayout, thumbParent, janitor)
	local thumb = Instance.new("Frame")
	thumb.Name = "ContentScrollThumb"
	ThemeBind(thumb, "BackgroundColor3", "TextDim")
	thumb.BackgroundTransparency = 0.35
	thumb.BorderSizePixel = 0
	thumb.AnchorPoint = Vector2.new(1, 0)
	thumb.Size = UDim2.new(0, 3, 0, 40)
	thumb.Visible = false
	thumb.ZIndex = (scroll.ZIndex or 0) + 6
	thumb.Parent = thumbParent
	Corner(thumb, 2)
 
	local MARGIN = 4
 
	janitor:Add(RunService.Heartbeat:Connect(function()
		if not thumbParent.Visible then
			thumb.Visible = false
			return
		end
		local windowH = scroll.AbsoluteWindowSize.Y
		local canvasH = scroll.AbsoluteCanvasSize.Y
		local overflow = canvasH - windowH
		if overflow <= 8 or windowH <= 0 then
			thumb.Visible = false
			return
		end
		local trackH = windowH - MARGIN * 2
		if trackH <= 0 then
			thumb.Visible = false
			return
		end
		local parentPos, parentSize = thumbParent.AbsolutePosition, thumbParent.AbsoluteSize
		if parentSize.X <= 0 or parentSize.Y <= 0 then
			thumb.Visible = false
			return
		end
		local thumbH = math.min(trackH, math.max(30, trackH * (windowH / canvasH)))
		local maxThumbY = trackH - thumbH
		local ratio = math.clamp(scroll.CanvasPosition.Y / overflow, 0, 1)
		local topY = (scroll.AbsolutePosition.Y - parentPos.Y) + MARGIN + maxThumbY * ratio
		local rightX = (scroll.AbsolutePosition.X + scroll.AbsoluteSize.X) - parentPos.X - MARGIN
		thumb.Visible = true
		thumb.Size = UDim2.new(0, 3, thumbH / parentSize.Y, 0)
		thumb.Position = UDim2.new(rightX / parentSize.X, 0, topY / parentSize.Y, 0)
	end))
 
	return thumb
end
 
local MEASURE_FUDGE = 1.06
local MeasureCache = {}
 
local function MeasureText(text, size, maxWidth)
	text = tostring(text or "")
	maxWidth = maxWidth or 10000
	local key = text .. "\1" .. size .. "\1" .. math.floor(maxWidth)
	local cached = MeasureCache[key]
	if cached then return cached.X, cached.Y end
 
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(
			text, size, BobloNEXT.Theme.MeasureFont,
			Vector2.new(maxWidth, 100000)
		)
	end)
	local w, h
	if ok and bounds then
		w = math.ceil(bounds.X * MEASURE_FUDGE)
		h = math.ceil(bounds.Y)
	else
		w = math.ceil(#text * size * 0.55)
		h = size + 2
	end
	MeasureCache[key] = Vector2.new(w, h)
	return w, h
end
 
-- Embedded icon lookup tables.
-- They are bundled into BobloNEXT so the library does not download icon maps at runtime.
-- See NOTICE.md and LICENSE-NEBULA-ICONS for provenance/licensing.
local IconSources = {
	Material = {
		["perm_media"] = 6031215982;
		["sticky_note_2"] = 6031265972;
		["gavel"] = 6023565902;
		["table_view"] = 6031233835;
		["home"] = 6026568195;
		["list"] = 6026568229;
		["alarm_add"] = 6023426898;
		["speaker_notes"] = 6031266001;
		["check_circle_outline"] = 6023426909;
		["extension"] = 6023565892;
		["pending"] = 6031084745;
		["pageview"] = 6031216007;
		["group_work"] = 6023565910;
		["zoom_in"] = 6031075573;
		["aspect_ratio"] = 6022668895;
		["code"] = 6022668955;
		["3d_rotation"] = 6022668893;
		["translate"] = 6031225812;
		["star_rate"] = 6031265978;
		["system_update_alt"] = 6031251515;
		["open_with"] = 6026568265;
		["build_circle"] = 6023426952;
		["toc"] = 6031229341;
		["settings_phone"] = 6031289445;
		["open_in_full"] = 6026568245;
		["history"] = 6026568197;
		["accessibility_new"] = 6022668945;
		["hourglass_disabled"] = 6026568193;
		["line_style"] = 6026568276;
		["account_circle"] = 6022668898;
		["settings_cell"] = 6031280890;
		["search_off"] = 6031260783;
		["shop"] = 6031265983;
		["anchor"] = 6023426906;
		["language"] = 6026568213;
		["settings_brightness"] = 6031280902;
		["restore_page"] = 6031154877;
		["chrome_reader_mode"] = 6023426912;
		["sync_alt"] = 6031233840;
		["book"] = 6022860343;
		["smart_button"] = 6031265962;
		["request_page"] = 6031154873;
		["lock_clock"] = 6026568260;
		["android"] = 6022668966;
		["outgoing_mail"] = 6026568242;
		["dynamic_form"] = 6023426970;
		["track_changes"] = 6031225814;
		["source"] = 6031289451;
		["thumb_down"] = 6031229336;
		["integration_instructions"] = 6026568214;
		["opacity"] = 6026568295;
		["perm_identity"] = 6031215978;
		["view_module"] = 6031079152;
		["perm_data_setting"] = 6031215991;
		["assignment_turned_in"] = 6023426904;
		["change_history"] = 6023426914;
		["thumb_down_off_alt"] = 6031229354;
		["text_rotation_angledown"] = 6031251513;
		["bookmark"] = 6022852108;
		["view_stream"] = 6031079164;
		["remove_done"] = 6031086169;
		["markunread_mailbox"] = 6031082531;
		["store"] = 6031265968;
		["text_rotation_angleup"] = 6031229337;
		["eco"] = 6023426988;
		["find_in_page"] = 6023426986;
		["api"] = 6022668911;
		["launch"] = 6026568211;
		["text_rotation_down"] = 6031229334;
		["flip_to_back"] = 6023565896;
		["contact_page"] = 6022668881;
		["preview"] = 6031260793;
		["restore"] = 6031260800;
		["favorite_border"] = 6023565882;
		["assignment_late"] = 6022668880;
		["youtube_searched_for"] = 6031075934;
		["hourglass_full"] = 6026568190;
		["timeline"] = 6031229350;
		["turned_in"] = 6031225808;
		["info"] = 6026568227;
		["restore_from_trash"] = 6031154869;
		["arrow_circle_down"] = 6022668877;
		["flaky"] = 6031082523;
		["alarm_on"] = 6023426920;
		["swap_vertical_circle"] = 6031233839;
		["open_in_new"] = 6026568256;
		["watch_later"] = 6031075924;
		["alarm_off"] = 6023426901;
		["maximize"] = 6026568267;
		["lock_outline"] = 6031082533;
		["outbond"] = 6026568244;
		["view_carousel"] = 6031251507;
		["published_with_changes"] = 6031243328;
		["verified_user"] = 6031225819;
		["drag_indicator"] = 6023426962;
		["lightbulb_outline"] = 6026568254;
		["segment"] = 6031260773;
		["assignment"] = 6022668882;
		["work_outline"] = 6031075930;
		["line_weight"] = 6026568226;
		["dangerous"] = 6022668916;
		["assessment"] = 6022668897;
		["view_day"] = 6031079153;
		["help_center"] = 6026568192;
		["logout"] = 6031082522;
		["event"] = 6023426959;
		["get_app"] = 6023565889;
		["tab"] = 6031233851;
		["label"] = 6031082525;
		["g_translate"] = 6031082526;
		["view_week"] = 6031079154;
		["view_in_ar"] = 6031079158;
		["card_travel"] = 6023426925;
		["lock_open"] = 6026568220;
		["voice_over_off"] = 6031075927;
		["app_blocking"] = 6022668952;
		["settings_ethernet"] = 6031280883;
		["supervised_user_circle"] = 6031289449;
		["done_all"] = 6023426929;
		["lightbulb"] = 6026568247;
		["find_replace"] = 6023426979;
		["bookmarks"] = 6023426924;
		["today"] = 6031229352;
		["class"] = 6022668949;
		["supervisor_account"] = 6031251516;
		["support"] = 6031251532;
		["done_outline"] = 6023426936;
		["reorder"] = 6031154868;
		["fact_check"] = 6023426951;
		["thumb_up"] = 6031229347;
		["assignment_returned"] = 6023426899;
		["card_giftcard"] = 6023426978;
		["trending_down"] = 6031225811;
		["settings_backup_restore"] = 6031280886;
		["settings_voice"] = 6031265966;
		["dns"] = 6023426958;
		["perm_scan_wifi"] = 6031215985;
		["plagiarism"] = 6031243320;
		["commute"] = 6022668901;
		["gif"] = 6031082540;
		["work"] = 6031075939;
		["picture_in_picture_alt"] = 6031215979;
		["query_builder"] = 6031086183;
		["label_off"] = 6026568209;
		["all_out"] = 6022668876;
		["article"] = 6022668907;
		["shopping_basket"] = 6031265997;
		["mark_as_unread"] = 6026568223;
		["work_off"] = 6031075937;
		["delete_outline"] = 6022668962;
		["account_box"] = 6023426915;
		["home_filled"] = 9080449299;
		["lock"] = 6026568224;
		["perm_device_information"] = 6031215996;
		["add_task"] = 6022668912;
		["text_rotate_up"] = 6031251526;
		["swipe"] = 6031233863;
		["eject"] = 6023426930;
		["mediation"] = 6026568249;
		["label_important_outline"] = 6026568199;
		["settings_remote"] = 6031289442;
		["history_toggle_off"] = 6026568196;
		["invert_colors"] = 6026568253;
		["visibility_off"] = 6031075929;
		["addchart"] = 6023426905;
		["cancel_schedule_send"] = 6022668963;
		["loyalty"] = 6026568237;
		["speaker_notes_off"] = 6031265965;
		["online_prediction"] = 6026568239;
		["remove_shopping_cart"] = 6031260778;
		["text_rotate_vertical"] = 6031251518;
		["visibility"] = 6031075931;
		["add_to_drive"] = 6022860335;
		["accessible"] = 6022668902;
		["bookmark_border"] = 6022860339;
		["tour"] = 6031229362;
		["compare_arrows"] = 6022668951;
		["view_sidebar"] = 6031079160;
		["face"] = 6023426944;
		["wysiwyg"] = 6031075938;
		["camera_enhance"] = 6023426935;
		["perm_camera_mic"] = 6031215983;
		["model_training"] = 6026568222;
		["arrow_circle_up"] = 6022668934;
		["euro_symbol"] = 6023426954;
		["pending_actions"] = 6031260777;
		["not_accessible"] = 6026568269;
		["explore_off"] = 6023426953;
		["build"] = 6023426938;
		["backup"] = 6023426911;
		["settings_input_antenna"] = 6031280891;
		["disabled_by_default"] = 6023426939;
		["upgrade"] = 6031225815;
		["contactless"] = 6022668886;
		["trending_flat"] = 6031225818;
		["schedule"] = 6031260808;
		["offline_pin"] = 6031084770;
		["date_range"] = 6022668894;
		["flight_land"] = 6023565897;
		["view_headline"] = 6031079151;
		["cached"] = 6023426921;
		["unpublished"] = 6031225817;
		["outlet"] = 6031084748;
		["favorite"] = 6023426974;
		["vertical_split"] = 6031225820;
		["report_problem"] = 6031086176;
		["fingerprint"] = 6023565895;
		["important_devices"] = 6026568202;
		["outbox"] = 6026568263;
		["all_inbox"] = 6022668909;
		["label_important"] = 6026568215;
		["print"] = 6031243324;
		["settings_bluetooth"] = 6031280905;
		["power_settings_new"] = 6031260781;
		["zoom_out"] = 6031075577;
		["stars"] = 6031265971;
		["offline_bolt"] = 6031084742;
		["feedback"] = 6023426957;
		["accessibility"] = 6022668887;
		["announcement"] = 6022668946;
		["settings_input_hdmi"] = 6031280970;
		["leaderboard"] = 6026568216;
		["view_quilt"] = 6031079155;
		["note_add"] = 6031084749;
		["theaters"] = 6031229335;
		["alarm"] = 6023426910;
		["settings_input_composite"] = 6031280896;
		["grade"] = 6026568189;
		["tab_unselected"] = 6031251505;
		["swap_vert"] = 6031233847;
		["assignment_return"] = 6023426931;
		["highlight_alt"] = 6023565913;
		["shopping_bag"] = 6031265970;
		["contact_support"] = 6022668879;
		["flip_to_front"] = 6023565894;
		["touch_app"] = 6031229361;
		["room"] = 6031154875;
		["send_and_archive"] = 6031280889;
		["view_array"] = 6031225842;
		["settings_power"] = 6031289446;
		["admin_panel_settings"] = 6022668961;
		["open_in_browser"] = 6026568266;
		["card_membership"] = 6023426942;
		["rule"] = 6031154859;
		["schedule_send"] = 6031154866;
		["calendar_today"] = 6022668917;
		["info_outline"] = 6026568210;
		["description"] = 6022668888;
		["dashboard_customize"] = 6022668899;
		["rowing"] = 6031154857;
		["swap_horizontal_circle"] = 6031233833;
		["account_balance_wallet"] = 6022668892;
		["view_agenda"] = 6031225831;
		["shop_two"] = 6031289461;
		["done"] = 6023426926;
		["circle_notifications"] = 6023426923;
		["compress"] = 6022668878;
		["calendar_view_day"] = 6023426946;
		["thumbs_up_down"] = 6031229373;
		["account_balance"] = 6022668900;
		["play_for_work"] = 6031260776;
		["pets"] = 6031260782;
		["view_column"] = 6031079172;
		["search"] = 6031154871;
		["autorenew"] = 6023565901;
		["copyright"] = 6023565898;
		["privacy_tip"] = 6031260784;
		["arrow_right_alt"] = 6022668890;
		["delete"] = 6022668885;
		["nightlight_round"] = 6031084743;
		["batch_prediction"] = 6022860334;
		["shopping_cart"] = 6031265976;
		["login"] = 6031082527;
		["settings_input_svideo"] = 6031289444;
		["payment"] = 6031084751;
		["update"] = 6031225810;
		["text_rotation_none"] = 6031229344;
		["perm_contact_calendar"] = 6031215990;
		["explore"] = 6023426941;
		["delete_forever"] = 6022668939;
		["rounded_corner"] = 6031154861;
		["book_online"] = 6022860332;
		["quickreply"] = 6031243319;
		["bug_report"] = 6022852107;
		["subtitles_off"] = 6031289466;
		["close_fullscreen"] = 6023426928;
		["horizontal_split"] = 6026568194;
		["minimize"] = 6026568240;
		["filter_list_alt"] = 6023426955;
		["add_shopping_cart"] = 6022668875;
		["next_plan"] = 6026568231;
		["view_list"] = 6031079156;
		["receipt"] = 6031086173;
		["polymer"] = 6031260785;
		["spellcheck"] = 6031289450;
		["wifi_protected_setup"] = 6031075926;
		["label_outline"] = 6026568207;
		["highlight_off"] = 6023565916;
		["turned_in_not"] = 6031225806;
		["edit_off"] = 6023426983;
		["question_answer"] = 6031086172;
		["settings_overscan"] = 6031289459;
		["trending_up"] = 6031225816;
		["verified"] = 6031225809;
		["flight_takeoff"] = 6023565891;
		["grading"] = 6026568191;
		["dashboard"] = 6022668883;
		["expand"] = 6022668891;
		["backup_table"] = 6022860338;
		["analytics"] = 6022668884;
		["picture_in_picture"] = 6031215994;
		["settings"] = 6031280882;
		["accessible_forward"] = 6022668906;
		["pan_tool"] = 6031084771;
		["https"] = 6026568200;
		["filter_alt"] = 6023426984;
		["thumb_up_off_alt"] = 6031229342;
		["record_voice_over"] = 6031243318;
		["help_outline"] = 6026568201;
		["check_circle"] = 6023426945;
		["comment_bank"] = 6023426937;
		["perm_phone_msg"] = 6031215986;
		["settings_applications"] = 6031280894;
		["exit_to_app"] = 6023426922;
		["saved_search"] = 6031154867;
		["toll"] = 6031229343;
		["not_started"] = 6026568232;
		["subject"] = 6031289452;
		["redeem"] = 6031086170;
		["input"] = 6026568225;
		["settings_input_component"] = 6031280884;
		["assignment_ind"] = 6022668935;
		["swap_horiz"] = 6031233841;
		["fullscreen"] = 6031094681;
		["cancel"] = 6031094677;
		["subdirectory_arrow_left"] = 6031104654;
		["close"] = 6031094678;
		["arrow_back_ios"] = 6031091003;
		["east"] = 6031094675;
		["unfold_more"] = 6031104644;
		["south"] = 6031104646;
		["arrow_drop_up"] = 6031090990;
		["arrow_back"] = 6031091000;
		["arrow_downward"] = 6031090991;
		["west"] = 6031104677;
		["legend_toggle"] = 6031097233;
		["fullscreen_exit"] = 6031094691;
		["last_page"] = 6031094686;
		["switch_right"] = 6031104649;
		["check"] = 6031094667;
		["home_work"] = 6031094683;
		["north_east"] = 6031097228;
		["double_arrow"] = 6031094674;
		["more_vert"] = 6031104648;
		["chevron_left"] = 6031094670;
		["more_horiz"] = 6031104650;
		["unfold_less"] = 6031104681;
		["first_page"] = 6031094682;
		["payments"] = 6031097227;
		["arrow_right"] = 6031090994;
		["offline_share"] = 6031097267;
		["south_west"] = 6031104652;
		["expand_less"] = 6031094679;
		["south_east"] = 6031104642;
		["assistant_navigation"] = 6031091006;
		["apps"] = 6031090999;
		["arrow_upward"] = 6031090997;
		["app_settings_alt"] = 6031090998;
		["subdirectory_arrow_right"] = 6031104647;
		["north_west"] = 6031104630;
		["switch_left"] = 6031104651;
		["chevron_right"] = 6031094680;
		["arrow_forward"] = 6031090995;
		["arrow_forward_ios"] = 6031091008;
		["arrow_drop_down"] = 6031091004;
		["refresh"] = 6031097226;
		["pivot_table_chart"] = 6031097234;
		["expand_more"] = 6031094687;
		["campaign"] = 6031094666;
		["arrow_left"] = 6031091002;
		["arrow_drop_down_circle"] = 6031091001;
		["menu_open"] = 6031097229;
		["waterfall_chart"] = 6031104632;
		["assistant_direction"] = 6031091005;
		["menu"] = 6031097225;
		["personal_video"] = 6034457070;
		["power_off"] = 6034457087;
		["wifi_off"] = 6034461625;
		["adb"] = 6034418515;
		["airline_seat_recline_normal"] = 6034418512;
		["sync_problem"] = 6034452653;
		["network_check"] = 6034461631;
		["event_busy"] = 6034439634;
		["airline_seat_flat"] = 6034418511;
		["disc_full"] = 6034418518;
		["sd_card"] = 6034457089;
		["time_to_leave"] = 6034452660;
		["phone_bluetooth_speaker"] = 6034457057;
		["phone_paused"] = 6034457066;
		["phone_locked"] = 6034457058;
		["more"] = 6034461627;
		["add_call"] = 6034418524;
		["account_tree"] = 6034418507;
		["do_not_disturb_on"] = 6034439649;
		["event_note"] = 6034439637;
		["sync_disabled"] = 6034452649;
		["mms"] = 6034461621;
		["airline_seat_flat_angled"] = 6034418513;
		["bluetooth_audio"] = 6034418522;
		["vibration"] = 6034452651;
		["system_update"] = 6034452663;
		["enhanced_encryption"] = 6034439652;
		["wc"] = 6034452643;
		["live_tv"] = 6034439648;
		["folder_special"] = 6034439639;
		["phone_missed"] = 6034457056;
		["airline_seat_recline_extra"] = 6034418528;
		["sms"] = 6034452645;
		["tap_and_play"] = 6034452650;
		["confirmation_number"] = 6034418519;
		["event_available"] = 6034439643;
		["sms_failed"] = 6034452676;
		["do_not_disturb_alt"] = 6034461619;
		["do_not_disturb"] = 6034439645;
		["ondemand_video"] = 6034457065;
		["no_encryption"] = 6034457059;
		["airline_seat_legroom_extra"] = 6034418508;
		["tv_off"] = 6034452646;
		["sim_card_alert"] = 6034452641;
		["airline_seat_legroom_normal"] = 6034418532;
		["wifi"] = 6034461626;
		["do_not_disturb_off"] = 6034439642;
		["imagesearch_roller"] = 6034439635;
		["power"] = 6034457105;
		["airline_seat_legroom_reduced"] = 6034418520;
		["phone_in_talk"] = 6034457067;
		["airline_seat_individual_suite"] = 6034418514;
		["priority_high"] = 6034457092;
		["phone_callback"] = 6034457104;
		["phone_forwarded"] = 6034457106;
		["sync"] = 6034452662;
		["vpn_lock"] = 6034452648;
		["support_agent"] = 6034452656;
		["network_locked"] = 6034457064;
		["directions_off"] = 6034418517;
		["drive_eta"] = 6034464371;
		["sensor_window"] = 6031067242;
		["sensor_door"] = 6031067241;
		["keyboard_return"] = 6034818370;
		["monitor"] = 6034837803;
		["device_hub"] = 6034789877;
		["keyboard"] = 6034818398;
		["keyboard_voice"] = 6034818360;
		["cast"] = 6034789876;
		["developer_board"] = 6034789883;
		["tablet"] = 6034848733;
		["keyboard_hide"] = 6034818386;
		["dock"] = 6034789888;
		["phonelink"] = 6034837801;
		["device_unknown"] = 6034789884;
		["speaker_group"] = 6034848732;
		["desktop_mac"] = 6034789898;
		["point_of_sale"] = 6034837798;
		["memory"] = 6034837807;
		["keyboard_tab"] = 6034818363;
		["router"] = 6034837806;
		["sim_card"] = 6034837800;
		["headset"] = 6034789880;
		["gamepad"] = 6034789879;
		["speaker"] = 6034848746;
		["devices_other"] = 6034789873;
		["laptop"] = 6034818367;
		["scanner"] = 6034837799;
		["tv"] = 6034848740;
		["headset_mic"] = 6034818383;
		["browser_not_supported"] = 6034789875;
		["computer"] = 6034789874;
		["connected_tv"] = 6034789870;
		["phonelink_off"] = 6034837804;
		["headset_off"] = 6034818402;
		["cast_connected"] = 6034789895;
		["watch"] = 6034848747;
		["keyboard_arrow_up"] = 6034818379;
		["keyboard_backspace"] = 6034818381;
		["laptop_chromebook"] = 6034818364;
		["phone_iphone"] = 6034837811;
		["smartphone"] = 6034848731;
		["power_input"] = 6034837794;
		["videogame_asset"] = 6034848748;
		["desktop_windows"] = 6034789893;
		["keyboard_arrow_down"] = 6034818372;
		["laptop_mac"] = 6034837808;
		["laptop_windows"] = 6034837796;
		["keyboard_arrow_right"] = 6034818365;
		["cast_for_education"] = 6034789872;
		["keyboard_capslock"] = 6034818403;
		["toys"] = 6034848752;
		["tablet_android"] = 6034848734;
		["mouse"] = 6034837797;
		["phone_android"] = 6034837793;
		["keyboard_arrow_left"] = 6034818375;
		["security"] = 6034837802;
		["dry_cleaning"] = 6034754456;
		["bakery_dining"] = 6034767610;
		["place"] = 6034503372;
		["run_circle"] = 6034503367;
		["local_post_office"] = 6034513883;
		["takeout_dining"] = 6034467808;
		["nightlife"] = 6034510003;
		["design_services"] = 6034754453;
		["celebration"] = 6034767613;
		["near_me_disabled"] = 6034509988;
		["add_location_alt"] = 6034483678;
		["directions_run"] = 6034754445;
		["local_fire_department"] = 6034684949;
		["add_road"] = 6034483677;
		["my_location"] = 6034509987;
		["dinner_dining"] = 6034754457;
		["local_airport"] = 6034687951;
		["zoom_out_map"] = 6035229856;
		["pin_drop"] = 6034470807;
		["subway"] = 6034467790;
		["electric_moped"] = 6034744027;
		["restaurant_menu"] = 6034503378;
		["local_gas_station"] = 6034684935;
		["local_cafe"] = 6034687954;
		["theater_comedy"] = 6034467796;
		["directions_bus"] = 6034754434;
		["hail"] = 6034744033;
		["satellite"] = 6034503370;
		["local_phone"] = 6034513884;
		["electric_bike"] = 6034744032;
		["local_see"] = 6034513887;
		["transit_enterexit"] = 6034467805;
		["local_convenience_store"] = 6034687956;
		["local_offer"] = 6034513891;
		["electric_car"] = 6034744029;
		["beenhere"] = 6034483675;
		["miscellaneous_services"] = 6034509993;
		["maps_ugc"] = 6034509992;
		["moped"] = 6034509999;
		["medical_services"] = 6034510001;
		["money"] = 6034509997;
		["transfer_within_a_station"] = 6034467809;
		["electrical_services"] = 6034744038;
		["museum"] = 6034510005;
		["add_location"] = 6034483672;
		["layers"] = 6034687957;
		["handyman"] = 6034744057;
		["local_pharmacy"] = 6034513903;
		["electric_rickshaw"] = 6034744043;
		["alt_route"] = 6034483670;
		["no_transfer"] = 6034503363;
		["pedal_bike"] = 6034503374;
		["directions_transit"] = 6034754436;
		["railway_alert"] = 6034470823;
		["local_police"] = 6034513895;
		["directions_car"] = 6034754441;
		["category"] = 6034767621;
		["attractions"] = 6034767620;
		["person_pin_circle"] = 6034503375;
		["cleaning_services"] = 6034767619;
		["terrain"] = 6034467794;
		["no_meals"] = 6034510024;
		["train"] = 6034467803;
		["delivery_dining"] = 6034767644;
		["pest_control"] = 6034470809;
		["directions"] = 6034754449;
		["atm"] = 6034767614;
		["rate_review"] = 6034503385;
		["local_bar"] = 6034687950;
		["local_drink"] = 6034687965;
		["directions_railway"] = 6034754433;
		["person_pin"] = 6034503364;
		["ev_station"] = 6034744037;
		["home_repair_service"] = 6034744064;
		["bus_alert"] = 6034767618;
		["agriculture"] = 6034483674;
		["volunteer_activism"] = 6034467799;
		["breakfast_dining"] = 6034483671;
		["layers_clear"] = 6034687975;
		["plumbing"] = 6034470800;
		["taxi_alert"] = 6034467792;
		["add_business"] = 6034483666;
		["badge"] = 6034767607;
		["edit_attributes"] = 6034754443;
		["directions_walk"] = 6034754448;
		["local_play"] = 6034513889;
		["bike_scooter"] = 6034483669;
		["two_wheeler"] = 6034467795;
		["local_florist"] = 6034684940;
		["local_hotel"] = 6034684939;
		["no_meals_ouline"] = 6034510025;
		["festival"] = 6034744031;
		["local_shipping"] = 6034684926;
		["directions_boat"] = 6034754442;
		["wrong_location"] = 6034467801;
		["restaurant"] = 6034503366;
		["directions_subway"] = 6034754440;
		["not_listed_location"] = 6034503380;
		["electric_scooter"] = 6034744041;
		["ramen_dining"] = 6034503377;
		["edit_road"] = 6034744035;
		["local_printshop"] = 6034513897;
		["map"] = 6034684930;
		["car_rental"] = 6034767641;
		["multiple_stop"] = 6034510026;
		["brunch_dining"] = 6034767611;
		["local_laundry_service"] = 6034684943;
		["set_meal"] = 6034503368;
		["local_car_wash"] = 6034687976;
		["pest_control_rodent"] = 6034470803;
		["local_pizza"] = 6034513885;
		["local_grocery_store"] = 6034684933;
		["traffic"] = 6034467797;
		["departure_board"] = 6034767615;
		["icecream"] = 6034687967;
		["navigation"] = 6034509984;
		["near_me"] = 6034509996;
		["fastfood"] = 6034744034;
		["local_library"] = 6034684931;
		["local_activity"] = 6034687955;
		["local_hospital"] = 6034684956;
		["menu_book"] = 6034509994;
		["directions_bike"] = 6034754459;
		["store_mall_directory"] = 6034470811;
		["trip_origin"] = 6034467804;
		["tram"] = 6034467806;
		["edit_location"] = 6034754439;
		["streetview"] = 6034470805;
		["hvac"] = 6034687960;
		["lunch_dining"] = 6034684928;
		["car_repair"] = 6034767617;
		["compass_calibration"] = 6034767623;
		["360"] = 6034767608;
		["flight"] = 6034744030;
		["local_mall"] = 6034684934;
		["hotel"] = 6034687977;
		["local_parking"] = 6034513893;
		["hardware"] = 6034744036;
		["local_dining"] = 6034687963;
		["park"] = 6034503369;
		["location_pin"] = 6034684937;
		["local_movies"] = 6034684936;
		["local_atm"] = 6034687953;
		["local_taxi"] = 6034684927;
		["brightness_low"] = 6034989542;
		["screen_lock_landscape"] = 6034996700;
		["graphic_eq"] = 6034989551;
		["screen_lock_rotation"] = 6034996710;
		["signal_cellular_4_bar"] = 6035030076;
		["airplanemode_inactive"] = 6034983848;
		["signal_wifi_0_bar"] = 6035030067;
		["battery_full"] = 6034983854;
		["gps_fixed"] = 6034989550;
		["brightness_high"] = 6034989541;
		["ad_units"] = 6034983845;
		["signal_cellular_alt"] = 6035030079;
		["bluetooth_connected"] = 6034983855;
		["wifi_tethering"] = 6035039430;
		["dvr"] = 6034989561;
		["screen_search_desktop"] = 6034996711;
		["network_wifi"] = 6034996712;
		["access_alarms"] = 6034983853;
		["nfc"] = 6034996698;
		["location_disabled"] = 6034996694;
		["signal_wifi_4_bar"] = 6035030077;
		["access_time"] = 6034983856;
		["mobile_off"] = 6034996702;
		["battery_unknown"] = 6034983842;
		["signal_cellular_null"] = 6035030075;
		["bluetooth_disabled"] = 6034989562;
		["developer_mode"] = 6034989549;
		["network_cell"] = 6034996709;
		["sd_storage"] = 6034996719;
		["signal_cellular_no_sim"] = 6035030078;
		["devices"] = 6034989540;
		["screen_rotation"] = 6034996701;
		["device_thermostat"] = 6034989544;
		["signal_wifi_off"] = 6035030074;
		["widgets"] = 6035039429;
		["bluetooth"] = 6034983880;
		["battery_charging_full"] = 6034983849;
		["mobile_friendly"] = 6034996699;
		["signal_cellular_0_bar"] = 6035030072;
		["storage"] = 6035030083;
		["send_to_mobile"] = 6034996697;
		["location_searching"] = 6034996695;
		["brightness_auto"] = 6034989545;
		["wifi_lock"] = 6035039428;
		["gps_not_fixed"] = 6034989547;
		["access_alarm"] = 6034983844;
		["battery_alert"] = 6034983843;
		["signal_cellular_off"] = 6035030084;
		["signal_cellular_connected_no_internet_4"] = 6035229858;
		["gps_off"] = 6034989548;
		["add_alarm"] = 6034983850;
		["brightness_medium"] = 6034989543;
		["usb"] = 6035030080;
		["airplanemode_active"] = 6034983864;
		["reset_tv"] = 6034996696;
		["wallpaper"] = 6035030102;
		["settings_system_daydream"] = 6035030081;
		["bluetooth_searching"] = 6034989553;
		["add_to_home_screen"] = 6034983858;
		["screen_lock_portrait"] = 6034996706;
		["data_usage"] = 6034989568;
		["_auto_delete"] = 6031071068;
		["_error"] = 6031071057;
		["_notification_important"] = 6031071056;
		["_add_alert"] = 6031071067;
		["_warning"] = 6031071053;
		["_error_outline"] = 6031071050;
		["check_box_outline_blank"] = 6031068420;
		["toggle_off"] = 6031068429;
		["indeterminate_check_box"] = 6031068445;
		["radio_button_checked"] = 6031068426;
		["toggle_on"] = 6031068430;
		["check_box"] = 6031068421;
		["radio_button_unchecked"] = 6031068433;
		["star"] = 6031068423;
		["star_border"] = 6031068425;
		["star_half"] = 6031068427;
		["star_outline"] = 6031068428;
		["multiline_chart"] = 6034941721;
		["pie_chart"] = 6034973076;
		["format_line_spacing"] = 6034910905;
		["format_align_left"] = 6034900727;
		["linear_scale"] = 6034941707;
		["insert_photo"] = 6034941703;
		["scatter_plot"] = 6034973094;
		["post_add"] = 6034973083;
		["format_textdirection_r_to_l"] = 6034925623;
		["format_size"] = 6034910908;
		["format_color_fill"] = 6034910903;
		["format_paint"] = 6034925618;
		["format_underlined"] = 6034925627;
		["format_shapes"] = 6034910909;
		["title"] = 6034934042;
		["highlight"] = 6034925617;
		["bar_chart"] = 6034898096;
		["format_indent_increase"] = 6034900724;
		["merge_type"] = 6034941705;
		["bubble_chart"] = 6034925612;
		["publish"] = 6034973085;
		["format_indent_decrease"] = 6034900733;
		["margin"] = 6034941701;
		["table_rows"] = 6034934025;
		["stacked_line_chart"] = 6034934039;
		["border_clear"] = 6034898135;
		["border_color"] = 6034898100;
		["border_inner"] = 6034898131;
		["insert_chart"] = 6034925628;
		["border_top"] = 6034900726;
		["padding"] = 6034973078;
		["border_vertical"] = 6034900725;
		["score"] = 6034934041;
		["border_right"] = 6034898120;
		["add_chart"] = 6034898093;
		["space_bar"] = 6034934037;
		["border_outer"] = 6034898104;
		["mode_comment"] = 6034941700;
		["attach_money"] = 6034898098;
		["drag_handle"] = 6034910907;
		["format_align_right"] = 6034900723;
		["pie_chart_outlined"] = 6034973077;
		["horizontal_rule"] = 6034925610;
		["border_all"] = 6034898101;
		["border_style"] = 6034898097;
		["insert_comment"] = 6034925609;
		["vertical_align_top"] = 6034973080;
		["vertical_align_center"] = 6034934051;
		["format_color_text"] = 6034910910;
		["format_quote"] = 6034925629;
		["height"] = 6034925613;
		["add_comment"] = 6034898128;
		["format_strikethrough"] = 6034910904;
		["strikethrough_s"] = 6034934030;
		["border_left"] = 6034898099;
		["format_list_bulleted"] = 6034925620;
		["format_italic"] = 6034910912;
		["format_list_numbered"] = 6034925622;
		["attach_file"] = 6034898102;
		["wrap_text"] = 6034973118;
		["insert_invitation"] = 6034973091;
		["format_list_numbered_rtl"] = 6034910906;
		["border_horizontal"] = 6034898105;
		["format_align_center"] = 6034900718;
		["format_textdirection_l_to_r"] = 6034925619;
		["show_chart"] = 6034934032;
		["insert_chart_outlined"] = 6034925606;
		["vertical_align_bottom"] = 6034934023;
		["subscript"] = 6034934059;
		["format_align_justify"] = 6034900721;
		["format_clear"] = 6034910902;
		["notes"] = 6034973084;
		["insert_drive_file"] = 6034941697;
		["functions"] = 6034925614;
		["insert_emoticon"] = 6034973079;
		["insert_link"] = 6034973074;
		["format_color_reset"] = 6034900743;
		["monetization_on"] = 6034973115;
		["short_text"] = 6034934035;
		["mode_edit"] = 6034941708;
		["superscript"] = 6034934034;
		["table_chart"] = 6034973081;
		["format_bold"] = 6034900732;
		["money_off"] = 6034973088;
		["border_bottom"] = 6034898094;
		["text_fields"] = 6034934040;
		["note"] = 6026663734;
		["shuffle"] = 6026667003;
		["library_books"] = 6026660085;
		["library_music"] = 6026660075;
		["surround_sound"] = 6026671209;
		["forward_30"] = 6026660088;
		["music_video"] = 6026663704;
		["videocam_off"] = 6026671212;
		["control_camera"] = 6026647916;
		["explicit"] = 6026647913;
		["3k_plus"] = 6026681598;
		["fiber_pin"] = 6026660064;
		["skip_previous"] = 6026667011;
		["pause_circle_filled"] = 6026663718;
		["video_settings"] = 6026671211;
		["movie"] = 6026660081;
		["add_to_queue"] = 6026647903;
		["6k"] = 6026681579;
		["web_asset"] = 6026671239;
		["play_circle_outline"] = 6026663726;
		["volume_off"] = 6026671224;
		["mic_off"] = 6026660076;
		["featured_play_list"] = 6026647932;
		["pause_circle_outline"] = 6026663701;
		["slow_motion_video"] = 6026681583;
		["7k"] = 6026681584;
		["playlist_add"] = 6026663728;
		["fiber_smart_record"] = 6026660080;
		["8k"] = 6026643014;
		["hd"] = 6026660065;
		["repeat_one_on"] = 6026666992;
		["recent_actors"] = 6026663773;
		["fiber_new"] = 6026647930;
		["fiber_dvr"] = 6026647912;
		["hearing_disabled"] = 6026660068;
		["forward_10"] = 6026660062;
		["4k_plus"] = 6026643005;
		["repeat_one"] = 6026681590;
		["equalizer"] = 6026647906;
		["stop"] = 6026681576;
		["2k"] = 6026643032;
		["playlist_add_check"] = 6026663727;
		["not_interested"] = 6026663743;
		["videocam"] = 6026671213;
		["sort_by_alpha"] = 6026667009;
		["library_add"] = 6026660063;
		["stop_circle"] = 6026681577;
		["pause"] = 6026663719;
		["new_releases"] = 6026663730;
		["album"] = 6026647905;
		["sd"] = 6026681582;
		["volume_up"] = 6026671215;
		["replay_5"] = 6026666993;
		["high_quality"] = 6026660059;
		["shuffle_on"] = 6026666996;
		["play_arrow"] = 6026663699;
		["snooze"] = 6026667006;
		["closed_caption_disabled"] = 6026647900;
		["subscriptions"] = 6026671207;
		["skip_next"] = 6026667005;
		["branding_watermark"] = 6026647911;
		["speed"] = 6026681578;
		["art_track"] = 6026647908;
		["3k"] = 6026681574;
		["4k"] = 6026643017;
		["volume_mute"] = 6026671214;
		["playlist_play"] = 6026663723;
		["remove_from_queue"] = 6026663771;
		["fast_forward"] = 6026647902;
		["play_disabled"] = 6026663702;
		["fast_rewind"] = 6026647942;
		["5k"] = 6026681575;
		["replay_10"] = 6026667007;
		["video_library"] = 6026671208;
		["loop"] = 6026660087;
		["replay_circle_filled"] = 6026667002;
		["5g"] = 6026643007;
		["library_add_check"] = 6026660083;
		["repeat"] = 6026666998;
		["queue_play_next"] = 6026663700;
		["forward_5"] = 6026660067;
		["web"] = 6026671234;
		["mic_none"] = 6026660066;
		["queue"] = 6026663724;
		["closed_caption_off"] = 6026647943;
		["hearing"] = 6026660060;
		["queue_music"] = 6026663725;
		["airplay"] = 6026647929;
		["9k"] = 6026643013;
		["video_label"] = 6026671204;
		["8k_plus"] = 6026643003;
		["play_circle_filled"] = 6026663705;
		["1k"] = 6026643002;
		["fiber_manual_record"] = 6026647909;
		["closed_caption"] = 6026647896;
		["subtitles"] = 6026671203;
		["featured_video"] = 6026647910;
		["replay_30"] = 6026667010;
		["10k"] = 6026643035;
		["5k_plus"] = 6026643028;
		["6k_plus"] = 6026643019;
		["replay"] = 6026666999;
		["repeat_on"] = 6026666994;
		["1k_plus"] = 6026681580;
		["2k_plus"] = 6026681588;
		["games"] = 6026660074;
		["volume_down"] = 6026671206;
		["mic"] = 6026660078;
		["call_to_action"] = 6026647898;
		["7k_plus"] = 6026643012;
		["av_timer"] = 6026647934;
		["9k_plus"] = 6026681585;
		["radio"] = 6026663698;
		["10mp"] = 6031328149;
		["20mp"] = 6031488940;
		["wb_twighlight"] = 6034412760;
		["movie_creation"] = 6034323681;
		["crop_portrait"] = 6031630198;
		["filter_5"] = 6031597518;
		["broken_image"] = 6031471480;
		["flip_camera_android"] = 6034333280;
		["flip_camera_ios"] = 6034333267;
		["circle"] = 6031625146;
		["photo_camera_front"] = 6031771000;
		["assistant"] = 6031360356;
		["face_retouching_natural"] = 6034333274;
		["palette"] = 6034316009;
		["nature_people"] = 6034323711;
		["14mp"] = 6031328161;
		["gradient"] = 6034333261;
		["filter_4"] = 6031597512;
		["panorama_wide_angle_select"] = 6031770990;
		["photo"] = 6031770993;
		["grid_off"] = 6034333286;
		["leak_add"] = 6034407074;
		["landscape"] = 6034407069;
		["exposure_plus_1"] = 6034328970;
		["slideshow"] = 6031754546;
		["camera_alt"] = 6031572307;
		["audiotrack"] = 6031471489;
		["filter_none"] = 6031600815;
		["blur_off"] = 6031371055;
		["crop_16_9"] = 6031630205;
		["blur_on"] = 6031371068;
		["brightness_4"] = 6031471483;
		["details"] = 6034328968;
		["panorama_horizontal"] = 6034315966;
		["camera_rear"] = 6031572316;
		["hdr_weak"] = 6034407083;
		["collections"] = 6031625145;
		["hdr_enhanced_select"] = 6034333281;
		["adjust"] = 6031339048;
		["burst_mode"] = 6031572306;
		["nature"] = 6034323695;
		["brightness_6"] = 6031572309;
		["19mp"] = 6031339054;
		["grain"] = 6034333288;
		["receipt_long"] = 6031763428;
		["photo_filter"] = 6031770992;
		["edit"] = 6034328955;
		["healing"] = 6034407071;
		["exposure_neg_1"] = 6034328957;
		["exposure"] = 6034328962;
		["wb_shade"] = 6034315974;
		["compare"] = 6031625151;
		["cases"] = 6031572324;
		["timer_3"] = 6031754540;
		["exposure_plus_2"] = 6034328961;
		["12mp"] = 6031328140;
		["22mp"] = 6031360353;
		["timer_off"] = 6031734881;
		["auto_stories"] = 6031360360;
		["rotate_left"] = 6031763427;
		["wb_iridescent"] = 6034315972;
		["shutter_speed"] = 6031763443;
		["switch_video"] = 6031754536;
		["23mp"] = 6031339045;
		["euro"] = 6034328963;
		["15mp"] = 6031328158;
		["filter_center_focus"] = 6031600817;
		["photo_library"] = 6031770998;
		["mp"] = 6034323674;
		["looks_4"] = 6034407089;
		["filter_2"] = 6031597521;
		["crop_3_2"] = 6034328956;
		["auto_fix_normal"] = 6031371074;
		["auto_fix_off"] = 6031360381;
		["wb_auto"] = 6031734875;
		["switch_camera"] = 6031754550;
		["filter_vintage"] = 6031600811;
		["photo_size_select_small"] = 6031763457;
		["blur_linear"] = 6031488930;
		["hdr_on"] = 6034333279;
		["tag_faces"] = 6031754560;
		["21mp"] = 6031339065;
		["camera"] = 6031572312;
		["image_aspect_ratio"] = 6034407073;
		["filter_b_and_w"] = 6031600824;
		["crop_landscape"] = 6031630202;
		["13mp"] = 6031328137;
		["grid_on"] = 6034333276;
		["motion_photos_pause"] = 6034323668;
		["filter_6"] = 6031597524;
		["linked_camera"] = 6034407082;
		["panorama_fish_eye"] = 6034315969;
		["panorama"] = 6034315955;
		["color_lens"] = 6031625148;
		["lens"] = 6034407081;
		["crop_din"] = 6031630208;
		["exposure_neg_2"] = 6034328973;
		["mic_external_off"] = 6034323672;
		["crop_free"] = 6031630212;
		["crop_original"] = 6031630204;
		["panorama_photosphere_select"] = 6034315975;
		["photo_size_select_actual"] = 6031771012;
		["leak_remove"] = 6034407080;
		["collections_bookmark"] = 6034328965;
		["straighten"] = 6031754545;
		["timelapse"] = 6031754541;
		["picture_as_pdf"] = 6031763425;
		["crop_rotate"] = 6031630203;
		["control_point_duplicate"] = 6034328959;
		["photo_camera_back"] = 6031771007;
		["looks_3"] = 6034407088;
		["motion_photos_off"] = 6034323670;
		["rotate_right"] = 6031763429;
		["view_compact"] = 6031734878;
		["crop_7_5"] = 6031630197;
		["style"] = 6031754538;
		["exposure_zero"] = 6034329000;
		["camera_front"] = 6031572318;
		["hdr_strong"] = 6034333272;
		["view_comfy"] = 6031734876;
		["panorama_vertical"] = 6034315963;
		["panorama_vertical_select"] = 6034315961;
		["looks_two"] = 6034412757;
		["filter_drama"] = 6031600813;
		["center_focus_strong"] = 6031625147;
		["18mp"] = 6031339064;
		["7mp"] = 6031328139;
		["wb_sunny"] = 6034412758;
		["filter_9_plus"] = 6031600812;
		["crop"] = 6034328964;
		["vignette"] = 6031734905;
		["brightness_2"] = 6031488938;
		["crop_square"] = 6031630222;
		["looks_5"] = 6034412764;
		["flip"] = 6034333275;
		["looks_one"] = 6034412761;
		["flash_off"] = 6034333270;
		["hdr_off"] = 6034333266;
		["photo_album"] = 6031770989;
		["motion_photos_paused"] = 6034323675;
		["photo_camera"] = 6031770997;
		["2mp"] = 6031328138;
		["3mp"] = 6031328136;
		["24mp"] = 6031360352;
		["filter_9"] = 6031597534;
		["6mp"] = 6031328131;
		["remove_red_eye"] = 6031763426;
		["4mp"] = 6031328152;
		["add_a_photo"] = 6031339049;
		["filter_3"] = 6031597513;
		["crop_5_4"] = 6034328960;
		["8mp"] = 6031328133;
		["camera_roll"] = 6031572314;
		["panorama_wide_angle"] = 6031770995;
		["transform"] = 6031734873;
		["flare"] = 6031600816;
		["image_search"] = 6034407084;
		["auto_awesome"] = 6031360365;
		["motion_photos_on"] = 6034323669;
		["rotate_90_degrees_ccw"] = 6031763456;
		["filter_1"] = 6031597511;
		["filter_tilt_shift"] = 6031600814;
		["image"] = 6034407078;
		["center_focus_weak"] = 6031625144;
		["blur_circular"] = 6031488945;
		["bedtime"] = 6031371054;
		["auto_fix_high"] = 6031360355;
		["monochrome_photos"] = 6034323678;
		["flash_auto"] = 6034333287;
		["5mp"] = 6031328144;
		["photo_size_select_large"] = 6031763423;
		["assistant_photo"] = 6031339052;
		["animation"] = 6031625150;
		["looks"] = 6034407096;
		["17mp"] = 6031339055;
		["panorama_horizontal_select"] = 6034315965;
		["flash_on"] = 6034333271;
		["iso"] = 6034407106;
		["music_note"] = 6034323673;
		["music_off"] = 6034323679;
		["navigate_next"] = 6034315956;
		["timer"] = 6031754564;
		["loupe"] = 6034412770;
		["navigate_before"] = 6034323696;
		["brightness_1"] = 6031471488;
		["brightness_7"] = 6031471491;
		["tonality"] = 6031734891;
		["brush"] = 6031572320;
		["colorize"] = 6031625161;
		["filter_7"] = 6031597515;
		["16mp"] = 6031328168;
		["timer_10"] = 6031734880;
		["portrait"] = 6031763434;
		["tune"] = 6031734877;
		["image_not_supported"] = 6034407076;
		["wb_cloudy"] = 6031734907;
		["auto_awesome_motion"] = 6031360370;
		["filter_8"] = 6031597532;
		["brightness_5"] = 6031471479;
		["movie_filter"] = 6034323687;
		["add_photo_alternate"] = 6031471484;
		["add_to_photos"] = 6031371075;
		["texture"] = 6031754553;
		["11mp"] = 6031328141;
		["mic_external_on"] = 6034323671;
		["looks_6"] = 6034412759;
		["dehaze"] = 6031630200;
		["control_point"] = 6031625131;
		["panorama_photosphere"] = 6034412763;
		["filter_frames"] = 6031600833;
		["auto_awesome_mosaic"] = 6031371053;
		["9mp"] = 6031328146;
		["filter"] = 6031597514;
		["brightness_3"] = 6031572317;
		["dirty_lens"] = 6034328967;
		["wb_incandescent"] = 6034316010;
		["filter_hdr"] = 6031600819;
		["textsms"] = 6035202006;
		["comment"] = 6035181871;
		["call_end"] = 6035173845;
		["qr_code_scanner"] = 6035202022;
		["phonelink_setup"] = 6035202025;
		["call_merge"] = 6035173843;
		["phonelink_erase"] = 6035202085;
		["contact_mail"] = 6035181868;
		["contact_phone"] = 6035181861;
		["screen_share"] = 6035202008;
		["present_to_all"] = 6035202020;
		["stay_primary_portrait"] = 6035202009;
		["message"] = 6035202033;
		["sentiment_satisfied_alt"] = 6035202069;
		["stay_current_portrait"] = 6035202004;
		["voicemail"] = 6035202019;
		["business"] = 6035173853;
		["mail_outline"] = 6035190844;
		["vpn_key"] = 6035202034;
		["forward_to_inbox"] = 6035190840;
		["contacts"] = 6035181864;
		["phonelink_ring"] = 6035202066;
		["domain_disabled"] = 6035181862;
		["person_add_disabled"] = 6035202007;
		["stay_primary_landscape"] = 6035202026;
		["alternate_email"] = 6035173865;
		["phone_disabled"] = 6035202028;
		["email"] = 6035181866;
		["mobile_screen_share"] = 6035202021;
		["live_help"] = 6035190836;
		["chat_bubble"] = 6035181858;
		["stop_screen_share"] = 6035202042;
		["location_on"] = 6035190846;
		["chat_bubble_outline"] = 6035181869;
		["dialer_sip"] = 6035181865;
		["no_sim"] = 6035202030;
		["list_alt"] = 6035190838;
		["call"] = 6035173859;
		["pause_presentation"] = 6035202015;
		["invert_colors_off"] = 6035190842;
		["call_missed_outgoing"] = 6035173847;
		["stay_current_landscape"] = 6035202011;
		["import_export"] = 6035202040;
		["add_ic_call"] = 6035173839;
		["dialpad"] = 6035181892;
		["nat"] = 6035202082;
		["unsubscribe"] = 6035202044;
		["mark_chat_unread"] = 6035190841;
		["portable_wifi_off"] = 6035202091;
		["location_off"] = 6035202049;
		["person_search"] = 6035202013;
		["phonelink_lock"] = 6035202064;
		["desktop_access_disabled"] = 6035181863;
		["import_contacts"] = 6035190854;
		["rss_feed"] = 6035202016;
		["chat"] = 6035173838;
		["print_disabled"] = 6035202041;
		["mark_email_read"] = 6035202038;
		["hourglass_top"] = 6035190886;
		["clear_all"] = 6035181870;
		["forum"] = 6035202002;
		["qr_code"] = 6035202012;
		["speaker_phone"] = 6035202018;
		["rtt"] = 6035202010;
		["domain_verification"] = 6035181867;
		["app_registration"] = 6035173870;
		["call_split"] = 6035173861;
		["cell_wifi"] = 6035173852;
		["phone_enabled"] = 6035202089;
		["call_made"] = 6035173858;
		["call_received"] = 6035173844;
		["phone"] = 6035202017;
		["ring_volume"] = 6035202032;
		["mark_email_unread"] = 6035202027;
		["hourglass_bottom"] = 6035202043;
		["read_more"] = 6035202014;
		["duo"] = 6035181860;
		["more_time"] = 6035202036;
		["wifi_calling"] = 6035202065;
		["swap_calls"] = 6035202037;
		["cancel_presentation"] = 6035173837;
		["call_missed"] = 6035173850;
		["mark_chat_read"] = 6035202031;
		["text_snippet"] = 6031302995;
		["snippet_folder"] = 6031302947;
		["workspaces_outline"] = 6031302952;
		["file_download"] = 6031302931;
		["request_quote"] = 6031302941;
		["approval"] = 6031302928;
		["drive_folder_upload"] = 6031302929;
		["rule_folder"] = 6031302940;
		["attach_email"] = 6031302935;
		["topic"] = 6031302976;
		["upload_file"] = 6031302959;
		["attachment"] = 6031302921;
		["file_download_done"] = 6031302926;
		["drive_file_move_outline"] = 6031302924;
		["cloud_upload"] = 6031302992;
		["cloud_circle"] = 6031302919;
		["folder_shared"] = 6031302945;
		["cloud_download"] = 6031302917;
		["file_upload"] = 6031302996;
		["workspaces_filled"] = 6031302961;
		["cloud_queue"] = 6031302916;
		["cloud"] = 6031302918;
		["folder_open"] = 6031302934;
		["grid_view"] = 6031302950;
		["cloud_off"] = 6031302993;
		["create_new_folder"] = 6031302933;
		["cloud_done"] = 6031302927;
		["folder"] = 6031302932;
		["drive_file_move"] = 6031302922;
		["drive_file_rename_outline"] = 6031302994;
		["notifications_active"] = 6034304908;
		["sentiment_neutral"] = 6034230636;
		["sick"] = 6034230642;
		["poll"] = 6034267991;
		["emoji_events"] = 6034275726;
		["groups"] = 6034281935;
		["sports_soccer"] = 6034227075;
		["person_add"] = 6034287514;
		["mood_bad"] = 6034295706;
		["person_remove_alt_1"] = 6034287515;
		["king_bed"] = 6034281948;
		["architecture"] = 6034275730;
		["deck"] = 6034295703;
		["group_add"] = 6034281909;
		["sports_basketball"] = 6034230649;
		["emoji_symbols"] = 6034281899;
		["switch_account"] = 6034227138;
		["remove_moderator"] = 6034267998;
		["coronavirus"] = 6034275724;
		["people"] = 6034287513;
		["person"] = 6034287594;
		["elderly"] = 6034295698;
		["clean_hands"] = 6034275729;
		["emoji_flags"] = 6034304898;
		["psychology"] = 6034287516;
		["person_add_alt"] = 6034267994;
		["sports_volleyball"] = 6034227139;
		["domain"] = 6034275722;
		["emoji_objects"] = 6034281900;
		["ios_share"] = 6034281941;
		["history_edu"] = 6034281934;
		["share"] = 6034230648;
		["military_tech"] = 6034295711;
		["sports_kabaddi"] = 6034227141;
		["cake"] = 6034295702;
		["engineering"] = 6034281908;
		["emoji_food_beverage"] = 6034304883;
		["notifications_none"] = 6034308947;
		["emoji_people"] = 6034281904;
		["thumb_down_alt"] = 6034227069;
		["sentiment_very_satisfied"] = 6034230650;
		["nights_stay"] = 6034304881;
		["reduce_capacity"] = 6034268013;
		["add_moderator"] = 6034295699;
		["science"] = 6034230640;
		["pages"] = 6034304892;
		["sentiment_satisfied"] = 6034230668;
		["plus_one"] = 6034268012;
		["party_mode"] = 6034287521;
		["person_remove"] = 6034267996;
		["single_bed"] = 6034230651;
		["mood"] = 6034295704;
		["public"] = 6034287522;
		["sports_rugby"] = 6034227073;
		["sports_handball"] = 6034227074;
		["person_add_alt_1"] = 6034287519;
		["people_alt"] = 6034287518;
		["notifications_off"] = 6034304894;
		["whatshot"] = 6034287525;
		["emoji_transportation"] = 6034281894;
		["outdoor_grill"] = 6034304900;
		["sentiment_very_dissatisfied"] = 6034230659;
		["masks"] = 6034295710;
		["luggage"] = 6034295708;
		["sports_motorsports"] = 6034227071;
		["sports_esports"] = 6034227061;
		["location_city"] = 6034304889;
		["sports_golf"] = 6034227060;
		["sentiment_dissatisfied"] = 6034230637;
		["no_luggage"] = 6034304891;
		["fireplace"] = 6034281910;
		["emoji_nature"] = 6034281896;
		["group"] = 6034281901;
		["thumb_up_alt"] = 6034227076;
		["sports_tennis"] = 6034227068;
		["facebook"] = 6034281898;
		["sports_mma"] = 6034227072;
		["person_outline"] = 6034268008;
		["sports_baseball"] = 6034230652;
		["sports_cricket"] = 6034230660;
		["people_outline"] = 6034287528;
		["notifications_paused"] = 6034304896;
		["emoji_emotions"] = 6034275731;
		["follow_the_signs"] = 6034281911;
		["sanitizer"] = 6034287586;
		["self_improvement"] = 6034230634;
		["notifications"] = 6034308946;
		["public_off"] = 6034287538;
		["recommend"] = 6034287524;
		["sports_football"] = 6034227067;
		["sports_hockey"] = 6034227064;
		["school"] = 6034230641;
		["connect_without_contact"] = 6034275800;
		["sports"] = 6034230647;
		["construction"] = 6034275725;
		["inventory"] = 6035056487;
		["add_box"] = 6035047375;
		["how_to_reg"] = 6035053288;
		["unarchive"] = 6035078921;
		["block_flipped"] = 6035047378;
		["file_copy"] = 6035053293;
		["bolt"] = 6035047381;
		["remove_circle_outline"] = 6035067843;
		["move_to_inbox"] = 6035067838;
		["save_alt"] = 6035067842;
		["weekend"] = 6035078894;
		["where_to_vote"] = 6035078913;
		["biotech"] = 6035047385;
		["report_off"] = 6035067830;
		["clear"] = 6035047409;
		["redo"] = 6035056483;
		["link"] = 6035056475;
		["drafts"] = 6035053297;
		["push_pin"] = 6035056481;
		["reply"] = 6035067844;
		["undo"] = 6035078896;
		["archive"] = 6035047379;
		["add"] = 6035047377;
		["insights"] = 6035067839;
		["flag"] = 6035053279;
		["save"] = 6035067857;
		["text_format"] = 6035078890;
		["content_cut"] = 6035053280;
		["ballot"] = 6035047386;
		["remove"] = 6035067836;
		["calculate"] = 6035047384;
		["report"] = 6035067826;
		["markunread"] = 6035056476;
		["delete_sweep"] = 6035053301;
		["gesture"] = 6035053287;
		["link_off"] = 6035056484;
		["forward"] = 6035053298;
		["reply_all"] = 6035067824;
		["how_to_vote"] = 6035053295;
		["square_foot"] = 6035078918;
		["outlined_flag"] = 6035056486;
		["add_circle"] = 6035047380;
		["stacked_bar_chart"] = 6035078892;
		["policy"] = 6035056512;
		["backspace"] = 6035047397;
		["sort"] = 6035078888;
		["content_paste"] = 6035053285;
		["low_priority"] = 6035056491;
		["font_download"] = 6035053275;
		["shield"] = 6035078889;
		["waves"] = 6035078898;
		["select_all"] = 6035067834;
		["dynamic_feed"] = 6035053289;
		["mail"] = 6035056477;
		["amp_stories"] = 6035047382;
		["filter_list"] = 6035053294;
		["send"] = 6035067832;
		["create"] = 6035053304;
		["stream"] = 6035078897;
		["next_week"] = 6035067835;
		["inbox"] = 6035067831;
		["add_link"] = 6035047374;
		["content_copy"] = 6035053278;
		["remove_circle"] = 6035067837;
		["add_circle_outline"] = 6035047391;
		["block"] = 6035047387;
		["tag"] = 6035078895;
		["beach_access"] = 6035107923;
		["stroller"] = 6035161535;
		["family_restroom"] = 6035121916;
		["corporate_fare"] = 6035121908;
		["no_meeting_room"] = 6035153649;
		["do_not_touch"] = 6035121915;
		["ac_unit"] = 6035107929;
		["business_center"] = 6035107933;
		["spa"] = 6035153639;
		["no_flash"] = 6035145424;
		["no_cell"] = 6035145376;
		["room_service"] = 6035153648;
		["tapas"] = 6035161533;
		["microwave"] = 6035145367;
		["meeting_room"] = 6035145361;
		["wash"] = 6035161540;
		["escalator"] = 6035121939;
		["house_siding"] = 6035145393;
		["food_bank"] = 6035121921;
		["foundation"] = 6035121918;
		["elevator"] = 6035121912;
		["room_preferences"] = 6035153642;
		["do_not_step"] = 6035121910;
		["free_breakfast"] = 6035145363;
		["house"] = 6035145364;
		["child_care"] = 6035107927;
		["night_shelter"] = 6035145378;
		["child_friendly"] = 6035121942;
		["checkroom"] = 6035107931;
		["hot_tub"] = 6035145382;
		["dry"] = 6035121909;
		["charging_station"] = 6035107925;
		["all_inclusive"] = 6035107920;
		["bento"] = 6035107924;
		["no_backpack"] = 6035145368;
		["storefront"] = 6035161534;
		["no_food"] = 6035145372;
		["backpack"] = 6035107928;
		["stairs"] = 6035153637;
		["carpenter"] = 6035107955;
		["no_stroller"] = 6035153661;
		["roofing"] = 6035153656;
		["umbrella"] = 6035161550;
		["sports_bar"] = 6035153638;
		["apartment"] = 6035107922;
		["smoke_free"] = 6035153647;
		["pool"] = 6035153655;
		["bathtub"] = 6035107939;
		["no_drinks"] = 6035145390;
		["escalator_warning"] = 6035121930;
		["wheelchair_pickup"] = 6035161536;
		["smoking_rooms"] = 6035153636;
		["rice_bowl"] = 6035153662;
		["tty"] = 6035161541;
		["no_photography"] = 6035153664;
		["casino"] = 6035107936;
		["fence"] = 6035121923;
		["grass"] = 6035145359;
		["countertops"] = 6035121914;
		["kitchen"] = 6035145362;
		["golf_course"] = 6035145423;
		["soap"] = 6035153645;
		["water_damage"] = 6035161563;
		["airport_shuttle"] = 6035107921;
		["fitness_center"] = 6035121907;
		["baby_changing_station"] = 6035107930;
		["fire_extinguisher"] = 6035121913;
		["sparkle"] = 4483362748
	},
	Lucide = {
		["a-arrow-down"] = 85758889687786,
		["a-arrow-up"] = 102165397775777,
		["a-large-small"] = 120435565718499,
		accessibility = 134709504811618,
		activity = 116785635688905,
		["air-vent"] = 128830959442416,
		airplay = 120532433393858,
		["alarm-clock"] = 135676792539632,
		["alarm-clock-check"] = 127147726542044,
		["alarm-clock-minus"] = 95643155997004,
		["alarm-clock-off"] = 137565311508297,
		["alarm-clock-plus"] = 120411905187238,
		["alarm-smoke"] = 132790621765466,
		album = 127392884430355,
		["align-center"] = 96679836838314,
		["align-center-horizontal"] = 81234251374424,
		["align-center-vertical"] = 123778475388904,
		["align-end-horizontal"] = 81993664554439,
		["align-end-vertical"] = 99312370694107,
		["align-horizontal-distribute-center"] = 118173212655147,
		["align-horizontal-distribute-end"] = 119611041085513,
		["align-horizontal-distribute-start"] = 121542670969125,
		["align-horizontal-justify-center"] = 129528110611234,
		["align-horizontal-justify-end"] = 84954252650701,
		["align-horizontal-justify-start"] = 94264399395941,
		["align-horizontal-space-around"] = 103744081790884,
		["align-horizontal-space-between"] = 101251856513947,
		["align-justify"] = 132508901949872,
		["align-left"] = 73665096529381,
		["align-right"] = 119992416120405,
		["align-start-horizontal"] = 92574847248087,
		["align-start-vertical"] = 96167730292932,
		["align-vertical-distribute-center"] = 100557171686579,
		["align-vertical-distribute-end"] = 140244274635306,
		["align-vertical-distribute-start"] = 104366918572697,
		["align-vertical-justify-center"] = 125823633272170,
		["align-vertical-justify-end"] = 101012057660025,
		["align-vertical-justify-start"] = 127756811142477,
		["align-vertical-space-around"] = 80630398253986,
		["align-vertical-space-between"] = 99587234432478,
		ambulance = 87996833293600,
		ampersand = 76003774257181,
		ampersands = 122865331745636,
		amphora = 85710574172044,
		anchor = 117368273793473,
		angry = 131535996678230,
		annoyed = 89651894120317,
		antenna = 105556767656262,
		anvil = 100535116378267,
		aperture = 88920539534875,
		["app-window"] = 128524598896661,
		["app-window-mac"] = 84920671926321,
		apple = 82452145861900,
		archive = 96979844504359,
		["archive-restore"] = 130207139403143,
		["archive-x"] = 125724859663305,
		armchair = 92951944347771,
		["arrow-big-down"] = 87872502681784,
		["arrow-big-down-dash"] = 80956925610434,
		["arrow-big-left"] = 76008736050357,
		["arrow-big-left-dash"] = 80166004308034,
		["arrow-big-right"] = 81390374011332,
		["arrow-big-right-dash"] = 125910019327152,
		["arrow-big-up"] = 118315457005585,
		["arrow-big-up-dash"] = 139174253931992,
		["arrow-down"] = 111101849488750,
		["arrow-down-0-1"] = 134662804888116,
		["arrow-down-1-0"] = 90807982982621,
		["arrow-down-a-z"] = 74563886614714,
		["arrow-down-from-line"] = 123039586915624,
		["arrow-down-left"] = 105470816142918,
		["arrow-down-narrow-wide"] = 104635517851768,
		["arrow-down-right"] = 104630792951402,
		["arrow-down-to-dot"] = 95176928712454,
		["arrow-down-to-line"] = 109729358294452,
		["arrow-down-up"] = 139238003599315,
		["arrow-down-wide-narrow"] = 88577562336410,
		["arrow-down-z-a"] = 90653871517145,
		["arrow-left"] = 86088091986547,
		["arrow-left-from-line"] = 88700685151310,
		["arrow-left-right"] = 94596049358882,
		["arrow-left-to-line"] = 116829154369215,
		["arrow-right"] = 81302631706885,
		["arrow-right-from-line"] = 132141803726901,
		["arrow-right-left"] = 108283385684703,
		["arrow-right-to-line"] = 114892398312410,
		["arrow-up"] = 79062740627249,
		["arrow-up-0-1"] = 114095112758791,
		["arrow-up-1-0"] = 115833544112532,
		["arrow-up-a-z"] = 130831349804002,
		["arrow-up-down"] = 102155677695268,
		["arrow-up-from-dot"] = 134959689985016,
		["arrow-up-from-line"] = 134860743051776,
		["arrow-up-left"] = 107477197303574,
		["arrow-up-narrow-wide"] = 101421168592063,
		["arrow-up-right"] = 103889806698388,
		["arrow-up-to-line"] = 131974361540264,
		["arrow-up-wide-narrow"] = 106886180124309,
		["arrow-up-z-a"] = 76578983028237,
		["arrows-up-from-line"] = 105423404426073,
		asterisk = 123815391218414,
		["at-sign"] = 104314582758551,
		atom = 120167347744561,
		["audio-lines"] = 138755914830486,
		["audio-waveform"] = 119789394178873,
		award = 89623672395278,
		axe = 95479937653376,
		["axis-3d"] = 92397422208087,
		baby = 134780923890658,
		backpack = 78993249203823,
		badge = 93861197775357,
		["badge-alert"] = 73521163893374,
		["badge-cent"] = 122278154144822,
		["badge-check"] = 102864233048311,
		["badge-dollar-sign"] = 99073011426006,
		["badge-euro"] = 129639299324055,
		["badge-indian-rupee"] = 87973104646655,
		["badge-info"] = 98821060789724,
		["badge-japanese-yen"] = 134928701899269,
		["badge-minus"] = 129618320064265,
		["badge-percent"] = 105307797413967,
		["badge-plus"] = 120096069624662,
		["badge-pound-sterling"] = 98623823861803,
		["badge-question-mark"] = 114663892643950,
		["badge-russian-ruble"] = 99522239121803,
		["badge-swiss-franc"] = 115747080056818,
		["badge-turkish-lira"] = 137289094254207,
		["badge-x"] = 127345048117218,
		["baggage-claim"] = 108988660196157,
		ban = 131594718784390,
		banana = 126474514866989,
		bandage = 102355944011166,
		banknote = 83624352345036,
		["banknote-arrow-down"] = 128101736029907,
		["banknote-arrow-up"] = 103476760707791,
		["banknote-x"] = 110844057471453,
		barcode = 129209916672607,
		barrel = 127931314050877,
		baseline = 137447148848893,
		bath = 111108655648642,
		battery = 81540661066811,
		["battery-charging"] = 126836500232390,
		["battery-full"] = 127212547690381,
		["battery-low"] = 87721404307217,
		["battery-medium"] = 114615415737248,
		["battery-plus"] = 76354196605526,
		["battery-warning"] = 136795384828263,
		beaker = 140429312347329,
		bean = 140548534094518,
		["bean-off"] = 87490357773352,
		bed = 103703460158347,
		["bed-double"] = 118545136165123,
		["bed-single"] = 117894740011786,
		beef = 95141393904694,
		bell = 111725241873349,
		["bell-dot"] = 102000063515653,
		["bell-electric"] = 130154093563594,
		["bell-minus"] = 134871560843826,
		["bell-off"] = 109403921599739,
		["bell-plus"] = 87193682465452,
		["bell-ring"] = 81911080119140,
		["between-horizontal-end"] = 105855324839543,
		["between-horizontal-start"] = 116266907424675,
		["between-vertical-end"] = 109243784030881,
		["between-vertical-start"] = 112708575033628,
		["biceps-flexed"] = 113573819070463,
		bike = 120355969619987,
		binary = 82905169249889,
		binoculars = 114841582615801,
		biohazard = 90593430701402,
		bird = 127082032570770,
		bitcoin = 120165823908407,
		blend = 106898143444225,
		blinds = 131748682748698,
		blocks = 99930206828481,
		bluetooth = 87938138872705,
		["bluetooth-connected"] = 93809243280097,
		["bluetooth-off"] = 92065127311527,
		["bluetooth-searching"] = 138407763527325,
		bold = 71230510917945,
		bolt = 72499878743015,
		bomb = 119539352578001,
		bone = 93032826374472,
		book = 136417435522797,
		["book-a"] = 138905558517206,
		["book-alert"] = 83126881397457,
		["book-audio"] = 130817325428812,
		["book-check"] = 101435243286406,
		["book-copy"] = 92171152631020,
		["book-dashed"] = 81283267299629,
		["book-down"] = 133514420249956,
		["book-headphones"] = 139523016403916,
		["book-heart"] = 122531870789237,
		["book-image"] = 137276864404721,
		["book-key"] = 139461027818572,
		["book-lock"] = 98420126712941,
		["book-marked"] = 108700129544150,
		["book-minus"] = 134429286820139,
		["book-open"] = 73094472868219,
		["book-open-check"] = 139564107496900,
		["book-open-text"] = 112163368354922,
		["book-plus"] = 86198588567912,
		["book-text"] = 92477178021408,
		["book-type"] = 140569336920621,
		["book-up"] = 129825144914500,
		["book-up-2"] = 138870529166566,
		["book-user"] = 78445558294223,
		["book-x"] = 117684589004730,
		bookmark = 96422374119496,
		["bookmark-check"] = 140385274312943,
		["bookmark-minus"] = 90761509653848,
		["bookmark-plus"] = 102716399992603,
		["bookmark-x"] = 83946741234593,
		["boom-box"] = 117773767367782,
		bot = 112973706230253,
		["bot-message-square"] = 127454915177046,
		["bot-off"] = 123215836836938,
		["bow-arrow"] = 82126194792160,
		box = 101391159909398,
		boxes = 129614835711516,
		braces = 74399703620454,
		brackets = 126480941270849,
		brain = 80449922621372,
		["brain-circuit"] = 122829293465734,
		["brain-cog"] = 133841445789468,
		["brick-wall"] = 88059137745523,
		["brick-wall-fire"] = 101508535298010,
		["brick-wall-shield"] = 122970924994177,
		briefcase = 79573382931819,
		["briefcase-business"] = 89024144265875,
		["briefcase-conveyor-belt"] = 80699894594034,
		["briefcase-medical"] = 88977669291957,
		["bring-to-front"] = 121372673068497,
		brush = 140399962450518,
		["brush-cleaning"] = 77081887717462,
		bubbles = 100951413779327,
		bug = 108064626456459,
		["bug-off"] = 115130754051050,
		["bug-play"] = 93005823489214,
		building = 115759871615135,
		["building-2"] = 113633264034729,
		bus = 70492885634507,
		["bus-front"] = 101442123728652,
		cable = 73929033306217,
		["cable-car"] = 103343370160284,
		cake = 94945328569141,
		["cake-slice"] = 134869363778873,
		calculator = 126294519603935,
		calendar = 95545489603627,
		["calendar-1"] = 111669544177893,
		["calendar-arrow-down"] = 98826297336095,
		["calendar-arrow-up"] = 101259481484784,
		["calendar-check"] = 128735293881337,
		["calendar-check-2"] = 134741295436727,
		["calendar-clock"] = 137989998809749,
		["calendar-cog"] = 81132100829120,
		["calendar-days"] = 74473866264642,
		["calendar-fold"] = 72800363993863,
		["calendar-heart"] = 140469143489469,
		["calendar-minus"] = 126947076491962,
		["calendar-minus-2"] = 114758284207771,
		["calendar-off"] = 83172321745470,
		["calendar-plus"] = 95864120179039,
		["calendar-plus-2"] = 110548362075353,
		["calendar-range"] = 137666557292561,
		["calendar-search"] = 77709463965815,
		["calendar-sync"] = 97624728588729,
		["calendar-x"] = 138974312970463,
		["calendar-x-2"] = 107515535887947,
		camera = 102911860111235,
		["camera-off"] = 99242316763000,
		candy = 121602796953412,
		["candy-cane"] = 112464754953529,
		["candy-off"] = 98908167238404,
		captions = 92247523675264,
		["captions-off"] = 117421756298550,
		car = 104209031513829,
		["car-front"] = 108397050137008,
		["car-taxi-front"] = 73584751879123,
		caravan = 127063101240586,
		["card-sim"] = 87568181073492,
		carrot = 121695263564136,
		["case-lower"] = 104147111219050,
		["case-sensitive"] = 80443686256687,
		["case-upper"] = 106568493343250,
		["cassette-tape"] = 85528666149718,
		cast = 106045389407030,
		castle = 137349466287423,
		cat = 132587012252853,
		cctv = 96089950910363,
		["chart-area"] = 83865456239149,
		["chart-bar"] = 78022204342641,
		["chart-bar-big"] = 77915167652266,
		["chart-bar-decreasing"] = 128999724972766,
		["chart-bar-increasing"] = 94790043521729,
		["chart-bar-stacked"] = 118586341637168,
		["chart-candlestick"] = 97939388409760,
		["chart-column"] = 90604892299985,
		["chart-column-big"] = 117124840997620,
		["chart-column-decreasing"] = 128154461153272,
		["chart-column-increasing"] = 110238053193715,
		["chart-column-stacked"] = 138210545678793,
		["chart-gantt"] = 105284278917364,
		["chart-line"] = 132073950959918,
		["chart-no-axes-column"] = 134593063392849,
		["chart-no-axes-column-decreasing"] = 117582413267339,
		["chart-no-axes-column-increasing"] = 107383929417521,
		["chart-no-axes-combined"] = 125766210212199,
		["chart-no-axes-gantt"] = 136683497999733,
		["chart-pie"] = 129237625973646,
		["chart-scatter"] = 109368208547302,
		["chart-spline"] = 128939166873577,
		check = 83827110621355,
		["check-check"] = 85764415779159,
		["check-line"] = 85776673122871,
		["chef-hat"] = 104351698660651,
		cherry = 130832753420629,
		["chevron-down"] = 95086910949405,
		["chevron-first"] = 130485497879762,
		["chevron-last"] = 127072220474704,
		["chevron-left"] = 83856486110301,
		["chevron-right"] = 126507964682213,
		["chevron-up"] = 124630674114245,
		["chevrons-down"] = 118746624854239,
		["chevrons-down-up"] = 122938925052724,
		["chevrons-left"] = 72622305378588,
		["chevrons-left-right"] = 100027150072609,
		["chevrons-left-right-ellipsis"] = 70758373090992,
		["chevrons-right"] = 115563110262022,
		["chevrons-right-left"] = 79674513843833,
		["chevrons-up"] = 115981451099607,
		["chevrons-up-down"] = 113432796824448,
		chrome = 73342145832786,
		church = 136057686683219,
		circle = 97474013459876,
		["circle-alert"] = 86075768491850,
		["circle-arrow-down"] = 98516510858394,
		["circle-arrow-left"] = 139149045348698,
		["circle-arrow-out-down-left"] = 140114130402613,
		["circle-arrow-out-down-right"] = 97306619688140,
		["circle-arrow-out-up-left"] = 133904465013804,
		["circle-arrow-out-up-right"] = 133791579853102,
		["circle-arrow-right"] = 132106229530514,
		["circle-arrow-up"] = 125630987618979,
		["circle-check"] = 122835208471730,
		["circle-check-big"] = 101462339244321,
		["circle-chevron-down"] = 125398962450772,
		["circle-chevron-left"] = 133979492199232,
		["circle-chevron-right"] = 130029053510525,
		["circle-chevron-up"] = 137057131849576,
		["circle-dashed"] = 97773019242734,
		["circle-divide"] = 75278590313141,
		["circle-dollar-sign"] = 103021845191343,
		["circle-dot"] = 73332621255981,
		["circle-dot-dashed"] = 121201310391755,
		["circle-ellipsis"] = 128894546879090,
		["circle-equal"] = 91854769894722,
		["circle-fading-arrow-up"] = 121178878326961,
		["circle-fading-plus"] = 95512963110153,
		["circle-gauge"] = 84688454826847,
		["circle-minus"] = 74458161947564,
		["circle-off"] = 80618483788295,
		["circle-parking"] = 121342131175144,
		["circle-parking-off"] = 115951067573453,
		["circle-pause"] = 75601858754638,
		["circle-percent"] = 89021739919224,
		["circle-play"] = 119442756895009,
		["circle-plus"] = 132023187288319,
		["circle-pound-sterling"] = 121749745341582,
		["circle-power"] = 131944289575262,
		["circle-question-mark"] = 98575632186975,
		["circle-slash"] = 86554477881978,
		["circle-slash-2"] = 93846864384983,
		["circle-small"] = 106775888594817,
		["circle-star"] = 108994144808450,
		["circle-stop"] = 122478988921288,
		["circle-user"] = 73363870264217,
		["circle-user-round"] = 103422319407938,
		["circle-x"] = 136096054247483,
		["circuit-board"] = 102649990533936,
		citrus = 104012894480157,
		clapperboard = 117040519290119,
		clipboard = 91839478896367,
		["clipboard-check"] = 119930716282333,
		["clipboard-clock"] = 81178312131599,
		["clipboard-copy"] = 116099874965891,
		["clipboard-list"] = 110095483413821,
		["clipboard-minus"] = 107683237596936,
		["clipboard-paste"] = 137750657442733,
		["clipboard-pen"] = 112275963070957,
		["clipboard-pen-line"] = 111346066067551,
		["clipboard-plus"] = 132362866476079,
		["clipboard-type"] = 106736512129205,
		["clipboard-x"] = 128986978015444,
		clock = 96835529467684,
		["clock-1"] = 98563563321460,
		["clock-10"] = 80443443598462,
		["clock-11"] = 82371834247998,
		["clock-12"] = 133877976025070,
		["clock-2"] = 72258367874092,
		["clock-3"] = 86319537133958,
		["clock-4"] = 111040057497751,
		["clock-5"] = 82455058311564,
		["clock-6"] = 110541146574832,
		["clock-7"] = 138423994726927,
		["clock-8"] = 98901513399369,
		["clock-9"] = 140464097226658,
		["clock-alert"] = 115862173875314,
		["clock-arrow-down"] = 95351498388159,
		["clock-arrow-up"] = 131512554213603,
		["clock-fading"] = 138812484601909,
		["clock-plus"] = 108994381956359,
		["closed-caption"] = 109168929168877,
		cloud = 76797375125469,
		["cloud-alert"] = 106567345820073,
		["cloud-check"] = 83689617445982,
		["cloud-cog"] = 99037393440946,
		["cloud-download"] = 134259137069761,
		["cloud-drizzle"] = 108966030756512,
		["cloud-fog"] = 116434374562091,
		["cloud-hail"] = 93896344446382,
		["cloud-lightning"] = 88393801019014,
		["cloud-moon"] = 92598532990542,
		["cloud-moon-rain"] = 102795706163713,
		["cloud-off"] = 132746052928464,
		["cloud-rain"] = 126682720368880,
		["cloud-rain-wind"] = 138531953575675,
		["cloud-snow"] = 83889452050491,
		["cloud-sun"] = 99857531021323,
		["cloud-sun-rain"] = 102969016910466,
		["cloud-upload"] = 85588611412306,
		cloudy = 72892691173430,
		clover = 73146836842348,
		club = 119692145642080,
		code = 102858857098762,
		["code-xml"] = 130876992978049,
		codepen = 121196034119960,
		codesandbox = 81104810964988,
		coffee = 75171771078867,
		cog = 134998527925514,
		coins = 128784569032326,
		["columns-2"] = 89175983308456,
		["columns-3"] = 109318054321048,
		["columns-3-cog"] = 138473447831624,
		["columns-4"] = 92778631374832,
		combine = 98228911815481,
		command = 129307680894782,
		compass = 117355392623233,
		component = 81317444646043,
		computer = 129323176739507,
		["concierge-bell"] = 126886445681359,
		cone = 74845976589938,
		construction = 115083821531795,
		contact = 83336471862351,
		["contact-round"] = 92207205844906,
		container = 116643588421234,
		contrast = 76959893700184,
		cookie = 139241068220893,
		["cooking-pot"] = 73135275032763,
		copy = 87942399647942,
		["copy-check"] = 99030373914807,
		["copy-minus"] = 73147465136627,
		["copy-plus"] = 124547842490145,
		["copy-slash"] = 73629354412770,
		["copy-x"] = 76935228109965,
		copyleft = 117008643514602,
		copyright = 116764791222062,
		["corner-down-left"] = 121810619354729,
		["corner-down-right"] = 94219370057308,
		["corner-left-down"] = 88518708580891,
		["corner-left-up"] = 80457911677892,
		["corner-right-down"] = 71667850048566,
		["corner-right-up"] = 116802297506682,
		["corner-up-left"] = 77719684055742,
		["corner-up-right"] = 101875782041114,
		cpu = 115781787166822,
		["creative-commons"] = 106945564709172,
		["credit-card"] = 135019527878105,
		croissant = 124064182582120,
		crop = 137832753521417,
		cross = 106039923010417,
		crosshair = 114929017287945,
		crown = 90472614287057,
		cuboid = 85125857520529,
		["cup-soda"] = 116064630908908,
		currency = 98741673384975,
		cylinder = 106008846957333,
		dam = 123638563636102,
		database = 122884003685338,
		["database-backup"] = 134263890065988,
		["database-zap"] = 94292145388316,
		["decimals-arrow-left"] = 83364854887027,
		["decimals-arrow-right"] = 89255202941321,
		delete = 120475342373468,
		dessert = 79122775950408,
		diameter = 103202047751161,
		diamond = 116224572544413,
		["diamond-minus"] = 98219591040851,
		["diamond-percent"] = 90953177250482,
		["diamond-plus"] = 81855866369969,
		["dice-1"] = 129785132691343,
		["dice-2"] = 101184428062194,
		["dice-3"] = 126124539917527,
		["dice-4"] = 136593201423203,
		["dice-5"] = 72548398039172,
		["dice-6"] = 107423423270100,
		dices = 117821030233748,
		diff = 89271474511472,
		disc = 139513828111819,
		["disc-2"] = 77624862049574,
		["disc-3"] = 101670496442540,
		["disc-album"] = 119925914044267,
		divide = 122092927804054,
		dna = 89745363802733,
		["dna-off"] = 138639847028076,
		dock = 132625251672190,
		dog = 111571812945872,
		["dollar-sign"] = 118972397587528,
		donut = 80434741396669,
		["door-closed"] = 89760328598955,
		["door-closed-locked"] = 72612456720492,
		["door-open"] = 133814065231262,
		dot = 97016002851923,
		download = 93868047445509,
		["drafting-compass"] = 132019045125555,
		drama = 140495061255070,
		dribbble = 85814569433570,
		drill = 102448607336819,
		drone = 87852662372231,
		droplet = 117947500824611,
		["droplet-off"] = 89562126293632,
		droplets = 91168064495352,
		drum = 85667754872431,
		drumstick = 75387497663037,
		dumbbell = 135834722331614,
		ear = 125040388889621,
		["ear-off"] = 77431400735000,
		earth = 80407859572555,
		["earth-lock"] = 82771383007037,
		eclipse = 124423514511474,
		egg = 73908680452587,
		["egg-fried"] = 88691210642745,
		["egg-off"] = 75945935080886,
		ellipsis = 95956203670622,
		["ellipsis-vertical"] = 93274856771582,
		equal = 81138954359025,
		["equal-approximately"] = 126766764416385,
		["equal-not"] = 110767672641130,
		eraser = 101514212866613,
		["ethernet-port"] = 107171703835846,
		euro = 105515269837621,
		expand = 135216706603096,
		["external-link"] = 88749979118129,
		eye = 139722329189430,
		["eye-closed"] = 85964738779718,
		["eye-off"] = 112375739491233,
		facebook = 126875779412726,
		factory = 124610887424481,
		fan = 99112617546784,
		["fast-forward"] = 86261062156594,
		feather = 72722125673150,
		fence = 136027177552403,
		["ferris-wheel"] = 94212033084546,
		figma = 78102137532795,
		file = 105710786731627,
		["file-archive"] = 121027564735426,
		["file-audio"] = 109136641816876,
		["file-audio-2"] = 71519060566551,
		["file-axis-3d"] = 120595284164307,
		["file-badge"] = 130908597463749,
		["file-badge-2"] = 117822997727543,
		["file-box"] = 78582029223846,
		["file-chart-column"] = 79314568863524,
		["file-chart-column-increasing"] = 113934830439854,
		["file-chart-line"] = 127333232922341,
		["file-chart-pie"] = 87366366651618,
		["file-check"] = 82422075525002,
		["file-check-2"] = 87216739205557,
		["file-clock"] = 73969155690610,
		["file-code"] = 92873308907212,
		["file-code-2"] = 115805780254840,
		["file-cog"] = 89816062085634,
		["file-diff"] = 123117415259557,
		["file-digit"] = 104037036187285,
		["file-down"] = 70441423818099,
		["file-heart"] = 90332007470916,
		["file-image"] = 80147266004613,
		["file-input"] = 126683034896557,
		["file-json"] = 76272094739618,
		["file-json-2"] = 117283373455325,
		["file-key"] = 85781683326011,
		["file-key-2"] = 104279126245073,
		["file-lock"] = 74414492225090,
		["file-lock-2"] = 129467818396353,
		["file-minus"] = 100049317730317,
		["file-minus-2"] = 99533501912168,
		["file-music"] = 87486385971490,
		["file-output"] = 117761656606452,
		["file-pen"] = 120012000577923,
		["file-pen-line"] = 77107867479655,
		["file-play"] = 122519637890628,
		["file-plus"] = 134349751246644,
		["file-plus-2"] = 98358464374463,
		["file-question-mark"] = 107111567783242,
		["file-scan"] = 116607859572941,
		["file-search"] = 87648314058326,
		["file-search-2"] = 97504576826222,
		["file-sliders"] = 87362735438576,
		["file-spreadsheet"] = 108378493201587,
		["file-stack"] = 119139237519469,
		["file-symlink"] = 125888988169632,
		["file-terminal"] = 114817439039127,
		["file-text"] = 77346633411296,
		["file-type"] = 91319647276184,
		["file-type-2"] = 102862931204754,
		["file-up"] = 77215633607245,
		["file-user"] = 125031706574705,
		["file-video-camera"] = 98825192269661,
		["file-volume"] = 84825655898765,
		["file-volume-2"] = 132074661677474,
		["file-warning"] = 131113901247439,
		["file-x"] = 134673190690961,
		["file-x-2"] = 75426786305569,
		files = 119868587246453,
		film = 115982940808785,
		fingerprint = 135337299493865,
		["fire-extinguisher"] = 106667025708329,
		fish = 107002260548857,
		["fish-off"] = 83515767284587,
		["fish-symbol"] = 112313456680575,
		flag = 80165228709790,
		["flag-off"] = 131374214560413,
		["flag-triangle-left"] = 100274047554673,
		["flag-triangle-right"] = 95559011206904,
		flame = 78769660969441,
		["flame-kindling"] = 125287652452426,
		flashlight = 114148297083785,
		["flashlight-off"] = 78806207489112,
		["flask-conical"] = 77588155748536,
		["flask-conical-off"] = 140153784540477,
		["flask-round"] = 125921380095942,
		["flip-horizontal"] = 104841355411279,
		["flip-horizontal-2"] = 75840761823703,
		["flip-vertical"] = 88010991372085,
		["flip-vertical-2"] = 115335841457244,
		flower = 125602823130456,
		["flower-2"] = 93937864318346,
		focus = 74209922635562,
		["fold-horizontal"] = 119215308506101,
		["fold-vertical"] = 89627287319601,
		folder = 94236858672537,
		["folder-archive"] = 85978040479686,
		["folder-check"] = 89058605827073,
		["folder-clock"] = 132379000568110,
		["folder-closed"] = 78087942744334,
		["folder-code"] = 79208102753918,
		["folder-cog"] = 125325854177187,
		["folder-dot"] = 135307937184362,
		["folder-down"] = 133724276147220,
		["folder-git"] = 129905012475725,
		["folder-git-2"] = 132556334850282,
		["folder-heart"] = 74682854132263,
		["folder-input"] = 89543549078565,
		["folder-kanban"] = 115692234423291,
		["folder-key"] = 134841972348783,
		["folder-lock"] = 129345483035475,
		["folder-minus"] = 96592440405999,
		["folder-open"] = 100030967746766,
		["folder-open-dot"] = 93584740507880,
		["folder-output"] = 79131635705997,
		["folder-pen"] = 95853187570930,
		["folder-plus"] = 133649526561782,
		["folder-root"] = 85546937479322,
		["folder-search"] = 85575256433549,
		["folder-search-2"] = 132801780326542,
		["folder-symlink"] = 82192734774481,
		["folder-sync"] = 80229070969489,
		["folder-tree"] = 137484935980485,
		["folder-up"] = 135876471645692,
		["folder-x"] = 98414588777713,
		folders = 129365910191151,
		footprints = 128293375583452,
		forklift = 121191524995774,
		forward = 85252404877367,
		frame = 91667256603587,
		framer = 105756021674631,
		frown = 136210266332024,
		fuel = 124477459297771,
		fullscreen = 75191423285573,
		funnel = 139525415522108,
		["funnel-plus"] = 85388798952525,
		["funnel-x"] = 118617352389010,
		["gallery-horizontal"] = 119833288662729,
		["gallery-horizontal-end"] = 110525792845537,
		["gallery-thumbnails"] = 104642411702006,
		["gallery-vertical"] = 73022710081053,
		["gallery-vertical-end"] = 81965622854313,
		gamepad = 98531369429309,
		["gamepad-2"] = 123513783706820,
		gauge = 112385371277348,
		gavel = 135735395765414,
		gem = 111750318675671,
		["georgian-lari"] = 83044477439865,
		ghost = 121912141443713,
		gift = 104098622197576,
		["git-branch"] = 137795533783771,
		["git-branch-plus"] = 140661560177072,
		["git-commit-horizontal"] = 70945132741002,
		["git-commit-vertical"] = 91329034046756,
		["git-compare"] = 115173556067875,
		["git-compare-arrows"] = 88221652268203,
		["git-fork"] = 99605451182076,
		["git-graph"] = 112496986736544,
		["git-merge"] = 136694613142223,
		["git-pull-request"] = 103161641898441,
		["git-pull-request-arrow"] = 135103379062990,
		["git-pull-request-closed"] = 132153092177959,
		["git-pull-request-create"] = 72404602418293,
		["git-pull-request-create-arrow"] = 78997835114389,
		["git-pull-request-draft"] = 109941927307148,
		github = 99911323926868,
		gitlab = 84697247849648,
		["glass-water"] = 88501428715818,
		glasses = 71294658108313,
		globe = 111578783307093,
		["globe-lock"] = 90505069766503,
		goal = 113884228231281,
		gpu = 94475400466478,
		["graduation-cap"] = 137048485405567,
		grape = 81297793587857,
		["grid-2x2"] = 74713443066181,
		["grid-2x2-check"] = 138646582122430,
		["grid-2x2-plus"] = 73772834594194,
		["grid-2x2-x"] = 70574771191740,
		["grid-3x2"] = 98309561243489,
		["grid-3x3"] = 71217273531422,
		grip = 85101746401400,
		["grip-horizontal"] = 87629819003793,
		["grip-vertical"] = 137774674680603,
		group = 137317722960946,
		guitar = 73621537334007,
		ham = 88694785814390,
		hamburger = 94625438561758,
		hammer = 118024154647073,
		hand = 135226632951455,
		["hand-coins"] = 83908670424159,
		["hand-fist"] = 107874697791879,
		["hand-grab"] = 123243858007453,
		["hand-heart"] = 112348965568014,
		["hand-helping"] = 125055501525649,
		["hand-metal"] = 79886749805841,
		["hand-platter"] = 107005076555892,
		handbag = 91595142847556,
		handshake = 119934900822508,
		["hard-drive"] = 78399523068992,
		["hard-drive-download"] = 126141378180246,
		["hard-drive-upload"] = 83678732882261,
		["hard-hat"] = 108269886668169,
		hash = 79281219073716,
		["hat-glasses"] = 88187986739237,
		haze = 71695050029489,
		["hdmi-port"] = 81667603031684,
		heading = 78795987652364,
		["heading-1"] = 139010744018776,
		["heading-2"] = 124511186941584,
		["heading-3"] = 93398585070111,
		["heading-4"] = 129752194457637,
		["heading-5"] = 91071250337131,
		["heading-6"] = 120942934503080,
		["headphone-off"] = 129718080175290,
		headphones = 77933962515384,
		headset = 78282688338634,
		heart = 111284155515598,
		["heart-crack"] = 127768416202523,
		["heart-handshake"] = 116921190920035,
		["heart-minus"] = 73753737435862,
		["heart-off"] = 77001527259120,
		["heart-plus"] = 136895624976238,
		["heart-pulse"] = 77506710442387,
		heater = 92597012287078,
		hexagon = 107545705237342,
		highlighter = 76647612275284,
		history = 87356875172942,
		hop = 107327941544346,
		["hop-off"] = 82070652552741,
		hospital = 136121422327167,
		hotel = 116521770015178,
		hourglass = 97354459771104,
		house = 127889862453151,
		["house-plug"] = 78286530988441,
		["house-plus"] = 86361930968044,
		["house-wifi"] = 81833657881659,
		["ice-cream-bowl"] = 132923169807183,
		["ice-cream-cone"] = 113398279002531,
		["id-card"] = 132284632593096,
		["id-card-lanyard"] = 109892675249866,
		image = 97933683823480,
		["image-down"] = 128149725849146,
		["image-minus"] = 133568289476916,
		["image-off"] = 99722939227313,
		["image-play"] = 73625941877084,
		["image-plus"] = 110592938693426,
		["image-up"] = 132790868440788,
		["image-upscale"] = 93091453446368,
		images = 100017582062659,
		import = 139415113590086,
		inbox = 117961494051741,
		["indent-decrease"] = 90925139615278,
		["indent-increase"] = 110694604864721,
		infinity = 71094877806551,
		info = 117194610053749,
		["inspection-panel"] = 140555328817154,
		instagram = 137841936676016,
		italic = 138130625449010,
		["iteration-ccw"] = 106807980654516,
		["iteration-cw"] = 117352992192290,
		["japanese-yen"] = 135085526808806,
		joystick = 126601646824958,
		kanban = 94237167428633,
		kayak = 114220085067472,
		key = 128426502701541,
		["key-round"] = 80439075172197,
		["key-square"] = 108847209577743,
		keyboard = 78021479821645,
		["keyboard-music"] = 96603074688320,
		["keyboard-off"] = 74463086557782,
		lamp = 106149598999550,
		["lamp-ceiling"] = 107373474068506,
		["lamp-desk"] = 119091300882668,
		["lamp-floor"] = 118721404002286,
		["lamp-wall-down"] = 131117332018010,
		["lamp-wall-up"] = 111944147622055,
		["land-plot"] = 117262165674351,
		landmark = 79297358121552,
		languages = 99917326264912,
		laptop = 88630921256285,
		["laptop-minimal"] = 91902636411470,
		["laptop-minimal-check"] = 98083699649871,
		lasso = 136407965747211,
		["lasso-select"] = 140206314736013,
		laugh = 88041268215527,
		layers = 92401939426051,
		["layers-2"] = 71032875043708,
		["layout-dashboard"] = 109242208940047,
		["layout-grid"] = 80776002921415,
		["layout-list"] = 114901096944423,
		["layout-panel-left"] = 114060619125104,
		["layout-panel-top"] = 140600115620376,
		["layout-template"] = 129513311046670,
		leaf = 114141473154636,
		["leafy-green"] = 75869853521394,
		lectern = 132546168528484,
		["letter-text"] = 127411184020577,
		library = 83641291044674,
		["library-big"] = 70943181021648,
		["life-buoy"] = 88251596523708,
		ligature = 108611580430117,
		lightbulb = 84480692719292,
		["lightbulb-off"] = 107872451939373,
		["line-squiggle"] = 109026309416970,
		link = 73034596791310,
		["link-2"] = 133396582932673,
		["link-2-off"] = 121617377271978,
		linkedin = 140464241694936,
		list = 114094290740453,
		["list-check"] = 127870753168379,
		["list-checks"] = 86457557777962,
		["list-collapse"] = 82013284474006,
		["list-end"] = 137196003577993,
		["list-filter"] = 93463268962238,
		["list-filter-plus"] = 82054172755080,
		["list-minus"] = 109578084629712,
		["list-music"] = 129462394886041,
		["list-ordered"] = 90091028350622,
		["list-plus"] = 132897130887667,
		["list-restart"] = 131578648989528,
		["list-start"] = 139157484305448,
		["list-todo"] = 80421543478674,
		["list-tree"] = 117981368838761,
		["list-video"] = 109079200359344,
		["list-x"] = 79967305528275,
		loader = 93092440305180,
		["loader-circle"] = 83085220798016,
		["loader-pinwheel"] = 80619164634690,
		locate = 76100135911825,
		["locate-fixed"] = 90537535083303,
		["locate-off"] = 130114126626523,
		lock = 71897067930472,
		["lock-keyhole"] = 82932539629673,
		["lock-keyhole-open"] = 126670774179963,
		["lock-open"] = 87192818819520,
		["log-in"] = 104921246880407,
		["log-out"] = 121452889215065,
		logs = 116413304493431,
		lollipop = 92370242563303,
		luggage = 109817666982832,
		magnet = 106378767543648,
		mail = 107247149114562,
		["mail-check"] = 102299214572170,
		["mail-minus"] = 137507529682313,
		["mail-open"] = 79957216174404,
		["mail-plus"] = 97392054041921,
		["mail-question-mark"] = 132294296415348,
		["mail-search"] = 132121654925757,
		["mail-warning"] = 85952461449135,
		["mail-x"] = 132599640757010,
		mailbox = 121433709442295,
		mails = 109802610456892,
		map = 108279805507438,
		["map-minus"] = 133117854348106,
		["map-pin"] = 125589857044225,
		["map-pin-check"] = 73433657551837,
		["map-pin-check-inside"] = 102543459974284,
		["map-pin-house"] = 128212288031307,
		["map-pin-minus"] = 120843698769560,
		["map-pin-minus-inside"] = 118797191517231,
		["map-pin-off"] = 83652562771070,
		["map-pin-pen"] = 102101538402375,
		["map-pin-plus"] = 90799053974278,
		["map-pin-plus-inside"] = 131853510003248,
		["map-pin-x"] = 129671310772849,
		["map-pin-x-inside"] = 90842207454692,
		["map-pinned"] = 113144984652101,
		["map-plus"] = 115814246160273,
		mars = 120237837691441,
		["mars-stroke"] = 78837613304628,
		martini = 131037926665327,
		maximize = 98630565368634,
		["maximize-2"] = 108777312690515,
		medal = 112779948066117,
		megaphone = 104747300280187,
		["megaphone-off"] = 77333538129191,
		meh = 95295284819943,
		["memory-stick"] = 136984029152121,
		menu = 88105946054940,
		merge = 101733452883797,
		["message-circle"] = 103253555420242,
		["message-circle-code"] = 96382573068905,
		["message-circle-dashed"] = 88932788490732,
		["message-circle-heart"] = 126027602940494,
		["message-circle-more"] = 101045229209246,
		["message-circle-off"] = 98784452586047,
		["message-circle-plus"] = 88173371208090,
		["message-circle-question-mark"] = 72740176528871,
		["message-circle-reply"] = 85158719896232,
		["message-circle-warning"] = 92512156177738,
		["message-circle-x"] = 138168651420422,
		["message-square"] = 101115671378532,
		["message-square-code"] = 87110566156463,
		["message-square-dashed"] = 114772668488726,
		["message-square-diff"] = 132647384859535,
		["message-square-dot"] = 95702767009418,
		["message-square-heart"] = 71034790619774,
		["message-square-lock"] = 138911497616369,
		["message-square-more"] = 76114133337761,
		["message-square-off"] = 72445971887595,
		["message-square-plus"] = 84876490293543,
		["message-square-quote"] = 101124360921783,
		["message-square-reply"] = 99682905593886,
		["message-square-share"] = 111163696139836,
		["message-square-text"] = 91402725252953,
		["message-square-warning"] = 133546627536577,
		["message-square-x"] = 91869532020383,
		["messages-square"] = 109110355978624,
		mic = 103948785438713,
		["mic-off"] = 79381540622986,
		["mic-vocal"] = 92319189653574,
		microchip = 114426363692876,
		microscope = 103981634776023,
		microwave = 75423014603555,
		milestone = 84696060292016,
		milk = 107378004547607,
		["milk-off"] = 81017198212200,
		minimize = 132292418800172,
		["minimize-2"] = 115725194133672,
		minus = 120931250449806,
		monitor = 73331152826648,
		["monitor-check"] = 108437497698621,
		["monitor-cog"] = 125290620584522,
		["monitor-dot"] = 86826823806038,
		["monitor-down"] = 80104156010991,
		["monitor-off"] = 107107538808355,
		["monitor-pause"] = 115791072190872,
		["monitor-play"] = 128624177550179,
		["monitor-smartphone"] = 124682793139873,
		["monitor-speaker"] = 105110083118826,
		["monitor-stop"] = 101211853475552,
		["monitor-up"] = 116088712099154,
		["monitor-x"] = 133534745521587,
		moon = 77588825794567,
		["moon-star"] = 98988085004726,
		mountain = 80263482644790,
		["mountain-snow"] = 104191181305826,
		mouse = 107043064551659,
		["mouse-off"] = 116655697625016,
		["mouse-pointer"] = 115752319794521,
		["mouse-pointer-2"] = 109904293129960,
		["mouse-pointer-ban"] = 137539892774993,
		["mouse-pointer-click"] = 107709798577185,
		move = 133600479817246,
		["move-3d"] = 81125830831808,
		["move-diagonal"] = 125202386581344,
		["move-diagonal-2"] = 81239271655220,
		["move-down"] = 125006021670342,
		["move-down-left"] = 76073036666591,
		["move-down-right"] = 129792477029045,
		["move-horizontal"] = 93208311061400,
		["move-left"] = 112800860992157,
		["move-right"] = 82428819089555,
		["move-up"] = 71652407503735,
		["move-up-left"] = 119494062849748,
		["move-up-right"] = 90419076834904,
		["move-vertical"] = 70761579193717,
		music = 93139938100228,
		["music-2"] = 113187037257153,
		["music-3"] = 81349478842651,
		["music-4"] = 96972456280656,
		navigation = 90646250576973,
		["navigation-2"] = 134503816311328,
		["navigation-2-off"] = 131174321328073,
		["navigation-off"] = 108454330041507,
		network = 126418990233987,
		newspaper = 135902869972441,
		nfc = 131962316674237,
		["non-binary"] = 105709493665133,
		notebook = 129243301519710,
		["notebook-pen"] = 91292009218546,
		["notebook-tabs"] = 123657464898215,
		["notebook-text"] = 133642544036180,
		["notepad-text"] = 92434105164050,
		["notepad-text-dashed"] = 136002331761132,
		nut = 81712991871726,
		["nut-off"] = 96078624970734,
		octagon = 134475998551461,
		["octagon-alert"] = 95722117767051,
		["octagon-minus"] = 115829204734243,
		["octagon-pause"] = 91912739903056,
		["octagon-x"] = 117018306251145,
		omega = 91642142247281,
		option = 109155681659629,
		orbit = 74587349912272,
		origami = 77425924575822,
		package = 132935702099654,
		["package-2"] = 91942377485714,
		["package-check"] = 101219557585600,
		["package-minus"] = 100080161784047,
		["package-open"] = 86330655620431,
		["package-plus"] = 83558395457935,
		["package-search"] = 94733344459732,
		["package-x"] = 131230547740708,
		["paint-bucket"] = 136313372531199,
		["paint-roller"] = 134288427758523,
		paintbrush = 131259265232881,
		["paintbrush-vertical"] = 102069363134766,
		palette = 72590019059979,
		panda = 94307958462865,
		["panel-bottom"] = 137958171526644,
		["panel-bottom-close"] = 129839176758045,
		["panel-bottom-dashed"] = 70933718377231,
		["panel-bottom-open"] = 121992330356041,
		["panel-left"] = 113565000264024,
		["panel-left-close"] = 74390600046658,
		["panel-left-dashed"] = 72672900085409,
		["panel-left-open"] = 83412022647633,
		["panel-right"] = 84244938232059,
		["panel-right-close"] = 110482031701194,
		["panel-right-dashed"] = 90286202042323,
		["panel-right-open"] = 97178553892975,
		["panel-top"] = 73398031615308,
		["panel-top-close"] = 96198752262708,
		["panel-top-dashed"] = 110503999562022,
		["panel-top-open"] = 97204124781562,
		["panels-left-bottom"] = 103748432439667,
		["panels-right-bottom"] = 126632243488487,
		["panels-top-left"] = 110293983641300,
		paperclip = 85348713089672,
		parentheses = 132664978899134,
		["parking-meter"] = 137810887120829,
		["party-popper"] = 109041559217985,
		pause = 103515787468348,
		["paw-print"] = 92297066485556,
		["pc-case"] = 128937361383812,
		pen = 116061195824555,
		["pen-line"] = 74845359608302,
		["pen-off"] = 87844360625113,
		["pen-tool"] = 133366920150012,
		pencil = 138696307419367,
		["pencil-line"] = 110410329363278,
		["pencil-off"] = 137726198263006,
		["pencil-ruler"] = 84544564987704,
		pentagon = 83842838413405,
		percent = 122952027760305,
		["person-standing"] = 88108597062307,
		["philippine-peso"] = 137021984302903,
		phone = 98258227445115,
		["phone-call"] = 110549742231723,
		["phone-forwarded"] = 101851668578549,
		["phone-incoming"] = 110075904144850,
		["phone-missed"] = 76822282444954,
		["phone-off"] = 96027672862323,
		["phone-outgoing"] = 136094637639849,
		pi = 76240757098861,
		piano = 99707908396210,
		pickaxe = 75482513098960,
		["picture-in-picture"] = 89952035422534,
		["picture-in-picture-2"] = 111681849788255,
		["piggy-bank"] = 90884658423229,
		pilcrow = 70649688801421,
		["pilcrow-left"] = 78150190347601,
		["pilcrow-right"] = 77497763828757,
		pill = 116144362117466,
		["pill-bottle"] = 135805261557990,
		pin = 91435057862637,
		["pin-off"] = 86227962812956,
		pipette = 71094894064846,
		pizza = 95650659741106,
		plane = 137398243053043,
		["plane-landing"] = 104010936460941,
		["plane-takeoff"] = 95605407118637,
		play = 80104466227462,
		plug = 127012265988191,
		["plug-2"] = 75875872308134,
		["plug-zap"] = 101683967511440,
		plus = 118563428285930,
		pocket = 113239264323778,
		["pocket-knife"] = 103757792000836,
		podcast = 96567592813667,
		pointer = 103954952458474,
		["pointer-off"] = 77566412863428,
		popcorn = 124139605746210,
		popsicle = 102234286085590,
		["pound-sterling"] = 126999093165604,
		power = 139821907770093,
		["power-off"] = 91025506233520,
		presentation = 126156401836303,
		printer = 138626675452013,
		["printer-check"] = 75685462628514,
		projector = 82137422954163,
		proportions = 95735787905869,
		puzzle = 94036333231756,
		pyramid = 134832369326112,
		["qr-code"] = 115947204757344,
		quote = 102055887623346,
		rabbit = 131189288131840,
		radar = 77840020129555,
		radiation = 100120053411692,
		radical = 83794585544135,
		radio = 96448232078753,
		["radio-receiver"] = 115849531523249,
		["radio-tower"] = 123806688762520,
		radius = 121971099119676,
		["rail-symbol"] = 114970540339018,
		rainbow = 93078612490453,
		rat = 79141000137786,
		ratio = 74750864366592,
		receipt = 76330670769012,
		["receipt-cent"] = 131615440184048,
		["receipt-euro"] = 70850947232799,
		["receipt-indian-rupee"] = 84786980270142,
		["receipt-japanese-yen"] = 82207509366200,
		["receipt-pound-sterling"] = 71719348386314,
		["receipt-russian-ruble"] = 81492439455331,
		["receipt-swiss-franc"] = 79810601551246,
		["receipt-text"] = 88438942017408,
		["receipt-turkish-lira"] = 86570860820726,
		["rectangle-circle"] = 85507321361461,
		["rectangle-ellipsis"] = 127439030387481,
		["rectangle-goggles"] = 118679920384510,
		["rectangle-horizontal"] = 71430723037696,
		["rectangle-vertical"] = 72311863384941,
		recycle = 113191864541329,
		redo = 121875341327093,
		["redo-2"] = 138576248818175,
		["redo-dot"] = 117514482954867,
		["refresh-ccw"] = 86267075959666,
		["refresh-ccw-dot"] = 119023527726959,
		["refresh-cw"] = 76845925482586,
		["refresh-cw-off"] = 129981583943775,
		refrigerator = 86690334895832,
		regex = 79467153526782,
		["remove-formatting"] = 100639728039833,
		["repeat"] = 140407645345286,
		["repeat-1"] = 138579844223208,
		["repeat-2"] = 81045504832502,
		replace = 90341483418707,
		["replace-all"] = 76323102138169,
		reply = 138678897436694,
		["reply-all"] = 118380589053924,
		rewind = 124642191767611,
		ribbon = 79206292377631,
		rocket = 79846157539863,
		["rocking-chair"] = 135381220274271,
		["roller-coaster"] = 135317411701728,
		["rotate-3d"] = 136846515530149,
		["rotate-ccw"] = 103593823592882,
		["rotate-ccw-key"] = 72108307437441,
		["rotate-ccw-square"] = 102805428127392,
		["rotate-cw"] = 92926614772014,
		["rotate-cw-square"] = 94393061569190,
		route = 90844221445155,
		["route-off"] = 85315637775689,
		router = 130572058656931,
		["rows-2"] = 140376315766404,
		["rows-3"] = 70922215029935,
		["rows-4"] = 82310713996487,
		rss = 74657652878902,
		ruler = 81932543667472,
		["ruler-dimension-line"] = 116926583536145,
		["russian-ruble"] = 108882947390227,
		sailboat = 138278085859398,
		salad = 97083943538056,
		sandwich = 84512118570250,
		satellite = 90379425147438,
		["satellite-dish"] = 139162594956306,
		["saudi-riyal"] = 111230712493826,
		save = 126786081818943,
		["save-all"] = 132114356737462,
		["save-off"] = 103052152978546,
		scale = 119160471592362,
		["scale-3d"] = 93309101177595,
		scaling = 72422884764012,
		scan = 85082632913446,
		["scan-barcode"] = 71220109533744,
		["scan-eye"] = 97734789454128,
		["scan-face"] = 112627054869699,
		["scan-heart"] = 126892182652292,
		["scan-line"] = 125356770699594,
		["scan-qr-code"] = 129609805395670,
		["scan-search"] = 123647342231468,
		["scan-text"] = 82686374141174,
		school = 82511976287252,
		scissors = 73848300538397,
		["scissors-line-dashed"] = 102508082248814,
		["screen-share"] = 106412780353220,
		["screen-share-off"] = 101801998485496,
		scroll = 125776467998184,
		["scroll-text"] = 86918746287564,
		search = 125618569555993,
		["search-check"] = 102448639481709,
		["search-code"] = 107490113587580,
		["search-slash"] = 140195845290995,
		["search-x"] = 76625315572908,
		section = 132412965594548,
		send = 120131238507529,
		["send-horizontal"] = 127567207232610,
		["send-to-back"] = 105100147812939,
		["separator-horizontal"] = 136326354982755,
		["separator-vertical"] = 81032704114272,
		server = 72203285684743,
		["server-cog"] = 80743099902491,
		["server-crash"] = 104218894040999,
		["server-off"] = 95557390125060,
		settings = 101463883805422,
		["settings-2"] = 75339943202126,
		shapes = 94522066975471,
		share = 117401968838172,
		["share-2"] = 128552309636290,
		sheet = 124970301577850,
		shell = 126582315829979,
		shield = 84528813312016,
		["shield-alert"] = 92505396627173,
		["shield-ban"] = 102215491431686,
		["shield-check"] = 83449656859552,
		["shield-ellipsis"] = 93186850567552,
		["shield-half"] = 127055700945681,
		["shield-minus"] = 130374791120900,
		["shield-off"] = 132566117165802,
		["shield-plus"] = 83455402777739,
		["shield-question-mark"] = 128418825650056,
		["shield-user"] = 99618574383264,
		["shield-x"] = 89958978888777,
		ship = 119708468740563,
		["ship-wheel"] = 100264434901423,
		shirt = 100263550622526,
		["shopping-bag"] = 128835919419658,
		["shopping-basket"] = 139164114183615,
		["shopping-cart"] = 74658309187754,
		shovel = 93002580942748,
		["shower-head"] = 73619400343212,
		shredder = 138895317439043,
		shrimp = 116646646308539,
		shrink = 88836419137438,
		shrub = 76988369043032,
		shuffle = 119271040819486,
		sigma = 95577381168467,
		signal = 86317434523846,
		["signal-high"] = 71259263664875,
		["signal-low"] = 131288244120038,
		["signal-medium"] = 100328562267364,
		["signal-zero"] = 129038651813632,
		signature = 109457267964186,
		signpost = 72013144690387,
		["signpost-big"] = 101768854635202,
		siren = 135315463281920,
		["skip-back"] = 100366953633482,
		["skip-forward"] = 96350165788710,
		skull = 89401908547230,
		slack = 103734185902703,
		slash = 80289381134111,
		slice = 110909868827850,
		["sliders-horizontal"] = 104021219611587,
		["sliders-vertical"] = 105544572196049,
		smartphone = 109476896891915,
		["smartphone-charging"] = 94398441643045,
		["smartphone-nfc"] = 108057157032168,
		smile = 72681486741811,
		["smile-plus"] = 74596726382029,
		snail = 112699295253268,
		snowflake = 82505048791925,
		["soap-dispenser-droplet"] = 117335418112713,
		sofa = 80126963498533,
		soup = 104459318914683,
		space = 124217116768896,
		spade = 76967916150583,
		sparkle = 126477294768200,
		sparkles = 130602425201313,
		speaker = 138304808385322,
		speech = 137983960166079,
		["spell-check"] = 78243940332032,
		["spell-check-2"] = 95385653254823,
		spline = 128106773633629,
		["spline-pointer"] = 123280676328314,
		split = 112314002585584,
		spool = 109278157412120,
		spotlight = 87670272614404,
		["spray-can"] = 121630219787799,
		sprout = 116761478445060,
		square = 96489726265199,
		["square-activity"] = 140333051781567,
		["square-arrow-down"] = 107014673922005,
		["square-arrow-down-left"] = 124277460165719,
		["square-arrow-down-right"] = 73561771563744,
		["square-arrow-left"] = 140645828577303,
		["square-arrow-out-down-left"] = 89110471358870,
		["square-arrow-out-down-right"] = 79224964686159,
		["square-arrow-out-up-left"] = 139915836525364,
		["square-arrow-out-up-right"] = 75394510228384,
		["square-arrow-right"] = 137883327825941,
		["square-arrow-up"] = 86704051916529,
		["square-arrow-up-left"] = 72035481166850,
		["square-arrow-up-right"] = 103199082180609,
		["square-asterisk"] = 91331591548413,
		["square-bottom-dashed-scissors"] = 72833822818441,
		["square-chart-gantt"] = 118014434980199,
		["square-check"] = 131281718379727,
		["square-check-big"] = 93336092924352,
		["square-chevron-down"] = 131902770547285,
		["square-chevron-left"] = 127087352857648,
		["square-chevron-right"] = 83652669185775,
		["square-chevron-up"] = 72583133755831,
		["square-code"] = 124986136764997,
		["square-dashed"] = 79183888005672,
		["square-dashed-bottom"] = 89157701577789,
		["square-dashed-bottom-code"] = 116292194698799,
		["square-dashed-kanban"] = 121007350604616,
		["square-dashed-mouse-pointer"] = 130924289391684,
		["square-dashed-top-solid"] = 124416825207572,
		["square-divide"] = 137218625315282,
		["square-dot"] = 117976103587060,
		["square-equal"] = 121507447179718,
		["square-function"] = 86203774968018,
		["square-kanban"] = 93286950307565,
		["square-library"] = 117062543132766,
		["square-m"] = 115722178058159,
		["square-menu"] = 81614384000771,
		["square-minus"] = 71839009603427,
		["square-mouse-pointer"] = 93614884809738,
		["square-parking"] = 129799277887252,
		["square-parking-off"] = 73561529934834,
		["square-pause"] = 126984552711307,
		["square-pen"] = 94523918453624,
		["square-percent"] = 127625721826020,
		["square-pi"] = 110661345713027,
		["square-pilcrow"] = 79387020279550,
		["square-play"] = 109792454183012,
		["square-plus"] = 73228825720276,
		["square-power"] = 110236577492349,
		["square-radical"] = 138382976817926,
		["square-round-corner"] = 117707560364355,
		["square-scissors"] = 75179246281400,
		["square-sigma"] = 131506090287142,
		["square-slash"] = 112196704068674,
		["square-split-horizontal"] = 97627785389902,
		["square-split-vertical"] = 106959144758418,
		["square-square"] = 80835095859324,
		["square-stack"] = 124304690179249,
		["square-star"] = 115056433115255,
		["square-stop"] = 111768891575856,
		["square-terminal"] = 93337999108432,
		["square-user"] = 72248743154708,
		["square-user-round"] = 135580858593151,
		["square-x"] = 107073482662073,
		["squares-exclude"] = 73691835285197,
		["squares-intersect"] = 96924928301087,
		["squares-subtract"] = 87554296790348,
		["squares-unite"] = 122198623051662,
		squircle = 82987060321691,
		["squircle-dashed"] = 118443285499033,
		squirrel = 73560557505029,
		stamp = 121319474186232,
		star = 127746172798481,
		["star-half"] = 131968454447228,
		["star-off"] = 72177495447859,
		["step-back"] = 85492554496339,
		["step-forward"] = 113928948415823,
		stethoscope = 105982582717298,
		sticker = 127276314334483,
		["sticky-note"] = 112097020099499,
		store = 133824185120097,
		["stretch-horizontal"] = 132144609663362,
		["stretch-vertical"] = 75386274307446,
		strikethrough = 83947301832572,
		subscript = 113391516050262,
		sun = 79901529465096,
		["sun-dim"] = 104619182730276,
		["sun-medium"] = 91618371923097,
		["sun-moon"] = 79929011380037,
		["sun-snow"] = 137414435824708,
		sunrise = 135585238325032,
		sunset = 73712698016360,
		superscript = 72669097231454,
		["swatch-book"] = 128454451162104,
		["swiss-franc"] = 136694453759982,
		["switch-camera"] = 140606464585502,
		sword = 75020726675544,
		swords = 89815227241465,
		syringe = 78733573607159,
		table = 86743029152675,
		["table-2"] = 124462232337013,
		["table-cells-merge"] = 103787916007071,
		["table-cells-split"] = 137584996978518,
		["table-columns-split"] = 112532547114237,
		["table-of-contents"] = 123289010637455,
		["table-properties"] = 106533508299112,
		["table-rows-split"] = 80913015124376,
		tablet = 98236546892857,
		["tablet-smartphone"] = 82512006965851,
		tablets = 118977326005264,
		tag = 103234399652910,
		tags = 102666304482309,
		["tally-1"] = 110936672654832,
		["tally-2"] = 94187147342756,
		["tally-3"] = 124913781937253,
		["tally-4"] = 92590022818947,
		["tally-5"] = 138114201809681,
		tangent = 115243287449073,
		target = 81035867308138,
		telescope = 111810481539512,
		tent = 135834669198083,
		["tent-tree"] = 78356729712249,
		terminal = 73413798937791,
		["test-tube"] = 108565640789121,
		["test-tube-diagonal"] = 111814426284329,
		["test-tubes"] = 84207634752507,
		text = 92542971051973,
		["text-cursor"] = 71303185547080,
		["text-cursor-input"] = 81578218115202,
		["text-quote"] = 103419429142075,
		["text-search"] = 119231709110976,
		["text-select"] = 107531686199786,
		theater = 83268813741529,
		thermometer = 105535887519165,
		["thermometer-snowflake"] = 129660993200918,
		["thermometer-sun"] = 72570194548829,
		["thumbs-down"] = 105602592815443,
		["thumbs-up"] = 72411375022432,
		ticket = 104336783939037,
		["ticket-check"] = 125662376066034,
		["ticket-minus"] = 125106761208017,
		["ticket-percent"] = 73387393631130,
		["ticket-plus"] = 91987299109025,
		["ticket-slash"] = 88947231854573,
		["ticket-x"] = 120285559163949,
		tickets = 128293616470608,
		["tickets-plane"] = 110636990485048,
		timer = 96119720980390,
		["timer-off"] = 73592886882763,
		["timer-reset"] = 115263131999748,
		["toggle-left"] = 126278872210073,
		["toggle-right"] = 135316241551499,
		toilet = 82858381666593,
		["tool-case"] = 133216548079593,
		tornado = 119132390241284,
		torus = 135140424211153,
		touchpad = 111708702894486,
		["touchpad-off"] = 111996914034893,
		["tower-control"] = 132285132951711,
		["toy-brick"] = 91649902772315,
		tractor = 97620732372191,
		["traffic-cone"] = 139621281679882,
		["train-front"] = 98677382842804,
		["train-front-tunnel"] = 114866528676443,
		["train-track"] = 120194201330757,
		["tram-front"] = 91307750164226,
		transgender = 111481765827654,
		trash = 116863849368916,
		["trash-2"] = 79564839810840,
		["tree-deciduous"] = 131205325166458,
		["tree-palm"] = 128164120447244,
		["tree-pine"] = 90774792597002,
		trees = 98571299046731,
		trello = 107898356259657,
		["trending-down"] = 117917602459815,
		["trending-up"] = 116886197130999,
		["trending-up-down"] = 103717610858616,
		triangle = 107100599170044,
		["triangle-alert"] = 76712741040235,
		["triangle-dashed"] = 84136951328014,
		["triangle-right"] = 97661263578338,
		trophy = 99468111768746,
		truck = 102380610139245,
		["truck-electric"] = 107501288276081,
		["turkish-lira"] = 98366519784263,
		turntable = 129425246442560,
		turtle = 124788802294981,
		tv = 91976706623107,
		["tv-minimal"] = 102675516773869,
		["tv-minimal-play"] = 133814752541561,
		twitch = 78418686039425,
		type = 123010942632689,
		["type-outline"] = 75596975306451,
		umbrella = 130176200284323,
		["umbrella-off"] = 123696654720209,
		underline = 86005310176484,
		undo = 98677000788509,
		["undo-2"] = 123288184651876,
		["undo-dot"] = 97048183118444,
		["unfold-horizontal"] = 102321820508665,
		["unfold-vertical"] = 110395906345252,
		ungroup = 116761886838866,
		university = 105398737245802,
		unlink = 114774779025598,
		["unlink-2"] = 84980216310960,
		unplug = 71213047838603,
		upload = 84448595764921,
		usb = 122244624865802,
		user = 81899856845503,
		["user-check"] = 124183127537182,
		["user-cog"] = 132530394308182,
		["user-lock"] = 102304427888373,
		["user-minus"] = 139212780407738,
		["user-pen"] = 109063575712204,
		["user-plus"] = 73169931625061,
		["user-round"] = 122472562648438,
		["user-round-check"] = 116820685971606,
		["user-round-cog"] = 81932262543896,
		["user-round-minus"] = 131104410574220,
		["user-round-pen"] = 88582957358214,
		["user-round-plus"] = 72756692986447,
		["user-round-search"] = 121920726195803,
		["user-round-x"] = 133496165281802,
		["user-search"] = 91526614931270,
		["user-star"] = 104674549336879,
		["user-x"] = 83017534068566,
		users = 109023655602096,
		["users-round"] = 73720692207232,
		utensils = 92328553872866,
		["utensils-crossed"] = 115379488607669,
		["utility-pole"] = 78544397723455,
		variable = 108495567404232,
		vault = 125730392773824,
		["vector-square"] = 120085753224630,
		vegan = 133693714976186,
		["venetian-mask"] = 73997918289433,
		venus = 77091339518872,
		["venus-and-mars"] = 85333806376716,
		vibrate = 94421703759873,
		["vibrate-off"] = 104055297186916,
		video = 120899025417114,
		["video-off"] = 98571437579498,
		videotape = 110595652490996,
		view = 96170375252355,
		voicemail = 129863571214632,
		volleyball = 79983513397509,
		volume = 136944486138432,
		["volume-1"] = 76450166585050,
		["volume-2"] = 127590428470553,
		["volume-off"] = 76437794585400,
		["volume-x"] = 102557100794756,
		vote = 111127508049086,
		wallet = 82693664006746,
		["wallet-cards"] = 131093307699863,
		["wallet-minimal"] = 104760648200766,
		wallpaper = 127531571966115,
		wand = 100247093544676,
		["wand-sparkles"] = 109636225248973,
		warehouse = 117043792208242,
		["washing-machine"] = 124299191442908,
		watch = 96632122742030,
		waves = 132537108109414,
		["waves-ladder"] = 130770635115623,
		waypoints = 89579429286632,
		webcam = 99543028331067,
		webhook = 127494549649286,
		["webhook-off"] = 94143246779298,
		weight = 70452176653194,
		wheat = 72827060603331,
		["wheat-off"] = 133950070398243,
		["whole-word"] = 83053413552620,
		wifi = 101360393607039,
		["wifi-cog"] = 86268760919032,
		["wifi-high"] = 139565602232260,
		["wifi-low"] = 129432377919005,
		["wifi-off"] = 128431848377922,
		["wifi-pen"] = 109435800293522,
		["wifi-sync"] = 134593311559828,
		["wifi-zero"] = 132143289837251,
		wind = 73952787381292,
		["wind-arrow-down"] = 107113727390188,
		workflow = 125401528378697,
		worm = 110566866003503,
		["wrap-text"] = 118921109568806,
		wrench = 108764185264619,
		x = 73070135088117,
		youtube = 100529433894693,
		zap = 99546940565021,
		["zap-off"] = 112636243101847,
		["zoom-in"] = 132256802524814,
		["zoom-out"] = 109610457179810,
		["beer-off"] = 138037951949066,
		["beer"] = 120586510698080,
		["bottle-wine"] = 93707442058849,
		["cannabis"] = 130136923421319,
		["chart-network"] = 116749958806877,
		["cigarrete-off"] = 85361164732665,
		["cigarette"] = 78543658965377,
		["indian-rupee"] = 139912038918762,
		["twitter"] = 83698772731875,
		["wine-off"] = 128440413658301,
		["wine"] = 73532622126175,
	},
	Phosphor = {
		acorn = 88209830316286,
		["address-book"] = 94320181064170,
		["address-book-tabs"] = 84869097264231,
		["air-traffic-control"] = 72704899475052,
		airplane = 93322151243119,
		["airplane-in-flight"] = 95410643348526,
		["airplane-landing"] = 98942604790689,
		["airplane-takeoff"] = 123805221722965,
		["airplane-taxiing"] = 131545563406563,
		["airplane-tilt"] = 77048576449038,
		airplay = 88143005841768,
		alarm = 138348294075104,
		alien = 87878012114485,
		["align-bottom"] = 87526618029643,
		["align-bottom-simple"] = 103031165025111,
		["align-center-horizontal"] = 79197609750374,
		["align-center-horizontal-simple"] = 108318012439475,
		["align-center-vertical"] = 95243470722502,
		["align-center-vertical-simple"] = 89426058687594,
		["align-left"] = 72291531513978,
		["align-left-simple"] = 96531238734625,
		["align-right"] = 99270710622771,
		["align-right-simple"] = 130770655082986,
		["align-top"] = 116854137820255,
		["align-top-simple"] = 80817768506920,
		["amazon-logo"] = 88541802202431,
		ambulance = 91892199257387,
		anchor = 86984238573582,
		["anchor-simple"] = 135388594681410,
		["android-logo"] = 121057086660996,
		angle = 90419965178590,
		["angular-logo"] = 129924216483697,
		aperture = 135411448427891,
		["app-store-logo"] = 70720618974854,
		["app-window"] = 98506878608859,
		["apple-logo"] = 105968783522354,
		["apple-podcasts-logo"] = 71638644943675,
		["approximate-equals"] = 71374391466328,
		archive = 83483023400957,
		armchair = 108547284938294,
		["arrow-arc-left"] = 128762206784795,
		["arrow-arc-right"] = 109778419808621,
		["arrow-bend-double-up-left"] = 125818151396210,
		["arrow-bend-double-up-right"] = 131671967992846,
		["arrow-bend-down-left"] = 135024782824991,
		["arrow-bend-down-right"] = 111193312367121,
		["arrow-bend-left-down"] = 92405897709056,
		["arrow-bend-left-up"] = 95777410925098,
		["arrow-bend-right-down"] = 120274786515517,
		["arrow-bend-right-up"] = 78739988704665,
		["arrow-bend-up-left"] = 88373030658937,
		["arrow-bend-up-right"] = 113111768292360,
		["arrow-circle-down"] = 70995820162929,
		["arrow-circle-down-left"] = 138096351146552,
		["arrow-circle-down-right"] = 83517171251816,
		["arrow-circle-left"] = 126893209727097,
		["arrow-circle-right"] = 107550983811996,
		["arrow-circle-up"] = 139837697340017,
		["arrow-circle-up-left"] = 96717549901172,
		["arrow-circle-up-right"] = 120081604304864,
		["arrow-clockwise"] = 139449381897769,
		["arrow-counter-clockwise"] = 136601197066720,
		["arrow-down"] = 106445735755555,
		["arrow-down-left"] = 95553916366293,
		["arrow-down-right"] = 75052604906347,
		["arrow-elbow-down-left"] = 140427460013236,
		["arrow-elbow-down-right"] = 76718088486430,
		["arrow-elbow-left"] = 76122255483964,
		["arrow-elbow-left-down"] = 124767890354389,
		["arrow-elbow-left-up"] = 96854370800230,
		["arrow-elbow-right"] = 116876393401869,
		["arrow-elbow-right-down"] = 84691326786257,
		["arrow-elbow-right-up"] = 130910392549063,
		["arrow-elbow-up-left"] = 100572402587562,
		["arrow-elbow-up-right"] = 112287532492427,
		["arrow-fat-down"] = 129414727528617,
		["arrow-fat-left"] = 98900650666809,
		["arrow-fat-line-down"] = 128577955012998,
		["arrow-fat-line-left"] = 86686770448432,
		["arrow-fat-line-right"] = 82501893212936,
		["arrow-fat-line-up"] = 89212680687457,
		["arrow-fat-lines-down"] = 113454322219927,
		["arrow-fat-lines-left"] = 116888798206950,
		["arrow-fat-lines-right"] = 101928681409074,
		["arrow-fat-lines-up"] = 92190390282112,
		["arrow-fat-right"] = 129364890603921,
		["arrow-fat-up"] = 101267795929055,
		["arrow-left"] = 126748662324095,
		["arrow-line-down"] = 122161529640366,
		["arrow-line-down-left"] = 82026002090048,
		["arrow-line-down-right"] = 92426383783299,
		["arrow-line-left"] = 115025326887844,
		["arrow-line-right"] = 88493449469027,
		["arrow-line-up"] = 76905347953052,
		["arrow-line-up-left"] = 104102319708171,
		["arrow-line-up-right"] = 87033772406405,
		["arrow-right"] = 98611387555192,
		["arrow-square-down"] = 104582941691501,
		["arrow-square-down-left"] = 75081254723635,
		["arrow-square-down-right"] = 110110551619531,
		["arrow-square-in"] = 112284912423703,
		["arrow-square-left"] = 98769395778912,
		["arrow-square-out"] = 135198379537698,
		["arrow-square-right"] = 106648186897881,
		["arrow-square-up"] = 78055332731387,
		["arrow-square-up-left"] = 102461562522501,
		["arrow-square-up-right"] = 112441391077390,
		["arrow-u-down-left"] = 84258070644279,
		["arrow-u-down-right"] = 133601972491757,
		["arrow-u-left-down"] = 76708992052526,
		["arrow-u-left-up"] = 86169428608258,
		["arrow-u-right-down"] = 71792237244384,
		["arrow-u-right-up"] = 129497849997680,
		["arrow-u-up-left"] = 102705822341229,
		["arrow-u-up-right"] = 114654960630774,
		["arrow-up"] = 128674428451012,
		["arrow-up-left"] = 119739464740897,
		["arrow-up-right"] = 81161838097371,
		["arrows-clockwise"] = 129935538130298,
		["arrows-counter-clockwise"] = 94123789126726,
		["arrows-down-up"] = 81013474709573,
		["arrows-horizontal"] = 76490546093442,
		["arrows-in"] = 97676269323869,
		["arrows-in-cardinal"] = 104427979581668,
		["arrows-in-line-horizontal"] = 125127642143208,
		["arrows-in-line-vertical"] = 135488362353069,
		["arrows-in-simple"] = 71369483904076,
		["arrows-left-right"] = 99974216775572,
		["arrows-merge"] = 113684462066536,
		["arrows-out"] = 71928156638112,
		["arrows-out-cardinal"] = 133594871885244,
		["arrows-out-line-horizontal"] = 121470352602422,
		["arrows-out-line-vertical"] = 122993314357666,
		["arrows-out-simple"] = 136094260152404,
		["arrows-split"] = 131587679218639,
		["arrows-vertical"] = 78158200761798,
		article = 135876201649553,
		["article-medium"] = 129421320914369,
		["article-ny-times"] = 75414307282073,
		asclepius = 110745768489845,
		asterisk = 100693110143505,
		["asterisk-simple"] = 134482916004823,
		at = 122852587149258,
		atom = 96700100025639,
		avocado = 104099617839857,
		axe = 74693365380007,
		baby = 106875910484846,
		["baby-carriage"] = 83176533290266,
		backpack = 138827986740845,
		backspace = 99076187454973,
		bag = 80297534390590,
		["bag-simple"] = 92184500538422,
		balloon = 80692425085159,
		bandaids = 107236088597742,
		bank = 119725347148035,
		barbell = 96186547634576,
		barcode = 128074367623785,
		barn = 104432680458380,
		barricade = 122055184094871,
		baseball = 83536871813157,
		["baseball-cap"] = 109544198728564,
		["baseball-helmet"] = 87814293044701,
		basket = 119063685457146,
		basketball = 87138677174269,
		bathtub = 106937176368145,
		["battery-charging"] = 140176149312420,
		["battery-charging-vertical"] = 80876461515081,
		["battery-empty"] = 124192042561549,
		["battery-full"] = 101627978693724,
		["battery-high"] = 87155046745258,
		["battery-low"] = 94377426126203,
		["battery-medium"] = 97131430683357,
		["battery-plus"] = 112255397310435,
		["battery-plus-vertical"] = 90994066971185,
		["battery-vertical-empty"] = 72336095156866,
		["battery-vertical-full"] = 131193109780257,
		["battery-vertical-high"] = 110199653021935,
		["battery-vertical-low"] = 122716190870383,
		["battery-vertical-medium"] = 84996155872758,
		["battery-warning"] = 118962940134789,
		["battery-warning-vertical"] = 106135137534102,
		["beach-ball"] = 72295157373313,
		beanie = 76343671209874,
		bed = 90413457159381,
		["behance-logo"] = 111556163583523,
		bell = 137985203475964,
		["bell-ringing"] = 99253040968016,
		["bell-simple"] = 108959111951343,
		["bell-simple-ringing"] = 104839962539416,
		["bell-simple-slash"] = 119539602032274,
		["bell-simple-z"] = 128515183841753,
		["bell-slash"] = 116917061396411,
		["bell-z"] = 86451956236531,
		belt = 115202366120931,
		["bezier-curve"] = 89911556451696,
		bicycle = 123979668454525,
		binary = 86498607433207,
		binoculars = 131212493374485,
		biohazard = 96710184905884,
		bird = 100804986340289,
		blueprint = 137015284531200,
		bluetooth = 75479614597281,
		["bluetooth-connected"] = 121315328127247,
		["bluetooth-slash"] = 124663108014345,
		["bluetooth-x"] = 84257375296635,
		boat = 127433943594993,
		bomb = 93762281618988,
		bone = 123377230688754,
		book = 115225514002248,
		["book-bookmark"] = 128598480245892,
		["book-open"] = 72099203301802,
		["book-open-text"] = 125805028550862,
		["book-open-user"] = 111163908354477,
		bookmark = 120509946782876,
		["bookmark-simple"] = 87201602455215,
		bookmarks = 88804535545581,
		["bookmarks-simple"] = 123464371062349,
		books = 135432126465762,
		boot = 100978307201368,
		boules = 102417776170396,
		["bounding-box"] = 118935182455276,
		["bowl-food"] = 134425065260307,
		["bowl-steam"] = 111922797542893,
		["bowling-ball"] = 125080049107781,
		["box-arrow-down"] = 87414847861287,
		["box-arrow-up"] = 92371754351383,
		["boxing-glove"] = 116982087137435,
		["brackets-angle"] = 100055372581495,
		["brackets-curly"] = 88652694767795,
		["brackets-round"] = 74848880354818,
		["brackets-square"] = 140253684437402,
		brain = 129710564888470,
		brandy = 119920828759114,
		bread = 97445628892460,
		bridge = 138845834943787,
		briefcase = 102173951124513,
		["briefcase-metal"] = 136436547552497,
		broadcast = 88617414241211,
		broom = 110284461441456,
		browser = 136019447985766,
		browsers = 73596555999380,
		bug = 77887315092020,
		["bug-beetle"] = 72155117508367,
		["bug-droid"] = 94452627747574,
		building = 100743112898255,
		["building-apartment"] = 134520034009900,
		["building-office"] = 85321609367476,
		buildings = 87016085129346,
		bulldozer = 75530561357543,
		bus = 109072589149653,
		butterfly = 88426841993327,
		["cable-car"] = 91193349723134,
		cactus = 140097896299596,
		cake = 137688164544602,
		calculator = 105258692230625,
		calendar = 118106312194385,
		["calendar-blank"] = 121492537081306,
		["calendar-check"] = 92102899769057,
		["calendar-dot"] = 106377863118708,
		["calendar-dots"] = 95095830621207,
		["calendar-heart"] = 121760107839329,
		["calendar-minus"] = 93175780755463,
		["calendar-plus"] = 111301765840979,
		["calendar-slash"] = 127399895402646,
		["calendar-star"] = 76683553740280,
		["calendar-x"] = 107998733234064,
		["call-bell"] = 123056407031695,
		camera = 93059764237560,
		["camera-plus"] = 140066100640459,
		["camera-rotate"] = 88808101351182,
		["camera-slash"] = 89715203623900,
		campfire = 132364044012568,
		car = 120906726125135,
		["car-battery"] = 127532227434693,
		["car-profile"] = 132397883411638,
		["car-simple"] = 99958983373254,
		cardholder = 76281274889578,
		cards = 110489853561584,
		["cards-three"] = 77829810754128,
		["caret-circle-double-down"] = 90555849535551,
		["caret-circle-double-left"] = 122697019999879,
		["caret-circle-double-right"] = 71274848908004,
		["caret-circle-double-up"] = 117450125842263,
		["caret-circle-down"] = 139900015303280,
		["caret-circle-left"] = 129812116702899,
		["caret-circle-right"] = 97903361778744,
		["caret-circle-up"] = 131868448540960,
		["caret-circle-up-down"] = 105167568592121,
		["caret-double-down"] = 88063288049645,
		["caret-double-left"] = 131080359024057,
		["caret-double-right"] = 86420301114170,
		["caret-double-up"] = 80209479807294,
		["caret-down"] = 124875244347045,
		["caret-left"] = 94710763961380,
		["caret-line-down"] = 94256737672448,
		["caret-line-left"] = 85116589304737,
		["caret-line-right"] = 117429694029384,
		["caret-line-up"] = 126346139999882,
		["caret-right"] = 112397363255991,
		["caret-up"] = 113012106733109,
		["caret-up-down"] = 136323760606001,
		carrot = 118533729109430,
		["cash-register"] = 102521027841764,
		["cassette-tape"] = 100037599035271,
		["castle-turret"] = 86750369480285,
		cat = 140116470500498,
		["cell-signal-full"] = 119068718941554,
		["cell-signal-high"] = 126061262604062,
		["cell-signal-low"] = 70762279860242,
		["cell-signal-medium"] = 70432289129069,
		["cell-signal-none"] = 122056369708851,
		["cell-signal-slash"] = 107918758392449,
		["cell-signal-x"] = 88723703296051,
		["cell-tower"] = 99457499860783,
		certificate = 136891268098615,
		chair = 123113424818184,
		chalkboard = 82157638275103,
		["chalkboard-simple"] = 102845149281117,
		["chalkboard-teacher"] = 71136598260383,
		["charging-station"] = 84712280330353,
		["chart-bar"] = 106306837878697,
		["chart-bar-horizontal"] = 133601931830444,
		["chart-donut"] = 89241049473219,
		["chart-line"] = 105457184098440,
		["chart-line-down"] = 97052202315147,
		["chart-line-up"] = 92948648392018,
		["chart-pie"] = 126996477009592,
		["chart-pie-slice"] = 98189015760457,
		["chart-polar"] = 122934553897534,
		["chart-scatter"] = 110224374449343,
		chat = 117355899424846,
		["chat-centered"] = 103540874665090,
		["chat-centered-dots"] = 126397282359094,
		["chat-centered-slash"] = 91590447197850,
		["chat-centered-text"] = 100408294827213,
		["chat-circle"] = 132110555496627,
		["chat-circle-dots"] = 97772445652206,
		["chat-circle-slash"] = 104745588168024,
		["chat-circle-text"] = 70823468274381,
		["chat-dots"] = 127235179261640,
		["chat-slash"] = 109181455101649,
		["chat-teardrop"] = 134521720304856,
		["chat-teardrop-dots"] = 83985665187313,
		["chat-teardrop-slash"] = 122331600596268,
		["chat-teardrop-text"] = 126345787700415,
		["chat-text"] = 94230264064230,
		chats = 91200408288499,
		["chats-circle"] = 124473250122452,
		["chats-teardrop"] = 119391793518594,
		check = 126864552069475,
		["check-circle"] = 127374295972113,
		["check-fat"] = 128359116873239,
		["check-square"] = 80902013226765,
		["check-square-offset"] = 72735306854190,
		checkerboard = 135712362184223,
		checks = 126296319183440,
		cheers = 114866565475795,
		cheese = 88324543389432,
		["chef-hat"] = 110309997765112,
		cherries = 84794515951090,
		church = 116145871852131,
		circle = 89301667668845,
		["circle-dashed"] = 122892996053007,
		["circle-half"] = 112956989110619,
		["circle-half-tilt"] = 78509622032341,
		["circle-notch"] = 94880447263868,
		["circles-four"] = 96949290984284,
		["circles-three"] = 110853783083744,
		["circles-three-plus"] = 92971594418100,
		circuitry = 77160533417093,
		city = 127943365555993,
		clipboard = 72167000888299,
		["clipboard-text"] = 81771636686964,
		clock = 83244374007852,
		["clock-afternoon"] = 118388094190052,
		["clock-clockwise"] = 114863166381319,
		["clock-countdown"] = 82759521944622,
		["clock-counter-clockwise"] = 80228143786800,
		["clock-user"] = 104999739529123,
		["closed-captioning"] = 86370262613156,
		cloud = 83712237687369,
		["cloud-arrow-down"] = 73735569440551,
		["cloud-arrow-up"] = 79953529457810,
		["cloud-check"] = 108081611802183,
		["cloud-fog"] = 95644491961828,
		["cloud-lightning"] = 94366915563220,
		["cloud-moon"] = 120245614334490,
		["cloud-rain"] = 93038513843817,
		["cloud-slash"] = 79969864034060,
		["cloud-snow"] = 104356768653573,
		["cloud-sun"] = 134800593419467,
		["cloud-warning"] = 102885287273934,
		["cloud-x"] = 126216923517106,
		clover = 110584043597159,
		club = 90112755751684,
		["coat-hanger"] = 78285458148946,
		["coda-logo"] = 92001445143328,
		code = 92441968158365,
		["code-block"] = 83231150045009,
		["code-simple"] = 109066437233543,
		["codepen-logo"] = 132919228229031,
		["codesandbox-logo"] = 129893296271248,
		coffee = 79227439635551,
		["coffee-bean"] = 116971555083125,
		coin = 123260102822362,
		["coin-vertical"] = 125130798048793,
		coins = 99378956409603,
		columns = 72033622039831,
		["columns-plus-left"] = 71165113067173,
		["columns-plus-right"] = 116352317441725,
		command = 120839692818705,
		compass = 80633104273386,
		["compass-rose"] = 131533858476549,
		["compass-tool"] = 74686627338076,
		["computer-tower"] = 90213894101572,
		confetti = 135942530029778,
		["contactless-payment"] = 116734005932336,
		control = 75405769407240,
		cookie = 117013885072439,
		["cooking-pot"] = 78019986403469,
		copy = 107128868068985,
		["copy-simple"] = 79671951638537,
		copyleft = 90723245657727,
		copyright = 113937902619498,
		["corners-in"] = 122518132660697,
		["corners-out"] = 78376491811076,
		couch = 107381212042268,
		["court-basketball"] = 105318979435104,
		cow = 110885267724553,
		["cowboy-hat"] = 98456980812785,
		cpu = 138217801369321,
		crane = 76768308716388,
		["crane-tower"] = 108746044380876,
		["credit-card"] = 99917308285366,
		cricket = 137220354774604,
		crop = 118884508909661,
		cross = 75797283854257,
		crosshair = 89358795252134,
		["crosshair-simple"] = 126969751619587,
		crown = 87187837175761,
		["crown-cross"] = 118930002119974,
		["crown-simple"] = 140010819020511,
		cube = 126514831757890,
		["cube-focus"] = 71513033839228,
		["cube-transparent"] = 115412367099257,
		["currency-btc"] = 76704229675977,
		["currency-circle-dollar"] = 125649656969393,
		["currency-cny"] = 72753448054667,
		["currency-dollar"] = 130857032609626,
		["currency-dollar-simple"] = 126977197317199,
		["currency-eth"] = 96606306476268,
		["currency-eur"] = 84456227182599,
		["currency-gbp"] = 70900957729775,
		["currency-inr"] = 87927447150535,
		["currency-jpy"] = 76165807924607,
		["currency-krw"] = 76723494322142,
		["currency-kzt"] = 104994253643750,
		["currency-ngn"] = 115163708950249,
		["currency-rub"] = 72062746235291,
		cursor = 95858752212702,
		["cursor-click"] = 126370365848250,
		["cursor-text"] = 125387141636820,
		cylinder = 84228963405257,
		database = 136047017843549,
		desk = 111108250145086,
		desktop = 90436560004648,
		["desktop-tower"] = 93822576233734,
		detective = 123418954397370,
		["dev-to-logo"] = 105188789867112,
		["device-mobile"] = 81593866732948,
		["device-mobile-camera"] = 118342286565296,
		["device-mobile-slash"] = 85090748645853,
		["device-mobile-speaker"] = 85087423260141,
		["device-rotate"] = 123014595101314,
		["device-tablet"] = 129937558797998,
		["device-tablet-camera"] = 80086001573417,
		["device-tablet-speaker"] = 77796437723093,
		devices = 77629794755312,
		diamond = 72521081801762,
		["diamonds-four"] = 87269510117827,
		["dice-five"] = 112085830466629,
		["dice-four"] = 74443250563487,
		["dice-one"] = 92448158953112,
		["dice-six"] = 81439442919065,
		["dice-three"] = 74776351459672,
		["dice-two"] = 95171089104179,
		disc = 128657548184487,
		["disco-ball"] = 138680968259184,
		["discord-logo"] = 101359832205037,
		divide = 101661910485811,
		dna = 138843745136890,
		dog = 83095744810621,
		door = 91402217910542,
		["door-open"] = 120614246198798,
		dot = 71862360860232,
		["dot-outline"] = 90558785707733,
		["dots-nine"] = 100321760762474,
		["dots-six"] = 131225682087189,
		["dots-six-vertical"] = 102525992426861,
		["dots-three"] = 136757429381352,
		["dots-three-circle"] = 140479555356056,
		["dots-three-circle-vertical"] = 105647303641819,
		["dots-three-outline"] = 130221850236302,
		["dots-three-outline-vertical"] = 80480671564358,
		["dots-three-vertical"] = 96889175280828,
		download = 82440080278534,
		["download-simple"] = 71279448913977,
		dress = 126106746020135,
		dresser = 110745130586943,
		["dribbble-logo"] = 103013956545101,
		drone = 81934725308750,
		drop = 133528650674379,
		["drop-half"] = 126410273479708,
		["drop-half-bottom"] = 103369089924773,
		["drop-simple"] = 105048946667399,
		["drop-slash"] = 105855245139082,
		["dropbox-logo"] = 111722097973972,
		ear = 86421301761594,
		["ear-slash"] = 95670456923251,
		egg = 95348856598177,
		["egg-crack"] = 119542043365441,
		eject = 105803669819056,
		["eject-simple"] = 77299395620133,
		elevator = 109094852473658,
		empty = 131546341387201,
		engine = 92779726203673,
		envelope = 107308763949089,
		["envelope-open"] = 132307229429967,
		["envelope-simple"] = 109175070181481,
		["envelope-simple-open"] = 129868360171093,
		equalizer = 138951072719747,
		equals = 93148623413869,
		eraser = 134672297536829,
		["escalator-down"] = 121632146068560,
		["escalator-up"] = 139985595584774,
		exam = 74899661541605,
		["exclamation-mark"] = 103261573477096,
		exclude = 139563916819491,
		["exclude-square"] = 79776436857215,
		export = 105443137552114,
		eye = 74506877814071,
		["eye-closed"] = 102149954897532,
		["eye-slash"] = 81778410546741,
		eyedropper = 121918348931842,
		["eyedropper-sample"] = 78726967841611,
		eyeglasses = 91902838840553,
		eyes = 121637497349101,
		["face-mask"] = 78717980828161,
		["facebook-logo"] = 105720719541631,
		factory = 134236058110000,
		faders = 110253937952620,
		["faders-horizontal"] = 91530112034607,
		["fallout-shelter"] = 110811799562964,
		fan = 73979710797518,
		farm = 85596917637977,
		["fast-forward"] = 90843506074622,
		["fast-forward-circle"] = 73892024595514,
		feather = 85946797623124,
		["fediverse-logo"] = 71461228821443,
		["figma-logo"] = 71333058965305,
		file = 90054850365088,
		["file-archive"] = 97097209086068,
		["file-arrow-down"] = 109948746014173,
		["file-arrow-up"] = 111989091343931,
		["file-audio"] = 80948721987518,
		["file-c"] = 71889750785444,
		["file-c-sharp"] = 81155307326569,
		["file-cloud"] = 104504681560506,
		["file-code"] = 136638608265331,
		["file-cpp"] = 113598497408276,
		["file-css"] = 99890697372668,
		["file-csv"] = 103792248908281,
		["file-dashed"] = 129912251963406,
		["file-doc"] = 125067274925310,
		["file-html"] = 74857038241805,
		["file-image"] = 117881259782758,
		["file-ini"] = 121166009227124,
		["file-jpg"] = 86255173276205,
		["file-js"] = 133395976982665,
		["file-jsx"] = 85148145776873,
		["file-lock"] = 70662591854807,
		["file-magnifying-glass"] = 115216697732597,
		["file-md"] = 133648881949258,
		["file-minus"] = 112374011506577,
		["file-pdf"] = 85472368017617,
		["file-plus"] = 122501308106877,
		["file-png"] = 82799555718265,
		["file-ppt"] = 130583289788230,
		["file-py"] = 125461180833828,
		["file-rs"] = 92218252308572,
		["file-sql"] = 113408241127916,
		["file-svg"] = 130340098820670,
		["file-text"] = 139342612556007,
		["file-ts"] = 131009714286165,
		["file-tsx"] = 125803492632867,
		["file-txt"] = 95324657454176,
		["file-video"] = 129640995419412,
		["file-vue"] = 109937731743162,
		["file-x"] = 102604982543581,
		["file-xls"] = 100672635810578,
		["file-zip"] = 89429916828875,
		files = 97812781805780,
		["film-reel"] = 119797046647611,
		["film-script"] = 75551134044931,
		["film-slate"] = 133864713655972,
		["film-strip"] = 128725350399813,
		fingerprint = 136133637635958,
		["fingerprint-simple"] = 84280665358267,
		["finn-the-human"] = 83225004831754,
		fire = 113375182425183,
		["fire-extinguisher"] = 80155370237251,
		["fire-simple"] = 81478002154585,
		["fire-truck"] = 116294139346959,
		["first-aid"] = 128774162681164,
		["first-aid-kit"] = 99977400880916,
		fish = 100694675276078,
		["fish-simple"] = 78914980902614,
		flag = 103891476705425,
		["flag-banner"] = 140112800142571,
		["flag-banner-fold"] = 116820468971956,
		["flag-checkered"] = 84675101518545,
		["flag-pennant"] = 130468071138500,
		flame = 121830872314026,
		flashlight = 121335674654290,
		flask = 94801343408198,
		["flip-horizontal"] = 88829981042884,
		["flip-vertical"] = 115348662698810,
		["floppy-disk"] = 102542936481550,
		["floppy-disk-back"] = 96927874547118,
		["flow-arrow"] = 111099236982709,
		flower = 79957287261597,
		["flower-lotus"] = 131467358329239,
		["flower-tulip"] = 91852433742041,
		["flying-saucer"] = 90701348420911,
		folder = 87978563139137,
		["folder-dashed"] = 123254784255048,
		["folder-lock"] = 110617860005203,
		["folder-minus"] = 94161133961829,
		["folder-open"] = 123251633159031,
		["folder-plus"] = 85445430502400,
		["folder-simple"] = 99644148759002,
		["folder-simple-dashed"] = 76345891927756,
		["folder-simple-lock"] = 79545802187120,
		["folder-simple-minus"] = 89694243889732,
		["folder-simple-plus"] = 106366166368103,
		["folder-simple-star"] = 120896831793442,
		["folder-simple-user"] = 81579780741345,
		["folder-star"] = 77400913089242,
		["folder-user"] = 122234041479539,
		folders = 138450011908973,
		football = 125989013652143,
		["football-helmet"] = 116107758270908,
		footprints = 133748703318858,
		["fork-knife"] = 128921388389159,
		["four-k"] = 113553303871626,
		["frame-corners"] = 78499318599381,
		["framer-logo"] = 129928769505538,
		["function"] = 72290049723138,
		funnel = 117499742003586,
		["funnel-simple"] = 102945490858473,
		["funnel-simple-x"] = 101232337183669,
		["funnel-x"] = 76409812113981,
		["game-controller"] = 113852436010267,
		garage = 92890250412154,
		["gas-can"] = 119533327472514,
		["gas-pump"] = 131442864726533,
		gauge = 103854863153418,
		gavel = 103802490955983,
		gear = 84790757237036,
		["gear-fine"] = 84508635522572,
		["gear-six"] = 72764670903206,
		["gender-female"] = 92970107616291,
		["gender-male"] = 108179313706076,
		["gender-neuter"] = 82309923183174,
		["gender-nonbinary"] = 95589673155616,
		["gender-transgender"] = 129145319705275,
		ghost = 76472647881256,
		gif = 76935837204804,
		gift = 73278692819080,
		["git-branch"] = 121524287737508,
		["git-commit"] = 103238871917899,
		["git-diff"] = 140471903258685,
		["git-fork"] = 97841875236881,
		["git-merge"] = 127770916228810,
		["git-pull-request"] = 134959516484047,
		["github-logo"] = 129788421705202,
		["gitlab-logo"] = 133313258576534,
		["gitlab-logo-simple"] = 79729842952547,
		globe = 124879844674621,
		["globe-hemisphere-east"] = 84773141776546,
		["globe-hemisphere-west"] = 86019565181934,
		["globe-simple"] = 134199087123210,
		["globe-simple-x"] = 92248840321628,
		["globe-stand"] = 88377660108372,
		["globe-x"] = 139095388465846,
		goggles = 83696611334473,
		golf = 76527956770996,
		["goodreads-logo"] = 117145800554348,
		["google-cardboard-logo"] = 78145280747014,
		["google-chrome-logo"] = 97127828457770,
		["google-drive-logo"] = 139457489942678,
		["google-logo"] = 112841175161389,
		["google-photos-logo"] = 127762589146875,
		["google-play-logo"] = 83235307087351,
		["google-podcasts-logo"] = 95998091982059,
		gps = 131864755413263,
		["gps-fix"] = 87388853217321,
		["gps-slash"] = 78854989499867,
		gradient = 89856751733127,
		["graduation-cap"] = 137246922516598,
		grains = 110252101256852,
		["grains-slash"] = 121010948525558,
		graph = 112723294951323,
		["graphics-card"] = 113537639618923,
		["greater-than"] = 111043122245477,
		["greater-than-or-equal"] = 96475281882070,
		["grid-four"] = 139194981584465,
		["grid-nine"] = 87061881809489,
		guitar = 136250731148664,
		["hair-dryer"] = 127858897418531,
		hamburger = 102738573401970,
		hammer = 91406410693095,
		hand = 124045743034283,
		["hand-arrow-down"] = 109615937154938,
		["hand-arrow-up"] = 136418072167134,
		["hand-coins"] = 135840597182334,
		["hand-deposit"] = 73631191328962,
		["hand-eye"] = 124272826600490,
		["hand-fist"] = 75648250067459,
		["hand-grabbing"] = 124816343858879,
		["hand-heart"] = 119612637823625,
		["hand-palm"] = 99213260343140,
		["hand-peace"] = 80492630895736,
		["hand-pointing"] = 109109407063217,
		["hand-soap"] = 89982870426608,
		["hand-swipe-left"] = 122796165936811,
		["hand-swipe-right"] = 79596979929392,
		["hand-tap"] = 114442308284285,
		["hand-waving"] = 91576504576404,
		["hand-withdraw"] = 96167652644923,
		handbag = 92074197446228,
		["handbag-simple"] = 132181921147982,
		["hands-clapping"] = 110080404491422,
		["hands-praying"] = 111410181418689,
		handshake = 89282846592852,
		["hard-drive"] = 98786827613505,
		["hard-drives"] = 120667963163832,
		["hard-hat"] = 80292496321576,
		hash = 102963103567776,
		["hash-straight"] = 92226450155377,
		["head-circuit"] = 112946423783361,
		headlights = 120325631714095,
		headphones = 110672519255076,
		headset = 139190358303716,
		heart = 71281978271535,
		["heart-break"] = 130032825297773,
		["heart-half"] = 113259232555318,
		["heart-straight"] = 92339286343384,
		["heart-straight-break"] = 130137310160143,
		heartbeat = 119635461951583,
		hexagon = 87407421176362,
		["high-definition"] = 99492524910037,
		["high-heel"] = 72924345615988,
		highlighter = 126761198772523,
		["highlighter-circle"] = 91810522770507,
		hockey = 98820967673259,
		hoodie = 120210645079807,
		horse = 99675851872854,
		hospital = 128461560457202,
		hourglass = 93747654631278,
		["hourglass-high"] = 107119225776109,
		["hourglass-low"] = 70823423749889,
		["hourglass-medium"] = 94297831814782,
		["hourglass-simple"] = 120263603820935,
		["hourglass-simple-high"] = 98761391586543,
		["hourglass-simple-low"] = 129050096005658,
		["hourglass-simple-medium"] = 121912251809896,
		house = 111457521328478,
		["house-line"] = 102902895437641,
		["house-simple"] = 89113531946605,
		hurricane = 114897393528450,
		["ice-cream"] = 131566415033849,
		["identification-badge"] = 106846129174722,
		["identification-card"] = 133082757704475,
		image = 84434130351196,
		["image-broken"] = 94025855579967,
		["image-square"] = 77968215646324,
		images = 100387157212670,
		["images-square"] = 95278278732880,
		infinity = 85946378512258,
		info = 75867060539283,
		["instagram-logo"] = 99337127359760,
		intersect = 96965575489290,
		["intersect-square"] = 88007449156256,
		["intersect-three"] = 128824305623670,
		intersection = 83385673191229,
		invoice = 79792604336311,
		island = 90824988406847,
		jar = 125775809217876,
		["jar-label"] = 96696733547612,
		jeep = 91937219824169,
		joystick = 131967292206895,
		kanban = 116294792835984,
		key = 80003242986347,
		["key-return"] = 134451131472087,
		keyboard = 132944807916275,
		keyhole = 74082075206448,
		knife = 92312379007553,
		ladder = 140684651977991,
		["ladder-simple"] = 78489087079148,
		lamp = 98111214634134,
		["lamp-pendant"] = 91811100647348,
		laptop = 89457727492032,
		lasso = 133266677368142,
		["lastfm-logo"] = 77329904156417,
		layout = 81248496410499,
		leaf = 91618375313756,
		lectern = 74595555162999,
		lego = 125429417559348,
		["lego-smiley"] = 101304778678913,
		["less-than"] = 126737574765707,
		["less-than-or-equal"] = 72795802093989,
		["letter-circle-h"] = 78457122040007,
		["letter-circle-p"] = 123937059894212,
		["letter-circle-v"] = 127358118261511,
		lifebuoy = 103059101115280,
		lightbulb = 116141358057034,
		["lightbulb-filament"] = 135067639633578,
		lighthouse = 138001441976431,
		lightning = 125915203364439,
		["lightning-a"] = 71322912475460,
		["lightning-slash"] = 107437938527349,
		["line-segment"] = 118650677502329,
		["line-segments"] = 74150003129678,
		["line-vertical"] = 109107152893478,
		link = 108613279334326,
		["link-break"] = 122821581045368,
		["link-simple"] = 79194241698522,
		["link-simple-break"] = 109673057701632,
		["link-simple-horizontal"] = 98730858761814,
		["link-simple-horizontal-break"] = 97543878122388,
		["linkedin-logo"] = 96622538432504,
		["linktree-logo"] = 128433170381432,
		["linux-logo"] = 134567825907894,
		list = 100295894538062,
		["list-bullets"] = 118531313284369,
		["list-checks"] = 115559031149937,
		["list-dashes"] = 124133545307403,
		["list-heart"] = 88477321277472,
		["list-magnifying-glass"] = 134605784469699,
		["list-numbers"] = 81710562264516,
		["list-plus"] = 89628602907233,
		["list-star"] = 104830560518667,
		lock = 88144603292938,
		["lock-key"] = 92318532513909,
		["lock-key-open"] = 96808573998523,
		["lock-laminated"] = 106506451213120,
		["lock-laminated-open"] = 134503555488994,
		["lock-open"] = 84976745345771,
		["lock-simple"] = 83682386305624,
		["lock-simple-open"] = 100324187514556,
		lockers = 76705582674666,
		log = 110234720885694,
		["magic-wand"] = 94532118462857,
		magnet = 92703314009506,
		["magnet-straight"] = 138409132292508,
		["magnifying-glass"] = 83285992249199,
		["magnifying-glass-minus"] = 78791152319046,
		["magnifying-glass-plus"] = 100738510857742,
		mailbox = 114467258808177,
		["map-pin"] = 103468959900549,
		["map-pin-area"] = 139349944439705,
		["map-pin-line"] = 125363208813517,
		["map-pin-plus"] = 95011199103346,
		["map-pin-simple"] = 78054079274008,
		["map-pin-simple-area"] = 110553296531197,
		["map-pin-simple-line"] = 111000614934196,
		["map-trifold"] = 94818781225795,
		["markdown-logo"] = 135824932275066,
		["marker-circle"] = 138172546646861,
		martini = 115951107953584,
		["mask-happy"] = 94713298311209,
		["mask-sad"] = 76685407645313,
		["mastodon-logo"] = 115361890756891,
		["math-operations"] = 92405604268797,
		["matrix-logo"] = 76012988212701,
		medal = 79841096742931,
		["medal-military"] = 139699001854161,
		["medium-logo"] = 120550545931159,
		megaphone = 134701835698923,
		["megaphone-simple"] = 137214228908327,
		["member-of"] = 105463657117703,
		memory = 120424871667238,
		["messenger-logo"] = 95373902950993,
		["meta-logo"] = 75677988423183,
		meteor = 109411014484917,
		metronome = 105409339285867,
		microphone = 81622608797979,
		["microphone-slash"] = 79699319722288,
		["microphone-stage"] = 75139422594283,
		microscope = 123049029351583,
		["microsoft-excel-logo"] = 119313573708470,
		["microsoft-outlook-logo"] = 113176035659047,
		["microsoft-powerpoint-logo"] = 116939087803187,
		["microsoft-teams-logo"] = 101552087446117,
		["microsoft-word-logo"] = 106822962331683,
		minus = 99490214819204,
		["minus-circle"] = 128260491386207,
		["minus-square"] = 93154145212701,
		money = 89642955248098,
		["money-wavy"] = 127417253647463,
		monitor = 118069935071668,
		["monitor-arrow-up"] = 77723146289766,
		["monitor-play"] = 70477046727115,
		moon = 79245136541154,
		["moon-stars"] = 127100347779424,
		moped = 133139949015636,
		["moped-front"] = 135632356369986,
		mosque = 76657962386953,
		motorcycle = 125160661239391,
		mountains = 128241865597195,
		mouse = 83129727192211,
		["mouse-left-click"] = 115056024167617,
		["mouse-middle-click"] = 135234908140403,
		["mouse-right-click"] = 137562079836941,
		["mouse-scroll"] = 77240971572523,
		["mouse-simple"] = 93659156853403,
		["music-note"] = 129764154706150,
		["music-note-simple"] = 130032566251842,
		["music-notes"] = 72704854709358,
		["music-notes-minus"] = 79936091236879,
		["music-notes-plus"] = 92167078570145,
		["music-notes-simple"] = 76491903525817,
		["navigation-arrow"] = 92918561340682,
		needle = 117716715769188,
		network = 135397989347896,
		["network-slash"] = 100958233680462,
		["network-x"] = 115993175661369,
		newspaper = 106398879150665,
		["newspaper-clipping"] = 114189008943050,
		["not-equals"] = 89232369304487,
		["not-member-of"] = 93488925583360,
		["not-subset-of"] = 99990309708404,
		["not-superset-of"] = 111844682486705,
		notches = 109818176117358,
		note = 70943206178286,
		["note-blank"] = 91990048404812,
		["note-pencil"] = 114396900157434,
		notebook = 77887672566251,
		notepad = 93506026247746,
		notification = 139404597918389,
		["notion-logo"] = 133002830786122,
		["nuclear-plant"] = 106298972454255,
		["number-circle-eight"] = 75550533045513,
		["number-circle-five"] = 138184399646019,
		["number-circle-four"] = 131004694646110,
		["number-circle-nine"] = 72655087428856,
		["number-circle-one"] = 103914077716022,
		["number-circle-seven"] = 82083097484192,
		["number-circle-six"] = 137281126998711,
		["number-circle-three"] = 88817392650323,
		["number-circle-two"] = 105120559628506,
		["number-circle-zero"] = 85157180410901,
		["number-eight"] = 120875239244036,
		["number-five"] = 113265987881434,
		["number-four"] = 102109953223930,
		["number-nine"] = 78083465565777,
		["number-one"] = 112581659066811,
		["number-seven"] = 93310432028299,
		["number-six"] = 95070681803527,
		["number-square-eight"] = 91250096257809,
		["number-square-five"] = 73049399021394,
		["number-square-four"] = 77683687946234,
		["number-square-nine"] = 133485593792169,
		["number-square-one"] = 90532996935382,
		["number-square-seven"] = 92665812348525,
		["number-square-six"] = 98592318771979,
		["number-square-three"] = 77834513881854,
		["number-square-two"] = 76712861850858,
		["number-square-zero"] = 138401389741367,
		["number-three"] = 80226129915630,
		["number-two"] = 122625699319249,
		["number-zero"] = 138088557807044,
		numpad = 87531872957205,
		nut = 78907809503519,
		["ny-times-logo"] = 122148006052007,
		octagon = 124719644114511,
		["office-chair"] = 125174160629083,
		onigiri = 132593994604910,
		["open-ai-logo"] = 92173987336264,
		option = 104867867447543,
		orange = 109231597416695,
		["orange-slice"] = 102385958081452,
		oven = 81210893110184,
		package = 74436902521263,
		["paint-brush"] = 90072811220032,
		["paint-brush-broad"] = 136756415229866,
		["paint-brush-household"] = 98883081346038,
		["paint-bucket"] = 139245000576918,
		["paint-roller"] = 97115514542011,
		palette = 127739553593223,
		panorama = 136029009019871,
		pants = 132921257331300,
		["paper-plane"] = 100529055866677,
		["paper-plane-right"] = 115095404337683,
		["paper-plane-tilt"] = 119756938858061,
		paperclip = 127275846346232,
		["paperclip-horizontal"] = 138555632844262,
		parachute = 122288463208790,
		paragraph = 114390434861681,
		parallelogram = 82922798625685,
		park = 110554439684814,
		password = 90585626219308,
		path = 96726681922072,
		["patreon-logo"] = 86776116905034,
		pause = 126568067232079,
		["pause-circle"] = 104536075956328,
		["paw-print"] = 139692634552371,
		["paypal-logo"] = 122226793785987,
		peace = 76226017519441,
		pen = 139663819533778,
		["pen-nib"] = 74012681799668,
		["pen-nib-straight"] = 124930917388311,
		pencil = 104021424470908,
		["pencil-circle"] = 105901738481588,
		["pencil-line"] = 120613992683971,
		["pencil-ruler"] = 114082801201206,
		["pencil-simple"] = 95009771319023,
		["pencil-simple-line"] = 74168614676489,
		["pencil-simple-slash"] = 94426220831117,
		["pencil-slash"] = 73925863961859,
		pentagon = 96726683161213,
		pentagram = 91962638041778,
		pepper = 131041308621874,
		percent = 133633092739004,
		person = 72212877766122,
		["person-arms-spread"] = 91864283638127,
		["person-simple"] = 89873890241795,
		["person-simple-bike"] = 131980093390164,
		["person-simple-circle"] = 113956426317557,
		["person-simple-hike"] = 136737427654229,
		["person-simple-run"] = 94348657678300,
		["person-simple-ski"] = 87005927436260,
		["person-simple-snowboard"] = 139387922642561,
		["person-simple-swim"] = 139063619498448,
		["person-simple-tai-chi"] = 128388851503134,
		["person-simple-throw"] = 79239365030790,
		["person-simple-walk"] = 123957434205685,
		perspective = 120574091387942,
		phone = 133732438248187,
		["phone-call"] = 73995467350576,
		["phone-disconnect"] = 116680467395057,
		["phone-incoming"] = 138583959982351,
		["phone-list"] = 96127747853973,
		["phone-outgoing"] = 139157699417115,
		["phone-pause"] = 81107190448527,
		["phone-plus"] = 110090058971469,
		["phone-slash"] = 82990090138806,
		["phone-transfer"] = 121529062936512,
		["phone-x"] = 86879454946115,
		["phosphor-logo"] = 96909578129492,
		pi = 90171842363350,
		["piano-keys"] = 76621940594974,
		["picnic-table"] = 73453800962240,
		["picture-in-picture"] = 121176470467095,
		["piggy-bank"] = 82618393554972,
		pill = 125564607255237,
		["ping-pong"] = 105949130278548,
		["pint-glass"] = 101381012526476,
		pinwheel = 98600303581007,
		pipe = 89860892880996,
		["pipe-wrench"] = 115138775244246,
		["pix-logo"] = 87151082836519,
		pizza = 108692030831221,
		placeholder = 73345491438311,
		planet = 95301915252597,
		plant = 75369902074132,
		play = 94245024986139,
		["play-circle"] = 125728180407262,
		["play-pause"] = 130400267462324,
		playlist = 130518405099913,
		plug = 126351411134502,
		["plug-charging"] = 135889137025663,
		plugs = 85802993587320,
		["plugs-connected"] = 98298787313908,
		plus = 113800466497594,
		["plus-circle"] = 111306830119558,
		["plus-minus"] = 97662233438890,
		["plus-square"] = 86023163426496,
		["poker-chip"] = 121638184206010,
		["police-car"] = 120014451917703,
		polygon = 123712297806443,
		popcorn = 90479844798314,
		popsicle = 78363824939875,
		["potted-plant"] = 117205627824448,
		power = 103575696671055,
		prescription = 109452483600536,
		presentation = 114759301517629,
		["presentation-chart"] = 113686599160795,
		printer = 110942944314440,
		prohibit = 112163167985109,
		["prohibit-inset"] = 115674365418014,
		["projector-screen"] = 139940650502279,
		["projector-screen-chart"] = 75398874915675,
		pulse = 70913835329047,
		["push-pin"] = 138311379196394,
		["push-pin-simple"] = 106745275414840,
		["push-pin-simple-slash"] = 123968186178909,
		["push-pin-slash"] = 90497402724301,
		["puzzle-piece"] = 117625709450772,
		["qr-code"] = 135688544379087,
		question = 127449414161427,
		["question-mark"] = 118357417000302,
		queue = 78937426842635,
		quotes = 124433271894911,
		rabbit = 93822746867465,
		racquet = 129115578530695,
		radical = 99036958810320,
		radio = 98256893684933,
		["radio-button"] = 70422378025638,
		radioactive = 96113936979251,
		rainbow = 127636572881269,
		["rainbow-cloud"] = 73071501341453,
		ranking = 90876590957204,
		["read-cv-logo"] = 78896481594152,
		receipt = 72404279956065,
		["receipt-x"] = 78990953203468,
		record = 92631679986296,
		rectangle = 128610982660817,
		["rectangle-dashed"] = 122743136958999,
		recycle = 138732247930628,
		["reddit-logo"] = 74815106803101,
		["repeat"] = 76307832410464,
		["repeat-once"] = 120848343518913,
		["replit-logo"] = 132908358650463,
		resize = 114209672587958,
		rewind = 109439187417763,
		["rewind-circle"] = 137325456275194,
		["road-horizon"] = 122999983276405,
		robot = 106054650603479,
		rocket = 91634685965097,
		["rocket-launch"] = 74952232961123,
		rows = 86518771943254,
		["rows-plus-bottom"] = 108147572160009,
		["rows-plus-top"] = 108435329226504,
		rss = 98075485280999,
		["rss-simple"] = 130617693482041,
		rug = 136869142363403,
		ruler = 115986307759152,
		sailboat = 94861464196886,
		scales = 92238191910595,
		scan = 129162738144039,
		["scan-smiley"] = 83143512388902,
		scissors = 77429562362600,
		scooter = 119799698183779,
		screencast = 140198048348335,
		screwdriver = 137631910744983,
		scribble = 128086473055653,
		["scribble-loop"] = 93713279702952,
		scroll = 86103454151982,
		seal = 117052056602349,
		["seal-check"] = 129442563194376,
		["seal-percent"] = 107535525748046,
		["seal-question"] = 113314649810071,
		["seal-warning"] = 76147772870221,
		seat = 105785993343684,
		seatbelt = 83506716814168,
		["security-camera"] = 106079193603726,
		selection = 131171231316944,
		["selection-all"] = 96477607067048,
		["selection-background"] = 131957769926704,
		["selection-foreground"] = 139585927484994,
		["selection-inverse"] = 92816012996069,
		["selection-plus"] = 120812503272500,
		["selection-slash"] = 121576868961586,
		shapes = 89581843239777,
		share = 86431416652683,
		["share-fat"] = 132190300448248,
		["share-network"] = 138525495703016,
		shield = 84054453143321,
		["shield-check"] = 127683234196858,
		["shield-checkered"] = 78049779425685,
		["shield-chevron"] = 129313801935055,
		["shield-plus"] = 109269591698060,
		["shield-slash"] = 114663971686991,
		["shield-star"] = 130021949329387,
		["shield-warning"] = 109020077070840,
		["shipping-container"] = 93394734378070,
		["shirt-folded"] = 131525238442646,
		["shooting-star"] = 123852282095674,
		["shopping-bag"] = 122087198404734,
		["shopping-bag-open"] = 96475800653650,
		["shopping-cart"] = 100719603133675,
		["shopping-cart-simple"] = 87702626298852,
		shovel = 76019667590176,
		shower = 89355718660523,
		shrimp = 104317664955645,
		shuffle = 101724660869786,
		["shuffle-angular"] = 74859786339231,
		["shuffle-simple"] = 109889979842512,
		sidebar = 102208092118769,
		["sidebar-simple"] = 120906518623892,
		sigma = 85632142587400,
		["sign-in"] = 109325945190487,
		["sign-out"] = 98581522820115,
		signature = 126798716874580,
		signpost = 95909719374938,
		["sim-card"] = 100058878452480,
		siren = 100886393442633,
		["sketch-logo"] = 109571015226538,
		["skip-back"] = 89168141910185,
		["skip-back-circle"] = 91382596828133,
		["skip-forward"] = 79338689273343,
		["skip-forward-circle"] = 80346121389265,
		skull = 140451695032556,
		["skype-logo"] = 76053659556861,
		["slack-logo"] = 104094458243374,
		sliders = 81828282218428,
		["sliders-horizontal"] = 89246854832407,
		slideshow = 121798831895858,
		smiley = 100976028724463,
		["smiley-angry"] = 77475426719707,
		["smiley-blank"] = 101559508768659,
		["smiley-meh"] = 115274948847838,
		["smiley-melting"] = 133639002190595,
		["smiley-nervous"] = 100056489730172,
		["smiley-sad"] = 139542055844823,
		["smiley-sticker"] = 80990090699432,
		["smiley-wink"] = 120052956479896,
		["smiley-x-eyes"] = 77880358063616,
		["snapchat-logo"] = 88732887516445,
		sneaker = 82561428659932,
		["sneaker-move"] = 79384285348006,
		snowflake = 139886599010566,
		["soccer-ball"] = 76997637455301,
		sock = 135319612364837,
		["solar-panel"] = 70516023589327,
		["solar-roof"] = 82134195662670,
		["sort-ascending"] = 133947012053519,
		["sort-descending"] = 102823829541471,
		["soundcloud-logo"] = 85938717753003,
		spade = 85568366826336,
		sparkle = 79946008681364,
		["speaker-hifi"] = 73695588646654,
		["speaker-high"] = 99649048625877,
		["speaker-low"] = 88707076355799,
		["speaker-none"] = 110336993051009,
		["speaker-simple-high"] = 127470169274537,
		["speaker-simple-low"] = 102377617584949,
		["speaker-simple-none"] = 95971728542895,
		["speaker-simple-slash"] = 133150923730748,
		["speaker-simple-x"] = 74133903648374,
		["speaker-slash"] = 86319263979579,
		["speaker-x"] = 74859047884046,
		speedometer = 109870719200362,
		sphere = 120624090227512,
		spinner = 139651535189514,
		["spinner-ball"] = 118485187861466,
		["spinner-gap"] = 86958057000711,
		spiral = 135358236451916,
		["split-horizontal"] = 134560003807869,
		["split-vertical"] = 93516930489451,
		["spotify-logo"] = 92417636745332,
		["spray-bottle"] = 107847525581460,
		square = 107824168810810,
		["square-half"] = 106593858256095,
		["square-half-bottom"] = 105437948231991,
		["square-logo"] = 120954265973516,
		["square-split-horizontal"] = 71574814331269,
		["square-split-vertical"] = 77061282910921,
		["squares-four"] = 131704517475738,
		stack = 86470990097058,
		["stack-minus"] = 126874396768436,
		["stack-overflow-logo"] = 128066800656097,
		["stack-plus"] = 128748981685073,
		["stack-simple"] = 129111342351966,
		stairs = 95085206311352,
		stamp = 72586688979269,
		["standard-definition"] = 118453206560855,
		star = 90467498707278,
		["star-and-crescent"] = 98404728724413,
		["star-four"] = 118486883043903,
		["star-half"] = 132645538130217,
		["star-of-david"] = 135009450295572,
		["steam-logo"] = 120600042792283,
		["steering-wheel"] = 115797745665618,
		steps = 132317585899731,
		stethoscope = 71892209034689,
		sticker = 77131202765553,
		stool = 101744563909345,
		stop = 80668785656012,
		["stop-circle"] = 138152721358965,
		storefront = 98839818604446,
		strategy = 73894953966517,
		["stripe-logo"] = 137777407420377,
		student = 87852075419093,
		["subset-of"] = 71950099326896,
		["subset-proper-of"] = 111042842690797,
		subtitles = 105706428785511,
		["subtitles-slash"] = 74097484521314,
		subtract = 71535444451191,
		["subtract-square"] = 119701732267480,
		subway = 133163831788337,
		suitcase = 125501340539802,
		["suitcase-rolling"] = 124177423981836,
		["suitcase-simple"] = 78868553494391,
		sun = 96513638256491,
		["sun-dim"] = 118420009375064,
		["sun-horizon"] = 73333246321851,
		sunglasses = 132577617083362,
		["superset-of"] = 104561915512623,
		["superset-proper-of"] = 82056261785666,
		swap = 103178924898601,
		swatches = 80533905630605,
		["swimming-pool"] = 126199911399061,
		sword = 115114343632183,
		synagogue = 127222969346548,
		syringe = 113193349189243,
		["t-shirt"] = 135410676300565,
		table = 116684925187883,
		tabs = 136680185348913,
		tag = 75717002993927,
		["tag-chevron"] = 73613032803009,
		["tag-simple"] = 117134900690972,
		target = 117001652606238,
		taxi = 121645662258524,
		["tea-bag"] = 101430105635366,
		["telegram-logo"] = 134744732976561,
		television = 126524745315693,
		["television-simple"] = 96995079940288,
		["tennis-ball"] = 112295948565488,
		tent = 79080056753959,
		terminal = 128505693881005,
		["terminal-window"] = 75202501284610,
		["test-tube"] = 90623086074508,
		["text-a-underline"] = 140544737678337,
		["text-aa"] = 83731651321247,
		["text-align-center"] = 103858454363571,
		["text-align-justify"] = 79222706454630,
		["text-align-left"] = 105539904524378,
		["text-align-right"] = 97147718080876,
		["text-b"] = 133286832147458,
		["text-columns"] = 78425055232728,
		["text-h"] = 137248239712137,
		["text-h-five"] = 134622100075399,
		["text-h-four"] = 79575808943827,
		["text-h-one"] = 113376145145802,
		["text-h-six"] = 105705414145509,
		["text-h-three"] = 82373509924639,
		["text-h-two"] = 129136449418132,
		["text-indent"] = 107823972992777,
		["text-italic"] = 91489249846911,
		["text-outdent"] = 72405886512658,
		["text-strikethrough"] = 107481171048156,
		["text-subscript"] = 77082860637490,
		["text-superscript"] = 99892400543836,
		["text-t"] = 110720224544730,
		["text-t-slash"] = 78452949514474,
		["text-underline"] = 87712830653755,
		textbox = 125362034207238,
		thermometer = 92125729122128,
		["thermometer-cold"] = 111366448049411,
		["thermometer-hot"] = 77906920807220,
		["thermometer-simple"] = 95899503769697,
		["threads-logo"] = 99815576078610,
		["three-d"] = 135258736842523,
		["thumbs-down"] = 116401576110364,
		["thumbs-up"] = 118133943796682,
		ticket = 135138344973996,
		["tidal-logo"] = 78899855750017,
		["tiktok-logo"] = 100161454276661,
		tilde = 123658530365421,
		timer = 138810579924450,
		["tip-jar"] = 130291661938503,
		tipi = 96120486330635,
		tire = 84332146919439,
		["toggle-left"] = 134295401966818,
		["toggle-right"] = 87733277142445,
		toilet = 136734657394115,
		["toilet-paper"] = 114303415686211,
		toolbox = 88759582430014,
		tooth = 102490400817526,
		tornado = 73033796703449,
		tote = 132184076570236,
		["tote-simple"] = 109660205486364,
		towel = 87886718483460,
		tractor = 111058622827062,
		trademark = 93885284372080,
		["trademark-registered"] = 96096498156357,
		["traffic-cone"] = 83424547763411,
		["traffic-sign"] = 98524121445865,
		["traffic-signal"] = 139305800942328,
		train = 116210186174473,
		["train-regional"] = 117257200670454,
		["train-simple"] = 94660183531457,
		tram = 74488677644056,
		translate = 80142001457816,
		trash = 106297559451840,
		["trash-simple"] = 134954679883311,
		tray = 72365529384499,
		["tray-arrow-down"] = 80481460677496,
		["tray-arrow-up"] = 110922712683703,
		["treasure-chest"] = 130672898251820,
		tree = 83743014452448,
		["tree-evergreen"] = 137883450024644,
		["tree-palm"] = 102202338927649,
		["tree-structure"] = 102021791152404,
		["tree-view"] = 94685952231942,
		["trend-down"] = 110405823889973,
		["trend-up"] = 118104922670768,
		triangle = 110181128846959,
		["triangle-dashed"] = 84962191573735,
		trolley = 89627655265631,
		["trolley-suitcase"] = 126044611160697,
		trophy = 101460092155493,
		truck = 73322035311724,
		["truck-trailer"] = 102206663158943,
		["tumblr-logo"] = 126544279468729,
		["twitch-logo"] = 116028145217100,
		["twitter-logo"] = 125797674195404,
		umbrella = 78104610769950,
		["umbrella-simple"] = 70562095512103,
		union = 117046002685019,
		unite = 138125302726650,
		["unite-square"] = 83617811272284,
		upload = 89518272494254,
		["upload-simple"] = 101687993864708,
		usb = 129707418186494,
		user = 90293576166452,
		["user-check"] = 109006980084354,
		["user-circle"] = 96498705076569,
		["user-circle-check"] = 85498663582803,
		["user-circle-dashed"] = 90317148329119,
		["user-circle-gear"] = 116402937561560,
		["user-circle-minus"] = 95600017025300,
		["user-circle-plus"] = 112606787880222,
		["user-focus"] = 126895656344952,
		["user-gear"] = 126421029777123,
		["user-list"] = 88157092129722,
		["user-minus"] = 95713978850767,
		["user-plus"] = 123402031588429,
		["user-rectangle"] = 114477283266095,
		["user-sound"] = 114253451742453,
		["user-square"] = 109629714553798,
		["user-switch"] = 102773420321670,
		users = 126634781550642,
		["users-four"] = 90270090509773,
		["users-three"] = 126543946716700,
		van = 91462430960853,
		vault = 70904046517861,
		["vector-three"] = 86707969116540,
		["vector-two"] = 139420153688759,
		vibrate = 85157059364884,
		video = 100842679205145,
		["video-camera"] = 134817621199126,
		["video-camera-slash"] = 84508024323840,
		["video-conference"] = 96854777226668,
		vignette = 139231896364317,
		["vinyl-record"] = 95765239963773,
		["virtual-reality"] = 125305553215156,
		virus = 104339438580587,
		visor = 104940769029693,
		voicemail = 130384081439479,
		volleyball = 77620396198808,
		wall = 84992510999920,
		wallet = 109874199612647,
		warehouse = 134690974065843,
		warning = 88031333881107,
		["warning-circle"] = 77249388941723,
		["warning-diamond"] = 96558949721808,
		["warning-octagon"] = 83833777691288,
		["washing-machine"] = 131313813048052,
		watch = 114770285458251,
		["wave-sawtooth"] = 102324183919729,
		["wave-sine"] = 128389340188386,
		["wave-square"] = 72457670800016,
		["wave-triangle"] = 86258298173269,
		waveform = 99744672327596,
		["waveform-slash"] = 134077402002637,
		waves = 108912116453158,
		webcam = 103581135640608,
		["webcam-slash"] = 82361258959254,
		["webhooks-logo"] = 100867115010021,
		["wechat-logo"] = 110125606521311,
		wheelchair = 96490713680805,
		["whatsapp-logo"] = 124413117001475,
		["wheelchair-motion"] = 122422155190625,
		["wifi-high"] = 111029349564170,
		["wifi-low"] = 76253166144498,
		["wifi-medium"] = 114130224101065,
		["wifi-none"] = 138580744971922,
		["wifi-slash"] = 74527453493051,
		["wifi-x"] = 101647371122947,
		wind = 88394959696635,
		windmill = 120914469275417,
		["windows-logo"] = 118759005613422,
		wrench = 135173363971173,
		x = 92408839668227,
		["x-circle"] = 95761210118619,
		["x-logo"] = 118570625913497,
		["x-square"] = 123056544520399,
		yarn = 83269839688794,
		["yin-yang"] = 134849293746426,
		["youtube-logo"] = 113451767964889,
		champagne = 70850734772088,
		wine = 75302742615329,
		cigarette = 123891004211654,
		["cigarette-slash"] = 109542215112177,
		["gender-intersex"] = 110454996850381,
		["pinterest-logo"] = 132418971488058,
	},
	["Phosphor-Filled"] = {
		["acorn"] = 83252700666770,
		["address-book"] = 94117857840281,
		["address-book-tabs"] = 79902742162713,
		["air-traffic-control"] = 122218102339847,
		["airplane"] = 75192075330156,
		["airplane-in-flight"] = 80897195196562,
		["airplane-landing"] = 104305059157524,
		["airplane-takeoff"] = 85555010744433,
		["airplane-taxiing"] = 125186677611430,
		["airplane-tilt"] = 115507185455241,
		["airplay"] = 112509357191032,
		["alarm"] = 99652673343145,
		["alien"] = 99923056621768,
		["align-bottom"] = 70997597420494,
		["align-bottom-simple"] = 71976326446405,
		["align-center-horizontal"] = 75980595897362,
		["align-center-horizontal-simple"] = 113153240379592,
		["align-center-vertical"] = 113100291601863,
		["align-center-vertical-simple"] = 135961455271094,
		["align-left"] = 108783081465185,
		["align-left-simple"] = 98926749420757,
		["align-right"] = 125377987191478,
		["align-right-simple"] = 90941384762038,
		["align-top"] = 136706866226876,
		["align-top-simple"] = 74859793209067,
		["amazon-logo"] = 121844599391722,
		["ambulance"] = 81396073888156,
		["anchor"] = 131809069461363,
		["anchor-simple"] = 94759911382425,
		["android-logo"] = 75650787755013,
		["angle"] = 115622208060777,
		["angular-logo"] = 96613569712722,
		["aperture"] = 83159998945338,
		["app-store-logo"] = 125376894644811,
		["app-window"] = 126810312694608,
		["apple-logo"] = 137550611950748,
		["apple-podcasts-logo"] = 73029260525445,
		["approximate-equals"] = 75233639069071,
		["archive"] = 77693616147183,
		["armchair"] = 116894591900305,
		["arrow-arc-left"] = 107942551007614,
		["arrow-arc-right"] = 115624622750788,
		["arrow-bend-double-up-left"] = 96416831501109,
		["arrow-bend-double-up-right"] = 115041915960645,
		["arrow-bend-down-left"] = 108339379837860,
		["arrow-bend-down-right"] = 102116127574195,
		["arrow-bend-left-down"] = 115449223551702,
		["arrow-bend-left-up"] = 121588814591197,
		["arrow-bend-right-down"] = 98982591026059,
		["arrow-bend-right-up"] = 102378824711792,
		["arrow-bend-up-left"] = 99419315396672,
		["arrow-bend-up-right"] = 132178101400856,
		["arrow-circle-down"] = 81610411199640,
		["arrow-circle-down-left"] = 112710504584324,
		["arrow-circle-down-right"] = 77043772046879,
		["arrow-circle-left"] = 127968891979516,
		["arrow-circle-right"] = 132641214623976,
		["arrow-circle-up"] = 114823612846925,
		["arrow-circle-up-left"] = 139898206249584,
		["arrow-circle-up-right"] = 84703881513710,
		["arrow-clockwise"] = 104438169025163,
		["arrow-counter-clockwise"] = 135366304848862,
		["arrow-down"] = 112794160140684,
		["arrow-down-left"] = 79851153932288,
		["arrow-down-right"] = 98164036980817,
		["arrow-elbow-down-left"] = 119290121841326,
		["arrow-elbow-down-right"] = 130301571636180,
		["arrow-elbow-left-down"] = 91034469306906,
		["arrow-elbow-left"] = 90447945899786,
		["arrow-elbow-left-up"] = 94872859569123,
		["arrow-elbow-right-down"] = 78355222253118,
		["arrow-elbow-right"] = 100786170053773,
		["arrow-elbow-right-up"] = 85151557187842,
		["arrow-elbow-up-left"] = 124977485502298,
		["arrow-elbow-up-right"] = 129528184571647,
		["arrow-fat-down"] = 80466604305648,
		["arrow-fat-left"] = 79555283917706,
		["arrow-fat-line-down"] = 88437038868444,
		["arrow-fat-line-left"] = 133513173576227,
		["arrow-fat-line-right"] = 85558222749313,
		["arrow-fat-line-up"] = 102315916230896,
		["arrow-fat-lines-down"] = 92573498773854,
		["arrow-fat-lines-left"] = 124943784282367,
		["arrow-fat-lines-right"] = 114390491873168,
		["arrow-fat-lines-up"] = 97825439443227,
		["arrow-fat-right"] = 136427469424249,
		["arrow-fat-up"] = 73715543829256,
		["arrow-left"] = 131896702621811,
		["arrow-line-down"] = 104325234407447,
		["arrow-line-down-left"] = 138849314750445,
		["arrow-line-down-right"] = 121405600864451,
		["arrow-line-left"] = 125260144677751,
		["arrow-line-right"] = 97451507558992,
		["arrow-line-up"] = 101831258313953,
		["arrow-line-up-left"] = 125672864156515,
		["arrow-line-up-right"] = 95141955456849,
		["arrow-right"] = 135938360121263,
		["arrow-square-down"] = 136470411522897,
		["arrow-square-down-left"] = 119882526430739,
		["arrow-square-down-right"] = 72019231637974,
		["arrow-square-in"] = 80868937926361,
		["arrow-square-left"] = 139837647537648,
		["arrow-square-out"] = 99427650427481,
		["arrow-square-right"] = 101830428622851,
		["arrow-square-up"] = 97640671273715,
		["arrow-square-up-left"] = 131393352478290,
		["arrow-square-up-right"] = 101941905195177,
		["arrow-u-down-left"] = 78650391846873,
		["arrow-u-down-right"] = 116025030874826,
		["arrow-u-left-down"] = 130012665069496,
		["arrow-u-left-up"] = 92870258785974,
		["arrow-u-right-down"] = 133677918482339,
		["arrow-u-right-up"] = 125155346266109,
		["arrow-u-up-left"] = 120886875521255,
		["arrow-u-up-right"] = 97887402356396,
		["arrow-up"] = 105658091937721,
		["arrow-up-left"] = 92527804630941,
		["arrow-up-right"] = 108356591225004,
		["arrows-clockwise"] = 137182410717944,
		["arrows-counter-clockwise"] = 89121984085959,
		["arrows-down-up"] = 98197567240243,
		["arrows-horizontal"] = 124327404299939,
		["arrows-in-cardinal"] = 104861946957786,
		["arrows-in"] = 95541174791745,
		["arrows-in-line-horizontal"] = 110878618610074,
		["arrows-in-line-vertical"] = 90954954572356,
		["arrows-in-simple"] = 130773244195965,
		["arrows-left-right"] = 87672035760420,
		["arrows-merge"] = 109508600454624,
		["arrows-out-cardinal"] = 96858411173038,
		["arrows-out"] = 94147786956940,
		["arrows-out-line-horizontal"] = 87385511267217,
		["arrows-out-line-vertical"] = 111922266363475,
		["arrows-out-simple"] = 109706400748630,
		["arrows-split"] = 79839508654933,
		["arrows-vertical"] = 123995608981756,
		["article"] = 137344875430825,
		["article-medium"] = 97953236609642,
		["article-ny-times"] = 88367665439341,
		["asclepius"] = 73351951316537,
		["asterisk"] = 137746657971351,
		["asterisk-simple"] = 135424748505415,
		["at"] = 102709490139366,
		["atom"] = 128692907804953,
		["avocado"] = 119380536755921,
		["axe"] = 135734308950370,
		["baby-carriage"] = 139452813345309,
		["baby"] = 129905851524013,
		["backpack"] = 136588910846855,
		["backspace"] = 82286438234844,
		["bag"] = 116947981086140,
		["bag-simple"] = 95221400237576,
		["balloon"] = 134973333003652,
		["bandaids"] = 119538755975919,
		["bank"] = 98892538950727,
		["barbell"] = 88873697656333,
		["barcode"] = 114344390379317,
		["barn"] = 134089261782732,
		["barricade"] = 117291699477384,
		["baseball-cap"] = 101262994143139,
		["baseball"] = 112131628191307,
		["baseball-helmet"] = 102931068504960,
		["basket"] = 105815576632767,
		["basketball"] = 137842360225831,
		["bathtub"] = 127837260313226,
		["battery-charging"] = 106396543220734,
		["battery-charging-vertical"] = 97620752871910,
		["battery-empty"] = 114050099139706,
		["battery-full"] = 76136881881450,
		["battery-high"] = 139918246641833,
		["battery-low"] = 129338820609568,
		["battery-medium"] = 110614031210242,
		["battery-plus"] = 93265990711567,
		["battery-plus-vertical"] = 100885825932438,
		["battery-vertical-empty"] = 70669706576055,
		["battery-vertical-full"] = 71460872497093,
		["battery-vertical-high"] = 127373518938916,
		["battery-vertical-low"] = 139774255541830,
		["battery-vertical-medium"] = 90417923692011,
		["battery-warning"] = 132632454885162,
		["battery-warning-vertical"] = 91048964888710,
		["beach-ball"] = 99303740435174,
		["beanie"] = 137846638541430,
		["bed"] = 89325496207134,
		["behance-logo"] = 75769404469609,
		["bell"] = 135111447645581,
		["bell-ringing"] = 79195699468202,
		["bell-simple"] = 76229743518696,
		["bell-simple-ringing"] = 115365129017032,
		["bell-simple-slash"] = 115467773647574,
		["bell-simple-z"] = 98597330768239,
		["bell-slash"] = 123640136652131,
		["bell-z"] = 78719575396644,
		["belt"] = 111985859111149,
		["bezier-curve"] = 116685119294175,
		["bicycle"] = 70924638082943,
		["binary"] = 128367729333148,
		["binoculars"] = 125911911871724,
		["biohazard"] = 128047424244555,
		["bird"] = 118773962601928,
		["blueprint"] = 139470903559247,
		["bluetooth-connected"] = 111199533141869,
		["bluetooth"] = 124016500716528,
		["bluetooth-slash"] = 135671717104530,
		["bluetooth-x"] = 124908136654903,
		["boat"] = 130608989718498,
		["bomb"] = 104990632610808,
		["bone"] = 92787273167631,
		["book-bookmark"] = 78412919475608,
		["book"] = 130361143261350,
		["book-open"] = 125567644458134,
		["book-open-text"] = 139939524247330,
		["book-open-user"] = 135451772040399,
		["bookmark"] = 111407663160302,
		["bookmark-simple"] = 74373435547631,
		["bookmarks"] = 82570386614294,
		["bookmarks-simple"] = 132442137168243,
		["books"] = 121378099455330,
		["boot"] = 89348340518648,
		["boules"] = 97458577998260,
		["bounding-box"] = 113138167577473,
		["bowl-food"] = 80968519639947,
		["bowl-steam"] = 103322138993032,
		["bowling-ball"] = 80937302766028,
		["box-arrow-down"] = 124975295084081,
		["box-arrow-up"] = 75819018905517,
		["boxing-glove"] = 71155075105211,
		["brackets-angle"] = 137453281109773,
		["brackets-curly"] = 113039847453271,
		["brackets-round"] = 131319293218100,
		["brackets-square"] = 81769884232086,
		["brain"] = 84740267411703,
		["brandy"] = 138377801283819,
		["bread"] = 136390735165084,
		["bridge"] = 135893018277395,
		["briefcase"] = 115927013358481,
		["briefcase-metal"] = 121433452567560,
		["broadcast"] = 86988954451365,
		["broom"] = 77054145041991,
		["browser"] = 83577502419395,
		["browsers"] = 86848589235296,
		["bug-beetle"] = 76502065162022,
		["bug-droid"] = 134341561292364,
		["bug"] = 122806770985738,
		["building-apartment"] = 125646967995622,
		["building"] = 98461884383545,
		["building-office"] = 100361757325955,
		["buildings"] = 108320546490747,
		["bulldozer"] = 135046246456864,
		["bus"] = 129518330407842,
		["butterfly"] = 117522707131213,
		["cable-car"] = 126358951047935,
		["cactus"] = 107441880269121,
		["cake"] = 103986267133378,
		["calculator"] = 81103255351794,
		["calendar-blank"] = 84190640607677,
		["calendar-check"] = 120475482851988,
		["calendar-dot"] = 99981238927218,
		["calendar-dots"] = 103768292818257,
		["calendar"] = 76858798882510,
		["calendar-heart"] = 110307054757525,
		["calendar-minus"] = 128350698545751,
		["calendar-plus"] = 87194840577444,
		["calendar-slash"] = 93415265108824,
		["calendar-star"] = 93959670820134,
		["calendar-x"] = 120712250371525,
		["call-bell"] = 135588537680508,
		["camera"] = 130248766187215,
		["camera-plus"] = 116252992551690,
		["camera-rotate"] = 136534097737857,
		["camera-slash"] = 117551322559600,
		["campfire"] = 140247514120255,
		["car-battery"] = 112304110366247,
		["car"] = 105893330807278,
		["car-profile"] = 130466720064677,
		["car-simple"] = 116019255656188,
		["cardholder"] = 111202456832668,
		["cards"] = 117525049398657,
		["cards-three"] = 113781589641333,
		["caret-circle-double-down"] = 94437943731161,
		["caret-circle-double-left"] = 81681412512591,
		["caret-circle-double-right"] = 129659405719680,
		["caret-circle-double-up"] = 83289034956625,
		["caret-circle-down"] = 87926744903992,
		["caret-circle-left"] = 95245510973160,
		["caret-circle-right"] = 81632701154838,
		["caret-circle-up-down"] = 93615401107168,
		["caret-circle-up"] = 105713387279750,
		["caret-double-down"] = 102587945536169,
		["caret-double-left"] = 132881785514788,
		["caret-double-right"] = 137665119973534,
		["caret-double-up"] = 112253293460222,
		["caret-down"] = 128645299088496,
		["caret-left"] = 71604605820538,
		["caret-line-down"] = 98193015471274,
		["caret-line-left"] = 124288576329075,
		["caret-line-right"] = 135308412845479,
		["caret-line-up"] = 91119533951797,
		["caret-right"] = 73127689438483,
		["caret-up-down"] = 72271604013887,
		["caret-up"] = 111075295520954,
		["carrot"] = 89941844566858,
		["cash-register"] = 109791506659933,
		["cassette-tape"] = 74288205973010,
		["castle-turret"] = 102001614579108,
		["cat"] = 130074763808479,
		["cell-signal-full"] = 80446550122820,
		["cell-signal-high"] = 112683998685959,
		["cell-signal-low"] = 115326744368929,
		["cell-signal-medium"] = 137179458214141,
		["cell-signal-none"] = 86727466140008,
		["cell-signal-slash"] = 80426777790244,
		["cell-signal-x"] = 114133799778180,
		["cell-tower"] = 135129665262769,
		["certificate"] = 127293832680639,
		["chair"] = 104502958865473,
		["chalkboard"] = 131727956093472,
		["chalkboard-simple"] = 98148017603215,
		["chalkboard-teacher"] = 123726475063451,
		["charging-station"] = 89076859268949,
		["chart-bar"] = 99864046755959,
		["chart-bar-horizontal"] = 133712110883568,
		["chart-donut"] = 123861803856400,
		["chart-line-down"] = 86762318374571,
		["chart-line"] = 111650278250092,
		["chart-line-up"] = 90842188322546,
		["chart-pie"] = 81827954897558,
		["chart-pie-slice"] = 88601123476307,
		["chart-polar"] = 134963669956849,
		["chart-scatter"] = 80399249950950,
		["chat-centered-dots"] = 74759527202939,
		["chat-centered"] = 77954318919425,
		["chat-centered-slash"] = 80938081301858,
		["chat-centered-text"] = 89171497760107,
		["chat-circle-dots"] = 77866402505138,
		["chat-circle"] = 86468975403163,
		["chat-circle-slash"] = 75172722527810,
		["chat-circle-text"] = 80380373670986,
		["chat-dots"] = 105695835561973,
		["chat"] = 98604151299680,
		["chat-slash"] = 135510389781721,
		["chat-teardrop-dots"] = 139113728851858,
		["chat-teardrop"] = 98071375493933,
		["chat-teardrop-slash"] = 136330269194305,
		["chat-teardrop-text"] = 131958659281820,
		["chat-text"] = 96161134972872,
		["chats-circle"] = 112657579944810,
		["chats"] = 126023520407670,
		["chats-teardrop"] = 84991413957392,
		["check-circle"] = 81251987013475,
		["check-fat"] = 113361296899368,
		["check"] = 106265403373090,
		["check-square"] = 110013245301090,
		["check-square-offset"] = 132344003855905,
		["checkerboard"] = 133403416870823,
		["checks"] = 120162435152729,
		["cheers"] = 129542771661089,
		["cheese"] = 137783166260527,
		["chef-hat"] = 139119781993443,
		["cherries"] = 83780327500338,
		["church"] = 89342534337572,
		["circle-dashed"] = 108791774201598,
		["circle"] = 97803084265411,
		["circle-half"] = 99024339917369,
		["circle-half-tilt"] = 89191408202528,
		["circle-notch"] = 92354307959679,
		["circles-four"] = 133020392532629,
		["circles-three"] = 138221175189409,
		["circles-three-plus"] = 134418584667947,
		["circuitry"] = 95560839785522,
		["city"] = 87922678300967,
		["clipboard"] = 84777785420633,
		["clipboard-text"] = 90750192516890,
		["clock-afternoon"] = 81926664045780,
		["clock-clockwise"] = 89127315331940,
		["clock-countdown"] = 129403776114991,
		["clock-counter-clockwise"] = 114200209578289,
		["clock"] = 103886802788615,
		["clock-user"] = 140497453215704,
		["closed-captioning"] = 102037948159280,
		["cloud-arrow-down"] = 86294055541463,
		["cloud-arrow-up"] = 131821572778189,
		["cloud-check"] = 129390684949336,
		["cloud"] = 123872640736591,
		["cloud-fog"] = 77301525485321,
		["cloud-lightning"] = 99504613605735,
		["cloud-moon"] = 93213882062379,
		["cloud-rain"] = 98199341528554,
		["cloud-slash"] = 99563395581546,
		["cloud-snow"] = 94458632563936,
		["cloud-sun"] = 85131923799970,
		["cloud-warning"] = 90414700153604,
		["cloud-x"] = 78590919674212,
		["clover"] = 82236360249260,
		["club"] = 88563731795260,
		["coat-hanger"] = 71197171670287,
		["coda-logo"] = 122324586342370,
		["code-block"] = 130010279369884,
		["code"] = 72630086045460,
		["code-simple"] = 122430395566312,
		["codepen-logo"] = 73020465582237,
		["codesandbox-logo"] = 131542862681894,
		["coffee-bean"] = 122885847253072,
		["coffee"] = 127582143995912,
		["coin"] = 90423279987669,
		["coin-vertical"] = 115826787261197,
		["coins"] = 134420357040407,
		["columns"] = 137730104352186,
		["columns-plus-left"] = 136797219565530,
		["columns-plus-right"] = 133031617260263,
		["command"] = 77224375030498,
		["compass"] = 117544601218723,
		["compass-rose"] = 118695217881713,
		["compass-tool"] = 100296652427194,
		["computer-tower"] = 105019342466919,
		["confetti"] = 92465983440399,
		["contactless-payment"] = 120148481248653,
		["control"] = 97986870326591,
		["cookie"] = 102612919573117,
		["cooking-pot"] = 109388352893257,
		["copy"] = 86516550944457,
		["copy-simple"] = 94074743183236,
		["copyleft"] = 114097351277017,
		["copyright"] = 97396605385251,
		["corners-in"] = 136329912724686,
		["corners-out"] = 119688679865503,
		["couch"] = 113789649989337,
		["court-basketball"] = 137860099085648,
		["cow"] = 88419411460131,
		["cowboy-hat"] = 91100733075803,
		["cpu"] = 88827515829831,
		["crane"] = 78866823061501,
		["crane-tower"] = 98334228550767,
		["credit-card"] = 97889937128939,
		["cricket"] = 77739741439830,
		["crop"] = 136894378014911,
		["cross"] = 108051264573198,
		["crosshair"] = 70953410348206,
		["crosshair-simple"] = 98095248475138,
		["crown-cross"] = 139099648783263,
		["crown"] = 112589860871869,
		["crown-simple"] = 116141169106399,
		["cube"] = 110128435675886,
		["cube-focus"] = 117142804409693,
		["cube-transparent"] = 70589081001107,
		["currency-btc"] = 95142523553250,
		["currency-circle-dollar"] = 92492175987422,
		["currency-cny"] = 138977277902436,
		["currency-dollar"] = 138286161261178,
		["currency-dollar-simple"] = 115457934659798,
		["currency-eth"] = 114887867495997,
		["currency-eur"] = 130283362137335,
		["currency-gbp"] = 107534189487787,
		["currency-inr"] = 127524928706837,
		["currency-jpy"] = 108191603683536,
		["currency-krw"] = 78894344424865,
		["currency-kzt"] = 123094325396896,
		["currency-ngn"] = 123570704877696,
		["currency-rub"] = 136541634784387,
		["cursor-click"] = 80577223219606,
		["cursor"] = 74663502670148,
		["cursor-text"] = 131898484458872,
		["cylinder"] = 130262182850618,
		["database"] = 90317051948406,
		["desk"] = 89875887386629,
		["desktop"] = 123704558959159,
		["desktop-tower"] = 118836612460669,
		["detective"] = 70563159211335,
		["dev-to-logo"] = 130099994181056,
		["device-mobile-camera"] = 98894033379208,
		["device-mobile"] = 139014965206415,
		["device-mobile-slash"] = 110812960815394,
		["device-mobile-speaker"] = 73317399132183,
		["device-rotate"] = 87402756511909,
		["device-tablet-camera"] = 80241703289708,
		["device-tablet"] = 74547072154439,
		["device-tablet-speaker"] = 71601515114388,
		["devices"] = 135043167697190,
		["diamond"] = 118913385784631,
		["diamonds-four"] = 109614924155822,
		["dice-five"] = 102359028486183,
		["dice-four"] = 137997407754935,
		["dice-one"] = 136872228063419,
		["dice-six"] = 132217872923239,
		["dice-three"] = 101941772243419,
		["dice-two"] = 111782410067968,
		["disc"] = 122313202869106,
		["disco-ball"] = 139744306431356,
		["discord-logo"] = 94637865026241,
		["divide"] = 91994292944214,
		["dna"] = 101055213381050,
		["dog"] = 136740609793034,
		["door"] = 117116735934479,
		["door-open"] = 72791079865421,
		["dot"] = 72493152304176,
		["dot-outline"] = 78016636336609,
		["dots-nine"] = 91226226144040,
		["dots-six"] = 100458819556300,
		["dots-six-vertical"] = 136090712847846,
		["dots-three-circle"] = 139366829236476,
		["dots-three-circle-vertical"] = 132634420513262,
		["dots-three"] = 83745339049530,
		["dots-three-outline"] = 84771002180932,
		["dots-three-outline-vertical"] = 126218181408150,
		["dots-three-vertical"] = 112096839001627,
		["download"] = 71301427330987,
		["download-simple"] = 138545428566600,
		["dress"] = 134634933877919,
		["dresser"] = 78892563548691,
		["dribbble-logo"] = 97744645207083,
		["drone"] = 89230645562486,
		["drop"] = 134275608494894,
		["drop-half-bottom"] = 96878998770522,
		["drop-half"] = 138574534853718,
		["drop-simple"] = 89968675488934,
		["drop-slash"] = 75705127114616,
		["dropbox-logo"] = 123954159703753,
		["ear"] = 72879276343449,
		["ear-slash"] = 93448694981086,
		["egg-crack"] = 88438042259697,
		["egg"] = 116990714592038,
		["eject"] = 108837662916480,
		["eject-simple"] = 85790427024285,
		["elevator"] = 134622572861234,
		["empty"] = 125946425352236,
		["engine"] = 122577288941563,
		["envelope"] = 91599684670867,
		["envelope-open"] = 117403508708136,
		["envelope-simple"] = 80526281152747,
		["envelope-simple-open"] = 99454241784070,
		["equalizer"] = 121149803322987,
		["equals"] = 82381322132133,
		["eraser"] = 77208887745901,
		["escalator-down"] = 73962091724533,
		["escalator-up"] = 122422053649501,
		["exam"] = 104716784888416,
		["exclamation-mark"] = 107039467919406,
		["exclude"] = 132196447321328,
		["exclude-square"] = 120926297048282,
		["export"] = 97047318144652,
		["eye-closed"] = 128086859417356,
		["eye"] = 91148908779390,
		["eye-slash"] = 87575513726659,
		["eyedropper"] = 137696943742528,
		["eyedropper-sample"] = 121373711929188,
		["eyeglasses"] = 87509290999592,
		["eyes"] = 114093700541897,
		["face-mask"] = 106399296942724,
		["facebook-logo"] = 78629793906028,
		["factory"] = 122807687761850,
		["faders"] = 122392629814263,
		["faders-horizontal"] = 73803779415049,
		["fallout-shelter"] = 74748767038638,
		["fan"] = 88266127897763,
		["farm"] = 111542027068158,
		["fast-forward-circle"] = 101637042420837,
		["fast-forward"] = 101398663356793,
		["feather"] = 86325171509319,
		["fediverse-logo"] = 138908910673892,
		["figma-logo"] = 135586693113190,
		["file-archive"] = 102477951325584,
		["file-arrow-down"] = 103822966564525,
		["file-arrow-up"] = 94429018216906,
		["file-audio"] = 126546535024562,
		["file-c"] = 120896057061805,
		["file-c-sharp"] = 112779487239784,
		["file-cloud"] = 111123525992889,
		["file-code"] = 129204497511213,
		["file-cpp"] = 132388433815677,
		["file-css"] = 121814411534969,
		["file-csv"] = 106038944963868,
		["file-dashed"] = 96573545669060,
		["file-doc"] = 122371819489572,
		["file"] = 119584866608809,
		["file-html"] = 131912242155338,
		["file-image"] = 124034925763497,
		["file-ini"] = 89954335560168,
		["file-jpg"] = 95216492880480,
		["file-js"] = 140179902405905,
		["file-jsx"] = 133355268871323,
		["file-lock"] = 94185071404887,
		["file-magnifying-glass"] = 130918540563842,
		["file-md"] = 94460512679468,
		["file-minus"] = 103734432586581,
		["file-pdf"] = 126484445408847,
		["file-plus"] = 87050179538426,
		["file-png"] = 134996159766097,
		["file-ppt"] = 98095942930677,
		["file-py"] = 101056934513590,
		["file-rs"] = 129915530886631,
		["file-sql"] = 134536752389848,
		["file-svg"] = 105826173512201,
		["file-text"] = 88351734886970,
		["file-ts"] = 112559608829441,
		["file-tsx"] = 94144807462544,
		["file-txt"] = 86943811524927,
		["file-video"] = 116562886410615,
		["file-vue"] = 118477444682969,
		["file-x"] = 133091994886641,
		["file-xls"] = 118533608189399,
		["file-zip"] = 78319511818795,
		["files"] = 99115890192380,
		["film-reel"] = 129077732863907,
		["film-script"] = 119058440215847,
		["film-slate"] = 70728437759057,
		["film-strip"] = 130457475790612,
		["fingerprint"] = 135980420697809,
		["fingerprint-simple"] = 138540352392887,
		["finn-the-human"] = 99775334479077,
		["fire-extinguisher"] = 99460357497107,
		["fire"] = 139749643202606,
		["fire-simple"] = 107014467409093,
		["fire-truck"] = 78583464907998,
		["first-aid"] = 85103320906733,
		["first-aid-kit"] = 99735923014960,
		["fish"] = 132088007142210,
		["fish-simple"] = 119452165768116,
		["flag-banner"] = 115850715541803,
		["flag-banner-fold"] = 84075102754886,
		["flag-checkered"] = 82984785913309,
		["flag"] = 132683019318099,
		["flag-pennant"] = 140656745777025,
		["flame"] = 107952159541953,
		["flashlight"] = 128605595348480,
		["flask"] = 122327912267928,
		["flip-horizontal"] = 71948240743853,
		["flip-vertical"] = 82546268882938,
		["floppy-disk-back"] = 103845452018999,
		["floppy-disk"] = 72841439310004,
		["flow-arrow"] = 131391006664201,
		["flower"] = 86371626626575,
		["flower-lotus"] = 133866769009971,
		["flower-tulip"] = 87871691225665,
		["flying-saucer"] = 113013343480581,
		["folder-dashed"] = 103386441357836,
		["folder"] = 124466113250845,
		["folder-lock"] = 135075150468150,
		["folder-minus"] = 124016032453667,
		["folder-open"] = 123158684281352,
		["folder-plus"] = 94310369498832,
		["folder-simple-dashed"] = 75854437548992,
		["folder-simple"] = 133138139269296,
		["folder-simple-lock"] = 138774167895286,
		["folder-simple-minus"] = 119660269090441,
		["folder-simple-plus"] = 103992182886982,
		["folder-simple-star"] = 80669070628513,
		["folder-simple-user"] = 112008220875984,
		["folder-star"] = 84496450268053,
		["folder-user"] = 137825175204439,
		["folders"] = 95956133434549,
		["football"] = 118322312252461,
		["football-helmet"] = 98816439941254,
		["footprints"] = 97168897540290,
		["fork-knife"] = 119017594431261,
		["four-k"] = 78252898650662,
		["frame-corners"] = 84754452257184,
		["framer-logo"] = 106152730893213,
		["function"] = 73387944549729,
		["funnel"] = 118665894915832,
		["funnel-simple"] = 125953940185592,
		["funnel-simple-x"] = 136161968442874,
		["funnel-x"] = 122154592800790,
		["game-controller"] = 94712051446939,
		["garage"] = 130586173284465,
		["gas-can"] = 94476820923974,
		["gas-pump"] = 76473915271667,
		["gauge"] = 117834465620858,
		["gavel"] = 110565495160762,
		["gear"] = 128863007232463,
		["gear-fine"] = 91293586426855,
		["gear-six"] = 138683035860008,
		["gender-female"] = 87681548561003,
		["gender-male"] = 111089618165183,
		["gender-neuter"] = 73655276564884,
		["gender-nonbinary"] = 139319226362025,
		["gender-transgender"] = 120976323378367,
		["ghost"] = 112470748063884,
		["gif"] = 73078635693893,
		["gift"] = 109177057726388,
		["git-branch"] = 72045448907014,
		["git-commit"] = 113645005470290,
		["git-fork"] = 120635525605294,
		["git-merge"] = 83673367119795,
		["git-pull-request"] = 127006631091106,
		["globe"] = 75634192848808,
		["globe-hemisphere-east"] = 94860786746451,
		["globe-hemisphere-west"] = 112463196699667,
		["globe-simple"] = 87848134033449,
		["globe-simple-x"] = 71373028730123,
		["globe-stand"] = 107356879194486,
		["globe-x"] = 134944995398231,
		["goggles"] = 85042547639133,
		["golf"] = 76281470886817,
		["goodreads-logo"] = 105498928473360,
		["google-cardboard-logo"] = 135832187639096,
		["google-chrome-logo"] = 92554366280244,
		["google-drive-logo"] = 115715672016012,
		["google-logo"] = 111965423325225,
		["google-photos-logo"] = 127304407162283,
		["google-play-logo"] = 90497163279727,
		["google-podcasts-logo"] = 94832929258166,
		["gps"] = 112668149285935,
		["gps-fix"] = 97540141966336,
		["gps-slash"] = 109770289985023,
		["gradient"] = 79842342485716,
		["graduation-cap"] = 72237217645434,
		["grains"] = 118391368937383,
		["grains-slash"] = 117288334760231,
		["graph"] = 86680887989732,
		["graphics-card"] = 74231594279289,
		["greater-than"] = 85605522184093,
		["greater-than-or-equal"] = 138721678666747,
		["grid-four"] = 128467194939450,
		["grid-nine"] = 112456660164267,
		["guitar"] = 72367797460822,
		["hair-dryer"] = 114420828117411,
		["hamburger"] = 74345218841715,
		["hammer"] = 113384070277693,
		["hand-arrow-down"] = 128216716092074,
		["hand-arrow-up"] = 72001984805906,
		["hand-coins"] = 115517148943037,
		["hand-deposit"] = 126180663523553,
		["hand-eye"] = 126805401658779,
		["hand"] = 111725727480429,
		["hand-fist"] = 112322439644997,
		["hand-grabbing"] = 79009515034754,
		["hand-heart"] = 137797241070358,
		["hand-palm"] = 119756720969132,
		["hand-peace"] = 88114669684567,
		["hand-pointing"] = 135193570846242,
		["hand-soap"] = 73013244896263,
		["hand-swipe-left"] = 74192211835265,
		["hand-swipe-right"] = 120072188935772,
		["hand-tap"] = 90112083803751,
		["hand-waving"] = 124930264274743,
		["hand-withdraw"] = 130179218351350,
		["handbag"] = 104641776241225,
		["handbag-simple"] = 93232893557942,
		["hands-clapping"] = 72460144751171,
		["hands-praying"] = 92262611320874,
		["handshake"] = 137312629140666,
		["hard-drive"] = 136865355246291,
		["hard-drives"] = 129836111647639,
		["hard-hat"] = 111494621445949,
		["hash"] = 117771968677623,
		["hash-straight"] = 138860157105004,
		["head-circuit"] = 93550640257132,
		["headlights"] = 73752248489317,
		["headphones"] = 87775429879895,
		["headset"] = 118699953144971,
		["heart-break"] = 97009840744724,
		["heart"] = 84167302580244,
		["heart-half"] = 117370704380229,
		["heart-straight-break"] = 110364694586604,
		["heart-straight"] = 105789146907268,
		["heartbeat"] = 122913848385394,
		["hexagon"] = 97998229237297,
		["high-definition"] = 103818938976998,
		["high-heel"] = 133340765093586,
		["highlighter-circle"] = 139055217217303,
		["highlighter"] = 86322261967933,
		["hockey"] = 86718317172455,
		["hoodie"] = 75030020156906,
		["horse"] = 93897841312691,
		["hospital"] = 116191795742096,
		["hourglass"] = 76871757750960,
		["hourglass-high"] = 115436308793975,
		["hourglass-low"] = 137393252702331,
		["hourglass-medium"] = 121339973096239,
		["hourglass-simple"] = 79146456939749,
		["hourglass-simple-high"] = 134681773319103,
		["hourglass-simple-low"] = 83929007718737,
		["hourglass-simple-medium"] = 121418012648499,
		["house"] = 140145947927063,
		["house-line"] = 138477782066834,
		["house-simple"] = 138030402069295,
		["hurricane"] = 85803537944402,
		["ice-cream"] = 116780903475199,
		["identification-badge"] = 140084891060172,
		["identification-card"] = 79481232755010,
		["image-broken"] = 134297175205683,
		["image"] = 75249762123160,
		["image-square"] = 79257066916334,
		["images"] = 114142753107933,
		["images-square"] = 100427990010115,
		["infinity"] = 131231438946784,
		["info"] = 127955842461182,
		["instagram-logo"] = 89463447523022,
		["intersect"] = 123084813433798,
		["intersect-square"] = 106616165844051,
		["intersect-three"] = 122190929981801,
		["intersection"] = 91196033098752,
		["invoice"] = 134857428928708,
		["island"] = 139293104550572,
		["jar"] = 84533053725071,
		["jar-label"] = 93758083857693,
		["jeep"] = 116518225135161,
		["joystick"] = 107286070369736,
		["kanban"] = 123605566110818,
		["key"] = 104396136301969,
		["key-return"] = 132486672612410,
		["keyboard"] = 98698444197293,
		["keyhole"] = 90401046176479,
		["knife"] = 74517561087832,
		["ladder"] = 85846799572551,
		["ladder-simple"] = 131861633326272,
		["lamp"] = 81497416356999,
		["lamp-pendant"] = 136344014878119,
		["laptop"] = 121427183958291,
		["lasso"] = 100662574254623,
		["lastfm-logo"] = 137749011285366,
		["layout"] = 106310079035824,
		["leaf"] = 110833163093112,
		["lectern"] = 89420548950590,
		["lego"] = 90840478234485,
		["lego-smiley"] = 116332972519283,
		["less-than"] = 114354450497089,
		["less-than-or-equal"] = 137398710764316,
		["letter-circle-h"] = 119126628449925,
		["letter-circle-p"] = 132629939817221,
		["letter-circle-v"] = 102161895808388,
		["lifebuoy"] = 93732226121197,
		["lightbulb-filament"] = 139816074130514,
		["lightbulb"] = 113747315532851,
		["lighthouse"] = 101501805389031,
		["lightning-a"] = 74120858079292,
		["lightning"] = 119457917600998,
		["lightning-slash"] = 132541819957240,
		["line-segment"] = 96592047294220,
		["line-segments"] = 95275721380069,
		["line-vertical"] = 116715966835566,
		["link-break"] = 90518405713382,
		["link"] = 72254078248039,
		["link-simple-break"] = 101561413778408,
		["link-simple"] = 96074584881120,
		["link-simple-horizontal-break"] = 95579796787537,
		["link-simple-horizontal"] = 112249432825206,
		["linkedin-logo"] = 132795348922065,
		["linktree-logo"] = 99143281698184,
		["linux-logo"] = 91881175137728,
		["list-bullets"] = 76911345821519,
		["list-checks"] = 73709183712167,
		["list-dashes"] = 118157357758528,
		["list"] = 97881671775091,
		["list-heart"] = 125913058835373,
		["list-magnifying-glass"] = 138193037240286,
		["list-numbers"] = 92091750446544,
		["list-plus"] = 92179172110237,
		["list-star"] = 103754802916441,
		["lock"] = 110315419440560,
		["lock-key"] = 73682039731080,
		["lock-key-open"] = 112267387645226,
		["lock-laminated"] = 88646303048208,
		["lock-laminated-open"] = 122383581322600,
		["lock-open"] = 97543354428297,
		["lock-simple"] = 84771366308942,
		["lock-simple-open"] = 84644047386468,
		["lockers"] = 74478043493524,
		["log"] = 89324324267416,
		["magic-wand"] = 107188952806833,
		["magnet"] = 98438544012728,
		["magnet-straight"] = 76508425032364,
		["magnifying-glass"] = 97766305654243,
		["magnifying-glass-minus"] = 88236284927693,
		["magnifying-glass-plus"] = 80515632006466,
		["mailbox"] = 98271089241110,
		["map-pin-area"] = 124002067089828,
		["map-pin"] = 134492119148232,
		["map-pin-line"] = 103627644115155,
		["map-pin-plus"] = 82172964348738,
		["map-pin-simple-area"] = 136304474467322,
		["map-pin-simple"] = 122315465223928,
		["map-pin-simple-line"] = 113422101172191,
		["map-trifold"] = 135420138087093,
		["markdown-logo"] = 101801711927999,
		["marker-circle"] = 89734330378923,
		["martini"] = 94401052637356,
		["mask-happy"] = 140129406707666,
		["mask-sad"] = 128354607201526,
		["mastodon-logo"] = 136222236659028,
		["math-operations"] = 74913314058920,
		["matrix-logo"] = 78535458704700,
		["medal"] = 123240924821600,
		["medal-military"] = 110807105796004,
		["medium-logo"] = 88340494875959,
		["megaphone"] = 84011091287092,
		["megaphone-simple"] = 102403590962545,
		["member-of"] = 140418415729430,
		["memory"] = 125342949499878,
		["messenger-logo"] = 82899117924757,
		["meta-logo"] = 139416149175140,
		["meteor"] = 114867961558473,
		["metronome"] = 137774990035593,
		["microphone"] = 72840729003641,
		["microphone-slash"] = 78262921464494,
		["microphone-stage"] = 117253903504295,
		["microscope"] = 111043739815131,
		["microsoft-excel-logo"] = 118776333364352,
		["microsoft-outlook-logo"] = 133911809078597,
		["microsoft-powerpoint-logo"] = 103894551679241,
		["microsoft-teams-logo"] = 85277317847294,
		["microsoft-word-logo"] = 121253966545854,
		["minus-circle"] = 101693129089368,
		["minus"] = 108496029261162,
		["minus-square"] = 138339238756078,
		["money"] = 75600965545406,
		["money-wavy"] = 96063472591616,
		["monitor-arrow-up"] = 112548472460699,
		["monitor"] = 123284420457203,
		["monitor-play"] = 123145632955742,
		["moon"] = 123459497983968,
		["moon-stars"] = 98238891727216,
		["moped"] = 121436640528188,
		["moped-front"] = 98905955888410,
		["mosque"] = 140499821395693,
		["motorcycle"] = 119202484342958,
		["mountains"] = 116321153121240,
		["mouse"] = 126515822728979,
		["mouse-left-click"] = 132057083804078,
		["mouse-middle-click"] = 102845138701956,
		["mouse-right-click"] = 100062127356563,
		["mouse-scroll"] = 82584213229368,
		["mouse-simple"] = 86956832643832,
		["music-note"] = 128564712565201,
		["music-note-simple"] = 137201817306781,
		["music-notes"] = 99929929023347,
		["music-notes-minus"] = 79485613553255,
		["music-notes-plus"] = 101524525943239,
		["music-notes-simple"] = 93750253641472,
		["navigation-arrow"] = 104439353976841,
		["needle"] = 87725953489487,
		["network"] = 135625824065631,
		["network-slash"] = 84603527536388,
		["network-x"] = 104912480951905,
		["newspaper-clipping"] = 110750183397671,
		["newspaper"] = 136886658834510,
		["not-equals"] = 110774609704053,
		["not-member-of"] = 81405050815878,
		["not-subset-of"] = 132902858945473,
		["not-superset-of"] = 104889817857295,
		["notches"] = 123805808530991,
		["note-blank"] = 86237237108954,
		["note"] = 77494285776007,
		["note-pencil"] = 119996799979145,
		["notebook"] = 82340177215445,
		["notepad"] = 75642504129724,
		["notification"] = 112869770625102,
		["notion-logo"] = 133204726448999,
		["nuclear-plant"] = 72266133427415,
		["number-circle-eight"] = 92358458825729,
		["number-circle-five"] = 126091146229735,
		["number-circle-four"] = 78610974633143,
		["number-circle-nine"] = 95613530717346,
		["number-circle-one"] = 139977360517628,
		["number-circle-seven"] = 72458561413833,
		["number-circle-six"] = 123051574574695,
		["number-circle-three"] = 94231263413780,
		["number-circle-two"] = 132176213936446,
		["number-circle-zero"] = 89759214462255,
		["number-eight"] = 85893092379157,
		["number-five"] = 74086656792848,
		["number-four"] = 114236446555263,
		["number-nine"] = 89956048995588,
		["number-one"] = 136320900328166,
		["number-seven"] = 130055664343363,
		["number-six"] = 120987462081846,
		["number-square-eight"] = 121331625891092,
		["number-square-five"] = 130582571988950,
		["number-square-four"] = 126242661022496,
		["number-square-nine"] = 128263898694852,
		["number-square-one"] = 114174402728851,
		["number-square-seven"] = 125342492553181,
		["number-square-six"] = 95818144462215,
		["number-square-three"] = 83049347681487,
		["number-square-two"] = 124142909766709,
		["number-square-zero"] = 102859232171250,
		["number-three"] = 85107100807120,
		["number-two"] = 104808896451799,
		["number-zero"] = 112120517641499,
		["numpad"] = 137890176808087,
		["nut"] = 137288210995932,
		["ny-times-logo"] = 136957739635268,
		["octagon"] = 112202343929250,
		["office-chair"] = 123791980989704,
		["onigiri"] = 96296813137977,
		["open-ai-logo"] = 114066610940554,
		["option"] = 97549610032071,
		["orange"] = 139185524637577,
		["orange-slice"] = 133861562811635,
		["oven"] = 138699827740074,
		["package"] = 120939325052964,
		["paint-brush-broad"] = 94921296914617,
		["paint-brush"] = 121465339944219,
		["paint-brush-household"] = 77601093620213,
		["paint-bucket"] = 70667255412782,
		["paint-roller"] = 127910920783338,
		["palette"] = 118627615901340,
		["panorama"] = 132108313361623,
		["pants"] = 95049549687741,
		["paper-plane"] = 73708245754832,
		["paper-plane-right"] = 79641613876292,
		["paper-plane-tilt"] = 120675139240439,
		["paperclip"] = 98913584355648,
		["paperclip-horizontal"] = 124149967465048,
		["parachute"] = 114158924675898,
		["paragraph"] = 75065852362798,
		["parallelogram"] = 124009313788366,
		["park"] = 105797195242429,
		["password"] = 77894422347232,
		["path"] = 134996519163396,
		["patreon-logo"] = 86037176885545,
		["pause-circle"] = 96298699304040,
		["pause"] = 120073065058308,
		["paw-print"] = 83442249960485,
		["paypal-logo"] = 70826729177680,
		["peace"] = 127715934634711,
		["pen"] = 128201374423471,
		["pen-nib"] = 130070831394380,
		["pen-nib-straight"] = 130901689535545,
		["pencil-circle"] = 77792973052695,
		["pencil"] = 110796147051300,
		["pencil-line"] = 90983778130231,
		["pencil-ruler"] = 119912952401994,
		["pencil-simple"] = 119680541202005,
		["pencil-simple-line"] = 74821992471437,
		["pencil-simple-slash"] = 111435663468987,
		["pencil-slash"] = 118338610540115,
		["pentagon"] = 138038258599351,
		["pentagram"] = 137208937174963,
		["pepper"] = 127319635752352,
		["percent"] = 77691015810112,
		["person-arms-spread"] = 139120846612529,
		["person"] = 87896763414852,
		["person-simple-bike"] = 118666751296089,
		["person-simple-circle"] = 109486782655353,
		["person-simple"] = 85130338124483,
		["person-simple-hike"] = 81085789302622,
		["person-simple-run"] = 125453474909827,
		["person-simple-ski"] = 75411741775324,
		["person-simple-snowboard"] = 87242179394172,
		["person-simple-swim"] = 127616201797923,
		["person-simple-tai-chi"] = 93228738488516,
		["person-simple-throw"] = 128979598929871,
		["person-simple-walk"] = 118085987309003,
		["perspective"] = 71769768188315,
		["phone-call"] = 107458555309496,
		["phone-disconnect"] = 119912809669213,
		["phone"] = 113032983540846,
		["phone-incoming"] = 74257597922989,
		["phone-list"] = 131675324449470,
		["phone-outgoing"] = 139303754174179,
		["phone-pause"] = 82883272617747,
		["phone-plus"] = 85840444045417,
		["phone-slash"] = 114607493351416,
		["phone-transfer"] = 108762543493901,
		["phone-x"] = 106701953485820,
		["phosphor-logo"] = 108533030368798,
		["pi"] = 120351162728534,
		["piano-keys"] = 82917472183875,
		["picnic-table"] = 108766730653509,
		["picture-in-picture"] = 73038822918021,
		["piggy-bank"] = 100965275671030,
		["pill"] = 121091356718707,
		["ping-pong"] = 83647184412731,
		["pint-glass"] = 107147253094681,
		["pinwheel"] = 139669237708163,
		["pipe"] = 74966147548674,
		["pipe-wrench"] = 108368618040066,
		["pix-logo"] = 80505824763709,
		["pizza"] = 136991726727639,
		["placeholder"] = 98223462405811,
		["planet"] = 123232203511939,
		["plant"] = 120918986565782,
		["play-circle"] = 86895794885246,
		["play"] = 93085666326277,
		["play-pause"] = 82455076432028,
		["playlist"] = 103486714622510,
		["plug-charging"] = 77980033182707,
		["plug"] = 103421144918466,
		["plugs-connected"] = 127112654202678,
		["plugs"] = 134340112349932,
		["plus-circle"] = 117964945283660,
		["plus"] = 107119126177637,
		["plus-minus"] = 78719383107588,
		["plus-square"] = 131207877854886,
		["poker-chip"] = 140162539452951,
		["police-car"] = 97992510248668,
		["polygon"] = 92051360879038,
		["popcorn"] = 107598748504858,
		["popsicle"] = 84672380493809,
		["potted-plant"] = 84277538587431,
		["power"] = 83853557363465,
		["prescription"] = 105865603653551,
		["presentation-chart"] = 127635165417665,
		["presentation"] = 135917218621936,
		["printer"] = 82600182582810,
		["prohibit"] = 109861116764935,
		["prohibit-inset"] = 114128428431874,
		["projector-screen-chart"] = 72784260825490,
		["projector-screen"] = 132287876446242,
		["pulse"] = 138796892031456,
		["push-pin"] = 87162817475712,
		["push-pin-simple"] = 96331224147420,
		["push-pin-simple-slash"] = 122685702157400,
		["push-pin-slash"] = 110671223807234,
		["puzzle-piece"] = 136767412153800,
		["qr-code"] = 134750583743586,
		["question"] = 85795629623038,
		["question-mark"] = 82923946781879,
		["queue"] = 84646731758260,
		["quotes"] = 115551402764114,
		["rabbit"] = 129988522829057,
		["racquet"] = 122299437870280,
		["radical"] = 84381289089786,
		["radio-button"] = 95581330066145,
		["radio"] = 109954227734443,
		["radioactive"] = 121075774214483,
		["rainbow-cloud"] = 104097843596187,
		["rainbow"] = 111069806505418,
		["ranking"] = 122989945948693,
		["read-cv-logo"] = 82601276605007,
		["receipt"] = 99442900771878,
		["receipt-x"] = 98401328441672,
		["record"] = 112200366762180,
		["rectangle-dashed"] = 100379731477369,
		["rectangle"] = 83052857323512,
		["recycle"] = 131972932138646,
		["reddit-logo"] = 127312917891326,
		["repeat"] = 80956979555284,
		["repeat-once"] = 116617309378931,
		["replit-logo"] = 99290186400665,
		["resize"] = 102789709662175,
		["rewind-circle"] = 112384683271037,
		["rewind"] = 110244609813689,
		["road-horizon"] = 121081668953047,
		["robot"] = 133612492066793,
		["rocket"] = 139777922866854,
		["rocket-launch"] = 111746127980618,
		["rows"] = 82458112626930,
		["rows-plus-bottom"] = 127967235565398,
		["rows-plus-top"] = 97759808635617,
		["rss"] = 90114955540779,
		["rss-simple"] = 91597660278955,
		["rug"] = 137663180305935,
		["ruler"] = 136557001486552,
		["sailboat"] = 110965980920567,
		["scales"] = 74016793659999,
		["scan"] = 122699635258803,
		["scan-smiley"] = 78835866167296,
		["scissors"] = 81451956065810,
		["scooter"] = 87160374949927,
		["screencast"] = 136808000032675,
		["screwdriver"] = 140532577790052,
		["scribble"] = 72252955516715,
		["scribble-loop"] = 70942629747839,
		["scroll"] = 89930501901485,
		["seal-check"] = 102649900014677,
		["seal"] = 80429836075524,
		["seal-percent"] = 134644123357677,
		["seal-question"] = 86250077240073,
		["seal-warning"] = 75150975791004,
		["seat"] = 111153494164434,
		["seatbelt"] = 75885760397768,
		["security-camera"] = 120851780443067,
		["selection-all"] = 96378981125262,
		["selection-background"] = 80043762304691,
		["selection"] = 102213895831494,
		["selection-foreground"] = 118662127932072,
		["selection-inverse"] = 114194371317547,
		["selection-plus"] = 75439569796841,
		["selection-slash"] = 137225412493569,
		["shapes"] = 95005005335509,
		["share-fat"] = 81468525552507,
		["share"] = 120893136377108,
		["share-network"] = 125117099332721,
		["shield-check"] = 126234589524891,
		["shield-checkered"] = 72385477461303,
		["shield-chevron"] = 96209556850089,
		["shield"] = 127944740972926,
		["shield-plus"] = 87172136217900,
		["shield-slash"] = 80431561705286,
		["shield-star"] = 102211586217869,
		["shield-warning"] = 72480330958042,
		["shipping-container"] = 128199623333164,
		["shirt-folded"] = 136237452785976,
		["shooting-star"] = 129600343623800,
		["shopping-bag"] = 131994508816044,
		["shopping-bag-open"] = 83217803816922,
		["shopping-cart"] = 119404381343580,
		["shopping-cart-simple"] = 106300729874820,
		["shovel"] = 116363619841146,
		["shower"] = 78749118316026,
		["shrimp"] = 134718907921089,
		["shuffle-angular"] = 107697107612434,
		["shuffle"] = 139888546456196,
		["shuffle-simple"] = 126925881493352,
		["sidebar"] = 70869427668680,
		["sidebar-simple"] = 114225355000913,
		["sigma"] = 119467998907922,
		["sign-in"] = 76878121178396,
		["sign-out"] = 132842961206473,
		["signature"] = 91719228279010,
		["signpost"] = 117866244116701,
		["sim-card"] = 75738664722940,
		["siren"] = 128683839835997,
		["sketch-logo"] = 82915457165521,
		["skip-back-circle"] = 92225129127386,
		["skip-back"] = 107463153691702,
		["skip-forward-circle"] = 101088011015233,
		["skip-forward"] = 71153907341835,
		["skull"] = 128315452688265,
		["skype-logo"] = 79254921376428,
		["slack-logo"] = 86316129533275,
		["sliders"] = 97512433256862,
		["sliders-horizontal"] = 111718353809208,
		["slideshow"] = 72815955064557,
		["smiley-angry"] = 82863903692058,
		["smiley-blank"] = 108582142876136,
		["smiley"] = 111337659222473,
		["smiley-meh"] = 137803026758230,
		["smiley-melting"] = 82009936481546,
		["smiley-nervous"] = 78992759893890,
		["smiley-sad"] = 135660797936988,
		["smiley-sticker"] = 85158540360633,
		["smiley-wink"] = 114383987442962,
		["smiley-x-eyes"] = 95317154290797,
		["snapchat-logo"] = 134271008855079,
		["sneaker"] = 134155366340454,
		["sneaker-move"] = 111490525040004,
		["snowflake"] = 126304965540409,
		["soccer-ball"] = 136782378410007,
		["sock"] = 80110171743348,
		["solar-panel"] = 71818583848749,
		["solar-roof"] = 76957753830300,
		["sort-ascending"] = 126504993567465,
		["sort-descending"] = 103240926850565,
		["soundcloud-logo"] = 125162101841640,
		["spade"] = 88971013859948,
		["sparkle"] = 121435567612084,
		["speaker-hifi"] = 80582532853392,
		["speaker-high"] = 139417702777388,
		["speaker-low"] = 130278447757368,
		["speaker-none"] = 93946681638911,
		["speaker-simple-high"] = 119465937909163,
		["speaker-simple-low"] = 100606291783116,
		["speaker-simple-none"] = 106372831410363,
		["speaker-simple-slash"] = 110494492652221,
		["speaker-simple-x"] = 88278496538258,
		["speaker-slash"] = 93880927458918,
		["speaker-x"] = 108543101101340,
		["speedometer"] = 107151050721538,
		["sphere"] = 108289313125348,
		["spinner-ball"] = 72922046487004,
		["spinner"] = 72858147438640,
		["spinner-gap"] = 79807798266796,
		["spiral"] = 93892830868070,
		["split-horizontal"] = 140028777108749,
		["split-vertical"] = 122472297062243,
		["spotify-logo"] = 127378553089349,
		["spray-bottle"] = 132658628220438,
		["square"] = 111579092519181,
		["square-half-bottom"] = 134381659791621,
		["square-half"] = 97330997319105,
		["square-logo"] = 123097497966597,
		["square-split-horizontal"] = 75532075976458,
		["square-split-vertical"] = 74422682205013,
		["squares-four"] = 72791167579771,
		["stack"] = 133970005770353,
		["stack-minus"] = 138459692123156,
		["stack-overflow-logo"] = 78801554607524,
		["stack-plus"] = 114080032809158,
		["stack-simple"] = 120526092923982,
		["stairs"] = 130161368845345,
		["stamp"] = 81091892145960,
		["standard-definition"] = 101827864953031,
		["star-and-crescent"] = 132948600667982,
		["star"] = 74964803556346,
		["star-four"] = 128198537900631,
		["star-half"] = 115501421452079,
		["star-of-david"] = 137236212695398,
		["steam-logo"] = 131215566333685,
		["steering-wheel"] = 100986646980527,
		["steps"] = 77191144747605,
		["stethoscope"] = 122333760676299,
		["sticker"] = 103067172341148,
		["stool"] = 87170872987572,
		["stop-circle"] = 84139667467534,
		["stop"] = 123152413056750,
		["storefront"] = 84742556332491,
		["strategy"] = 97794239361034,
		["stripe-logo"] = 130474443246246,
		["student"] = 109217773474412,
		["subset-of"] = 86073412292735,
		["subset-proper-of"] = 98755140713193,
		["subtitles"] = 71008737234038,
		["subtitles-slash"] = 132394653480387,
		["subtract"] = 70852379789034,
		["subtract-square"] = 93599293949381,
		["subway"] = 71076506616764,
		["suitcase"] = 112628075361024,
		["suitcase-rolling"] = 124071590366488,
		["suitcase-simple"] = 139737175151771,
		["sun-dim"] = 123065980694857,
		["sun"] = 121242785057267,
		["sun-horizon"] = 78812027747444,
		["sunglasses"] = 125265715714539,
		["superset-of"] = 85335126083721,
		["superset-proper-of"] = 79171797801961,
		["swap"] = 96725418768724,
		["swatches"] = 132674507277744,
		["swimming-pool"] = 81217568045402,
		["sword"] = 118652945169395,
		["synagogue"] = 98700054577302,
		["syringe"] = 84678516422003,
		["t-shirt"] = 109021513255487,
		["table"] = 95645046042734,
		["tabs"] = 109981068284712,
		["tag-chevron"] = 79598719024594,
		["tag"] = 111519233154255,
		["tag-simple"] = 109983292323682,
		["target"] = 126787144161031,
		["taxi"] = 94004929558973,
		["tea-bag"] = 137062775613389,
		["telegram-logo"] = 113317195920722,
		["television"] = 136577948624149,
		["television-simple"] = 135871716340845,
		["tennis-ball"] = 89962754882592,
		["tent"] = 103657163285972,
		["terminal"] = 128559089622210,
		["terminal-window"] = 121665743603099,
		["test-tube"] = 96481302113487,
		["text-a-underline"] = 138645195511553,
		["text-aa"] = 95961442267613,
		["text-align-center"] = 92090222055561,
		["text-align-justify"] = 113505779357119,
		["text-align-left"] = 96339153712239,
		["text-align-right"] = 102512345359997,
		["text-b"] = 106466696486058,
		["text-columns"] = 70679078147352,
		["text-h"] = 128084919620495,
		["text-h-five"] = 114637531284661,
		["text-h-four"] = 87612345455586,
		["text-h-one"] = 123337955596030,
		["text-h-six"] = 77608269730207,
		["text-h-three"] = 75749899420891,
		["text-h-two"] = 81144719602911,
		["text-indent"] = 95833884710608,
		["text-italic"] = 94195383851957,
		["text-outdent"] = 115246505504207,
		["text-strikethrough"] = 89674465289268,
		["text-subscript"] = 93404914640978,
		["text-superscript"] = 112202295026218,
		["text-t"] = 108802538783605,
		["text-t-slash"] = 97012199433347,
		["text-underline"] = 122707249263546,
		["thermometer-cold"] = 75750005723563,
		["thermometer"] = 100879020245040,
		["thermometer-hot"] = 78679282145467,
		["thermometer-simple"] = 133879855853735,
		["threads-logo"] = 122596963831153,
		["three-d"] = 118891761647506,
		["thumbs-down"] = 71354508063243,
		["thumbs-up"] = 96579392325931,
		["ticket"] = 110266522016844,
		["tidal-logo"] = 124183729149496,
		["tiktok-logo"] = 95403407971534,
		["tilde"] = 135037214729362,
		["timer"] = 104194460421425,
		["tip-jar"] = 82546118097968,
		["tipi"] = 83669530377782,
		["tire"] = 109331443234158,
		["toggle-left"] = 80134195198890,
		["toggle-right"] = 124471816644652,
		["toilet"] = 80559704002113,
		["toilet-paper"] = 77999009044614,
		["toolbox"] = 134865115422896,
		["tooth"] = 112160904485995,
		["tornado"] = 86739775678025,
		["tote"] = 71971576205702,
		["tote-simple"] = 120534771682254,
		["towel"] = 104833933144517,
		["tractor"] = 110748777171715,
		["trademark"] = 78232125126821,
		["trademark-registered"] = 97124163374847,
		["traffic-cone"] = 117865899356667,
		["traffic-sign"] = 105042029917025,
		["traffic-signal"] = 108465875679782,
		["train"] = 85263598101205,
		["train-regional"] = 72114031831458,
		["train-simple"] = 130399196240565,
		["tram"] = 102352292074259,
		["translate"] = 130015350429825,
		["trash"] = 101229707920546,
		["trash-simple"] = 115577765236264,
		["tray-arrow-down"] = 107855654698101,
		["tray-arrow-up"] = 103616659037270,
		["tray"] = 115390321512600,
		["treasure-chest"] = 95925218813392,
		["tree-evergreen"] = 107365228995045,
		["tree"] = 113775582247445,
		["tree-palm"] = 112161058239811,
		["tree-structure"] = 90551439785811,
		["tree-view"] = 90551425064841,
		["trend-down"] = 133561579091757,
		["trend-up"] = 98867962205673,
		["triangle-dashed"] = 74324519604270,
		["triangle"] = 114239582208860,
		["trolley"] = 99481798168294,
		["trolley-suitcase"] = 110507002249734,
		["trophy"] = 130938849995074,
		["truck"] = 121460637481572,
		["truck-trailer"] = 84263372802846,
		["tumblr-logo"] = 73845541374791,
		["twitch-logo"] = 119027185154333,
		["twitter-logo"] = 73162955618436,
		["umbrella"] = 101871892768335,
		["umbrella-simple"] = 73614569075296,
		["union"] = 133789516486783,
		["unite"] = 122070425022664,
		["unite-square"] = 108158190563513,
		["upload"] = 125798291454801,
		["upload-simple"] = 127540757187876,
		["usb"] = 126691760335912,
		["user-check"] = 129226101597560,
		["user-circle-check"] = 77940967736265,
		["user-circle-dashed"] = 129008549510429,
		["user-circle"] = 79064078939950,
		["user-circle-gear"] = 140516346915650,
		["user-circle-minus"] = 101474221157139,
		["user-circle-plus"] = 109621429245535,
		["user"] = 92109577763657,
		["user-focus"] = 87821591369965,
		["user-gear"] = 92165991527160,
		["user-list"] = 105169971133168,
		["user-minus"] = 117639147832141,
		["user-plus"] = 139863400278509,
		["user-rectangle"] = 96969330601911,
		["user-sound"] = 136519432428969,
		["user-square"] = 95071398644062,
		["user-switch"] = 123891745860526,
		["users"] = 82831061388568,
		["users-four"] = 104487789303292,
		["users-three"] = 129218266223923,
		["van"] = 132710389326668,
		["vault"] = 124150979881026,
		["vector-three"] = 73022430035692,
		["vector-two"] = 132153130876752,
		["vibrate"] = 99296768089421,
		["video-camera"] = 96881668035733,
		["video-camera-slash"] = 127394470340762,
		["video-conference"] = 96688125332175,
		["video"] = 88808635343133,
		["vignette"] = 79850252126413,
		["vinyl-record"] = 79439589379615,
		["virtual-reality"] = 71670359158399,
		["virus"] = 107180872048213,
		["visor"] = 137513602060844,
		["voicemail"] = 81253152352719,
		["volleyball"] = 94223076638125,
		["wall"] = 122638565179365,
		["wallet"] = 119687203614116,
		["warehouse"] = 128286696622039,
		["warning-circle"] = 107788297516544,
		["warning-diamond"] = 105810645936201,
		["warning"] = 129398364168201,
		["warning-octagon"] = 136887876062330,
		["washing-machine"] = 94769230121765,
		["watch"] = 75336610844917,
		["wave-sawtooth"] = 127188627314292,
		["wave-sine"] = 72959105777544,
		["wave-square"] = 123231443274611,
		["wave-triangle"] = 86293815386123,
		["waveform"] = 80479801100836,
		["waveform-slash"] = 71754891206105,
		["waves"] = 118056033795719,
		["webcam"] = 73602975485723,
		["webcam-slash"] = 130047268434524,
		["webhooks-logo"] = 74331537769596,
		["wechat-logo"] = 121463211479783,
		["wheelchair"] = 114695192930276,
		["wheelchair-motion"] = 85388556984133,
		["wifi-high"] = 71344362235454,
		["wifi-low"] = 134784761341849,
		["wifi-medium"] = 122989116293626,
		["wifi-none"] = 102881447895223,
		["wifi-slash"] = 86966972968032,
		["wifi-x"] = 74778887092461,
		["wind"] = 126437609642893,
		["windmill"] = 135267633121488,
		["windows-logo"] = 99926294258844,
		["wrench"] = 87682633335385,
		["x-circle"] = 108304673750311,
		["x"] = 128144748581796,
		["x-logo"] = 137327112516552,
		["x-square"] = 76533820121265,
		["yarn"] = 133240731962883,
		["yin-yang"] = 89044793372578,
		["youtube-logo"] = 118246649729916,
		["champagne"] = 125594615484562,
		["wine"] = 78528323306811,
		["cigarette"] = 127301573202997,
		["cigarette-slash"] = 75468348127131,
		["gender-intersex"] = 92089492374726,
		["pinterest-logo"] = 91041087953400,
		["wa-logo"] = 86180312530094,
	},
	SF = {
		["abc"] = 100440409146443,
		["abs"] = 92363621005271,
		["absBrakesignal"] = 96650934172241,
		["absBrakesignalSlash"] = 99031194280970,
		["absCircle"] = 131263640878114,
		["accessibility"] = 123674923606554,
		["accessibilityBadgeArrowUpRight"] = 131591143368145,
		["airConditionerHorizontal"] = 87575263873354,
		["airConditionerVertical"] = 106787802446841,
		["airplane"] = 127042155092569,
		["airplaneArrival"] = 125165623922032,
		["airplaneCircle"] = 117680366547881,
		["airplaneDeparture"] = 114170964619388,
		["airplayaudio"] = 132916942955864,
		["airplayaudioBadgeExclamationmark"] = 136447514823399,
		["airplayaudioCircle"] = 88830131647623,
		["airplayvideo"] = 84461284428154,
		["airplayvideoBadgeExclamationmark"] = 118815409444339,
		["airplayvideoCircle"] = 76641158810884,
		["airpodGen3Left"] = 120194681953744,
		["airpodGen3Right"] = 104554594654809,
		["airpodLeft"] = 127082905729968,
		["airpodproLeft"] = 95793086337265,
		["airpodproRight"] = 74684142613428,
		["airpodRight"] = 97787903919466,
		["airpods"] = 136964903160287,
		["airpodsChargingcase"] = 127604967961172,
		["airpodsChargingcaseWireless"] = 128040173837707,
		["airpodsGen3"] = 79095121374595,
		["airpodsGen3ChargingcaseWireless"] = 79120104892509,
		["airpodsmax"] = 102938893282204,
		["airpodspro"] = 116114855183538,
		["airpodsproChargingcaseWireless"] = 111093760650540,
		["airpodsproChargingcaseWirelessRadiowavesLeftAndRight"] = 137171665646568,
		["airportExpress"] = 103598731296602,
		["airportExtreme"] = 81211335346183,
		["airportExtremeTower"] = 135286452960382,
		["airPurifier"] = 87703577858510,
		["airtag"] = 101507304635423,
		["airtagRadiowavesForward"] = 88004630385643,
		["alarm"] = 132188666358118,
		["alarmWavesLeftAndRight"] = 105400305752811,
		["alignHorizontalCenter"] = 95921584129344,
		["alignHorizontalLeft"] = 106940079409954,
		["alignHorizontalRight"] = 101931127005354,
		["alignVerticalBottom"] = 92406406320406,
		["alignVerticalCenter"] = 122679867744486,
		["alignVerticalTop"] = 101426271263942,
		["allergens"] = 87768241115636,
		["alt"] = 89032163581958,
		["alternatingcurrent"] = 101357264837592,
		["amplifier"] = 100107786740728,
		["angle"] = 74330288838897,
		["ant"] = 94075524151725,
		["antCircle"] = 96475495112465,
		["antennaRadiowavesLeftAndRight"] = 72723891852899,
		["antennaRadiowavesLeftAndRightCircle"] = 117240621000245,
		["antennaRadiowavesLeftAndRightSlash"] = 102128620863450,
		["app"] = 101315629151886,
		["appBadge"] = 102624785615875,
		["appBadgeCheckmark"] = 99120212063507,
		["appclip"] = 132400920175025,
		["appDashed"] = 97103574854305,
		["appGift"] = 139735193386777,
		["appleLogo"] = 79874646000726,
		["applepencil"] = 71508629094546,
		["applepencilAdapterUsbC"] = 104042719277026,
		["applepencilAndScribble"] = 85245799946302,
		["applepencilGen1"] = 113532794795052,
		["applepencilGen2"] = 139584787357503,
		["applepencilTip"] = 133105725054284,
		["applescript"] = 113292612764892,
		["appleTerminal"] = 105620027353765,
		["appleTerminalOnRectangle"] = 108117667376805,
		["appletv"] = 84883082397458,
		["appletvremoteGen1"] = 119012046125113,
		["appletvremoteGen2"] = 93801259888316,
		["appletvremoteGen3"] = 131349462839025,
		["appletvremoteGen4"] = 101881302490457,
		["applewatch"] = 129677660779802,
		["applewatchAndArrowForward"] = 94636880937571,
		["applewatchRadiowavesLeftAndRight"] = 79517882888121,
		["applewatchSideRight"] = 77458279744932,
		["applewatchSlash"] = 106487744048553,
		["applewatchWatchface"] = 117435831221666,
		["appsIpad"] = 121355599129544,
		["appsIpadLandscape"] = 74514301508288,
		["appsIphone"] = 118931901091531,
		["appsIphoneBadgePlus"] = 104454579409348,
		["appsIphoneLandscape"] = 91558115971997,
		["appwindowSwipeRectangle"] = 79439081300205,
		["aqiHigh"] = 72062504551012,
		["aqiLow"] = 126600553985406,
		["aqiMedium"] = 82709779091864,
		["arcadeStick"] = 93492689048821,
		["arcadeStickAndArrowDown"] = 107150850066094,
		["arcadeStickAndArrowLeft"] = 80931908224133,
		["arcadeStickAndArrowLeftAndArrowRight"] = 113538637882184,
		["arcadeStickAndArrowRight"] = 118437259875645,
		["arcadeStickAndArrowUp"] = 99939791639299,
		["arcadeStickAndArrowUpAndArrowDown"] = 120462278152727,
		["arcadeStickConsole"] = 70725038182070,
		["archivebox"] = 135383976129056,
		["archiveboxCircle"] = 101202683672622,
		["arkit"] = 73289369029656,
		["arkitBadgeXmark"] = 100220549336778,
		["arrow2Squarepath"] = 127170986892509,
		["arrow3Trianglepath"] = 92055746162910,
		["arrowBackward"] = 112330339418031,
		["arrowBackwardCircle"] = 133754892259320,
		["arrowBackwardSquare"] = 71210181227209,
		["arrowBackwardToLine"] = 131149659554320,
		["arrowBackwardToLineCircle"] = 105992196112787,
		["arrowBackwardToLineSquare"] = 115127988659041,
		["arrowCirclepath"] = 82375876675933,
		["arrowClockwise"] = 134482647457048,
		["arrowClockwiseCircle"] = 124617274153370,
		["arrowClockwiseHeart"] = 89932974116238,
		["arrowClockwiseIcloud"] = 119564317606359,
		["arrowClockwiseSquare"] = 82037007154063,
		["arrowCounterclockwise"] = 80049773948475,
		["arrowCounterclockwiseCircle"] = 82641775112281,
		["arrowCounterclockwiseIcloud"] = 76284977441664,
		["arrowCounterclockwiseSquare"] = 95456182343093,
		["arrowDown"] = 120893366817058,
		["arrowDownAndLineHorizontalAndArrowUp"] = 105096454812767,
		["arrowDownApp"] = 101156186420690,
		["arrowDownApplewatch"] = 120002286004487,
		["arrowDownBackward"] = 84372422969086,
		["arrowDownBackwardAndArrowUpForward"] = 115506026700307,
		["arrowDownBackwardAndArrowUpForwardCircle"] = 132088763650225,
		["arrowDownBackwardAndArrowUpForwardSquare"] = 77579180067022,
		["arrowDownBackwardCircle"] = 139319262138804,
		["arrowDownBackwardSquare"] = 87936482941174,
		["arrowDownBackwardToptrailingRectangle"] = 80094690053160,
		["arrowDownCircle"] = 135687701059912,
		["arrowDownCircleDotted"] = 101541376073384,
		["arrowDownDoc"] = 126263364298576,
		["arrowDownForward"] = 138429343266815,
		["arrowDownForwardAndArrowUpBackward"] = 105132150648607,
		["arrowDownForwardAndArrowUpBackwardCircle"] = 98096628303846,
		["arrowDownForwardAndArrowUpBackwardSquare"] = 118896379730302,
		["arrowDownForwardCircle"] = 114742817046266,
		["arrowDownForwardSquare"] = 122244741025675,
		["arrowDownForwardTopleadingRectangle"] = 92753107479824,
		["arrowDownHeart"] = 76691901422122,
		["arrowDownLeft"] = 130189990980427,
		["arrowDownLeftAndArrowUpRight"] = 120882682390032,
		["arrowDownLeftAndArrowUpRightCircle"] = 97211898865142,
		["arrowDownLeftAndArrowUpRightSquare"] = 84482192272392,
		["arrowDownLeftArrowUpRight"] = 132740716083533,
		["arrowDownLeftArrowUpRightCircle"] = 93754869362186,
		["arrowDownLeftArrowUpRightSquare"] = 130585360415797,
		["arrowDownLeftCircle"] = 131608148845778,
		["arrowDownLeftSquare"] = 88308766003484,
		["arrowDownLeftToprightRectangle"] = 114551511358264,
		["arrowDownLeftVideo"] = 136029105755243,
		["arrowDownMessage"] = 104206901132398,
		["arrowDownRight"] = 118950468930444,
		["arrowDownRightAndArrowUpLeft"] = 107180286189567,
		["arrowDownRightAndArrowUpLeftCircle"] = 97521353204554,
		["arrowDownRightAndArrowUpLeftSquare"] = 137365362823760,
		["arrowDownRightCircle"] = 87286697787942,
		["arrowDownRightSquare"] = 91789149246769,
		["arrowDownRightTopleftRectangle"] = 117892888765494,
		["arrowDownSquare"] = 76474747966331,
		["arrowDownToLine"] = 83105765761411,
		["arrowDownToLineCircle"] = 90947227270873,
		["arrowDownToLineCompact"] = 126559109803157,
		["arrowDownToLineSquare"] = 76781097145495,
		["arrowForward"] = 112440157421837,
		["arrowForwardCircle"] = 96454424569563,
		["arrowForwardSquare"] = 90430974943165,
		["arrowForwardToLine"] = 93446567012878,
		["arrowForwardToLineCircle"] = 138601264218304,
		["arrowForwardToLineSquare"] = 115341155712775,
		["arrowkeys"] = 126979603862785,
		["arrowLeft"] = 112148732853002,
		["arrowLeftAndLineVerticalAndArrowRight"] = 114567668927782,
		["arrowLeftAndRight"] = 79428652692177,
		["arrowLeftAndRightCircle"] = 115633173343620,
		["arrowLeftAndRightRighttriangleLeftRighttriangleRight"] = 103119872066027,
		["arrowLeftAndRightSquare"] = 110450073968496,
		["arrowLeftAndRightTextVertical"] = 75763739968686,
		["arrowLeftArrowRight"] = 120431304356715,
		["arrowLeftArrowRightCircle"] = 99428433695571,
		["arrowLeftArrowRightSquare"] = 87908581484568,
		["arrowLeftCircle"] = 92906985394534,
		["arrowLeftSquare"] = 108649833569730,
		["arrowLeftToLine"] = 91535624617729,
		["arrowLeftToLineCircle"] = 109191609726535,
		["arrowLeftToLineCompact"] = 137013662504945,
		["arrowLeftToLineSquare"] = 88530682642886,
		["arrowRectanglepath"] = 122042553990804,
		["arrowRight"] = 113471694745518,
		["arrowRightAndLineVerticalAndArrowLeft"] = 91576414580063,
		["arrowRightCircle"] = 105967295580928,
		["arrowRightDocOnClipboard"] = 84583825314018,
		["arrowRightSquare"] = 93389575694266,
		["arrowRightToLine"] = 90990542985129,
		["arrowRightToLineCircle"] = 98641567674577,
		["arrowRightToLineCompact"] = 71624979668985,
		["arrowRightToLineSquare"] = 102598223319183,
		["arrowshapeBackward"] = 139167863296495,
		["arrowshapeBackwardCircle"] = 107550168752276,
		["arrowshapeBounceForward"] = 90684323957302,
		["arrowshapeBounceRight"] = 93105621166904,
		["arrowshapeDown"] = 91829213579792,
		["arrowshapeDownCircle"] = 75580018546670,
		["arrowshapeForward"] = 91304613238570,
		["arrowshapeForwardCircle"] = 118241293673963,
		["arrowshapeLeft"] = 122480071123738,
		["arrowshapeLeftArrowshapeRight"] = 91916390208501,
		["arrowshapeLeftCircle"] = 114939573825311,
		["arrowshapeRight"] = 109069611579824,
		["arrowshapeRightCircle"] = 89120927231982,
		["arrowshapeTurnUpBackward"] = 139873237324835,
		["arrowshapeTurnUpBackward2"] = 127362384731831,
		["arrowshapeTurnUpBackward2Circle"] = 115334220360651,
		["arrowshapeTurnUpBackwardBadgeClock"] = 108299886317610,
		["arrowshapeTurnUpBackwardCircle"] = 94708728708136,
		["arrowshapeTurnUpForward"] = 96433164067727,
		["arrowshapeTurnUpForwardCircle"] = 101016787745031,
		["arrowshapeTurnUpLeft"] = 117847648137876,
		["arrowshapeTurnUpLeft2"] = 132172917650912,
		["arrowshapeTurnUpLeft2Circle"] = 113031615933213,
		["arrowshapeTurnUpLeftCircle"] = 113730508554004,
		["arrowshapeTurnUpRight"] = 72549478489418,
		["arrowshapeTurnUpRightCircle"] = 94130254046801,
		["arrowshapeUp"] = 127139131306591,
		["arrowshapeUpCircle"] = 137551401253095,
		["arrowshapeZigzagForward"] = 130854328680399,
		["arrowshapeZigzagRight"] = 129803929902665,
		["arrowTriangle2Circlepath"] = 97876840821545,
		["arrowTriangle2CirclepathCamera"] = 110761440206205,
		["arrowTriangle2CirclepathCircle"] = 137167033413367,
		["arrowTriangle2CirclepathDocOnClipboard"] = 102874106989561,
		["arrowTriangle2CirclepathIcloud"] = 89703160887614,
		["arrowtriangleBackward"] = 108402823194656,
		["arrowtriangleBackwardCircle"] = 126152740388605,
		["arrowtriangleBackwardSquare"] = 128338590587813,
		["arrowTriangleBranch"] = 106848864851086,
		["arrowTriangleCapsulepath"] = 79935404561753,
		["arrowtriangleDown"] = 72787893293395,
		["arrowtriangleDownCircle"] = 104919990370784,
		["arrowtriangleDownSquare"] = 133033956423659,
		["arrowtriangleForward"] = 132838813881036,
		["arrowtriangleForwardCircle"] = 103401920692169,
		["arrowtriangleForwardSquare"] = 101790327314181,
		["arrowtriangleLeft"] = 91265849254908,
		["arrowtriangleLeftAndLineVerticalAndArrowtriangleRight"] = 74633712708743,
		["arrowtriangleLeftCircle"] = 96932146280238,
		["arrowtriangleLeftSquare"] = 80111170074465,
		["arrowTriangleMerge"] = 135675192910274,
		["arrowTrianglePull"] = 92844954623247,
		["arrowtriangleRight"] = 112980405706132,
		["arrowtriangleRightAndLineVerticalAndArrowtriangleLeft"] = 127030796163985,
		["arrowtriangleRightCircle"] = 99969752782206,
		["arrowtriangleRightSquare"] = 99173850468552,
		["arrowTriangleSwap"] = 127274138579155,
		["arrowTriangleTurnUpRightCircle"] = 81052567291587,
		["arrowTriangleTurnUpRightDiamond"] = 88682763036554,
		["arrowtriangleUp"] = 130152840566831,
		["arrowtriangleUpArrowtriangleDownWindowLeft"] = 96115161860321,
		["arrowtriangleUpArrowtriangleDownWindowRight"] = 116578098264532,
		["arrowtriangleUpCircle"] = 116726453583909,
		["arrowtriangleUpSquare"] = 91339965289186,
		["arrowTurnDownLeft"] = 91442849259875,
		["arrowTurnDownRight"] = 107664517513606,
		["arrowTurnLeftDown"] = 112415091718387,
		["arrowTurnLeftUp"] = 77538578090691,
		["arrowTurnRightDown"] = 109618367644978,
		["arrowTurnRightUp"] = 132379012556481,
		["arrowTurnUpForwardIphone"] = 120567714696276,
		["arrowTurnUpLeft"] = 111182069278648,
		["arrowTurnUpRight"] = 127383771921504,
		["arrowUp"] = 111856178352737,
		["arrowUpAndDown"] = 91105704080398,
		["arrowUpAndDownAndArrowLeftAndRight"] = 119442452388381,
		["arrowUpAndDownAndSparkles"] = 82082346977957,
		["arrowUpAndDownCircle"] = 82400034655781,
		["arrowUpAndDownRighttriangleUpRighttriangleDown"] = 89990169721189,
		["arrowUpAndDownSquare"] = 121369852320103,
		["arrowUpAndDownTextHorizontal"] = 128271955363044,
		["arrowUpAndLineHorizontalAndArrowDown"] = 106453726801380,
		["arrowUpAndPersonRectanglePortrait"] = 125809959389147,
		["arrowUpAndPersonRectangleTurnLeft"] = 112611140372325,
		["arrowUpAndPersonRectangleTurnRight"] = 79601046498181,
		["arrowUpArrowDown"] = 117712483401629,
		["arrowUpArrowDownCircle"] = 83035492810608,
		["arrowUpArrowDownSquare"] = 115130978941629,
		["arrowUpBackward"] = 107983217917470,
		["arrowUpBackwardAndArrowDownForward"] = 109026531462630,
		["arrowUpBackwardAndArrowDownForwardCircle"] = 110092087112749,
		["arrowUpBackwardAndArrowDownForwardSquare"] = 110682801676144,
		["arrowUpBackwardBottomtrailingRectangle"] = 115337472931506,
		["arrowUpBackwardCircle"] = 79903026800100,
		["arrowUpBackwardSquare"] = 89344345422929,
		["arrowUpBin"] = 103441767152543,
		["arrowUpCircle"] = 88743831776989,
		["arrowUpCircleBadgeClock"] = 95368924706561,
		["arrowUpDoc"] = 130298316589925,
		["arrowUpDocOnClipboard"] = 99871373237994,
		["arrowUpForward"] = 124167135098864,
		["arrowUpForwardAndArrowDownBackward"] = 122592705614034,
		["arrowUpForwardAndArrowDownBackwardCircle"] = 128471028094648,
		["arrowUpForwardAndArrowDownBackwardSquare"] = 137585471458270,
		["arrowUpForwardApp"] = 131933740133848,
		["arrowUpForwardBottomleadingRectangle"] = 110999766641418,
		["arrowUpForwardCircle"] = 84932697750141,
		["arrowUpForwardSquare"] = 105444809401712,
		["arrowUpHeart"] = 83799612279671,
		["arrowUpLeft"] = 89584947457099,
		["arrowUpLeftAndArrowDownRight"] = 133598790392386,
		["arrowUpLeftAndArrowDownRightCircle"] = 80058763516940,
		["arrowUpLeftAndArrowDownRightSquare"] = 75206026448263,
		["arrowUpLeftAndDownRightAndArrowUpRightAndDownLeft"] = 117463534086629,
		["arrowUpLeftAndDownRightMagnifyingglass"] = 99438628725161,
		["arrowUpLeftArrowDownRight"] = 95766864812549,
		["arrowUpLeftArrowDownRightCircle"] = 106024952650012,
		["arrowUpLeftArrowDownRightSquare"] = 124857889894711,
		["arrowUpLeftBottomrightRectangle"] = 78150263178639,
		["arrowUpLeftCircle"] = 135419340258594,
		["arrowUpLeftSquare"] = 125710552388487,
		["arrowUpMessage"] = 77428852209968,
		["arrowUpRight"] = 127621375626588,
		["arrowUpRightAndArrowDownLeft"] = 101550387789265,
		["arrowUpRightAndArrowDownLeftCircle"] = 139655733055978,
		["arrowUpRightAndArrowDownLeftRectangle"] = 125852488466248,
		["arrowUpRightAndArrowDownLeftSquare"] = 130088797723364,
		["arrowUpRightBottomleftRectangle"] = 123634959623435,
		["arrowUpRightCircle"] = 87672337890293,
		["arrowUpRightSquare"] = 100256620819416,
		["arrowUpRightVideo"] = 109165767612830,
		["arrowUpSquare"] = 102337880166856,
		["arrowUpToLine"] = 92193992915403,
		["arrowUpToLineCircle"] = 95928377013785,
		["arrowUpToLineCompact"] = 93450807056034,
		["arrowUpToLineSquare"] = 121356256036839,
		["arrowUpTrash"] = 136982732917435,
		["arrowUturnBackward"] = 78250853479442,
		["arrowUturnBackwardCircle"] = 71359517271199,
		["arrowUturnBackwardCircleBadgeEllipsis"] = 78974954556644,
		["arrowUturnBackwardSquare"] = 131836344415760,
		["arrowUturnDown"] = 127565271196418,
		["arrowUturnDownCircle"] = 131605343986849,
		["arrowUturnDownSquare"] = 134417927642187,
		["arrowUturnForward"] = 117370895244584,
		["arrowUturnForwardCircle"] = 124855208121735,
		["arrowUturnForwardSquare"] = 85497760936396,
		["arrowUturnLeft"] = 95143979400512,
		["arrowUturnLeftCircle"] = 112874051033671,
		["arrowUturnLeftCircleBadgeEllipsis"] = 81250043023237,
		["arrowUturnLeftSquare"] = 90011875127193,
		["arrowUturnRight"] = 99994475531343,
		["arrowUturnRightCircle"] = 112768238689058,
		["arrowUturnRightSquare"] = 77154714933245,
		["arrowUturnUp"] = 118464251843876,
		["arrowUturnUpCircle"] = 104690230461758,
		["arrowUturnUpSquare"] = 103879252728271,
		["aspectratio"] = 108017962786655,
		["asterisk"] = 135733799281280,
		["asteriskCircle"] = 94002783368127,
		["at"] = 123781978634436,
		["atBadgeMinus"] = 131415499619133,
		["atBadgePlus"] = 87035690727729,
		["atCircle"] = 122313756366525,
		["atom"] = 78600959704648,
		["australiandollarsign"] = 81507067071133,
		["australiandollarsignCircle"] = 78244495216255,
		["australiandollarsignSquare"] = 125724737766857,
		["australsign"] = 83481295842654,
		["australsignCircle"] = 96531120709701,
		["australsignSquare"] = 73994125116439,
		["automaticBrakesignal"] = 140256406585296,
		["automaticHeadlightHighBeam"] = 92403405363212,
		["automaticHeadlightLowBeam"] = 108776917846957,
		["autostartstop"] = 77380688725931,
		["autostartstopSlash"] = 88305884098022,
		["autostartstopTrianglebadgeExclamationmark"] = 99812312476607,
		["avRemote"] = 140422938965747,
		["axle2"] = 77816815434149,
		["axle2DriveshaftDisengaged"] = 71544277492160,
		["axle2FrontAndRearEngaged"] = 114394723695103,
		["axle2FrontDisengaged"] = 76811726503902,
		["axle2FrontEngaged"] = 93754956923695,
		["axle2RearDisengaged"] = 107454941272936,
		["axle2RearEngaged"] = 122267575954087,
		["axle2RearLock"] = 82332614339521,
		["backpack"] = 138470539701582,
		["backpackCircle"] = 133623902024586,
		["backward"] = 132891262469005,
		["backwardCircle"] = 110874661858454,
		["backwardEnd"] = 133316887211041,
		["backwardEndAlt"] = 131463770655563,
		["backwardEndCircle"] = 120552658756659,
		["backwardFrame"] = 79607616390210,
		["badgePlusRadiowavesForward"] = 132464432229186,
		["badgePlusRadiowavesRight"] = 107805764320302,
		["bag"] = 98838042666176,
		["bagBadgeMinus"] = 75393349013094,
		["bagBadgePlus"] = 85996805561778,
		["bagBadgeQuestionmark"] = 79526326813516,
		["bagCircle"] = 73082954287278,
		["bahtsign"] = 117968192591538,
		["bahtsignCircle"] = 74465184790378,
		["bahtsignSquare"] = 131162278838168,
		["balloon"] = 99823122145564,
		["balloon2"] = 93507693460257,
		["bandage"] = 130780589444721,
		["banknote"] = 108069782154566,
		["barcode"] = 136753767679432,
		["barcodeViewfinder"] = 118601521304332,
		["barometer"] = 135390591486370,
		["baseball"] = 105717198391714,
		["baseballCircle"] = 92833075753616,
		["baseballDiamondBases"] = 110684655482592,
		["basket"] = 93773308549052,
		["basketball"] = 137444151625842,
		["basketballCircle"] = 72528201476323,
		["bathtub"] = 81614353294538,
		["battery0percent"] = 81581331009197,
		["battery100percent"] = 125062056047608,
		["battery100percentBolt"] = 111370651983069,
		["battery100percentCircle"] = 127835112877390,
		["battery25percent"] = 73260132652169,
		["battery50percent"] = 138488004814227,
		["battery75percent"] = 114027737135751,
		["batteryblock"] = 108402200743221,
		["batteryblockSlash"] = 113307132229111,
		["beachUmbrella"] = 114722837605511,
		["beatsEarphones"] = 128677622725363,
		["beatsFitPro"] = 122083986744951,
		["beatsFitProChargingcase"] = 120936645934230,
		["beatsFitProLeft"] = 116602459616537,
		["beatsFitProRight"] = 119699746025879,
		["beatsHeadphones"] = 102560034462751,
		["beatsPowerbeats"] = 110704356814585,
		["beatsPowerbeats3"] = 99495669230030,
		["beatsPowerbeats3Left"] = 127696382982014,
		["beatsPowerbeats3Right"] = 92002254150732,
		["beatsPowerbeatsLeft"] = 94031639892774,
		["beatsPowerbeatspro"] = 91388282815385,
		["beatsPowerbeatsproChargingcase"] = 129174227736582,
		["beatsPowerbeatsproLeft"] = 132454103156247,
		["beatsPowerbeatsproRight"] = 121014913156174,
		["beatsPowerbeatsRight"] = 139808468287937,
		["beatsStudiobudLeft"] = 123610938062441,
		["beatsStudiobudRight"] = 92812822483138,
		["beatsStudiobuds"] = 87614277962771,
		["beatsStudiobudsChargingcase"] = 136547753864530,
		["beatsStudiobudsplus"] = 71975225998517,
		["beatsStudiobudsplusChargingcase"] = 125879752007426,
		["beatsStudiobudsplusLeft"] = 111603577383991,
		["beatsStudiobudsplusRight"] = 118741913661751,
		["bedDouble"] = 126743498549074,
		["bedDoubleCircle"] = 93060808599688,
		["bell"] = 108730354061577,
		["bellAndWavesLeftAndRight"] = 135794959340299,
		["bellBadge"] = 126861827876338,
		["bellBadgeCircle"] = 120944439956890,
		["bellBadgeSlash"] = 97481645339034,
		["bellBadgeWaveform"] = 116078028991384,
		["bellCircle"] = 89781868535223,
		["bellSlash"] = 106134669703906,
		["bellSlashCircle"] = 82705838720523,
		["bellSquare"] = 120750810111193,
		["bicycle"] = 73108279549194,
		["bicycleCircle"] = 114098204063015,
		["binoculars"] = 113174504252721,
		["binocularsCircle"] = 109842784819874,
		["bird"] = 105045939393151,
		["birdCircle"] = 116806463752157,
		["birthdayCake"] = 121877168692995,
		["bitcoinsign"] = 111289432710524,
		["bitcoinsignCircle"] = 111900725194210,
		["bitcoinsignSquare"] = 102186923930539,
		["blindsHorizontalClosed"] = 131273464201939,
		["blindsHorizontalOpen"] = 80664504714325,
		["blindsVerticalClosed"] = 138542860108094,
		["blindsVerticalOpen"] = 97675169021680,
		["bold"] = 83774109857539,
		["boldItalicUnderline"] = 107993526243245,
		["boldUnderline"] = 116346273632115,
		["bolt"] = 77814408500232,
		["boltBadgeAutomatic"] = 73516208495655,
		["boltBadgeCheckmark"] = 92057948269674,
		["boltBadgeClock"] = 91664084918442,
		["boltBadgeXmark"] = 132991794262973,
		["boltBatteryblock"] = 127600797242051,
		["boltBrakesignal"] = 78092425535693,
		["boltCar"] = 122505580659266,
		["boltCarCircle"] = 99602827629942,
		["boltCircle"] = 104194065853669,
		["boltHeart"] = 74340142617776,
		["boltHorizontal"] = 140147034069655,
		["boltHorizontalCircle"] = 96064124853270,
		["boltHorizontalIcloud"] = 139269108237141,
		["boltRingClosed"] = 72946728121681,
		["boltShield"] = 101835060527618,
		["boltSlash"] = 72834901637431,
		["boltSlashCircle"] = 121063130817047,
		["boltSquare"] = 110722856720397,
		["boltTrianglebadgeExclamationmark"] = 95601421061653,
		["bonjour"] = 119338913505343,
		["book"] = 124521438156260,
		["bookAndWrench"] = 75665502438670,
		["bookCircle"] = 93034857300426,
		["bookClosed"] = 125163356428251,
		["bookClosedCircle"] = 102723323908022,
		["bookmark"] = 83006767513596,
		["bookmarkCircle"] = 87706305557149,
		["bookmarkSlash"] = 85980073948000,
		["bookmarkSquare"] = 128061657297278,
		["bookPages"] = 94438500659706,
		["booksVertical"] = 139165548005884,
		["booksVerticalCircle"] = 118418837844188,
		["brain"] = 129788246923948,
		["brainHeadProfile"] = 78520739010036,
		["brakesignal"] = 104910257831620,
		["brakesignalDashed"] = 135892472888282,
		["brazilianrealsign"] = 100249158064866,
		["brazilianrealsignCircle"] = 100582404893766,
		["brazilianrealsignSquare"] = 80811936202304,
		["briefcase"] = 124399879307020,
		["briefcaseCircle"] = 112640004758209,
		["bubble"] = 121181767293645,
		["bubbleCircle"] = 100446732387558,
		["bubbleLeft"] = 132260167571866,
		["bubbleLeftAndBubbleRight"] = 108345337858311,
		["bubbleLeftAndExclamationmarkBubbleRight"] = 98835807201120,
		["bubbleLeftAndTextBubbleRight"] = 80847191799259,
		["bubbleLeftCircle"] = 101780262453207,
		["bubbleMiddleBottom"] = 121682393260567,
		["bubbleMiddleTop"] = 128275401894534,
		["bubbleRight"] = 123596782040427,
		["bubbleRightCircle"] = 92487414704155,
		["bubblesAndSparkles"] = 100289524317057,
		["building"] = 74497526931655,
		["building2"] = 135140327189124,
		["building2CropCircle"] = 72550003313773,
		["buildingColumns"] = 108085258638798,
		["buildingColumnsCircle"] = 93580334594628,
		["burn"] = 89637301912553,
		["burst"] = 92440263503096,
		["bus"] = 115545056568030,
		["busDoubledecker"] = 82490981170964,
		["buttonAngledbottomHorizontalLeft"] = 112508711185074,
		["buttonAngledbottomHorizontalRight"] = 83042582871795,
		["buttonAngledtopVerticalLeft"] = 129728846581610,
		["buttonAngledtopVerticalRight"] = 79101463236867,
		["buttonHorizontal"] = 85760977216388,
		["buttonHorizontalTopPress"] = 85724854788946,
		["buttonProgrammable"] = 128094815365200,
		["buttonProgrammableSquare"] = 137938822603298,
		["buttonRoundedbottomHorizontal"] = 122394857086713,
		["buttonRoundedtopHorizontal"] = 135194862562191,
		["buttonVerticalLeftPress"] = 98503025569985,
		["buttonVerticalRightPress"] = 122635214533801,
		["cabinet"] = 81281632410063,
		["cablecar"] = 133177411473534,
		["cableCoaxial"] = 103420466609414,
		["cableConnector"] = 95250523182971,
		["cableConnectorHorizontal"] = 70561861308742,
		["calendar"] = 79737535968642,
		["calendarBadgeCheckmark"] = 92566052530481,
		["calendarBadgeClock"] = 133151027082077,
		["calendarBadgeExclamationmark"] = 103967581920764,
		["calendarBadgeMinus"] = 77213466439908,
		["calendarBadgePlus"] = 135617859505274,
		["calendarCircle"] = 139255178536196,
		["calendarDayTimelineLeading"] = 110169793705336,
		["calendarDayTimelineLeft"] = 83107748344167,
		["calendarDayTimelineRight"] = 128069220873510,
		["calendarDayTimelineTrailing"] = 94165568872184,
		["camera"] = 89945218134735,
		["cameraAperture"] = 121021899879686,
		["cameraBadgeClock"] = 90354003604291,
		["cameraBadgeEllipsis"] = 77877495990287,
		["cameraCircle"] = 117792452185137,
		["cameraFilters"] = 88884914634550,
		["cameraMacro"] = 121686355573677,
		["cameraMacroCircle"] = 132499999252329,
		["cameraMeteringCenterWeighted"] = 135180300846700,
		["cameraMeteringCenterWeightedAverage"] = 80836917877860,
		["cameraMeteringMatrix"] = 122445534316129,
		["cameraMeteringMultispot"] = 80813301305780,
		["cameraMeteringNone"] = 74827096541791,
		["cameraMeteringPartial"] = 112665922615550,
		["cameraMeteringSpot"] = 131215279883358,
		["cameraMeteringUnknown"] = 126456725091662,
		["cameraOnRectangle"] = 116668205210476,
		["cameraShutterButton"] = 79414983850348,
		["cameraViewfinder"] = 137705914346946,
		["candybarphone"] = 116310078266047,
		["capslock"] = 123582242109746,
		["capsule"] = 106985446772776,
		["capsulePortrait"] = 89385301062049,
		["captionsBubble"] = 89989991166798,
		["car"] = 115153742682128,
		["car2"] = 116564015801554,
		["carbonDioxideCloud"] = 133052361872033,
		["carbonMonoxideCloud"] = 131055011171872,
		["carCircle"] = 132581565652122,
		["carFerry"] = 104827520064780,
		["carFrontWavesDown"] = 71909428020274,
		["carFrontWavesUp"] = 121003264407064,
		["carRear"] = 90389088164488,
		["carRearAndCollisionRoadLane"] = 113072294097363,
		["carRearAndCollisionRoadLaneSlash"] = 95948320037424,
		["carRearAndTireMarks"] = 85848895837438,
		["carRearAndTireMarksSlash"] = 105424568839530,
		["carRearRoadLane"] = 126400036756316,
		["carRearRoadLaneDashed"] = 93490888998771,
		["carRearWavesUp"] = 80379521726788,
		["carrot"] = 128338494668133,
		["carseatLeft"] = 124545647301837,
		["carseatLeft1"] = 84991921100225,
		["carseatLeft2"] = 125508996576995,
		["carseatLeft3"] = 128807976947540,
		["carseatLeftAndHeatWaves"] = 89340686855058,
		["carseatLeftBackrestUpAndDown"] = 99156812446355,
		["carseatLeftFan"] = 85239862425416,
		["carseatLeftForwardAndBackward"] = 85883335040617,
		["carseatLeftMassage"] = 137727800253714,
		["carseatLeftUpAndDown"] = 112260720116054,
		["carseatRight"] = 72498729253038,
		["carseatRight1"] = 86480375690352,
		["carseatRight2"] = 96594379970529,
		["carseatRight3"] = 122376174266552,
		["carseatRightAndHeatWaves"] = 138333397539530,
		["carseatRightBackrestUpAndDown"] = 114831566768144,
		["carseatRightFan"] = 123689986058189,
		["carseatRightForwardAndBackward"] = 133004310755748,
		["carseatRightMassage"] = 117334096975830,
		["carseatRightUpAndDown"] = 70729000477643,
		["carSide"] = 109616461699485,
		["carSideAirCirculate"] = 73877967301036,
		["carSideAirFresh"] = 133762480386821,
		["carSideAndExclamationmark"] = 106343950431395,
		["carSideArrowtriangleDown"] = 73802432977067,
		["carSideArrowtriangleUp"] = 79548639152596,
		["carSideArrowtriangleUpArrowtriangleDown"] = 100048646452150,
		["carSideFrontOpen"] = 136367260185019,
		["carSideHillDown"] = 96457938763632,
		["carSideHillUp"] = 111323010786312,
		["carSideLock"] = 134729528233973,
		["carSideLockOpen"] = 135145360628317,
		["carSideRearAndCollisionAndCarSideFront"] = 120814411842447,
		["carSideRearAndCollisionAndCarSideFrontSlash"] = 90060210242892,
		["carSideRearAndExclamationmarkAndCarSideFront"] = 127169373734278,
		["carSideRearAndWave3AndCarSideFront"] = 95489511581489,
		["carSideRearOpen"] = 85197467865979,
		["cart"] = 71113964288896,
		["cartBadgeMinus"] = 83371939881266,
		["cartBadgePlus"] = 117262987573775,
		["cartBadgeQuestionmark"] = 78032512277063,
		["cartCircle"] = 95648168138395,
		["carTopDoorFrontLeftAndFrontRightAndRearLeftAndRearRightOpen"] = 108598631957590,
		["carTopDoorFrontLeftAndFrontRightAndRearLeftOpen"] = 130484365029093,
		["carTopDoorFrontLeftAndFrontRightAndRearRightOpen"] = 101557881323023,
		["carTopDoorFrontLeftAndFrontRightOpen"] = 132390047435333,
		["carTopDoorFrontLeftAndRearLeftAndRearRightOpen"] = 78637858995180,
		["carTopDoorFrontLeftAndRearLeftOpen"] = 77496058782553,
		["carTopDoorFrontLeftAndRearRightOpen"] = 70934670701281,
		["carTopDoorFrontLeftOpen"] = 83046254227023,
		["carTopDoorFrontRightAndRearLeftAndRearRightOpen"] = 130499786065614,
		["carTopDoorFrontRightAndRearLeftOpen"] = 83329821885376,
		["carTopDoorFrontRightAndRearRightOpen"] = 137845766165561,
		["carTopDoorFrontRightOpen"] = 101010465641416,
		["carTopDoorRearLeftAndRearRightOpen"] = 140635292616652,
		["carTopDoorRearLeftOpen"] = 92523230565215,
		["carTopDoorRearRightOpen"] = 77498034305859,
		["carTopDoorSlidingLeftOpen"] = 131575928322126,
		["carTopDoorSlidingRightOpen"] = 96829472136151,
		["carTopFrontleftArrowtriangle"] = 74249929591233,
		["carTopFrontrightArrowtriangle"] = 109439050535736,
		["carTopLaneDashedArrowtriangleInward"] = 107753556864574,
		["carTopLaneDashedBadgeSteeringwheel"] = 88219271332073,
		["carTopLaneDashedDepartureLeft"] = 70900086945448,
		["carTopLaneDashedDepartureRight"] = 118329210410561,
		["carTopRadiowavesFront"] = 78359206006645,
		["carTopRadiowavesRear"] = 95204667543944,
		["carTopRadiowavesRearLeft"] = 80735865854484,
		["carTopRadiowavesRearLeftAndRearRight"] = 123738562081264,
		["carTopRadiowavesRearRight"] = 108911165934290,
		["carTopRadiowavesRearRightBadgeExclamationmark"] = 125767316989449,
		["carTopRadiowavesRearRightBadgeXmark"] = 119234831010228,
		["carTopRearleftArrowtriangle"] = 132477167189845,
		["carTopRearrightArrowtriangle"] = 121164497326761,
		["carWindowLeft"] = 70748317264596,
		["carWindowLeftBadgeExclamationmark"] = 128276495074253,
		["carWindowLeftBadgeXmark"] = 79678942064243,
		["carWindowLeftExclamationmark"] = 82765470370277,
		["carWindowLeftXmark"] = 120073506868750,
		["carWindowRight"] = 104730160216324,
		["carWindowRightBadgeExclamationmark"] = 103368616894295,
		["carWindowRightBadgeXmark"] = 115233984600523,
		["carWindowRightExclamationmark"] = 125449141066791,
		["carWindowRightXmark"] = 105589769492092,
		["caseGylph"] = 72684442825623,
		["cat"] = 86250189983975,
		["catCircle"] = 116692607667199,
		["cedisign"] = 138194758451812,
		["cedisignCircle"] = 70892433228320,
		["cedisignSquare"] = 114577853488285,
		["cellularbars"] = 118727231524691,
		["centsign"] = 113858962126518,
		["centsignCircle"] = 78942375468913,
		["centsignSquare"] = 109963001152676,
		["chair"] = 99351023008668,
		["chairLounge"] = 124785536550390,
		["chandelier"] = 97485955489896,
		["character"] = 114226612873891,
		["characterBookClosed"] = 103867459841635,
		["characterBubble"] = 106288947807251,
		["characterCursorIbeam"] = 139717327157810,
		["characterDuployan"] = 126435179210700,
		["characterMagnify"] = 131262156040245,
		["characterPhonetic"] = 71143117808156,
		["characterSutton"] = 85613883152868,
		["characterTextbox"] = 138841230915690,
		["chartBar"] = 120914655002595,
		["chartBarDocHorizontal"] = 88206449206082,
		["chartBarXaxis"] = 95434020393724,
		["chartBarXaxisAscending"] = 137366011712039,
		["chartBarXaxisAscendingBadgeClock"] = 127422554007788,
		["chartDotsScatter"] = 137901928504735,
		["chartLineDowntrendXyaxis"] = 94170918152103,
		["chartLineDowntrendXyaxisCircle"] = 72965720912136,
		["chartLineFlattrendXyaxis"] = 124173279630795,
		["chartLineFlattrendXyaxisCircle"] = 129203535753585,
		["chartLineUptrendXyaxis"] = 91058186938159,
		["chartLineUptrendXyaxisCircle"] = 88433500523242,
		["chartPie"] = 118850574017813,
		["chartXyaxisLine"] = 71242960230090,
		["checklist"] = 96123412349358,
		["checklistChecked"] = 122249488419579,
		["checklistUnchecked"] = 134179298991627,
		["checkmark"] = 80083151652572,
		["checkmarkApplewatch"] = 110475735660132,
		["checkmarkBubble"] = 95299383343238,
		["checkmarkCircle"] = 121827912892409,
		["checkmarkCircleBadgeQuestionmark"] = 109911703727305,
		["checkmarkCircleBadgeXmark"] = 125191621241355,
		["checkmarkCircleTrianglebadgeExclamationmark"] = 102919651395256,
		["checkmarkDiamond"] = 81113321311196,
		["checkmarkGobackward"] = 137921605172447,
		["checkmarkIcloud"] = 135240021766953,
		["checkmarkMessage"] = 99999620075692,
		["checkmarkRectangle"] = 134026532600049,
		["checkmarkRectanglePortrait"] = 128354501518090,
		["checkmarkRectangleStack"] = 126501144040860,
		["checkmarkSeal"] = 76205965014688,
		["checkmarkShield"] = 128784966069296,
		["checkmarkSquare"] = 125568270907833,
		["chevronBackward"] = 127673100954233,
		["chevronBackward2"] = 112420395416746,
		["chevronBackwardCircle"] = 120258319549735,
		["chevronBackwardSquare"] = 103813658867200,
		["chevronBackwardToLine"] = 73724127355493,
		["chevronCompactDown"] = 123343315778119,
		["chevronCompactLeft"] = 139766380434950,
		["chevronCompactRight"] = 120598715794326,
		["chevronCompactUp"] = 113243988937759,
		["chevronDown"] = 99166577372338,
		["chevronDownCircle"] = 138287742474054,
		["chevronDownSquare"] = 127265632433023,
		["chevronForward"] = 94291254481690,
		["chevronForward2"] = 97296978339607,
		["chevronForwardCircle"] = 90929840523469,
		["chevronForwardSquare"] = 94543441555166,
		["chevronForwardToLine"] = 97974884959841,
		["chevronLeft"] = 117321898070552,
		["chevronLeft2"] = 108003712086139,
		["chevronLeftCircle"] = 76379402917087,
		["chevronLeftForwardslashChevronRight"] = 111664725689720,
		["chevronLeftSquare"] = 80698792237138,
		["chevronLeftToLine"] = 79628568689866,
		["chevronRight"] = 109778622420693,
		["chevronRight2"] = 78199972337874,
		["chevronRightCircle"] = 105626450271578,
		["chevronRightSquare"] = 90408944876173,
		["chevronRightToLine"] = 124411396279525,
		["chevronUp"] = 95197501590678,
		["chevronUpChevronDown"] = 119655894508741,
		["chevronUpCircle"] = 81279484459134,
		["chevronUpSquare"] = 95431538878093,
		["chineseyuanrenminbisign"] = 75882360999685,
		["chineseyuanrenminbisignCircle"] = 135786634031595,
		["chineseyuanrenminbisignSquare"] = 79544727771157,
		["circle"] = 74410186179968,
		["circleAndLineHorizontal"] = 92654051225554,
		["circlebadge"] = 126366967492086,
		["circlebadge2"] = 116487408579648,
		["circleBadgeCheckmark"] = 118978624242448,
		["circleBadgeExclamationmark"] = 130393081242396,
		["circleBadgeMinus"] = 124877272219219,
		["circleBadgePlus"] = 118985536139784,
		["circleBadgeQuestionmark"] = 111471516894446,
		["circleBadgeXmark"] = 111853652482990,
		["circleBottomrighthalfCheckered"] = 122575558098594,
		["circleCircle"] = 103394163979695,
		["circleDashed"] = 136105292255368,
		["circleDashedRectangle"] = 85645366423225,
		["circleDotted"] = 95633055010341,
		["circleDottedAndCircle"] = 122294143799868,
		["circleDottedCircle"] = 99752875727555,
		["circleGrid2x1"] = 84143860653224,
		["circleGrid2x2"] = 139778243806459,
		["circleGrid3x3"] = 120098734006282,
		["circleGrid3x3Circle"] = 130310006903024,
		["circleGridCross"] = 123340667472948,
		["circleHexagongrid"] = 78813009330205,
		["circleHexagongridCircle"] = 106106095478285,
		["circleHexagonpath"] = 134952566153330,
		["circleLefthalfStripedHorizontal"] = 92754097690861,
		["circleLefthalfStripedHorizontalInverse"] = 120946268346026,
		["circleRectangleDashed"] = 79965725599780,
		["circleSlash"] = 102561151406059,
		["circleSquare"] = 82264224373098,
		["clear"] = 112156642973884,
		["clipboard"] = 81027244001527,
		["clock"] = 71865878247301,
		["clockArrow2Circlepath"] = 120448260426448,
		["clockArrowCirclepath"] = 83500708276723,
		["clockBadge"] = 95543881222190,
		["clockBadgeCheckmark"] = 110889511043247,
		["clockBadgeExclamationmark"] = 96219827415804,
		["clockBadgeQuestionmark"] = 121937201035118,
		["clockBadgeXmark"] = 100578139064509,
		["clockCircle"] = 104879643385324,
		["cloud"] = 72439815109377,
		["cloudBolt"] = 138545210167719,
		["cloudBoltCircle"] = 113867033834751,
		["cloudBoltRain"] = 82572191900241,
		["cloudBoltRainCircle"] = 71520224958159,
		["cloudCircle"] = 138009396818670,
		["cloudDrizzle"] = 101174065846367,
		["cloudDrizzleCircle"] = 134490921738321,
		["cloudFog"] = 135490835996578,
		["cloudFogCircle"] = 116570711195787,
		["cloudHail"] = 92728162041412,
		["cloudHailCircle"] = 128302721450852,
		["cloudHeavyrain"] = 132393131962904,
		["cloudHeavyrainCircle"] = 131787242867470,
		["cloudMoon"] = 128637077638309,
		["cloudMoonBolt"] = 90404966526640,
		["cloudMoonBoltCircle"] = 88637087433527,
		["cloudMoonCircle"] = 71510329303583,
		["cloudMoonRain"] = 86226283847488,
		["cloudMoonRainCircle"] = 135271835175143,
		["cloudRain"] = 137913324435715,
		["cloudRainbowHalf"] = 80949891966526,
		["cloudRainCircle"] = 125770718460295,
		["cloudSleet"] = 138740371048571,
		["cloudSleetCircle"] = 108186361674214,
		["cloudSnow"] = 105959993072064,
		["cloudSnowCircle"] = 94353656591244,
		["cloudSun"] = 76219717200572,
		["cloudSunBolt"] = 82434887608964,
		["cloudSunBoltCircle"] = 121980548748043,
		["cloudSunCircle"] = 138030869492942,
		["cloudSunRain"] = 134074736472532,
		["cloudSunRainCircle"] = 137383261943827,
		["coloncurrencysign"] = 131140994393008,
		["coloncurrencysignCircle"] = 70944403095065,
		["coloncurrencysignSquare"] = 73629414426424,
		["comb"] = 130067018388344,
		["command"] = 87759558375295,
		["commandCircle"] = 108217555020959,
		["commandSquare"] = 107055043334206,
		["compassDrawing"] = 134681338415164,
		["computermouse"] = 116864473507298,
		["cone"] = 124587204416297,
		["contactSensor"] = 102690488068099,
		["contextualmenuAndCursorarrow"] = 123228274012415,
		["control"] = 97239100115918,
		["cooktop"] = 93215843989191,
		["cpu"] = 87589615309566,
		["creditcard"] = 77524266713323,
		["creditcardAnd123"] = 87625010126625,
		["creditcardCircle"] = 99286306323174,
		["creditcardTrianglebadgeExclamationmark"] = 90236628566099,
		["creditcardViewfinder"] = 128954685381450,
		["cricketBall"] = 132338647483230,
		["cricketBallCircle"] = 112380861010223,
		["crop"] = 138327728447328,
		["cropRotate"] = 121012418950102,
		["cross"] = 75739153896374,
		["crossCase"] = 78079423098645,
		["crossCaseCircle"] = 137234921754938,
		["crossCircle"] = 117192023436084,
		["crossVial"] = 115154605300684,
		["crown"] = 107058160728845,
		["cruzeirosign"] = 106216304865538,
		["cruzeirosignCircle"] = 98155899113585,
		["cruzeirosignSquare"] = 112549175142358,
		["cube"] = 113324099127598,
		["cubeTransparent"] = 78558225501795,
		["cupAndSaucer"] = 70882561472053,
		["curlybraces"] = 122379752309193,
		["curlybracesSquare"] = 108806416027883,
		["cursorarrow"] = 76353347413637,
		["cursorarrowAndSquareOnSquareDashed"] = 123035396911468,
		["cursorarrowClick"] = 120755931811218,
		["cursorarrowClick2"] = 131954684779465,
		["cursorarrowClickBadgeClock"] = 96674815416136,
		["cursorarrowMotionlines"] = 117420120397428,
		["cursorarrowMotionlinesClick"] = 81573780818011,
		["cursorarrowRays"] = 126392116415147,
		["cursorarrowSlash"] = 91144329352020,
		["cursorarrowSlashSquare"] = 95513304668296,
		["cursorarrowSquare"] = 131316405162767,
		["curtainsClosed"] = 122945237141959,
		["curtainsOpen"] = 122698824186293,
		["cylinder"] = 114645416111348,
		["cylinderSplit1x2"] = 85943184592349,
		["danishkronesign"] = 132317859196237,
		["danishkronesignCircle"] = 96037553795865,
		["danishkronesignSquare"] = 98413802386021,
		["decreaseIndent"] = 114166951637598,
		["decreaseQuotelevel"] = 122987348583660,
		["dehumidifier"] = 133596695507827,
		["deleteBackward"] = 97790611923098,
		["deleteForward"] = 108241377729036,
		["deleteLeft"] = 90957127933134,
		["deleteRight"] = 81407575985610,
		["deskclock"] = 100063925348875,
		["desktopcomputer"] = 96859406924780,
		["desktopcomputerAndArrowDown"] = 129425011002064,
		["desktopcomputerTrianglebadgeExclamationmark"] = 77859158998904,
		["deskview"] = 113833580070691,
		["dialHigh"] = 75770110909347,
		["dialLow"] = 111908632839614,
		["dialMedium"] = 103296321412929,
		["diamond"] = 98755623140060,
		["diamondCircle"] = 75496260365440,
		["dice"] = 79901563934016,
		["dieFace1"] = 97973837927564,
		["dieFace2"] = 97103901429519,
		["dieFace3"] = 74553149585882,
		["dieFace4"] = 107085806823827,
		["dieFace5"] = 105681650712833,
		["dieFace6"] = 111952413902020,
		["digitalcrownArrowClockwise"] = 99697391718088,
		["digitalcrownArrowCounterclockwise"] = 79014014935970,
		["digitalcrownHorizontalArrowClockwise"] = 101662260300961,
		["digitalcrownHorizontalArrowCounterclockwise"] = 89143641561402,
		["digitalcrownHorizontalPress"] = 70865991094071,
		["digitalcrownPress"] = 100235041582512,
		["directcurrent"] = 123771305124455,
		["dishwasher"] = 130920646838171,
		["dishwasherCircle"] = 76935618125226,
		["display"] = 75167987039384,
		["display2"] = 111139979103041,
		["displayAndArrowDown"] = 90569241422518,
		["displayTrianglebadgeExclamationmark"] = 100356722210963,
		["distributeHorizontalCenter"] = 133563584737123,
		["distributeHorizontalLeft"] = 97346698660085,
		["distributeHorizontalRight"] = 125138096691204,
		["distributeVerticalBottom"] = 97606841865015,
		["distributeVerticalCenter"] = 140714241241921,
		["distributeVerticalTop"] = 114880541014379,
		["divide"] = 113308977415214,
		["divideCircle"] = 117656594502455,
		["divideSquare"] = 83099420768337,
		["doc"] = 80680488161934,
		["docAppend"] = 92502742629439,
		["docBadgeArrowUp"] = 80297421254328,
		["docBadgeClock"] = 106217049362270,
		["docBadgeEllipsis"] = 131787139108704,
		["docBadgeGearshape"] = 75017579898518,
		["docBadgePlus"] = 124537298304533,
		["docCircle"] = 114937888569701,
		["dockArrowDownRectangle"] = 72021890628584,
		["dockArrowUpRectangle"] = 116152143083972,
		["dockRectangle"] = 76782381671460,
		["docOnClipboard"] = 94277113748864,
		["docOnDoc"] = 74221368188325,
		["docPlaintext"] = 116104151169652,
		["docRichtext"] = 94749196343692,
		["docText"] = 106048817459549,
		["docTextBelowEcg"] = 111731877748125,
		["docTextImage"] = 122105011236494,
		["docTextMagnifyingglass"] = 86983114420254,
		["docViewfinder"] = 137034209283570,
		["docZipper"] = 96676285483415,
		["dog"] = 140572982890767,
		["dogCircle"] = 122395060321313,
		["dollarsign"] = 109669077542924,
		["dollarsignArrowCirclepath"] = 111141236452341,
		["dollarsignCircle"] = 80248987427627,
		["dollarsignSquare"] = 104039678975004,
		["dongsign"] = 107964991032390,
		["dongsignCircle"] = 82390177440942,
		["dongsignSquare"] = 135476238812943,
		["doorFrenchClosed"] = 115590490197965,
		["doorFrenchOpen"] = 121469591613419,
		["doorGarageClosed"] = 106034477525186,
		["doorGarageClosedTrianglebadgeExclamationmark"] = 106064431783267,
		["doorGarageDoubleBayClosed"] = 77708115686304,
		["doorGarageDoubleBayClosedTrianglebadgeExclamationmark"] = 90250572170703,
		["doorGarageDoubleBayOpen"] = 99872177348788,
		["doorGarageDoubleBayOpenTrianglebadgeExclamationmark"] = 89179536238976,
		["doorGarageOpen"] = 100261874181752,
		["doorGarageOpenTrianglebadgeExclamationmark"] = 129676177042694,
		["doorLeftHandClosed"] = 127332916375130,
		["doorLeftHandOpen"] = 88478617958400,
		["doorRightHandClosed"] = 90865411752842,
		["doorRightHandOpen"] = 120226629467300,
		["doorSlidingLeftHandClosed"] = 104460639241760,
		["doorSlidingLeftHandOpen"] = 90434437684846,
		["doorSlidingRightHandClosed"] = 80954533274056,
		["doorSlidingRightHandOpen"] = 107047945884408,
		["dotArrowtrianglesUpRightDownLeftCircle"] = 92171085368638,
		["dotCircleAndCursorarrow"] = 115122421262820,
		["dotCircleViewfinder"] = 76791877752769,
		["dotRadiowavesForward"] = 125958365101126,
		["dotRadiowavesLeftAndRight"] = 125089665001336,
		["dotRadiowavesRight"] = 134899456728459,
		["dotRadiowavesUpForward"] = 89160672441436,
		["dotsAndLineVerticalAndCursorarrowRectangle"] = 82575719013218,
		["dotSquare"] = 93040404947406,
		["dotSquareshape"] = 71756482462243,
		["dotSquareshapeSplit2x2"] = 122291530539759,
		["dotViewfinder"] = 116893339458370,
		["dpad"] = 87682605776106,
		["drop"] = 111642008758112,
		["dropCircle"] = 72183646280977,
		["dropDegreesign"] = 101079401640724,
		["dropDegreesignSlash"] = 77370786202614,
		["dropHalffull"] = 106217001834494,
		["dropKeypadRectangle"] = 71258286014229,
		["dropTransmission"] = 121675820611513,
		["dropTriangle"] = 98703665707348,
		["dryer"] = 100248519786703,
		["dryerCircle"] = 127979000291506,
		["dumbbell"] = 116727072092392,
		["ear"] = 76035901479639,
		["earBadgeCheckmark"] = 91787437407196,
		["earBadgeWaveform"] = 135033697589671,
		["earbuds"] = 116995008079922,
		["earbudsCase"] = 87434619318458,
		["earpods"] = 73551661527717,
		["earTrianglebadgeExclamationmark"] = 121508208509561,
		["eject"] = 105034421093103,
		["ejectCircle"] = 71243734846382,
		["ellipsis"] = 77216475856263,
		["ellipsisBubble"] = 81757807051403,
		["ellipsisCircle"] = 99199083887688,
		["ellipsisCurlybraces"] = 108569164111258,
		["ellipsisMessage"] = 114344761995567,
		["ellipsisRectangle"] = 129501243800814,
		["ellipsisVerticalBubble"] = 90497496915411,
		["ellipsisViewfinder"] = 126002018966475,
		["engineCombustion"] = 131885131929586,
		["engineCombustionBadgeExclamationmark"] = 85947213993940,
		["entryLeverKeypad"] = 105656001411388,
		["entryLeverKeypadTrianglebadgeExclamationmark"] = 102460548449598,
		["envelope"] = 135422700018555,
		["envelopeArrowTriangleBranch"] = 124377309512740,
		["envelopeBadge"] = 103845751654589,
		["envelopeBadgePersonCrop"] = 77560437146295,
		["envelopeCircle"] = 134475749846380,
		["envelopeOpen"] = 136933873070357,
		["envelopeOpenBadgeClock"] = 107286443232372,
		["equal"] = 104261784698979,
		["equalCircle"] = 94173011590634,
		["equalSquare"] = 92317829899624,
		["eraser"] = 95305220254055,
		["eraserLineDashed"] = 96768889006093,
		["escape"] = 88241911322694,
		["esim"] = 77580602275303,
		["eurosign"] = 136356099634353,
		["eurosignCircle"] = 126918102604088,
		["eurosignSquare"] = 116000285709817,
		["eurozonesign"] = 93139449983402,
		["eurozonesignCircle"] = 87247460844999,
		["eurozonesignSquare"] = 129461749044283,
		["evCharger"] = 79556138542907,
		["evChargerArrowtriangleLeft"] = 119824246559477,
		["evChargerArrowtriangleRight"] = 126528173588647,
		["evChargerExclamationmark"] = 102012721466143,
		["evChargerSlash"] = 99276226601989,
		["evPlugAcGbT"] = 123710740255487,
		["evPlugAcType1"] = 99601941122060,
		["evPlugAcType2"] = 135993885168737,
		["evPlugDcCcs1"] = 96871163987413,
		["evPlugDcCcs2"] = 133131308191446,
		["evPlugDcChademo"] = 91501489271555,
		["evPlugDcGbT"] = 131449273570632,
		["evPlugDcNacs"] = 138621271016511,
		["exclamationmark"] = 123140835548673,
		["exclamationmark2"] = 75679665682282,
		["exclamationmark3"] = 94835741243894,
		["exclamationmarkApplewatch"] = 131402916699982,
		["exclamationmarkArrowCirclepath"] = 111446640991646,
		["exclamationmarkArrowTriangle2Circlepath"] = 121048701816249,
		["exclamationmarkBrakesignal"] = 91423055094258,
		["exclamationmarkBubble"] = 105426640441082,
		["exclamationmarkBubbleCircle"] = 140043827963868,
		["exclamationmarkCircle"] = 92439494359035,
		["exclamationmarkIcloud"] = 131750039428036,
		["exclamationmarkLock"] = 71368682685575,
		["exclamationmarkOctagon"] = 123387035798080,
		["exclamationmarkQuestionmark"] = 114232460979754,
		["exclamationmarkShield"] = 102928689678762,
		["exclamationmarkSquare"] = 90730727329485,
		["exclamationmarkTirepressure"] = 111652449176889,
		["exclamationmarkTransmission"] = 84123174580190,
		["exclamationmarkTriangle"] = 106021451924989,
		["exclamationmarkWarninglight"] = 84262825388416,
		["externaldrive"] = 120236805690488,
		["externaldriveBadgeCheckmark"] = 70712203348861,
		["externaldriveBadgeExclamationmark"] = 77017834633822,
		["externaldriveBadgeIcloud"] = 86180483675834,
		["externaldriveBadgeMinus"] = 75906682662471,
		["externaldriveBadgePersonCrop"] = 94868100647171,
		["externaldriveBadgePlus"] = 92651555219115,
		["externaldriveBadgeQuestionmark"] = 125099541780510,
		["externaldriveBadgeTimemachine"] = 111351777977541,
		["externaldriveBadgeWifi"] = 109165399503090,
		["externaldriveBadgeXmark"] = 125875178687284,
		["externaldriveConnectedToLineBelow"] = 112872241937256,
		["externaldriveTrianglebadgeExclamationmark"] = 71483990859238,
		["eye"] = 138470672816964,
		["eyebrow"] = 135171080166572,
		["eyeCircle"] = 138323405545081,
		["eyedropper"] = 118390984141654,
		["eyedropperFull"] = 105807600321254,
		["eyedropperHalffull"] = 121173088005138,
		["eyeglasses"] = 73685932692008,
		["eyeglassesSlash"] = 88818268210473,
		["eyes"] = 118899102922882,
		["eyesInverse"] = 93009022157585,
		["eyeSlash"] = 91677658237967,
		["eyeSlashCircle"] = 126482458192010,
		["eyeSquare"] = 123952861895885,
		["eyeTrianglebadgeExclamationmark"] = 95629223399861,
		["faceDashed"] = 102614227688607,
		["faceid"] = 95982198583714,
		["facemask"] = 80851101613761,
		["faceSmiling"] = 73031260403382,
		["faceSmilingInverse"] = 98365509137544,
		["fan"] = 125371771993888,
		["fanAndLightCeiling"] = 126784674387812,
		["fanBadgeAutomatic"] = 121503027473712,
		["fanCeiling"] = 124559414278240,
		["fanDesk"] = 126417457946871,
		["fanFloor"] = 85469961697628,
		["fanOscillation"] = 71303317357784,
		["fanSlash"] = 92778825024012,
		["faxmachine"] = 100326873282556,
		["ferry"] = 121251155343877,
		["fibrechannel"] = 90895493471592,
		["fieldOfViewUltrawide"] = 81839418625368,
		["fieldOfViewWide"] = 136944686072143,
		["figure"] = 124210592176929,
		["figure2"] = 139132362873473,
		["figure2AndChildHoldinghands"] = 105110831438422,
		["figure2ArmsOpen"] = 70979576402718,
		["figure2Circle"] = 72262299949069,
		["figureAmericanFootball"] = 126882844996991,
		["figureAndChildHoldinghands"] = 128184365089297,
		["figureArchery"] = 93902013631670,
		["figureArmsOpen"] = 105660776949905,
		["figureAustralianFootball"] = 97813783388963,
		["figureBadminton"] = 73181260188357,
		["figureBarre"] = 85880551540473,
		["figureBaseball"] = 130108782246517,
		["figureBasketball"] = 128808469126544,
		["figureBowling"] = 112929888815227,
		["figureBoxing"] = 107712089903705,
		["figureChild"] = 130972091582571,
		["figureChildAndLock"] = 137851062454246,
		["figureChildAndLockOpen"] = 105149521674659,
		["figureChildCircle"] = 95811955832285,
		["figureClimbing"] = 128133423006685,
		["figureCooldown"] = 135219375145537,
		["figureCoreTraining"] = 83820740613832,
		["figureCricket"] = 112539492344674,
		["figureCrossTraining"] = 87648383986794,
		["figureCurling"] = 96833980986058,
		["figureDance"] = 117059550991943,
		["figureDiscSports"] = 132589592587251,
		["figureDressLineVerticalFigure"] = 100940012571116,
		["figureElliptical"] = 99650888567647,
		["figureEquestrianSports"] = 86059488055849,
		["figureFall"] = 100202475660961,
		["figureFallCircle"] = 96928098825680,
		["figureFencing"] = 129126904429160,
		["figureFishing"] = 111765160362879,
		["figureFlexibility"] = 132776843430665,
		["figureGolf"] = 92214790721841,
		["figureGymnastics"] = 138567055276067,
		["figureHandball"] = 96660474278951,
		["figureHandCycling"] = 138507015290592,
		["figureHighintensityIntervaltraining"] = 73401395867175,
		["figureHiking"] = 97548427005732,
		["figureHockey"] = 91386080555336,
		["figureHunting"] = 85543734308109,
		["figureIndoorCycle"] = 93376649335246,
		["figureJumprope"] = 136263293348295,
		["figureKickboxing"] = 130136587320083,
		["figureLacrosse"] = 94034254784117,
		["figureMartialArts"] = 105181192399282,
		["figureMindAndBody"] = 102796026083961,
		["figureMixedCardio"] = 90474695143116,
		["figureOpenWaterSwim"] = 97359834860506,
		["figureOutdoorCycle"] = 126672021170079,
		["figurePickleball"] = 96334506833011,
		["figurePilates"] = 140491276895800,
		["figurePlay"] = 101368145480192,
		["figurePoolSwim"] = 139271073007059,
		["figureRacquetball"] = 118844109971027,
		["figureRoll"] = 88477472972731,
		["figureRolling"] = 88476186859346,
		["figureRollRunningpace"] = 79868941671699,
		["figureRower"] = 101478600974292,
		["figureRugby"] = 98478654484690,
		["figureRun"] = 124566141570199,
		["figureRunCircle"] = 96855548794052,
		["figureRunSquareStack"] = 114133664599268,
		["figureSailing"] = 137032787787986,
		["figureSeatedSeatbelt"] = 133384463233836,
		["figureSeatedSeatbeltAndAirbagOff"] = 96721597477065,
		["figureSeatedSeatbeltAndAirbagOn"] = 118056777273996,
		["figureSeatedSide"] = 103157176969588,
		["figureSeatedSideAirbagOff"] = 104984860910066,
		["figureSeatedSideAirbagOff2"] = 123574096899524,
		["figureSeatedSideAirbagOn"] = 112751749735103,
		["figureSeatedSideAirbagOn2"] = 133224719349931,
		["figureSeatedSideAirDistributionLower"] = 120257665940386,
		["figureSeatedSideAirDistributionMiddle"] = 92433515109818,
		["figureSeatedSideAirDistributionMiddleAndLower"] = 118216495126795,
		["figureSeatedSideAirDistributionMiddleAndLowerAngled"] = 132877218661072,
		["figureSeatedSideAirDistributionUpper"] = 80332126775420,
		["figureSeatedSideAirDistributionUpperAngledAndLowerAngled"] = 128830311959827,
		["figureSeatedSideAirDistributionUpperAngledAndMiddle"] = 110778248234270,
		["figureSeatedSideAirDistributionUpperAngledAndMiddleAndLowerAngled"] = 112235343241027,
		["figureSeatedSideAutomatic"] = 136215915659039,
		["figureSeatedSideWindshieldFrontAndHeatWaves"] = 87077410641628,
		["figureSeatedSideWindshieldFrontAndHeatWavesAirDistributionLower"] = 95211211764474,
		["figureSeatedSideWindshieldFrontAndHeatWavesAirDistributionMiddle"] = 79055808238898,
		["figureSeatedSideWindshieldFrontAndHeatWavesAirDistributionMiddleAndLower"] = 95139994219690,
		["figureSeatedSideWindshieldFrontAndHeatWavesAirDistributionUpper"] = 112780319350991,
		["figureSeatedSideWindshieldFrontAndHeatWavesAirDistributionUpperAndLower"] = 118828536958349,
		["figureSeatedSideWindshieldFrontAndHeatWavesAirDistributionUpperAndMiddle"] = 117604588619581,
		["figureSeatedSideWindshieldFrontAndHeatWavesAirDistributionUpperAndMiddleAndLower"] = 133887310459410,
		["figureSkating"] = 131519789461691,
		["figureSkiingCrosscountry"] = 109466747599943,
		["figureSkiingDownhill"] = 140392631123789,
		["figureSnowboarding"] = 134055706340887,
		["figureSoccer"] = 116190117656300,
		["figureSocialdance"] = 110405320778957,
		["figureSoftball"] = 97680142485776,
		["figureSquash"] = 109987323082963,
		["figureStairs"] = 119472344590394,
		["figureStairStepper"] = 102517804783821,
		["figureStand"] = 136221195306106,
		["figureStandLineDottedFigureStand"] = 110619836250430,
		["figureStepTraining"] = 84477171821852,
		["figureStrengthtrainingFunctional"] = 104048412669475,
		["figureStrengthtrainingTraditional"] = 138784898800398,
		["figureSurfing"] = 83044521165737,
		["figureTableTennis"] = 112539865230350,
		["figureTaichi"] = 111801226705681,
		["figureTennis"] = 117271917367811,
		["figureTrackAndField"] = 137096520282183,
		["figureVolleyball"] = 74388368898391,
		["figureWalk"] = 103110169492468,
		["figureWalkArrival"] = 132785672648822,
		["figureWalkCircle"] = 73018858953327,
		["figureWalkDeparture"] = 92487952988888,
		["figureWalkDiamond"] = 92350130943679,
		["figureWalkMotion"] = 120593776733345,
		["figureWalkMotionTrianglebadgeExclamationmark"] = 101645821918157,
		["figureWaterFitness"] = 96614205937760,
		["figureWaterpolo"] = 91412710561700,
		["figureWave"] = 114134027406795,
		["figureWaveCircle"] = 120321972281760,
		["figureWrestling"] = 83176353465102,
		["figureYoga"] = 96242701314139,
		["filemenuAndCursorarrow"] = 103877132330792,
		["filemenuAndSelection"] = 81852472789474,
		["film"] = 139278965589106,
		["filmCircle"] = 111466196163243,
		["filmStack"] = 105407775312941,
		["fireplace"] = 134966411587948,
		["firewall"] = 114840190064977,
		["fireworks"] = 114777713958614,
		["fish"] = 95630600389657,
		["fishCircle"] = 75389797082516,
		["flag"] = 102363227837340,
		["flag2Crossed"] = 70682050300398,
		["flag2CrossedCircle"] = 126304171890647,
		["flagBadgeEllipsis"] = 78600854244026,
		["flagCheckered"] = 78821229595515,
		["flagCheckered2Crossed"] = 78412090520637,
		["flagCheckeredCircle"] = 123648433572775,
		["flagCircle"] = 85706804053151,
		["flagSlash"] = 89297263331746,
		["flagSlashCircle"] = 94426163465898,
		["flagSquare"] = 137440369468694,
		["flame"] = 110230166553578,
		["flameCircle"] = 71866528782393,
		["flashlightOffCircle"] = 137828518876290,
		["flashlightOnCircle"] = 138372723792697,
		["flashlightSlash"] = 137595008121368,
		["flashlightSlashCircle"] = 100149592723764,
		["flask"] = 84982251579563,
		["fleuron"] = 127254498069507,
		["flipphone"] = 121655288668724,
		["florinsign"] = 85198379296878,
		["florinsignCircle"] = 91968364679095,
		["florinsignSquare"] = 124557685313833,
		["flowchart"] = 76502922913770,
		["fluidBrakesignal"] = 106945535029492,
		["fluidTransmission"] = 106920308433404,
		["fn"] = 110984852514729,
		["folder"] = 115997264836727,
		["folderBadgeGearshape"] = 130851892723979,
		["folderBadgeMinus"] = 135738422209124,
		["folderBadgePersonCrop"] = 95982372409592,
		["folderBadgePlus"] = 114979073485854,
		["folderBadgeQuestionmark"] = 107424384579367,
		["folderCircle"] = 117008504066827,
		["football"] = 99824306110508,
		["footballCircle"] = 82719329435185,
		["forkKnife"] = 104969007607141,
		["forkKnifeCircle"] = 90290316044160,
		["forward"] = 95245574750012,
		["forwardCircle"] = 126501657617147,
		["forwardEnd"] = 132223524998425,
		["forwardEndAlt"] = 121503429886100,
		["forwardEndCircle"] = 138908494671044,
		["forwardFrame"] = 88008148795157,
		["fossilShell"] = 93224289967262,
		["francsign"] = 81293763334250,
		["francsignCircle"] = 139095444943390,
		["francsignSquare"] = 85547004298688,
		["fryingPan"] = 81228964166221,
		["fuelpump"] = 98986287945777,
		["fuelpumpArrowtriangleLeft"] = 94434558902102,
		["fuelpumpArrowtriangleRight"] = 131571623639889,
		["fuelpumpCircle"] = 84672225297380,
		["fuelpumpExclamationmark"] = 119295509966816,
		["fuelpumpSlash"] = 80568453132219,
		["function"] = 88302320601228,
		["fx"] = 103009020235959,
		["gamecontroller"] = 119096220409886,
		["gaugeOpenWithLinesNeedle33percent"] = 104863675880095,
		["gaugeOpenWithLinesNeedle33percentAndArrowtriangle"] = 132553697695096,
		["gaugeOpenWithLinesNeedle33percentAndArrowtriangleFrom0percentTo50percent"] = 81580637007677,
		["gaugeOpenWithLinesNeedle67percentAndArrowtriangle"] = 72110696522804,
		["gaugeOpenWithLinesNeedle67percentAndArrowtriangleAndCar"] = 134391478669913,
		["gaugeOpenWithLinesNeedle84percentExclamation"] = 125730930227651,
		["gaugeWithDotsNeedle0percent"] = 105915505394027,
		["gaugeWithDotsNeedle100percent"] = 135036724297473,
		["gaugeWithDotsNeedle33percent"] = 75307562428779,
		["gaugeWithDotsNeedle50percent"] = 113165147850221,
		["gaugeWithDotsNeedle67percent"] = 73356725050455,
		["gaugeWithDotsNeedleBottom0percent"] = 81053665147339,
		["gaugeWithDotsNeedleBottom100percent"] = 118065291887447,
		["gaugeWithDotsNeedleBottom50percent"] = 115283421029609,
		["gaugeWithDotsNeedleBottom50percentBadgeMinus"] = 121238805875359,
		["gaugeWithDotsNeedleBottom50percentBadgePlus"] = 109301754562729,
		["gear"] = 93463417713731,
		["gearBadge"] = 103383744725187,
		["gearBadgeCheckmark"] = 88555949397622,
		["gearBadgeQuestionmark"] = 73947849677930,
		["gearBadgeXmark"] = 84416506389985,
		["gearCircle"] = 115384869742127,
		["gearshape"] = 117049869817852,
		["gearshape2"] = 117355100489135,
		["gearshapeArrowTriangle2Circlepath"] = 84641602565527,
		["gearshapeCircle"] = 129388953569327,
		["gearshiftLayoutSixspeed"] = 105192785758859,
		["gift"] = 124716473916822,
		["giftcard"] = 123357243253728,
		["giftCircle"] = 95170019998697,
		["globe"] = 101767218366266,
		["globeAmericas"] = 119372469642645,
		["globeAsiaAustralia"] = 120808677555396,
		["globeBadgeChevronBackward"] = 89916175364862,
		["globeCentralSouthAsia"] = 120522058696581,
		["globeDesk"] = 107755158064853,
		["globeEuropeAfrica"] = 106142876012163,
		["glowplug"] = 117502042940538,
		["gobackward"] = 91320889824011,
		["gobackward10"] = 90559603880621,
		["gobackward15"] = 120316938540272,
		["gobackward30"] = 140354039230051,
		["gobackward45"] = 93434813605748,
		["gobackward5"] = 97130008586442,
		["gobackward60"] = 91215922364999,
		["gobackward75"] = 140735752535943,
		["gobackward90"] = 108207845332277,
		["gobackwardMinus"] = 92431716781150,
		["goforward"] = 131297950123949,
		["goforward10"] = 136515914036455,
		["goforward15"] = 91999877907911,
		["goforward30"] = 77322694446691,
		["goforward45"] = 90174945269280,
		["goforward5"] = 92986838147448,
		["goforward60"] = 116153177521739,
		["goforward75"] = 71594405050565,
		["goforward90"] = 81147746129102,
		["goforwardPlus"] = 130621369072851,
		["graduationcap"] = 107016904273927,
		["graduationcapCircle"] = 101968938789158,
		["greaterthan"] = 100154976668906,
		["greaterthanCircle"] = 102770886704387,
		["greaterthanSquare"] = 129436011561737,
		["greetingcard"] = 103898388974312,
		["grid"] = 140178861976840,
		["gridCircle"] = 130234958416171,
		["guaranisign"] = 75439930844128,
		["guaranisignCircle"] = 106474371188305,
		["guaranisignSquare"] = 99643661441187,
		["guitars"] = 89552692956885,
		["gymBag"] = 91936141424860,
		["gyroscope"] = 132244916029235,
		["hammer"] = 103131584528770,
		["hammerCircle"] = 74490498390973,
		["handbag"] = 132152356168017,
		["handbagCircle"] = 114510833555325,
		["handDraw"] = 77538773866494,
		["handPointDown"] = 119738942472362,
		["handPointLeft"] = 81548791076395,
		["handPointRight"] = 88897279924338,
		["handPointUp"] = 135989287278173,
		["handPointUpBraille"] = 125997713968939,
		["handPointUpLeft"] = 113458915824230,
		["handPointUpLeftAndText"] = 126912275881889,
		["handRaised"] = 82019405080955,
		["handRaisedApp"] = 117707357852142,
		["handRaisedBrakesignal"] = 137889578262374,
		["handRaisedBrakesignalSlash"] = 136404686007826,
		["handRaisedCircle"] = 77964496621148,
		["handRaisedFingersSpread"] = 87382145130925,
		["handRaisedSlash"] = 99551377759203,
		["handRaisedSquare"] = 120124026695951,
		["handRaisedSquareOnSquare"] = 95839429879229,
		["handsAndSparkles"] = 86849300947781,
		["handsClap"] = 77562764751019,
		["handTap"] = 128075990773888,
		["handThumbsdown"] = 122067645581433,
		["handThumbsdownCircle"] = 126932375202246,
		["handThumbsup"] = 71873367293048,
		["handThumbsupCircle"] = 127941020251542,
		["handWave"] = 107235477795246,
		["hanger"] = 82820384563336,
		["hare"] = 81680749337155,
		["hareCircle"] = 117167437846510,
		["hazardsign"] = 81532417708970,
		["headlightDaytime"] = 137136468021745,
		["headlightFog"] = 97458710225335,
		["headlightHighBeam"] = 128131652757062,
		["headlightLowBeam"] = 135099116151086,
		["headphones"] = 106715715835631,
		["headphonesCircle"] = 117557349152734,
		["headProfileArrowForwardAndVisionpro"] = 121693109509839,
		["hearingdeviceAndSignalMeter"] = 98123946880457,
		["hearingdeviceEar"] = 140472299081006,
		["heart"] = 109117761441183,
		["heartCircle"] = 108890463961676,
		["heartRectangle"] = 127223437499170,
		["heartSlash"] = 114165709625494,
		["heartSlashCircle"] = 96341086302072,
		["heartSquare"] = 102824926831120,
		["heartTextSquare"] = 101879174324148,
		["heatElementWindshield"] = 115720262850623,
		["heaterVertical"] = 84741339638914,
		["heatWaves"] = 133713407444127,
		["helm"] = 112363025158819,
		["hexagon"] = 117932412411502,
		["hifireceiver"] = 83575856188207,
		["hifispeaker"] = 106843553305004,
		["hifispeaker2"] = 90092840094055,
		["hifispeakerAndAppletv"] = 92524124618718,
		["hifispeakerAndHomepod"] = 137888286379086,
		["hifispeakerAndHomepodmini"] = 104285147267424,
		["highlighter"] = 77806724703440,
		["hockeyPuck"] = 123663110103043,
		["hockeyPuckCircle"] = 136584542208226,
		["holdBrakesignal"] = 78638998322603,
		["homekit"] = 129816863247706,
		["homepod"] = 96629146531238,
		["homepod2"] = 101411606767286,
		["homepodAndAppletv"] = 136566168513238,
		["homepodAndHomepodmini"] = 128138460912737,
		["homepodmini"] = 93368409427047,
		["homepodmini2"] = 138072319954848,
		["homepodminiAndAppletv"] = 96899217298462,
		["horn"] = 76499301028205,
		["hornBlast"] = 99208021557068,
		["hourglass"] = 109119388646355,
		["hourglassBadgePlus"] = 125140797406882,
		["hourglassCircle"] = 74121557568551,
		["house"] = 75142559607619,
		["houseAndFlag"] = 75627724392758,
		["houseAndFlagCircle"] = 103248755163222,
		["houseCircle"] = 84194969699478,
		["houseLodge"] = 119318595239178,
		["houseLodgeCircle"] = 131993754948664,
		["hryvniasign"] = 84763508059884,
		["hryvniasignCircle"] = 137112151466307,
		["hryvniasignSquare"] = 117405927580324,
		["humidifier"] = 95385649840572,
		["humidifierAndDroplets"] = 70766413669259,
		["humidity"] = 138202713708255,
		["hurricane"] = 129364860302491,
		["hurricaneCircle"] = 122254392121714,
		["icloud"] = 101659161537443,
		["icloudAndArrowDown"] = 124106021512201,
		["icloudAndArrowUp"] = 130588908975143,
		["icloudCircle"] = 109505824359041,
		["icloudSlash"] = 110954111758183,
		["icloudSquare"] = 116854988059481,
		["increaseIndent"] = 77365198387403,
		["increaseQuotelevel"] = 128578001501285,
		["indianrupeesign"] = 139464987853385,
		["indianrupeesignCircle"] = 93399459022070,
		["indianrupeesignSquare"] = 89644071481395,
		["infinity"] = 105395628064475,
		["infinityCircle"] = 95923582554532,
		["info"] = 82779181850384,
		["infoBubble"] = 110157898124544,
		["infoCircle"] = 79229862313887,
		["infoSquare"] = 73485756772281,
		["infoWindshield"] = 87644855323791,
		["internaldrive"] = 129361039257665,
		["ipad"] = 94420007219781,
		["ipadAndArrowForward"] = 82027737489705,
		["ipadAndIphone"] = 133274203016358,
		["ipadAndIphoneSlash"] = 98585690423131,
		["ipadBadgePlay"] = 84600357822005,
		["ipadCase"] = 138027023973892,
		["ipadCaseAndIphoneCase"] = 77836789602876,
		["ipadGen1"] = 88794919460803,
		["ipadGen1BadgePlay"] = 134986643881512,
		["ipadGen1Landscape"] = 126103693177768,
		["ipadGen1LandscapeBadgePlay"] = 89593645952972,
		["ipadGen2"] = 127231244602569,
		["ipadGen2BadgePlay"] = 129931538764333,
		["ipadGen2Landscape"] = 99302614491902,
		["ipadGen2LandscapeBadgePlay"] = 87970154286850,
		["ipadLandscape"] = 110038748912228,
		["ipadLandscapeBadgePlay"] = 109183769920897,
		["ipadRearCamera"] = 128574448370495,
		["ipadSizes"] = 81434181784323,
		["iphone"] = 111795206347277,
		["iphoneAndArrowForward"] = 117210262149661,
		["iphoneAndArrowLeftAndArrowRight"] = 104339904723080,
		["iphoneBadgePlay"] = 84138013743752,
		["iphoneCase"] = 96086235791617,
		["iphoneCircle"] = 86067583325421,
		["iphoneGen1"] = 112794459854723,
		["iphoneGen1BadgePlay"] = 98425076138035,
		["iphoneGen1Circle"] = 110199837007404,
		["iphoneGen1Landscape"] = 94767575190460,
		["iphoneGen1RadiowavesLeftAndRight"] = 78127522254255,
		["iphoneGen1RadiowavesLeftAndRightCircle"] = 138216818862050,
		["iphoneGen1Slash"] = 102599840307323,
		["iphoneGen1SlashCircle"] = 105895703080604,
		["iphoneGen2"] = 122770568933385,
		["iphoneGen2BadgePlay"] = 139832238864734,
		["iphoneGen2Circle"] = 130935162290121,
		["iphoneGen2Landscape"] = 87875792716059,
		["iphoneGen2RadiowavesLeftAndRight"] = 92464260478869,
		["iphoneGen2RadiowavesLeftAndRightCircle"] = 70984103278879,
		["iphoneGen2Slash"] = 77297986025491,
		["iphoneGen2SlashCircle"] = 87700982364550,
		["iphoneGen3"] = 100351573771562,
		["iphoneGen3BadgePlay"] = 122644965643843,
		["iphoneGen3Circle"] = 104540027873195,
		["iphoneGen3Landscape"] = 71663584341551,
		["iphoneGen3RadiowavesLeftAndRight"] = 121367569706988,
		["iphoneGen3RadiowavesLeftAndRightCircle"] = 116278730977293,
		["iphoneGen3Slash"] = 118011635853050,
		["iphoneGen3SlashCircle"] = 129979217684984,
		["iphoneLandscape"] = 76557835009779,
		["iphoneRadiowavesLeftAndRight"] = 78146085694021,
		["iphoneRadiowavesLeftAndRightCircle"] = 90736886459698,
		["iphoneRearCamera"] = 79312022064431,
		["iphoneSizes"] = 105482650343437,
		["iphoneSlash"] = 79469285052471,
		["iphoneSlashCircle"] = 127811850755000,
		["iphoneSmartbatterycaseGen1"] = 136472612806937,
		["iphoneSmartbatterycaseGen2"] = 134549125864284,
		["ipod"] = 97844506854313,
		["ipodshuffleGen1"] = 85956093711602,
		["ipodshuffleGen2"] = 85111088101023,
		["ipodshuffleGen3"] = 123523059376894,
		["ipodshuffleGen4"] = 73762011203526,
		["ipodtouch"] = 119129980411950,
		["ipodtouchLandscape"] = 84719307699005,
		["ipodtouchSlash"] = 71827533045992,
		["italic"] = 139292651945967,
		["ivfluidBag"] = 110843514482726,
		["kashidaArabic"] = 101604962894446,
		["key"] = 106796214107043,
		["keyboard"] = 70993223382855,
		["keyboardBadgeEllipsis"] = 111768859224873,
		["keyboardBadgeEye"] = 113804851330054,
		["keyboardChevronCompactDown"] = 118417513585237,
		["keyboardChevronCompactLeft"] = 90214842609924,
		["keyboardMacwindow"] = 76519401712264,
		["keyboardOnehandedLeft"] = 128398887142334,
		["keyboardOnehandedRight"] = 127594314426760,
		["keyHorizontal"] = 138166984818495,
		["keyIcloud"] = 104546203584651,
		["keyRadiowavesForward"] = 92155972436404,
		["keySlash"] = 139341479389926,
		["keyViewfinder"] = 128204547906608,
		["kipsign"] = 84820598778532,
		["kipsignCircle"] = 107385191106095,
		["kipsignSquare"] = 123502079309974,
		["kph"] = 87214822772084,
		["kphCircle"] = 72083926923875,
		["l1ButtonRoundedbottomHorizontal"] = 132322744377824,
		["l1Circle"] = 132299740102925,
		["l2ButtonAngledtopVerticalLeft"] = 105858072312942,
		["l2ButtonRoundedtopHorizontal"] = 128110003833200,
		["l2Circle"] = 95083162382164,
		["l3ButtonAngledbottomHorizontalLeft"] = 85683690645172,
		["l4ButtonHorizontal"] = 131957849368422,
		["ladybug"] = 79532640477990,
		["ladybugCircle"] = 93722787684416,
		["lampCeiling"] = 130378537137100,
		["lampCeilingInverse"] = 77998797568264,
		["lampDesk"] = 103312036381935,
		["lampFloor"] = 115217511907999,
		["lampTable"] = 101033305963783,
		["lane"] = 102792633304550,
		["lanyardcard"] = 97744958017931,
		["laptopcomputer"] = 107281859794400,
		["laptopcomputerAndArrowDown"] = 117027416027544,
		["laptopcomputerSlash"] = 128050477390913,
		["laptopcomputerTrianglebadgeExclamationmark"] = 100946318266937,
		["larisign"] = 83530500017287,
		["larisignCircle"] = 76238072655395,
		["larisignSquare"] = 136100671509788,
		["laserBurst"] = 84243364035565,
		["lasso"] = 119920715432629,
		["lassoBadgeSparkles"] = 72681411350757,
		["latch2Case"] = 77092895295754,
		["laurelLeading"] = 130361076360068,
		["laurelTrailing"] = 98791363187803,
		["lbButtonRoundedbottomHorizontal"] = 123755402651583,
		["lbCircle"] = 100757059317772,
		["leaf"] = 104165823693595,
		["leafArrowTriangleCirclepath"] = 84475508392251,
		["leafCircle"] = 105670621279893,
		["left"] = 112613324207829,
		["leftCircle"] = 107615454875833,
		["lessthan"] = 106161556782338,
		["lessthanCircle"] = 106184112793325,
		["lessthanSquare"] = 139369098231160,
		["letterACircle"] = 102043519807680,
		["letterASquare"] = 123876841192249,
		["letterBCircle"] = 81796888108964,
		["letterBSquare"] = 107926268990493,
		["letterCCircle"] = 102283325788464,
		["letterCSquare"] = 77342805733080,
		["letterDCircle"] = 77271013016863,
		["letterDSquare"] = 71745998559849,
		["letterECircle"] = 110939040840018,
		["letterESquare"] = 130805805047117,
		["letterFCircle"] = 75292206915955,
		["letterFCursive"] = 129129749457489,
		["letterFCursiveCircle"] = 88414197139904,
		["letterFSquare"] = 80222891036830,
		["letterGCircle"] = 101617051624970,
		["letterGSquare"] = 101108516134256,
		["letterHCircle"] = 104755888415516,
		["letterHSquare"] = 119444843840302,
		["letterHSquareOnSquare"] = 138633232751099,
		["letterICircle"] = 100265252155056,
		["letterISquare"] = 78227741894490,
		["letterJCircle"] = 127681856901613,
		["letterJSquare"] = 70614371401130,
		["letterJSquareOnSquare"] = 136068707644750,
		["letterK"] = 93236576104824,
		["letterKCircle"] = 126766755298208,
		["letterKSquare"] = 132054295015575,
		["letterLButtonRoundedbottomHorizontal"] = 86796430696473,
		["letterLCircle"] = 115151845775938,
		["letterLJoystick"] = 126954698608958,
		["letterLJoystickPressDown"] = 101991839887936,
		["letterLJoystickTiltDown"] = 109426620639396,
		["letterLJoystickTiltLeft"] = 88760036840814,
		["letterLJoystickTiltRight"] = 123427118118507,
		["letterLJoystickTiltUp"] = 108699411245416,
		["letterLSquare"] = 102129122454965,
		["letterMCircle"] = 105252616936701,
		["letterMSquare"] = 91788346353476,
		["letterNCircle"] = 108501754774630,
		["letterNSquare"] = 134128630622949,
		["letterOCircle"] = 102216372092166,
		["letterOSquare"] = 100189064332452,
		["letterPCircle"] = 133454893649760,
		["letterPSquare"] = 121771081041226,
		["letterQCircle"] = 121158947718797,
		["letterQSquare"] = 138412895934294,
		["letterRButtonRoundedbottomHorizontal"] = 127892690915857,
		["letterRCircle"] = 71266917331154,
		["letterRJoystick"] = 77839293235193,
		["letterRJoystickPressDown"] = 101313826207669,
		["letterRJoystickTiltDown"] = 107724362619264,
		["letterRJoystickTiltLeft"] = 105136001525486,
		["letterRJoystickTiltRight"] = 110960582214040,
		["letterRJoystickTiltUp"] = 71286967299311,
		["letterRSquare"] = 135777530848446,
		["letterRSquareOnSquare"] = 123053148394613,
		["letterSCircle"] = 83393144046860,
		["letterSSquare"] = 137609708051079,
		["letterTCircle"] = 75623106527183,
		["letterTSquare"] = 116018632541398,
		["letterUCircle"] = 100569535331718,
		["letterUSquare"] = 76708256054317,
		["letterVCircle"] = 83920398217229,
		["letterVSquare"] = 129063617167906,
		["letterWCircle"] = 107802977183125,
		["letterWSquare"] = 83322547030564,
		["letterXCircle"] = 99920343804208,
		["letterXSquare"] = 123476212380657,
		["letterXSquareroot"] = 80429022258285,
		["letterYCircle"] = 120543405393753,
		["letterYSquare"] = 80658772608290,
		["letterZCircle"] = 109541227310226,
		["letterZSquare"] = 139916717288653,
		["level"] = 100308504901487,
		["licenseplate"] = 137114933132779,
		["lifepreserver"] = 135131229835272,
		["lightBeaconMax"] = 124312382613163,
		["lightBeaconMin"] = 70423881683729,
		["lightbulb"] = 133139109847915,
		["lightbulb2"] = 113732604881776,
		["lightbulbCircle"] = 118221893668950,
		["lightbulbLed"] = 94823659962786,
		["lightbulbLedWide"] = 90211091241325,
		["lightbulbMax"] = 125899987559082,
		["lightbulbMin"] = 136026940464695,
		["lightbulbMinBadgeExclamationmark"] = 79741870105023,
		["lightbulbSlash"] = 75943132819488,
		["lightCylindricalCeiling"] = 122085524435093,
		["lightCylindricalCeilingInverse"] = 71514036206061,
		["lightMax"] = 98054612514465,
		["lightMin"] = 106830474075817,
		["lightOverheadLeft"] = 77338685313149,
		["lightOverheadRight"] = 80072282008170,
		["lightPanel"] = 95814870024986,
		["lightrail"] = 131976541545046,
		["lightRecessed"] = 86260930652333,
		["lightRecessed3"] = 114724303679773,
		["lightRecessed3Inverse"] = 104736639469269,
		["lightRecessedInverse"] = 71537648368875,
		["lightRibbon"] = 105551604595639,
		["lightspectrumHorizontal"] = 136876578426359,
		["lightStrip2"] = 109514183964177,
		["lightswitchOff"] = 107459744997878,
		["lightswitchOffSquare"] = 129076838815388,
		["lightswitchOn"] = 91075409896822,
		["lightswitchOnSquare"] = 125232571135272,
		["line2HorizontalDecreaseCircle"] = 91785772312764,
		["line3CrossedSwirlCircle"] = 79363605870305,
		["line3Horizontal"] = 75751226066824,
		["line3HorizontalButtonAngledtopVerticalRight"] = 97400802704692,
		["line3HorizontalCircle"] = 110254435693486,
		["line3HorizontalDecrease"] = 109126919762827,
		["line3HorizontalDecreaseCircle"] = 71228118949528,
		["lineDiagonal"] = 82666299567550,
		["lineDiagonalArrow"] = 92568642919457,
		["linesMeasurementHorizontal"] = 106602621327513,
		["linesMeasurementVertical"] = 70411457538222,
		["lineweight"] = 72563256038805,
		["link"] = 129995000515171,
		["linkBadgePlus"] = 95861775889792,
		["linkCircle"] = 130455786914257,
		["linkIcloud"] = 128000480304769,
		["lirasign"] = 85086103429122,
		["lirasignCircle"] = 94083907273646,
		["lirasignSquare"] = 79032718509179,
		["listAndFilm"] = 139241711577989,
		["listBullet"] = 100123835173933,
		["listBulletBelowRectangle"] = 80023544987733,
		["listBulletCircle"] = 136723888881994,
		["listBulletClipboard"] = 121315754661696,
		["listBulletIndent"] = 102199183886425,
		["listBulletRectangle"] = 117229481852614,
		["listBulletRectanglePortrait"] = 116075715529412,
		["listClipboard"] = 103260641776255,
		["listDash"] = 118277557957455,
		["listDashHeaderRectangle"] = 85943743779050,
		["listNumber"] = 91244323866171,
		["listStar"] = 110452119166185,
		["listTriangle"] = 119019384389138,
		["livephoto"] = 102834300794894,
		["livephotoBadgeAutomatic"] = 117804202337786,
		["livephotoPlay"] = 117241613033811,
		["livephotoSlash"] = 125048275199622,
		["lizard"] = 103748917799848,
		["lizardCircle"] = 94464094044811,
		["lmButtonHorizontal"] = 94380610717086,
		["location"] = 122678502104360,
		["locationCircle"] = 113957216146271,
		["locationMagnifyingglass"] = 98241048499649,
		["locationNorth"] = 82169739589093,
		["locationNorthCircle"] = 132843911874563,
		["locationNorthLine"] = 139985377517529,
		["locationSlash"] = 91990528463774,
		["locationSlashCircle"] = 132188592884970,
		["locationSquare"] = 86937326871446,
		["locationViewfinder"] = 122466714159268,
		["lock"] = 119125428737838,
		["lockAppDashed"] = 111344596174945,
		["lockApplewatch"] = 81987142815643,
		["lockBadgeClock"] = 75062161205651,
		["lockCircle"] = 93274298465206,
		["lockCircleDotted"] = 127519593614049,
		["lockDesktopcomputer"] = 136358075907544,
		["lockDisplay"] = 103111304999607,
		["lockDoc"] = 122591748345523,
		["lockIcloud"] = 88181705897505,
		["lockIpad"] = 97694280883446,
		["lockIphone"] = 116360902928809,
		["lockLaptopcomputer"] = 132525575467307,
		["lockOpen"] = 82132779304054,
		["lockOpenApplewatch"] = 138549364400959,
		["lockOpenDesktopcomputer"] = 97385609564243,
		["lockOpenDisplay"] = 117213485694448,
		["lockOpenIpad"] = 120198073263922,
		["lockOpenIphone"] = 107078188358826,
		["lockOpenLaptopcomputer"] = 89711722973070,
		["lockOpenRotation"] = 91539290703274,
		["lockOpenTrianglebadgeExclamationmark"] = 102183066621732,
		["lockRectangle"] = 130656167137532,
		["lockRectangleOnRectangle"] = 132802306064274,
		["lockRectangleStack"] = 118554514944289,
		["lockRotation"] = 99937396878315,
		["lockShield"] = 136853703264345,
		["lockSlash"] = 101795791789254,
		["lockSquare"] = 98566443709245,
		["lockSquareStack"] = 71722029808763,
		["lockTrianglebadgeExclamationmark"] = 103914618699393,
		["loupe"] = 81647791995971,
		["lsbButtonAngledbottomHorizontalLeft"] = 128594273750837,
		["ltButtonRoundedtopHorizontal"] = 133145313133247,
		["ltCircle"] = 136152244620004,
		["lungs"] = 123279436452980,
		["m1ButtonHorizontal"] = 87087217250166,
		["m2ButtonHorizontal"] = 108885641299566,
		["m3ButtonHorizontal"] = 127888106481885,
		["m4ButtonHorizontal"] = 140519232868304,
		["macbook"] = 86472747691252,
		["macbookAndIpad"] = 77003037265710,
		["macbookAndIphone"] = 84340669511803,
		["macbookAndVisionpro"] = 127278593229556,
		["macbookGen1"] = 90881537901989,
		["macbookGen2"] = 79759408409418,
		["macmini"] = 125685878830022,
		["macproGen1"] = 119393591565976,
		["macproGen2"] = 114725993670899,
		["macproGen3"] = 86124477871382,
		["macproGen3Server"] = 84145547699628,
		["macstudio"] = 76642054977973,
		["macwindow"] = 110276030463954,
		["macwindowAndCursorarrow"] = 90741041437063,
		["macwindowBadgePlus"] = 87166150150186,
		["macwindowOnRectangle"] = 131115847589274,
		["magazine"] = 134630064485077,
		["magicmouse"] = 96927055531974,
		["magnifyingglass"] = 134122727615034,
		["magnifyingglassCircle"] = 86464344711108,
		["magsafeBatterypack"] = 79639408689089,
		["mail"] = 108246439499760,
		["mailAndTextMagnifyingglass"] = 75549816367630,
		["mailStack"] = 126813915735862,
		["manatsign"] = 99099739233864,
		["manatsignCircle"] = 116051288811223,
		["manatsignSquare"] = 79259161110982,
		["map"] = 136805527671928,
		["mapCircle"] = 77610408904670,
		["mappin"] = 103020839450072,
		["mappinAndEllipse"] = 126322593782895,
		["mappinAndEllipseCircle"] = 131745353866034,
		["mappinCircle"] = 74179773070764,
		["mappinSlash"] = 127844876046017,
		["mappinSlashCircle"] = 75702585672244,
		["mappinSquare"] = 79910957001962,
		["medal"] = 134971613911509,
		["mediastick"] = 96017921741888,
		["medicalThermometer"] = 94373493783669,
		["megaphone"] = 137016768703735,
		["memories"] = 109786533078027,
		["memoriesBadgeMinus"] = 86865909767639,
		["memoriesBadgePlus"] = 120626706873914,
		["memorychip"] = 85008277084746,
		["menubarArrowDownRectangle"] = 119960778680170,
		["menubarArrowUpRectangle"] = 89052358166513,
		["menubarDockRectangle"] = 98555969356271,
		["menubarDockRectangleBadgeRecord"] = 81512824979210,
		["menubarRectangle"] = 97397394002959,
		["menucard"] = 96119871867711,
		["message"] = 72241028686449,
		["messageBadge"] = 95008660525929,
		["messageBadgeCircle"] = 138999347319073,
		["messageBadgeWaveform"] = 88244349364147,
		["messageCircle"] = 87601751094524,
		["metronome"] = 97739534053490,
		["mic"] = 70559142840213,
		["micAndSignalMeter"] = 98371685797325,
		["micBadgePlus"] = 124905697228070,
		["micBadgeXmark"] = 90776924897027,
		["micCircle"] = 97798740260123,
		["microbe"] = 121303258684373,
		["microbeCircle"] = 78114102963002,
		["microwave"] = 96310568064690,
		["micSlash"] = 77413617305085,
		["micSlashCircle"] = 124310703535746,
		["micSquare"] = 113336595252301,
		["millsign"] = 136543947978868,
		["millsignCircle"] = 129083347617966,
		["millsignSquare"] = 97660568436996,
		["minus"] = 120243537927411,
		["minusCircle"] = 75645831305441,
		["minusDiamond"] = 86936086210042,
		["minusForwardslashPlus"] = 71254452238286,
		["minusMagnifyingglass"] = 123606884277714,
		["minusPlusAndFluidBatteryblock"] = 120131222786282,
		["minusPlusBatteryblock"] = 131524999134330,
		["minusPlusBatteryblockExclamationmark"] = 115460080165403,
		["minusPlusBatteryblockSlash"] = 135096725601247,
		["minusPlusBatteryblockStack"] = 108480603987168,
		["minusPlusBatteryblockStackExclamationmark"] = 126662981282596,
		["minusRectangle"] = 81081385196803,
		["minusRectanglePortrait"] = 87804665538297,
		["minusSquare"] = 73893413794606,
		["mirrorSideLeft"] = 70895722264014,
		["mirrorSideLeftAndArrowTurnDownRight"] = 84679324674485,
		["mirrorSideLeftAndHeatWaves"] = 70930057310516,
		["mirrorSideRight"] = 71465512634260,
		["mirrorSideRightAndArrowTurnDownLeft"] = 103244246445799,
		["mirrorSideRightAndHeatWaves"] = 83606053441080,
		["moon"] = 134740339752496,
		["moonCircle"] = 71384714868629,
		["moonDust"] = 72370895135010,
		["moonDustCircle"] = 132656040539406,
		["moonHaze"] = 130751963413095,
		["moonHazeCircle"] = 123906847453556,
		["moonphaseFirstQuarter"] = 115831170662432,
		["moonphaseFirstQuarterInverse"] = 114122330597748,
		["moonphaseFullMoon"] = 132583368419563,
		["moonphaseFullMoonInverse"] = 140020174918496,
		["moonphaseLastQuarter"] = 80167679969519,
		["moonphaseLastQuarterInverse"] = 87886084385086,
		["moonphaseNewMoon"] = 118342168561745,
		["moonphaseNewMoonInverse"] = 87418554982706,
		["moonphaseWaningCrescent"] = 129421422642553,
		["moonphaseWaningCrescentInverse"] = 98293484041714,
		["moonphaseWaningGibbous"] = 81222054116109,
		["moonphaseWaningGibbousInverse"] = 119506904322823,
		["moonphaseWaxingCrescent"] = 99224910993382,
		["moonphaseWaxingCrescentInverse"] = 116039335421508,
		["moonphaseWaxingGibbous"] = 114168237513262,
		["moonphaseWaxingGibbousInverse"] = 124370152593202,
		["moonrise"] = 104211541577947,
		["moonriseCircle"] = 112969428653535,
		["moonset"] = 136817842137929,
		["moonsetCircle"] = 116016767393972,
		["moonStars"] = 87751912018193,
		["moonStarsCircle"] = 78928354868984,
		["moonZzz"] = 119950763586659,
		["mosaic"] = 103642437897783,
		["mount"] = 116781539906082,
		["mountain2"] = 103253627588735,
		["mountain2Circle"] = 75596088969984,
		["mouth"] = 81554253441017,
		["move3d"] = 124163244087469,
		["movieclapper"] = 110731151411422,
		["mph"] = 82611137171340,
		["mphCircle"] = 70712789480975,
		["mug"] = 107785798546923,
		["multiply"] = 121923161396626,
		["multiplyCircle"] = 88024174281445,
		["multiplySquare"] = 120023339335211,
		["musicMic"] = 126510932173223,
		["musicMicCircle"] = 121995856123205,
		["musicNote"] = 133237720818172,
		["musicNoteHouse"] = 98530136283172,
		["musicNoteList"] = 138145661496558,
		["musicNoteTv"] = 76316565456234,
		["musicQuarternote3"] = 111853378946214,
		["mustache"] = 123686636668421,
		["nairasign"] = 86634510364909,
		["nairasignCircle"] = 77590797149551,
		["nairasignSquare"] = 101949521514770,
		["network"] = 95447228158380,
		["networkSlash"] = 136179450801365,
		["newspaper"] = 94882365651933,
		["newspaperCircle"] = 124076154041904,
		["norwegiankronesign"] = 73048636434744,
		["norwegiankronesignCircle"] = 70861021416629,
		["norwegiankronesignSquare"] = 88021808466600,
		["nose"] = 137854511086792,
		["nosign"] = 135434009047019,
		["nosignApp"] = 114399860120925,
		["note"] = 93279801394323,
		["noteText"] = 128260562606530,
		["noteTextBadgePlus"] = 103069459660634,
		["number"] = 84795648344820,
		["number00Circle"] = 131779637005640,
		["number00Square"] = 81236373352019,
		["number01Circle"] = 138017951861028,
		["number01Square"] = 97241538934163,
		["number02Circle"] = 133242670562001,
		["number02Square"] = 99179290111993,
		["number03Circle"] = 105983470184277,
		["number03Square"] = 132291497347326,
		["number04Circle"] = 116987436384055,
		["number04Square"] = 104100419385488,
		["number05Circle"] = 130314809611820,
		["number05Square"] = 114379850471491,
		["number06Circle"] = 137452105712472,
		["number06Square"] = 103212010162769,
		["number07Circle"] = 102549222409891,
		["number07Square"] = 80554919883042,
		["number08Circle"] = 133051884093292,
		["number08Square"] = 128176821770996,
		["number09Circle"] = 76455988018714,
		["number09Square"] = 87408221362281,
		["number0Circle"] = 112630144563845,
		["number0Square"] = 83690626547054,
		["number10Circle"] = 96193951740646,
		["number10Lane"] = 81314525759681,
		["number10Square"] = 81808119537499,
		["number11Circle"] = 121287509877595,
		["number11Lane"] = 103036455180106,
		["number11Square"] = 137943364469277,
		["number123Rectangle"] = 115605993616370,
		["number12Circle"] = 95488831711839,
		["number12Lane"] = 122996912273287,
		["number12Square"] = 134346701257530,
		["number13Circle"] = 117905874629917,
		["number13Square"] = 117293639837435,
		["number14Circle"] = 108407748009645,
		["number14Square"] = 87120163705904,
		["number15Circle"] = 101007633009470,
		["number15Square"] = 78052584911395,
		["number16Circle"] = 107648080370730,
		["number16Square"] = 127190639879155,
		["number17Circle"] = 104117985546346,
		["number17Square"] = 73499070638265,
		["number18Circle"] = 102380885337705,
		["number18Square"] = 80311469813477,
		["number19Circle"] = 134713999920408,
		["number19Square"] = 102272936095513,
		["number1Brakesignal"] = 79144309389823,
		["number1Circle"] = 90420045405973,
		["number1Lane"] = 125260612972564,
		["number1Magnifyingglass"] = 111096049925424,
		["number1Square"] = 108186243137995,
		["number20Circle"] = 119790353650997,
		["number20Square"] = 73427706736721,
		["number21Circle"] = 115011080119497,
		["number21Square"] = 100575245011241,
		["number22Circle"] = 79147656530403,
		["number22Square"] = 107808365980228,
		["number23Circle"] = 113967161448579,
		["number23Square"] = 126327561252667,
		["number24Circle"] = 77688026724586,
		["number24Square"] = 102948515141281,
		["number25Circle"] = 103932230280729,
		["number25Square"] = 85964236323828,
		["number26Circle"] = 110095157711014,
		["number26Square"] = 72769891775076,
		["number27Circle"] = 80413679989648,
		["number27Square"] = 78907626263409,
		["number28Circle"] = 77630558937328,
		["number28Square"] = 101516015146640,
		["number29Circle"] = 112151950673070,
		["number29Square"] = 126060868481076,
		["number2Brakesignal"] = 130026522834900,
		["number2Circle"] = 115644023941063,
		["number2Lane"] = 76895941784764,
		["number2Square"] = 135434406067611,
		["number30Circle"] = 93539842298014,
		["number30Square"] = 92360148508407,
		["number31Circle"] = 117202855882818,
		["number31Square"] = 72665219530870,
		["number32Circle"] = 102701322952852,
		["number32Square"] = 97548734649989,
		["number33Circle"] = 76331950936098,
		["number33Square"] = 91723950606376,
		["number34Circle"] = 76108893775703,
		["number34Square"] = 98356773601222,
		["number35Circle"] = 128638587888904,
		["number35Square"] = 114874576219731,
		["number36Circle"] = 124580301053177,
		["number36Square"] = 128676757513519,
		["number37Circle"] = 105355724679695,
		["number37Square"] = 111356313667440,
		["number38Circle"] = 140658654909786,
		["number38Square"] = 87276444787352,
		["number39Circle"] = 127160538226349,
		["number39Square"] = 110607591007885,
		["number3Circle"] = 82210102360256,
		["number3Lane"] = 123566814024217,
		["number3Square"] = 100151903595968,
		["number40Circle"] = 76284811463961,
		["number40Square"] = 108964733911464,
		["number41Circle"] = 81051156411638,
		["number41Square"] = 108180042091768,
		["number42Circle"] = 105367690120970,
		["number42Square"] = 121398683227303,
		["number43Circle"] = 116742062830209,
		["number43Square"] = 114456062917463,
		["number44Circle"] = 95645523276973,
		["number44Square"] = 74196270639498,
		["number45Circle"] = 131982584078162,
		["number45Square"] = 112633410131411,
		["number46Circle"] = 98121889785827,
		["number46Square"] = 71827970370485,
		["number47Circle"] = 110683991524351,
		["number47Square"] = 130355817586206,
		["number48Circle"] = 100680920554029,
		["number48Square"] = 137504486853690,
		["number49Circle"] = 85012410965666,
		["number49Square"] = 112216977302610,
		["number4AltCircle"] = 120280636483094,
		["number4AltSquare"] = 122930727055244,
		["number4Circle"] = 113950512097158,
		["number4Lane"] = 80369915269072,
		["number4Square"] = 85342885629372,
		["number50Circle"] = 76596482604277,
		["number50Square"] = 89126185617207,
		["number5Circle"] = 84249571663594,
		["number5Lane"] = 80082125386311,
		["number5Square"] = 92555254652509,
		["number6AltCircle"] = 132108212531324,
		["number6AltSquare"] = 133921705918574,
		["number6Circle"] = 139508584419391,
		["number6Lane"] = 120411900425268,
		["number6Square"] = 136827465810666,
		["number7Circle"] = 91048231428377,
		["number7Lane"] = 89152600086974,
		["number7Square"] = 128474224252993,
		["number8Circle"] = 90175124244732,
		["number8Lane"] = 135579479621822,
		["number8Square"] = 103037928409169,
		["number9AltCircle"] = 89157942477413,
		["number9AltSquare"] = 127573342279334,
		["number9Circle"] = 122405410433743,
		["number9Lane"] = 118878335756561,
		["number9Square"] = 113640399773664,
		["numberCircle"] = 110293375077907,
		["numbersign"] = 93703605960093,
		["numberSquare"] = 91122754706061,
		["numeric2h"] = 105497397405088,
		["numeric2hCircle"] = 70624293530403,
		["numeric4a"] = 86756867568912,
		["numeric4aCircle"] = 80949635570356,
		["numeric4h"] = 111499849309749,
		["numeric4hCircle"] = 108759735497325,
		["numeric4kTv"] = 138479967752101,
		["numeric4l"] = 132669284716581,
		["numeric4lCircle"] = 81144013373119,
		["oar2Crossed"] = 134346835878356,
		["octagon"] = 112640529146294,
		["oilcan"] = 73751343226394,
		["opticaldisc"] = 119334666009921,
		["opticaldiscdrive"] = 94114570802765,
		["opticid"] = 104886052136547,
		["option"] = 79633949097966,
		["oval"] = 82165435449960,
		["ovalPortrait"] = 99917388154358,
		["oven"] = 97338326968474,
		["p1ButtonHorizontal"] = 111393827741253,
		["p2ButtonHorizontal"] = 73539710946704,
		["p3ButtonHorizontal"] = 118240536899525,
		["p4ButtonHorizontal"] = 91079232850384,
		["paddleshifterLeft"] = 128985311786011,
		["paddleshifterRight"] = 103520208885819,
		["paintbrush"] = 78778796291471,
		["paintbrushPointed"] = 124104285860059,
		["paintpalette"] = 103052185781646,
		["pano"] = 126701823254172,
		["panoBadgePlay"] = 88001585740645,
		["paperclip"] = 133243253436828,
		["paperclipBadgeEllipsis"] = 71478987980623,
		["paperclipCircle"] = 83283601046729,
		["paperplane"] = 83069617793753,
		["paperplaneCircle"] = 134742116792128,
		["paragraphsign"] = 129795684441190,
		["parentheses"] = 138450840186073,
		["parkinglight"] = 118512616807904,
		["parkingsign"] = 126556570862214,
		["parkingsignBrakesignal"] = 125769976097943,
		["parkingsignBrakesignalSlash"] = 108971010055508,
		["parkingsignCircle"] = 109967744872497,
		["parkingsignRadiowavesLeftAndRight"] = 137597641731664,
		["parkingsignRadiowavesRightAndSafetycone"] = 107042978276216,
		["parkingsignSteeringwheel"] = 94161303067638,
		["partyPopper"] = 112713963236563,
		["pause"] = 139216971418437,
		["pauseCircle"] = 98946488847229,
		["pauseRectangle"] = 104549464466075,
		["pawprint"] = 95126175157453,
		["pawprintCircle"] = 75537067952063,
		["pc"] = 83096268492687,
		["peacesign"] = 83001873559850,
		["pedalAccelerator"] = 122201211401663,
		["pedalBrake"] = 82326398948926,
		["pedalClutch"] = 108171489732171,
		["pedestrianGateClosed"] = 127375934703336,
		["pedestrianGateOpen"] = 82356564995154,
		["pencil"] = 79600866067272,
		["pencilAndOutline"] = 101584267503414,
		["pencilAndRuler"] = 117072105162042,
		["pencilAndScribble"] = 90456520308543,
		["pencilCircle"] = 92041537326764,
		["pencilLine"] = 86421421264789,
		["pencilSlash"] = 100768820882286,
		["pencilTip"] = 100586979383356,
		["pencilTipCropCircle"] = 92015155867835,
		["pencilTipCropCircleBadgeArrowForward"] = 123273703865125,
		["pencilTipCropCircleBadgeMinus"] = 127282372833061,
		["pencilTipCropCircleBadgePlus"] = 73637261242191,
		["pentagon"] = 82328640826189,
		["percent"] = 112473305729794,
		["person"] = 116021451912285,
		["person2"] = 111998470155308,
		["person2BadgeGearshape"] = 138032001009208,
		["person2BadgeKey"] = 120643953202096,
		["person2Circle"] = 120032420649331,
		["person2CropSquareStack"] = 107882458912037,
		["person2Gobackward"] = 77336790373231,
		["person2Slash"] = 91490961902965,
		["person2Wave2"] = 92393446701692,
		["person3"] = 101994328734673,
		["person3Sequence"] = 122525315379680,
		["personalhotspot"] = 131263865479644,
		["personalhotspotCircle"] = 80358099135295,
		["personAndArrowLeftAndArrowRight"] = 128164370218812,
		["personAndBackgroundDotted"] = 106855141833683,
		["personAndBackgroundStripedHorizontal"] = 80613924548522,
		["personBadgeClock"] = 135617743892366,
		["personBadgeKey"] = 78454102710171,
		["personBadgeMinus"] = 101063022271154,
		["personBadgePlus"] = 94727274541288,
		["personBadgeShieldCheckmark"] = 79493775266690,
		["personBubble"] = 121024423780997,
		["personBust"] = 90245467181053,
		["personBustCircle"] = 92689216973556,
		["personCircle"] = 129465160382108,
		["personCropArtframe"] = 91245281038674,
		["personCropCircle"] = 110606444275572,
		["personCropCircleBadge"] = 107947395714624,
		["personCropCircleBadgeCheckmark"] = 72819767827115,
		["personCropCircleBadgeClock"] = 116476836377449,
		["personCropCircleBadgeExclamationmark"] = 128726094920945,
		["personCropCircleBadgeMinus"] = 86049981762080,
		["personCropCircleBadgeMoon"] = 123372767298874,
		["personCropCircleBadgePlus"] = 101669410692706,
		["personCropCircleBadgeQuestionmark"] = 72238314183198,
		["personCropCircleBadgeXmark"] = 114085430986250,
		["personCropCircleDashed"] = 80608834016797,
		["personCropCircleDashedCircle"] = 85289002159133,
		["personCropRectangle"] = 118490743414497,
		["personCropRectangleBadgePlus"] = 137595870025492,
		["personCropRectangleStack"] = 72369057380020,
		["personCropSquare"] = 86026512121028,
		["personIcloud"] = 75415947180379,
		["personLineDottedPerson"] = 120261667568160,
		["personSlash"] = 135492599367813,
		["personTextRectangle"] = 136636038705110,
		["personWave2"] = 93344210163431,
		["perspective"] = 104935679203505,
		["pesetasign"] = 122937635612334,
		["pesetasignCircle"] = 136839926018301,
		["pesetasignSquare"] = 138929664669224,
		["pesosign"] = 130169037644067,
		["pesosignCircle"] = 92594498475141,
		["pesosignSquare"] = 80097174397814,
		["phone"] = 101851519628829,
		["phoneArrowDownLeft"] = 136312395884021,
		["phoneArrowRight"] = 71837612610759,
		["phoneArrowUpRight"] = 97361543037256,
		["phoneArrowUpRightCircle"] = 102856105226209,
		["phoneBadgeCheckmark"] = 129703778505781,
		["phoneBadgePlus"] = 92211015196093,
		["phoneBadgeWaveform"] = 106306500528949,
		["phoneBubble"] = 139534849741392,
		["phoneCircle"] = 113071989329960,
		["phoneConnection"] = 104763696754755,
		["phoneDown"] = 117300651986088,
		["phoneDownCircle"] = 117349481484807,
		["phoneDownWavesLeftAndRight"] = 94223664552263,
		["photo"] = 119891718242970,
		["photoArtframe"] = 85166170338826,
		["photoArtframeCircle"] = 129522994218684,
		["photoBadgeArrowDown"] = 93732940342806,
		["photoBadgeCheckmark"] = 106124733193567,
		["photoBadgePlus"] = 104140352595581,
		["photoCircle"] = 135595834116845,
		["photoOnRectangle"] = 101739126044462,
		["photoOnRectangleAngled"] = 76993915929292,
		["photoStack"] = 131603418978165,
		["photoTv"] = 71841499652328,
		["pianokeys"] = 121513356842278,
		["pianokeysInverse"] = 95843330464030,
		["pill"] = 122458068597877,
		["pillCircle"] = 70668216406589,
		["pills"] = 82618799693877,
		["pillsCircle"] = 114193645114608,
		["pin"] = 104248915186202,
		["pinCircle"] = 70640396547151,
		["pinSlash"] = 126241136504528,
		["pinSquare"] = 79119804117782,
		["pip"] = 115967653846850,
		["pipeAndDrop"] = 83693236492739,
		["pipEnter"] = 91682820732322,
		["pipExit"] = 79540644388261,
		["pipRemove"] = 101926467036428,
		["pipSwap"] = 120732651410224,
		["platterBottomApplewatchCase"] = 71962024468770,
		["platterTopApplewatchCase"] = 101888557518229,
		["play"] = 93150903163211,
		["playCircle"] = 105691552662846,
		["playDesktopcomputer"] = 134614914293344,
		["playDisplay"] = 128768280044816,
		["playHouse"] = 74576022776067,
		["playLaptopcomputer"] = 102306252768628,
		["playpause"] = 84516015334328,
		["playpauseCircle"] = 104255500816645,
		["playRectangle"] = 112783672572897,
		["playRectangleOnRectangle"] = 127492187065121,
		["playRectangleOnRectangleCircle"] = 94680194456115,
		["playSlash"] = 127588932891396,
		["playSquare"] = 100507695206960,
		["playSquareStack"] = 97407504970894,
		["playstationLogo"] = 111043522235372,
		["playTv"] = 78284603022317,
		["plus"] = 116313904677555,
		["plusApp"] = 134454016485062,
		["plusBubble"] = 79114500158071,
		["plusCircle"] = 106498819435037,
		["plusDiamond"] = 99471083644312,
		["plusForwardslashMinus"] = 101583852484106,
		["plusMagnifyingglass"] = 106605689820309,
		["plusMessage"] = 84287372349882,
		["plusminus"] = 111531324704436,
		["plusminusCircle"] = 140615272292516,
		["plusRectangle"] = 115868131231932,
		["plusRectangleOnFolder"] = 73631354257330,
		["plusRectangleOnRectangle"] = 130849601240379,
		["plusRectanglePortrait"] = 121108211858314,
		["plusSquare"] = 81291475389001,
		["plusSquareDashed"] = 114727435936796,
		["plusSquareOnSquare"] = 125892817208221,
		["plusViewfinder"] = 81871809820849,
		["point3ConnectedTrianglepathDotted"] = 74660617726642,
		["pointBottomleftForwardToArrowtriangleUturnScurvepath"] = 137756040106336,
		["pointBottomleftForwardToPointToprightScurvepath"] = 79728028643343,
		["pointForwardToPointCapsulepath"] = 112214880986572,
		["pointTopleftDownToPointBottomrightCurvepath"] = 80186088768531,
		["polishzlotysign"] = 128827211573021,
		["polishzlotysignCircle"] = 126253337677719,
		["polishzlotysignSquare"] = 73854696737565,
		["popcorn"] = 114196868128828,
		["popcornCircle"] = 114944517087215,
		["power"] = 72689307860434,
		["powerCircle"] = 113272254391277,
		["powercord"] = 80760528975994,
		["powerDotted"] = 81125510275781,
		["poweroff"] = 137073482781299,
		["poweron"] = 75648097915966,
		["poweroutletStrip"] = 117866413302881,
		["poweroutletTypeA"] = 89023037120590,
		["poweroutletTypeASquare"] = 102210644328395,
		["poweroutletTypeB"] = 106019854161686,
		["poweroutletTypeBSquare"] = 95891293096602,
		["poweroutletTypeC"] = 137371671720849,
		["poweroutletTypeCSquare"] = 74229499833367,
		["poweroutletTypeD"] = 73617572168680,
		["poweroutletTypeDSquare"] = 88968914344180,
		["poweroutletTypeE"] = 93090468579267,
		["poweroutletTypeESquare"] = 78186051128155,
		["poweroutletTypeF"] = 127420391847658,
		["poweroutletTypeFSquare"] = 108279471977293,
		["poweroutletTypeG"] = 98024472425132,
		["poweroutletTypeGSquare"] = 74263336399146,
		["poweroutletTypeH"] = 110263464628023,
		["poweroutletTypeHSquare"] = 121300311443144,
		["poweroutletTypeI"] = 72402044256005,
		["poweroutletTypeISquare"] = 81535330406319,
		["poweroutletTypeJ"] = 135057502262222,
		["poweroutletTypeJSquare"] = 97621195021690,
		["poweroutletTypeK"] = 92422817771764,
		["poweroutletTypeKSquare"] = 109081418122651,
		["poweroutletTypeL"] = 137998110606546,
		["poweroutletTypeLSquare"] = 86062018568562,
		["poweroutletTypeM"] = 133802871153933,
		["poweroutletTypeMSquare"] = 130482343499161,
		["poweroutletTypeN"] = 76103667593602,
		["poweroutletTypeNSquare"] = 136254790252178,
		["poweroutletTypeO"] = 75218095438939,
		["poweroutletTypeOSquare"] = 71900293448203,
		["powerplug"] = 111879589251527,
		["powersleep"] = 91943586075883,
		["printer"] = 83881840159268,
		["printerDotmatrix"] = 105219095792793,
		["projective"] = 71738513277519,
		["purchased"] = 80222037688102,
		["purchasedCircle"] = 133888454143255,
		["puzzlepiece"] = 98099182294534,
		["puzzlepieceExtension"] = 130117895810806,
		["pyramid"] = 95463742492961,
		["qrcode"] = 140725727320555,
		["qrcodeViewfinder"] = 104595181570709,
		["questionmark"] = 80880276906111,
		["questionmarkApp"] = 124214756534126,
		["questionmarkAppDashed"] = 82630189464324,
		["questionmarkBubble"] = 116817120269321,
		["questionmarkCircle"] = 121510622803439,
		["questionmarkDiamond"] = 131080964700897,
		["questionmarkFolder"] = 128944831989494,
		["questionmarkSquare"] = 72864331831173,
		["questionmarkSquareDashed"] = 91846373605770,
		["questionmarkVideo"] = 98709776325814,
		["quoteBubble"] = 103878791163454,
		["quoteClosing"] = 118643231228533,
		["quotelevel"] = 80605913759097,
		["quoteOpening"] = 103445457344425,
		["r1ButtonRoundedbottomHorizontal"] = 108990914077074,
		["r1Circle"] = 106475140183391,
		["r2ButtonAngledtopVerticalRight"] = 137854250504108,
		["r2ButtonRoundedtopHorizontal"] = 121350488190576,
		["r2Circle"] = 119637665894130,
		["r3ButtonAngledbottomHorizontalRight"] = 95271269099059,
		["r4ButtonHorizontal"] = 109939286065658,
		["radio"] = 127813707013877,
		["rainbow"] = 122459289380054,
		["rays"] = 103853957057967,
		["rbButtonRoundedbottomHorizontal"] = 78435476357010,
		["rbCircle"] = 135754915920490,
		["recordCircle"] = 118850296850025,
		["recordingtape"] = 123485659101411,
		["recordingtapeCircle"] = 136987433157501,
		["rectangle"] = 105842035689856,
		["rectangle2Swap"] = 74207930657385,
		["rectangle3Group"] = 78742917596230,
		["rectangle3GroupBubble"] = 77645484700555,
		["rectangleAndArrowUpRightAndArrowDownLeft"] = 95663560935589,
		["rectangleAndArrowUpRightAndArrowDownLeftSlash"] = 125488933131093,
		["rectangleAndHandPointUpLeft"] = 122271575147438,
		["rectangleAndPaperclip"] = 93726076902766,
		["rectangleAndPencilAndEllipsis"] = 115419852351706,
		["rectangleAndTextMagnifyingglass"] = 87433712298166,
		["rectangleArrowtriangle2Inward"] = 77031627269456,
		["rectangleArrowtriangle2Outward"] = 90565029178403,
		["rectangleBadgeCheckmark"] = 138477173171828,
		["rectangleBadgeMinus"] = 85430673830703,
		["rectangleBadgePersonCrop"] = 74070598829533,
		["rectangleBadgePlus"] = 75776053794542,
		["rectangleBadgeXmark"] = 123746641688580,
		["rectangleCheckered"] = 93153326915076,
		["rectangleCompressVertical"] = 104681751048761,
		["rectangleConnectedToLineBelow"] = 82631799831020,
		["rectangleDashed"] = 126583281259116,
		["rectangleDashedAndPaperclip"] = 110442692260490,
		["rectangleDashedBadgeRecord"] = 80584763472715,
		["rectangleExpandVertical"] = 76715190679203,
		["rectangleGrid1x2"] = 113103804041889,
		["rectangleGrid2x2"] = 128728263365353,
		["rectangleGrid3x2"] = 77824004592449,
		["rectangleInsetBadgeRecord"] = 80945153582789,
		["rectangleLandscapeRotate"] = 116754709211472,
		["rectangleOnRectangle"] = 93744957969363,
		["rectangleOnRectangleAngled"] = 116702087868251,
		["rectangleOnRectangleButtonAngledtopVerticalLeft"] = 121909629757135,
		["rectangleOnRectangleCircle"] = 102618216381515,
		["rectangleOnRectangleSlash"] = 115930917875352,
		["rectangleOnRectangleSlashCircle"] = 83145354639291,
		["rectangleOnRectangleSquare"] = 137725651591810,
		["rectanglePortrait"] = 108637808072962,
		["rectanglePortraitAndArrowForward"] = 99167544053526,
		["rectanglePortraitAndArrowRight"] = 124300182286131,
		["rectanglePortraitArrowtriangle2Inward"] = 105200912760319,
		["rectanglePortraitArrowtriangle2Outward"] = 131909629450570,
		["rectanglePortraitBadgePlus"] = 95374044206535,
		["rectanglePortraitOnRectanglePortrait"] = 130615051679928,
		["rectanglePortraitOnRectanglePortraitAngled"] = 93286321128807,
		["rectanglePortraitOnRectanglePortraitSlash"] = 83660481195838,
		["rectanglePortraitRotate"] = 73469374308722,
		["rectanglePortraitSlash"] = 122374434743593,
		["rectanglePortraitSplit2x1"] = 91308949433578,
		["rectanglePortraitSplit2x1Slash"] = 127185754063741,
		["rectangleRatio16To9"] = 109938930436731,
		["rectangleRatio3To4"] = 130405672862642,
		["rectangleRatio4To3"] = 87584913225684,
		["rectangleRatio9To16"] = 129248134323563,
		["rectangleSlash"] = 119234922547258,
		["rectangleSplit1x2"] = 139199408414951,
		["rectangleSplit2x1"] = 122985323236874,
		["rectangleSplit2x1Slash"] = 77049759453884,
		["rectangleSplit2x2"] = 124511928304111,
		["rectangleSplit3x1"] = 106422066212410,
		["rectangleSplit3x3"] = 87511467952331,
		["rectangleStack"] = 116436365604694,
		["rectangleStackBadgeMinus"] = 71773953022774,
		["rectangleStackBadgePersonCrop"] = 116647073390820,
		["rectangleStackBadgePlay"] = 105071912152364,
		["rectangleStackBadgePlus"] = 94330078931959,
		["refrigerator"] = 134196464931732,
		["repeat1"] = 86869926343704,
		["repeat1Circle"] = 123029304044267,
		["repeatCircle"] = 74291857794948,
		["repeatGlyph"] = 94715683784128,
		["restart"] = 99230014772294,
		["restartCircle"] = 131591881198070,
		["retarderBrakesignal"] = 100157667180542,
		["retarderBrakesignalAndExclamationmark"] = 74902498530962,
		["retarderBrakesignalSlash"] = 84102803071686,
		["returnGlyph"] = 125022377592914,
		["returnLeft"] = 110224380772500,
		["returnRight"] = 122185733816748,
		["rhombus"] = 97211209378526,
		["right"] = 70410321543143,
		["rightCircle"] = 131025561974165,
		["righttriangle"] = 96561870650351,
		["righttriangleSplitDiagonal"] = 89239583520619,
		["rmButtonHorizontal"] = 74090385970824,
		["roadLaneArrowtriangle2Inward"] = 108870516678186,
		["roadLanes"] = 136448319824043,
		["roadLanesCurvedLeft"] = 123174448761559,
		["roadLanesCurvedRight"] = 127016599803614,
		["rollerShadeClosed"] = 75299567401714,
		["rollerShadeOpen"] = 133504201544705,
		["romanShadeClosed"] = 119842663324888,
		["romanShadeOpen"] = 98539120053062,
		["rosette"] = 104515407773377,
		["rotate3d"] = 93761802614112,
		["rotate3dCircle"] = 134226688957397,
		["rotateLeft"] = 98799628588304,
		["rotateRight"] = 111275860515167,
		["rsbButtonAngledbottomHorizontalRight"] = 112596870199527,
		["rtButtonRoundedtopHorizontal"] = 77414193246574,
		["rtCircle"] = 73945464414109,
		["rublesign"] = 118249868271730,
		["rublesignCircle"] = 79226077520588,
		["rublesignSquare"] = 123531328159580,
		["ruler"] = 124580708960964,
		["rupeesign"] = 85411502631666,
		["rupeesignCircle"] = 119535270201362,
		["rupeesignSquare"] = 106889772279759,
		["safari"] = 134813194739204,
		["sailboat"] = 124223873287376,
		["sailboatCircle"] = 80188382794265,
		["scale3d"] = 103494897886729,
		["scalemass"] = 133153878762852,
		["scanner"] = 78787533209735,
		["scissors"] = 134014368605943,
		["scissorsBadgeEllipsis"] = 124510059336842,
		["scissorsCircle"] = 73749284657232,
		["scooter"] = 101451506223502,
		["scope"] = 138965519058977,
		["screwdriver"] = 108754384830635,
		["scribble"] = 112659538886348,
		["scribbleVariable"] = 113418787669609,
		["scroll"] = 100275128356418,
		["sdcard"] = 89062794519312,
		["seal"] = 116680651128574,
		["selectionPinInOut"] = 118937861811428,
		["sensor"] = 99545470323641,
		["sensorTagRadiowavesForward"] = 101287793606982,
		["serverRack"] = 87471642858713,
		["shadow"] = 101016771832491,
		["sharedWithYou"] = 99587894742741,
		["sharedWithYouCircle"] = 105105656683870,
		["sharedWithYouSlash"] = 110559749416219,
		["shareplay"] = 138079370720763,
		["shareplaySlash"] = 121565824245528,
		["shazamLogo"] = 88386725554767,
		["shekelsign"] = 125416979323531,
		["shekelsignCircle"] = 119059176394326,
		["shekelsignSquare"] = 114005761845672,
		["shield"] = 91456099996277,
		["shieldCheckered"] = 122359446295344,
		["shieldSlash"] = 127623631983240,
		["shift"] = 103497538775852,
		["shippingbox"] = 107938215608690,
		["shippingboxAndArrowBackward"] = 121166407104401,
		["shippingboxCircle"] = 102547406990516,
		["shoe"] = 82493855899710,
		["shoe2"] = 79242384179363,
		["shoeCircle"] = 90588951026587,
		["shower"] = 97695002865005,
		["showerHandheld"] = 84464581325650,
		["showerSidejet"] = 121175241416575,
		["shuffle"] = 87450497439316,
		["shuffleCircle"] = 133059088881917,
		["sidebarLeading"] = 124272600426135,
		["sidebarLeft"] = 130573800693254,
		["sidebarRight"] = 136433333923397,
		["sidebarSquaresLeading"] = 89410164136670,
		["sidebarSquaresLeft"] = 122373684808454,
		["sidebarSquaresRight"] = 121764320633671,
		["sidebarSquaresTrailing"] = 135215950427898,
		["sidebarTrailing"] = 112168102439448,
		["signature"] = 99872213385309,
		["signpostAndArrowtriangleUp"] = 135811855637794,
		["signpostAndArrowtriangleUpCircle"] = 132260859335770,
		["signpostLeft"] = 82043050227523,
		["signpostLeftCircle"] = 89166289473162,
		["signpostRight"] = 125234331963023,
		["signpostRightAndLeft"] = 100126199311107,
		["signpostRightAndLeftCircle"] = 121579829956208,
		["signpostRightCircle"] = 97809916615544,
		["simcard"] = 75942064097734,
		["simcard2"] = 109448480863154,
		["sink"] = 78779590744156,
		["skateboard"] = 128480869239478,
		["skew"] = 115857011318404,
		["skis"] = 117669107559086,
		["slashCircle"] = 87377327240033,
		["sleep"] = 126008454743032,
		["sleepCircle"] = 137037304125529,
		["sliderHorizontal2Gobackward"] = 82873088218553,
		["sliderHorizontal2RectangleAndArrowTriangle2Circlepath"] = 114334030505190,
		["sliderHorizontal2Square"] = 139963867327097,
		["sliderHorizontal2SquareBadgeArrowDown"] = 83805287451173,
		["sliderHorizontal2SquareOnSquare"] = 86052721209640,
		["sliderHorizontal3"] = 125312809266536,
		["sliderHorizontalBelowRectangle"] = 104503235376084,
		["sliderHorizontalBelowSunMax"] = 127938100858050,
		["sliderVertical3"] = 77544182772028,
		["slowmo"] = 128626341731847,
		["smallcircleCircle"] = 110993506219366,
		["smartphone"] = 136541768651991,
		["smoke"] = 125856836085455,
		["smokeCircle"] = 96560042568991,
		["snowboard"] = 94644320377389,
		["snowflake"] = 94996818832550,
		["snowflakeCircle"] = 136095050387598,
		["snowflakeRoadLane"] = 86171703026173,
		["snowflakeRoadLaneDashed"] = 134725589357545,
		["snowflakeSlash"] = 135229843970972,
		["soccerball"] = 93588660811184,
		["soccerballCircle"] = 112098460084295,
		["soccerballCircleInverse"] = 109103360528747,
		["soccerballInverse"] = 80168579233004,
		["sofa"] = 90257588118101,
		["sos"] = 92239693015980,
		["sosCircle"] = 73656725577112,
		["space"] = 84228287737516,
		["sparkle"] = 137342676578759,
		["sparkleMagnifyingglass"] = 97868818415034,
		["sparkles"] = 136785461727211,
		["sparklesRectangleStack"] = 72293617251305,
		["sparklesTv"] = 100100430518994,
		["speaker"] = 100089005176028,
		["speakerBadgeExclamationmark"] = 111352971044258,
		["speakerCircle"] = 95286777593066,
		["speakerMinus"] = 87951749521691,
		["speakerPlus"] = 113437716920071,
		["speakerSlash"] = 111271654439696,
		["speakerSlashCircle"] = 94312826802104,
		["speakerSquare"] = 96052663063298,
		["speakerWave1"] = 74357466482248,
		["speakerWave2"] = 125400878293762,
		["speakerWave2Bubble"] = 138385174727103,
		["speakerWave2Circle"] = 122573191160979,
		["speakerWave3"] = 83682739710738,
		["speakerZzz"] = 106200649349362,
		["spigot"] = 123132266452704,
		["sportscourt"] = 139920796888744,
		["sportscourtCircle"] = 73405086307525,
		["sprinkler"] = 96293092408391,
		["sprinklerAndDroplets"] = 91088171991120,
		["square"] = 129582598166480,
		["square2Layers3d"] = 101269866424806,
		["square3Layers3d"] = 102169132825714,
		["square3Layers3dDownBackward"] = 130745266323734,
		["square3Layers3dDownForward"] = 76679271188673,
		["square3Layers3dDownLeft"] = 73469205525507,
		["square3Layers3dDownLeftSlash"] = 109408664468844,
		["square3Layers3dDownRight"] = 129579025247041,
		["square3Layers3dDownRightSlash"] = 95581434284076,
		["square3Layers3dSlash"] = 98366671660323,
		["squareAndArrowDown"] = 79587815753711,
		["squareAndArrowDownOnSquare"] = 109055198586744,
		["squareAndArrowUp"] = 76100481665919,
		["squareAndArrowUpCircle"] = 102883600711271,
		["squareAndArrowUpOnSquare"] = 80620430732303,
		["squareAndArrowUpTrianglebadgeExclamationmark"] = 128677213480334,
		["squareAndAtRectangle"] = 132539666086102,
		["squareAndLineVerticalAndSquare"] = 84150791951041,
		["squareAndPencil"] = 140076550722533,
		["squareAndPencilCircle"] = 133506064060496,
		["squareArrowtriangle4Outward"] = 102099341147458,
		["squareBadgePlus"] = 101427888056506,
		["squareCircle"] = 107653029399075,
		["squareDashed"] = 73775231115700,
		["squareDotted"] = 100046623230666,
		["squareGrid2x2"] = 112798363114425,
		["squareGrid3x1BelowLineGrid1x2"] = 131093292287095,
		["squareGrid3x1FolderBadgePlus"] = 73003254597852,
		["squareGrid3x2"] = 138618469503094,
		["squareGrid3x3"] = 131603440779190,
		["squareGrid3x3Square"] = 121341762621158,
		["squareOnCircle"] = 79322048074111,
		["squareOnSquare"] = 83114835552488,
		["squareOnSquareBadgePersonCrop"] = 76298079857132,
		["squareOnSquareDashed"] = 129387505216630,
		["squareOnSquareIntersectionDashed"] = 117126700660099,
		["squareOnSquareSquareshapeControlhandles"] = 135072980607270,
		["squareResize"] = 96684945440533,
		["squareResizeDown"] = 139611739836485,
		["squareResizeUp"] = 112157204168286,
		["squaresBelowRectangle"] = 139212478963369,
		["squareshape"] = 115465076039027,
		["squareshapeControlhandlesOnSquareshapeControlhandles"] = 109180456759120,
		["squareshapeDottedSplit2x2"] = 91166447813616,
		["squareshapeDottedSquareshape"] = 136135057397579,
		["squareshapeSplit2x2"] = 124589508119591,
		["squareshapeSplit2x2Dotted"] = 128554723537974,
		["squareshapeSplit3x3"] = 128687020079752,
		["squareshapeSquareshapeDotted"] = 104026015415021,
		["squareSlash"] = 105002680063220,
		["squaresLeadingRectangle"] = 73002236561583,
		["squareSplit1x2"] = 85695933542376,
		["squareSplit2x1"] = 140361673907262,
		["squareSplit2x2"] = 80607562660987,
		["squareSplitBottomrightquarter"] = 74374099500726,
		["squareSplitDiagonal"] = 85690414662074,
		["squareSplitDiagonal2x2"] = 103107217012653,
		["squareStack"] = 126509171459852,
		["squareStack3dDownForward"] = 136839933637256,
		["squareStack3dDownRight"] = 88831883911906,
		["squareStack3dForwardDottedline"] = 99671805593479,
		["squareStack3dUp"] = 132246403381093,
		["squareStack3dUpBadgeAutomatic"] = 132060196448728,
		["squareStack3dUpSlash"] = 96629379704580,
		["squareStack3dUpTrianglebadgeExclamationmark"] = 92226983821401,
		["squareTextSquare"] = 86807905492081,
		["stairs"] = 84125960911060,
		["star"] = 121044708288511,
		["starBubble"] = 90730129592978,
		["starCircle"] = 74113798414652,
		["staroflife"] = 130180459020683,
		["staroflifeCircle"] = 107209354940663,
		["staroflifeShield"] = 71187905819692,
		["starSlash"] = 82419419900719,
		["starSquare"] = 137365351954235,
		["starSquareOnSquare"] = 139970590215352,
		["steeringwheel"] = 92183035957801,
		["steeringwheelAndHeatWaves"] = 113178310406499,
		["steeringwheelAndKey"] = 90520284268011,
		["steeringwheelAndLiquidWave"] = 87294669615842,
		["steeringwheelAndLock"] = 74743575328404,
		["steeringwheelArrowtriangleLeft"] = 88898032553978,
		["steeringwheelArrowtriangleRight"] = 102529502145209,
		["steeringwheelBadgeExclamationmark"] = 83325628672712,
		["steeringwheelCircle"] = 103709474487322,
		["steeringwheelExclamationmark"] = 76594873846428,
		["steeringwheelRoadLane"] = 107769890993151,
		["steeringwheelRoadLaneDashed"] = 129239795139154,
		["steeringwheelSlash"] = 134437200205984,
		["sterlingsign"] = 134832180316284,
		["sterlingsignCircle"] = 136356829104212,
		["sterlingsignSquare"] = 83605346351975,
		["stethoscope"] = 89329640332709,
		["stethoscopeCircle"] = 133416066230092,
		["stop"] = 105695319911866,
		["stopCircle"] = 137732435777947,
		["stopwatch"] = 113139216636221,
		["storefront"] = 86584275512423,
		["storefrontCircle"] = 84046393260817,
		["stove"] = 71957334471804,
		["strikethrough"] = 131277316824132,
		["stroller"] = 132675133177273,
		["studentdesk"] = 78328747111113,
		["suitcase"] = 79096298263246,
		["suitcaseCart"] = 105497197779430,
		["suitcaseRolling"] = 135725521532386,
		["suitClub"] = 127115733770447,
		["suitDiamond"] = 72053411888478,
		["suitHeart"] = 79734794502960,
		["suitSpade"] = 117912839271550,
		["sum"] = 94609082916141,
		["sunDust"] = 125978578265900,
		["sunDustCircle"] = 123242725996662,
		["sunglasses"] = 81075971778330,
		["sunHaze"] = 140362619208896,
		["sunHazeCircle"] = 79317673278321,
		["sunHorizon"] = 84823083704566,
		["sunHorizonCircle"] = 136610267484073,
		["sunMax"] = 70966423109015,
		["sunMaxCircle"] = 116061290404119,
		["sunMaxTrianglebadgeExclamationmark"] = 137724770650489,
		["sunMin"] = 134147267476594,
		["sunRain"] = 124988831687915,
		["sunRainCircle"] = 95382927717552,
		["sunrise"] = 86522868392545,
		["sunriseCircle"] = 102096127517282,
		["sunset"] = 98250111223411,
		["sunsetCircle"] = 118261521702696,
		["sunSnow"] = 105497846293144,
		["sunSnowCircle"] = 93743760547649,
		["surfboard"] = 127625923112521,
		["suvSide"] = 140446325087274,
		["suvSideAirCirculate"] = 133108762312504,
		["suvSideAirFresh"] = 91736704064763,
		["suvSideAndExclamationmark"] = 83769689408337,
		["suvSideArrowtriangleDown"] = 98875535178411,
		["suvSideArrowtriangleUp"] = 76355034102038,
		["suvSideArrowtriangleUpArrowtriangleDown"] = 132319310613060,
		["suvSideFrontOpen"] = 86582352934925,
		["suvSideHillDown"] = 71407531470410,
		["suvSideHillUp"] = 81173169979474,
		["suvSideLock"] = 89210382014188,
		["suvSideLockOpen"] = 101512866346721,
		["suvSideRearOpen"] = 83402986313506,
		["swatchpalette"] = 82881073984440,
		["swedishkronasign"] = 121254481031925,
		["swedishkronasignCircle"] = 114114603728837,
		["swedishkronasignSquare"] = 87797718899327,
		["swift"] = 124422809080916,
		["switch2"] = 123774929100933,
		["switchProgrammable"] = 86373319257783,
		["switchProgrammableSquare"] = 100534974804220,
		["syringe"] = 140598137500472,
		["tablecells"] = 136915178998357,
		["tablecellsBadgeEllipsis"] = 78977408182246,
		["tableFurniture"] = 96709265353196,
		["tag"] = 120982593056390,
		["tagCircle"] = 137127479586070,
		["tagSlash"] = 75512320803484,
		["tagSquare"] = 122755613849311,
		["taillightFog"] = 106911392297072,
		["takeoutbagAndCupAndStraw"] = 85060700118806,
		["target"] = 133083478000285,
		["teddybear"] = 109324656874845,
		["teletype"] = 130437459178859,
		["teletypeAnswer"] = 92419798289116,
		["teletypeAnswerCircle"] = 125307270919332,
		["teletypeCircle"] = 70386732453341,
		["tengesign"] = 104571134181209,
		["tengesignCircle"] = 88838846920003,
		["tengesignSquare"] = 98181250215462,
		["tennisball"] = 112015684614085,
		["tennisballCircle"] = 122806857306890,
		["tennisRacket"] = 127846239289143,
		["tennisRacketCircle"] = 132815488263915,
		["tent"] = 128313992003405,
		["tent2"] = 133197448646156,
		["tent2Circle"] = 123018159014682,
		["tentCircle"] = 105629629735006,
		["testtube2"] = 87224379973316,
		["textAligncenter"] = 100013389243756,
		["textAlignleft"] = 131300826723120,
		["textAlignright"] = 109977962042867,
		["textAndCommandMacwindow"] = 134232637327534,
		["textAppend"] = 116984371214024,
		["textBadgeCheckmark"] = 83959915995233,
		["textBadgeMinus"] = 102450982956747,
		["textBadgePlus"] = 125107548432735,
		["textBadgeStar"] = 135709025716856,
		["textBadgeXmark"] = 112245439023510,
		["textBelowPhoto"] = 77022030147537,
		["textBookClosed"] = 93946762025599,
		["textBubble"] = 126703621249282,
		["textformat"] = 107554513869335,
		["textformat12"] = 96656679869431,
		["textformat123"] = 134142879344254,
		["textformatAbc"] = 138305677898152,
		["textformatAbcDottedunderline"] = 94626317959618,
		["textformatAlt"] = 123124468510980,
		["textformatSize"] = 91204946072031,
		["textformatSizeLarger"] = 119056994611696,
		["textformatSizeSmaller"] = 140144442713341,
		["textformatSubscript"] = 93956563381755,
		["textformatSuperscript"] = 89885950993129,
		["textInsert"] = 96094280367287,
		["textJustify"] = 74017281128119,
		["textJustifyLeading"] = 110841533402588,
		["textJustifyLeft"] = 71056893606616,
		["textJustifyRight"] = 117627394764231,
		["textJustifyTrailing"] = 75698539941130,
		["textLineFirstAndArrowtriangleForward"] = 87316700589333,
		["textLineLastAndArrowtriangleForward"] = 98382438293518,
		["textMagnifyingglass"] = 92054561041377,
		["textQuote"] = 135436305746756,
		["textRedaction"] = 126203267075245,
		["textViewfinder"] = 99598174505678,
		["textWordSpacing"] = 107756440139738,
		["theatermaskAndPaintbrush"] = 107133906416240,
		["theatermasks"] = 90184535673274,
		["theatermasksCircle"] = 95838756478953,
		["thermometerAndLiquidWaves"] = 128722545733178,
		["thermometerBrakesignal"] = 107352044231129,
		["thermometerHigh"] = 91101915692277,
		["thermometerLow"] = 115575513971184,
		["thermometerMedium"] = 77455077808435,
		["thermometerMediumSlash"] = 87304643965180,
		["thermometerSnowflake"] = 116774329016388,
		["thermometerSnowflakeCircle"] = 111476847709075,
		["thermometerSun"] = 94194458426641,
		["thermometerSunCircle"] = 128477041487200,
		["thermometerTransmission"] = 140542372721482,
		["thermometerVariableAndFigure"] = 88123909655888,
		["thermometerVariableAndFigureCircle"] = 135638340391848,
		["ticket"] = 110925526107379,
		["timelapse"] = 83242866202757,
		["timelineSelection"] = 78056459768529,
		["timer"] = 135824106698294,
		["timerCircle"] = 89099539604505,
		["timerSquare"] = 124854155922379,
		["tirepressure"] = 70630773850730,
		["togglepower"] = 82636385469382,
		["toilet"] = 115464108201574,
		["toiletCircle"] = 118229119810610,
		["tornado"] = 123649806863264,
		["tornadoCircle"] = 86814092515491,
		["tortoise"] = 96267357253452,
		["tortoiseCircle"] = 80695585362980,
		["torus"] = 129104387170046,
		["touchid"] = 102431783184781,
		["tractionControlTirepressure"] = 94252420030182,
		["tractionControlTirepressureExclamationmark"] = 83126806524953,
		["tractionControlTirepressureSlash"] = 81782026780838,
		["trainSideFrontCar"] = 71136775064369,
		["trainSideMiddleCar"] = 122783570956217,
		["trainSideRearCar"] = 99248862375127,
		["tram"] = 79089921419275,
		["tramCircle"] = 139587665939032,
		["transmission"] = 82095327657690,
		["trapezoidAndLineHorizontal"] = 114580783863586,
		["trapezoidAndLineVertical"] = 99657006798406,
		["trash"] = 78126576618726,
		["trashCircle"] = 74847809036755,
		["trashSlash"] = 138785965824409,
		["trashSlashCircle"] = 118205904212505,
		["trashSlashSquare"] = 76844228322051,
		["trashSquare"] = 73676689899686,
		["tray"] = 95002984534597,
		["tray2"] = 105911615551602,
		["trayAndArrowDown"] = 79443320438795,
		["trayAndArrowUp"] = 131013044002938,
		["trayCircle"] = 115587769194043,
		["trayFull"] = 83955310930749,
		["tree"] = 124716247326474,
		["treeCircle"] = 125501930381970,
		["triangle"] = 117056701383483,
		["triangleCircle"] = 131013922022315,
		["triangleshape"] = 132938112335367,
		["trophy"] = 114768961322644,
		["trophyCircle"] = 131353197601526,
		["tropicalstorm"] = 104920374967118,
		["tropicalstormCircle"] = 134316857776368,
		["truckBox"] = 75988082105887,
		["truckBoxBadgeClock"] = 125009138126042,
		["truckPickupSide"] = 127765698300247,
		["truckPickupSideAirCirculate"] = 85891775608419,
		["truckPickupSideAirFresh"] = 131753875087703,
		["truckPickupSideAndExclamationmark"] = 83231779858162,
		["truckPickupSideArrowtriangleDown"] = 114386236093562,
		["truckPickupSideArrowtriangleUp"] = 116428744585632,
		["truckPickupSideArrowtriangleUpArrowtriangleDown"] = 76427781095379,
		["truckPickupSideFrontOpen"] = 112435745703377,
		["truckPickupSideHillDown"] = 123808339764039,
		["truckPickupSideHillUp"] = 121251602304733,
		["truckPickupSideLock"] = 102108675422985,
		["truckPickupSideLockOpen"] = 75887904051247,
		["tshirt"] = 105519615410765,
		["tshirtCircle"] = 113143848007202,
		["tugriksign"] = 89930597498005,
		["tugriksignCircle"] = 115746887844395,
		["tugriksignSquare"] = 90977696033651,
		["tuningfork"] = 70787488294701,
		["turkishlirasign"] = 76225802272770,
		["turkishlirasignCircle"] = 120182321691308,
		["turkishlirasignSquare"] = 79819479586064,
		["tv"] = 100431872634918,
		["tvAndMediabox"] = 77121105114658,
		["tvBadgeWifi"] = 107607303450493,
		["tvCircle"] = 83077239950445,
		["tvSlash"] = 92840793230642,
		["uiwindowSplit2x1"] = 100870750902375,
		["umbrella"] = 139873711710370,
		["umbrellaPercent"] = 137759731975203,
		["underline"] = 130727477130834,
		["vialViewfinder"] = 79284010194080,
		["video"] = 116674608022538,
		["videoBadgeCheckmark"] = 100590959863177,
		["videoBadgeEllipsis"] = 127470952590102,
		["videoBadgePlus"] = 110276669673190,
		["videoBadgeWaveform"] = 100775815776537,
		["videoBubble"] = 100513787700252,
		["videoCircle"] = 80336523442172,
		["videoDoorbell"] = 124958500647626,
		["videoprojector"] = 109557205246641,
		["videoSlash"] = 104694593162011,
		["videoSlashCircle"] = 132935698623392,
		["videoSquare"] = 79070228843547,
		["view2d"] = 130581988648518,
		["view3d"] = 118981422861746,
		["viewfinder"] = 107163384837844,
		["viewfinderCircle"] = 87068760477512,
		["viewfinderRectangular"] = 84113775338318,
		["viewfinderTrianglebadgeExclamationmark"] = 136880541411896,
		["visionpro"] = 76932342920990,
		["visionproAndArrowForward"] = 108237299822657,
		["visionproBadgeExclamationmark"] = 78812515285709,
		["visionproBadgePlay"] = 122979325623328,
		["visionproCircle"] = 70783957641063,
		["visionproSlash"] = 118082278749251,
		["visionproSlashCircle"] = 116051094478142,
		["voiceover"] = 137803560786421,
		["volleyball"] = 79299062876735,
		["volleyballCircle"] = 91043163448360,
		["wake"] = 78336416523921,
		["wakeCircle"] = 110980432478312,
		["walletPass"] = 75933590775088,
		["wandAndRays"] = 123378637843142,
		["wandAndRaysInverse"] = 122867501488879,
		["wandAndStars"] = 95449961416091,
		["wandAndStarsInverse"] = 108387310992441,
		["warninglight"] = 121399035072757,
		["washer"] = 128326072958231,
		["washerCircle"] = 96232743495062,
		["watchAnalog"] = 130235028835944,
		["watchfaceApplewatchCase"] = 117162603748095,
		["waterbottle"] = 80368662508442,
		["waterWaves"] = 131771944642242,
		["waterWavesAndArrowDown"] = 108671761307420,
		["waterWavesAndArrowDownTrianglebadgeExclamationmark"] = 126530403017273,
		["waterWavesAndArrowUp"] = 117956742428464,
		["waterWavesSlash"] = 91314059201896,
		["wave3Backward"] = 135465950254542,
		["wave3BackwardCircle"] = 120993164293924,
		["wave3Forward"] = 71234179988746,
		["wave3ForwardCircle"] = 134368876486800,
		["wave3Left"] = 101143794643507,
		["wave3LeftCircle"] = 77678245431607,
		["wave3Right"] = 100308895062444,
		["wave3RightCircle"] = 104949505698077,
		["waveform"] = 121102653139749,
		["waveformBadgeExclamationmark"] = 91003956461628,
		["waveformBadgeMagnifyingglass"] = 118658132559543,
		["waveformBadgeMic"] = 140630166066509,
		["waveformBadgeMinus"] = 89730195325992,
		["waveformBadgePlus"] = 73965498188945,
		["waveformCircle"] = 113277128212488,
		["waveformPath"] = 131882662434037,
		["waveformPathBadgeMinus"] = 80268627824682,
		["waveformPathBadgePlus"] = 105872860151936,
		["waveformPathEcg"] = 80139427564577,
		["waveformPathEcgRectangle"] = 111322357968319,
		["waveformSlash"] = 112494455650123,
		["webCamera"] = 140198237568248,
		["wifi"] = 121202214555256,
		["wifiCircle"] = 114091788211357,
		["wifiExclamationmark"] = 85758132404029,
		["wifiExclamationmarkCircle"] = 102728247165080,
		["wifiRouter"] = 79015444123271,
		["wifiSlash"] = 113880302917880,
		["wifiSquare"] = 113783186289066,
		["wind"] = 97805301082946,
		["windCircle"] = 127880345932797,
		["windowAwning"] = 98590089878990,
		["windowAwningClosed"] = 135088798223478,
		["windowCasement"] = 96091297622037,
		["windowCasementClosed"] = 117978652705592,
		["windowCeiling"] = 85800394868097,
		["windowCeilingClosed"] = 124121037535399,
		["windowHorizontal"] = 79372383682799,
		["windowHorizontalClosed"] = 94160140686303,
		["windowShadeClosed"] = 133215479484096,
		["windowShadeOpen"] = 72955891166629,
		["windowVerticalClosed"] = 118478764399998,
		["windowVerticalOpen"] = 89163736928849,
		["windshieldFrontAndFluidAndSpray"] = 123297482803348,
		["windshieldFrontAndHeatWaves"] = 96857923676249,
		["windshieldFrontAndSpray"] = 135400265655852,
		["windshieldFrontAndWiper"] = 110551981358261,
		["windshieldFrontAndWiperAndDrop"] = 93090721542909,
		["windshieldFrontAndWiperAndSpray"] = 139773699538838,
		["windshieldFrontAndWiperExclamationmark"] = 126299493138437,
		["windshieldFrontAndWiperIntermittent"] = 132227982392304,
		["windshieldRearAndFluidAndSpray"] = 94558257176129,
		["windshieldRearAndHeatWaves"] = 98580494345897,
		["windshieldRearAndSpray"] = 74972751796584,
		["windshieldRearAndWiper"] = 93339699351032,
		["windshieldRearAndWiperAndDrop"] = 74523105939242,
		["windshieldRearAndWiperAndSpray"] = 88627632568368,
		["windshieldRearAndWiperExclamationmark"] = 89630225593658,
		["windshieldRearAndWiperIntermittent"] = 133454234211807,
		["windSnow"] = 97001593895983,
		["windSnowCircle"] = 81698538505313,
		["wineglass"] = 117555650477049,
		["wonsign"] = 77488733779624,
		["wonsignCircle"] = 117854231480262,
		["wonsignSquare"] = 96295977744019,
		["wrenchAdjustable"] = 101329895864399,
		["wrenchAndScrewdriver"] = 82772346778192,
		["wrongwaysign"] = 128555958259139,
		["xboxLogo"] = 108507288025895,
		["xmark"] = 74305353078098,
		["xmarkApp"] = 98017685577280,
		["xmarkBin"] = 126218087132335,
		["xmarkBinCircle"] = 94227498676286,
		["xmarkCircle"] = 129591096461118,
		["xmarkDiamond"] = 135421117881034,
		["xmarkIcloud"] = 139598175458488,
		["xmarkOctagon"] = 136123728807852,
		["xmarkRectangle"] = 139899770012733,
		["xmarkRectanglePortrait"] = 135232429145312,
		["xmarkSeal"] = 135122266065960,
		["xmarkShield"] = 138130228413169,
		["xmarkSquare"] = 122807484131120,
		["xserve"] = 73888078101687,
		["xserveRaid"] = 117204052589312,
		["yensign"] = 94276977373948,
		["yensignCircle"] = 121345638639744,
		["yensignSquare"] = 108349363714803,
		["yieldsign"] = 132369059216845,
		["zlButtonRoundedtopHorizontal"] = 126115161459047,
		["zrButtonRoundedtopHorizontal"] = 107608277098590,
		["zzz"] = 137515429343264,
	},
}

local function LoadIconSource(source)
	local data = IconSources[source]
	if type(data) == "table" then
		return data
	end
	return nil
end

function BobloNEXT:GetIcon(name, source)
	source = source or "Lucide"
	local set = LoadIconSource(source)
	local iconId = set and set[name]
	if not iconId then return "" end
	return "rbxassetid://" .. tostring(iconId)
end

local function ResolveIcon(icon)
	if icon == nil or icon == "" then return "" end
	if type(icon) ~= "string" then return icon end
	if icon:match("^%a[%w%+%-%.]*://") then return icon end
	if icon:match("^%d+$") then return "rbxassetid://" .. icon end
	local source, name = icon:match("^(%a[%w%-]*):(.+)$")
	if source and name then
		return BobloNEXT:GetIcon(name, source)
	end
	return BobloNEXT:GetIcon(icon, "Lucide")
end

function BobloNEXT:PreloadIcons(sources)
	-- Icon maps are already embedded. Keep this API for compatibility.
	return true
end

local function GetRoot()
	local parent = PlayerGui
	local hidden = hasFn("gethui")
	if hidden then
		local ok, container = pcall(hidden)
		if ok and container then parent = container end
	end
 
	local stale = parent:FindFirstChild("BobloNEXT")
	if stale then stale:Destroy() end
 
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BobloNEXT"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 9999
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = parent
	return screenGui
end
 
BobloNEXT._Root = GetRoot()
 
local function ViewportSize()
	local root = BobloNEXT._Root
	if root and root.AbsoluteSize.X > 0 then
		return root.AbsoluteSize
	end
	local cam = workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1280, 720)
end
 
local UI_SCALE_BASELINE = IsMobileDevice and 380 or 720
local UI_SCALE_MIN = IsMobileDevice and 1.0 or 0.75
local UI_SCALE_MAX = IsMobileDevice and 1.5 or 1.35
 
local function ComputeUIScale()
	return SafeClamp(ViewportSize().Y / UI_SCALE_BASELINE, UI_SCALE_MIN, UI_SCALE_MAX)
end
 
local GlobalScale = Instance.new("UIScale")
GlobalScale.Name = "GlobalScale"
GlobalScale.Scale = ComputeUIScale()
GlobalScale.Parent = BobloNEXT._Root
 
local function GetUIScale()
	return GlobalScale.Scale
end
 
local function RefreshUIScale()
	GlobalScale.Scale = ComputeUIScale()
end
 
local function WatchCamera(cam)
	if not cam then return end
	LibJanitor:Add(cam:GetPropertyChangedSignal("ViewportSize"):Connect(RefreshUIScale))
end
 
WatchCamera(workspace.CurrentCamera)
LibJanitor:Add(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	WatchCamera(workspace.CurrentCamera)
	RefreshUIScale()
end))
 
function BobloNEXT:SetScaleRange(minScale, maxScale)
	UI_SCALE_MIN = minScale or UI_SCALE_MIN
	UI_SCALE_MAX = maxScale or UI_SCALE_MAX
	RefreshUIScale()
end
 
local ActivePopupClose = nil
 
local function RegisterPopupOpen(closeFn)
	if ActivePopupClose and ActivePopupClose ~= closeFn then
		local previous = ActivePopupClose
		ActivePopupClose = nil
		previous()
	end
	ActivePopupClose = closeFn
end
 
local function RegisterPopupClose(closeFn)
	if ActivePopupClose == closeFn then
		ActivePopupClose = nil
	end
end
 
local function CloseAnyOpenPopup()
	if ActivePopupClose then
		local fn = ActivePopupClose
		ActivePopupClose = nil
		fn()
	end
end
 
local function MakePopupBackdrop(onClose)
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "PopupBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = Z.Backdrop
	backdrop.Parent = BobloNEXT._Root
	backdrop.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			onClose()
		end
	end)
	return backdrop
end
 
LibJanitor:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Escape and ActivePopupClose then
		CloseAnyOpenPopup()
	end
end))
 
local KeybindCapturing = false
 
local NotificationQueue = {}
 
local function GetNotifyHolder()
	local root = BobloNEXT._Root
	local holder = root:FindFirstChild("NotificationHolder")
	if holder then return holder end
 
	holder = Instance.new("Frame")
	holder.Name = "NotificationHolder"
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Position = UDim2.new(1, -20, 1, -20)
	holder.Size = UDim2.new(0, 280, 1, -40)
	holder.BackgroundTransparency = 1
	holder.ZIndex = Z.Toast
	holder.Parent = root
 
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, 10)
	layout.Parent = holder
	holder.ClipsDescendants = true
 
	LibJanitor:Add(RunService.Heartbeat:Connect(function()
		if not holder.Parent then return end
		local s = GetUIScale()
		local view = ViewportSize()
		holder.Size = UDim2.fromOffset(math.max(1, math.min(280, view.X / s - 40)), math.max(1, view.Y / s - 40))
		local used, count = 0, 0
		local function fullHeight(card)
			local anim = card:FindFirstChildOfClass("UIScale")
			return card.AbsoluteSize.Y / (anim and math.max(anim.Scale, 0.01) or 1)
		end
		for _, child in ipairs(holder:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible then
				used += fullHeight(child) + (count > 0 and 10 * s or 0)
				count += 1
			end
		end
		while #NotificationQueue > 0 do
			local entry = NotificationQueue[1]
			if not entry.Card.Parent then
				table.remove(NotificationQueue, 1)
			else
				local h = fullHeight(entry.Card)
				if h <= 0 then break end
				local needed = h + (count > 0 and 10 * s or 0)
				if used + needed > holder.AbsoluteSize.Y then break end
				table.remove(NotificationQueue, 1)
				entry.Start()
				used += needed
				count += 1
			end
		end
	end))
 
	return holder
end
 
BobloNEXT._NotifyCounter = 0
 
local NotifyIcons = {
	info    = "info",
	success = "check",
	warning = "triangle-alert",
	error   = "circle-x",
}
 
local NotifyColors = {
	info    = Color3.fromRGB(120, 170, 255),
	success = Color3.fromRGB(110, 220, 140),
	warning = Color3.fromRGB(255, 190, 90),
	error   = Color3.fromRGB(255, 105, 105),
}
 
function BobloNEXT:Notify(opts)
	opts = opts or {}
	local title      = opts.Title or "Notification"
	local text       = opts.Text or ""
	local duration   = opts.Duration or 4
	local notifyType = opts.Type or "info"
	local color      = opts.Color or NotifyColors[notifyType] or BobloNEXT.Theme.Accent
	local iconName   = opts.Icon or NotifyIcons[notifyType] or NotifyIcons.info
 
	local holder = GetNotifyHolder()
	BobloNEXT._NotifyCounter = BobloNEXT._NotifyCounter + 1
 
	local dismiss
 
	local card = Instance.new("Frame")
	card.Name = "Notification"
	card.BackgroundColor3 = BobloNEXT.Theme.Surface
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, 0, 0, 0)
	card.LayoutOrder = BobloNEXT._NotifyCounter
	card.ZIndex = Z.Toast
	card.Visible = false
	card.Parent = holder
	Corner(card, 12)
	local stroke = Stroke(card, Color3.new(1, 1, 1), 1, 1)
	local notificationAcrylic = nil
	local scale = Instance.new("UIScale")
	scale.Scale = 0.88
	scale.Parent = card
 
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = card
 
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card
 
	local headerRow = Instance.new("Frame")
	headerRow.BackgroundTransparency = 1
	headerRow.AutomaticSize = Enum.AutomaticSize.XY
	headerRow.Size = UDim2.new(0, 0, 0, 0)
	headerRow.LayoutOrder = 1
	headerRow.ZIndex = Z.Toast + 1
	headerRow.Parent = card
 
	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Horizontal
	headerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	headerLayout.Padding = UDim.new(0, 7)
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Parent = headerRow
 
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = ResolveIcon(iconName)
	icon.ImageColor3 = color
	icon.ImageTransparency = 1
	icon.Size = UDim2.fromOffset(14, 14)
	icon.LayoutOrder = 1
	icon.ZIndex = Z.Toast + 1
	icon.Parent = headerRow
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = BobloNEXT.Theme.Font
	titleLabel.Text = title
	titleLabel.TextColor3 = BobloNEXT.Theme.Text
	titleLabel.TextTransparency = 1
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.AutomaticSize = Enum.AutomaticSize.XY
	titleLabel.Size = UDim2.fromOffset(0, 14)
	titleLabel.LayoutOrder = 2
	titleLabel.ZIndex = Z.Toast + 1
	titleLabel.Parent = headerRow
 
	local textLabel
	if text ~= "" then
		textLabel = Instance.new("TextLabel")
		textLabel.BackgroundTransparency = 1
		textLabel.FontFace = BobloNEXT.Theme.FontRegular
		textLabel.Text = text
		textLabel.TextColor3 = BobloNEXT.Theme.TextDim
		textLabel.TextTransparency = 1
		textLabel.TextSize = 12
		textLabel.TextWrapped = true
		textLabel.TextXAlignment = Enum.TextXAlignment.Left
		textLabel.AutomaticSize = Enum.AutomaticSize.Y
		textLabel.LayoutOrder = 2
		textLabel.Size = UDim2.new(1, 0, 0, 14)
		textLabel.ZIndex = Z.Toast + 1
		textLabel.Parent = card
	end
 
	local actionButtons = {}
	if type(opts.Actions) == "table" and #opts.Actions > 0 then
		local actionsRow = Instance.new("Frame")
		actionsRow.Name = "Actions"
		actionsRow.BackgroundTransparency = 1
		actionsRow.AutomaticSize = Enum.AutomaticSize.Y
		actionsRow.Size = UDim2.new(1, 0, 0, 0)
		actionsRow.LayoutOrder = 3
		actionsRow.ZIndex = Z.Toast + 1
		actionsRow.Parent = card
 
		local actionsLayout = Instance.new("UIListLayout")
		actionsLayout.FillDirection = Enum.FillDirection.Horizontal
		actionsLayout.Padding = UDim.new(0, 6)
		actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		actionsLayout.Parent = actionsRow
 
		for i, action in ipairs(opts.Actions) do
			local btn = Instance.new("TextButton")
			btn.AutoButtonColor = false
			btn.BackgroundColor3 = color
			btn.BackgroundTransparency = 1
			btn.BorderSizePixel = 0
			btn.Text = ""
			btn.AutomaticSize = Enum.AutomaticSize.X
			btn.Size = UDim2.fromOffset(0, 22)
			btn.LayoutOrder = i
			btn.ZIndex = Z.Toast + 1
			btn.Parent = actionsRow
			Corner(btn, 6)
			local btnStroke = Stroke(btn, color, 1, 1)
 
			local btnPad = Instance.new("UIPadding")
			btnPad.PaddingLeft = UDim.new(0, 8)
			btnPad.PaddingRight = UDim.new(0, 8)
			btnPad.Parent = btn
 
			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.FontFace = BobloNEXT.Theme.Font
			lbl.Text = action.Text or "Action"
			lbl.TextColor3 = color
			lbl.TextTransparency = 1
			lbl.TextSize = 12
			lbl.AutomaticSize = Enum.AutomaticSize.X
			lbl.Size = UDim2.fromOffset(0, 22)
			lbl.ZIndex = Z.Toast + 2
			lbl.Parent = btn
 
			Tween(btn, { BackgroundTransparency = 0.85 }, 0.28)
			Tween(btnStroke, { Transparency = 0.6 }, 0.28)
			Tween(lbl, { TextTransparency = 0 }, 0.28)
 
			btn.MouseEnter:Connect(function() Tween(btn, { BackgroundTransparency = 0.7 }, 0.12) end)
			btn.MouseLeave:Connect(function() Tween(btn, { BackgroundTransparency = 0.85 }, 0.12) end)
			btn.MouseButton1Click:Connect(function()
				if action.Callback then task.spawn(action.Callback) end
				if action.DismissOnClick ~= false then dismiss() end
			end)
 
			table.insert(actionButtons, { Button = btn, Stroke = btnStroke, Label = lbl })
		end
	end
 
	local barHolder = Instance.new("Frame")
	barHolder.BackgroundColor3 = Color3.new(1, 1, 1)
	barHolder.BackgroundTransparency = 1
	barHolder.BorderSizePixel = 0
	barHolder.Size = UDim2.new(1, 0, 0, 3)
	barHolder.LayoutOrder = 4
	barHolder.ZIndex = Z.Toast + 1
	barHolder.Parent = card
	Corner(barHolder, 2)
 
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = color
	bar.BackgroundTransparency = 1
	bar.BorderSizePixel = 0
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.new(0, 0, 0.5, 0)
	bar.Size = UDim2.fromScale(1, 1)
	bar.ZIndex = Z.Toast + 2
	bar.Parent = barHolder
	Corner(bar, 2)
 
	local barGradient = Instance.new("UIGradient")
	barGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(1, 1, 1), 0.4)),
		ColorSequenceKeypoint.new(1, color),
	})
	barGradient.Parent = bar
 
 
	local dismissed = false
	function dismiss()
		if dismissed or not card.Parent then return end
		dismissed = true
		if not card.Visible then card:Destroy(); return end
 
		local currentHeight = card.AbsoluteSize.Y / GetUIScale()
		card.AutomaticSize = Enum.AutomaticSize.None
		card.Size = UDim2.new(1, 0, 0, currentHeight)
 
		Tween(card, { BackgroundTransparency = 1 }, 0.16)
		Tween(stroke, { Transparency = 1 }, 0.16)
		Tween(scale, { Scale = 0.9 }, 0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		Tween(icon, { ImageTransparency = 1 }, 0.16)
		Tween(titleLabel, { TextTransparency = 1 }, 0.16)
		if textLabel then Tween(textLabel, { TextTransparency = 1 }, 0.16) end
 
		task.delay(0.1, function()
			if card and card.Parent then
				Tween(card, { Size = UDim2.new(1, 0, 0, 0) }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			end
		end)
 
		task.delay(0.34, function()
			if notificationAcrylic then
				notificationAcrylic:Destroy()
				notificationAcrylic = nil
			end
			if card then card:Destroy() end
		end)
	end
 
	local function startNotification()
		if dismissed or not card.Parent then return end
		card.Visible = true
		notificationAcrylic = CreateWindowAcrylic(card)
	Tween(card, { BackgroundTransparency = 0.25 }, 0.28)
	Tween(stroke, { Transparency = 0.82 }, 0.28)
	Tween(scale, { Scale = 1 }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	Tween(icon, { ImageTransparency = 0 }, 0.28)
	Tween(titleLabel, { TextTransparency = 0 }, 0.28)
	Tween(barHolder, { BackgroundTransparency = 0.88 }, 0.28)
	Tween(bar, { BackgroundTransparency = 0 }, 0.28)
	if textLabel then
		Tween(textLabel, { TextTransparency = 0 }, 0.28)
	end
 
	task.delay(0.05, function()
		if bar and bar.Parent then
			Tween(bar, { Size = UDim2.new(0, 0, 1, 0) }, duration - 0.05,
				Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
		end
	end)
 
		task.delay(duration, dismiss)
	end
	table.insert(NotificationQueue, { Card = card, Start = startNotification })
 
	return {
		Instance = card,
		Dismiss = dismiss,
	}
end
 
local function ComputeDialogCenter(anchorFrame)
	local view = ViewportSize()
	if not anchorFrame or anchorFrame.AbsoluteSize.X <= 0 then
		return view.X / 2, view.Y / 2
	end
	local pos, size = anchorFrame.AbsolutePosition, anchorFrame.AbsoluteSize
	local cx = SafeClamp(pos.X + size.X / 2, 190, math.max(190, view.X - 190))
	local cy = SafeClamp(pos.Y + size.Y / 2, 110, math.max(110, view.Y - 110))
	return cx, cy
end
 
function BobloNEXT:Confirm(opts)
	opts = opts or {}
	local title       = opts.Title or "Confirm"
	local text        = opts.Text or ""
	local confirmText = opts.ConfirmText or "Confirm"
	local cancelText  = opts.CancelText or "Cancel"
	local danger      = opts.Danger == true
	local anchorFrame = opts.Window
	if type(anchorFrame) == "table" then
		anchorFrame = anchorFrame._gui
	end
 
	local root = BobloNEXT._Root
	local jan = Janitor.new()
 
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "ConfirmBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = Z.Modal
	backdrop.Parent = root
 
	local dialog = Instance.new("Frame")
	dialog.Name = "ConfirmDialog"
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	do
		local cx, cy = ComputeDialogCenter(anchorFrame)
		local s = GetUIScale()
		dialog.Position = UDim2.fromOffset(math.round(cx / s), math.round(cy / s))
	end
	dialog.BackgroundColor3 = BobloNEXT.Theme.Surface
	dialog.BackgroundTransparency = 1
	dialog.BorderSizePixel = 0
	dialog.Active = true
	dialog.ClipsDescendants = true
	dialog.AutomaticSize = Enum.AutomaticSize.Y
	dialog.Size = UDim2.new(0, 340, 0, 0)
	dialog.ZIndex = Z.ModalTop
	dialog.Parent = backdrop
	Corner(dialog, 16)
	local dialogStroke = Stroke(dialog, Color3.new(1, 1, 1), 1, 1)
 
	local scale = Instance.new("UIScale")
	scale.Scale = 0.9
	scale.Parent = dialog
 
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 20)
	padding.PaddingBottom = UDim.new(0, 18)
	padding.PaddingLeft = UDim.new(0, 20)
	padding.PaddingRight = UDim.new(0, 20)
	padding.Parent = dialog
 
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = dialog
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = BobloNEXT.Theme.Font
	titleLabel.Text = title
	titleLabel.TextColor3 = danger and BobloNEXT.Theme.Danger or BobloNEXT.Theme.Text
	titleLabel.TextTransparency = 1
	titleLabel.TextSize = 18
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextWrapped = true
	titleLabel.AutomaticSize = Enum.AutomaticSize.Y
	titleLabel.Size = UDim2.new(1, 0, 0, 20)
	titleLabel.LayoutOrder = 1
	titleLabel.ZIndex = Z.ModalTop + 1
	titleLabel.Parent = dialog
 
	local textLabel
	if text ~= "" then
		textLabel = Instance.new("TextLabel")
		textLabel.BackgroundTransparency = 1
		textLabel.FontFace = BobloNEXT.Theme.FontRegular
		textLabel.Text = text
		textLabel.TextColor3 = BobloNEXT.Theme.TextDim
		textLabel.TextTransparency = 1
		textLabel.TextSize = 14
		textLabel.TextWrapped = true
		textLabel.TextXAlignment = Enum.TextXAlignment.Left
		textLabel.LineHeight = 1.25
		textLabel.AutomaticSize = Enum.AutomaticSize.Y
		textLabel.Size = UDim2.new(1, 0, 0, 14)
		textLabel.LayoutOrder = 2
		textLabel.ZIndex = Z.ModalTop + 1
		textLabel.Parent = dialog
	end
 
	local buttonsRow = Instance.new("Frame")
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.Size = UDim2.new(1, 0, 0, 38)
	buttonsRow.LayoutOrder = 3
	buttonsRow.ZIndex = Z.ModalTop + 1
	buttonsRow.Parent = dialog
 
	local rowPad = Instance.new("UIPadding")
	rowPad.PaddingTop = UDim.new(0, 6)
	rowPad.Parent = buttonsRow
 
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = buttonsRow
 
	local function makeButton(text_, order, filled)
		local tint = (filled and danger) and BobloNEXT.Theme.Danger or Color3.new(1, 1, 1)
 
		local btn = Instance.new("TextButton")
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = tint
		btn.BackgroundTransparency = filled and (danger and 0.55 or 0.82) or 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(0.5, -4, 1, 0)
		btn.LayoutOrder = order
		btn.ZIndex = Z.ModalTop + 1
		btn.Parent = buttonsRow
		Corner(btn, 10)
		local btnStroke = Stroke(btn, tint, 1, filled and 0.7 or 0.85)
 
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.FontFace = BobloNEXT.Theme.Font
		lbl.Text = text_
		lbl.TextColor3 = (filled and danger) and BobloNEXT.Theme.Danger or BobloNEXT.Theme.Text
		lbl.TextSize = 14
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.ZIndex = Z.ModalTop + 2
		lbl.Parent = btn
 
		local baseBg = btn.BackgroundTransparency
		local baseStroke = btnStroke.Transparency
 
		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = math.max(baseBg - 0.1, 0) }, 0.12)
			Tween(btnStroke, { Transparency = math.max(baseStroke - 0.15, 0) }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = baseBg }, 0.12)
			Tween(btnStroke, { Transparency = baseStroke }, 0.12)
		end))
 
		return btn
	end
 
	local cancelBtn  = makeButton(cancelText, 1, false)
	local confirmBtn = makeButton(confirmText, 2, true)
 
	local closed = false
	local function close(confirmed)
		if closed then return end
		closed = true
 
		Tween(scale, { Scale = 0.94 }, 0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		Tween(dialog, { BackgroundTransparency = 1 }, 0.15)
		Tween(dialogStroke, { Transparency = 1 }, 0.15)
		Tween(backdrop, { BackgroundTransparency = 1 }, 0.15)
		Tween(titleLabel, { TextTransparency = 1 }, 0.12)
		if textLabel then Tween(textLabel, { TextTransparency = 1 }, 0.12) end
 
		task.delay(0.18, function()
			jan:Destroy()
			if backdrop then backdrop:Destroy() end
		end)
 
		if opts.Callback then task.spawn(opts.Callback, confirmed) end
	end
 
	jan:Add(backdrop.MouseButton1Click:Connect(function() close(false) end))
	jan:Add(cancelBtn.MouseButton1Click:Connect(function() close(false) end))
	jan:Add(confirmBtn.MouseButton1Click:Connect(function() close(true) end))
 
	jan:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or closed then return end
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			close(true)
		elseif input.KeyCode == Enum.KeyCode.Escape then
			close(false)
		end
	end))
 
	Tween(backdrop, { BackgroundTransparency = 0.5 }, 0.18)
	Tween(dialog, { BackgroundTransparency = 0 }, 0.18)
	Tween(dialogStroke, { Transparency = 0.8 }, 0.18)
	Tween(titleLabel, { TextTransparency = 0 }, 0.2)
	if textLabel then Tween(textLabel, { TextTransparency = 0 }, 0.2) end
	Tween(scale, { Scale = 1 }, 0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
 
	return { Close = close }
end
 
function BobloNEXT:Modal(opts)
	opts = opts or {}
	local title       = opts.Title or "Modal"
	local text        = opts.Text or ""
	local confirmText = opts.ConfirmText or "Confirm"
	local cancelText  = opts.CancelText or "Cancel"
	local danger      = opts.Danger == true
	local fields      = opts.Fields or {}
	local anchorFrame = opts.Window
	if type(anchorFrame) == "table" then
		anchorFrame = anchorFrame._gui
	end
 
	local root = BobloNEXT._Root
	local jan = Janitor.new()
 
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "ModalBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = Z.Modal
	backdrop.Parent = root
 
	local dialog = Instance.new("Frame")
	dialog.Name = "ModalDialog"
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	do
		local cx, cy = ComputeDialogCenter(anchorFrame)
		local s = GetUIScale()
		dialog.Position = UDim2.fromOffset(math.round(cx / s), math.round(cy / s))
	end
	dialog.BackgroundColor3 = BobloNEXT.Theme.Surface
	dialog.BackgroundTransparency = 1
	dialog.BorderSizePixel = 0
	dialog.Active = true
	dialog.ClipsDescendants = true
	dialog.AutomaticSize = Enum.AutomaticSize.Y
	dialog.Size = UDim2.new(0, 360, 0, 0)
	dialog.ZIndex = Z.ModalTop
	dialog.Parent = backdrop
	Corner(dialog, 16)
	local dialogStroke = Stroke(dialog, Color3.new(1, 1, 1), 1, 1)
 
	local scale = Instance.new("UIScale")
	scale.Scale = 0.9
	scale.Parent = dialog
 
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 20)
	padding.PaddingBottom = UDim.new(0, 18)
	padding.PaddingLeft = UDim.new(0, 20)
	padding.PaddingRight = UDim.new(0, 20)
	padding.Parent = dialog
 
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = dialog
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = BobloNEXT.Theme.Font
	titleLabel.Text = title
	titleLabel.TextColor3 = danger and BobloNEXT.Theme.Danger or BobloNEXT.Theme.Text
	titleLabel.TextTransparency = 1
	titleLabel.TextSize = 18
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextWrapped = true
	titleLabel.AutomaticSize = Enum.AutomaticSize.Y
	titleLabel.Size = UDim2.new(1, 0, 0, 20)
	titleLabel.LayoutOrder = 1
	titleLabel.ZIndex = Z.ModalTop + 1
	titleLabel.Parent = dialog
 
	local textLabel
	if text ~= "" then
		textLabel = Instance.new("TextLabel")
		textLabel.BackgroundTransparency = 1
		textLabel.FontFace = BobloNEXT.Theme.FontRegular
		textLabel.Text = text
		textLabel.TextColor3 = BobloNEXT.Theme.TextDim
		textLabel.TextTransparency = 1
		textLabel.TextSize = 13
		textLabel.TextWrapped = true
		textLabel.TextXAlignment = Enum.TextXAlignment.Left
		textLabel.LineHeight = 1.25
		textLabel.AutomaticSize = Enum.AutomaticSize.Y
		textLabel.Size = UDim2.new(1, 0, 0, 14)
		textLabel.LayoutOrder = 2
		textLabel.ZIndex = Z.ModalTop + 1
		textLabel.Parent = dialog
	end
 
	local fieldsHolder = Instance.new("Frame")
	fieldsHolder.BackgroundTransparency = 1
	fieldsHolder.AutomaticSize = Enum.AutomaticSize.Y
	fieldsHolder.Size = UDim2.new(1, 0, 0, 0)
	fieldsHolder.LayoutOrder = 3
	fieldsHolder.ZIndex = Z.ModalTop + 1
	fieldsHolder.Parent = dialog
 
	local fieldsLayout = Instance.new("UIListLayout")
	fieldsLayout.Padding = UDim.new(0, 10)
	fieldsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	fieldsLayout.Parent = fieldsHolder
 
	local fieldBoxes = {}
 
	for i, field in ipairs(fields) do
		local isTextarea = field.Type == "textarea"
		local labelH = field.Label and field.Label ~= "" and 16 or 0
		local boxH = isTextarea and 60 or 34
 
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.AutomaticSize = Enum.AutomaticSize.Y
		holder.Size = UDim2.new(1, 0, 0, 0)
		holder.LayoutOrder = i
		holder.ZIndex = Z.ModalTop + 1
		holder.Parent = fieldsHolder
 
		local holderLayout = Instance.new("UIListLayout")
		holderLayout.Padding = UDim.new(0, 4)
		holderLayout.SortOrder = Enum.SortOrder.LayoutOrder
		holderLayout.Parent = holder
 
		if labelH > 0 then
			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.FontFace = BobloNEXT.Theme.FontRegular
			lbl.Text = string.upper(field.Label)
			lbl.TextColor3 = danger and BobloNEXT.Theme.Danger or BobloNEXT.Theme.TextDim
			lbl.TextSize = 11
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.Size = UDim2.new(1, 0, 0, labelH)
			lbl.LayoutOrder = 1
			lbl.ZIndex = Z.ModalTop + 2
			lbl.Parent = holder
		end
 
		local fieldFrame = Instance.new("Frame")
		fieldFrame.BackgroundColor3 = Color3.new(1, 1, 1)
		fieldFrame.BackgroundTransparency = 0.93
		fieldFrame.BorderSizePixel = 0
		fieldFrame.Size = UDim2.new(1, 0, 0, boxH)
		fieldFrame.LayoutOrder = 2
		fieldFrame.ZIndex = Z.ModalTop + 2
		fieldFrame.Parent = holder
		Corner(fieldFrame, 9)
		local fieldStroke = Stroke(fieldFrame, Color3.new(1, 1, 1), 1, 0.88)
 
		local fieldPad = Instance.new("UIPadding")
		fieldPad.PaddingLeft = UDim.new(0, 10)
		fieldPad.PaddingRight = UDim.new(0, 10)
		fieldPad.PaddingTop = UDim.new(0, isTextarea and 8 or 0)
		fieldPad.Parent = fieldFrame
 
		local box = Instance.new("TextBox")
		box.ClearTextOnFocus = false
		box.MultiLine = isTextarea
		box.FontFace = BobloNEXT.Theme.FontRegular
		box.PlaceholderText = field.Placeholder or ""
		box.PlaceholderColor3 = Color3.fromRGB(120, 120, 122)
		box.Text = tostring(field.Default or "")
		box.TextColor3 = BobloNEXT.Theme.Text
		box.TextSize = 13
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.TextYAlignment = isTextarea and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
		box.TextWrapped = isTextarea
		box.ClipsDescendants = true
		box.BackgroundTransparency = 1
		box.Size = UDim2.fromScale(1, 1)
		box.ZIndex = Z.ModalTop + 3
		box.Parent = fieldFrame
 
		if field.MaxLength then
			jan:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
				if utf8.len(box.Text) and utf8.len(box.Text) > field.MaxLength then
					box.Text = string.sub(box.Text, 1, field.MaxLength)
				end
			end))
		end
 
		jan:Add(box.Focused:Connect(function()
			Tween(fieldStroke, { Color = BobloNEXT.Theme.Accent, Transparency = 0.3 }, 0.15)
			Tween(fieldFrame, { BackgroundTransparency = 0.85 }, 0.15)
		end))
		jan:Add(box.FocusLost:Connect(function()
			Tween(fieldStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.88 }, 0.15)
			Tween(fieldFrame, { BackgroundTransparency = 0.93 }, 0.15)
		end))
 
		fieldBoxes[field.Key or i] = { Type = field.Type, Box = box }
	end
 
	local buttonsRow = Instance.new("Frame")
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.Size = UDim2.new(1, 0, 0, 38)
	buttonsRow.LayoutOrder = 4
	buttonsRow.ZIndex = Z.ModalTop + 1
	buttonsRow.Parent = dialog
 
	local rowPad = Instance.new("UIPadding")
	rowPad.PaddingTop = UDim.new(0, 4)
	rowPad.Parent = buttonsRow
 
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = buttonsRow
 
	local function makeButton(text_, order, filled)
		local tint = (filled and danger) and BobloNEXT.Theme.Danger or Color3.new(1, 1, 1)
 
		local btn = Instance.new("TextButton")
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = tint
		btn.BackgroundTransparency = filled and (danger and 0.55 or 0.82) or 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(0.5, -4, 1, 0)
		btn.LayoutOrder = order
		btn.ZIndex = Z.ModalTop + 1
		btn.Parent = buttonsRow
		Corner(btn, 10)
		local btnStroke = Stroke(btn, tint, 1, filled and 0.7 or 0.85)
 
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.FontFace = BobloNEXT.Theme.Font
		lbl.Text = text_
		lbl.TextColor3 = (filled and danger) and BobloNEXT.Theme.Danger or BobloNEXT.Theme.Text
		lbl.TextSize = 14
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.ZIndex = Z.ModalTop + 2
		lbl.Parent = btn
 
		local baseBg = btn.BackgroundTransparency
		local baseStroke = btnStroke.Transparency
 
		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = math.max(baseBg - 0.1, 0) }, 0.12)
			Tween(btnStroke, { Transparency = math.max(baseStroke - 0.15, 0) }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = baseBg }, 0.12)
			Tween(btnStroke, { Transparency = baseStroke }, 0.12)
		end))
 
		return btn
	end
 
	local cancelBtn  = makeButton(cancelText, 1, false)
	local confirmBtn = makeButton(confirmText, 2, true)
 
	local function collectValues()
		local values = {}
		for key, entry in pairs(fieldBoxes) do
			if entry.Type == "tags" then
				local list = {}
				for piece in string.gmatch(entry.Box.Text, "[^,]+") do
					local trimmed = piece:gsub("^%s+", ""):gsub("%s+$", "")
					if trimmed ~= "" then table.insert(list, trimmed) end
				end
				values[key] = list
			else
				values[key] = entry.Box.Text
			end
		end
		return values
	end
 
	local closed = false
	local function close(confirmed)
		if closed then return end
		closed = true
 
		Tween(scale, { Scale = 0.94 }, 0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		Tween(dialog, { BackgroundTransparency = 1 }, 0.15)
		Tween(dialogStroke, { Transparency = 1 }, 0.15)
		Tween(backdrop, { BackgroundTransparency = 1 }, 0.15)
		Tween(titleLabel, { TextTransparency = 1 }, 0.12)
		if textLabel then Tween(textLabel, { TextTransparency = 1 }, 0.12) end
 
		task.delay(0.18, function()
			jan:Destroy()
			if backdrop then backdrop:Destroy() end
		end)
 
		if opts.Callback then
			task.spawn(opts.Callback, confirmed, confirmed and collectValues() or nil)
		end
	end
 
	jan:Add(backdrop.MouseButton1Click:Connect(function() close(false) end))
	jan:Add(cancelBtn.MouseButton1Click:Connect(function() close(false) end))
	jan:Add(confirmBtn.MouseButton1Click:Connect(function() close(true) end))
 
	jan:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or closed then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			close(false)
		end
	end))
 
	Tween(backdrop, { BackgroundTransparency = 0.5 }, 0.18)
	Tween(dialog, { BackgroundTransparency = 0 }, 0.18)
	Tween(dialogStroke, { Transparency = 0.8 }, 0.18)
	Tween(titleLabel, { TextTransparency = 0 }, 0.2)
	if textLabel then Tween(textLabel, { TextTransparency = 0 }, 0.2) end
	Tween(scale, { Scale = 1 }, 0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
 
	return { Close = close }
end
 
local DRAG_SMOOTH_SPEED = 22
 
local function SetupSmoothDrag(frame, handle, janitor)
	handle = handle or frame
 
	local detector = handle:FindFirstChildWhichIsA("UIDragDetector")
	if detector then detector.Enabled = false end
 
	local dragging = false
	local settling = false
	local mouseOffset = Vector2.zero
	local activeInput = nil
 
	local function frameOffset()
		local pos = frame.Position
		local parentSize = ViewportSize()
		if frame.Parent and frame.Parent:IsA("GuiObject") and frame.Parent.AbsoluteSize.X > 0 then
			parentSize = frame.Parent.AbsoluteSize
		end
		local s = GetUIScale()
		return Vector2.new(
			pos.X.Scale * parentSize.X + pos.X.Offset * s,
			pos.Y.Scale * parentSize.Y + pos.Y.Offset * s
		)
	end
 
	local currentPosition = frameOffset()
	local targetPosition = currentPosition
 
	local function clampToScreen(pos)
		local view = ViewportSize()
		local size = frame.AbsoluteSize
		local anchor = frame.AnchorPoint
		local minVisible = 60
		local left = pos.X - size.X * anchor.X
		local top  = pos.Y - size.Y * anchor.Y
		left = SafeClamp(left, -size.X + minVisible, view.X - minVisible)
		-- A ScreenGui vive abaixo do inset do topo, entao travar em 0 era o teto invisivel
		-- que impedia arrastar a janela pra cima. -inset.Y libera ate a borda real da tela.
		top  = SafeClamp(top, -GuiService:GetGuiInset().Y, view.Y - minVisible)
		return Vector2.new(left + size.X * anchor.X, top + size.Y * anchor.Y)
	end
 
	local api = {}
 
	function api.Sync()
		currentPosition = frameOffset()
		targetPosition = currentPosition
		settling = false
	end
 
	janitor:Add(handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if dragging then return end
		dragging = true
		settling = true
		activeInput = input
		currentPosition = frameOffset()
		targetPosition = currentPosition
		mouseOffset = Vector2.new(input.Position.X, input.Position.Y) - currentPosition
	end))
 
	janitor:Add(UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch
			and activeInput and input ~= activeInput then
			return
		end
		targetPosition = clampToScreen(
			Vector2.new(input.Position.X, input.Position.Y) - mouseOffset
		)
	end))
 
	janitor:Add(UserInputService.InputEnded:Connect(function(input)
		if input == activeInput
			or (activeInput and activeInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = false
			activeInput = nil
		end
	end))
 
	janitor:Add(RunService.RenderStepped:Connect(function(dt)
		if not dragging and not settling then return end
		if not frame.Parent then return end
 
		local alpha = 1 - math.exp(-DRAG_SMOOTH_SPEED * dt)
		currentPosition = currentPosition:Lerp(targetPosition, alpha)
 
		if not dragging and (currentPosition - targetPosition).Magnitude < 0.5 then
			currentPosition = targetPosition
			settling = false
		end
 
		local s = GetUIScale()
		frame.Position = UDim2.fromOffset(
			math.round(currentPosition.X / s),
			math.round(currentPosition.Y / s)
		)
	end))
 
	return api
end
 
local function SetupResize(frame, handle, janitor, opts)
	opts = opts or {}
	local minSize = opts.MinSize or Vector2.new(420, 300)
	local onResize = opts.OnResize
 
	local resizing = false
	local startSize, startTopLeft, startInput, activeInput
 
	janitor:Add(handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if resizing then return end
		resizing = true
		activeInput = input
		startSize = frame.AbsoluteSize
		startTopLeft = frame.AbsolutePosition
		startInput = Vector2.new(input.Position.X, input.Position.Y)
	end))
 
	janitor:Add(UserInputService.InputChanged:Connect(function(input)
		if not resizing then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch
			and activeInput and input ~= activeInput then
			return
		end
 
		local view = ViewportSize()
		local delta = Vector2.new(input.Position.X, input.Position.Y) - startInput
		local maxW = math.max(view.X - startTopLeft.X - 8, 100)
		local maxH = math.max(view.Y - startTopLeft.Y - 8, 100)
		local newW = SafeClamp(startSize.X + delta.X, math.min(minSize.X, maxW), maxW)
		local newH = SafeClamp(startSize.Y + delta.Y, math.min(minSize.Y, maxH), maxH)
 
		local s = GetUIScale()
		frame.Size = UDim2.fromOffset(math.round(newW / s), math.round(newH / s))
 
		local centerX = startTopLeft.X + newW / 2
		local centerY = startTopLeft.Y + newH / 2
		frame.Position = UDim2.fromOffset(math.round(centerX / s), math.round(centerY / s))
 
		if onResize then onResize(frame.Size, false) end
	end))
 
	janitor:Add(UserInputService.InputEnded:Connect(function(input)
		if not resizing then return end
		if input == activeInput
			or (activeInput and activeInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1) then
			resizing = false
			activeInput = nil
			if onResize then onResize(frame.Size, true) end
		end
	end))
end
 
local DRAG_THRESHOLD = 6
 
local function BaseCard(parent, height)
	local card = Instance.new("Frame")
	card.BackgroundColor3 = BobloNEXT.Theme.SurfaceHigh
	card.BackgroundTransparency = 0.12
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, height or 44)
	card.ZIndex = Z.Content
	card.Parent = parent
	ThemeBind(card, "BackgroundColor3", "SurfaceHigh")
	Corner(card, BobloNEXT.Theme.CornerRadiusSm)
	local cardStroke = Stroke(card, BobloNEXT.Theme.Border, 1, 0.55)
	ThemeBind(cardStroke, "Color", "Border")
	return card
end
 
local function AddLeadingIcon(card, icon, height)
	local asset = icon and ResolveIcon(icon) or ""
	if asset == "" then return 14, nil end
 
	local img = Instance.new("ImageLabel")
	img.Name = "LeadingIcon"
	img.BackgroundTransparency = 1
	img.Image = asset
	ThemeBind(img, "ImageColor3", "TextDim")
	img.Size = UDim2.fromOffset(16, 16)
	img.AnchorPoint = Vector2.new(0, 0.5)
	img.Position = UDim2.new(0, 14, 0.5, 0)
	img.ZIndex = Z.Content + 1
	img.Parent = card
	return 14 + 16 + 10, img
end
 
local function AddTitleDesc(card, x, rightReserve, title, description, baseHeight, extraBottom)
	extraBottom = extraBottom or 0
	local hasDesc = description ~= nil and description ~= ""
	local titleH, descH, gap = 16, 14, 3
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = BobloNEXT.Theme.Font
	titleLabel.Text = title
	ThemeBind(titleLabel, "TextColor3", "Text")
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextYAlignment = Enum.TextYAlignment.Center
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Size = UDim2.new(1, -(x + (type(rightReserve) == "function" and rightReserve() or rightReserve)), 0, titleH)
	titleLabel.Position = UDim2.fromOffset(x, 0)
	titleLabel.ZIndex = Z.Content + 1
	titleLabel.Parent = card
 
	local descLabel
	if hasDesc then
		descLabel = Instance.new("TextLabel")
		descLabel.Name = "Description"
		descLabel.BackgroundTransparency = 1
		descLabel.FontFace = BobloNEXT.Theme.FontRegular
		descLabel.Text = description
		ThemeBind(descLabel, "TextColor3", "TextDim")
		descLabel.TextSize = 12
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.Size = UDim2.new(1, -(x + (type(rightReserve) == "function" and rightReserve() or rightReserve)), 0, descH)
		descLabel.Position = UDim2.fromOffset(x, titleH + gap)
		descLabel.ZIndex = Z.Content + 1
		descLabel.Parent = card
	end
 
	local lastWidth = -1
	local lastReserve = -1
 
	local function relayout()
		local cardW = card.AbsoluteSize.X / GetUIScale()
		if cardW <= 0 then return end
		local reserve = type(rightReserve) == "function" and rightReserve() or rightReserve
		if math.abs(cardW - lastWidth) < 1 and reserve == lastReserve then return end
		lastReserve = reserve
		titleLabel.Size = UDim2.new(1, -(x + reserve), 0, titleH)
		lastWidth = cardW
 
		local avail = math.max(cardW - x - reserve, 1)
		local realDescH = descH
		if hasDesc then
			local _, h = MeasureText(description, 12, avail)
			realDescH = math.max(descH, h)
			descLabel.Size = UDim2.new(1, -(x + (type(rightReserve) == "function" and rightReserve() or rightReserve)), 0, realDescH)
		end
 
		local blockH = hasDesc and (titleH + gap + realDescH) or titleH
		local topPortion = math.max(baseHeight, blockH + 18)
		card.Size = UDim2.new(1, 0, 0, topPortion + extraBottom)
 
		local top = math.floor((topPortion - blockH) / 2)
		titleLabel.Position = UDim2.fromOffset(x, top)
		if hasDesc then
			descLabel.Position = UDim2.fromOffset(x, top + titleH + gap)
		end
	end
 
	card:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	task.defer(relayout)
 
	return titleLabel, descLabel, relayout
end
 
local function AddEmptyState(scroll, overlayParent, janitor)
	local emptyState = Instance.new("Frame")
	emptyState.Name = "EmptyState"
	emptyState.BackgroundTransparency = 1
	emptyState.Size = UDim2.fromScale(1, 1)
	emptyState.ZIndex = (scroll.ZIndex or 0) + 5
	emptyState.Parent = overlayParent
 
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = emptyState
 
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = ResolveIcon("frown")
	icon.ImageColor3 = BobloNEXT.Theme.TextDim
	icon.Size = UDim2.fromOffset(26, 26)
	icon.LayoutOrder = 1
	icon.ZIndex = emptyState.ZIndex + 1
	icon.Parent = emptyState
 
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = BobloNEXT.Theme.FontRegular
	label.Text = "There's nothing here yet"
	label.TextColor3 = BobloNEXT.Theme.TextDim
	label.TextSize = 13
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 16)
	label.LayoutOrder = 2
	label.ZIndex = emptyState.ZIndex + 1
	label.Parent = emptyState
 
	local function update()
		local hasContent = false
		for _, child in ipairs(scroll:GetChildren()) do
			local cn = child.ClassName
			if cn ~= "UIListLayout" and cn ~= "UIPadding" then
				hasContent = true
				break
			end
		end
		emptyState.Visible = not hasContent
	end
 
	janitor:Add(scroll.ChildAdded:Connect(update))
	janitor:Add(scroll.ChildRemoved:Connect(update))
	update()
 
	return emptyState
end
 
local Window = {}
Window.__index = Window
 
local Tab = {}
Tab.__index = Tab
 
function BobloNEXT:CreateWindow(opts)
	opts = opts or {}
	local size = opts.Size or UDim2.fromOffset(605, 405)
 
	if IsMobileDevice then
		-- Landscape layout: use the available height instead of flattening the window.
		local vp = ViewportSize()
		local s = GetUIScale()
		size = UDim2.fromOffset(
			math.floor((vp.X / s) * 0.64),
			math.floor((vp.Y / s) * 0.96)
		)
	end
	local margin = BobloNEXT.Theme.Margin
 
	local root = BobloNEXT._Root
	local jan = Janitor.new()
 
	local main = Instance.new("Frame")
	main.Name = "Window"
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.Position = UDim2.fromScale(0.5, IsMobileDevice and 0.5 or 0.55)
	main.Size = size
	ThemeBind(main, "BackgroundColor3", "Background")
	main.BackgroundTransparency = 1
	main.BorderSizePixel = 0
	main.ClipsDescendants = true
	main.ZIndex = Z.Window
	main.Parent = root
	Corner(main, BobloNEXT.Theme.CornerRadius)
	local mainStroke = Stroke(main, BobloNEXT.Theme.Border, 1, 0.55)
	ThemeBind(mainStroke, "Color", "Border")
	GlassLayer(main, BobloNEXT.Theme.CornerRadius, 0.985)
 
	local topbar = Instance.new("Frame")
	topbar.Name = "TopBar"
	topbar.BackgroundTransparency = 1
	topbar.Size = UDim2.new(1, 0, 0, 52)
	topbar.ZIndex = Z.Content
	topbar.Parent = main
 
	local controlsHolder = Instance.new("Frame")
	controlsHolder.Name = "WindowControls"
	controlsHolder.AnchorPoint = Vector2.new(1, 0.5)
	controlsHolder.Position = UDim2.new(1, -margin, 0.5, 0)
	controlsHolder.Size = UDim2.fromOffset(120, 26)
	controlsHolder.BackgroundTransparency = 1
	controlsHolder.ZIndex = Z.Content + 1
	controlsHolder.Parent = topbar
 
	local controlsLayout = Instance.new("UIListLayout")
	controlsLayout.FillDirection = Enum.FillDirection.Horizontal
	controlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	controlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	controlsLayout.Padding = UDim.new(0, 4)
	controlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	controlsLayout.Parent = controlsHolder
 
	local function addControl(icon, name, order, hoverColor)
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = BobloNEXT.Theme.SurfaceHigh
		ThemeBind(btn, "BackgroundColor3", "SurfaceHigh")
		btn.BackgroundTransparency = 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.fromOffset(26, 26)
		btn.LayoutOrder = order
		btn.ZIndex = Z.Content + 1
		btn.Parent = controlsHolder
		Corner(btn, 8)
 
		local ic = Instance.new("ImageLabel")
		ic.BackgroundTransparency = 1
		ic.Image = ResolveIcon(icon)
		ThemeBind(ic, "ImageColor3", "TextDim")
		ic.Size = UDim2.fromOffset(14, 14)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.ZIndex = Z.Content + 2
		ic.Parent = btn
 
		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = 0.9 }, 0.12)
			Tween(ic, { ImageColor3 = hoverColor or BobloNEXT.Theme.Text }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = 1 }, 0.12)
			Tween(ic, { ImageColor3 = BobloNEXT.Theme.TextDim }, 0.12)
		end))
		return btn
	end
 
	local searchBtn = addControl("search",   "SearchButton",     1)
	local minBtn    = addControl("minus",    "MinimizeButton",   2)
	local fullBtn   = addControl("maximize", "FullscreenButton", 3)
	local closeBtn  = addControl("x",        "CloseButton",      4)
 
	local titleStartX  = margin + 5
	local titleTextPad = 146
 
	local hasIcon = opts.Icon and opts.Icon ~= ""
	if hasIcon then
		local windowIcon = Instance.new("ImageLabel")
		windowIcon.Name = "WindowIcon"
		windowIcon.BackgroundTransparency = 1
		windowIcon.Image = ResolveIcon(opts.Icon)
		ThemeBind(windowIcon, "ImageColor3", "Text")
		windowIcon.Size = UDim2.fromOffset(20, 20)
		windowIcon.AnchorPoint = Vector2.new(0, 0.5)
		windowIcon.Position = UDim2.new(0, titleStartX, 0.5, 0)
		windowIcon.ZIndex = Z.Content
		windowIcon.Parent = topbar
		titleStartX += 20 + 8
	end
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = BobloNEXT.Theme.Font
	titleLabel.Text = opts.Title or "Window"
	ThemeBind(titleLabel, "TextColor3", "Text")
	titleLabel.TextSize = 16
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextYAlignment = Enum.TextYAlignment.Center
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Position = UDim2.fromOffset(titleStartX, opts.Subtitle and 8 or 0)
	titleLabel.Size = UDim2.new(1, -titleStartX - titleTextPad, 0, 20)
	titleLabel.ZIndex = Z.Content
	titleLabel.Parent = topbar
 
	local subLabel
	if opts.Subtitle then
		subLabel = Instance.new("TextLabel")
		subLabel.Name = "Subtitle"
		subLabel.BackgroundTransparency = 1
		subLabel.FontFace = BobloNEXT.Theme.FontRegular
		subLabel.Text = opts.Subtitle
		ThemeBind(subLabel, "TextColor3", "TextDim")
		subLabel.TextSize = 13
		subLabel.TextXAlignment = Enum.TextXAlignment.Left
		subLabel.TextYAlignment = Enum.TextYAlignment.Center
		subLabel.TextTruncate = Enum.TextTruncate.AtEnd
		subLabel.Position = UDim2.fromOffset(titleStartX, 28)
		subLabel.Size = UDim2.new(1, -titleStartX - titleTextPad, 0, 14)
		subLabel.ZIndex = Z.Content
		subLabel.Parent = topbar
	end
 
	local tabBar = Instance.new("ScrollingFrame")
	tabBar.Name = "TabBar"
	tabBar.BackgroundTransparency = 1
	tabBar.BorderSizePixel = 0
	tabBar.Position = UDim2.fromOffset(margin, 58)
	tabBar.Size = UDim2.new(0, 130, 1, -(58 + margin))
	tabBar.ScrollBarThickness = 0
	tabBar.ScrollingDirection = Enum.ScrollingDirection.Y
	tabBar.AutomaticCanvasSize = Enum.AutomaticSize.Y
	tabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
	tabBar.ZIndex = Z.Content
	tabBar.Parent = main
 
	local tabBarLayout = Instance.new("UIListLayout")
	tabBarLayout.Padding = UDim.new(0, 4)
	tabBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabBarLayout.Parent = tabBar
 
	AddScrollbar(tabBar)
 
	local tabIndicatorLayer = Instance.new("Frame")
	tabIndicatorLayer.Name = "TabIndicatorLayer"
	tabIndicatorLayer.BackgroundTransparency = 1
	tabIndicatorLayer.ClipsDescendants = true
	tabIndicatorLayer.ZIndex = Z.Window
	tabIndicatorLayer.Position = tabBar.Position
	tabIndicatorLayer.Size = tabBar.Size
	tabIndicatorLayer.Parent = main
 
	local tabIndicator = Instance.new("Frame")
	tabIndicator.Name = "Indicator"
	ThemeBind(tabIndicator, "BackgroundColor3", "Accent")
	tabIndicator.BackgroundTransparency = 1
	tabIndicator.BorderSizePixel = 0
	tabIndicator.ZIndex = Z.Window
	tabIndicator.Size = UDim2.new(1, 0, 0, 34)
	tabIndicator.Position = UDim2.new(0, 0, 0, 0)
	tabIndicator.Parent = tabIndicatorLayer
	Corner(tabIndicator, 10)
 
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	ThemeBind(divider, "BackgroundColor3", "Border")
	divider.BackgroundTransparency = 0.94
	divider.BorderSizePixel = 0
	divider.Position = UDim2.new(0, margin + 144, 0, 58)
	divider.Size = UDim2.new(0, 1, 1, -(58 + margin))
	divider.ZIndex = Z.Content
	divider.Parent = main
 
	local contentX = margin + 144 + 16
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.new(0, contentX, 0, 58)
	content.Size = UDim2.new(1, -contentX - margin, 1, -(58 + margin))
	content.ZIndex = Z.Content
	content.Parent = main
 
	local resizeHandle = Instance.new("ImageButton")
	resizeHandle.Name = "ResizeHandle"
	resizeHandle.BackgroundTransparency = 1
	resizeHandle.AutoButtonColor = false
	resizeHandle.Image = "rbxassetid://120997033468887"
	ThemeBind(resizeHandle, "ImageColor3", "TextDim")
	resizeHandle.ImageTransparency = 0.35
	resizeHandle.AnchorPoint = Vector2.new(1, 1)
	resizeHandle.Position = UDim2.new(1, -4, 1, -4)
	resizeHandle.Size = UDim2.fromOffset(16, 16)
	resizeHandle.ZIndex = Z.Content + 4
	resizeHandle.Parent = main
 
	jan:Add(resizeHandle.MouseEnter:Connect(function()
		Tween(resizeHandle, { ImageTransparency = 0 }, 0.12)
	end))
	jan:Add(resizeHandle.MouseLeave:Connect(function()
		Tween(resizeHandle, { ImageTransparency = 0.35 }, 0.12)
	end))
 
	Tween(main, { BackgroundTransparency = 0.15 }, 0.6, Enum.EasingStyle.Exponential)
 
	local self = setmetatable({
		_gui            = main,
		_content        = content,
		_tabBar         = tabBar,
		_tabIndicatorLayer = tabIndicatorLayer,
		_tabIndicator   = tabIndicator,
		_titleLabel     = titleLabel,
		_subLabel       = subLabel,
		_tabs           = {},
		_currentTab     = nil,
		_normalSize     = size,
		_fullscreen     = false,
		_janitor        = jan,
		_state          = "open",
		_busy           = false,
		_destroyed      = false,
		_searchIndex    = {},
		_useBlur        = opts.UseBlur ~= false,
		_defaultTabName = opts.DefaultTab,
		_tabChangeListeners = {},
	}, Window)
 
	table.insert(BobloNEXT._Windows, self)
 
	if opts.Draggable ~= false then
		self._drag = SetupSmoothDrag(main, topbar, jan)
	end
 
	if opts.Resizable ~= false then
		SetupResize(main, resizeHandle, jan, {
			-- No mobile o minimo nao pode ser maior que a janela ja clampada, senao um
			-- resize devolve a janela pro tamanho cortado.
			MinSize = Vector2.new(
				math.min((opts.MinSize or Vector2.new(420, 300)).X, size.X.Offset),
				math.min((opts.MinSize or Vector2.new(420, 300)).Y, size.Y.Offset)
			),
			OnResize = function(newSize, finished)
				if self._fullscreen then return end
				if finished then
					self._normalSize = newSize
					self._sizeBeforeMinimize = newSize
				end
			end,
		})
	else
		resizeHandle.Visible = false
	end
 
	if self._useBlur then
		self._acrylic = CreateWindowAcrylic(main)
		jan:Add(self._acrylic)
	end
 
	jan:Add(closeBtn.MouseButton1Click:Connect(function()
		BobloNEXT:Confirm({
			Title = "Close Window",
			Text = "Do you want to close this window? You will not be able to open it again. "
				.. "If you just want to hide it, use the minimize button instead.",
			ConfirmText = "Close Window",
			CancelText = "Cancel",
			Danger = true,
			Window = self,
			Callback = function(confirmed)
				if confirmed then self:Destroy() end
			end,
		})
	end))
 
	jan:Add(minBtn.MouseButton1Click:Connect(function() self:Toggle() end))
	jan:Add(fullBtn.MouseButton1Click:Connect(function() self:ToggleFullscreen() end))
	jan:Add(searchBtn.MouseButton1Click:Connect(function() self:_OpenSearch() end))
 
	jan:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or KeybindCapturing then return end
		if self._state ~= "open" then return end
		local ctrlDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.LeftMeta)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightMeta)
		if ctrlDown and input.KeyCode == Enum.KeyCode.K then
			self:_OpenSearch()
		end
	end))
 
	local toggleKey = opts.ToggleKeybind
	if toggleKey == nil then
		toggleKey = Enum.KeyCode.RightShift
	end
 
	if toggleKey then
		jan:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or KeybindCapturing then return end
			if UserInputService:GetFocusedTextBox() then return end
			if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == toggleKey then
				self:Toggle()
			end
		end))
	end
 
	if IsMobileDevice then
		local mobileToggle = Instance.new("ImageButton")
		mobileToggle.Name = "MobileToggleButton"
		mobileToggle.BackgroundColor3 = Color3.fromRGB(1, 1, 1)
		mobileToggle.BackgroundTransparency = 1
		mobileToggle.BorderSizePixel = 0
		-- Alinhado com a barra do Roblox: a ScreenGui comeca abaixo do inset, entao
		-- subir inset.Y coloca o botao na mesma faixa das pilulas do topo.
		local topInset  = GuiService:GetGuiInset().Y
		local toggleSize = 45
		local bandY = -(topInset / GetUIScale()) + ((topInset / GetUIScale()) - toggleSize) / 2
 
		mobileToggle.AnchorPoint = Vector2.new(0, 0)
		mobileToggle.Position = opts.TogglePosition or UDim2.fromOffset(300, math.floor(bandY))
		mobileToggle.Size = UDim2.fromOffset(toggleSize, toggleSize)
		mobileToggle.Image = "rbxassetid://136834285051667"
		mobileToggle.ZIndex = Z.Toast
		mobileToggle.Parent = root
 
		local mobileToggleCorner = Instance.new("UICorner")
		mobileToggleCorner.CornerRadius = UDim.new(1, 0)
		mobileToggleCorner.Parent = mobileToggle
 
		-- Draggable is deprecated and swallows touch input (Activated never fires),
		-- so drive the drag by hand and treat a touch that barely moved as a tap.
		local DRAG_SLOP = 8
		local dragInput, dragStart, startPos, dragged
 
		jan:Add(mobileToggle.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch
				and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			if dragInput then return end
			dragInput = input
			dragStart = input.Position
			startPos  = mobileToggle.Position
			dragged   = false
		end))
 
		jan:Add(UserInputService.InputChanged:Connect(function(input)
			if input ~= dragInput or not dragStart then return end
			local delta = input.Position - dragStart
			if not dragged and delta.Magnitude > DRAG_SLOP then dragged = true end
			if not dragged then return end
			local s = GetUIScale()
			mobileToggle.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X / s,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y / s
			)
		end))
 
		jan:Add(UserInputService.InputEnded:Connect(function(input)
			if input ~= dragInput then return end
			dragInput, dragStart = nil, nil
			if not dragged then
				self:Toggle()
			end
		end))
 
		jan:Add(mobileToggle)
	elseif toggleKey then
		BobloNEXT:Notify({
			Title = "Minimize Keybind",
			Text  = "Press " .. toggleKey.Name .. " to minimize or open this panel.",
			Type  = "info",
			Duration = 15,
		})
	end
 
	return self
end
 
function Window:SetTitle(title, subtitle)
	if self._titleLabel then self._titleLabel.Text = title or self._titleLabel.Text end
	if subtitle and self._subLabel then self._subLabel.Text = subtitle end
end
 
function Window:IsOpen()
	return self._state == "open"
end
 
function Window:Destroy()
	if self._destroyed then return end
	self._destroyed = true
 
	local idx = table.find(BobloNEXT._Windows, self)
	if idx then table.remove(BobloNEXT._Windows, idx) end
 
	CloseAnyOpenPopup()
 
	local gui = self._gui
 
	Tween(gui, {
		Size = UDim2.new(gui.Size.X.Scale, gui.Size.X.Offset, 0, 0),
	}, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	Tween(gui, { BackgroundTransparency = 1 }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
 
	task.delay(0.34, function()
		self._janitor:Destroy()
		if gui then gui:Destroy() end
	end)
end
 
function Window:Toggle()
	if self._destroyed or self._busy then return end
	if self._state == "open" then
		self:Close()
	else
		self:Open()
	end
end
 
function Window:Close()
	if self._destroyed or self._busy or self._state ~= "open" then return end
	self._busy = true
	self._state = "closed"
 
	CloseAnyOpenPopup()
 
	local gui = self._gui
	self._sizeBeforeMinimize = self._fullscreen
		and UDim2.new(0.94, 0, 0.9, 0)
		or (self._normalSize or gui.Size)
 
	Tween(gui, {
		Size = UDim2.new(gui.Size.X.Scale, gui.Size.X.Offset, 0, 0),
	}, 0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	Tween(gui, { BackgroundTransparency = 1 }, 0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
 
	task.delay(0.28, function()
		if self._destroyed then return end
		if self._state == "closed" and gui and gui.Parent then
			gui.Visible = false
		end
		self._busy = false
	end)
 
end
 
function Window:Open()
	if self._destroyed or self._busy or self._state ~= "closed" then return end
	self._busy = true
	self._state = "open"
 
	local gui = self._gui
	gui.Visible = true
 
	local targetSize = self._sizeBeforeMinimize or self._normalSize
	Tween(gui, {
		Size = targetSize,
		BackgroundTransparency = 0.15,
	}, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
 
	task.delay(0.33, function()
		self._busy = false
		if self._drag then self._drag.Sync() end
	end)
end
 
function Window:ToggleFullscreen()
	if self._destroyed then return end
	local gui = self._gui
	self._fullscreen = not self._fullscreen
 
	CloseAnyOpenPopup()
 
	if self._fullscreen then
		self._preFullscreenPosition = gui.Position
		Tween(gui, {
			Size = UDim2.new(0.94, 0, 0.9, 0),
			Position = UDim2.fromScale(0.5, 0.5),
		}, 0.35, Enum.EasingStyle.Quint)
	else
		Tween(gui, {
			Size = self._normalSize,
			Position = self._preFullscreenPosition or UDim2.fromScale(0.5, 0.55),
		}, 0.35, Enum.EasingStyle.Quint)
	end
 
	task.delay(0.36, function()
		if self._drag then self._drag.Sync() end
	end)
end
 
function Window:AddTabLine()
	local holder = Instance.new("Frame")
	holder.Name = "TabLine"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 9)
	holder.ZIndex = Z.Content
	holder.Parent = self._tabBar
 
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Position = UDim2.new(0, 4, 0.5, 0)
	line.Size = UDim2.new(1, -8, 0, 1)
	line.BackgroundColor3 = Color3.new(1, 1, 1)
	line.BackgroundTransparency = 0.92
	line.BorderSizePixel = 0
	line.ZIndex = Z.Content
	line.Parent = holder
 
	return holder
end
 
local DOCK_ICON_SIZE = 28
local DOCK_HEIGHT    = 34
 
function Window:AddDockButton(opts)
	opts = opts or {}
	local jan = self._janitor
	local margin = BobloNEXT.Theme.Margin
 
	if not self._dock then
		local shrunkSize = UDim2.new(0, 130, 1, -(58 + margin + DOCK_HEIGHT + 10))
		self._tabBar.Size = shrunkSize
		self._tabIndicatorLayer.Size = shrunkSize
 
		local dock = Instance.new("Frame")
		dock.Name = "Dock"
		dock.BackgroundTransparency = 1
		dock.AnchorPoint = Vector2.new(0, 1)
		dock.Position = UDim2.new(0, margin, 1, -margin)
		dock.Size = UDim2.new(0, 130, 0, DOCK_HEIGHT)
		dock.ZIndex = Z.Content
		dock.Parent = self._gui
 
		local dockLayout = Instance.new("UIListLayout")
		dockLayout.FillDirection = Enum.FillDirection.Horizontal
		dockLayout.Padding = UDim.new(0, 6)
		dockLayout.SortOrder = Enum.SortOrder.LayoutOrder
		dockLayout.Parent = dock
 
		self._dock = dock
	end
 
	local btn = Instance.new("TextButton")
	btn.Name = opts.Name or "DockButton"
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = Color3.new(1, 1, 1)
	btn.BackgroundTransparency = 0.95
	btn.BorderSizePixel = 0
	btn.Size = UDim2.fromOffset(DOCK_ICON_SIZE, DOCK_ICON_SIZE)
	btn.LayoutOrder = #self._dock:GetChildren()
	btn.ZIndex = Z.Content + 1
	btn.Parent = self._dock
	Corner(btn, 8)
 
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = opts.Icon and ResolveIcon(opts.Icon) or ""
	icon.ImageColor3 = BobloNEXT.Theme.TextDim
	icon.Size = UDim2.fromOffset(15, 15)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = Z.Content + 2
	icon.Parent = btn
 
	local active = false
 
	jan:Add(btn.MouseEnter:Connect(function()
		if active then return end
		Tween(btn, { BackgroundTransparency = 0.85 }, 0.12)
		Tween(icon, { ImageColor3 = BobloNEXT.Theme.Text }, 0.12)
	end))
	jan:Add(btn.MouseLeave:Connect(function()
		if active then return end
		Tween(btn, { BackgroundTransparency = 0.95 }, 0.12)
		Tween(icon, { ImageColor3 = BobloNEXT.Theme.TextDim }, 0.12)
	end))
	jan:Add(btn.MouseButton1Click:Connect(function()
		if opts.Callback then task.spawn(opts.Callback) end
	end))
 
	return {
		Instance = btn,
		Icon = icon,
		SetActive = function(_, isActive)
			active = isActive and true or false
			Tween(btn, { BackgroundTransparency = active and 0.8 or 0.95 }, 0.12)
			Tween(icon, { ImageColor3 = active and BobloNEXT.Theme.Text or BobloNEXT.Theme.TextDim }, 0.12)
		end,
	}
end
 
local CHAT_CODE_FONT = "rbxasset://fonts/families/RobotoMono.json"
 
local function EscapeRichText(text)
	text = text:gsub("&", "&amp;")
	text = text:gsub("<", "&lt;")
	text = text:gsub(">", "&gt;")
	return text
end
 
local function MarkdownToRichText(text)
	text = EscapeRichText(text)
 
	text = text:gsub("`([^`\n]+)`", "<font family=\"" .. CHAT_CODE_FONT .. "\">%1</font>")
 
	text = text:gsub("%*%*(.-)%*%*", "<b>%1</b>")
	text = text:gsub("__(.-)__", "<b>%1</b>")
 
	text = text:gsub("%*([^%s*][^*]-)%*", "<i>%1</i>")
	text = text:gsub("_([^%s_][^_]-)_", "<i>%1</i>")
 
	return text
end
 
local function SplitMessageSegments(text)
	local segments = {}
	local pos = 1
	while true do
		local s, e, lang, code = text:find("```(%w*)\n?(.-)```", pos)
		if not s then
			local rest = text:sub(pos)
			if rest ~= "" then table.insert(segments, { kind = "text", content = rest }) end
			break
		end
		if s > pos then
			local before = text:sub(pos, s - 1)
			if before:match("%S") then
				table.insert(segments, { kind = "text", content = before })
			end
		end
		code = code:gsub("^%s+", ""):gsub("%s+$", "")
		table.insert(segments, { kind = "code", lang = lang ~= "" and lang or "lua", content = code })
		pos = e + 1
	end
	if #segments == 0 then
		table.insert(segments, { kind = "text", content = text })
	end
	return segments
end
 
local LUA_KEYWORDS = {
	["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true,
	["end"] = true, ["false"] = true, ["for"] = true, ["function"] = true, ["if"] = true,
	["in"] = true, ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
	["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
	["until"] = true, ["while"] = true, ["continue"] = true,
}
 
local function HighlightLua(code)
	local out = {}
	local n = #code
	local i = 1
 
	while i <= n do
		local c = code:sub(i, i)
 
		if code:sub(i, i + 3) == "--[[" then
			local closeEnd = select(2, code:find("%]%]", i + 4))
			local stop = closeEnd or n
			out[#out + 1] = "<font color=\"#6A9955\">" .. code:sub(i, stop) .. "</font>"
			i = stop + 1
		elseif code:sub(i, i + 1) == "--" then
			local nl = code:find("\n", i, true)
			local stop = (nl or (n + 1)) - 1
			out[#out + 1] = "<font color=\"#6A9955\">" .. code:sub(i, stop) .. "</font>"
			i = stop + 1
		elseif c == '"' or c == "'" then
			local quote = c
			local j = i + 1
			while j <= n do
				local jc = code:sub(j, j)
				if jc == "\\" then
					j = j + 2
				elseif jc == quote or jc == "\n" then
					break
				else
					j = j + 1
				end
			end
			j = math.min(j, n)
			out[#out + 1] = "<font color=\"#CE9178\">" .. code:sub(i, j) .. "</font>"
			i = j + 1
		elseif c:match("%a") or c == "_" then
			local j = i
			while j <= n and code:sub(j, j):match("[%w_]") do j = j + 1 end
			local word = code:sub(i, j - 1)
			out[#out + 1] = LUA_KEYWORDS[word] and ("<font color=\"#C586C0\">" .. word .. "</font>") or word
			i = j
		elseif c:match("%d") then
			local j = i
			while j <= n and code:sub(j, j):match("[%d%.]") do j = j + 1 end
			out[#out + 1] = "<font color=\"#B5CEA8\">" .. code:sub(i, j - 1) .. "</font>"
			i = j
		else
			out[#out + 1] = c
			i = i + 1
		end
	end
 
	return table.concat(out)
end
 
function Window:AddPanelTab(opts)
	opts = opts or {}
	local self_ = self
	local tabObj = self:AddTab({
		Name   = opts.Name,
		Icon   = opts.Icon,
		Hidden = opts.Hidden ~= false,
	})
	tabObj._page.Visible = false
	local staleEmptyState = tabObj._group:FindFirstChild("EmptyState")
	if staleEmptyState then staleEmptyState.Visible = false end
 
	if opts.OnToggle then
		table.insert(self._tabChangeListeners, function(selected)
			task.spawn(opts.OnToggle, selected == tabObj)
		end)
	end
 
	local lastRealTab = nil
	local function openPanel()
		if self_._currentTab == tabObj then return end
		if self_._currentTab and not self_._currentTab.Hidden then
			lastRealTab = self_._currentTab
		end
		tabObj._select()
	end
	local function closePanel()
		if self_._currentTab ~= tabObj then return end
		if lastRealTab and not lastRealTab.Hidden then
			lastRealTab._select()
		elseif self_._tabs[1] and self_._tabs[1] ~= tabObj then
			self_._tabs[1]._select()
		end
	end
 
	return {
		Instance = tabObj._group,
		Tab = tabObj,
		Open = openPanel,
		Close = closePanel,
		Toggle = function()
			if self_._currentTab == tabObj then closePanel() else openPanel() end
		end,
		IsOpen = function() return self_._currentTab == tabObj end,
	}
end
 
function Window:AddDefaultCreditsPanel()
	local jan = self._janitor
	local dockBtn
	local panel = self:AddPanelTab({
		Name = "Credits",
		Icon = "Lucide:heart-handshake",
		OnToggle = function(isOpen)
			if dockBtn then dockBtn:SetActive(isOpen) end
		end,
	})
 
	local CREDITS = {
		{ Name = "Skinny",   Role = "~90% of the UI, and organization of the Touchline script and its functions", Color = Color3.fromRGB(120, 150, 255) },
		{ Name = "Shezz",    Role = "Sub-tabs, and suggestions for the UI and script", Color = Color3.fromRGB(110, 210, 170) },
		{ Name = "NoSkills", Role = "Suggestions for the UI, and developer of Touchline script functions", Color = Color3.fromRGB(190, 150, 255) },
		{ Name = "Luxy_00",  Role = "Mobile UI tester, and developer of Touchline script functions", Color = Color3.fromRGB(255, 190, 110) },
		{ Name = "Elusive",  Role = "Suggestions for the UI, and main contributor to getting it launched fast", Color = Color3.fromRGB(255, 140, 170) },
	}
 
	local HEADER_H = 38
 
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.ZIndex = Z.Content + 1
	header.Parent = panel.Instance
 
	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingLeft = UDim.new(0, 14)
	headerPad.PaddingRight = UDim.new(0, 8)
	headerPad.Parent = header
 
	local titleRow = Instance.new("Frame")
	titleRow.BackgroundTransparency = 1
	titleRow.Size = UDim2.new(1, -40, 1, 0)
	titleRow.ZIndex = Z.Content + 2
	titleRow.Parent = header
 
	local titleLayout = Instance.new("UIListLayout")
	titleLayout.FillDirection = Enum.FillDirection.Horizontal
	titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	titleLayout.Padding = UDim.new(0, 7)
	titleLayout.Parent = titleRow
 
	local titleIcon = Instance.new("ImageLabel")
	titleIcon.BackgroundTransparency = 1
	titleIcon.Image = ResolveIcon("heart-handshake")
	titleIcon.ImageColor3 = BobloNEXT.Theme.Text
	titleIcon.Size = UDim2.fromOffset(14, 14)
	titleIcon.LayoutOrder = 1
	titleIcon.ZIndex = Z.Content + 3
	titleIcon.Parent = titleRow
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = BobloNEXT.Theme.Font
	titleLabel.Text = "Credits"
	titleLabel.TextColor3 = BobloNEXT.Theme.Text
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.AutomaticSize = Enum.AutomaticSize.X
	titleLabel.Size = UDim2.fromOffset(0, 14)
	titleLabel.LayoutOrder = 2
	titleLabel.ZIndex = Z.Content + 3
	titleLabel.Parent = titleRow
 
	local closeBtn = Instance.new("TextButton")
	closeBtn.Text = ""
	closeBtn.AutoButtonColor = false
	closeBtn.BackgroundColor3 = Color3.new(1, 1, 1)
	closeBtn.BackgroundTransparency = 1
	closeBtn.BorderSizePixel = 0
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, 0, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(26, 26)
	closeBtn.ZIndex = Z.Content + 2
	closeBtn.Parent = header
 
	local closeIcon = Instance.new("ImageLabel")
	closeIcon.BackgroundTransparency = 1
	closeIcon.Image = ResolveIcon("x")
	closeIcon.ImageColor3 = BobloNEXT.Theme.TextDim
	closeIcon.Size = UDim2.fromOffset(13, 13)
	closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	closeIcon.Position = UDim2.fromScale(0.5, 0.5)
	closeIcon.ZIndex = Z.Content + 3
	closeIcon.Parent = closeBtn
 
	closeBtn.MouseEnter:Connect(function() closeIcon.ImageColor3 = BobloNEXT.Theme.Text end)
	closeBtn.MouseLeave:Connect(function() closeIcon.ImageColor3 = BobloNEXT.Theme.TextDim end)
	closeBtn.MouseButton1Click:Connect(function() panel.Close() end)
 
	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = Color3.new(1, 1, 1)
	divider.BackgroundTransparency = 0.94
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromOffset(0, HEADER_H)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.ZIndex = Z.Content + 1
	divider.Parent = panel.Instance
 
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, HEADER_H + 1)
	scroll.Size = UDim2.new(1, 0, 1, -(HEADER_H + 1))
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 0
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ZIndex = Z.Content + 1
	scroll.Parent = panel.Instance
 
	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingTop = UDim.new(0, 12)
	scrollPad.PaddingBottom = UDim.new(0, 12)
	scrollPad.PaddingLeft = UDim.new(0, 14)
	scrollPad.PaddingRight = UDim.new(0, 14)
	scrollPad.Parent = scroll
 
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scroll
 
	AddScrollbar(scroll)
	AddContentScrollThumb(scroll, listLayout, panel.Instance, jan)
 
	for i, credit in ipairs(CREDITS) do
		local row = Instance.new("Frame")
		row.Name = credit.Name
		row.BackgroundColor3 = Color3.new(1, 1, 1)
		row.BackgroundTransparency = 0.96
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 60)
		row.ZIndex = Z.Content + 2
		row.Parent = scroll
 
		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 10)
		rowCorner.Parent = row
 
		local rowStroke = Instance.new("UIStroke")
		rowStroke.Color = Color3.new(1, 1, 1)
		rowStroke.Transparency = 0.94
		rowStroke.Thickness = 1
		rowStroke.Parent = row
 
		row.MouseEnter:Connect(function() row.BackgroundTransparency = 0.92 end)
		row.MouseLeave:Connect(function() row.BackgroundTransparency = 0.96 end)
 
		local avatar = Instance.new("Frame")
		avatar.AnchorPoint = Vector2.new(0, 0.5)
		avatar.Position = UDim2.new(0, 12, 0.5, 0)
		avatar.Size = UDim2.fromOffset(38, 38)
		avatar.BackgroundColor3 = credit.Color
		avatar.BackgroundTransparency = 0.82
		avatar.BorderSizePixel = 0
		avatar.ZIndex = Z.Content + 2
		avatar.Parent = row
 
		local avCorner = Instance.new("UICorner")
		avCorner.CornerRadius = UDim.new(1, 0)
		avCorner.Parent = avatar
 
		local avStroke = Instance.new("UIStroke")
		avStroke.Color = credit.Color
		avStroke.Transparency = 0.55
		avStroke.Thickness = 1
		avStroke.Parent = avatar
 
		local avIcon = Instance.new("ImageLabel")
		avIcon.BackgroundTransparency = 1
		avIcon.Image = ResolveIcon("user-round")
		avIcon.ImageColor3 = credit.Color
		avIcon.Size = UDim2.fromOffset(17, 17)
		avIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		avIcon.Position = UDim2.fromScale(0.5, 0.5)
		avIcon.ZIndex = Z.Content + 3
		avIcon.Parent = avatar
 
		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.FontFace = BobloNEXT.Theme.Font
		nameLabel.Text = credit.Name
		nameLabel.TextColor3 = BobloNEXT.Theme.Text
		nameLabel.TextSize = 13.5
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Position = UDim2.fromOffset(62, 8)
		nameLabel.Size = UDim2.new(1, -74, 0, 16)
		nameLabel.ZIndex = Z.Content + 2
		nameLabel.Parent = row
 
		local roleLabel = Instance.new("TextLabel")
		roleLabel.BackgroundTransparency = 1
		roleLabel.FontFace = BobloNEXT.Theme.FontRegular
		roleLabel.Text = credit.Role
		roleLabel.TextColor3 = BobloNEXT.Theme.TextDim
		roleLabel.TextSize = 11.5
		roleLabel.TextWrapped = true
		roleLabel.TextXAlignment = Enum.TextXAlignment.Left
		roleLabel.TextYAlignment = Enum.TextYAlignment.Top
		roleLabel.Position = UDim2.fromOffset(62, 25)
		roleLabel.Size = UDim2.new(1, -74, 0, 28)
		roleLabel.ZIndex = Z.Content + 2
		roleLabel.Parent = row
	end
 
	dockBtn = self:AddDockButton({
		Icon = "Lucide:heart-handshake",
		Callback = function() panel.Toggle() end,
	})
 
	return panel
end
 
function Window:AddSpotifyPanel(opts)
	opts = opts or {}
	local jan = self._janitor
	local dockBtn
	local connectBridge
	local hasOpenedSpotify = false
	local panel
	panel = self:AddPanelTab({
		Name = opts.Name or "Spotify",
		Icon = opts.Icon or "Lucide:music-2",
		OnToggle = function(isOpen)
			if dockBtn then dockBtn:SetActive(isOpen) end
			if isOpen and not hasOpenedSpotify then
				hasOpenedSpotify = true
				if opts.AutoConnect == true and opts.BridgeUrl ~= "" then
					task.defer(function()
						if connectBridge then connectBridge() end
					end)
				end
			end
			if opts.OnToggle then task.spawn(opts.OnToggle, isOpen) end
		end,
	})
 
	local function websocketConnect()
		local candidates = {}
		pcall(function()
			if WebSocket and type(WebSocket.connect) == "function" then
				table.insert(candidates, WebSocket.connect)
			end
		end)
		pcall(function()
			if websocket and type(websocket.connect) == "function" then
				table.insert(candidates, websocket.connect)
			end
		end)
		pcall(function()
			if syn and syn.websocket and type(syn.websocket.connect) == "function" then
				table.insert(candidates, syn.websocket.connect)
			end
		end)
		return candidates[1]
	end
 
	local HEADER_H = 0
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.ZIndex = Z.Content + 1
	header.Parent = panel.Instance
	header.Visible = false
 
	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingLeft = UDim.new(0, 14)
	headerPad.PaddingRight = UDim.new(0, 8)
	headerPad.Parent = header
 
	local titleIcon = Instance.new("ImageLabel")
	titleIcon.BackgroundTransparency = 1
	titleIcon.Image = ResolveIcon(opts.Icon or "Lucide:music-2")
	titleIcon.ImageColor3 = Color3.fromRGB(30, 215, 96)
	titleIcon.AnchorPoint = Vector2.new(0, 0.5)
	titleIcon.Position = UDim2.new(0, 0, 0.5, 0)
	titleIcon.Size = UDim2.fromOffset(15, 15)
	titleIcon.ZIndex = Z.Content + 2
	titleIcon.Parent = header
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = BobloNEXT.Theme.Font
	titleLabel.Text = opts.Title or "Spotify Player"
	titleLabel.TextColor3 = BobloNEXT.Theme.Text
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.AnchorPoint = Vector2.new(0, 0.5)
	titleLabel.Position = UDim2.new(0, 22, 0.5, 0)
	titleLabel.Size = UDim2.new(1, -62, 0, 18)
	titleLabel.ZIndex = Z.Content + 2
	titleLabel.Parent = header
 
	local closeBtn = Instance.new("TextButton")
	closeBtn.Text = ""
	closeBtn.AutoButtonColor = false
	closeBtn.BackgroundTransparency = 1
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, 0, 0.5, 0)
	closeBtn.Size = UDim2.fromOffset(26, 26)
	closeBtn.ZIndex = Z.Content + 2
	closeBtn.Parent = header
 
	local closeIcon = Instance.new("ImageLabel")
	closeIcon.BackgroundTransparency = 1
	closeIcon.Image = ResolveIcon("x")
	closeIcon.ImageColor3 = BobloNEXT.Theme.TextDim
	closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	closeIcon.Position = UDim2.fromScale(0.5, 0.5)
	closeIcon.Size = UDim2.fromOffset(13, 13)
	closeIcon.ZIndex = Z.Content + 3
	closeIcon.Parent = closeBtn
	jan:Add(closeBtn.MouseButton1Click:Connect(function() panel.Close() end))
 
	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = Color3.new(1, 1, 1)
	divider.BackgroundTransparency = 0.94
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromOffset(0, HEADER_H)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.ZIndex = Z.Content + 1
	divider.Parent = panel.Instance
	divider.Visible = false
 
	local subTabHost = Instance.new("ScrollingFrame")
	subTabHost.Name = "SpotifySubTabs"
	subTabHost.BackgroundTransparency = 1
	subTabHost.BorderSizePixel = 0
	subTabHost.Position = UDim2.fromOffset(0, HEADER_H)
	subTabHost.Size = UDim2.new(1, 0, 1, -HEADER_H)
	subTabHost.ScrollBarThickness = 0
	subTabHost.ZIndex = Z.Content + 1
	subTabHost.Parent = panel.Instance
 
	local subTabRoot = setmetatable({
		Name = "Spotify Player",
		_page = subTabHost,
		_window = self,
		_janitor = jan,
		_group = panel.Instance,
	}, Tab)
	local playerSubTab = subTabRoot:AddSubTab({ Name = "Spotify Player", Icon = "Lucide:music-2" })
	local favoritesSubTab = subTabRoot:AddSubTab({ Name = "Favorites", Icon = "Lucide:heart" })
	local scroll = playerSubTab._page
	local list = scroll:FindFirstChild("PageLayout")
	local scrollPad = scroll:FindFirstChild("PagePadding")
	if scrollPad then
		scrollPad.PaddingTop = UDim.new(0, 0)
		scrollPad.PaddingLeft = UDim.new(0, 0)
		scrollPad.PaddingRight = UDim.new(0, 12)
		scrollPad.PaddingBottom = UDim.new(0, 6)
	end
	local favoritesPad = favoritesSubTab._page:FindFirstChild("PagePadding")
	if favoritesPad then
		favoritesPad.PaddingTop = UDim.new(0, 0)
		favoritesPad.PaddingLeft = UDim.new(0, 0)
		favoritesPad.PaddingRight = UDim.new(0, 12)
		favoritesPad.PaddingBottom = UDim.new(0, 6)
	end
 
	local function makeCard(height, order, parent)
		local card = Instance.new("Frame")
		card.BackgroundColor3 = Color3.new(1, 1, 1)
		card.BackgroundTransparency = 0.96
		card.BorderSizePixel = 0
		card.Size = UDim2.new(1, 0, 0, height)
		card.LayoutOrder = order
		card.ZIndex = Z.Content + 2
		card.Parent = parent or scroll
		Corner(card, 10)
		Stroke(card, Color3.new(1, 1, 1), 1, 0.94)
		return card
	end
 
	local guideParagraph = playerSubTab:AddParagraph({
		Title = "Quick setup",
		Icon = "Lucide:link-2",
		Text = "Copy the player link, keep it open in your browser, load a playlist and press Play once.",
	})
	guideParagraph.Instance.LayoutOrder = 1
 
	local statusCard = makeCard(30, 6)
	local statusDot = Instance.new("Frame")
	statusDot.BackgroundColor3 = Color3.fromRGB(125, 130, 128)
	statusDot.BorderSizePixel = 0
	statusDot.AnchorPoint = Vector2.new(0, 0.5)
	statusDot.Position = UDim2.new(0, 11, 0.5, 0)
	statusDot.Size = UDim2.fromOffset(7, 7)
	statusDot.ZIndex = Z.Content + 3
	statusDot.Parent = statusCard
	Corner(statusDot, 4)
 
	local statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.FontFace = BobloNEXT.Theme.FontRegular
	statusLabel.Text = "Bridge disconnected"
	statusLabel.TextColor3 = BobloNEXT.Theme.TextDim
	statusLabel.TextSize = 12
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Position = UDim2.fromOffset(27, 0)
	statusLabel.Size = UDim2.new(1, -38, 1, 0)
	statusLabel.ZIndex = Z.Content + 3
	statusLabel.Parent = statusCard
 
	local nowCard = makeCard(164, 7)
	nowCard.ClipsDescendants = true
	local art = Instance.new("ImageLabel")
	art.BackgroundColor3 = Color3.fromRGB(30, 215, 96)
	art.BackgroundTransparency = 0.84
	art.BorderSizePixel = 0
	art.Image = ""
	art.ImageColor3 = Color3.new(1, 1, 1)
	art.ScaleType = Enum.ScaleType.Crop
	art.AnchorPoint = Vector2.new(0, 0)
	art.Position = UDim2.fromOffset(0, 12)
	art.Size = UDim2.fromOffset(88, 88)
	art.ZIndex = Z.Content + 3
	art.Parent = nowCard
	Corner(art, 12)
	Stroke(art, Color3.new(1, 1, 1), 1, 0.9)
 
	local artIcon = Instance.new("ImageLabel")
	artIcon.BackgroundTransparency = 1
	artIcon.Image = ResolveIcon("music-2")
	artIcon.ImageColor3 = Color3.fromRGB(30, 215, 96)
	artIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	artIcon.Position = UDim2.fromScale(0.5, 0.5)
	artIcon.Size = UDim2.fromOffset(28, 28)
	artIcon.ZIndex = Z.Content + 4
	artIcon.Parent = art
 
	local coverToken = 0
	local coverCache = {}
	local function showCover(url)
		coverToken += 1
		local token = coverToken
		url = type(url) == "string" and url or ""
		if url == "" then
			art.BackgroundTransparency = 0.84
			art.Image = ""
			artIcon.Visible = true
			artIcon.Image = ResolveIcon("music-2")
			artIcon.ImageColor3 = Color3.fromRGB(30, 215, 96)
			artIcon.BackgroundTransparency = 1
			artIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			artIcon.Size = UDim2.fromOffset(28, 28)
			artIcon.Position = UDim2.fromScale(0.5, 0.5)
			return
		end
		task.spawn(function()
			local asset = coverCache[url]
			if not asset and fn_customasset and fn_writefile and EnsureAssetsFolder() then
				local hash = 7
				for index = 1, #url do hash = (hash * 31 + url:byte(index)) % 2147483647 end
				local path = ASSETS_FOLDER .. "/spotify-cover-" .. tostring(hash) .. ".jpg"
				if not (fn_isfile and fn_isfile(path)) then
					local ok, body = pcall(function() return game:HttpGet(url) end)
					if ok and type(body) == "string" and #body > 256 then pcall(fn_writefile, path, body) end
				end
				if not fn_isfile or fn_isfile(path) then
					local ok, result = pcall(fn_customasset, path)
					if ok then asset = result; coverCache[url] = result end
				end
			end
			if token ~= coverToken or not asset then return end
			art.BackgroundTransparency = 1
			art.Image = asset
			artIcon.Visible = false
		end)
	end
 
	local nowPlayingTag = Instance.new("TextLabel")
	nowPlayingTag.BackgroundTransparency = 1
	nowPlayingTag.FontFace = BobloNEXT.Theme.Font
	nowPlayingTag.Text = "NOW PLAYING"
	nowPlayingTag.TextColor3 = Color3.fromRGB(30, 215, 96)
	nowPlayingTag.TextSize = 9
	nowPlayingTag.TextXAlignment = Enum.TextXAlignment.Left
	nowPlayingTag.Position = UDim2.fromOffset(100, 9)
	nowPlayingTag.Size = UDim2.new(1, -100, 0, 12)
	nowPlayingTag.ZIndex = Z.Content + 3
	nowPlayingTag.Parent = nowCard
 
	local trackLabel = Instance.new("TextLabel")
	trackLabel.BackgroundTransparency = 1
	trackLabel.FontFace = BobloNEXT.Theme.Font
	trackLabel.Text = "Nothing playing"
	trackLabel.TextColor3 = BobloNEXT.Theme.Text
	trackLabel.TextSize = 15
	trackLabel.TextXAlignment = Enum.TextXAlignment.Left
	trackLabel.TextTruncate = Enum.TextTruncate.AtEnd
	trackLabel.Position = UDim2.fromOffset(100, 25)
	trackLabel.Size = UDim2.new(1, -100, 0, 20)
	trackLabel.ZIndex = Z.Content + 3
	trackLabel.Parent = nowCard
 
	local artistLabel = Instance.new("TextLabel")
	artistLabel.BackgroundTransparency = 1
	artistLabel.FontFace = BobloNEXT.Theme.FontRegular
	artistLabel.Text = "Connect your Spotify bridge"
	artistLabel.TextColor3 = BobloNEXT.Theme.TextDim
	artistLabel.TextSize = 12
	artistLabel.TextXAlignment = Enum.TextXAlignment.Left
	artistLabel.TextTruncate = Enum.TextTruncate.AtEnd
	artistLabel.Position = UDim2.fromOffset(100, 47)
	artistLabel.Size = UDim2.new(1, -100, 0, 16)
	artistLabel.ZIndex = Z.Content + 3
	artistLabel.Parent = nowCard
 
	local progressTrack = Instance.new("Frame")
	progressTrack.BackgroundColor3 = Color3.fromRGB(95, 100, 98)
	progressTrack.BackgroundTransparency = 0.45
	progressTrack.BorderSizePixel = 0
	progressTrack.Position = UDim2.fromOffset(100, 76)
	progressTrack.Size = UDim2.new(1, -100, 0, 5)
	progressTrack.ZIndex = Z.Content + 3
	progressTrack.Parent = nowCard
	Corner(progressTrack, 2)
 
	local progressFill = Instance.new("Frame")
	progressFill.BackgroundColor3 = Color3.fromRGB(30, 215, 96)
	progressFill.BorderSizePixel = 0
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	progressFill.ZIndex = Z.Content + 4
	progressFill.Parent = progressTrack
	Corner(progressFill, 2)
 
	local progressKnob = Instance.new("Frame")
	progressKnob.BackgroundColor3 = Color3.fromRGB(235, 239, 237)
	progressKnob.BorderSizePixel = 0
	progressKnob.AnchorPoint = Vector2.new(0.5, 0.5)
	progressKnob.Position = UDim2.new(0, 0, 0.5, 0)
	progressKnob.Size = UDim2.fromOffset(9, 9)
	progressKnob.ZIndex = Z.Content + 6
	progressKnob.Parent = progressTrack
	Corner(progressKnob, 5)
 
	local seekBubble = Instance.new("Frame")
	seekBubble.BackgroundColor3 = Color3.fromRGB(21, 26, 24)
	seekBubble.BackgroundTransparency = 0.04
	seekBubble.BorderSizePixel = 0
	seekBubble.AnchorPoint = Vector2.new(0.5, 1)
	seekBubble.Position = UDim2.new(0, 0, 0, -8)
	seekBubble.Size = UDim2.fromOffset(48, 25)
	seekBubble.Visible = false
	seekBubble.ZIndex = Z.Content + 8
	seekBubble.Parent = progressTrack
	Corner(seekBubble, 7)
	Stroke(seekBubble, Color3.new(1, 1, 1), 1, 0.9)
	local seekBubbleLabel = Instance.new("TextLabel")
	seekBubbleLabel.BackgroundTransparency = 1
	seekBubbleLabel.FontFace = BobloNEXT.Theme.Font
	seekBubbleLabel.Text = "0:00"
	seekBubbleLabel.TextColor3 = BobloNEXT.Theme.Text
	seekBubbleLabel.TextSize = 10
	seekBubbleLabel.Size = UDim2.fromScale(1, 1)
	seekBubbleLabel.ZIndex = Z.Content + 9
	seekBubbleLabel.Parent = seekBubble
 
	local progressHitbox = Instance.new("TextButton")
	progressHitbox.Text = ""
	progressHitbox.AutoButtonColor = false
	progressHitbox.BackgroundTransparency = 1
	progressHitbox.BorderSizePixel = 0
	progressHitbox.Position = UDim2.fromOffset(100, 68)
	progressHitbox.Size = UDim2.new(1, -100, 0, 21)
	progressHitbox.ZIndex = Z.Content + 7
	progressHitbox.Parent = nowCard
 
	local timeLabel = Instance.new("TextLabel")
	timeLabel.BackgroundTransparency = 1
	timeLabel.FontFace = BobloNEXT.Theme.FontRegular
	timeLabel.Text = "0:00"
	timeLabel.TextColor3 = BobloNEXT.Theme.TextDim
	timeLabel.TextSize = 10
	timeLabel.TextXAlignment = Enum.TextXAlignment.Left
	timeLabel.Position = UDim2.fromOffset(100, 87)
	timeLabel.Size = UDim2.new(0.5, -50, 0, 14)
	timeLabel.ZIndex = Z.Content + 3
	timeLabel.Parent = nowCard
 
	local durationLabel = Instance.new("TextLabel")
	durationLabel.BackgroundTransparency = 1
	durationLabel.FontFace = BobloNEXT.Theme.FontRegular
	durationLabel.Text = "0:00"
	durationLabel.TextColor3 = BobloNEXT.Theme.TextDim
	durationLabel.TextSize = 10
	durationLabel.TextXAlignment = Enum.TextXAlignment.Right
	durationLabel.Position = UDim2.new(0.5, 50, 0, 87)
	durationLabel.Size = UDim2.new(0.5, -50, 0, 14)
	durationLabel.ZIndex = Z.Content + 3
	durationLabel.Parent = nowCard
 
	local controlsDivider = Instance.new("Frame")
	controlsDivider.BackgroundColor3 = Color3.new(1, 1, 1)
	controlsDivider.BackgroundTransparency = 0.93
	controlsDivider.BorderSizePixel = 0
	controlsDivider.Position = UDim2.fromOffset(0, 111)
	controlsDivider.Size = UDim2.new(1, 0, 0, 1)
	controlsDivider.ZIndex = Z.Content + 3
	controlsDivider.Parent = nowCard
 
	local controls = Instance.new("Frame")
	controls.BackgroundTransparency = 1
	controls.BorderSizePixel = 0
	controls.Position = UDim2.fromOffset(0, 114)
	controls.Size = UDim2.new(1, 0, 0, 44)
	controls.ZIndex = Z.Content + 3
	controls.Parent = nowCard
	local controlsLayout = Instance.new("UIListLayout")
	controlsLayout.FillDirection = Enum.FillDirection.Horizontal
	controlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	controlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	controlsLayout.Padding = UDim.new(0, 12)
	controlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	controlsLayout.Parent = controls
 
	local controlRefs = {}
	local function makeControl(name, icon, order, primary)
		local button = Instance.new("TextButton")
		button.Name = name
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = primary and Color3.fromRGB(30, 215, 96) or Color3.new(1, 1, 1)
		button.BackgroundTransparency = primary and 0.05 or 0.94
		button.BorderSizePixel = 0
		button.Size = UDim2.fromOffset(primary and 36 or 32, primary and 36 or 32)
		button.LayoutOrder = order
		button.ZIndex = Z.Content + 3
		button.Parent = controls
		Corner(button, primary and 18 or 10)
 
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Image = ResolveIcon(icon)
		image.ImageColor3 = primary and Color3.fromRGB(12, 28, 18) or BobloNEXT.Theme.TextDim
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromOffset(primary and 17 or 15, primary and 17 or 15)
		image.ZIndex = Z.Content + 4
		image.Parent = button
		controlRefs[name] = { Button = button, Icon = image }
		return button
	end
 
	local shuffleBtn = makeControl("Shuffle", "shuffle", 1, false)
	local previousBtn = makeControl("Previous", "skip-back", 2, false)
	local playBtn = makeControl("PlayPause", "play", 3, true)
	local nextBtn = makeControl("Next", "skip-forward", 4, false)
	local repeatBtn = makeControl("Repeat", "repeat", 5, false)
 
	local function makeInputCard(order, title, placeholder, buttonIcon)
		local card = makeCard(66, order)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.FontFace = BobloNEXT.Theme.Font
		label.Text = title
		label.TextColor3 = BobloNEXT.Theme.Text
		label.TextSize = 12
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Position = UDim2.fromOffset(11, 6)
		label.Size = UDim2.new(1, -22, 0, 16)
		label.ZIndex = Z.Content + 3
		label.Parent = card
 
		local pill = Instance.new("Frame")
		pill.BackgroundColor3 = Color3.new(1, 1, 1)
		pill.BackgroundTransparency = 0.94
		pill.BorderSizePixel = 0
		pill.Position = UDim2.fromOffset(10, 27)
		pill.Size = UDim2.new(1, -20, 0, 30)
		pill.ZIndex = Z.Content + 3
		pill.Parent = card
		Corner(pill, 8)
 
		local button = Instance.new("TextButton")
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = Color3.new(1, 1, 1)
		button.BackgroundTransparency = 0.91
		button.BorderSizePixel = 0
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.new(1, -3, 0, 3)
		button.Size = UDim2.fromOffset(34, 24)
		button.ZIndex = Z.Content + 5
		button.Parent = pill
		Corner(button, 7)
		Stroke(button, Color3.new(1, 1, 1), 1, 0.94)
		local buttonImage = Instance.new("ImageLabel")
		buttonImage.BackgroundTransparency = 1
		buttonImage.Image = ResolveIcon(buttonIcon)
		buttonImage.ImageColor3 = BobloNEXT.Theme.Text
		buttonImage.AnchorPoint = Vector2.new(0.5, 0.5)
		buttonImage.Position = UDim2.fromScale(0.5, 0.5)
		buttonImage.Size = UDim2.fromOffset(14, 14)
		buttonImage.ZIndex = Z.Content + 6
		buttonImage.Parent = button
 
		local box = Instance.new("TextBox")
		box.ClearTextOnFocus = false
		box.FontFace = BobloNEXT.Theme.FontRegular
		box.PlaceholderText = placeholder
		box.PlaceholderColor3 = Color3.fromRGB(115, 120, 118)
		box.Text = ""
		box.TextColor3 = BobloNEXT.Theme.Text
		box.TextSize = 11
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.BackgroundTransparency = 1
		box.Position = UDim2.fromOffset(9, 0)
		box.Size = UDim2.new(1, -52, 1, 0)
		box.ZIndex = Z.Content + 4
		box.Parent = pill
		return box, button, card, label, pill
	end
 
	local searchBox, searchBtn, searchCard, searchTitle, searchPill = makeInputCard(3, "", "Search this playlist...", "search")
	local pairBox, connectBtn, pairCard = makeInputCard(3, "Spotify Connect", "Pairing code", "link-2")
	local connectBtnIcon = connectBtn:FindFirstChildOfClass("ImageLabel")
	pairBox.TextEditable = false
	pairBox.Text = HttpService:GenerateGUID(false):gsub("%-", ""):sub(1, 8):upper()
	local playlistBox, loadBtn, playlistCard, playlistTitle, playlistPill = makeInputCard(4, "", "Paste a Spotify playlist link...", "play")
 
	local connectSection = playerSubTab:AddLineText("Spotify Connect")
	connectSection.Instance.LayoutOrder = 2
	local playerSection = playerSubTab:AddLineText("Player")
	playerSection.Instance.LayoutOrder = 4
	local playerShell = makeCard(286, 5)
	local function flattenIntoPlayer(card, y, height)
		card.Parent = playerShell
		card.BackgroundTransparency = 1
		card.Position = UDim2.fromOffset(12, y)
		card.Size = UDim2.new(1, -24, 0, height)
		for _, child in ipairs(card:GetChildren()) do
			if child:IsA("UIStroke") then child.Transparency = 1 end
		end
	end
	flattenIntoPlayer(searchCard, 12, 40)
	searchTitle.Visible = false
	searchPill.Position = UDim2.fromOffset(0, 0)
	searchPill.Size = UDim2.fromScale(1, 1)
	searchPill.BackgroundTransparency = 0.92
	searchBtn.AnchorPoint = Vector2.zero
	searchBtn.Position = UDim2.fromOffset(4, 4)
	searchBtn.Size = UDim2.fromOffset(32, 32)
	searchBtn.BackgroundTransparency = 1
	for _, child in ipairs(searchBtn:GetChildren()) do
		if child:IsA("UIStroke") then child.Transparency = 1 end
	end
	searchBox.Position = UDim2.fromOffset(38, 0)
	searchBox.Size = UDim2.new(1, -46, 1, 0)
	searchBox.TextSize = 13
 
	flattenIntoPlayer(playlistCard, 60, 40)
	playlistTitle.Visible = false
	playlistPill.Position = UDim2.fromOffset(0, 0)
	playlistPill.Size = UDim2.fromScale(1, 1)
	playlistPill.BackgroundTransparency = 0.92
	loadBtn.Position = UDim2.new(1, -4, 0, 4)
	loadBtn.Size = UDim2.fromOffset(32, 32)
	playlistBox.Position = UDim2.fromOffset(12, 0)
	playlistBox.Size = UDim2.new(1, -56, 1, 0)
 
	statusCard.Parent = playerShell
	statusCard.Position = UDim2.fromOffset(12, 108)
	statusCard.Size = UDim2.new(1, -24, 0, 30)
	statusCard.Visible = false
	nowCard.Parent = playerShell
	nowCard.Position = UDim2.fromOffset(12, 108)
	nowCard.Size = UDim2.new(1, -24, 0, 164)
	nowCard.BackgroundTransparency = 1
	for _, child in ipairs(nowCard:GetChildren()) do
		if child:IsA("UIStroke") then child.Transparency = 1 end
	end
 
	local favoritesSection = favoritesSubTab:AddLineText("Saved Playlists")
	favoritesSection.Instance.LayoutOrder = 1
	local favoritesHeader = makeCard(137, 2, favoritesSubTab._page)
	local favoritesTitle = Instance.new("TextLabel")
	favoritesTitle.BackgroundTransparency = 1
	favoritesTitle.FontFace = BobloNEXT.Theme.Font
	favoritesTitle.Text = "Favorite playlists"
	favoritesTitle.TextColor3 = BobloNEXT.Theme.Text
	favoritesTitle.TextSize = 14
	favoritesTitle.TextXAlignment = Enum.TextXAlignment.Left
	favoritesTitle.Position = UDim2.fromOffset(12, 8)
	favoritesTitle.Size = UDim2.new(1, -112, 0, 20)
	favoritesTitle.ZIndex = Z.Content + 3
	favoritesTitle.Parent = favoritesHeader
	favoritesTitle.Visible = false
	local favoritesHint = Instance.new("TextLabel")
	favoritesHint.BackgroundTransparency = 1
	favoritesHint.FontFace = BobloNEXT.Theme.FontRegular
	favoritesHint.Text = "Save and load your playlists with one tap"
	favoritesHint.TextColor3 = BobloNEXT.Theme.TextDim
	favoritesHint.TextSize = 10
	favoritesHint.TextXAlignment = Enum.TextXAlignment.Left
	favoritesHint.Position = UDim2.fromOffset(12, 29)
	favoritesHint.Size = UDim2.new(1, -112, 0, 16)
	favoritesHint.ZIndex = Z.Content + 3
	favoritesHint.Parent = favoritesHeader
	favoritesHint.Visible = false
	local favoritesSearchPill = Instance.new("Frame")
	favoritesSearchPill.BackgroundColor3 = Color3.new(1, 1, 1)
	favoritesSearchPill.BackgroundTransparency = 0.94
	favoritesSearchPill.BorderSizePixel = 0
	favoritesSearchPill.Position = UDim2.fromOffset(8, 7)
	favoritesSearchPill.Size = UDim2.new(1, -16, 0, 36)
	favoritesSearchPill.ZIndex = Z.Content + 3
	favoritesSearchPill.Parent = favoritesHeader
	Corner(favoritesSearchPill, 9)
	local favoritesSearchIcon = Instance.new("ImageLabel")
	favoritesSearchIcon.BackgroundTransparency = 1
	favoritesSearchIcon.Image = ResolveIcon("search")
	favoritesSearchIcon.ImageColor3 = BobloNEXT.Theme.TextDim
	favoritesSearchIcon.AnchorPoint = Vector2.new(0, 0.5)
	favoritesSearchIcon.Position = UDim2.new(0, 11, 0.5, 0)
	favoritesSearchIcon.Size = UDim2.fromOffset(15, 15)
	favoritesSearchIcon.ZIndex = Z.Content + 4
	favoritesSearchIcon.Parent = favoritesSearchPill
	local favoritesSearchBox = Instance.new("TextBox")
	favoritesSearchBox.BackgroundTransparency = 1
	favoritesSearchBox.ClearTextOnFocus = false
	favoritesSearchBox.FontFace = BobloNEXT.Theme.FontRegular
	favoritesSearchBox.PlaceholderText = "Search favorite playlists..."
	favoritesSearchBox.PlaceholderColor3 = Color3.fromRGB(115, 120, 118)
	favoritesSearchBox.Text = ""
	favoritesSearchBox.TextColor3 = BobloNEXT.Theme.Text
	favoritesSearchBox.TextSize = 11
	favoritesSearchBox.TextXAlignment = Enum.TextXAlignment.Left
	favoritesSearchBox.Position = UDim2.fromOffset(36, 0)
	favoritesSearchBox.Size = UDim2.new(1, -44, 1, 0)
	favoritesSearchBox.ZIndex = Z.Content + 4
	favoritesSearchBox.Parent = favoritesSearchPill
	local addFavoriteBtn = Instance.new("TextButton")
	addFavoriteBtn.Text = ""
	addFavoriteBtn.AutoButtonColor = false
	addFavoriteBtn.BackgroundColor3 = Color3.new(1, 1, 1)
	addFavoriteBtn.BackgroundTransparency = 0.96
	addFavoriteBtn.BorderSizePixel = 0
	addFavoriteBtn.Position = UDim2.fromOffset(8, 113)
	addFavoriteBtn.Size = UDim2.new(1, -16, 0, 56)
	addFavoriteBtn.ZIndex = Z.Content + 4
	addFavoriteBtn.Parent = favoritesHeader
	Corner(addFavoriteBtn, 10)
	Stroke(addFavoriteBtn, Color3.new(1, 1, 1), 1, 0.94)
	local addFavoriteIcon = Instance.new("ImageLabel")
	addFavoriteIcon.BackgroundTransparency = 1
	addFavoriteIcon.Image = ResolveIcon("heart-plus")
	addFavoriteIcon.ImageColor3 = BobloNEXT.Theme.Text
	addFavoriteIcon.AnchorPoint = Vector2.new(0, 0.5)
	addFavoriteIcon.Position = UDim2.new(0, 16, 0.5, 0)
	addFavoriteIcon.Size = UDim2.fromOffset(17, 17)
	addFavoriteIcon.ZIndex = Z.Content + 5
	addFavoriteIcon.Parent = addFavoriteBtn
	local saveFavoriteTitle = Instance.new("TextLabel")
	saveFavoriteTitle.BackgroundTransparency = 1
	saveFavoriteTitle.FontFace = BobloNEXT.Theme.Font
	saveFavoriteTitle.Text = "Save current playlist"
	saveFavoriteTitle.TextColor3 = BobloNEXT.Theme.Text
	saveFavoriteTitle.TextSize = 12
	saveFavoriteTitle.TextXAlignment = Enum.TextXAlignment.Left
	saveFavoriteTitle.Position = UDim2.fromOffset(44, 7)
	saveFavoriteTitle.Size = UDim2.new(1, -84, 0, 20)
	saveFavoriteTitle.ZIndex = Z.Content + 5
	saveFavoriteTitle.Parent = addFavoriteBtn
	local saveFavoriteHint = Instance.new("TextLabel")
	saveFavoriteHint.BackgroundTransparency = 1
	saveFavoriteHint.FontFace = BobloNEXT.Theme.FontRegular
	saveFavoriteHint.Text = "Add the playlist loaded in the player to Favorites"
	saveFavoriteHint.TextColor3 = BobloNEXT.Theme.TextDim
	saveFavoriteHint.TextSize = 9
	saveFavoriteHint.TextXAlignment = Enum.TextXAlignment.Left
	saveFavoriteHint.Position = UDim2.fromOffset(44, 27)
	saveFavoriteHint.Size = UDim2.new(1, -84, 0, 17)
	saveFavoriteHint.ZIndex = Z.Content + 5
	saveFavoriteHint.Parent = addFavoriteBtn
	local saveFavoriteChevron = Instance.new("ImageLabel")
	saveFavoriteChevron.BackgroundTransparency = 1
	saveFavoriteChevron.Image = ResolveIcon("chevron-right")
	saveFavoriteChevron.ImageColor3 = BobloNEXT.Theme.TextDim
	saveFavoriteChevron.AnchorPoint = Vector2.new(1, 0.5)
	saveFavoriteChevron.Position = UDim2.new(1, -16, 0.5, 0)
	saveFavoriteChevron.Size = UDim2.fromOffset(14, 14)
	saveFavoriteChevron.ZIndex = Z.Content + 5
	saveFavoriteChevron.Parent = addFavoriteBtn
	local saveFavoriteDivider = Instance.new("Frame")
	saveFavoriteDivider.BackgroundColor3 = Color3.new(1, 1, 1)
	saveFavoriteDivider.BackgroundTransparency = 0.92
	saveFavoriteDivider.BorderSizePixel = 0
	saveFavoriteDivider.Position = UDim2.fromOffset(8, 103)
	saveFavoriteDivider.Size = UDim2.new(1, -16, 0, 1)
	saveFavoriteDivider.ZIndex = Z.Content + 3
	saveFavoriteDivider.Parent = favoritesHeader
 
	local favoritesList = Instance.new("Frame")
	favoritesList.BackgroundTransparency = 1
	favoritesList.BorderSizePixel = 0
	favoritesList.Position = UDim2.fromOffset(8, 51)
	favoritesList.Size = UDim2.new(1, -16, 0, 78)
	favoritesList.ZIndex = Z.Content + 2
	favoritesList.Parent = favoritesHeader
	local favoriteRows = {}
	local favorites = {}
	local currentPlaylistName = "Spotify playlist"
	local favoritesPath = ASSETS_FOLDER .. "/spotify-favorites.json"
	if fn_readfile and fn_isfile and fn_isfile(favoritesPath) then
		pcall(function()
			local decoded = HttpService:JSONDecode(fn_readfile(favoritesPath))
			if type(decoded) == "table" then favorites = decoded end
		end)
	end
	local function saveFavorites()
		if not (fn_writefile and EnsureAssetsFolder()) then return end
		pcall(fn_writefile, favoritesPath, HttpService:JSONEncode(favorites))
	end
 
	local socket
	local socketConnections = {}
	local isConnected = false
	local isPlaying = false
	local shuffle = false
	local repeatMode = "off"
	local durationMs = 0
	local progressMs = 0
	local lastStateClock = os.clock()
	local seekDragging = false
	local seekPreviewMs = 0
 
	local function setStatus(text, color)
		statusLabel.Text = tostring(text or "")
		statusDot.BackgroundColor3 = color or Color3.fromRGB(125, 130, 128)
	end
 
	local notifyTimes = {}
	local function spotifyNotify(key, title, text, notifyType, icon, duration, actions)
		if not panel.IsOpen() then return end
		local now = os.clock()
		if notifyTimes[key] and now - notifyTimes[key] < 2.5 then return end
		notifyTimes[key] = now
		BobloNEXT:Notify({
			Title = title,
			Text = text,
			Type = notifyType or "info",
			Icon = icon,
			Duration = duration or 5,
			Actions = actions,
		})
	end
 
	local function formatTime(ms)
		local seconds = math.max(0, math.floor((tonumber(ms) or 0) / 1000))
		return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
	end
 
	local function renderProgress()
		local shownProgress = progressMs
		if isPlaying and durationMs > 0 then
			shownProgress = math.min(durationMs, progressMs + (os.clock() - lastStateClock) * 1000)
		end
		local alpha = durationMs > 0 and math.clamp(shownProgress / durationMs, 0, 1) or 0
		if not seekDragging then
			progressFill.Size = UDim2.new(alpha, 0, 1, 0)
			progressKnob.Position = UDim2.new(alpha, 0, 0.5, 0)
			timeLabel.Text = formatTime(shownProgress)
		end
		durationLabel.Text = formatTime(durationMs)
	end
	jan:Add(RunService.Heartbeat:Connect(renderProgress))
 
	local function send(action, extra)
		if not (isConnected and socket) then
			setStatus("Connect the bridge first", Color3.fromRGB(255, 190, 90))
			return false
		end
		local payload = extra or {}
		payload.type = "command"
		payload.action = action
		local ok, err = pcall(function()
			socket:Send(HttpService:JSONEncode(payload))
		end)
		if not ok then
			setStatus("Could not send command: " .. tostring(err), Color3.fromRGB(255, 105, 105))
		end
		return ok
	end
 
	local function setView(name)
		subTabRoot:SelectSubTabByName(name)
	end
 
	local function renderFavorites()
		for _, row in ipairs(favoriteRows) do row:Destroy() end
		table.clear(favoriteRows)
		local query = favoritesSearchBox.Text:lower():gsub("^%s+", ""):gsub("%s+$", "")
		local filtered = {}
		for originalIndex, favorite in ipairs(favorites) do
			local searchable = (tostring(favorite.name or "") .. " " .. tostring(favorite.url or "")):lower()
			if query == "" or searchable:find(query, 1, true) then
				table.insert(filtered, { Favorite = favorite, Index = originalIndex })
			end
		end
		local count = math.min(#filtered, 8)
		local listHeight = count == 0 and 52 or count * 64
		favoritesList.Size = UDim2.new(1, -16, 0, listHeight)
		local dividerY = 51 + listHeight + 7
		saveFavoriteDivider.Position = UDim2.fromOffset(8, dividerY)
		addFavoriteBtn.Position = UDim2.fromOffset(8, dividerY + 10)
		favoritesHeader.Size = UDim2.new(1, 0, 0, dividerY + 74)
		if count == 0 then
			local empty = Instance.new("TextLabel")
			empty.BackgroundTransparency = 1
			empty.FontFace = BobloNEXT.Theme.FontRegular
			empty.Text = query ~= "" and "No saved playlist matches your search" or "No saved playlists yet"
			empty.TextColor3 = BobloNEXT.Theme.TextDim
			empty.TextSize = 11
			empty.Size = UDim2.fromScale(1, 1)
			empty.ZIndex = Z.Content + 3
			empty.Parent = favoritesList
			table.insert(favoriteRows, empty)
		else
		for visibleIndex = 1, count do
			local entry = filtered[visibleIndex]
			local favorite = entry.Favorite
			local originalIndex = entry.Index
			local row = Instance.new("Frame")
			row.BackgroundColor3 = Color3.new(1, 1, 1)
			row.BackgroundTransparency = 0.96
			row.BorderSizePixel = 0
			row.Position = UDim2.fromOffset(0, (visibleIndex - 1) * 64)
			row.Size = UDim2.new(1, 0, 0, 58)
			row.ZIndex = Z.Content + 3
			row.Parent = favoritesList
			Corner(row, 10)
			Stroke(row, Color3.new(1, 1, 1), 1, 0.94)
			local playlistIconBox = Instance.new("Frame")
			playlistIconBox.BackgroundColor3 = Color3.new(1, 1, 1)
			playlistIconBox.BackgroundTransparency = 0.91
			playlistIconBox.BorderSizePixel = 0
			playlistIconBox.Position = UDim2.fromOffset(10, 9)
			playlistIconBox.Size = UDim2.fromOffset(40, 40)
			playlistIconBox.ZIndex = Z.Content + 4
			playlistIconBox.Parent = row
			Corner(playlistIconBox, 8)
			local playlistIcon = Instance.new("ImageLabel")
			playlistIcon.BackgroundTransparency = 1
			playlistIcon.Image = ResolveIcon("list-music")
			playlistIcon.ImageColor3 = BobloNEXT.Theme.Text
			playlistIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			playlistIcon.Position = UDim2.fromScale(0.5, 0.5)
			playlistIcon.Size = UDim2.fromOffset(15, 15)
			playlistIcon.ZIndex = Z.Content + 5
			playlistIcon.Parent = playlistIconBox
			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.FontFace = BobloNEXT.Theme.Font
			name.Text = tostring(favorite.name or "Spotify playlist")
			name.TextColor3 = BobloNEXT.Theme.Text
			name.TextSize = 11
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Position = UDim2.fromOffset(60, 8)
			name.Size = UDim2.new(1, -152, 0, 20)
			name.ZIndex = Z.Content + 4
			name.Parent = row
			local subtitle = Instance.new("TextLabel")
			subtitle.BackgroundTransparency = 1
			subtitle.FontFace = BobloNEXT.Theme.FontRegular
			subtitle.Text = "Spotify playlist"
			subtitle.TextColor3 = BobloNEXT.Theme.TextDim
			subtitle.TextSize = 9
			subtitle.TextXAlignment = Enum.TextXAlignment.Left
			subtitle.Position = UDim2.fromOffset(60, 30)
			subtitle.Size = UDim2.new(1, -152, 0, 16)
			subtitle.ZIndex = Z.Content + 4
			subtitle.Parent = row
			local loadFavorite = Instance.new("TextButton")
			loadFavorite.Text = ""
			loadFavorite.AutoButtonColor = false
			loadFavorite.BackgroundColor3 = Color3.new(1, 1, 1)
			loadFavorite.BackgroundTransparency = 0.91
			loadFavorite.BorderSizePixel = 0
			loadFavorite.Position = UDim2.new(1, -76, 0, 13)
			loadFavorite.Size = UDim2.fromOffset(32, 32)
			loadFavorite.ZIndex = Z.Content + 5
			loadFavorite.Parent = row
			Corner(loadFavorite, 8)
			local loadFavoriteIcon = Instance.new("ImageLabel")
			loadFavoriteIcon.BackgroundTransparency = 1
			loadFavoriteIcon.Image = ResolveIcon("play")
			loadFavoriteIcon.ImageColor3 = BobloNEXT.Theme.Text
			loadFavoriteIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			loadFavoriteIcon.Position = UDim2.fromScale(0.5, 0.5)
			loadFavoriteIcon.Size = UDim2.fromOffset(13, 13)
			loadFavoriteIcon.ZIndex = Z.Content + 6
			loadFavoriteIcon.Parent = loadFavorite
			local removeFavorite = Instance.new("TextButton")
			removeFavorite.Text = ""
			removeFavorite.BackgroundColor3 = Color3.new(1, 1, 1)
			removeFavorite.BackgroundTransparency = 0.94
			removeFavorite.Position = UDim2.new(1, -38, 0, 13)
			removeFavorite.Size = UDim2.fromOffset(30, 32)
			removeFavorite.ZIndex = Z.Content + 5
			removeFavorite.Parent = row
			Corner(removeFavorite, 8)
			local removeFavoriteIcon = Instance.new("ImageLabel")
			removeFavoriteIcon.BackgroundTransparency = 1
			removeFavoriteIcon.Image = ResolveIcon("trash-2")
			removeFavoriteIcon.ImageColor3 = Color3.fromRGB(220, 125, 125)
			removeFavoriteIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			removeFavoriteIcon.Position = UDim2.fromScale(0.5, 0.5)
			removeFavoriteIcon.Size = UDim2.fromOffset(13, 13)
			removeFavoriteIcon.ZIndex = Z.Content + 6
			removeFavoriteIcon.Parent = removeFavorite
			jan:Add(loadFavorite.MouseButton1Click:Connect(function()
				playlistBox.Text = tostring(favorite.url or "")
				setView("Spotify Player")
				if send("load_playlist", { url = playlistBox.Text }) then
					setStatus("Loading favorite playlist...", Color3.fromRGB(30, 215, 96))
					spotifyNotify("favorite_load", "Open Spotify Bridge", "Open the browser site, wait for the playlist and press Play once. Then return to Roblox to control it here.", "warning", "external-link", 8)
				end
			end))
			jan:Add(removeFavorite.MouseButton1Click:Connect(function()
				local removedName = tostring(favorite.name or "Spotify playlist")
				table.remove(favorites, originalIndex)
				saveFavorites()
				renderFavorites()
				spotifyNotify("favorite_removed", "Favorite removed", removedName, "success", "trash-2", 3)
			end))
			table.insert(favoriteRows, row)
		end
		end
	end
	jan:Add(favoritesSearchBox:GetPropertyChangedSignal("Text"):Connect(renderFavorites))
 
	jan:Add(addFavoriteBtn.MouseButton1Click:Connect(function()
		local url = playlistBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if url == "" then
			spotifyNotify("favorite_missing", "Nothing to save", "Paste or load a Spotify playlist first.", "warning", "heart", 4)
			return
		end
		for _, favorite in ipairs(favorites) do
			if favorite.url == url then
				spotifyNotify("favorite_duplicate", "Already saved", "This playlist is already in your favorites.", "warning", "heart", 4)
				return
			end
		end
		table.insert(favorites, 1, { name = currentPlaylistName, url = url })
		saveFavorites()
		renderFavorites()
		spotifyNotify("favorite_saved", "Playlist saved", currentPlaylistName .. " was added to Favorites.", "success", "heart", 4)
	end))
	renderFavorites()
 
	local function paintModes()
		controlRefs.PlayPause.Icon.Image = ResolveIcon(isPlaying and "pause" or "play")
		controlRefs.Shuffle.Icon.ImageColor3 = shuffle and Color3.fromRGB(30, 215, 96) or BobloNEXT.Theme.TextDim
		controlRefs.Repeat.Icon.ImageColor3 = repeatMode ~= "off" and Color3.fromRGB(30, 215, 96) or BobloNEXT.Theme.TextDim
	end
 
	local function applyState(data)
		local track = data.track or data.item or {}
		local artists = track.artist or track.artists or data.artist
		if type(artists) == "table" then
			local names = {}
			for _, artist in ipairs(artists) do
				table.insert(names, type(artist) == "table" and tostring(artist.name or "") or tostring(artist))
			end
			artists = table.concat(names, ", ")
		end
		trackLabel.Text = tostring(track.name or data.trackName or "Nothing playing")
		artistLabel.Text = tostring(artists or "Spotify")
		showCover(track.image or track.imageUrl or track.albumArt or data.image or data.imageUrl)
		isPlaying = data.isPlaying == true or data.playing == true
		shuffle = data.shuffle == true or data.shuffleState == true
		repeatMode = tostring(data.repeatMode or data.repeat_state or "off")
		durationMs = tonumber(track.durationMs or track.duration_ms or data.durationMs or data.duration_ms) or 0
		progressMs = tonumber(data.progressMs or data.progress_ms or data.positionMs or data.position_ms) or 0
		lastStateClock = os.clock()
		paintModes()
		renderProgress()
		if trackLabel.Text ~= "Playlist ready" and trackLabel.Text ~= "Nothing playing" then
			setStatus(isPlaying and "Playing — controls synced" or "Paused — controls synced", Color3.fromRGB(30, 215, 96))
		end
	end
 
	local function clearSocketConnections()
		for _, connection in ipairs(socketConnections) do
			pcall(function() connection:Disconnect() end)
		end
		table.clear(socketConnections)
	end
 
	local function disconnectBridge(silent)
		clearSocketConnections()
		local oldSocket = socket
		socket = nil
		isConnected = false
		if connectBtnIcon then connectBtnIcon.Image = ResolveIcon("link-2") end
		if oldSocket then pcall(function() oldSocket:Close() end) end
		if not silent then setStatus("Bridge disconnected", Color3.fromRGB(125, 130, 128)) end
	end
 
	local function bindSocketEvent(event, callback)
		if event and type(event.Connect) == "function" then
			local ok, connection = pcall(function() return event:Connect(callback) end)
			if ok and connection then table.insert(socketConnections, connection) end
		end
	end
 
	connectBridge = function()
		if isConnected then
			local pageUrl = tostring(opts.ConnectUrl or "")
			local pairUrl = pageUrl .. (pageUrl:find("?", 1, true) and "&" or "?") .. "code=" .. pairBox.Text
			local copy = hasFn("setclipboard")
			if copy then
				pcall(copy, pairUrl)
				setStatus("Player link copied — open it in your browser", Color3.fromRGB(30, 215, 96))
				spotifyNotify("link_copied", "Player link copied", "Open the link in your browser and keep that tab running.", "success", "external-link", 6, {
					{ Text = "Copy again", Callback = function() pcall(copy, pairUrl) end },
				})
			else
				setStatus("Open the player page and enter code " .. pairBox.Text, Color3.fromRGB(255, 190, 90))
				spotifyNotify("manual_code", "Open Spotify Bridge", "Clipboard is unavailable. Open the player page and enter code " .. pairBox.Text .. ".", "warning", "monitor-up", 7)
			end
			return
		end
		local bridgeUrl = tostring(opts.BridgeUrl or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if not bridgeUrl:match("^wss?://") then
			setStatus("Spotify bridge is not configured by the script owner", Color3.fromRGB(255, 105, 105))
			return
		end
		local url = bridgeUrl
			.. (bridgeUrl:find("?", 1, true) and "&" or "?")
			.. "code=" .. pairBox.Text .. "&role=game"
		local connect = websocketConnect()
		if not connect then
			setStatus("This executor has no WebSocket support", Color3.fromRGB(255, 105, 105))
			return
		end
		setStatus("Connecting...", Color3.fromRGB(255, 190, 90))
		if connectBtnIcon then connectBtnIcon.Image = ResolveIcon("loader-circle") end
		task.spawn(function()
			local ok, result = pcall(connect, url)
			if not ok or not result then
				if connectBtnIcon then connectBtnIcon.Image = ResolveIcon("link-2") end
				setStatus("Connection failed: " .. tostring(result), Color3.fromRGB(255, 105, 105))
				return
			end
			socket = result
			isConnected = true
			if connectBtnIcon then connectBtnIcon.Image = ResolveIcon("copy") end
			local pageUrl = tostring(opts.ConnectUrl or "")
			local pairUrl = pageUrl .. (pageUrl:find("?", 1, true) and "&" or "?") .. "code=" .. pairBox.Text
			local copy = hasFn("setclipboard")
			if copy then pcall(copy, pairUrl) end
			setStatus(copy and "Player link copied — open it in your browser" or ("Open player page; code " .. pairBox.Text), Color3.fromRGB(30, 215, 96))
			if copy then
				spotifyNotify("initial_link", "Spotify Connect ready", "The player link was copied. Open it now and keep the browser tab running.", "success", "copy-check", 7, {
					{ Text = "Copy again", Callback = function() pcall(copy, pairUrl) end },
				})
			else
				spotifyNotify("manual_code", "Open Spotify Bridge", "Enter pairing code " .. pairBox.Text .. " on the player page.", "warning", "monitor-up", 7)
			end
 
			bindSocketEvent(socket.OnMessage, function(raw)
				local decoded
				local decodedOk = pcall(function() decoded = HttpService:JSONDecode(tostring(raw)) end)
				if not decodedOk or type(decoded) ~= "table" then return end
				if decoded.type == "state" or decoded.event == "state" then
					applyState(decoded)
				elseif decoded.type == "queue" then
					local playlist = decoded.playlist or {}
					currentPlaylistName = tostring(playlist.name or "Spotify playlist")
					local trackCount = tonumber(decoded.count) or 0
					setStatus(string.format("%s — %d tracks ready", currentPlaylistName, trackCount), Color3.fromRGB(30, 215, 96))
					spotifyNotify("queue_ready_" .. currentPlaylistName, "Playlist ready", string.format("%s loaded with %d tracks.", currentPlaylistName, trackCount), "success", "list-music", 4)
				elseif decoded.type == "ready" or decoded.event == "ready" then
					local message = tostring(decoded.message or "Spotify ready")
					setStatus(message, Color3.fromRGB(30, 215, 96))
					local lower = message:lower()
					if lower:find("press", 1, true) or lower:find("open", 1, true) or lower:find("tap", 1, true) then
						spotifyNotify("browser_action", "Browser action needed", "Open Spotify Bridge and press Play once to unlock remote controls.", "warning", "monitor-play", 7)
					end
				elseif decoded.type == "needs_browser" then
					local message = tostring(decoded.message or "Open the Spotify player tab once to continue playback")
					setStatus(message, Color3.fromRGB(255, 190, 90))
					spotifyNotify("browser_attention", "Spotify needs attention", message, "warning", "external-link", 7)
				elseif decoded.type == "error" or decoded.event == "error" then
					local message = tostring(decoded.message or decoded.error or "Spotify bridge error")
					setStatus(message, Color3.fromRGB(255, 105, 105))
					spotifyNotify("spotify_error_" .. message, "Spotify error", message, "error", "circle-x", 6)
				end
			end)
			bindSocketEvent(socket.OnClose, function()
				disconnectBridge(false)
			end)
			send("hello", { client = "BobloNEXT", protocol = 1 })
		end)
	end
 
	jan:Add(connectBtn.MouseButton1Click:Connect(connectBridge))
	jan:Add(loadBtn.MouseButton1Click:Connect(function()
		local url = playlistBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if url == "" then
			setStatus("Paste a Spotify playlist link", Color3.fromRGB(255, 190, 90))
			return
		end
		if send("load_playlist", { url = url }) then
			setStatus("Playlist sent to Spotify", Color3.fromRGB(30, 215, 96))
			spotifyNotify("playlist_sent", "Open Spotify Bridge", "Open the browser site, wait for the playlist and press Play once. Then return to Roblox to control it here.", "warning", "external-link", 8)
		end
	end))
	local function searchPlaylist()
		local query = searchBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if query == "" then setStatus("Type a song or artist to search", Color3.fromRGB(255, 190, 90)); return end
		if send("search", { query = query }) then setStatus("Searching this playlist...", Color3.fromRGB(30, 215, 96)) end
	end
	jan:Add(searchBtn.MouseButton1Click:Connect(searchPlaylist))
	jan:Add(searchBox.FocusLost:Connect(function(enterPressed) if enterPressed then searchPlaylist() end end))
	jan:Add(shuffleBtn.MouseButton1Click:Connect(function() send("toggle_shuffle") end))
	jan:Add(previousBtn.MouseButton1Click:Connect(function() send("previous") end))
	jan:Add(playBtn.MouseButton1Click:Connect(function() send("play_pause") end))
	jan:Add(nextBtn.MouseButton1Click:Connect(function() send("next") end))
	jan:Add(repeatBtn.MouseButton1Click:Connect(function() send("cycle_repeat") end))
	local seekInput
	local function updateSeekPreview(screenX)
		if durationMs <= 0 or progressTrack.AbsoluteSize.X <= 0 then return end
		local alpha = math.clamp((screenX - progressTrack.AbsolutePosition.X) / progressTrack.AbsoluteSize.X, 0, 1)
		seekPreviewMs = math.floor(durationMs * alpha)
		progressFill.Size = UDim2.new(alpha, 0, 1, 0)
		progressKnob.Position = UDim2.new(alpha, 0, 0.5, 0)
		seekBubble.Position = UDim2.new(math.clamp(alpha, 0.04, 0.96), 0, 0, -8)
		seekBubbleLabel.Text = formatTime(seekPreviewMs)
		timeLabel.Text = formatTime(seekPreviewMs)
	end
	jan:Add(progressHitbox.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if durationMs <= 0 then return end
		seekDragging = true
		seekInput = input
		seekBubble.Visible = true
		updateSeekPreview(input.Position.X)
	end))
	jan:Add(UserInputService.InputChanged:Connect(function(input)
		if not seekDragging then return end
		if input == seekInput or input.UserInputType == Enum.UserInputType.MouseMovement then
			updateSeekPreview(input.Position.X)
		end
	end))
	jan:Add(UserInputService.InputEnded:Connect(function(input)
		if not seekDragging then return end
		if input ~= seekInput and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		updateSeekPreview(input.Position.X)
		seekDragging = false
		seekInput = nil
		seekBubble.Visible = false
		if send("seek", { positionMs = seekPreviewMs }) then
			progressMs = seekPreviewMs
			lastStateClock = os.clock()
		end
		renderProgress()
	end))
 
	jan:Add(function() disconnectBridge(true) end)
	dockBtn = self:AddDockButton({
		Icon = opts.Icon or "Lucide:music-2",
		Callback = function() panel.Toggle() end,
	})
 
	panel.Connect = connectBridge
	panel.Disconnect = disconnectBridge
	panel.Send = send
	panel.SetState = applyState
	if opts.BridgeUrl == nil or opts.BridgeUrl == "" then
		setStatus("Spotify bridge is not configured by the script owner", Color3.fromRGB(255, 190, 90))
	else
		setStatus("Tap Connect, then open the copied browser link", Color3.fromRGB(125, 130, 128))
	end
	return panel
end
 
function Window:_BuildDefaultChatTools()
	local windowSelf = self
 
	return {
		{
			Name = "list_ui_elements",
			Description = "Lists every UI element that has a Flag, with its kind and current value.",
			Parameters = { type = "object", properties = {}, required = {} },
			Handler = function()
				return BobloNEXT:ListUIElements()
			end,
		},
		{
			Name = "set_ui_element_value",
			Description = "Sets a UI element's value by its flag name. Use list_ui_elements first to find valid flags.",
			Parameters = {
				type = "object",
				properties = {
					flag  = { type = "string", description = "The Flag of the UI element to change." },
					value = { description = "The new value: true/false for a Toggle, a number for a Slider, a string for a Textbox/Dropdown." },
				},
				required = { "flag", "value" },
			},
			Handler = function(args)
				local ok, err = BobloNEXT:SetUIElementValue(args.flag, args.value)
				if not ok then error(err, 0) end
				return true
			end,
		},
		{
			Name = "select_tab",
			Description = "Switches the panel to one of its top-level sidebar tabs.",
			Parameters = {
				type = "object",
				properties = {
					tab = { type = "string", description = "The tab's name." },
				},
				required = { "tab" },
			},
			Handler = function(args)
				local tabObj = windowSelf:SelectTab(args.tab)
				if not tabObj then error("No tab named '" .. tostring(args.tab) .. "'", 0) end
				return "Switched to " .. tabObj.Name
			end,
		},
		{
			Name = "select_subtab",
			Description = "Switches to a sub-tab nested under one of the top-level tabs. Selects the "
				.. "parent tab first automatically -- no need to call select_tab beforehand.",
			Parameters = {
				type = "object",
				properties = {
					tab    = { type = "string", description = "The top-level tab that contains the sub-tab." },
					subtab = { type = "string", description = "The sub-tab's name." },
				},
				required = { "tab", "subtab" },
			},
			Handler = function(args)
				local tabObj = windowSelf:SelectTab(args.tab)
				if not tabObj then error("No tab named '" .. tostring(args.tab) .. "'", 0) end
				local sub = tabObj:SelectSubTabByName(args.subtab)
				if not sub then
					error("No sub-tab named '" .. tostring(args.subtab) .. "' under " .. tabObj.Name, 0)
				end
				return "Switched to " .. tabObj.Name .. " > " .. sub.Name
			end,
		},
		{
			Name = "find_and_highlight_element",
			Description = "Finds a UI element (button, toggle, card, slider, etc.) by its visible label, "
				.. "jumps to whichever tab or sub-tab it lives on, scrolls to it, and flashes a highlight "
				.. "on it -- the same thing Ctrl+K search does when you click a result.",
			Parameters = {
				type = "object",
				properties = {
					query = { type = "string", description = "The element's visible text. Partial matches are fine." },
				},
				required = { "query" },
			},
			Handler = function(args)
				local ok, titleOrErr = windowSelf:JumpToElement(args.query)
				if not ok then error(titleOrErr, 0) end
				return "Highlighted: " .. titleOrErr
			end,
		},
	}
end
 
function Window:_BuildDefaultSystemPrompt()
	local names = {}
	for _, t in ipairs(self._tabs) do
		if not t.Hidden then table.insert(names, t.Name) end
	end
 
	return "You are a helpful assistant embedded in a Roblox UI panel built with BobloNEXT. Your tools "
		.. "only affect THIS PANEL -- they inspect/adjust the panel's own toggles/sliders/etc, switch "
		.. "between its top-level tabs (" .. table.concat(names, ", ") .. "), switch to a specific "
		.. "sub-tab within one of those, and jump to/highlight a specific UI element on the panel by "
		.. "its visible label. Only use select_tab, select_subtab, or find_and_highlight_element when "
		.. "the user is asking to be taken somewhere IN THIS PANEL, or to interact with a control "
		.. "that's actually on it. If the user asks you to write a script, explain something, or "
		.. "anything else that isn't about navigating this panel, just answer directly in chat -- do "
		.. "not call a tool just because the message happens to mention a word that sounds like a "
		.. "setting. When you write a Luau script for the user, put it in a normal ```lua fenced block "
		.. "-- the panel automatically adds a Run button to it that the user can click themselves, so "
		.. "you don't need to explain how to run it or tell them you can't execute code; you're just "
		.. "not the one who decides to run it -- they click Run after reading it. Keep answers short "
		.. "and to the point. None of your tools execute anything outside this panel, and you have no "
		.. "way to trigger the Run button yourself."
end
 
function Window:AddChatPanel(opts)
	opts = opts or {}
	opts.Tools = opts.Tools or self:_BuildDefaultChatTools()
	local jan = self._janitor
 
	local tabObj = self:AddTab({
		Name   = opts.Name or "Assistant",
		Icon   = opts.Icon or "bot",
		Hidden = true,
	})
	tabObj._page.Visible = false
 
	local staleEmptyState = tabObj._group:FindFirstChild("EmptyState")
	if staleEmptyState then staleEmptyState.Visible = false end
 
	local toolByName = {}
	for _, tool in ipairs(opts.Tools or {}) do
		if tool.Name then toolByName[tool.Name] = tool end
	end
 
	local INPUT_H = 38
	local HEADER_H = 38
 
	local panel = Instance.new("Frame")
	panel.Name = "ChatPanel"
	panel.BackgroundTransparency = 1
	panel.ClipsDescendants = true
	panel.Size = UDim2.fromScale(1, 1)
	panel.ZIndex = Z.Content
	panel.Parent = tabObj._group
 
	local BASE_Z = panel.ZIndex + 1
 
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = panel.ZIndex
	content.Parent = panel
 
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Active = true
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.ZIndex = BASE_Z
	header.Parent = content
 
	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingLeft = UDim.new(0, 14)
	headerPad.PaddingRight = UDim.new(0, 8)
	headerPad.Parent = header
 
	local titleRow = Instance.new("Frame")
	titleRow.BackgroundTransparency = 1
	titleRow.Size = UDim2.new(1, -84, 1, 0)
	titleRow.ZIndex = BASE_Z + 1
	titleRow.Parent = header
 
	local titleLayout = Instance.new("UIListLayout")
	titleLayout.FillDirection = Enum.FillDirection.Horizontal
	titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	titleLayout.Padding = UDim.new(0, 7)
	titleLayout.Parent = titleRow
 
	local titleIcon = Instance.new("ImageLabel")
	titleIcon.BackgroundTransparency = 1
	titleIcon.Image = ResolveIcon(opts.Icon or "bot")
	titleIcon.ImageColor3 = BobloNEXT.Theme.Text
	titleIcon.Size = UDim2.fromOffset(14, 14)
	titleIcon.LayoutOrder = 1
	titleIcon.ZIndex = BASE_Z + 2
	titleIcon.Parent = titleRow
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = BobloNEXT.Theme.Font
	titleLabel.Text = opts.Title or "Assistant"
	titleLabel.TextColor3 = BobloNEXT.Theme.Text
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.AutomaticSize = Enum.AutomaticSize.X
	titleLabel.Size = UDim2.fromOffset(0, 16)
	titleLabel.LayoutOrder = 2
	titleLabel.ZIndex = BASE_Z + 2
	titleLabel.Parent = titleRow
 
	local controls = Instance.new("Frame")
	controls.BackgroundTransparency = 1
	controls.AnchorPoint = Vector2.new(1, 0.5)
	controls.Position = UDim2.new(1, 0, 0.5, 0)
	controls.Size = UDim2.fromOffset(100, 22)
	controls.ZIndex = BASE_Z + 1
	controls.Parent = header
 
	local controlsLayout = Instance.new("UIListLayout")
	controlsLayout.FillDirection = Enum.FillDirection.Horizontal
	controlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	controlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	controlsLayout.Padding = UDim.new(0, 4)
	controlsLayout.Parent = controls
 
	local function headerIconButton(icon, layoutOrder)
		local btn = Instance.new("TextButton")
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = Color3.new(1, 1, 1)
		btn.BackgroundTransparency = 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.fromOffset(22, 22)
		btn.LayoutOrder = layoutOrder
		btn.ZIndex = BASE_Z + 1
		btn.Parent = controls
		Corner(btn, 6)
 
		local ic = Instance.new("ImageLabel")
		ic.BackgroundTransparency = 1
		ic.Image = ResolveIcon(icon)
		ic.ImageColor3 = BobloNEXT.Theme.TextDim
		ic.Size = UDim2.fromOffset(13, 13)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.ZIndex = BASE_Z + 2
		ic.Parent = btn
 
		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = 0.9 }, 0.12)
			Tween(ic, { ImageColor3 = BobloNEXT.Theme.Text }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = 1 }, 0.12)
			Tween(ic, { ImageColor3 = BobloNEXT.Theme.TextDim }, 0.12)
		end))
 
		return btn, ic
	end
 
	local copyBtn, copyIcon = headerIconButton("copy", 1)
	local regenBtn, regenIcon = headerIconButton("refresh-cw", 2)
	local clearBtn = headerIconButton("trash-2", 3)
	local closeBtn = headerIconButton("x", 4)
 
	local headerDivider = Instance.new("Frame")
	headerDivider.BackgroundColor3 = Color3.new(1, 1, 1)
	headerDivider.BackgroundTransparency = 0.94
	headerDivider.BorderSizePixel = 0
	headerDivider.Position = UDim2.fromOffset(0, HEADER_H)
	headerDivider.Size = UDim2.new(1, 0, 0, 1)
	headerDivider.ZIndex = BASE_Z
	headerDivider.Parent = content
 
	local contentPad = Instance.new("UIPadding")
	contentPad.PaddingLeft = UDim.new(0, 14)
	contentPad.PaddingRight = UDim.new(0, 14)
	contentPad.PaddingBottom = UDim.new(0, 12)
	contentPad.Parent = content
 
	local inputRow = Instance.new("Frame")
	inputRow.BackgroundTransparency = 1
	inputRow.Active = true
	inputRow.AnchorPoint = Vector2.new(0, 1)
	inputRow.Position = UDim2.new(0, 0, 1, 0)
	inputRow.Size = UDim2.new(1, 0, 0, INPUT_H)
	inputRow.ZIndex = BASE_Z
	inputRow.Parent = content
 
	local pill = Instance.new("Frame")
	pill.BackgroundColor3 = Color3.new(1, 1, 1)
	pill.BackgroundTransparency = 0.95
	pill.BorderSizePixel = 0
	pill.Size = UDim2.new(1, -(INPUT_H + 6), 1, 0)
	pill.ZIndex = BASE_Z + 1
	pill.Parent = inputRow
	Corner(pill, 9)
	local pillStroke = Stroke(pill, Color3.new(1, 1, 1), 1, 0.9)
 
	local pillPad = Instance.new("UIPadding")
	pillPad.PaddingLeft = UDim.new(0, 10)
	pillPad.PaddingRight = UDim.new(0, 10)
	pillPad.Parent = pill
 
	local inputBox = Instance.new("TextBox")
	inputBox.BackgroundTransparency = 1
	inputBox.ClearTextOnFocus = false
	inputBox.FontFace = BobloNEXT.Theme.FontRegular
	inputBox.PlaceholderText = opts.Placeholder or "Ask me anything..."
	inputBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 122)
	inputBox.Text = ""
	inputBox.TextColor3 = BobloNEXT.Theme.Text
	inputBox.TextSize = 13
	inputBox.TextXAlignment = Enum.TextXAlignment.Left
	inputBox.TextYAlignment = Enum.TextYAlignment.Center
	inputBox.ClipsDescendants = true
	inputBox.Size = UDim2.fromScale(1, 1)
	inputBox.ZIndex = BASE_Z + 2
	inputBox.Parent = pill
 
	jan:Add(inputBox.Focused:Connect(function()
		Tween(pillStroke, { Color = BobloNEXT.Theme.Accent, Transparency = 0.3 }, 0.15)
	end))
	jan:Add(inputBox.FocusLost:Connect(function()
		Tween(pillStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.9 }, 0.15)
	end))
 
	local sendBtn = Instance.new("TextButton")
	sendBtn.Name = "Send"
	sendBtn.Text = ""
	sendBtn.AutoButtonColor = false
	sendBtn.BackgroundColor3 = Color3.new(1, 1, 1)
	sendBtn.BackgroundTransparency = 0.9
	sendBtn.BorderSizePixel = 0
	sendBtn.AnchorPoint = Vector2.new(1, 0)
	sendBtn.Position = UDim2.new(1, 0, 0, 0)
	sendBtn.Size = UDim2.fromOffset(INPUT_H, INPUT_H)
	sendBtn.ZIndex = BASE_Z + 1
	sendBtn.Parent = inputRow
	Corner(sendBtn, 9)
 
	local sendIcon = Instance.new("ImageLabel")
	sendIcon.BackgroundTransparency = 1
	sendIcon.Image = ResolveIcon("send")
	sendIcon.ImageColor3 = BobloNEXT.Theme.Text
	sendIcon.Size = UDim2.fromOffset(14, 14)
	sendIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	sendIcon.Position = UDim2.fromScale(0.5, 0.5)
	sendIcon.ZIndex = BASE_Z + 2
	sendIcon.Parent = sendBtn
 
	jan:Add(sendBtn.MouseEnter:Connect(function() Tween(sendBtn, { BackgroundTransparency = 0.8 }, 0.12) end))
	jan:Add(sendBtn.MouseLeave:Connect(function() Tween(sendBtn, { BackgroundTransparency = 0.9 }, 0.12) end))
 
	local msgScroll = Instance.new("ScrollingFrame")
	msgScroll.BackgroundTransparency = 1
	msgScroll.BorderSizePixel = 0
	msgScroll.Position = UDim2.fromOffset(0, HEADER_H + 9)
	msgScroll.Size = UDim2.new(1, 0, 1, -(HEADER_H + 9 + INPUT_H + 10))
	msgScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	msgScroll.ScrollBarThickness = 0
	msgScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	msgScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	msgScroll.ZIndex = BASE_Z
	msgScroll.Parent = content
 
	local msgPad = Instance.new("UIPadding")
	msgPad.PaddingRight = UDim.new(0, 18)
	msgPad.Parent = msgScroll
 
	local msgLayout = Instance.new("UIListLayout")
	msgLayout.Padding = UDim.new(0, 8)
	msgLayout.SortOrder = Enum.SortOrder.LayoutOrder
	msgLayout.Parent = msgScroll
 
	AddScrollbar(msgScroll)
	AddContentScrollThumb(msgScroll, msgLayout, panel, jan)
 
	local order = 0
	local transcript = {}
 
	local pinnedToBottom = true
	jan:Add(msgScroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
		if pinnedToBottom then
			msgScroll.CanvasPosition = Vector2.new(0, msgScroll.AbsoluteCanvasSize.Y)
		end
	end))
	jan:Add(msgScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local atBottom = msgScroll.CanvasPosition.Y
			>= msgScroll.AbsoluteCanvasSize.Y - msgScroll.AbsoluteWindowSize.Y - 20
		pinnedToBottom = atBottom
	end))
 
	local function scrollToBottom()
		pinnedToBottom = true
		task.defer(function()
			if msgScroll and msgScroll.Parent then
				msgScroll.CanvasPosition = Vector2.new(0, msgScroll.AbsoluteCanvasSize.Y)
			end
		end)
	end
 
	local AVATAR = 26
 
	local function addBubble(text, role)
		local isUser = role == "user"
		order = order + 1
 
		text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n\n\n+", "\n\n")
 
		local row = Instance.new("Frame")
		row.Name = "MessageRow"
		row.BackgroundTransparency = 1
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.Size = UDim2.new(1, 0, 0, 0)
		row.LayoutOrder = order
		row.ZIndex = BASE_Z + 1
		row.Parent = msgScroll
 
		local rowScale = Instance.new("UIScale")
		rowScale.Scale = 0.92
		rowScale.Parent = row
 
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.HorizontalAlignment = isUser and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		rowLayout.Padding = UDim.new(0, 8)
		rowLayout.Parent = row
 
		local avatarFinalTransparency = isUser and 0.85 or 0.82
		local avatar = Instance.new("Frame")
		avatar.Name = "Avatar"
		avatar.BackgroundColor3 = isUser and Color3.new(1, 1, 1) or BobloNEXT.Theme.Accent
		avatar.BackgroundTransparency = 1
		avatar.BorderSizePixel = 0
		avatar.Size = UDim2.fromOffset(AVATAR, AVATAR)
		avatar.LayoutOrder = isUser and 2 or 1
		avatar.ZIndex = BASE_Z + 2
		avatar.Parent = row
		Corner(avatar, AVATAR / 2)
 
		local avatarIcon
		if isUser then
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.ImageTransparency = 1
			img.ScaleType = Enum.ScaleType.Crop
			img.Size = UDim2.fromScale(1, 1)
			img.ZIndex = BASE_Z + 3
			img.Parent = avatar
			Corner(img, AVATAR / 2)
			avatarIcon = img
			task.spawn(function()
				local ok, content = pcall(
					Players.GetUserThumbnailAsync,
					Players,
					LocalPlayer.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size100x100
				)
				if ok and content and img.Parent then
					img.Image = content
				end
			end)
		else
			local botIcon = Instance.new("ImageLabel")
			botIcon.BackgroundTransparency = 1
			botIcon.ImageTransparency = 1
			botIcon.Image = ResolveIcon("bot")
			botIcon.ImageColor3 = BobloNEXT.Theme.Accent
			botIcon.Size = UDim2.fromOffset(14, 14)
			botIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			botIcon.Position = UDim2.fromScale(0.5, 0.5)
			botIcon.ZIndex = BASE_Z + 3
			botIcon.Parent = avatar
			avatarIcon = botIcon
		end
 
		local segments = SplitMessageSegments(text)
		local hasCode = false
		for _, seg in ipairs(segments) do
			if seg.kind == "code" then hasCode = true end
		end
 
		local H_PAD, V_PAD = 10, 8
		local BUBBLE_MAX_WIDTH = hasCode and 380 or 260
		local bubbleWidth
		if hasCode then
			bubbleWidth = BUBBLE_MAX_WIDTH
		else
			local naturalW = MeasureText(segments[1].content, 13, 10000)
			bubbleWidth = math.min(naturalW, BUBBLE_MAX_WIDTH - H_PAD * 2) + H_PAD * 2
		end
		if msgScroll.AbsoluteSize.X > 0 then
			bubbleWidth = math.min(bubbleWidth, math.max(200, msgScroll.AbsoluteSize.X - 20))
		end
 
		local bubbleFinalTransparency = isUser and 0.72 or 0.9
		local bubble = Instance.new("Frame")
		bubble.Name = "Bubble"
		bubble.BackgroundColor3 = isUser and BobloNEXT.Theme.Accent or Color3.new(1, 1, 1)
		bubble.BackgroundTransparency = 1
		bubble.BorderSizePixel = 0
		bubble.AutomaticSize = Enum.AutomaticSize.Y
		bubble.Size = UDim2.fromOffset(bubbleWidth, 0)
		bubble.LayoutOrder = isUser and 1 or 2
		bubble.ZIndex = BASE_Z + 2
		bubble.Parent = row
		Corner(bubble, 12)
		local strokeFinalTransparency = isUser and 0.8 or 0.9
		local bubbleStroke = Stroke(bubble, Color3.new(1, 1, 1), 1, 1)
 
		local bubblePad = Instance.new("UIPadding")
		bubblePad.PaddingTop = UDim.new(0, V_PAD)
		bubblePad.PaddingBottom = UDim.new(0, V_PAD)
		bubblePad.PaddingLeft = UDim.new(0, H_PAD)
		bubblePad.PaddingRight = UDim.new(0, H_PAD)
		bubblePad.Parent = bubble
 
		local bubbleLayout = Instance.new("UIListLayout")
		bubbleLayout.FillDirection = Enum.FillDirection.Vertical
		bubbleLayout.Padding = UDim.new(0, 8)
		bubbleLayout.SortOrder = Enum.SortOrder.LayoutOrder
		bubbleLayout.Parent = bubble
 
		Tween(avatar, { BackgroundTransparency = avatarFinalTransparency }, 0.16)
		Tween(avatarIcon, { ImageTransparency = 0 }, 0.16)
		Tween(bubble, { BackgroundTransparency = bubbleFinalTransparency }, 0.16)
		Tween(bubbleStroke, { Transparency = strokeFinalTransparency }, 0.16)
		Tween(rowScale, { Scale = 1 }, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
 
		local TYPE_START_DELAY = 0.08
		local maxTypeDuration = 0
 
		for i, seg in ipairs(segments) do
			if seg.kind == "code" then
				local card = Instance.new("Frame")
				card.Name = "CodeBlock"
				card.BackgroundColor3 = BobloNEXT.Theme.Background
				card.BackgroundTransparency = 0.1
				card.BorderSizePixel = 0
				card.ClipsDescendants = true
				card.AutomaticSize = Enum.AutomaticSize.Y
				card.Size = UDim2.new(1, 0, 0, 0)
				card.LayoutOrder = i
				card.ZIndex = BASE_Z + 3
				card.Parent = bubble
				Corner(card, 8)
				Stroke(card, Color3.new(1, 1, 1), 1, 0.92)
 
				local cardLayout = Instance.new("UIListLayout")
				cardLayout.FillDirection = Enum.FillDirection.Vertical
				cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
				cardLayout.Parent = card
 
				local header = Instance.new("Frame")
				header.BackgroundTransparency = 1
				header.Size = UDim2.new(1, 0, 0, 24)
				header.LayoutOrder = 1
				header.ZIndex = BASE_Z + 4
				header.Parent = card
 
				local langLabel = Instance.new("TextLabel")
				langLabel.BackgroundTransparency = 1
				langLabel.FontFace = BobloNEXT.Theme.FontRegular
				langLabel.Text = seg.lang
				langLabel.TextColor3 = BobloNEXT.Theme.TextDim
				langLabel.TextSize = 11
				langLabel.TextXAlignment = Enum.TextXAlignment.Left
				langLabel.Position = UDim2.fromOffset(10, 0)
				langLabel.Size = UDim2.new(1, -70, 1, 0)
				langLabel.ZIndex = BASE_Z + 5
				langLabel.Parent = header
 
				local function codeHeaderButton(icon, rightOffset)
					local btn = Instance.new("TextButton")
					btn.Text = ""
					btn.AutoButtonColor = false
					btn.BackgroundColor3 = Color3.new(1, 1, 1)
					btn.BackgroundTransparency = 1
					btn.BorderSizePixel = 0
					btn.AnchorPoint = Vector2.new(1, 0.5)
					btn.Position = UDim2.new(1, -rightOffset, 0.5, 0)
					btn.Size = UDim2.fromOffset(20, 20)
					btn.ZIndex = BASE_Z + 5
					btn.Parent = header
					Corner(btn, 5)
 
					local ic = Instance.new("ImageLabel")
					ic.BackgroundTransparency = 1
					ic.Image = ResolveIcon(icon)
					ic.ImageColor3 = BobloNEXT.Theme.TextDim
					ic.Size = UDim2.fromOffset(12, 12)
					ic.AnchorPoint = Vector2.new(0.5, 0.5)
					ic.Position = UDim2.fromScale(0.5, 0.5)
					ic.ZIndex = BASE_Z + 6
					ic.Parent = btn
 
					jan:Add(btn.MouseEnter:Connect(function()
						Tween(btn, { BackgroundTransparency = 0.85 }, 0.12)
						Tween(ic, { ImageColor3 = BobloNEXT.Theme.Text }, 0.12)
					end))
					jan:Add(btn.MouseLeave:Connect(function()
						Tween(btn, { BackgroundTransparency = 1 }, 0.12)
						Tween(ic, { ImageColor3 = BobloNEXT.Theme.TextDim }, 0.12)
					end))
 
					return btn, ic
				end
 
				local copyBtn, copyIcon = codeHeaderButton("copy", 8)
				jan:Add(copyBtn.MouseButton1Click:Connect(function()
					local setclipboard = hasFn("setclipboard")
					if not setclipboard then return end
					pcall(setclipboard, seg.content)
					Tween(copyIcon, { ImageColor3 = Color3.fromRGB(120, 220, 140) }, 0.1)
					task.delay(0.4, function()
						if copyIcon.Parent then
							Tween(copyIcon, { ImageColor3 = BobloNEXT.Theme.TextDim }, 0.15)
						end
					end)
				end))
 
				if opts.OnRunCode then
					local runBtn, runIcon = codeHeaderButton("play", 32)
					jan:Add(runBtn.MouseButton1Click:Connect(function()
						BobloNEXT:Confirm({
							Title = "Run this code?",
							Text = "This runs exactly what's shown above, right now, in this game.",
							ConfirmText = "Run",
							CancelText = "Cancel",
							Danger = true,
							Window = self,
							Callback = function(confirmed)
								if not confirmed then return end
								local ok, err = pcall(opts.OnRunCode, seg.content, seg.lang)
								BobloNEXT:Notify({
									Title = ok and "Ran" or "Run failed",
									Text = ok and "Code executed." or tostring(err),
									Type = ok and "success" or "error",
									Duration = 3,
								})
							end,
						})
					end))
				end
 
				local headerDivider = Instance.new("Frame")
				headerDivider.BackgroundColor3 = Color3.new(1, 1, 1)
				headerDivider.BackgroundTransparency = 0.92
				headerDivider.BorderSizePixel = 0
				headerDivider.Size = UDim2.new(1, 0, 0, 1)
				headerDivider.LayoutOrder = 2
				headerDivider.ZIndex = BASE_Z + 4
				headerDivider.Parent = card
 
				local codeContainer = Instance.new("Frame")
				codeContainer.BackgroundTransparency = 1
				codeContainer.AutomaticSize = Enum.AutomaticSize.Y
				codeContainer.Size = UDim2.new(1, 0, 0, 0)
				codeContainer.LayoutOrder = 3
				codeContainer.ZIndex = BASE_Z + 4
				codeContainer.Parent = card
 
				local codePad = Instance.new("UIPadding")
				codePad.PaddingTop = UDim.new(0, 8)
				codePad.PaddingBottom = UDim.new(0, 8)
				codePad.PaddingLeft = UDim.new(0, 10)
				codePad.PaddingRight = UDim.new(0, 10)
				codePad.Parent = codeContainer
 
				local codeLabel = Instance.new("TextLabel")
				codeLabel.BackgroundTransparency = 1
				codeLabel.FontFace = Font.new(CHAT_CODE_FONT, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
				codeLabel.RichText = true
				codeLabel.Text = HighlightLua(EscapeRichText(seg.content))
				codeLabel.TextColor3 = BobloNEXT.Theme.Text
				codeLabel.TextSize = 12
				codeLabel.TextWrapped = true
				codeLabel.TextXAlignment = Enum.TextXAlignment.Left
				codeLabel.TextYAlignment = Enum.TextYAlignment.Top
				codeLabel.LineHeight = 1.3
				codeLabel.AutomaticSize = Enum.AutomaticSize.Y
				codeLabel.Size = UDim2.new(1, 0, 0, 16)
				codeLabel.ZIndex = BASE_Z + 5
				codeLabel.Parent = codeContainer
			else
				local label = Instance.new("TextLabel")
				label.Name = "Prose"
				label.BackgroundTransparency = 1
				label.FontFace = BobloNEXT.Theme.FontRegular
				label.RichText = true
				label.Text = MarkdownToRichText(seg.content)
				label.TextColor3 = BobloNEXT.Theme.Text
				label.TextTransparency = 1
				label.TextSize = 13
				label.TextWrapped = true
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.TextYAlignment = Enum.TextYAlignment.Top
				label.LineHeight = 1.3
				label.AutomaticSize = Enum.AutomaticSize.Y
				label.Size = UDim2.new(1, 0, 0, 16)
				label.LayoutOrder = i
				label.ZIndex = BASE_Z + 3
 
				label.MaxVisibleGraphemes = 0
				label.Parent = bubble
 
				Tween(label, { TextTransparency = 0 }, 0.16)
 
				local graphemeCount = utf8.len(seg.content) or #seg.content
				local typeDuration = math.clamp(graphemeCount * 0.014, 0.12, 1.6)
				maxTypeDuration = math.max(maxTypeDuration, typeDuration)
				task.delay(TYPE_START_DELAY, function()
					if label and label.Parent then
						TweenService:Create(
							label,
							TweenInfo.new(typeDuration, Enum.EasingStyle.Linear),
							{ MaxVisibleGraphemes = graphemeCount }
						):Play()
					end
				end)
			end
		end
 
		scrollToBottom()
		table.insert(transcript, (isUser and "You" or "Assistant") .. ": " .. text)
 
		return TYPE_START_DELAY + maxTypeDuration
	end
 
	local bumpTypingToBottom
 
	local function addToolLine(name)
		order = order + 1
		local row = Instance.new("Frame")
		row.Name = "ToolCall"
		row.BackgroundTransparency = 1
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.Size = UDim2.new(1, 0, 0, 18)
		row.LayoutOrder = order
		row.ZIndex = BASE_Z + 1
		row.Parent = msgScroll
 
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.Padding = UDim.new(0, 6)
		rowLayout.Parent = row
 
		local toolIcon = Instance.new("ImageLabel")
		toolIcon.BackgroundTransparency = 1
		toolIcon.Image = ResolveIcon("wrench")
		toolIcon.ImageColor3 = BobloNEXT.Theme.Accent
		toolIcon.Size = UDim2.fromOffset(11, 11)
		toolIcon.LayoutOrder = 1
		toolIcon.ZIndex = BASE_Z + 2
		toolIcon.Parent = row
 
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.FontFace = BobloNEXT.Theme.FontRegular
		label.Text = "Called tool: " .. tostring(name)
		label.TextColor3 = BobloNEXT.Theme.TextDim
		label.TextSize = 11
		label.AutomaticSize = Enum.AutomaticSize.XY
		label.Size = UDim2.fromOffset(0, 14)
		label.LayoutOrder = 2
		label.ZIndex = BASE_Z + 2
		label.Parent = row
 
		scrollToBottom()
		table.insert(transcript, "[Called tool: " .. tostring(name) .. "]")
		if bumpTypingToBottom then bumpTypingToBottom() end
	end
 
	local typingRow, typingTweens, typingActive = nil, nil, false
 
	local function destroyTypingRow()
		if not typingRow then return end
		for _, tw in ipairs(typingTweens) do tw:Cancel() end
		local row = typingRow
		typingRow, typingTweens = nil, nil
		row:Destroy()
	end
 
	local function buildTypingRow()
		order = order + 1
 
		local row = Instance.new("Frame")
		row.Name = "TypingRow"
		row.BackgroundTransparency = 1
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.Size = UDim2.new(1, 0, 0, 0)
		row.LayoutOrder = order
		row.ZIndex = BASE_Z + 1
		row.Parent = msgScroll
 
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		rowLayout.Padding = UDim.new(0, 8)
		rowLayout.Parent = row
 
		local avatar = Instance.new("Frame")
		avatar.BackgroundColor3 = BobloNEXT.Theme.Accent
		avatar.BackgroundTransparency = 1
		avatar.BorderSizePixel = 0
		avatar.Size = UDim2.fromOffset(AVATAR, AVATAR)
		avatar.LayoutOrder = 1
		avatar.ZIndex = BASE_Z + 2
		avatar.Parent = row
		Corner(avatar, AVATAR / 2)
 
		local botIcon = Instance.new("ImageLabel")
		botIcon.BackgroundTransparency = 1
		botIcon.ImageTransparency = 1
		botIcon.Image = ResolveIcon("bot")
		botIcon.ImageColor3 = BobloNEXT.Theme.Accent
		botIcon.Size = UDim2.fromOffset(14, 14)
		botIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		botIcon.Position = UDim2.fromScale(0.5, 0.5)
		botIcon.ZIndex = BASE_Z + 3
		botIcon.Parent = avatar
 
		local bubble = Instance.new("Frame")
		bubble.BackgroundColor3 = Color3.new(1, 1, 1)
		bubble.BackgroundTransparency = 1
		bubble.BorderSizePixel = 0
		bubble.Size = UDim2.fromOffset(38, AVATAR)
		bubble.LayoutOrder = 2
		bubble.ZIndex = BASE_Z + 2
		bubble.Parent = row
		Corner(bubble, 12)
		local bubbleStroke = Stroke(bubble, Color3.new(1, 1, 1), 1, 1)
 
		local tweens = {}
		for i = 1, 3 do
			local baseX = 10 + (i - 1) * 9
			local dot = Instance.new("Frame")
			dot.BackgroundColor3 = BobloNEXT.Theme.TextDim
			dot.BackgroundTransparency = 1
			dot.BorderSizePixel = 0
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.new(0, baseX, 0.5, 0)
			dot.Size = UDim2.fromOffset(4, 4)
			dot.ZIndex = BASE_Z + 3
			dot.Parent = bubble
			Corner(dot, 2)
			Tween(dot, { BackgroundTransparency = 0 }, 0.15)
 
			tweens[i] = TweenService:Create(
				dot,
				TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, (i - 1) * 0.15),
				{ Position = UDim2.new(0, baseX, 0.5, -3) }
			)
			tweens[i]:Play()
		end
 
		Tween(avatar, { BackgroundTransparency = 0.82 }, 0.15)
		Tween(botIcon, { ImageTransparency = 0 }, 0.15)
		Tween(bubble, { BackgroundTransparency = 0.9 }, 0.15)
		Tween(bubbleStroke, { Transparency = 0.9 }, 0.15)
 
		typingRow, typingTweens = row, tweens
		scrollToBottom()
	end
 
	local function showTyping()
		if typingRow then return end
		typingActive = true
		buildTypingRow()
	end
 
	function bumpTypingToBottom()
		if not typingRow then return end
		destroyTypingRow()
		buildTypingRow()
	end
 
	local function hideTyping()
		if not typingActive then return end
		typingActive = false
		destroyTypingRow()
	end
 
	local function addMessage(role, text)
		text = tostring(text or "")
		if text == "" then return end
		hideTyping()
		if role == "tool" then
			addToolLine(text)
			return nil
		end
		return addBubble(text, role)
	end
 
	local function handleToolCall(name, args)
		local tool = toolByName[name]
		addToolLine(name)
		if not tool or not tool.Handler then
			addMessage("assistant", "Unknown tool: " .. tostring(name))
			return nil
		end
		local ok, result = pcall(tool.Handler, args)
		if not ok then
			addMessage("assistant", "Tool error: " .. tostring(result))
			return nil
		end
		return result
	end
 
	local api
 
	local sending = false
	local lastUserText = nil
 
	local function setSending(value)
		sending = value
		sendIcon.Image = ResolveIcon(value and "square" or "send")
	end
 
	local function trySend(overrideText)
		local text = overrideText or inputBox.Text
		if sending or text == "" then return end
		setSending(true)
		if not overrideText then inputBox.Text = "" end
		lastUserText = text
		local revealTime = addMessage("user", text)
		if opts.OnSend then
			local finished = false
 
			task.spawn(function()
 
				if revealTime and revealTime > 0 then task.wait(revealTime) end
				local ok, err = pcall(opts.OnSend, api, text)
				if not ok then
					addMessage("assistant", "Error: " .. tostring(err))
				end
				finished = true
				setSending(false)
			end)
 
			task.delay(opts.SendTimeout or 30, function()
				if not finished and sending then
					setSending(false)
					hideTyping()
					addMessage("assistant", "(Taking too long -- you can try sending again.)")
				end
			end)
		else
			setSending(false)
		end
	end
 
	local function tryRegenerate()
		if sending or not lastUserText then return end
		if opts.OnRegenerate then
			task.spawn(opts.OnRegenerate, api, lastUserText)
		else
			trySend(lastUserText)
		end
	end
 
	local lastRealTab = nil
 
	local function openChat()
		if self._currentTab == tabObj then return end
		if self._currentTab and not self._currentTab.Hidden then
			lastRealTab = self._currentTab
		end
		tabObj._select()
	end
 
	local function closeChat()
		if self._currentTab ~= tabObj then return end
		if lastRealTab and not lastRealTab.Hidden then
			lastRealTab._select()
		elseif self._tabs[1] and self._tabs[1] ~= tabObj then
			self._tabs[1]._select()
		end
	end
 
	table.insert(self._tabChangeListeners, function(selected)
		if opts.OnToggle then task.spawn(opts.OnToggle, selected == tabObj) end
	end)
 
	local function clearChat()
		hideTyping()
		for _, child in ipairs(msgScroll:GetChildren()) do
			if child.Name == "MessageRow" or child.Name == "ToolCall" then
				child:Destroy()
			end
		end
		table.clear(transcript)
		if opts.OnClear then task.spawn(opts.OnClear) end
	end
 
	jan:Add(sendBtn.MouseButton1Click:Connect(function()
		if sending then
			if opts.OnStop then task.spawn(opts.OnStop, api) end
		else
			trySend()
		end
	end))
	jan:Add(inputBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then trySend() end
	end))
	jan:Add(closeBtn.MouseButton1Click:Connect(closeChat))
 
	jan:Add(copyBtn.MouseButton1Click:Connect(function()
		local setclipboard = hasFn("setclipboard")
		if not setclipboard or #transcript == 0 then return end
		pcall(setclipboard, table.concat(transcript, "\n\n"))
		Tween(copyIcon, { ImageColor3 = Color3.fromRGB(120, 220, 140) }, 0.1)
		task.delay(0.4, function()
			if copyIcon.Parent then
				Tween(copyIcon, { ImageColor3 = BobloNEXT.Theme.TextDim }, 0.15)
			end
		end)
	end))
	jan:Add(regenBtn.MouseButton1Click:Connect(function()
		if sending or not lastUserText then return end
		Tween(regenIcon, { Rotation = regenIcon.Rotation + 180 }, 0.25)
		tryRegenerate()
	end))
	jan:Add(clearBtn.MouseButton1Click:Connect(function()
		clearChat()
		lastUserText = nil
	end))
 
	api = {
		Instance = panel,
		Tab = tabObj,
		Open = openChat,
		Close = closeChat,
		Toggle = function()
			if self._currentTab == tabObj then closeChat() else openChat() end
		end,
		IsOpen = function() return self._currentTab == tabObj end,
		AddMessage = function(_, role, text) addMessage(role, text) end,
		LogToolCall = function(_, name) addToolLine(name) end,
		HandleToolCall = function(_, name, args) return handleToolCall(name, args) end,
		ShowTyping = function() showTyping() end,
		HideTyping = function() hideTyping() end,
		IsSending = function() return sending end,
		Clear = function() clearChat() end,
		Destroy = function() panel:Destroy() end,
	}
 
	return api
end
 
function Window:AddCloudPanel(opts)
	opts = opts or {}
	local service = opts.Service
 
	local tabObj = self:AddTab({
		Name   = opts.Name or "Cloud",
		Icon   = opts.Icon or "cloud",
		Hidden = opts.Hidden ~= false,
	})
 
	table.insert(self._tabChangeListeners, function(selected)
		if opts.OnToggle then task.spawn(opts.OnToggle, selected == tabObj) end
	end)
 
	local mineGrid, publicGrid, localGrid
	local function relativeTime(timestamp)
		local seconds = math.max(0, os.time() - tonumber(timestamp or os.time()))
		if seconds < 60 then return "updated just now" end
		if seconds < 3600 then return "updated " .. math.floor(seconds / 60) .. "m ago" end
		if seconds < 86400 then return "updated " .. math.floor(seconds / 3600) .. "h ago" end
		return "updated " .. math.floor(seconds / 86400) .. "d ago"
	end
 
	local CloudTabs = {
		Local = tabObj:AddSubTab({ Name = "Local Configs", Icon = "Lucide:hard-drive" }),
		Mine = tabObj:AddSubTab({ Name = "Publish Public Config", Icon = "Lucide:cloud-cog" }),
		Explore = tabObj:AddSubTab({ Name = "Public Configs", Icon = "Lucide:cloud" }),
	}
 
	CloudTabs.Local:AddParagraph({
		Title = "Local Library",
		Icon = "Lucide:hard-drive",
		Text = "Private presets saved only on this device. Load, create and manage them without uploading anything.",
	})
 
	CloudTabs.Local:AddSection("Quick Actions", "Lucide:zap")
	CloudTabs.Local:AddButton({
		Text = "Save Current Settings Locally",
		Description = "Stays on this device only",
		Icon = "Lucide:save",
		Callback = function()
			BobloNEXT:Modal({
				Title = "Save Config Locally",
				Text  = "Stays only on this device -- never sent anywhere.",
				ConfirmText = "Save",
				CancelText  = "Cancel",
				Window = self,
				Fields = {
					{ Key = "Name", Label = "Name", Placeholder = "Enter a name...", MaxLength = 60 },
					{ Key = "Description", Label = "Description (optional)", Type = "textarea",
						Placeholder = "What's different about this one?", MaxLength = 280 },
				},
				Callback = function(confirmed, values)
					if not confirmed then return end
					if not values.Name or values.Name:gsub("%s+", "") == "" then
						BobloNEXT:Notify({ Title = "Local Save", Text = "Name can't be empty.", Type = "warning", Duration = 3 })
						return
					end
					local function saveNow()
						local ok, err = BobloNEXT:SaveConfig(values.Name, { Description = values.Description })
						BobloNEXT:Notify({
							Title = ok and "Saved" or "Could not save", Text = ok and "Saved locally." or tostring(err),
							Type = ok and "success" or "error", Duration = 3,
						})
						if ok and localGrid then localGrid.Refresh() end
					end
					if BobloNEXT:GetConfigMeta(values.Name) then
						BobloNEXT:Confirm({
							Title = "Overwrite \"" .. tostring(values.Name) .. "\"?",
							Text = "A local config already uses this name.", ConfirmText = "Overwrite", CancelText = "Cancel",
							Danger = true, Window = self,
							Callback = function(overwrite) if overwrite then saveNow() end end,
						})
					else
						saveNow()
					end
				end,
			})
		end,
	})
 
	localGrid = CloudTabs.Local:AddCardGrid({
		Title = "Local Configs",
		Height = 224,
		FixedHeight = true,
		Search = true,
		SearchPlaceholder = "Search local configs...",
		CardHeight = 68,
		AutoCardHeight = false,
		CardMinWidth = 180,
		Columns = 2,
		MaxColumns = 2,
		OuterPadding = 12,
		CardPadding = 8,
		ShowScrollbar = true,
		EmptyText = "No local configs saved yet.",
		ErrorText = "Your executor doesn't support local file access.",
		Fetch = function(state)
			local items, err = BobloNEXT:ListConfigs()
			if err and #items == 0 then return nil, err end
			local query = string.lower(tostring(state and state.Query or ""))
			local out = {}
			for _, cfg in ipairs(items) do
				local searchable = string.lower(table.concat({
					tostring(cfg.Name or ""),
					tostring(cfg.Description or ""),
					table.concat(cfg.Tags or {}, " "),
				}, " "))
				if query ~= "" and not string.find(searchable, query, 1, true) then continue end
 
				local function loadLocalConfig()
					BobloNEXT:Confirm({
						Title = "Load \"" .. tostring(cfg.Name) .. "\"?",
						Text = "This overwrites your current settings. A snapshot is kept for instant undo.",
						ConfirmText = "Load", CancelText = "Cancel", Window = self,
						Callback = function(confirmedLoad)
							if not confirmedLoad then return end
							local snapshot = BobloNEXT:CreateSnapshot()
							local ok, loadErr = BobloNEXT:LoadConfig(cfg.Name, false)
							if not ok then
								BobloNEXT:Notify({ Title = "Could not load", Text = tostring(loadErr), Type = "error", Duration = 4 })
								return
							end
							BobloNEXT:Notify({
								Title = "Loaded", Text = tostring(cfg.Name) .. " is now active.", Type = "success", Duration = 6,
								Actions = {{ Text = "Undo", Callback = function() BobloNEXT:RestoreSnapshot(snapshot, false) end }},
							})
						end,
					})
				end
 
				local function renameLocalConfig()
					BobloNEXT:Modal({
						Title = "Rename Config", Text = "Choose a new name for \"" .. tostring(cfg.Name) .. "\".",
						ConfirmText = "Rename", CancelText = "Cancel", Window = self,
						Fields = {{ Key = "Name", Label = "New name", Default = cfg.Name, MaxLength = 60 }},
						Callback = function(confirmed, values)
							if not confirmed then return end
							local newName = tostring(values.Name or ""):match("^%s*(.-)%s*$")
							if newName == "" then return end
							local existing = BobloNEXT:GetConfigMeta(newName)
							if existing and newName ~= cfg.Name then
								BobloNEXT:Notify({ Title = "Name already used", Text = "Choose another config name.", Type = "warning", Duration = 3 })
								return
							end
							local ok, renameErr = BobloNEXT:RenameConfig(cfg.Name, newName)
							BobloNEXT:Notify({ Title = ok and "Renamed" or "Could not rename", Text = ok and "Config name updated." or tostring(renameErr), Type = ok and "success" or "error", Duration = 3 })
							if ok and localGrid then localGrid.Refresh() end
						end,
					})
				end
 
				local function publishLocalConfig()
					if not service then
						BobloNEXT:Notify({ Title = "Cloud", Text = "No cloud service configured.", Type = "warning", Duration = 3 })
						return
					end
					local saved, savedErr = BobloNEXT:GetSavedConfig(cfg.Name)
					if not saved then
						BobloNEXT:Notify({ Title = "Could not read config", Text = tostring(savedErr), Type = "error", Duration = 3 })
						return
					end
					local result, publishErr = service:Publish({ Name = cfg.Name, Description = cfg.Description, Tags = cfg.Tags }, saved.Data)
					BobloNEXT:Notify({ Title = result and "Published" or "Could not publish", Text = result and "Config published successfully." or tostring(publishErr), Type = result and "success" or "error", Duration = 4 })
					if result then
						if mineGrid then mineGrid.Refresh() end
						if publicGrid then publicGrid.Refresh() end
					end
				end
 
				local function deleteLocalConfig()
					BobloNEXT:Confirm({
						Title = "Delete \"" .. tostring(cfg.Name) .. "\"?", Text = "This local config will be permanently removed.",
						ConfirmText = "Delete", CancelText = "Cancel", Danger = true, Window = self,
						Callback = function(confirmed)
							if not confirmed then return end
							local ok, deleteErr = BobloNEXT:DeleteConfig(cfg.Name)
							BobloNEXT:Notify({ Title = ok and "Deleted" or "Could not delete", Text = ok and "Config removed." or tostring(deleteErr), Type = ok and "success" or "error", Duration = 3 })
							if ok and localGrid then localGrid.Refresh() end
						end,
					})
				end
 
				table.insert(out, {
					Title = cfg.Name,
					Description = cfg.Description,
					Byline = relativeTime(cfg.CreatedAt)
						.. ((cfg.Tags and #cfg.Tags > 0) and ("  •  " .. table.concat(cfg.Tags, ", ")) or ""),
					Icon = "Lucide:file-text",
					ActionIcon = "download",
					Callback = loadLocalConfig,
					SecondaryIcon = "trash-2",
					SecondaryCallback = deleteLocalConfig,
					SecondaryDanger = true,
				})
			end
			return out
		end,
	})
 
	local function publishFlow()
		if not service then
			BobloNEXT:Notify({ Title = "Cloud", Text = "No cloud service configured.", Type = "warning", Duration = 3 })
			return
		end
		BobloNEXT:Modal({
			Title = "New Config",
			ConfirmText = "Publish",
			CancelText = "Cancel",
			Window = self,
			Fields = {
				{ Key = "Name", Label = "Name", Placeholder = "Enter profile name...", MaxLength = 60 },
				{ Key = "Description", Label = "Description", Type = "textarea",
					Placeholder = "Enter profile's description...", MaxLength = 280 },
				{ Key = "Tags", Label = "Tags (optional)", Type = "tags",
					Placeholder = "Enter tags separated by commas..." },
			},
			Callback = function(confirmed, values)
				if not confirmed then return end
				local result, err = service:Publish({
					Name = values.Name,
					Description = values.Description,
					Tags = values.Tags,
				})
				BobloNEXT:Notify({
					Title = result and "Published" or "Could not publish",
					Text  = result and "Your config is now public." or tostring(err),
					Type  = result and "success" or "error",
					Duration = 4,
				})
				if result then
					if mineGrid then mineGrid.Refresh() end
					if publicGrid then publicGrid.Refresh() end
				end
			end,
		})
	end
 
	CloudTabs.Mine:AddParagraph({
		Title = "My Cloud Library",
		Icon = "Lucide:cloud",
		Text = "Publish your current setup, review what you shared and remove old uploads from one place.",
	})
 
	CloudTabs.Mine:AddSection("Publishing", "Lucide:upload-cloud")
	CloudTabs.Mine:AddButton({
		Text = "Publish Current Settings",
		Description = "Share your current config publicly",
		Icon = "Lucide:upload-cloud",
		Callback = publishFlow,
	})
 
	mineGrid = CloudTabs.Mine:AddCardGrid({
		Title = "Your Configs",
		Height = 210,
		FixedHeight = true,
		Search = false,
		CardHeight = 104,
		AutoCardHeight = false,
		DescriptionHeight = 24,
		CardMinWidth = 180,
		Columns = 2,
		MaxColumns = 2,
		OuterPadding = 12,
		CardPadding = 8,
		ShowScrollbar = true,
		EmptyText = service and "You haven't published anything yet." or "No cloud service configured.",
		ErrorText = "Couldn't load your configs.",
		Fetch = function()
			if not service then
				return {}, nil
			end
			local items, err = service:ListMine()
			if not items then return nil, err end
			local out = {}
			for _, cfg in ipairs(items) do
				local function deletePublishedConfig()
					BobloNEXT:Confirm({
						Title = "Delete \"" .. tostring(cfg.Name) .. "\"?",
						Text = "This removes it from the public library. This cannot be undone.",
						ConfirmText = "Delete", CancelText = "Cancel", Danger = true, Window = self,
						Callback = function(confirmedDelete)
							if not confirmedDelete then return end
							local ok, delErr = service:Delete(cfg.Id)
							BobloNEXT:Notify({ Title = ok and "Deleted" or "Could not delete", Text = ok and "Config removed." or tostring(delErr), Type = ok and "success" or "error", Duration = 3 })
							if ok then
								if mineGrid then mineGrid.Refresh() end
								if publicGrid then publicGrid.Refresh() end
							end
						end,
					})
				end
				table.insert(out, {
					Title = cfg.Name,
					Description = cfg.Description,
					Byline = cfg.CreatedAtText or "",
					Icon = "Lucide:cloud",
					Stats = {
						{ Icon = "thumbs-up", Text = tostring(cfg.Likes or 0) },
						{ Icon = "download", Text = tostring(cfg.Downloads or 0) },
					},
					Menu = {
						{ Text = "Delete publication", Icon = "trash-2", Danger = true, Callback = deletePublishedConfig },
					},
				})
			end
			return out
		end,
	})
 
	CloudTabs.Explore:AddParagraph({
		Title = "Community Library",
		Icon = "Lucide:compass",
		Text = "Discover public configs, compare popularity and apply a setup with an instant undo snapshot.",
	})
 
	CloudTabs.Explore:AddSection("Browse Configs", "Lucide:layout-grid")
 
	local SORT_MAP = { ["Top Rated"] = "top", ["Most Downloaded"] = "downloads", ["Newest"] = "new" }
 
	publicGrid = CloudTabs.Explore:AddCardGrid({
		Title = "Public Configs",
		Height = 230,
		FixedHeight = true,
		Sorts = { "Top Rated", "Most Downloaded", "Newest" },
		SearchPlaceholder = "Search config by name / tags...",
		CardHeight = 112,
		AutoCardHeight = false,
		DescriptionHeight = 24,
		CardMinWidth = 180,
		Columns = 2,
		MaxColumns = 2,
		OuterPadding = 12,
		CardPadding = 8,
		ShowScrollbar = true,
		EmptyText = "No public configs match your search.",
		ErrorText = "Couldn't reach the cloud service.",
		Fetch = function(state)
			if not service then return nil, "No cloud service configured." end
			local items, err = service:List({
				Query = state.Query,
				Sort = SORT_MAP[state.Sort] or "top",
				PageSize = state.PageSize,
			})
			if not items then return nil, err end
			local out = {}
			for _, cfg in ipairs(items) do
				local byline = cfg.OwnerName or "anonymous"
				if cfg.CreatedAtText then byline = byline .. " \226\128\162 " .. cfg.CreatedAtText end
				table.insert(out, {
					Title = cfg.Name,
					Description = cfg.Description,
					Byline = byline,
					Icon = "Lucide:cloud-download",
					ActionIcon = "download",
					Stats = {
						{
							Icon = "thumbs-up",
							Text = tostring(cfg.Likes or 0),
							Callback = function()
								local liked, likeErr = service:Like(cfg.Id)
								if not liked then
									BobloNEXT:Notify({
										Title = "Could not like",
										Text  = tostring(likeErr),
										Type  = "error",
										Duration = 3,
									})
									return
								end
								if publicGrid then publicGrid.Refresh() end
							end,
						},
						{ Icon = "download", Text = tostring(cfg.Downloads or 0) },
					},
					Callback = function()
						BobloNEXT:Confirm({
							Title = "Apply \"" .. tostring(cfg.Name) .. "\"?",
							Text  = "This overwrites your current settings. A snapshot of what you have now "
								.. "is kept so you can undo it right after.",
							ConfirmText = "Apply",
							CancelText  = "Cancel",
							Window = self,
							Callback = function(confirmedApply)
								if not confirmedApply then return end
								local result, dlErr = service:Download(cfg.Id)
								if not result or not result.Data then
									BobloNEXT:Notify({
										Title = "Could not apply",
										Text  = tostring(dlErr),
										Type  = "error",
										Duration = 4,
									})
									return
								end
 
								local snapshot = BobloNEXT:CreateSnapshot()
 
								BobloNEXT:SetConfig(result.Data, false)
								BobloNEXT:Notify({
									Title = "Applied",
									Text  = tostring(cfg.Name) .. " is now active.",
									Type  = "success",
									Duration = 6,
									Actions = {
										{
											Text = "Undo",
											Callback = function()
												BobloNEXT:RestoreSnapshot(snapshot, false)
												BobloNEXT:Notify({
													Title = "Reverted",
													Text  = "Your previous settings are back.",
													Type  = "info",
													Duration = 3,
												})
											end,
										},
									},
								})
 
								if publicGrid then publicGrid.Refresh() end
								if opts.OnApplied then task.spawn(opts.OnApplied, cfg) end
							end,
						})
					end,
				})
			end
			return out
		end,
	})
 
	local lastRealTab = nil
	local function openPanel()
		if self._currentTab == tabObj then return end
		if self._currentTab and not self._currentTab.Hidden then
			lastRealTab = self._currentTab
		end
		tabObj._select()
	end
	local function closePanel()
		if self._currentTab ~= tabObj then return end
		if lastRealTab and not lastRealTab.Hidden then
			lastRealTab._select()
		elseif self._tabs[1] and self._tabs[1] ~= tabObj then
			self._tabs[1]._select()
		end
	end
 
	return {
		Instance = tabObj._group,
		Tab = tabObj,
		Open = openPanel,
		Close = closePanel,
		Toggle = function()
			if self._currentTab == tabObj then closePanel() else openPanel() end
		end,
		IsOpen = function() return self._currentTab == tabObj end,
		RefreshMine = function() if mineGrid then mineGrid.Refresh() end end,
		RefreshPublic = function() if publicGrid then publicGrid.Refresh() end end,
	}
end
 
function Window:AddGlobalChatPanel(opts)
	opts = opts or {}
	local service = opts.Service
	local jan = self._janitor
 
	local tabObj = self:AddTab({
		Name   = opts.Name or "Chat",
		Icon   = opts.Icon or "messages-square",
		Hidden = opts.Hidden ~= false,
	})
	tabObj._page.Visible = false
	local staleEmptyState = tabObj._group:FindFirstChild("EmptyState")
	if staleEmptyState then staleEmptyState.Visible = false end
 
	table.insert(self._tabChangeListeners, function(selected)
		if opts.OnToggle then task.spawn(opts.OnToggle, selected == tabObj) end
	end)
 
	local INPUT_H, HEADER_H = 38, 38
 
	local panel = Instance.new("Frame")
	panel.Name = "GlobalChatPanel"
	panel.BackgroundTransparency = 1
	panel.ClipsDescendants = true
	panel.Size = UDim2.fromScale(1, 1)
	panel.ZIndex = Z.Content
	panel.Parent = tabObj._group
 
	local BASE_Z = panel.ZIndex + 1
 
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = panel.ZIndex
	content.Parent = panel
 
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Active = true
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.ZIndex = BASE_Z
	header.Parent = content
 
	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingLeft = UDim.new(0, 14)
	headerPad.PaddingRight = UDim.new(0, 8)
	headerPad.Parent = header
 
	local titleRow = Instance.new("Frame")
	titleRow.BackgroundTransparency = 1
	titleRow.Size = UDim2.new(1, -136, 1, 0)
	titleRow.ZIndex = BASE_Z + 1
	titleRow.Parent = header
 
	local titleLayout = Instance.new("UIListLayout")
	titleLayout.FillDirection = Enum.FillDirection.Horizontal
	titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	titleLayout.Padding = UDim.new(0, 7)
	titleLayout.Parent = titleRow
 
	local titleIcon = Instance.new("ImageLabel")
	titleIcon.BackgroundTransparency = 1
	titleIcon.Image = ResolveIcon(opts.Icon or "messages-square")
	titleIcon.ImageColor3 = BobloNEXT.Theme.Text
	titleIcon.Size = UDim2.fromOffset(14, 14)
	titleIcon.LayoutOrder = 1
	titleIcon.ZIndex = BASE_Z + 2
	titleIcon.Parent = titleRow
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = BobloNEXT.Theme.Font
	titleLabel.Text = opts.Title or "Chat"
	titleLabel.TextColor3 = BobloNEXT.Theme.Text
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.AutomaticSize = Enum.AutomaticSize.X
	titleLabel.Size = UDim2.fromOffset(0, 16)
	titleLabel.LayoutOrder = 2
	titleLabel.ZIndex = BASE_Z + 2
	titleLabel.Parent = titleRow
 
	local controls = Instance.new("Frame")
	controls.BackgroundTransparency = 1
	controls.AnchorPoint = Vector2.new(1, 0.5)
	controls.Position = UDim2.new(1, 0, 0.5, 0)
	controls.Size = UDim2.fromOffset(126, 22)
	controls.ZIndex = BASE_Z + 1
	controls.Parent = header
 
	local controlsLayout = Instance.new("UIListLayout")
	controlsLayout.FillDirection = Enum.FillDirection.Horizontal
	controlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	controlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	controlsLayout.Padding = UDim.new(0, 4)
	controlsLayout.Parent = controls
 
	local function headerIconButton(icon, layoutOrder)
		local btn = Instance.new("TextButton")
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = Color3.new(1, 1, 1)
		btn.BackgroundTransparency = 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.fromOffset(22, 22)
		btn.LayoutOrder = layoutOrder
		btn.ZIndex = BASE_Z + 1
		btn.Parent = controls
		Corner(btn, 6)
 
		local ic = Instance.new("ImageLabel")
		ic.BackgroundTransparency = 1
		ic.Image = ResolveIcon(icon)
		ic.ImageColor3 = BobloNEXT.Theme.TextDim
		ic.Size = UDim2.fromOffset(13, 13)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.ZIndex = BASE_Z + 2
		ic.Parent = btn
 
		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = 0.9 }, 0.12)
			Tween(ic, { ImageColor3 = BobloNEXT.Theme.Text }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = 1 }, 0.12)
			Tween(ic, { ImageColor3 = BobloNEXT.Theme.TextDim }, 0.12)
		end))
 
		return btn, ic
	end
 
	local anonymousMode = opts.AnonymousByDefault ~= false
	local showTimestamps = true
	local notifySound = false
	local pollInterval = opts.PollInterval or 2.5
 
	local copyBtn, copyIcon = headerIconButton("copy", 1)
	local anonBtn, anonIcon = headerIconButton(anonymousMode and "eye-off" or "eye", 2)
	local clearBtn, clearIcon = headerIconButton("trash-2", 3)
	local settingsBtn, settingsIcon = headerIconButton("settings", 4)
	local closeBtn, closeIcon = headerIconButton("x", 5)
 
	local headerDivider = Instance.new("Frame")
	headerDivider.BackgroundColor3 = Color3.new(1, 1, 1)
	headerDivider.BackgroundTransparency = 0.94
	headerDivider.BorderSizePixel = 0
	headerDivider.Position = UDim2.fromOffset(0, HEADER_H)
	headerDivider.Size = UDim2.new(1, 0, 0, 1)
	headerDivider.ZIndex = BASE_Z
	headerDivider.Parent = content
 
	local contentPad = Instance.new("UIPadding")
	contentPad.PaddingLeft = UDim.new(0, 14)
	contentPad.PaddingRight = UDim.new(0, 14)
	contentPad.PaddingBottom = UDim.new(0, 12)
	contentPad.Parent = content
 
	local inputRow = Instance.new("Frame")
	inputRow.BackgroundTransparency = 1
	inputRow.Active = true
	inputRow.AnchorPoint = Vector2.new(0, 1)
	inputRow.Position = UDim2.new(0, 0, 1, 0)
	inputRow.Size = UDim2.new(1, 0, 0, INPUT_H)
	inputRow.ZIndex = BASE_Z
	inputRow.Parent = content
 
	local pill = Instance.new("Frame")
	pill.BackgroundColor3 = Color3.new(1, 1, 1)
	pill.BackgroundTransparency = 0.95
	pill.BorderSizePixel = 0
	pill.Size = UDim2.new(1, -(INPUT_H + 6), 1, 0)
	pill.ZIndex = BASE_Z + 1
	pill.Parent = inputRow
	Corner(pill, 9)
	local pillStroke = Stroke(pill, Color3.new(1, 1, 1), 1, 0.9)
 
	local pillPad = Instance.new("UIPadding")
	pillPad.PaddingLeft = UDim.new(0, 10)
	pillPad.PaddingRight = UDim.new(0, 10)
	pillPad.Parent = pill
 
	local inputBox = Instance.new("TextBox")
	inputBox.BackgroundTransparency = 1
	inputBox.ClearTextOnFocus = false
	inputBox.FontFace = BobloNEXT.Theme.FontRegular
	inputBox.PlaceholderText = opts.Placeholder or "Message everyone using this script..."
	inputBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 122)
	inputBox.Text = ""
	inputBox.TextColor3 = BobloNEXT.Theme.Text
	inputBox.TextSize = 13
	inputBox.TextXAlignment = Enum.TextXAlignment.Left
	inputBox.TextYAlignment = Enum.TextYAlignment.Center
	inputBox.ClipsDescendants = true
	inputBox.Size = UDim2.fromScale(1, 1)
	inputBox.ZIndex = BASE_Z + 2
	inputBox.Parent = pill
 
	jan:Add(inputBox.Focused:Connect(function()
		Tween(pillStroke, { Color = BobloNEXT.Theme.Accent, Transparency = 0.3 }, 0.15)
	end))
	jan:Add(inputBox.FocusLost:Connect(function()
		Tween(pillStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.9 }, 0.15)
	end))
 
	local sendBtn = Instance.new("TextButton")
	sendBtn.Text = ""
	sendBtn.AutoButtonColor = false
	sendBtn.BackgroundColor3 = Color3.new(1, 1, 1)
	sendBtn.BackgroundTransparency = 0.9
	sendBtn.BorderSizePixel = 0
	sendBtn.AnchorPoint = Vector2.new(1, 0)
	sendBtn.Position = UDim2.new(1, 0, 0, 0)
	sendBtn.Size = UDim2.fromOffset(INPUT_H, INPUT_H)
	sendBtn.ZIndex = BASE_Z + 1
	sendBtn.Parent = inputRow
	Corner(sendBtn, 9)
 
	local sendIcon = Instance.new("ImageLabel")
	sendIcon.BackgroundTransparency = 1
	sendIcon.Image = ResolveIcon("send")
	sendIcon.ImageColor3 = BobloNEXT.Theme.Text
	sendIcon.Size = UDim2.fromOffset(14, 14)
	sendIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	sendIcon.Position = UDim2.fromScale(0.5, 0.5)
	sendIcon.ZIndex = BASE_Z + 2
	sendIcon.Parent = sendBtn
 
	jan:Add(sendBtn.MouseEnter:Connect(function() Tween(sendBtn, { BackgroundTransparency = 0.8 }, 0.12) end))
	jan:Add(sendBtn.MouseLeave:Connect(function() Tween(sendBtn, { BackgroundTransparency = 0.9 }, 0.12) end))
 
	local msgScroll = Instance.new("ScrollingFrame")
	msgScroll.BackgroundTransparency = 1
	msgScroll.BorderSizePixel = 0
	msgScroll.Position = UDim2.fromOffset(0, HEADER_H + 9)
	msgScroll.Size = UDim2.new(1, 0, 1, -(HEADER_H + 9 + INPUT_H + 10))
	msgScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	msgScroll.ScrollBarThickness = 0
	msgScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	msgScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	msgScroll.ZIndex = BASE_Z
	msgScroll.Parent = content
 
	local msgPad = Instance.new("UIPadding")
	msgPad.PaddingRight = UDim.new(0, 18)
	msgPad.Parent = msgScroll
 
	local msgLayout = Instance.new("UIListLayout")
	msgLayout.Padding = UDim.new(0, 8)
	msgLayout.SortOrder = Enum.SortOrder.LayoutOrder
	msgLayout.Parent = msgScroll
 
	AddScrollbar(msgScroll)
	AddContentScrollThumb(msgScroll, msgLayout, panel, jan)
 
	local order = 0
	local transcript = {}
	local timestampLabels = {}
	local pinnedToBottom = true
	jan:Add(msgScroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
		if pinnedToBottom then
			msgScroll.CanvasPosition = Vector2.new(0, msgScroll.AbsoluteCanvasSize.Y)
		end
	end))
	jan:Add(msgScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local atBottom = msgScroll.CanvasPosition.Y
			>= msgScroll.AbsoluteCanvasSize.Y - msgScroll.AbsoluteWindowSize.Y - 20
		pinnedToBottom = atBottom
	end))
 
	local function scrollToBottom()
		pinnedToBottom = true
		task.defer(function()
			if msgScroll and msgScroll.Parent then
				msgScroll.CanvasPosition = Vector2.new(0, msgScroll.AbsoluteCanvasSize.Y)
			end
		end)
	end
 
	local AVATAR = 26
 
	local function addBubble(msg, isOwn)
		order = order + 1
		local text = tostring(msg.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if text == "" then return end
 
		local row = Instance.new("Frame")
		row.Name = "ChatRow"
		row.BackgroundTransparency = 1
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.Size = UDim2.new(1, 0, 0, 0)
		row.LayoutOrder = order
		row.ZIndex = BASE_Z + 1
		row.Parent = msgScroll
 
		local rowScale = Instance.new("UIScale")
		rowScale.Scale = 0.92
		rowScale.Parent = row
 
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.HorizontalAlignment = isOwn and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		rowLayout.Padding = UDim.new(0, 8)
		rowLayout.Parent = row
 
		local isAnon = not msg.UserId or msg.UserId == 0
 
		local avatar = Instance.new("Frame")
		avatar.Name = "Avatar"
 
		avatar.BackgroundColor3 = isAnon and Color3.fromRGB(196, 143, 105) or BobloNEXT.Theme.Accent
		avatar.BackgroundTransparency = 1
		avatar.BorderSizePixel = 0
		avatar.Size = UDim2.fromOffset(AVATAR, AVATAR)
		avatar.LayoutOrder = isOwn and 2 or 1
		avatar.ZIndex = BASE_Z + 2
		avatar.Parent = row
		Corner(avatar, AVATAR / 2)
 
		if isAnon then
			local anonIconImg = Instance.new("ImageLabel")
			anonIconImg.BackgroundTransparency = 1
			anonIconImg.ImageTransparency = 1
			anonIconImg.Image = ResolveIcon("user-round")
			anonIconImg.ImageColor3 = Color3.fromRGB(90, 61, 40)
			anonIconImg.Size = UDim2.fromOffset(15, 15)
			anonIconImg.AnchorPoint = Vector2.new(0.5, 0.5)
			anonIconImg.Position = UDim2.fromScale(0.5, 0.5)
			anonIconImg.ZIndex = BASE_Z + 3
			anonIconImg.Parent = avatar
			Tween(anonIconImg, { ImageTransparency = 0 }, 0.16)
		else
			local avatarImg = Instance.new("ImageLabel")
			avatarImg.BackgroundTransparency = 1
			avatarImg.ImageTransparency = 1
			avatarImg.ScaleType = Enum.ScaleType.Crop
			avatarImg.Size = UDim2.fromScale(1, 1)
			avatarImg.ZIndex = BASE_Z + 3
			avatarImg.Parent = avatar
			Corner(avatarImg, AVATAR / 2)
			Tween(avatarImg, { ImageTransparency = 0 }, 0.16)
			task.spawn(function()
				local ok, content = pcall(
					Players.GetUserThumbnailAsync,
					Players,
					msg.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size100x100
				)
				if ok and content and avatarImg.Parent then
					avatarImg.Image = content
				end
			end)
		end
 
		local H_PAD, V_PAD = 10, 8
		local BUBBLE_MAX_WIDTH = 240
 
		local MIN_BUBBLE_WIDTH = 64
		local naturalW = MeasureText(text, 13, 10000)
		local bubbleWidth = math.min(naturalW, BUBBLE_MAX_WIDTH - H_PAD * 2) + H_PAD * 2
		bubbleWidth = math.max(bubbleWidth, MIN_BUBBLE_WIDTH)
		if msgScroll.AbsoluteSize.X > 0 then
			bubbleWidth = math.min(bubbleWidth, math.max(160, msgScroll.AbsoluteSize.X - 20))
		end
 
		local bubble = Instance.new("Frame")
		bubble.Name = "Bubble"
		bubble.BackgroundColor3 = isOwn and BobloNEXT.Theme.Accent or Color3.new(1, 1, 1)
		bubble.BackgroundTransparency = 1
		bubble.BorderSizePixel = 0
		bubble.ClipsDescendants = true
		bubble.AutomaticSize = Enum.AutomaticSize.Y
		bubble.Size = UDim2.fromOffset(bubbleWidth, 0)
		bubble.LayoutOrder = isOwn and 1 or 2
		bubble.ZIndex = BASE_Z + 2
		bubble.Parent = row
		Corner(bubble, 12)
		local bubbleStroke = Stroke(bubble, Color3.new(1, 1, 1), 1, 1)
 
		local bubblePad = Instance.new("UIPadding")
		bubblePad.PaddingTop = UDim.new(0, V_PAD)
		bubblePad.PaddingBottom = UDim.new(0, V_PAD)
		bubblePad.PaddingLeft = UDim.new(0, H_PAD)
		bubblePad.PaddingRight = UDim.new(0, H_PAD)
		bubblePad.Parent = bubble
 
		local bubbleLayout = Instance.new("UIListLayout")
		bubbleLayout.SortOrder = Enum.SortOrder.LayoutOrder
		bubbleLayout.Parent = bubble
 
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.FontFace = BobloNEXT.Theme.FontRegular
		label.Text = text
		label.TextColor3 = BobloNEXT.Theme.Text
		label.TextTransparency = 1
		label.TextSize = 13
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.LineHeight = 1.3
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.Size = UDim2.new(1, 0, 0, 16)
		label.LayoutOrder = 1
		label.ZIndex = BASE_Z + 3
		label.Parent = bubble
 
		if msg.CreatedAt then
			local timeLbl = Instance.new("TextLabel")
			timeLbl.BackgroundTransparency = 1
			timeLbl.FontFace = BobloNEXT.Theme.FontRegular
			timeLbl.Text = os.date("%H:%M", math.floor(msg.CreatedAt / 1000))
			timeLbl.TextColor3 = isOwn and Color3.new(1, 1, 1) or BobloNEXT.Theme.TextDim
			timeLbl.TextTransparency = isOwn and 0.5 or 0.4
			timeLbl.TextSize = 10
			timeLbl.TextXAlignment = Enum.TextXAlignment.Left
			timeLbl.AutomaticSize = Enum.AutomaticSize.Y
			timeLbl.Size = UDim2.new(1, 0, 0, 12)
			timeLbl.LayoutOrder = 2
			timeLbl.ZIndex = BASE_Z + 3
 
			timeLbl.Visible = showTimestamps
			timeLbl.Parent = bubble
			table.insert(timestampLabels, timeLbl)
		end
 
		if not isOwn and msg.Id and service then
			local reportBtn = Instance.new("TextButton")
			reportBtn.Text = ""
			reportBtn.AutoButtonColor = false
			reportBtn.BackgroundColor3 = Color3.new(1, 1, 1)
			reportBtn.BackgroundTransparency = 1
			reportBtn.BorderSizePixel = 0
			reportBtn.Size = UDim2.fromOffset(20, 20)
			reportBtn.LayoutOrder = 3
			reportBtn.ZIndex = BASE_Z + 2
			reportBtn.Parent = row
			Corner(reportBtn, 6)
 
			local reportIcon = Instance.new("ImageLabel")
			reportIcon.BackgroundTransparency = 1
			reportIcon.ImageTransparency = 1
			reportIcon.Image = ResolveIcon("flag")
			reportIcon.ImageColor3 = BobloNEXT.Theme.TextDim
			reportIcon.Size = UDim2.fromOffset(11, 11)
			reportIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			reportIcon.Position = UDim2.fromScale(0.5, 0.5)
			reportIcon.ZIndex = BASE_Z + 3
			reportIcon.Parent = reportBtn
 
			jan:Add(row.MouseEnter:Connect(function()
				Tween(reportIcon, { ImageTransparency = 0.3 }, 0.12)
			end))
			jan:Add(row.MouseLeave:Connect(function()
				Tween(reportIcon, { ImageTransparency = 1 }, 0.12)
			end))
			jan:Add(reportBtn.MouseEnter:Connect(function()
				Tween(reportBtn, { BackgroundTransparency = 0.88 }, 0.1)
				Tween(reportIcon, { ImageColor3 = BobloNEXT.Theme.Danger, ImageTransparency = 0 }, 0.1)
			end))
			jan:Add(reportBtn.MouseLeave:Connect(function()
				Tween(reportBtn, { BackgroundTransparency = 1 }, 0.1)
				Tween(reportIcon, { ImageColor3 = BobloNEXT.Theme.TextDim }, 0.1)
			end))
			jan:Add(reportBtn.MouseButton1Click:Connect(function()
				BobloNEXT:Confirm({
					Title = "Report this message?",
					Text  = "Hides it for everyone once enough people report it.",
					ConfirmText = "Report",
					CancelText  = "Cancel",
					Danger = true,
					Window = self,
					Callback = function(confirmed)
						if not confirmed then return end
						local ok, err = service:ReportChatMessage(msg.Id)
						BobloNEXT:Notify({
							Title = ok and "Reported" or "Could not report",
							Text  = ok and "Thanks -- our filters will take it from here." or tostring(err),
							Type  = ok and "success" or "error",
							Duration = 3,
						})
					end,
				})
			end))
		end
 
		local avatarFinalTransparency = isOwn and 0.85 or 0.82
		local bubbleFinalTransparency = isOwn and 0.72 or 0.9
		local strokeFinalTransparency = isOwn and 0.8 or 0.9
		Tween(avatar, { BackgroundTransparency = avatarFinalTransparency }, 0.16)
		Tween(bubble, { BackgroundTransparency = bubbleFinalTransparency }, 0.16)
		Tween(bubbleStroke, { Transparency = strokeFinalTransparency }, 0.16)
		Tween(label, { TextTransparency = 0 }, 0.16)
		Tween(rowScale, { Scale = 1 }, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
 
		scrollToBottom()
		table.insert(transcript, (isOwn and "You" or "Someone") .. ": " .. text)
	end
 
	jan:Add(copyBtn.MouseButton1Click:Connect(function()
		local setclipboard = hasFn("setclipboard")
		if not setclipboard or #transcript == 0 then return end
		pcall(setclipboard, table.concat(transcript, "\n"))
		Tween(copyIcon, { ImageColor3 = Color3.fromRGB(120, 220, 140) }, 0.1)
		task.delay(0.4, function()
			if copyIcon.Parent then
				Tween(copyIcon, { ImageColor3 = BobloNEXT.Theme.TextDim }, 0.15)
			end
		end)
	end))
 
	local seenIds = { [0] = true }
	local lastSeenId = 0
 
	local function trySend()
		local text = inputBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if text == "" or not service then return end
		inputBox.Text = ""
		local sendUserId = anonymousMode and 0 or LocalPlayer.UserId
		task.spawn(function()
			local result, err = service:SendChatMessage(sendUserId, text)
			if not result then
				BobloNEXT:Notify({ Title = "Chat", Text = tostring(err), Type = "error", Duration = 3 })
				return
			end
			seenIds[result.Id] = true
			if result.Id > lastSeenId then lastSeenId = result.Id end
			addBubble({ UserId = sendUserId, Text = text, CreatedAt = os.time() * 1000 }, true)
		end)
	end
 
	jan:Add(sendBtn.MouseButton1Click:Connect(trySend))
	jan:Add(inputBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then trySend() end
	end))
	jan:Add(anonBtn.MouseButton1Click:Connect(function()
		anonymousMode = not anonymousMode
		anonIcon.Image = ResolveIcon(anonymousMode and "eye-off" or "eye")
		BobloNEXT:Notify({
			Title = "Chat",
			Text  = anonymousMode
				and "Anonymous mode on -- new messages won't reveal your avatar."
				or "Anonymous mode off -- new messages show your avatar.",
			Type  = "info",
			Duration = 3,
		})
	end))
	jan:Add(clearBtn.MouseButton1Click:Connect(function()
 
		for _, child in ipairs(msgScroll:GetChildren()) do
			if child.Name == "ChatRow" then child:Destroy() end
		end
		table.clear(transcript)
		table.clear(timestampLabels)
	end))
	jan:Add(closeBtn.MouseButton1Click:Connect(function()
		if self._currentTab == tabObj then
			if self._tabs[1] and self._tabs[1] ~= tabObj then self._tabs[1]._select() end
		end
	end))
 
	local settingsPopup
	local function closeSettingsPopup()
		if settingsPopup then
			settingsPopup:Destroy()
			settingsPopup = nil
		end
	end
 
	local function openSettingsPopup()
		if settingsPopup then closeSettingsPopup(); return end
 
		local popup = Instance.new("Frame")
		popup.Name = "ChatSettingsPopup"
		popup.BackgroundColor3 = BobloNEXT.Theme.Surface
		popup.BackgroundTransparency = 0.05
		popup.BorderSizePixel = 0
		popup.AnchorPoint = Vector2.new(1, 0)
		popup.Position = UDim2.new(1, 0, 0, HEADER_H + 4)
		popup.Size = UDim2.new(0, 190, 0, 0)
		popup.AutomaticSize = Enum.AutomaticSize.Y
		popup.ClipsDescendants = true
		popup.ZIndex = BASE_Z + 10
		popup.Parent = panel
		Corner(popup, 10)
		local popupStroke = Stroke(popup, Color3.new(1, 1, 1), 1, 0.88)
 
		local popupPad = Instance.new("UIPadding")
		popupPad.PaddingTop = UDim.new(0, 10)
		popupPad.PaddingBottom = UDim.new(0, 10)
		popupPad.PaddingLeft = UDim.new(0, 12)
		popupPad.PaddingRight = UDim.new(0, 12)
		popupPad.Parent = popup
 
		local popupLayout = Instance.new("UIListLayout")
		popupLayout.Padding = UDim.new(0, 8)
		popupLayout.SortOrder = Enum.SortOrder.LayoutOrder
		popupLayout.Parent = popup
 
		local function toggleRow(order, label, getValue, onToggle)
			local row = Instance.new("Frame")
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, 0, 0, 20)
			row.LayoutOrder = order
			row.ZIndex = BASE_Z + 11
			row.Parent = popup
 
			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.FontFace = BobloNEXT.Theme.FontRegular
			lbl.Text = label
			lbl.TextColor3 = BobloNEXT.Theme.Text
			lbl.TextSize = 12
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.Size = UDim2.new(1, -30, 1, 0)
			lbl.ZIndex = BASE_Z + 12
			lbl.Parent = row
 
			local check = Instance.new("TextButton")
			check.Text = ""
			check.AutoButtonColor = false
			check.BackgroundColor3 = Color3.new(1, 1, 1)
			check.BackgroundTransparency = getValue() and 0.7 or 0.92
			check.BorderSizePixel = 0
			check.AnchorPoint = Vector2.new(1, 0.5)
			check.Position = UDim2.new(1, 0, 0.5, 0)
			check.Size = UDim2.fromOffset(20, 20)
			check.ZIndex = BASE_Z + 12
			check.Parent = row
			Corner(check, 6)
 
			local checkIcon = Instance.new("ImageLabel")
			checkIcon.BackgroundTransparency = 1
			checkIcon.Image = ResolveIcon("check")
			checkIcon.ImageColor3 = BobloNEXT.Theme.Accent
			checkIcon.ImageTransparency = getValue() and 0 or 1
			checkIcon.Size = UDim2.fromOffset(11, 11)
			checkIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			checkIcon.Position = UDim2.fromScale(0.5, 0.5)
			checkIcon.ZIndex = BASE_Z + 13
			checkIcon.Parent = check
 
			jan:Add(check.MouseButton1Click:Connect(function()
				local newValue = onToggle()
				Tween(check, { BackgroundTransparency = newValue and 0.7 or 0.92 }, 0.12)
				Tween(checkIcon, { ImageTransparency = newValue and 0 or 1 }, 0.12)
			end))
		end
 
		toggleRow(1, "Show timestamps", function() return showTimestamps end, function()
			showTimestamps = not showTimestamps
			for _, lbl in ipairs(timestampLabels) do
				if lbl.Parent then lbl.Visible = showTimestamps end
			end
			return showTimestamps
		end)
		toggleRow(2, "Sound on new message", function() return notifySound end, function()
			notifySound = not notifySound
			return notifySound
		end)
		toggleRow(3, "Fast updates (1s)", function() return pollInterval <= 1 end, function()
			pollInterval = (pollInterval <= 1) and (opts.PollInterval or 2.5) or 1
			return pollInterval <= 1
		end)
 
		settingsPopup = popup
	end
 
	jan:Add(settingsBtn.MouseButton1Click:Connect(function()
		if settingsPopup then closeSettingsPopup() else openSettingsPopup() end
	end))
 
	local notifySoundInstance = Instance.new("Sound")
	notifySoundInstance.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	notifySoundInstance.Volume = 0.5
	notifySoundInstance.Parent = panel
 
	if service then
		task.spawn(function()
			local backlog = service:PollChatMessages(0)
			if backlog then
				local historyLimit = opts.HistoryLimit or 3
				local startIdx = math.max(1, #backlog - historyLimit + 1)
				for i = startIdx, #backlog do
					local m = backlog[i]
					if not seenIds[m.Id] then
						seenIds[m.Id] = true
						addBubble(m, m.UserId == LocalPlayer.UserId)
					end
					if m.Id > lastSeenId then lastSeenId = m.Id end
				end
			end
			while panel and panel.Parent do
				task.wait(pollInterval)
				local newMsgs = service:PollChatMessages(lastSeenId)
				if newMsgs then
					for _, m in ipairs(newMsgs) do
						if not seenIds[m.Id] then
							seenIds[m.Id] = true
							local isOwn = m.UserId == LocalPlayer.UserId
							addBubble(m, isOwn)
 
							if notifySound and not isOwn and notifySoundInstance.Parent then
								notifySoundInstance:Play()
							end
						end
						if m.Id > lastSeenId then lastSeenId = m.Id end
					end
				end
			end
		end)
	end
 
	local lastRealTab = nil
	local function openPanel()
		if self._currentTab == tabObj then return end
		if self._currentTab and not self._currentTab.Hidden then
			lastRealTab = self._currentTab
		end
		tabObj._select()
	end
	local function closePanel()
		if self._currentTab ~= tabObj then return end
		if lastRealTab and not lastRealTab.Hidden then
			lastRealTab._select()
		elseif self._tabs[1] and self._tabs[1] ~= tabObj then
			self._tabs[1]._select()
		end
	end
 
	return {
		Instance = panel,
		Tab = tabObj,
		Open = openPanel,
		Close = closePanel,
		Toggle = function()
			if self._currentTab == tabObj then closePanel() else openPanel() end
		end,
		IsOpen = function() return self._currentTab == tabObj end,
		Destroy = function() panel:Destroy() end,
	}
end
 
local TRANSITION_EXIT  = 0.18
local TRANSITION_GAP   = 0.08
local TRANSITION_ENTER = 0.32
 
function Window:AddTab(nameOrOpts)
	local opts = type(nameOrOpts) == "table" and nameOrOpts or { Name = nameOrOpts }
	local name = opts.Name or opts.Title or "Tab"
	local iconAsset = opts.Icon and ResolveIcon(opts.Icon) or nil
	local hasIcon = iconAsset ~= nil and iconAsset ~= ""
	local jan = self._janitor
 
	local hidden = opts.Hidden == true
 
	local tabButton = Instance.new("TextButton")
	tabButton.Name = name
	tabButton.Text = ""
	tabButton.AutoButtonColor = false
	tabButton.BackgroundColor3 = BobloNEXT.Theme.Accent
	tabButton.BackgroundTransparency = 1
	tabButton.BorderSizePixel = 0
	tabButton.Size = UDim2.new(1, 0, 0, 34)
	tabButton.ZIndex = Z.Content
	if not hidden then
		tabButton.Parent = self._tabBar
	end
	Corner(tabButton, 10)
 
	local isPrivate = opts.Password ~= nil and opts.Password ~= ""
	local remembered = isPrivate and IsPrivateTabRemembered(name)
	local unlocked = not isPrivate or remembered
	local glowColor = opts.GlowColor or BobloNEXT.Theme.Accent
	local glowStroke, lockBadge, glowPulse
 
	if isPrivate then
		glowStroke = Stroke(tabButton, glowColor, 1, remembered and 0.9 or 0.82)
 
		if not remembered then
			glowPulse = TweenService:Create(
				glowStroke,
				TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.94 }
			)
			glowPulse:Play()
		end
	end
 
	if isPrivate and not remembered then
		lockBadge = Instance.new("Frame")
		lockBadge.Name = "LockBadge"
		lockBadge.BackgroundColor3 = BobloNEXT.Theme.Background
		lockBadge.BackgroundTransparency = 0
		lockBadge.BorderSizePixel = 0
		lockBadge.Size = UDim2.fromOffset(13, 13)
		lockBadge.AnchorPoint = Vector2.new(1, 0)
		lockBadge.Position = UDim2.new(1, -2, 0, -3)
		lockBadge.ZIndex = Z.Content + 3
		lockBadge.Parent = tabButton
		Corner(lockBadge, 7)
		Stroke(lockBadge, glowColor, 1, 0.7)
 
		local lockIcon = Instance.new("ImageLabel")
		lockIcon.BackgroundTransparency = 1
		lockIcon.Image = ResolveIcon("lock")
		lockIcon.ImageColor3 = glowColor
		lockIcon.Size = UDim2.fromOffset(7, 7)
		lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		lockIcon.Position = UDim2.fromScale(0.5, 0.5)
		lockIcon.ZIndex = Z.Content + 4
		lockIcon.Parent = lockBadge
	end
 
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.ZIndex = Z.Content
	row.Parent = tabButton
 
	local rowPad = Instance.new("UIPadding")
	rowPad.PaddingLeft = UDim.new(0, 12)
	rowPad.PaddingRight = UDim.new(0, 12)
	rowPad.Parent = row
 
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 10)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row
 
	local iconLabel
	if hasIcon then
		iconLabel = Instance.new("ImageLabel")
		iconLabel.Name = "Icon"
		iconLabel.BackgroundTransparency = 1
		iconLabel.Image = iconAsset
		iconLabel.ImageColor3 = BobloNEXT.Theme.TextDim
		iconLabel.Size = UDim2.fromOffset(16, 16)
		iconLabel.LayoutOrder = 1
		iconLabel.ZIndex = Z.Content + 1
		iconLabel.Parent = row
	end
 
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Label"
	textLabel.BackgroundTransparency = 1
	textLabel.FontFace = BobloNEXT.Theme.Font
	textLabel.Text = name
	textLabel.TextColor3 = BobloNEXT.Theme.TextDim
	textLabel.TextSize = 14
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextTruncate = Enum.TextTruncate.AtEnd
	textLabel.Size = UDim2.new(1, hasIcon and -26 or 0, 1, 0)
	textLabel.LayoutOrder = 2
	textLabel.ZIndex = Z.Content + 1
	textLabel.Parent = row
 
	local pageGroup = Instance.new("CanvasGroup")
	pageGroup.Name = name .. "Group"
	pageGroup.BackgroundTransparency = 1
	pageGroup.Size = UDim2.fromScale(1, 1)
	pageGroup.GroupTransparency = 0
	pageGroup.Visible = false
	pageGroup.ZIndex = Z.Content
	pageGroup.Parent = self._content
 
	local page = Instance.new("ScrollingFrame")
	page.Name = name .. "Page"
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Size = UDim2.fromScale(1, 1)
	page.ScrollingDirection = Enum.ScrollingDirection.Y
	page.ScrollBarThickness = 0
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.ZIndex = Z.Content
	page.Parent = pageGroup
 
	local pagePad = Instance.new("UIPadding")
	pagePad.Name = "PagePadding"
	pagePad.PaddingRight = UDim.new(0, 12)
	pagePad.PaddingBottom = UDim.new(0, 6)
	pagePad.Parent = page
 
	local pageLayout = Instance.new("UIListLayout")
	pageLayout.Name = "PageLayout"
	pageLayout.Padding = UDim.new(0, 8)
	pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pageLayout.Parent = page
 
	AddScrollbar(page)
	AddContentScrollThumb(page, pageLayout, pageGroup, jan)
	AddEmptyState(page, pageGroup, jan)
 
	local tabObj = setmetatable({
		Name      = name,
		_page     = page,
		_group    = pageGroup,
		_button   = tabButton,
		_icon     = iconLabel,
		_label    = textLabel,
		_window   = self,
		_janitor  = jan,
		_password = opts.Password,
	}, Tab)
 
	ThemeBind(tabButton, "BackgroundColor3", "Accent")
	ThemeBind(textLabel, "TextColor3", function(theme)
		return self._currentTab == tabObj and theme.Text or theme.TextDim
	end)
	if iconLabel then
		ThemeBind(iconLabel, "ImageColor3", function(theme)
			return self._currentTab == tabObj and theme.Text or theme.TextDim
		end)
	end

	local myIndex = #self._tabs + 1
 
	local function indicatorY()
		return (tabButton.AbsolutePosition.Y - self._tabBar.AbsolutePosition.Y) / GetUIScale()
	end
 
	local function selectTab()
		if self._currentTab == tabObj then return end
 
		self._tabSwitchToken = (self._tabSwitchToken or 0) + 1
		local myToken = self._tabSwitchToken
 
		local direction = 0
		if self._currentIndex then
			direction = (myIndex > self._currentIndex) and 1 or -1
		end
		self._currentIndex = myIndex
 
		local previousTab = self._currentTab
		self._currentTab = tabObj
		for _, fn in ipairs(self._tabChangeListeners) do
			task.spawn(fn, tabObj)
		end
 
		for _, t in pairs(self._tabs) do
			local isSelected = (t == tabObj)
			Tween(t._label, { TextColor3 = isSelected and BobloNEXT.Theme.Text or BobloNEXT.Theme.TextDim }, 0.22)
			if t._icon then
				Tween(t._icon, { ImageColor3 = isSelected and BobloNEXT.Theme.Text or BobloNEXT.Theme.TextDim }, 0.22)
			end
			if not isSelected then
				Tween(t._button, { BackgroundTransparency = 1 }, 0.15)
			end
		end
 
		if hidden then
			Tween(self._tabIndicator, { BackgroundTransparency = 1 }, 0.15)
		else
			Tween(self._tabIndicator, {
				Position = UDim2.new(0, 0, 0, indicatorY()),
				BackgroundTransparency = 0.88,
			}, 0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		end
 
		for _, t in pairs(self._tabs) do
			if t ~= tabObj and t ~= previousTab and t._group.Visible then
				t._group.Visible = false
			end
		end
 
		local function playEnter()
			if self._tabSwitchToken ~= myToken then return end
			pageGroup.Visible = true
			pageGroup.GroupTransparency = 1
			pageGroup.Position = UDim2.fromOffset(direction * 20, 0)
			Tween(pageGroup, {
				GroupTransparency = 0,
				Position = UDim2.fromOffset(0, 0),
			}, TRANSITION_ENTER, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		end
 
		if previousTab and previousTab._group.Visible then
			local g = previousTab._group
			Tween(g, {
				GroupTransparency = 1,
				Position = UDim2.fromOffset(-direction * 20, 0),
			}, TRANSITION_EXIT, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(TRANSITION_EXIT, function()
				if g then g.Visible = false end
				task.delay(TRANSITION_GAP, playEnter)
			end)
		else
			playEnter()
		end
	end
 
	local promptOpen = false
	local function guardedSelect()
		if isPrivate and not unlocked then
			if promptOpen then return end
			promptOpen = true
			self:_PromptTabPassword(tabObj, function(success, remember)
				promptOpen = false
				if not success then return end
				SetPrivateTabRemembered(tabObj.Name, remember == true)
				unlocked = true
				tabObj.Unlocked = true
				if glowPulse then glowPulse:Cancel() end
				if glowStroke then Tween(glowStroke, { Transparency = 0.9 }, 0.4) end
				if lockBadge then
					Tween(lockBadge, { BackgroundTransparency = 1 }, 0.25)
					task.delay(0.25, function()
						if lockBadge then lockBadge:Destroy(); lockBadge = nil end
					end)
				end
				selectTab()
			end)
			return
		end
		selectTab()
	end
 
	tabObj._select = guardedSelect
	tabObj.IsPrivate = isPrivate
	tabObj.Unlocked = unlocked
	tabObj.Hidden = hidden
 
	if not hidden then
		jan:Add(tabButton:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
			if self._currentTab == tabObj then
				self._tabIndicator.Position = UDim2.new(0, 0, 0, indicatorY())
			end
		end))
 
		jan:Add(tabButton.MouseButton1Click:Connect(guardedSelect))
 
		jan:Add(tabButton.MouseEnter:Connect(function()
			if self._currentTab ~= tabObj then
				Tween(tabButton, { BackgroundTransparency = 0.95 }, 0.15)
			end
		end))
		jan:Add(tabButton.MouseLeave:Connect(function()
			if self._currentTab ~= tabObj then
				Tween(tabButton, { BackgroundTransparency = 1 }, 0.15)
			end
		end))
	end
 
	table.insert(self._tabs, tabObj)
	if not hidden then
 
		self._visibleTabCount = (self._visibleTabCount or 0) + 1
		if self._visibleTabCount == 1 then
			guardedSelect()
		end
		if self._defaultTabName and name == self._defaultTabName then
			guardedSelect()
		end
	end
 
	return tabObj
end
 
function Window:AddPrivateTab(opts)
	opts = type(opts) == "table" and opts or { Name = opts }
	assert(opts.Password and opts.Password ~= "", "AddPrivateTab requires opts.Password")
	return self:AddTab(opts)
end
 
function Window:_PromptTabPassword(tabObj, callback)
	local root = BobloNEXT._Root
	local jan = Janitor.new()
	local closed = false
	local settled = false
 
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "TabPasswordBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = Z.Modal
	backdrop.Parent = root
 
	local dialog = Instance.new("Frame")
	dialog.Name = "TabPasswordDialog"
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	do
		local cx, cy = ComputeDialogCenter(self._gui)
		local s = GetUIScale()
		dialog.Position = UDim2.fromOffset(math.round(cx / s), math.round(cy / s))
	end
	dialog.BackgroundColor3 = BobloNEXT.Theme.Background
	dialog.BackgroundTransparency = 1
	dialog.BorderSizePixel = 0
	dialog.ClipsDescendants = true
	dialog.AutomaticSize = Enum.AutomaticSize.Y
	dialog.Size = UDim2.new(0, 300, 0, 0)
	dialog.ZIndex = Z.ModalTop
	dialog.Parent = backdrop
	Corner(dialog, 14)
	local dialogStroke = Stroke(dialog, Color3.new(1, 1, 1), 1, 0.9)
 
	local scale = Instance.new("UIScale")
	scale.Scale = 0.94
	scale.Parent = dialog
 
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 18)
	pad.PaddingBottom = UDim.new(0, 18)
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = dialog
 
	local dialogLayout = Instance.new("UIListLayout")
	dialogLayout.Padding = UDim.new(0, 8)
	dialogLayout.SortOrder = Enum.SortOrder.LayoutOrder
	dialogLayout.Parent = dialog
 
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 20)
	header.LayoutOrder = 1
	header.ZIndex = Z.ModalTop + 1
	header.Parent = dialog
 
	local lockIcon = Instance.new("ImageLabel")
	lockIcon.BackgroundTransparency = 1
	lockIcon.Image = ResolveIcon("lock")
	lockIcon.ImageColor3 = BobloNEXT.Theme.TextDim
	lockIcon.Size = UDim2.fromOffset(18, 18)
	lockIcon.Position = UDim2.fromOffset(0, 0)
	lockIcon.ZIndex = Z.ModalTop + 2
	lockIcon.Parent = header
 
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.FontFace = BobloNEXT.Theme.Font
	title.Text = "Private Tab"
	title.TextColor3 = BobloNEXT.Theme.Text
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(1, -26, 1, 0)
	title.Position = UDim2.fromOffset(26, 0)
	title.ZIndex = Z.ModalTop + 2
	title.Parent = header
 
	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.FontFace = BobloNEXT.Theme.FontRegular
	subtitle.Text = ("Enter the password to unlock \"%s\""):format(tabObj.Name or "")
	subtitle.TextColor3 = BobloNEXT.Theme.TextDim
	subtitle.TextSize = 12
	subtitle.TextWrapped = true
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextYAlignment = Enum.TextYAlignment.Top
	subtitle.AutomaticSize = Enum.AutomaticSize.Y
	subtitle.Size = UDim2.new(1, 0, 0, 0)
	subtitle.LayoutOrder = 2
	subtitle.ZIndex = Z.ModalTop + 1
	subtitle.Parent = dialog
 
	local fieldHolder = Instance.new("Frame")
	fieldHolder.BackgroundColor3 = Color3.new(1, 1, 1)
	fieldHolder.BackgroundTransparency = 0.94
	fieldHolder.BorderSizePixel = 0
	fieldHolder.ClipsDescendants = true
	fieldHolder.Size = UDim2.new(1, 0, 0, 36)
	fieldHolder.LayoutOrder = 3
	fieldHolder.ZIndex = Z.ModalTop + 1
	fieldHolder.Parent = dialog
	Corner(fieldHolder, 8)
	local fieldStroke = Stroke(fieldHolder, Color3.new(1, 1, 1), 1, 0.88)
 
	local box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.FontFace = BobloNEXT.Theme.FontRegular
	box.PlaceholderText = ""
	box.Text = ""
	box.TextColor3 = BobloNEXT.Theme.Text
	box.TextTransparency = 1
	box.TextSize = 14
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Position = UDim2.fromOffset(10, 0)
	box.Size = UDim2.new(1, -20, 1, 0)
	box.ZIndex = Z.ModalTop + 2
	box.Parent = fieldHolder
 
	local maskLabel = Instance.new("TextLabel")
	maskLabel.BackgroundTransparency = 1
	maskLabel.FontFace = BobloNEXT.Theme.FontRegular
	maskLabel.Text = ""
	maskLabel.TextColor3 = BobloNEXT.Theme.Text
	maskLabel.TextSize = 14
	maskLabel.TextXAlignment = Enum.TextXAlignment.Left
	maskLabel.Position = box.Position
	maskLabel.Size = box.Size
	maskLabel.ZIndex = box.ZIndex + 1
	maskLabel.Parent = fieldHolder
 
	local placeholderLabel = Instance.new("TextLabel")
	placeholderLabel.BackgroundTransparency = 1
	placeholderLabel.FontFace = BobloNEXT.Theme.FontRegular
	placeholderLabel.Text = "Password"
	placeholderLabel.TextColor3 = BobloNEXT.Theme.TextDim
	placeholderLabel.TextSize = 14
	placeholderLabel.TextXAlignment = Enum.TextXAlignment.Left
	placeholderLabel.Position = box.Position
	placeholderLabel.Size = box.Size
	placeholderLabel.ZIndex = box.ZIndex + 1
	placeholderLabel.Parent = fieldHolder
 
	jan:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
		maskLabel.Text = string.rep("\226\128\162", #box.Text)
		placeholderLabel.Visible = (#box.Text == 0)
	end))
 
	local rememberRow = Instance.new("Frame")
	rememberRow.BackgroundTransparency = 1
	rememberRow.Size = UDim2.new(1, 0, 0, 18)
	rememberRow.LayoutOrder = 4
	rememberRow.ZIndex = Z.ModalTop + 1
	rememberRow.Parent = dialog
 
	local remember = IsPrivateTabRemembered(tabObj.Name)
 
	local rememberSwitch = Instance.new("Frame")
	rememberSwitch.AnchorPoint = Vector2.new(0, 0.5)
	rememberSwitch.Position = UDim2.new(0, 0, 0.5, 0)
	rememberSwitch.Size = UDim2.fromOffset(32, 18)
	rememberSwitch.BackgroundColor3 = remember and Color3.new(1, 1, 1) or Color3.fromRGB(60, 60, 60)
	rememberSwitch.BorderSizePixel = 0
	rememberSwitch.ZIndex = Z.ModalTop + 2
	rememberSwitch.Parent = rememberRow
	Corner(rememberSwitch, 9)
 
	local rememberLabel = Instance.new("TextLabel")
	rememberLabel.BackgroundTransparency = 1
	rememberLabel.FontFace = BobloNEXT.Theme.FontRegular
	rememberLabel.Text = "Remember me"
	rememberLabel.TextColor3 = BobloNEXT.Theme.TextDim
	rememberLabel.TextSize = 12
	rememberLabel.TextXAlignment = Enum.TextXAlignment.Left
	rememberLabel.AnchorPoint = Vector2.new(0, 0.5)
	rememberLabel.Position = UDim2.new(0, 42, 0.5, 0)
	rememberLabel.Size = UDim2.new(1, -42, 1, 0)
	rememberLabel.ZIndex = Z.ModalTop + 2
	rememberLabel.Parent = rememberRow
 
	local rememberKnob = Instance.new("Frame")
	rememberKnob.Size = UDim2.fromOffset(14, 14)
	rememberKnob.AnchorPoint = Vector2.new(0, 0.5)
	rememberKnob.Position = remember and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
	rememberKnob.BackgroundColor3 = remember and Color3.fromRGB(18, 18, 18) or Color3.new(1, 1, 1)
	rememberKnob.BorderSizePixel = 0
	rememberKnob.ZIndex = Z.ModalTop + 3
	rememberKnob.Parent = rememberSwitch
	Corner(rememberKnob, 7)
 
	local rememberClick = Instance.new("TextButton")
	rememberClick.Text = ""
	rememberClick.AutoButtonColor = false
	rememberClick.BackgroundTransparency = 1
	rememberClick.Size = UDim2.fromScale(1, 1)
	rememberClick.ZIndex = Z.ModalTop + 3
	rememberClick.Parent = rememberRow
 
	jan:Add(rememberClick.MouseButton1Click:Connect(function()
		remember = not remember
		Tween(rememberSwitch, {
			BackgroundColor3 = remember and Color3.new(1, 1, 1) or Color3.fromRGB(60, 60, 60),
		}, 0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
		Tween(rememberKnob, {
			BackgroundColor3 = remember and Color3.fromRGB(18, 18, 18) or Color3.new(1, 1, 1),
			Position = remember and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
		}, 0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
	end))
 
	local buttonsRow = Instance.new("Frame")
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.Size = UDim2.new(1, 0, 0, 34)
	buttonsRow.LayoutOrder = 5
	buttonsRow.ZIndex = Z.ModalTop + 1
	buttonsRow.Parent = dialog
 
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = buttonsRow
 
	local function makeButton(text_, order, filled)
		local btn = Instance.new("TextButton")
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = Color3.new(1, 1, 1)
		btn.BackgroundTransparency = filled and 0.82 or 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(0.5, -4, 1, 0)
		btn.LayoutOrder = order
		btn.ZIndex = Z.ModalTop + 1
		btn.Parent = buttonsRow
		Corner(btn, 10)
		local btnStroke = Stroke(btn, Color3.new(1, 1, 1), 1, filled and 0.7 or 0.85)
 
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.FontFace = BobloNEXT.Theme.Font
		lbl.Text = text_
		lbl.TextColor3 = BobloNEXT.Theme.Text
		lbl.TextSize = 13
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.ZIndex = Z.ModalTop + 2
		lbl.Parent = btn
 
		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = math.max((filled and 0.82 or 1) - 0.1, 0) }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = filled and 0.82 or 1 }, 0.12)
		end))
 
		return btn
	end
 
	local cancelBtn  = makeButton("Cancel", 1, false)
	local unlockBtn  = makeButton("Unlock", 2, true)
 
	local function close(success)
		if closed then return end
		closed = true
 
		Tween(scale, { Scale = 0.94 }, 0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		Tween(dialog, { BackgroundTransparency = 1 }, 0.15)
		Tween(dialogStroke, { Transparency = 1 }, 0.15)
		Tween(backdrop, { BackgroundTransparency = 1 }, 0.15)
		task.delay(0.16, function()
			jan:Destroy()
			backdrop:Destroy()
		end)
 
		task.spawn(callback, success, remember)
	end
 
	local function shakeError()
		Tween(fieldStroke, { Color = BobloNEXT.Theme.Danger, Transparency = 0.4 }, 0.12)
		placeholderLabel.Text = "Incorrect password"
		Tween(placeholderLabel, { TextColor3 = BobloNEXT.Theme.Danger }, 0.12)
 
		local baseX = dialog.Position.X.Offset
		local seq = { 8, -7, 5, -4, 0 }
		local t = 0
		for _, dx in ipairs(seq) do
			t = t + 0.05
			task.delay(t, function()
				if closed then return end
				Tween(dialog, {
					Position = UDim2.fromOffset(baseX + dx, dialog.Position.Y.Offset),
				}, 0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			end)
		end
 
		task.delay(1.4, function()
			if closed then return end
			Tween(fieldStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.88 }, 0.3)
			Tween(placeholderLabel, { TextColor3 = BobloNEXT.Theme.TextDim }, 0.3)
			task.delay(0.3, function()
				if not closed then placeholderLabel.Text = "Password" end
			end)
		end)
	end
 
	local function attempt()
		if closed or settled then return end
		if box.Text == tabObj._password then
			settled = true
			close(true)
		else
			shakeError()
			box.Text = ""
		end
	end
 
	jan:Add(cancelBtn.MouseButton1Click:Connect(function() close(false) end))
	jan:Add(unlockBtn.MouseButton1Click:Connect(attempt))
	jan:Add(backdrop.MouseButton1Click:Connect(function() close(false) end))
 
	jan:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if closed then return end
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			attempt()
		elseif input.KeyCode == Enum.KeyCode.Escape and not gameProcessed then
			close(false)
		end
	end))
 
	Tween(backdrop, { BackgroundTransparency = 0.5 }, 0.18)
	Tween(dialog, { BackgroundTransparency = 0 }, 0.18)
	Tween(dialogStroke, { Transparency = 0.8 }, 0.18)
	Tween(scale, { Scale = 1 }, 0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
 
	task.defer(function()
		if box.Parent then box:CaptureFocus() end
	end)
end
 
function Window:SelectTab(nameOrIndex)
	if type(nameOrIndex) == "number" then
		local t = self._tabs[nameOrIndex]
		if t then t._select() end
		return t
	end
	for _, t in ipairs(self._tabs) do
		if t.Name == nameOrIndex then
			t._select()
			return t
		end
	end
	return nil
end
 
function Window:_RegisterSearchable(tabObj, title, instance)
	if not title or title == "" or not instance then return end
	table.insert(self._searchIndex, { title = title, instance = instance, tabObj = tabObj })
end
 
local function SearchEntryPath(tabObj)
	if not tabObj then return "" end
	if tabObj._parentTabName then
		return tabObj._parentTabName .. " \226\128\186 " .. tabObj.Name
	end
	return tabObj.Name or ""
end
 
function Window:_JumpToSearchable(entry)
	local tabObj = entry.tabObj
	local inst = entry.instance
	if not tabObj or not inst or not inst.Parent then return end
 
	if tabObj._parentTab then
		tabObj._parentTab._select()
		tabObj._parentTab:SelectSubTab(tabObj._subTabIdx)
	elseif tabObj._select then
		tabObj._select()
	end
 
	task.delay(0.6, function()
		if not inst.Parent then return end
		local page = tabObj._page
		if not page then return end
		local targetY = math.max(
			0,
			(inst.AbsolutePosition.Y - page.AbsolutePosition.Y) + page.CanvasPosition.Y - 40
		)
		page.CanvasPosition = Vector2.new(page.CanvasPosition.X, targetY)
 
		local baseColor = inst.BackgroundColor3
		local baseBg = inst.BackgroundTransparency
 
		inst.BackgroundColor3 = BobloNEXT.Theme.Accent
		Tween(inst, { BackgroundTransparency = 0.85 }, 0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
 
		task.delay(0.5, function()
			if not inst.Parent then return end
			Tween(inst, { BackgroundTransparency = baseBg }, 0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
			task.delay(0.7, function()
				if inst.Parent then inst.BackgroundColor3 = baseColor end
			end)
		end)
	end)
end
 
function Window:JumpToElement(query)
	query = tostring(query or "")
	if query == "" then return false, "No element name given" end
 
	local q = query:lower()
	local best, bestScore = nil, 0
	for _, entry in ipairs(self._searchIndex) do
		local title = tostring(entry.title or ""):lower()
		if title == q then
			best, bestScore = entry, math.huge
			break
		elseif title:find(q, 1, true) then
			local score = 1000 - math.abs(#title - #q)
			if score > bestScore then best, bestScore = entry, score end
		end
	end
 
	if not best then
		return false, "No element found matching '" .. query .. "'"
	end
 
	self:_JumpToSearchable(best)
	return true, best.title
end
 
function Window:_OpenSearch()
	local self_ = self
	local root = BobloNEXT._Root
	local panelW = math.min(440, ViewportSize().X / GetUIScale() - 40)
	local HEADER_H = 50
	local MAX_RESULTS_H = 280
	local ROW_H = 40
 
	local open = true
	local backdrop, panel, scale
	local heartbeatConn, textConn, focusConn
	local lastMatches = {}
 
	local restY
 
	local function closeSearch()
		if not open then return end
		open = false
		RegisterPopupClose(closeSearch)
		if heartbeatConn then heartbeatConn:Disconnect(); heartbeatConn = nil end
		if textConn then textConn:Disconnect(); textConn = nil end
		if focusConn then focusConn:Disconnect(); focusConn = nil end
 
		local b, p = backdrop, panel
		backdrop, panel = nil, nil
		if p then
			Tween(p, { Size = UDim2.new(p.Size.X.Scale, p.Size.X.Offset, 0, 0) }, 0.32,
				Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			Tween(p, { GroupTransparency = 1 }, 0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		end
		if b then Tween(b, { BackgroundTransparency = 1 }, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.In) end
		task.delay(0.32, function()
			if b then b:Destroy() end
			if p then p:Destroy() end
		end)
	end
 
	RegisterPopupOpen(closeSearch)
	backdrop = MakePopupBackdrop(closeSearch)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	Tween(backdrop, { BackgroundTransparency = 0.4 }, 0.36, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
 
	panel = Instance.new("CanvasGroup")
	panel.Name = "SearchPalette"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	do
		local cx, cy = ComputeDialogCenter(self_._gui)
		local s = GetUIScale()
		local px, py = math.round(cx / s), math.round(cy / s)
		restY = py
		panel.Position = UDim2.fromOffset(px, py - 18)
	end
	panel.Size = UDim2.new(0, panelW, 0, HEADER_H)
	panel.BackgroundColor3 = BobloNEXT.Theme.Background
	panel.BackgroundTransparency = 0.05
	panel.GroupTransparency = 1
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	panel.ZIndex = Z.Modal
	panel.Parent = root
	Corner(panel, 14)
	Stroke(panel, Color3.new(1, 1, 1), 1, 0.8)
	GlassLayer(panel, 14, 0.985)
 
	scale = Instance.new("UIScale")
	scale.Scale = 0.94
	scale.Parent = panel
 
	local searchIcon = Instance.new("ImageLabel")
	searchIcon.BackgroundTransparency = 1
	searchIcon.Image = ResolveIcon("search")
	searchIcon.ImageColor3 = BobloNEXT.Theme.TextDim
	searchIcon.Size = UDim2.fromOffset(16, 16)
	searchIcon.AnchorPoint = Vector2.new(0, 0.5)
	searchIcon.Position = UDim2.new(0, 16, 0, HEADER_H / 2)
	searchIcon.ZIndex = Z.Modal + 2
	searchIcon.Parent = panel
 
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Text = ""
	closeBtn.AutoButtonColor = false
	closeBtn.BackgroundColor3 = Color3.new(1, 1, 1)
	closeBtn.BackgroundTransparency = 1
	closeBtn.BorderSizePixel = 0
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Size = UDim2.fromOffset(24, 24)
	closeBtn.Position = UDim2.new(1, -10, 0, HEADER_H / 2)
	closeBtn.ZIndex = Z.Modal + 2
	closeBtn.Parent = panel
	Corner(closeBtn, 7)
 
	local closeIcon = Instance.new("ImageLabel")
	closeIcon.BackgroundTransparency = 1
	closeIcon.Image = ResolveIcon("x")
	closeIcon.ImageColor3 = BobloNEXT.Theme.TextDim
	closeIcon.Size = UDim2.fromOffset(12, 12)
	closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	closeIcon.Position = UDim2.fromScale(0.5, 0.5)
	closeIcon.ZIndex = Z.Modal + 3
	closeIcon.Parent = closeBtn
 
	closeBtn.MouseEnter:Connect(function()
		Tween(closeBtn, { BackgroundTransparency = 0.9 }, 0.12)
		Tween(closeIcon, { ImageColor3 = BobloNEXT.Theme.Text }, 0.12)
	end)
	closeBtn.MouseLeave:Connect(function()
		Tween(closeBtn, { BackgroundTransparency = 1 }, 0.12)
		Tween(closeIcon, { ImageColor3 = BobloNEXT.Theme.TextDim }, 0.12)
	end)
	closeBtn.MouseButton1Click:Connect(closeSearch)
 
	local box = Instance.new("TextBox")
	box.Name = "SearchBox"
	box.BackgroundTransparency = 1
	box.FontFace = BobloNEXT.Theme.FontRegular
	box.PlaceholderText = "Search everything..."
	box.Text = ""
	box.TextColor3 = BobloNEXT.Theme.Text
	box.PlaceholderColor3 = BobloNEXT.Theme.TextDim
	box.TextSize = 15
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Position = UDim2.new(0, 40, 0, 0)
	box.Size = UDim2.new(1, -78, 0, HEADER_H)
	box.ZIndex = Z.Modal + 2
	box.Parent = panel
 
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.BackgroundColor3 = Color3.new(1, 1, 1)
	divider.BackgroundTransparency = 0.92
	divider.BorderSizePixel = 0
	divider.Position = UDim2.new(0, 0, 0, HEADER_H)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.Visible = false
	divider.ZIndex = Z.Modal + 1
	divider.Parent = panel
 
	local resultsHolder = Instance.new("ScrollingFrame")
	resultsHolder.Name = "Results"
	resultsHolder.BackgroundTransparency = 1
	resultsHolder.BorderSizePixel = 0
	resultsHolder.Position = UDim2.new(0, 0, 0, HEADER_H + 1)
	resultsHolder.Size = UDim2.new(1, 0, 0, 0)
	resultsHolder.Visible = false
	resultsHolder.ScrollingDirection = Enum.ScrollingDirection.Y
	resultsHolder.ScrollBarThickness = 0
	resultsHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
	resultsHolder.CanvasSize = UDim2.new(0, 0, 0, 0)
	resultsHolder.ZIndex = Z.Modal + 1
	resultsHolder.Parent = panel
 
	local resultsPad = Instance.new("UIPadding")
	resultsPad.PaddingTop = UDim.new(0, 6)
	resultsPad.PaddingBottom = UDim.new(0, 6)
	resultsPad.PaddingLeft = UDim.new(0, 6)
	resultsPad.PaddingRight = UDim.new(0, 16)
	resultsPad.Parent = resultsHolder
 
	local resultsLayout = Instance.new("UIListLayout")
	resultsLayout.Padding = UDim.new(0, 2)
	resultsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	resultsLayout.Parent = resultsHolder
 
	AddScrollbar(resultsHolder)
	AddContentScrollThumb(resultsHolder, resultsLayout, panel, {
		Add = function(_, conn) heartbeatConn = conn end,
	})
 
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.FontFace = BobloNEXT.Theme.FontRegular
	emptyLabel.Text = "No results"
	emptyLabel.TextColor3 = BobloNEXT.Theme.TextDim
	emptyLabel.TextSize = 13
	emptyLabel.Visible = false
	emptyLabel.Position = UDim2.new(0, 0, 0, HEADER_H + 9)
	emptyLabel.Size = UDim2.new(1, 0, 0, 26)
	emptyLabel.ZIndex = Z.Modal + 1
	emptyLabel.Parent = panel
 
	local function activate(entry)
		closeSearch()
		self_:_JumpToSearchable(entry)
	end
 
	local function rebuild(query)
		for _, child in ipairs(resultsHolder:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
 
		local q = query:lower():match("^%s*(.-)%s*$")
		local matches = {}
		for _, entry in ipairs(self_._searchIndex) do
			if entry.instance and entry.instance.Parent then
				if q == "" or entry.title:lower():find(q, 1, true) then
					table.insert(matches, entry)
					if #matches >= 15 then break end
				end
			end
		end
		lastMatches = matches
 
		local showEmpty = (#matches == 0 and q ~= "")
		emptyLabel.Visible = showEmpty
		resultsHolder.Visible = (#matches > 0)
		divider.Visible = (#matches > 0) or showEmpty
 
		for i, entry in ipairs(matches) do
			local row = Instance.new("TextButton")
			row.Text = ""
			row.AutoButtonColor = false
			row.BackgroundColor3 = Color3.new(1, 1, 1)
			row.BackgroundTransparency = 1
			row.BorderSizePixel = 0
			row.Size = UDim2.new(1, 0, 0, ROW_H)
			row.LayoutOrder = i
			row.ZIndex = Z.Modal + 2
			row.Parent = resultsHolder
			Corner(row, 8)
 
			local titleLbl = Instance.new("TextLabel")
			titleLbl.BackgroundTransparency = 1
			titleLbl.FontFace = BobloNEXT.Theme.Font
			titleLbl.Text = entry.title
			titleLbl.TextColor3 = BobloNEXT.Theme.Text
			titleLbl.TextSize = 13
			titleLbl.TextXAlignment = Enum.TextXAlignment.Left
			titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
			titleLbl.Position = UDim2.fromOffset(12, 5)
			titleLbl.Size = UDim2.new(1, -24, 0, 16)
			titleLbl.ZIndex = Z.Modal + 3
			titleLbl.Parent = row
 
			local pathLbl = Instance.new("TextLabel")
			pathLbl.BackgroundTransparency = 1
			pathLbl.FontFace = BobloNEXT.Theme.FontRegular
			pathLbl.Text = SearchEntryPath(entry.tabObj)
			pathLbl.TextColor3 = BobloNEXT.Theme.TextDim
			pathLbl.TextSize = 11
			pathLbl.TextXAlignment = Enum.TextXAlignment.Left
			pathLbl.TextTruncate = Enum.TextTruncate.AtEnd
			pathLbl.Position = UDim2.fromOffset(12, 21)
			pathLbl.Size = UDim2.new(1, -24, 0, 12)
			pathLbl.ZIndex = Z.Modal + 3
			pathLbl.Parent = row
 
			row.MouseEnter:Connect(function()
				Tween(row, { BackgroundTransparency = 0.92 }, 0.1)
			end)
			row.MouseLeave:Connect(function()
				Tween(row, { BackgroundTransparency = 1 }, 0.1)
			end)
			row.MouseButton1Click:Connect(function()
				activate(entry)
			end)
		end
 
		local resultsH = math.min(#matches * (ROW_H + 2), MAX_RESULTS_H)
 
		local extraH = 0
		if resultsH > 0 then
			extraH = resultsH + 1
		elseif showEmpty then
			extraH = 36
		end
 
		Tween(resultsHolder, { Size = UDim2.new(1, 0, 0, resultsH) }, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
		Tween(panel, { Size = UDim2.new(0, panelW, 0, HEADER_H + extraH) }, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
	end
 
	local rebuildToken = 0
	textConn = box:GetPropertyChangedSignal("Text"):Connect(function()
		rebuildToken = rebuildToken + 1
		local myToken = rebuildToken
		local text = box.Text
		task.delay(0.12, function()
			if rebuildToken == myToken and box.Parent then
				rebuild(text)
			end
		end)
	end)
 
	focusConn = box.FocusLost:Connect(function(enterPressed)
		if enterPressed and lastMatches[1] then
			activate(lastMatches[1])
		end
	end)
 
	rebuild("")
 
	scale.Scale = 0.94
	Tween(panel, {
		GroupTransparency = 0,
		Position = UDim2.fromOffset(panel.Position.X.Offset, restY),
	}, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	Tween(scale, { Scale = 1 }, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
 
	task.defer(function()
		if box.Parent then box:CaptureFocus() end
	end)
end
 
local SUBTAB_EXIT  = 0.18
local SUBTAB_GAP   = 0.08
local SUBTAB_ENTER = 0.30
 
function Tab:AddSubTab(nameOrOpts)
	local opts = type(nameOrOpts) == "table" and nameOrOpts or { Name = nameOrOpts }
	local title = opts.Name or "SubTab"
	local iconAsset = opts.Icon and ResolveIcon(opts.Icon) or nil
	local jan = self._janitor
 
	self._subTabCount = (self._subTabCount or 0) + 1
	local idx = self._subTabCount
 
	if not self._subTabHolder then
		local page = self._page
		page.ScrollingEnabled = false
		page.AutomaticCanvasSize = Enum.AutomaticSize.None
		page.CanvasSize = UDim2.new(0, 0, 0, 0)
 
		local pl = page:FindFirstChildOfClass("UIListLayout")
		if pl then pl:Destroy() end
		local pp = page:FindFirstChildOfClass("UIPadding")
		if pp then pp:Destroy() end
		local oldTrack = page:FindFirstChild("ScrollTrack")
		if oldTrack then oldTrack:Destroy() end
 
		self._subTabHolder = Instance.new("ScrollingFrame")
		self._subTabHolder.Name = "SubTabBar"
		self._subTabHolder.Size = UDim2.new(1, -12, 0, 40)
		self._subTabHolder.Position = UDim2.fromOffset(2, 6)
		self._subTabHolder.BackgroundTransparency = 1
		self._subTabHolder.BorderSizePixel = 0
		self._subTabHolder.ScrollingDirection = Enum.ScrollingDirection.X
		self._subTabHolder.ScrollBarThickness = 0
		self._subTabHolder.AutomaticCanvasSize = Enum.AutomaticSize.X
		self._subTabHolder.CanvasSize = UDim2.new(0, 0, 0, 40)
		self._subTabHolder.ZIndex = Z.Content
		self._subTabHolder.Parent = page
		AddScrollbar(self._subTabHolder)
 
		self._subTabIndicatorLayer = Instance.new("Frame")
		self._subTabIndicatorLayer.Name = "SubTabIndicatorLayer"
		self._subTabIndicatorLayer.BackgroundTransparency = 1
		self._subTabIndicatorLayer.ClipsDescendants = true
		self._subTabIndicatorLayer.ZIndex = Z.Window
		self._subTabIndicatorLayer.Position = self._subTabHolder.Position
		self._subTabIndicatorLayer.Size = self._subTabHolder.Size
		self._subTabIndicatorLayer.Parent = page
 
		self._subTabIndicator = Instance.new("Frame")
		self._subTabIndicator.Name = "Indicator"
		self._subTabIndicator.BackgroundColor3 = Color3.new(1, 1, 1)
		self._subTabIndicator.BackgroundTransparency = 1
		self._subTabIndicator.BorderSizePixel = 0
		self._subTabIndicator.ZIndex = Z.Window
		self._subTabIndicator.Size = UDim2.fromOffset(0, 32)
		self._subTabIndicator.Position = UDim2.fromOffset(0, 4)
		self._subTabIndicator.Parent = self._subTabIndicatorLayer
		Corner(self._subTabIndicator, 8)
 
		local sl = Instance.new("UIListLayout")
		sl.FillDirection = Enum.FillDirection.Horizontal
		sl.VerticalAlignment = Enum.VerticalAlignment.Center
		sl.Padding = UDim.new(0, 6)
		sl.SortOrder = Enum.SortOrder.LayoutOrder
		sl.Parent = self._subTabHolder
 
		self._subTabBody = Instance.new("Frame")
		self._subTabBody.Name = "SubTabBody"
		self._subTabBody.Size = UDim2.new(1, -4, 1, -62)
		self._subTabBody.Position = UDim2.fromOffset(2, 56)
		self._subTabBody.BackgroundTransparency = 1
		self._subTabBody.BorderSizePixel = 0
		self._subTabBody.ClipsDescendants = true
		self._subTabBody.ZIndex = Z.Content
		self._subTabBody.Parent = page
 
		self._subTabScrollTrack = Instance.new("Frame")
		self._subTabScrollTrack.Name = "SubTabScrollTrack"
		self._subTabScrollTrack.BackgroundColor3 = BobloNEXT.Theme.TextDim
		self._subTabScrollTrack.BackgroundTransparency = 0.85
		self._subTabScrollTrack.BorderSizePixel = 0
		self._subTabScrollTrack.Position = UDim2.new(0, 2, 0, 48)
		self._subTabScrollTrack.Size = UDim2.new(1, -12, 0, 3)
		self._subTabScrollTrack.Visible = false
		self._subTabScrollTrack.ZIndex = Z.Content
		self._subTabScrollTrack.Parent = page
		Corner(self._subTabScrollTrack, 2)
 
		self._subTabScrollThumb = Instance.new("Frame")
		self._subTabScrollThumb.Name = "Thumb"
		self._subTabScrollThumb.BackgroundColor3 = BobloNEXT.Theme.TextDim
		self._subTabScrollThumb.BackgroundTransparency = 0.35
		self._subTabScrollThumb.BorderSizePixel = 0
		self._subTabScrollThumb.Size = UDim2.new(0, 40, 1, 0)
		self._subTabScrollThumb.ZIndex = Z.Content + 1
		self._subTabScrollThumb.Parent = self._subTabScrollTrack
		Corner(self._subTabScrollThumb, 2)
 
		function self._updateSubTabScrollbar()
			local holder = self._subTabHolder
			local track = self._subTabScrollTrack
			if not holder or not track then return end
			if not self._group or not self._group.Visible then
				track.Visible = false
				return
			end
			local windowW = holder.AbsoluteWindowSize.X
			local canvasW = holder.AbsoluteCanvasSize.X
			local overflow = canvasW - windowW
			if overflow <= 1 or windowW <= 0 then
				track.Visible = false
				return
			end
			track.Visible = true
			local trackW = track.AbsoluteSize.X
			if trackW <= 0 then return end
			local thumbW = math.min(trackW, math.max(30, trackW * (windowW / canvasW)))
			local maxThumbX = trackW - thumbW
			local ratio = math.clamp(holder.CanvasPosition.X / overflow, 0, 1)
			self._subTabScrollThumb.Size = UDim2.new(thumbW / trackW, 0, 1, 0)
			self._subTabScrollThumb.Position = UDim2.new((maxThumbX / trackW) * ratio, 0, 0, 0)
		end
 
		jan:Add(RunService.Heartbeat:Connect(self._updateSubTabScrollbar))
 
		self._subTabs = {}
 
		function self._syncSubIndicator(animated)
			local sel = self._subTabs and self._subTabs[self.SelectedSubTab]
			if not sel or not sel.Button.Parent then return end
			local holder = self._subTabHolder
			local s = GetUIScale()
			local relX = (sel.Button.AbsolutePosition.X - holder.AbsolutePosition.X) / s
			local w = sel.Button.AbsoluteSize.X / s
			if w <= 0 then return end
			local goal = {
				Position = UDim2.fromOffset(math.round(relX), 4),
				Size = UDim2.fromOffset(math.round(w), 32),
				BackgroundTransparency = 0.86,
			}
			if animated then
				Tween(self._subTabIndicator, goal, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			else
				self._subTabIndicator.Position = goal.Position
				self._subTabIndicator.Size = goal.Size
				self._subTabIndicator.BackgroundTransparency = goal.BackgroundTransparency
			end
		end
 
		jan:Add(self._subTabHolder:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			self._syncSubIndicator(false)
			self._updateSubTabScrollbar()
		end))
	end
 
	local btn = Instance.new("TextButton")
	btn.Name = "SubTab_" .. title:gsub("%s", "")
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = Color3.new(1, 1, 1)
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.AutomaticSize = Enum.AutomaticSize.X
	btn.Size = UDim2.fromOffset(0, 32)
	btn.LayoutOrder = idx
	btn.ZIndex = Z.Content
	btn.Parent = self._subTabHolder
	Corner(btn, 8)
 
	local bl = Instance.new("UIListLayout")
	bl.FillDirection = Enum.FillDirection.Horizontal
	bl.VerticalAlignment = Enum.VerticalAlignment.Center
	bl.SortOrder = Enum.SortOrder.LayoutOrder
	bl.Padding = UDim.new(0, 6)
	bl.Parent = btn
 
	local bpad = Instance.new("UIPadding")
	bpad.PaddingLeft = UDim.new(0, 12)
	bpad.PaddingRight = UDim.new(0, 12)
	bpad.Parent = btn
 
	local ic = nil
	if iconAsset and iconAsset ~= "" then
		ic = Instance.new("ImageLabel")
		ic.BackgroundTransparency = 1
		ic.Image = iconAsset
		ic.ImageColor3 = BobloNEXT.Theme.TextDim
		ic.Size = UDim2.fromOffset(16, 16)
		ic.LayoutOrder = 1
		ic.ZIndex = Z.Content + 1
		ic.Parent = btn
	end
 
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.FontFace = BobloNEXT.Theme.Font
	lbl.Text = title
	lbl.TextColor3 = BobloNEXT.Theme.TextDim
	lbl.TextSize = 13
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Size = UDim2.new(0, 0, 0, 32)
	lbl.AutomaticSize = Enum.AutomaticSize.X
	lbl.LayoutOrder = 2
	lbl.ZIndex = Z.Content + 1
	lbl.Parent = btn
 
	local group = Instance.new("Frame")
	group.Name = title .. "Group"
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.Visible = false
	group.ZIndex = Z.Content
	group.Parent = self._subTabBody
 
	local container = Instance.new("ScrollingFrame")
	container.Name = title .. "Page"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ScrollingDirection = Enum.ScrollingDirection.Y
	container.ScrollBarThickness = 0
	container.AutomaticCanvasSize = Enum.AutomaticSize.Y
	container.CanvasSize = UDim2.new(0, 0, 0, 0)
	container.ZIndex = Z.Content
	container.Parent = group
 
	local cpad = Instance.new("UIPadding")
	cpad.Name = "PagePadding"
	cpad.PaddingRight = UDim.new(0, 12)
	cpad.PaddingBottom = UDim.new(0, 6)
	cpad.Parent = container
 
	local clayout = Instance.new("UIListLayout")
	clayout.Name = "PageLayout"
	clayout.Padding = UDim.new(0, 8)
	clayout.SortOrder = Enum.SortOrder.LayoutOrder
	clayout.Parent = container
 
	AddScrollbar(container)
	AddContentScrollThumb(container, clayout, group, jan)
	AddEmptyState(container, group, jan)
 
	local sub = setmetatable({
		Name           = title,
		_page          = container,
		_window        = self._window,
		_janitor       = jan,
		_parentTab     = self,
		_parentTabName = self.Name,
		_subTabIdx     = idx,
		Button    = btn,
		Label     = lbl,
		Icon      = ic,
		Container = container,
		Group     = group,
		Selected  = false,
	}, Tab)
 
	self._subTabs[idx] = sub
 
	jan:Add(btn:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		if self.SelectedSubTab == idx then
			self._syncSubIndicator(false)
		end
	end))
	jan:Add(btn:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if self.SelectedSubTab == idx then
			self._syncSubIndicator(false)
		end
	end))
 
	jan:Add(btn.MouseEnter:Connect(function()
		if idx ~= self.SelectedSubTab then
			Tween(btn, { BackgroundTransparency = 0.94 }, 0.15)
		end
	end))
	jan:Add(btn.MouseLeave:Connect(function()
		if idx ~= self.SelectedSubTab then
			Tween(btn, { BackgroundTransparency = 1 }, 0.15)
		end
	end))
 
	local downPos = nil
	jan:Add(btn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			downPos = input.Position
		end
	end))
	jan:Add(btn.InputEnded:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch) and downPos then
			if (input.Position - downPos).Magnitude < DRAG_THRESHOLD then
				self:SelectSubTab(idx)
			end
			downPos = nil
		end
	end))
 
	if not self.SelectedSubTab then
		self:SelectSubTab(idx)
	end
 
	return sub
end
 
function Tab:SelectSubTab(idx)
	if not self._subTabs then return end
	local previous = self.SelectedSubTab
	if previous == idx then return end
 
	self._subTabSwitchToken = (self._subTabSwitchToken or 0) + 1
	local myToken = self._subTabSwitchToken
 
	local direction = 0
	if previous then
		direction = (idx > previous) and 1 or -1
	end
 
	self.SelectedSubTab = idx
	local target = self._subTabs[idx]
	local previousSub = previous and self._subTabs[previous]
	if not target then return end
 
	self._syncSubIndicator(previous ~= nil)
 
	for i, st in pairs(self._subTabs) do
		local sel = (i == idx)
		st.Selected = sel
		if not sel then
			Tween(st.Button, { BackgroundTransparency = 1 }, 0.15)
		end
		Tween(st.Label, { TextColor3 = sel and BobloNEXT.Theme.Text or BobloNEXT.Theme.TextDim }, 0.22)
		if st.Icon then
			Tween(st.Icon, { ImageColor3 = sel and BobloNEXT.Theme.Text or BobloNEXT.Theme.TextDim }, 0.22)
		end
	end
 
	for _, st in pairs(self._subTabs) do
		if st ~= target and st ~= previousSub and st.Group.Visible then
			st.Group.Visible = false
		end
	end
 
	local function playEnter()
		if self._subTabSwitchToken ~= myToken then return end
		target.Group.Visible = true
		target.Group.Position = UDim2.fromOffset(direction * 20, 0)
		Tween(target.Group, {
			Position = UDim2.fromOffset(0, 0),
		}, SUBTAB_ENTER, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end
 
	if previousSub and previousSub.Group.Visible then
		local g = previousSub.Group
		Tween(g, {
			Position = UDim2.fromOffset(-direction * 20, 0),
		}, SUBTAB_EXIT, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(SUBTAB_EXIT, function()
			if g then g.Visible = false end
			task.delay(SUBTAB_GAP, playEnter)
		end)
	else
		playEnter()
	end
end
 
function Tab:SelectSubTabByName(name)
	if not self._subTabs then return nil end
	for idx, st in pairs(self._subTabs) do
		if st.Name == name then
			self:SelectSubTab(idx)
			return st
		end
	end
	return nil
end
 
local function RegisterFlag(opts, api, kind)
	if opts.Flag then
		BobloNEXT.Flags[opts.Flag] = api
		api.Flag = opts.Flag
		api.Kind = kind
		api.Label = opts.Text or opts.Label or opts.Flag
	end
	return api
end
 
function Tab:AddLabel(text)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = BobloNEXT.Theme.FontRegular
	label.Text = text
	label.TextColor3 = BobloNEXT.Theme.TextDim
	label.TextSize = 13
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, 0, 0, 16)
	label.ZIndex = Z.Content
	label.Parent = self._page
 
	return {
		Instance = label,
		Set = function(_, v) label.Text = v end,
		Get = function() return label.Text end,
		Destroy = function() label:Destroy() end,
	}
end
 
function Tab:AddSection(textOrOpts, maybeIcon)
	local opts = type(textOrOpts) == "table" and textOrOpts or { Text = textOrOpts, Icon = maybeIcon }
	local text = opts.Text or "Section"
	local iconAsset = opts.Icon and ResolveIcon(opts.Icon) or ""
 
	local holder = Instance.new("Frame")
	holder.Name = "Section"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 24)
	holder.ZIndex = Z.Content
	holder.Parent = self._page
 
	local x = 2
	if iconAsset ~= "" then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = iconAsset
		ThemeBind(img, "ImageColor3", "TextDim")
		img.Size = UDim2.fromOffset(13, 13)
		img.Position = UDim2.fromOffset(2, 8)
		img.ZIndex = Z.Content + 1
		img.Parent = holder
		x = 2 + 13 + 7
	end
 
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = BobloNEXT.Theme.Font
	label.Text = string.upper(text)
	ThemeBind(label, "TextColor3", "TextDim")
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Position = UDim2.fromOffset(x, 8)
	label.Size = UDim2.new(1, -(x + 2), 0, 14)
	label.ZIndex = Z.Content + 1
	label.Parent = holder
 
	return {
		Instance = holder,
		Set = function(_, v) label.Text = string.upper(v) end,
		Destroy = function() holder:Destroy() end,
	}
end
 
function Tab:AddDivider()
	local holder = Instance.new("Frame")
	holder.Name = "Divider"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 13)
	holder.ZIndex = Z.Content
	holder.Parent = self._page
 
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Position = UDim2.new(0, 0, 0.5, 0)
	line.Size = UDim2.new(1, 0, 0, 1)
	ThemeBind(line, "BackgroundColor3", "Border")
	line.BackgroundTransparency = 0.92
	line.BorderSizePixel = 0
	line.ZIndex = Z.Content
	line.Parent = holder
 
	return { Instance = holder, Destroy = function() holder:Destroy() end }
end
 
Tab.AddLine = Tab.AddDivider
 
function Tab:AddLineText(text)
	text = tostring(text or "")
 
	local holder = Instance.new("Frame")
	holder.Name = "LineText"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 20)
	holder.ZIndex = Z.Content
	holder.Parent = self._page
 
	local left = Instance.new("Frame")
	left.Name = "Left"
	left.AnchorPoint = Vector2.new(0, 0.5)
	left.Position = UDim2.fromScale(0, 0.5)
	left.Size = UDim2.new(0.5, -10, 0, 1)
	left.BackgroundColor3 = Color3.new(1, 1, 1)
	left.BackgroundTransparency = 0.92
	left.BorderSizePixel = 0
	left.ZIndex = Z.Content
	left.Parent = holder
 
	local right = Instance.new("Frame")
	right.Name = "Right"
	right.AnchorPoint = Vector2.new(1, 0.5)
	right.Position = UDim2.fromScale(1, 0.5)
	right.Size = UDim2.new(0.5, -10, 0, 1)
	right.BackgroundColor3 = Color3.new(1, 1, 1)
	right.BackgroundTransparency = 0.92
	right.BorderSizePixel = 0
	right.ZIndex = Z.Content
	right.Parent = holder
 
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.FontFace = BobloNEXT.Theme.FontRegular
	label.Text = text
	label.TextColor3 = BobloNEXT.Theme.TextDim
	label.TextSize = 12
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 16)
	label.ZIndex = Z.Content + 1
	label.Parent = holder
 
	local gap = 10
	local minSide = 6
	local lastW = -1
 
	local function relayout()
		local w = holder.AbsoluteSize.X / GetUIScale()
		if w <= 0 or math.abs(w - lastW) < 1 then return end
		lastW = w
 
		local textW = MeasureText(text, 12, w)
		local sideW = math.max((w - textW) / 2 - gap, minSide)
		left.Size = UDim2.new(0, sideW, 0, 1)
		right.Size = UDim2.new(0, sideW, 0, 1)
	end
 
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	task.defer(relayout)
 
	return {
		Instance = holder,
		Set = function(_, v)
			text = tostring(v or "")
			label.Text = text
			lastW = -1
			relayout()
		end,
		Destroy = function() holder:Destroy() end,
	}
end
 
function Tab:AddParagraph(opts)
	opts = opts or {}
 
	local card = BaseCard(self._page, 10)
	card.AutomaticSize = Enum.AutomaticSize.Y
 
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = card
 
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card
 
	local titleLabel
	if opts.Title then
		local titleRow = Instance.new("Frame")
		titleRow.BackgroundTransparency = 1
		titleRow.Size = UDim2.new(1, 0, 0, 18)
		titleRow.AutomaticSize = Enum.AutomaticSize.Y
		titleRow.LayoutOrder = 1
		titleRow.ZIndex = Z.Content + 1
		titleRow.Parent = card
 
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Padding = UDim.new(0, 7)
		rowLayout.Parent = titleRow
 
		local iconAsset = opts.Icon and ResolveIcon(opts.Icon) or ""
		if iconAsset ~= "" then
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Image = iconAsset
			img.ImageColor3 = BobloNEXT.Theme.Text
			img.Size = UDim2.fromOffset(15, 15)
			img.LayoutOrder = 1
			img.ZIndex = Z.Content + 2
			img.Parent = titleRow
		end
 
		titleLabel = Instance.new("TextLabel")
		titleLabel.BackgroundTransparency = 1
		titleLabel.FontFace = BobloNEXT.Theme.Font
		titleLabel.Text = opts.Title
		titleLabel.TextColor3 = BobloNEXT.Theme.Text
		titleLabel.TextSize = 14
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.TextYAlignment = Enum.TextYAlignment.Center
		titleLabel.AutomaticSize = Enum.AutomaticSize.X
		titleLabel.Size = UDim2.fromOffset(0, 18)
		titleLabel.LayoutOrder = 2
		titleLabel.ZIndex = Z.Content + 2
		titleLabel.Parent = titleRow
 
		local titlePadding = Instance.new("UIPadding")
		titlePadding.PaddingTop = UDim.new(0, 2)
		titlePadding.Parent = titleLabel
	end
 
	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.FontFace = BobloNEXT.Theme.FontRegular
	textLabel.Text = opts.Text or ""
	textLabel.TextColor3 = BobloNEXT.Theme.TextDim
	textLabel.TextSize = 13
	textLabel.TextWrapped = true
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.AutomaticSize = Enum.AutomaticSize.Y
	textLabel.Size = UDim2.new(1, 0, 0, 16)
	textLabel.LayoutOrder = 2
	textLabel.ZIndex = Z.Content + 1
	textLabel.Parent = card
 
	return {
		Instance = card,
		Set = function(_, v) textLabel.Text = v end,
		Get = function() return textLabel.Text end,
		SetTitle = function(_, v) if titleLabel then titleLabel.Text = v end end,
		Destroy = function() card:Destroy() end,
	}
end
 
local function BuildStarRow(parent, layoutOrder, maxStars, starColor, starSize, default)
	local starOutline = ResolveIcon("Phosphor:star")
	local starFilled = ResolveIcon("Material:star")
 
	local row = Instance.new("Frame")
	row.Name = "Stars"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, starSize)
	row.LayoutOrder = layoutOrder
	row.ZIndex = Z.Content + 1
	row.Parent = parent
 
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = row
 
	local stars = {}
	local selected = math.clamp(default or 0, 0, maxStars)
 
	local function paint(previewCount)
		local count = previewCount or selected
		for i, button in ipairs(stars) do
			local on = i <= count
			button.Image = on and starFilled or starOutline
			Tween(button, { ImageColor3 = on and starColor or BobloNEXT.Theme.TextDim }, 0.12)
		end
	end
 
	for i = 1, maxStars do
		local button = Instance.new("ImageButton")
		button.Name = "Star" .. i
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false
		button.Image = starOutline
		button.ImageColor3 = BobloNEXT.Theme.TextDim
		button.Size = UDim2.fromOffset(starSize, starSize)
		button.LayoutOrder = i
		button.ZIndex = Z.Content + 2
		button.Parent = row
 
		button.MouseEnter:Connect(function() paint(i) end)
		button.MouseLeave:Connect(function() paint() end)
		button.MouseButton1Click:Connect(function()
			selected = i
			paint()
		end)
 
		stars[i] = button
	end
	paint()
 
	return {
		Row = row,
		Get = function() return selected end,
		Set = function(v)
			selected = math.clamp(v or 0, 0, maxStars)
			paint()
		end,
		Nudge = function()
			for _, button in ipairs(stars) do Tween(button, { Rotation = 8 }, 0.06) end
			task.delay(0.06, function()
				for _, button in ipairs(stars) do Tween(button, { Rotation = 0 }, 0.12) end
			end)
		end,
	}
end
 
local function NormalizeFeedbackText(text)
	local invisibleChars = {
		["\226\128\139"] = "", ["\226\128\142"] = "", ["\226\128\143"] = "",
		["\239\187\191"] = "", ["\194\173"] = "",
	}
	for char, replacement in pairs(invisibleChars) do
		text = text:gsub(char, replacement)
	end
	text = text:gsub("%s+", " ")
	text = text:gsub("^%s+", "")
	text = text:gsub("%s+$", "")
	return text
end
 
local FeedbackEvasionPatterns = {
	{pattern = "d%s*i%s*s%s*c%s*o%s*r%s*d", name = "discord"},
	{pattern = "t%s*e%s*l%s*e%s*g%s*r%s*a%s*m", name = "telegram"},
	{pattern = "w%s*h%s*a%s*t%s*s%s*a%s*p%s*p", name = "whatsapp"},
	{pattern = "h%s*t%s*t%s*p", name = "http"},
	{pattern = "h%s*t%s*t%s*p%s*s", name = "https"},
	{pattern = "w%s*w%s*w", name = "www"},
	{pattern = "c%s*o%s*m", name = "com"},
	{pattern = "o%s*r%s*g", name = "org"},
	{pattern = "n%s*e%s*t", name = "net"},
	{pattern = ".%s*g%s*g", name = ".gg"},
	{pattern = ".%s*c%s*o%s*m", name = ".com"},
	{pattern = "/%s*i%s*n%s*v%s*i%s*t%s*e", name = "/invite"},
	{pattern = "d%s*o%s*t%s*%s*c%s*o%s*m", name = "dot com"},
	{pattern = "a%s*t%s*%s*%s*h%s*e%s*r%s*e", name = "@here"},
	{pattern = "a%s*t%s*%s*%s*e%s*v%s*e%s*r%s*y%s*o%s*n%s*e", name = "@everyone"},
}
 
local function DetectFeedbackEvasion(text)
	for _, evasion in ipairs(FeedbackEvasionPatterns) do
		if text:match(evasion.pattern) then
			return true, evasion.name
		end
	end
	local dotCount, slashCount = 0, 0
	for i = 1, #text do
		local char = text:sub(i, i)
		if char == "." then dotCount = dotCount + 1 end
		if char == "/" then slashCount = slashCount + 1 end
	end
	if dotCount >= 3 or slashCount >= 3 then
		return true, "suspicious link/invite"
	end
	return false, nil
end
 
local FeedbackAsciiMap = {
	["á"] = "a", ["à"] = "a", ["ã"] = "a", ["â"] = "a", ["ä"] = "a",
	["Á"] = "A", ["À"] = "A", ["Ã"] = "A", ["Â"] = "A", ["Ä"] = "A",
	["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
	["É"] = "E", ["È"] = "E", ["Ê"] = "E", ["Ë"] = "E",
	["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i",
	["Í"] = "I", ["Ì"] = "I", ["Î"] = "I", ["Ï"] = "I",
	["ó"] = "o", ["ò"] = "o", ["õ"] = "o", ["ô"] = "o", ["ö"] = "o",
	["Ó"] = "O", ["Ò"] = "O", ["Õ"] = "O", ["Ô"] = "O", ["Ö"] = "O",
	["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u",
	["Ú"] = "U", ["Ù"] = "U", ["Û"] = "U", ["Ü"] = "U",
	["ç"] = "c", ["Ç"] = "C", ["ñ"] = "n", ["Ñ"] = "N",
	["°"] = " ", ["º"] = " ", ["ª"] = " ",
}
 
local FeedbackAllowedChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,!?;:()[]{}@#%&*+-=/_\"'"
 
local function SanitizeFeedbackText(text)
	if not text or text == "" then
		return "_No message_"
	end
 
	text = NormalizeFeedbackText(text)
 
	local hasEvasion, evasionType = DetectFeedbackEvasion(text)
	if hasEvasion then
		return "[Message blocked - " .. evasionType .. "]"
	end
 
	text = text:gsub("@everyone", "@\226\128\139everyone")
	text = text:gsub("@here", "@\226\128\139here")
	text = text:gsub("<@!?(%d+)>", "[user]")
	text = text:gsub("<@&(%d+)>", "[role]")
 
	text = text:gsub("d[iI][sS][cC][oO][rR][dD]%.?[gG][gG]%s*/?%s*[%w%-_]+", "[invite removed]")
	text = text:gsub("d[iI][sS][cC][oO][rR][dD]%.?[cC][oO][mM]%s*/?%s*[iI][nN][vV][iI][tT][eE]%s*/?%s*[%w%-_]+", "[invite removed]")
	text = text:gsub("https?%s*:%s*//%s*[%w%-%.]+%s*%.%s*[%w]+[%w%-%./?=&%%]*", "[link removed]")
	text = text:gsub("www%s*%.%s*[%w%-]+%s*%.%s*[%w]+", "[link removed]")
	text = text:gsub("t[eE][lL][eE][gG][rR][aA][mM]%.?%s*[mM][eE]%s*/%s*[%w%-_]+", "[invite removed]")
 
	for old, new in pairs(FeedbackAsciiMap) do
		text = text:gsub(old, new)
	end
 
	local cleaned = ""
	for i = 1, #text do
		local char = text:sub(i, i)
		if FeedbackAllowedChars:find(char, 1, true) then
			cleaned = cleaned .. char
		else
			cleaned = cleaned .. " "
		end
	end
	text = cleaned
 
	text = text:gsub("%s+", " ")
	text = text:gsub("^%s+", "")
	text = text:gsub("%s+$", "")
 
	local hasEvasionAfter = DetectFeedbackEvasion(text)
	if hasEvasionAfter then
		return "[Message blocked - suspicious content]"
	end
 
	if #text > 500 then
		text = text:sub(1, 500) .. "..."
	end
 
	return text
end
 
function BobloNEXT:SanitizeText(text, opts)
	opts = opts or {}
	local maxLength = opts.MaxLength or 500
 
	if not text or text == "" then
		return "", false, nil
	end
 
	local normalized = NormalizeFeedbackText(tostring(text))
	local hasEvasion, evasionType = DetectFeedbackEvasion(normalized)
	if hasEvasion then
		return "", true, evasionType
	end
 
	local cleaned = SanitizeFeedbackText(text)
	if cleaned == "_No message_" then
		return "", false, nil
	end
	if cleaned:find("^%[Message blocked") then
		return "", true, "blocked content"
	end
 
	if #cleaned > maxLength then
		cleaned = cleaned:sub(1, maxLength)
	end
 
	return cleaned, false, nil
end
 
local FEEDBACK_WEBHOOK_COOLDOWN = 30
local LastFeedbackWebhookAt = 0
 
function BobloNEXT:SendFeedbackWebhook(webhookUrl, stars, message, opts)
	opts = opts or {}
	stars = math.clamp(math.floor((stars or 0) + 0.5), 0, 5)
 
	local now = os.clock()
	if now - LastFeedbackWebhookAt < FEEDBACK_WEBHOOK_COOLDOWN then
		self:Notify({
			Title = "Feedback",
			Text  = string.format(
				"Please wait %ds before sending more feedback.",
				math.ceil(FEEDBACK_WEBHOOK_COOLDOWN - (now - LastFeedbackWebhookAt))
			),
			Type  = "warning",
			Duration = 3,
		})
		return false
	end
 
	if not webhookUrl or webhookUrl == "" then
		self:Notify({
			Title = "Feedback",
			Text  = "No webhook configured.",
			Type  = "warning",
			Duration = 4,
		})
		return false
	end
 
	local httpRequest = (syn and syn.request) or http_request or request
	if not httpRequest then
		self:Notify({
			Title = "Feedback",
			Text  = "Your executor doesn't support HTTP requests.",
			Type  = "error",
			Duration = 4,
		})
		return false
	end
 
	local normalizedMessage = NormalizeFeedbackText(message or "")
	local hasEvasion = DetectFeedbackEvasion(normalizedMessage)
	local cleanMessage = SanitizeFeedbackText(message)
 
	if hasEvasion or cleanMessage:find("blocked") then
		LastFeedbackWebhookAt = now
		self:Notify({
			Title = "Blocked",
			Text = "Unallowed content detected.",
			Type = "error",
			Duration = 4,
		})
		return false
	end
 
	LastFeedbackWebhookAt = now
 
	local starDisplay = string.rep("\226\152\133", stars) .. string.rep("\226\152\134", 5 - stars)
	local embedColor = opts.Color or 0xFFC440
	local hasInvite = cleanMessage:find("%[invite removed%]") or cleanMessage:find("%[link removed%]")
 
	local body = HttpService:JSONEncode({
		allowed_mentions = { parse = {} },
		embeds = {{
			title = opts.Title or "New UI Feedback",
			description = starDisplay .. "  (" .. stars .. "/5)",
			color = embedColor,
			fields = {
				{ name = "Message", value = cleanMessage, inline = false },
			},
			footer = { text = hasInvite and "Invites removed" or "Submitted anonymously" },
			timestamp = DateTime.now():ToIsoDate(),
		}},
	})
 
	task.spawn(function()
		local ok, err = pcall(httpRequest, {
			Url = webhookUrl,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = body,
		})
		self:Notify({
			Title = ok and "Feedback Sent" or "Failed to Send",
			Text  = ok and "Thanks for rating the UI!" or tostring(err),
			Type  = ok and "success" or "error",
			Duration = 3,
		})
	end)
 
	return true
end
 
local function BuildFeedbackRow(parent, layoutOrder, rowH, placeholder, buttonIcon)
	local row = Instance.new("Frame")
	row.Name = "Feedback"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, rowH)
	row.LayoutOrder = layoutOrder
	row.ZIndex = Z.Content + 1
	row.Parent = parent
 
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.BackgroundColor3 = Color3.new(1, 1, 1)
	pill.BackgroundTransparency = 0.95
	pill.BorderSizePixel = 0
	pill.Size = UDim2.new(1, -(rowH + 6), 1, 0)
	pill.ZIndex = Z.Content + 1
	pill.Parent = row
	Corner(pill, 9)
	local pillStroke = Stroke(pill, Color3.new(1, 1, 1), 1, 0.9)
 
	local pillPad = Instance.new("UIPadding")
	pillPad.PaddingLeft = UDim.new(0, 10)
	pillPad.PaddingRight = UDim.new(0, 10)
	pillPad.Parent = pill
 
	local box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.ClearTextOnFocus = false
	box.FontFace = BobloNEXT.Theme.FontRegular
	box.PlaceholderText = placeholder or "Give us some feedback!"
	box.PlaceholderColor3 = Color3.fromRGB(120, 120, 122)
	box.Text = ""
	box.TextColor3 = BobloNEXT.Theme.Text
	box.TextSize = 13
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Center
	box.TextTruncate = Enum.TextTruncate.AtEnd
	box.ClipsDescendants = true
	box.Size = UDim2.fromScale(1, 1)
	box.ZIndex = Z.Content + 2
	box.Parent = pill
 
	box.Focused:Connect(function()
		Tween(pillStroke, { Color = BobloNEXT.Theme.Accent, Transparency = 0.3 }, 0.15)
	end)
	box.FocusLost:Connect(function()
		Tween(pillStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.9 }, 0.15)
	end)
 
	local sendBtn = Instance.new("TextButton")
	sendBtn.Name = "Send"
	sendBtn.Text = ""
	sendBtn.AutoButtonColor = false
	sendBtn.BackgroundColor3 = Color3.new(1, 1, 1)
	sendBtn.BackgroundTransparency = 0.9
	sendBtn.BorderSizePixel = 0
	sendBtn.AnchorPoint = Vector2.new(1, 0)
	sendBtn.Position = UDim2.new(1, 0, 0, 0)
	sendBtn.Size = UDim2.fromOffset(rowH, rowH)
	sendBtn.ZIndex = Z.Content + 1
	sendBtn.Parent = row
	Corner(sendBtn, 9)
 
	local sendIcon = Instance.new("ImageLabel")
	sendIcon.BackgroundTransparency = 1
	sendIcon.Image = ResolveIcon(buttonIcon or "send")
	sendIcon.ImageColor3 = BobloNEXT.Theme.Text
	sendIcon.Size = UDim2.fromOffset(12, 12)
	sendIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	sendIcon.Position = UDim2.fromScale(0.5, 0.5)
	sendIcon.ZIndex = Z.Content + 2
	sendIcon.Parent = sendBtn
 
	sendBtn.MouseEnter:Connect(function() Tween(sendBtn, { BackgroundTransparency = 0.8 }, 0.12) end)
	sendBtn.MouseLeave:Connect(function() Tween(sendBtn, { BackgroundTransparency = 0.9 }, 0.12) end)
 
	return { Row = row, Box = box, SendBtn = sendBtn }
end
 
function Tab:AddRating(opts)
	opts = opts or {}
	local maxStars = math.max(1, opts.MaxStars or 5)
	local starColor = opts.StarColor or Color3.fromRGB(255, 196, 64)
	local hasTitle = opts.Title and opts.Title ~= ""
 
	local card = BaseCard(self._page, 10)
	card.AutomaticSize = Enum.AutomaticSize.Y
 
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = card
 
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card
 
	if hasTitle then
		local titleLabel = Instance.new("TextLabel")
		titleLabel.BackgroundTransparency = 1
		titleLabel.FontFace = BobloNEXT.Theme.Font
		titleLabel.Text = opts.Title
		titleLabel.TextColor3 = BobloNEXT.Theme.Text
		titleLabel.TextSize = 14
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.Size = UDim2.new(1, 0, 0, 16)
		titleLabel.LayoutOrder = 1
		titleLabel.ZIndex = Z.Content + 1
		titleLabel.Parent = card
 
		self._window:_RegisterSearchable(self, opts.Title, card)
	end
 
	local starBar = BuildStarRow(card, 2, maxStars, starColor, 20, opts.Default)
	local feedback = BuildFeedbackRow(card, 3, 26, opts.Placeholder, opts.ButtonIcon)
 
	local clearOnSubmit = opts.ClearOnSubmit ~= false
	feedback.SendBtn.MouseButton1Click:Connect(function()
		local selected = starBar.Get()
		if selected <= 0 then
			starBar.Nudge()
			return
		end
		if opts.Callback then task.spawn(opts.Callback, selected, feedback.Box.Text) end
		if opts.WebhookUrl then
			task.spawn(function()
				BobloNEXT:SendFeedbackWebhook(opts.WebhookUrl, selected, feedback.Box.Text, opts.WebhookOptions)
			end)
		end
		if clearOnSubmit then
			feedback.Box.Text = ""
			starBar.Set(opts.Default or 0)
		end
	end)
 
	return {
		Instance = card,
		Get = function() return starBar.Get(), feedback.Box.Text end,
		Set = function(_, newStars, newText)
			starBar.Set(newStars)
			if newText ~= nil then feedback.Box.Text = newText end
		end,
		Destroy = function() card:Destroy() end,
	}
end
 
function Tab:AddButton(opts)
	opts = opts or {}
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local card = BaseCard(self._page, height)
 
	local textX = AddLeadingIcon(card, opts.Icon, height)
	AddTitleDesc(card, textX, 44, opts.Text or "Button", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Button", card)
 
	local chev = Instance.new("ImageLabel")
	chev.BackgroundTransparency = 1
	chev.Image = ResolveIcon("chevron-right")
	chev.ImageColor3 = BobloNEXT.Theme.TextDim
	chev.Size = UDim2.fromOffset(14, 14)
	chev.AnchorPoint = Vector2.new(1, 0.5)
	chev.Position = UDim2.new(1, -16, 0.5, 0)
	chev.ZIndex = Z.Content + 1
	chev.Parent = card
 
	local click = Instance.new("TextButton")
	click.Text = ""
	click.AutoButtonColor = false
	click.BackgroundTransparency = 1
	click.Size = UDim2.fromScale(1, 1)
	click.ZIndex = Z.Content + 3
	click.Parent = card
 
	click.MouseEnter:Connect(function()
		Tween(card, { BackgroundTransparency = 0.9 }, 0.15)
		Tween(chev, { ImageColor3 = BobloNEXT.Theme.Text, Position = UDim2.new(1, -12, 0.5, 0) }, 0.15)
	end)
	click.MouseLeave:Connect(function()
		Tween(card, { BackgroundTransparency = 0.96 }, 0.15)
		Tween(chev, { ImageColor3 = BobloNEXT.Theme.TextDim, Position = UDim2.new(1, -16, 0.5, 0) }, 0.15)
	end)
	click.MouseButton1Click:Connect(function()
		Tween(card, { BackgroundTransparency = 0.8 }, 0.08)
		Tween(chev, { ImageColor3 = BobloNEXT.Theme.Accent }, 0.08)
		task.delay(0.08, function()
			if not card.Parent then return end
			Tween(card, { BackgroundTransparency = 0.9 }, 0.15)
			Tween(chev, { ImageColor3 = BobloNEXT.Theme.Text }, 0.15)
		end)
		if opts.Callback then task.spawn(opts.Callback) end
	end)
 
	return {
		Instance = card,
		Destroy = function() card:Destroy() end,
	}
end
 
function Tab:AddCard(opts)
	opts = opts or {}
	local hasDesc = opts.Description and opts.Description ~= ""
	local hasImage = (opts.Image and opts.Image ~= "") or opts.UserId ~= nil
	local hasButton = opts.ButtonText ~= nil and opts.ButtonText ~= ""
	local BUTTON_H, BUTTON_GAP, BUTTON_MARGIN = 32, 6, 4
	local buttonReserve = hasButton and (BUTTON_GAP + BUTTON_H + BUTTON_MARGIN) or 0
 
	local hasRating = type(opts.Rating) == "table"
	local RATING_LABEL_H, RATING_STAR_H, RATING_INPUT_H = 14, 20, 26
	local RATING_ROW_GAP, RATING_TOP_GAP, RATING_BOTTOM_MARGIN = 6, 10, 8
	local ratingHasTitle = hasRating and opts.Rating.Title and opts.Rating.Title ~= ""
	local ratingBlockH = 0
	if hasRating then
		local bodyH = (ratingHasTitle and (RATING_LABEL_H + RATING_ROW_GAP) or 0)
			+ RATING_STAR_H + RATING_ROW_GAP + RATING_INPUT_H
		ratingBlockH = RATING_TOP_GAP + bodyH + RATING_BOTTOM_MARGIN
	end
 
	local extraBottom = buttonReserve + ratingBlockH
	local topHeight = hasDesc and 56 or 44
	local height = topHeight + extraBottom
	local imgSize, imgPad = 34, 10
 
	local card = BaseCard(self._page, height)
	local textX = 14
 
	if hasImage then
		local imgHolder = Instance.new("Frame")
		imgHolder.Name = "Image"
		imgHolder.AnchorPoint = Vector2.new(0, 0.5)
		imgHolder.Position = UDim2.fromOffset(10, topHeight / 2)
		imgHolder.Size = UDim2.fromOffset(imgSize, imgSize)
		imgHolder.BackgroundTransparency = 1
		imgHolder.BorderSizePixel = 0
		imgHolder.ClipsDescendants = true
		imgHolder.ZIndex = Z.Content + 1
		imgHolder.Parent = card
		Corner(imgHolder, BobloNEXT.Theme.CornerRadiusSm)
		Stroke(imgHolder, Color3.new(1, 1, 1), 1, 0.85)
 
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.ScaleType = Enum.ScaleType.Crop
		img.Size = UDim2.fromScale(1, 1)
		img.ZIndex = Z.Content + 2
		img.Parent = imgHolder
		Corner(img, BobloNEXT.Theme.CornerRadiusSm)
 
		if opts.UserId then
			task.spawn(function()
				local ok, content = pcall(
					Players.GetUserThumbnailAsync,
					Players,
					opts.UserId,
					opts.ThumbnailType or Enum.ThumbnailType.HeadShot,
					opts.ThumbnailSize or Enum.ThumbnailSize.Size100x100
				)
				if ok and content and img.Parent then
					img.Image = content
				end
			end)
		else
			img.Image = ResolveIcon(opts.Image)
		end
 
		textX = 10 + imgSize + imgPad
	end
 
	local rightReserve = opts.Callback and 44 or 14
	AddTitleDesc(card, textX, rightReserve, opts.Title or "Card", opts.Description, topHeight, extraBottom)
	self._window:_RegisterSearchable(self, opts.Title or "Card", card)
 
	if opts.Callback then
		local chev = Instance.new("ImageLabel")
		chev.BackgroundTransparency = 1
		chev.Image = ResolveIcon("chevron-right")
		chev.ImageColor3 = BobloNEXT.Theme.TextDim
		chev.Size = UDim2.fromOffset(14, 14)
		chev.AnchorPoint = Vector2.new(1, 0.5)
		chev.Position = UDim2.new(1, -16, 0.5, 0)
		chev.ZIndex = Z.Content + 1
		chev.Parent = card
 
		local click = Instance.new("TextButton")
		click.Text = ""
		click.AutoButtonColor = false
		click.BackgroundTransparency = 1
		click.Size = UDim2.fromScale(1, 1)
		click.ZIndex = Z.Content + 3
		click.Parent = card
 
		click.MouseEnter:Connect(function()
			Tween(card, { BackgroundTransparency = 0.9 }, 0.15)
			Tween(chev, { ImageColor3 = BobloNEXT.Theme.Text, Position = UDim2.new(1, -12, 0.5, 0) }, 0.15)
		end)
		click.MouseLeave:Connect(function()
			Tween(card, { BackgroundTransparency = 0.96 }, 0.15)
			Tween(chev, { ImageColor3 = BobloNEXT.Theme.TextDim, Position = UDim2.new(1, -16, 0.5, 0) }, 0.15)
		end)
		click.MouseButton1Click:Connect(function()
			Tween(card, { BackgroundTransparency = 0.8 }, 0.08)
			task.delay(0.08, function()
				if card.Parent then Tween(card, { BackgroundTransparency = 0.9 }, 0.15) end
			end)
			task.spawn(opts.Callback)
		end)
	end
 
	if hasButton then
		local footerBtn = Instance.new("TextButton")
		footerBtn.Name = "FooterButton"
		footerBtn.Text = ""
		footerBtn.AutoButtonColor = false
		footerBtn.BackgroundColor3 = Color3.new(1, 1, 1)
		footerBtn.BackgroundTransparency = 0.85
		footerBtn.BorderSizePixel = 0
		footerBtn.Position = UDim2.new(0, 10, 1, -(BUTTON_H + BUTTON_MARGIN))
		footerBtn.Size = UDim2.new(1, -20, 0, BUTTON_H)
		footerBtn.ZIndex = Z.Content + 1
		footerBtn.Parent = card
		Corner(footerBtn, 8)
		local footerStroke = Stroke(footerBtn, Color3.new(1, 1, 1), 1, 0.85)
 
		local footerLabel = Instance.new("TextLabel")
		footerLabel.BackgroundTransparency = 1
		footerLabel.FontFace = BobloNEXT.Theme.Font
		footerLabel.Text = opts.ButtonText
		footerLabel.TextColor3 = BobloNEXT.Theme.Text
		footerLabel.TextSize = 13
		footerLabel.Size = UDim2.fromScale(1, 1)
		footerLabel.ZIndex = Z.Content + 2
		footerLabel.Parent = footerBtn
 
		footerBtn.MouseEnter:Connect(function()
			Tween(footerBtn, { BackgroundTransparency = 0.7 }, 0.12)
			Tween(footerStroke, { Transparency = 0.7 }, 0.12)
		end)
		footerBtn.MouseLeave:Connect(function()
			Tween(footerBtn, { BackgroundTransparency = 0.85 }, 0.12)
			Tween(footerStroke, { Transparency = 0.85 }, 0.12)
		end)
		footerBtn.MouseButton1Click:Connect(function()
			Tween(footerBtn, { BackgroundTransparency = 0.55 }, 0.08)
			task.delay(0.08, function()
				if footerBtn.Parent then Tween(footerBtn, { BackgroundTransparency = 0.7 }, 0.15) end
			end)
			if opts.ButtonCallback then task.spawn(opts.ButtonCallback) end
		end)
	end
 
	local ratingBar
	if hasRating then
		local ratingOpts = opts.Rating
 
		local ratingHolder = Instance.new("Frame")
		ratingHolder.Name = "Rating"
		ratingHolder.BackgroundTransparency = 1
		ratingHolder.Position = UDim2.new(0, 10, 1, -(ratingBlockH + buttonReserve))
		ratingHolder.Size = UDim2.new(1, -20, 0, ratingBlockH - RATING_BOTTOM_MARGIN)
		ratingHolder.ZIndex = Z.Content + 1
		ratingHolder.Parent = card
 
		local divider = Instance.new("Frame")
		divider.Name = "Divider"
		divider.BackgroundColor3 = Color3.new(1, 1, 1)
		divider.BackgroundTransparency = 0.94
		divider.BorderSizePixel = 0
		divider.Size = UDim2.new(1, 0, 0, 1)
		divider.ZIndex = Z.Content + 1
		divider.Parent = ratingHolder
 
		local ratingBody = Instance.new("Frame")
		ratingBody.BackgroundTransparency = 1
		ratingBody.Position = UDim2.new(0, 0, 0, RATING_TOP_GAP)
		ratingBody.Size = UDim2.new(1, 0, 1, -RATING_TOP_GAP)
		ratingBody.ZIndex = Z.Content + 1
		ratingBody.Parent = ratingHolder
 
		local ratingLayout = Instance.new("UIListLayout")
		ratingLayout.Padding = UDim.new(0, RATING_ROW_GAP)
		ratingLayout.SortOrder = Enum.SortOrder.LayoutOrder
		ratingLayout.Parent = ratingBody
 
		if ratingHasTitle then
			local ratingLabel = Instance.new("TextLabel")
			ratingLabel.BackgroundTransparency = 1
			ratingLabel.FontFace = BobloNEXT.Theme.Font
			ratingLabel.Text = ratingOpts.Title
			ratingLabel.TextColor3 = BobloNEXT.Theme.Text
			ratingLabel.TextSize = 13
			ratingLabel.TextXAlignment = Enum.TextXAlignment.Left
			ratingLabel.Size = UDim2.new(1, 0, 0, RATING_LABEL_H)
			ratingLabel.LayoutOrder = 1
			ratingLabel.ZIndex = Z.Content + 1
			ratingLabel.Parent = ratingBody
		end
 
		local starBar = BuildStarRow(ratingBody, 2, math.max(1, ratingOpts.MaxStars or 5),
			ratingOpts.StarColor or Color3.fromRGB(255, 196, 64), RATING_STAR_H, ratingOpts.Default)
		local feedback = BuildFeedbackRow(ratingBody, 3, RATING_INPUT_H, ratingOpts.Placeholder, ratingOpts.ButtonIcon)
 
		local clearOnSubmit = ratingOpts.ClearOnSubmit ~= false
		feedback.SendBtn.MouseButton1Click:Connect(function()
			local sel = starBar.Get()
			if sel <= 0 then
				starBar.Nudge()
				return
			end
			if ratingOpts.Callback then task.spawn(ratingOpts.Callback, sel, feedback.Box.Text) end
			if ratingOpts.WebhookUrl then
				task.spawn(function()
					BobloNEXT:SendFeedbackWebhook(ratingOpts.WebhookUrl, sel, feedback.Box.Text, ratingOpts.WebhookOptions)
				end)
			end
			if clearOnSubmit then
				feedback.Box.Text = ""
				starBar.Set(ratingOpts.Default or 0)
			end
		end)
 
		ratingBar = {
			Get = function() return starBar.Get(), feedback.Box.Text end,
			Set = function(newStars, newText)
				starBar.Set(newStars)
				if newText ~= nil then feedback.Box.Text = newText end
			end,
		}
	end
 
	return {
		Instance = card,
		Rating = ratingBar,
		Destroy = function() card:Destroy() end,
	}
end
 
local CHANGELOG_TYPES = {
	Added   = { Color = Color3.fromRGB(120, 210, 140), Icon = "plus" },
	Fixed   = { Color = Color3.fromRGB(120, 170, 255), Icon = "wrench" },
	Changed = { Color = Color3.fromRGB(255, 190, 90),  Icon = "refresh-cw" },
	Removed = { Color = Color3.fromRGB(230, 120, 120), Icon = "minus" },
}
 
function Tab:AddChangelogEntry(opts)
	opts = opts or {}
	local version = opts.Version or "Update"
	local date = opts.Date
	local changes = opts.Changes or {}
 
	local PAD = 12
	local HEADER_H = 18
	local ROW_H = 22
	local ROW_GAP = 2
	local height = PAD * 2 + HEADER_H + (#changes > 0 and 8 or 0)
 
	local card = BaseCard(self._page, height)
	card.AutomaticSize = Enum.AutomaticSize.Y
	self._window:_RegisterSearchable(self, version, card)
 
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, PAD)
	pad.PaddingBottom = UDim.new(0, PAD)
	pad.PaddingLeft = UDim.new(0, PAD)
	pad.PaddingRight = UDim.new(0, PAD)
	pad.Parent = card
 
	local versionLabel = Instance.new("TextLabel")
	versionLabel.BackgroundTransparency = 1
	versionLabel.FontFace = BobloNEXT.Theme.Font
	versionLabel.Text = version
	versionLabel.TextColor3 = BobloNEXT.Theme.Text
	versionLabel.TextSize = 14
	versionLabel.TextXAlignment = Enum.TextXAlignment.Left
	versionLabel.TextTruncate = Enum.TextTruncate.AtEnd
	versionLabel.Size = UDim2.new(1, date and -90 or 0, 0, HEADER_H)
	versionLabel.ZIndex = Z.Content + 1
	versionLabel.Parent = card
 
	if date then
		local dateLabel = Instance.new("TextLabel")
		dateLabel.BackgroundTransparency = 1
		dateLabel.FontFace = BobloNEXT.Theme.FontRegular
		dateLabel.Text = date
		dateLabel.TextColor3 = BobloNEXT.Theme.TextDim
		dateLabel.TextSize = 12
		dateLabel.TextXAlignment = Enum.TextXAlignment.Right
		dateLabel.AnchorPoint = Vector2.new(1, 0)
		dateLabel.Position = UDim2.new(1, 0, 0, 2)
		dateLabel.Size = UDim2.fromOffset(90, HEADER_H)
		dateLabel.ZIndex = Z.Content + 1
		dateLabel.Parent = card
	end
 
	local rowsHolder = Instance.new("Frame")
	rowsHolder.Name = "Rows"
	rowsHolder.BackgroundTransparency = 1
	rowsHolder.Position = UDim2.fromOffset(0, HEADER_H + 8)
	rowsHolder.Size = UDim2.new(1, 0, 0, 0)
	rowsHolder.AutomaticSize = Enum.AutomaticSize.Y
	rowsHolder.ZIndex = Z.Content + 1
	rowsHolder.Parent = card
 
	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.FillDirection = Enum.FillDirection.Vertical
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Padding = UDim.new(0, ROW_GAP)
	rowsLayout.Parent = rowsHolder
 
	for i, change in ipairs(changes) do
		local kind = CHANGELOG_TYPES[change.Type] and change.Type or "Changed"
		local meta = CHANGELOG_TYPES[kind]
 
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = i * 2 - 1
		row.ZIndex = Z.Content + 1
		row.Parent = rowsHolder
 
		local pill = Instance.new("Frame")
		pill.BackgroundColor3 = meta.Color
		pill.BackgroundTransparency = 0.85
		pill.BorderSizePixel = 0
		pill.AnchorPoint = Vector2.zero
		pill.Position = UDim2.fromOffset(0, 1)
		pill.Size = UDim2.fromOffset(66, 18)
		pill.ZIndex = Z.Content + 2
		pill.Parent = row
		Corner(pill, 5)
 
		local pillLayout = Instance.new("UIListLayout")
		pillLayout.FillDirection = Enum.FillDirection.Horizontal
		pillLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		pillLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		pillLayout.Padding = UDim.new(0, 3)
		pillLayout.Parent = pill
 
		local pillIcon = Instance.new("ImageLabel")
		pillIcon.BackgroundTransparency = 1
		pillIcon.Image = ResolveIcon(meta.Icon)
		pillIcon.ImageColor3 = meta.Color
		pillIcon.Size = UDim2.fromOffset(9, 9)
		pillIcon.LayoutOrder = 1
		pillIcon.ZIndex = Z.Content + 3
		pillIcon.Parent = pill
 
		local pillLabel = Instance.new("TextLabel")
		pillLabel.BackgroundTransparency = 1
		pillLabel.FontFace = BobloNEXT.Theme.Font
		pillLabel.Text = string.upper(kind)
		pillLabel.TextColor3 = meta.Color
		pillLabel.TextSize = 9
		pillLabel.AutomaticSize = Enum.AutomaticSize.X
		pillLabel.Size = UDim2.fromOffset(0, 12)
		pillLabel.LayoutOrder = 2
		pillLabel.ZIndex = Z.Content + 3
		pillLabel.Parent = pill
 
		local changeLabel = Instance.new("TextLabel")
		changeLabel.BackgroundTransparency = 1
		changeLabel.FontFace = BobloNEXT.Theme.FontRegular
		changeLabel.Text = tostring(change.Text or "")
		changeLabel.TextColor3 = BobloNEXT.Theme.TextDim
		changeLabel.TextSize = 12
		changeLabel.TextXAlignment = Enum.TextXAlignment.Left
		changeLabel.TextYAlignment = Enum.TextYAlignment.Top
		changeLabel.TextWrapped = true
		changeLabel.TextTruncate = Enum.TextTruncate.None
		changeLabel.AutomaticSize = Enum.AutomaticSize.Y
		changeLabel.Position = UDim2.fromOffset(76, 0)
		changeLabel.Size = UDim2.new(1, -76, 0, ROW_H)
		changeLabel.ZIndex = Z.Content + 2
		changeLabel.Parent = row
 
		local function alignChangelogRow()
			local isMultiline = changeLabel.TextBounds.Y > 18
			if isMultiline then
				pill.AnchorPoint = Vector2.zero
				pill.Position = UDim2.fromOffset(0, 1)
				changeLabel.TextYAlignment = Enum.TextYAlignment.Top
			else
				pill.AnchorPoint = Vector2.new(0, 0.5)
				pill.Position = UDim2.new(0, 0, 0.5, 0)
				changeLabel.TextYAlignment = Enum.TextYAlignment.Center
			end
		end
		changeLabel:GetPropertyChangedSignal("TextBounds"):Connect(alignChangelogRow)
		task.defer(alignChangelogRow)
 
		if i < #changes then
			local separator = Instance.new("Frame")
			separator.Name = "Separator" .. i
			separator.BackgroundColor3 = Color3.new(1, 1, 1)
			separator.BackgroundTransparency = 0.93
			separator.BorderSizePixel = 0
			separator.Size = UDim2.new(1, 0, 0, 1)
			separator.LayoutOrder = i * 2
			separator.ZIndex = Z.Content + 1
			separator.Parent = rowsHolder
		end
	end
 
	return { Instance = card, Destroy = function() card:Destroy() end }
end
 
function Tab:AddLoadoutGroup(opts)
	opts = opts or {}
	local title = opts.Title or "Loadout"
	local color = opts.Color or BobloNEXT.Theme.Accent
	local icons = opts.Icons or {}
	local buttonText = opts.ButtonText or "Equip"
 
	local PAD = 12
	local HEADER_H = 16
	local ICON_SIZE = 44
	local ROW_GAP = 8
	local BUTTON_H = 30
	local GAP1, GAP2 = 8, 10
	local height = PAD * 2 + HEADER_H + GAP1 + ICON_SIZE + GAP2 + BUTTON_H
 
	local card = BaseCard(self._page, height)
	self._window:_RegisterSearchable(self, title, card)
 
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, PAD)
	pad.PaddingBottom = UDim.new(0, PAD)
	pad.PaddingLeft = UDim.new(0, PAD)
	pad.PaddingRight = UDim.new(0, PAD)
	pad.Parent = card
 
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromOffset(0, 0)
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.ZIndex = Z.Content + 1
	header.Parent = card
 
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.new(0, 1, 0.5, 0)
	dot.Size = UDim2.fromOffset(6, 6)
	dot.BackgroundColor3 = color
	dot.BorderSizePixel = 0
	dot.ZIndex = Z.Content + 2
	dot.Parent = header
	Corner(dot, 3)
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = BobloNEXT.Theme.Font
	titleLabel.Text = string.upper(title)
	titleLabel.TextColor3 = BobloNEXT.Theme.TextDim
	titleLabel.TextSize = 12
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Position = UDim2.fromOffset(15, 0)
	titleLabel.Size = UDim2.new(1, -15, 1, 0)
	titleLabel.ZIndex = Z.Content + 2
	titleLabel.Parent = header
 
	local iconsRow = Instance.new("Frame")
	iconsRow.Name = "Icons"
	iconsRow.BackgroundTransparency = 1
	iconsRow.Position = UDim2.fromOffset(0, HEADER_H + GAP1)
	iconsRow.Size = UDim2.new(1, 0, 0, ICON_SIZE)
	iconsRow.ZIndex = Z.Content + 1
	iconsRow.Parent = card
 
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, ROW_GAP)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = iconsRow
 
	for i, iconAsset in ipairs(icons) do
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. i
		slot.BackgroundColor3 = Color3.new(1, 1, 1)
		slot.BackgroundTransparency = 0.95
		slot.BorderSizePixel = 0
		slot.ClipsDescendants = true
		slot.Size = UDim2.new(1 / 3, -ROW_GAP * 2 / 3, 1, 0)
		slot.LayoutOrder = i
		slot.ZIndex = Z.Content + 2
		slot.Parent = iconsRow
		Corner(slot, BobloNEXT.Theme.CornerRadiusSm)
		Stroke(slot, Color3.new(1, 1, 1), 1, 0.94)
 
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = ResolveIcon(iconAsset)
		img.ImageColor3 = color
		img.ScaleType = Enum.ScaleType.Fit
		img.Position = UDim2.fromOffset(8, 8)
		img.Size = UDim2.new(1, -16, 1, -16)
		img.ZIndex = Z.Content + 3
		img.Parent = slot
	end
 
	local btn = Instance.new("TextButton")
	btn.Name = "EquipButton"
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = Color3.new(1, 1, 1)
	btn.BackgroundTransparency = 0.92
	btn.BorderSizePixel = 0
	btn.Position = UDim2.fromOffset(0, HEADER_H + GAP1 + ICON_SIZE + GAP2)
	btn.Size = UDim2.new(1, 0, 0, BUTTON_H)
	btn.ZIndex = Z.Content + 1
	btn.Parent = card
	Corner(btn, 8)
 
	local btnLabel = Instance.new("TextLabel")
	btnLabel.BackgroundTransparency = 1
	btnLabel.FontFace = BobloNEXT.Theme.Font
	btnLabel.Text = buttonText
	btnLabel.TextColor3 = BobloNEXT.Theme.Text
	btnLabel.TextSize = 12
	btnLabel.Size = UDim2.fromScale(1, 1)
	btnLabel.ZIndex = Z.Content + 2
	btnLabel.Parent = btn
 
	btn.MouseEnter:Connect(function()
		Tween(btn, { BackgroundTransparency = 0.85 }, 0.12)
	end)
	btn.MouseLeave:Connect(function()
		Tween(btn, { BackgroundTransparency = 0.92 }, 0.12)
	end)
	btn.MouseButton1Click:Connect(function()
		Tween(btn, { BackgroundTransparency = 0.7 }, 0.08)
		task.delay(0.08, function()
			if btn.Parent then Tween(btn, { BackgroundTransparency = 0.85 }, 0.15) end
		end)
		if opts.Callback then task.spawn(opts.Callback) end
	end)
 
	return { Instance = card, Destroy = function() card:Destroy() end }
end
 
function Tab:AddInfoGrid(opts)
	opts = opts or {}
	local title = opts.Title or "Info"
	local hasDesc = opts.Description and opts.Description ~= ""
	local items = opts.Items or {}
	local color = opts.Color
	local columns = opts.Columns or 2
 
	local PAD = 12
	local HEADER_H = hasDesc and 32 or 16
	local CHIP_H = 38
	local GRID_GAP = 8
	local rows = math.ceil(#items / columns)
	local gridH = rows > 0 and (rows * CHIP_H + (rows - 1) * GRID_GAP) or 0
	local height = PAD * 2 + HEADER_H + (rows > 0 and (10 + gridH) or 0)
 
	local card = BaseCard(self._page, height)
	self._window:_RegisterSearchable(self, title, card)
 
	local leftInset = 0
	if color then
		local accent = Instance.new("Frame")
		accent.Name = "Accent"
		accent.BackgroundColor3 = color
		accent.BorderSizePixel = 0
		accent.Size = UDim2.new(0, 3, 1, -12)
		accent.Position = UDim2.fromOffset(0, 6)
		accent.ZIndex = Z.Content + 1
		accent.Parent = card
		Corner(accent, 1.5)
		leftInset = 6
	end
 
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, PAD)
	pad.PaddingBottom = UDim.new(0, PAD)
	pad.PaddingLeft = UDim.new(0, PAD + leftInset)
	pad.PaddingRight = UDim.new(0, PAD)
	pad.Parent = card
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = BobloNEXT.Theme.Font
	titleLabel.Text = title
	titleLabel.TextColor3 = BobloNEXT.Theme.Text
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Position = UDim2.fromOffset(0, 0)
	titleLabel.Size = UDim2.new(1, 0, 0, 16)
	titleLabel.ZIndex = Z.Content + 1
	titleLabel.Parent = card
 
	if hasDesc then
		local descLabel = Instance.new("TextLabel")
		descLabel.BackgroundTransparency = 1
		descLabel.FontFace = BobloNEXT.Theme.FontRegular
		descLabel.Text = opts.Description
		descLabel.TextColor3 = BobloNEXT.Theme.TextDim
		descLabel.TextSize = 12
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.Position = UDim2.fromOffset(0, 18)
		descLabel.Size = UDim2.new(1, 0, 0, 14)
		descLabel.ZIndex = Z.Content + 1
		descLabel.Parent = card
	end
 
	local chipValues = {}
 
	if rows > 0 then
		local grid = Instance.new("Frame")
		grid.Name = "Grid"
		grid.BackgroundTransparency = 1
		grid.Position = UDim2.fromOffset(0, HEADER_H + 10)
		grid.Size = UDim2.new(1, 0, 0, gridH)
		grid.ZIndex = Z.Content + 1
		grid.Parent = card
 
		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.CellPadding = UDim2.fromOffset(GRID_GAP, GRID_GAP)
		gridLayout.FillDirectionMaxCells = columns
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.Parent = grid
 
		local function relayout()
			local w = grid.AbsoluteSize.X / GetUIScale()
			if w <= 0 then return end
			local cellW = (w - GRID_GAP * (columns - 1)) / columns
			gridLayout.CellSize = UDim2.fromOffset(cellW, CHIP_H)
		end
		grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
		task.defer(relayout)
 
		for i, item in ipairs(items) do
			local chip = Instance.new("Frame")
			chip.Name = "Chip" .. i
			chip.BackgroundColor3 = Color3.new(1, 1, 1)
			chip.BackgroundTransparency = 0.95
			chip.BorderSizePixel = 0
			chip.LayoutOrder = i
			chip.ZIndex = Z.Content + 2
			chip.Parent = grid
			Corner(chip, 6)
 
			local chipPad = Instance.new("UIPadding")
			chipPad.PaddingTop = UDim.new(0, 6)
			chipPad.PaddingLeft = UDim.new(0, 8)
			chipPad.PaddingRight = UDim.new(0, 8)
			chipPad.Parent = chip
 
			local labelLabel = Instance.new("TextLabel")
			labelLabel.BackgroundTransparency = 1
			labelLabel.FontFace = BobloNEXT.Theme.Font
			labelLabel.Text = tostring(item.Label or "")
			labelLabel.TextColor3 = BobloNEXT.Theme.Text
			labelLabel.TextSize = 12
			labelLabel.TextXAlignment = Enum.TextXAlignment.Left
			labelLabel.TextTruncate = Enum.TextTruncate.AtEnd
			labelLabel.Size = UDim2.new(1, 0, 0, 15)
			labelLabel.ZIndex = Z.Content + 3
			labelLabel.Parent = chip
 
			local valueLabel = Instance.new("TextLabel")
			valueLabel.Name = "Value"
			valueLabel.BackgroundTransparency = 1
			valueLabel.FontFace = BobloNEXT.Theme.FontRegular
			valueLabel.Text = tostring(item.Value or "")
			valueLabel.TextColor3 = BobloNEXT.Theme.TextDim
			valueLabel.TextSize = 11
			valueLabel.TextXAlignment = Enum.TextXAlignment.Left
			valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
			valueLabel.Position = UDim2.fromOffset(0, 15)
			valueLabel.Size = UDim2.new(1, 0, 0, 12)
			valueLabel.ZIndex = Z.Content + 3
			valueLabel.Parent = chip
 
			if item.Label then chipValues[item.Label] = valueLabel end
		end
	end
 
	return {
		Instance = card,
		SetValue = function(_, label, value)
			local lbl = chipValues[label]
			if lbl then lbl.Text = tostring(value) end
		end,
		Destroy = function() card:Destroy() end,
	}
end
 
function Tab:AddSystemInfoGrid(opts)
	opts = opts or {}
	local Stats = game:GetService("Stats")
	local LocalPlayer = Players.LocalPlayer
 
	local runCount = BumpRunCount()
 
	local grid = self:AddInfoGrid({
		Title       = opts.Title or "System Info",
		Description = opts.Description,
		Color       = opts.Color,
		Columns     = opts.Columns or 2,
		Items = {
			{ Label = "FPS",           Value = "--" },
			{ Label = "Ping",          Value = "-- ms" },
			{ Label = "Executor",      Value = GetExecutorName() },
			{ Label = "Executions",    Value = tostring(runCount) },
			{ Label = "Server Region", Value = "Unknown" },
			{ Label = "Time of Day",   Value = "--:--" },
		},
	})
 
	local frames = 0
	local lastFpsUpdate = os.clock()
	self._janitor:Add(RunService.Heartbeat:Connect(function()
		frames = frames + 1
		local now = os.clock()
		local elapsed = now - lastFpsUpdate
		if elapsed >= 1 then
			grid:SetValue("FPS", math.floor(frames / elapsed + 0.5))
			frames = 0
			lastFpsUpdate = now
		end
	end))
 
	local alive = true
	self._janitor:Add(function() alive = false end)
 
	task.spawn(function()
		while alive and grid.Instance.Parent do
			pcall(function()
				local ping = 0
				pcall(function()
					ping = math.clamp(Stats.Network.ServerStatsItem["Data Ping"]:GetValue(), 0, 9999)
				end)
				grid:SetValue("Ping", math.floor(ping) .. " ms")
 
				local h = tonumber(os.date("%H"))
				local m = tonumber(os.date("%M"))
				grid:SetValue("Time of Day", FormatClock(h * 60 + m))
			end)
			task.wait(1)
		end
	end)
 
	task.spawn(function()
		local ok, region = pcall(function()
			return game:GetService("LocalizationService"):GetCountryRegionForPlayerAsync(LocalPlayer)
		end)
		if ok and region and alive then grid:SetValue("Server Region", region) end
	end)
 
	return grid
end
 
function Tab:AddActiveUsersGrid(opts)
	opts = opts or {}
	local service = opts.Service
	local interval = opts.Interval or 30
 
	local grid = self:AddInfoGrid({
		Title       = opts.Title or "Active Users",
		Description = opts.Description,
		Color       = opts.Color,
		Columns     = 1,
		Items = { { Label = "Active Now", Value = "--" } },
	})
 
	if not service then
		grid:SetValue("Active Now", "No Service configured")
		return grid
	end
 
	local alive = true
	self._janitor:Add(function() alive = false end)
 
	task.spawn(function()
		while alive and grid.Instance.Parent do
			service:Heartbeat()
			local count, err = service:GetActiveCount()
			if alive and grid.Instance.Parent then
				grid:SetValue("Active Now", count and tostring(count) or ("Error: " .. tostring(err)))
			end
			task.wait(interval)
		end
	end)
 
	return grid
end
 
function Tab:AddLeaderboard(opts)
	opts = opts or {}
	local jan = self._janitor
	local service = opts.Service
	local interval = opts.Interval or 30
	local limit = math.clamp(opts.Limit or 5, 1, 50)
	local title = opts.Title or "Leaderboard"
	local hasDesc = opts.Description and opts.Description ~= ""
 
	local PAD = 12
	local HEADER_H = hasDesc and 32 or 16
	local ROW_H, ROW_GAP = 44, 6
	local listY = PAD + HEADER_H + 12
	local listH = limit * ROW_H + (limit - 1) * ROW_GAP
	local totalHeight = listY + listH + PAD
 
	local container = Instance.new("Frame")
	container.Name = "Leaderboard"
	container.BackgroundColor3 = BobloNEXT.Theme.Surface
	container.BackgroundTransparency = 0.35
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Size = UDim2.new(1, 0, 0, totalHeight)
	container.ZIndex = Z.Content
	container.Parent = self._page
	Corner(container, BobloNEXT.Theme.CornerRadiusSm)
	Stroke(container, Color3.new(1, 1, 1), 1, 0.92)
	self._window:_RegisterSearchable(self, title, container)
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = BobloNEXT.Theme.Font
	titleLabel.Text = title
	titleLabel.TextColor3 = BobloNEXT.Theme.Text
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Position = UDim2.fromOffset(PAD, PAD)
	titleLabel.Size = UDim2.new(1, -PAD * 2 - 32, 0, 16)
	titleLabel.ZIndex = Z.Content + 1
	titleLabel.Parent = container
 
	if hasDesc then
		local descLabel = Instance.new("TextLabel")
		descLabel.BackgroundTransparency = 1
		descLabel.FontFace = BobloNEXT.Theme.FontRegular
		descLabel.Text = opts.Description
		descLabel.TextColor3 = BobloNEXT.Theme.TextDim
		descLabel.TextSize = 12
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.Position = UDim2.fromOffset(PAD, PAD + 18)
		descLabel.Size = UDim2.new(1, -PAD * 2 - 32, 0, 14)
		descLabel.ZIndex = Z.Content + 1
		descLabel.Parent = container
	end
 
	local revealMe = opts.RevealByDefault == true
 
	local revealBtn = Instance.new("TextButton")
	revealBtn.Name = "RevealToggle"
	revealBtn.Text = ""
	revealBtn.AutoButtonColor = false
	revealBtn.BackgroundColor3 = Color3.new(1, 1, 1)
	revealBtn.BackgroundTransparency = 1
	revealBtn.BorderSizePixel = 0
	revealBtn.AnchorPoint = Vector2.new(1, 0)
	revealBtn.Position = UDim2.new(1, -PAD, 0, PAD - 4)
	revealBtn.Size = UDim2.fromOffset(24, 24)
	revealBtn.ZIndex = Z.Content + 2
	revealBtn.Parent = container
	Corner(revealBtn, 7)
 
	local revealIcon = Instance.new("ImageLabel")
	revealIcon.BackgroundTransparency = 1
	revealIcon.Image = ResolveIcon(revealMe and "eye" or "eye-off")
	revealIcon.ImageColor3 = BobloNEXT.Theme.TextDim
	revealIcon.Size = UDim2.fromOffset(14, 14)
	revealIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	revealIcon.Position = UDim2.fromScale(0.5, 0.5)
	revealIcon.ZIndex = Z.Content + 3
	revealIcon.Parent = revealBtn
 
	jan:Add(revealBtn.MouseEnter:Connect(function()
		Tween(revealBtn, { BackgroundTransparency = 0.9 }, 0.12)
		Tween(revealIcon, { ImageColor3 = BobloNEXT.Theme.Text }, 0.12)
	end))
	jan:Add(revealBtn.MouseLeave:Connect(function()
		Tween(revealBtn, { BackgroundTransparency = 1 }, 0.12)
		Tween(revealIcon, { ImageColor3 = BobloNEXT.Theme.TextDim }, 0.12)
	end))
 
	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = Color3.new(1, 1, 1)
	divider.BackgroundTransparency = 0.92
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromOffset(0, PAD + HEADER_H + 8)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.ZIndex = Z.Content + 1
	divider.Parent = container
 
	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(PAD, listY)
	list.Size = UDim2.new(1, -PAD * 2, 0, listH)
	list.ZIndex = Z.Content + 1
	list.Parent = container
 
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, ROW_GAP)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list
 
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.FontFace = BobloNEXT.Theme.FontRegular
	emptyLabel.Text = "No one's run this yet"
	emptyLabel.TextColor3 = BobloNEXT.Theme.TextDim
	emptyLabel.TextSize = 12
	emptyLabel.Position = UDim2.fromOffset(PAD, listY + 10)
	emptyLabel.Size = UDim2.new(1, -PAD * 2, 0, 16)
	emptyLabel.Visible = false
	emptyLabel.ZIndex = Z.Content + 1
	emptyLabel.Parent = container
 
	local RANK_COLORS = {
		[1] = Color3.fromRGB(255, 196, 64),
		[2] = Color3.fromRGB(203, 209, 217),
		[3] = Color3.fromRGB(205, 141, 92),
	}
	local RANK_ICONS = { [1] = "crown", [2] = "medal", [3] = "medal" }
 
	local function formatSeconds(total)
		total = math.floor(total or 0)
		local h = math.floor(total / 3600)
		local m = math.floor((total % 3600) / 60)
		if h > 0 then return string.format("%dh %dm", h, m) end
		if m > 0 then return string.format("%dm", m) end
		return string.format("%ds", total)
	end
 
	local function fallbackLabel(identity)
		local tag = (identity or ""):gsub("-", ""):sub(1, 4):upper()
		return "Player-" .. (tag ~= "" and tag or "????")
	end
 
	local rowFrames = {}
	local function clearRows()
		for _, f in ipairs(rowFrames) do f:Destroy() end
		table.clear(rowFrames)
	end
 
	local function buildRow(index, item)
		local rankColor = RANK_COLORS[index]
 
		local row = Instance.new("Frame")
		row.Name = "Row" .. index
		row.Active = true
		row.BackgroundColor3 = Color3.new(1, 1, 1)
		row.BackgroundTransparency = item.IsYou and 0.9 or 0.96
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.ZIndex = Z.Content + 2
		row.Parent = list
		Corner(row, BobloNEXT.Theme.CornerRadiusSm)
		Stroke(row, Color3.new(1, 1, 1), 1, item.IsYou and 0.88 or 0.94)
 
		local baseTransparency = row.BackgroundTransparency
		row.MouseEnter:Connect(function() Tween(row, { BackgroundTransparency = baseTransparency - 0.05 }, 0.12) end)
		row.MouseLeave:Connect(function() Tween(row, { BackgroundTransparency = baseTransparency }, 0.12) end)
 
		local rowPad = Instance.new("UIPadding")
		rowPad.PaddingLeft = UDim.new(0, 10)
		rowPad.PaddingRight = UDim.new(0, 10)
		rowPad.Parent = row
 
		local badge = Instance.new("Frame")
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(0, 0, 0.5, 0)
		badge.Size = UDim2.fromOffset(28, 28)
		badge.BackgroundColor3 = Color3.new(1, 1, 1)
		badge.BackgroundTransparency = 0.94
		badge.BorderSizePixel = 0
		badge.ZIndex = Z.Content + 3
		badge.Parent = row
		Corner(badge, 14)
		Stroke(badge, Color3.new(1, 1, 1), 1, 0.9)
 
		if rankColor then
			local badgeIcon = Instance.new("ImageLabel")
			badgeIcon.BackgroundTransparency = 1
			badgeIcon.Image = ResolveIcon(RANK_ICONS[index])
			badgeIcon.ImageColor3 = rankColor
			badgeIcon.Size = UDim2.fromOffset(15, 15)
			badgeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			badgeIcon.Position = UDim2.fromScale(0.5, 0.5)
			badgeIcon.ZIndex = Z.Content + 4
			badgeIcon.Parent = badge
		else
			local badgeLabel = Instance.new("TextLabel")
			badgeLabel.BackgroundTransparency = 1
			badgeLabel.FontFace = BobloNEXT.Theme.Font
			badgeLabel.Text = "#" .. tostring(index)
			badgeLabel.TextColor3 = BobloNEXT.Theme.TextDim
			badgeLabel.TextSize = 11
			badgeLabel.Size = UDim2.fromScale(1, 1)
			badgeLabel.ZIndex = Z.Content + 4
			badgeLabel.Parent = badge
		end
 
		local avatarHolder = Instance.new("Frame")
		avatarHolder.AnchorPoint = Vector2.new(0, 0.5)
		avatarHolder.Position = UDim2.new(0, 34, 0.5, 0)
		avatarHolder.Size = UDim2.fromOffset(28, 28)
		avatarHolder.BackgroundColor3 = Color3.new(1, 1, 1)
		avatarHolder.BackgroundTransparency = 0.94
		avatarHolder.BorderSizePixel = 0
		avatarHolder.ClipsDescendants = true
		avatarHolder.ZIndex = Z.Content + 3
		avatarHolder.Parent = row
		Corner(avatarHolder, 14)
		Stroke(avatarHolder, Color3.new(1, 1, 1), 1, 0.85)
 
		if item.UserId and item.UserId ~= 0 then
			local avatarImg = Instance.new("ImageLabel")
			avatarImg.BackgroundTransparency = 1
			avatarImg.ScaleType = Enum.ScaleType.Crop
			avatarImg.Size = UDim2.fromScale(1, 1)
			avatarImg.ZIndex = Z.Content + 4
			avatarImg.Parent = avatarHolder
			task.spawn(function()
				local ok, content = pcall(
					Players.GetUserThumbnailAsync,
					Players,
					item.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size48x48
				)
				if ok and content and avatarImg.Parent then
					avatarImg.Image = content
				end
			end)
		else
			local placeholder = Instance.new("ImageLabel")
			placeholder.BackgroundTransparency = 1
			placeholder.Image = ResolveIcon("user")
			placeholder.ImageColor3 = BobloNEXT.Theme.TextDim
			placeholder.Size = UDim2.fromOffset(14, 14)
			placeholder.AnchorPoint = Vector2.new(0.5, 0.5)
			placeholder.Position = UDim2.fromScale(0.5, 0.5)
			placeholder.ZIndex = Z.Content + 4
			placeholder.Parent = avatarHolder
		end
 
		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.FontFace = BobloNEXT.Theme.Font
		nameLabel.Text = (item.NamePreview and item.NamePreview ~= "" and item.NamePreview or fallbackLabel(item.Identity))
			.. (item.IsYou and "  (You)" or "")
		nameLabel.TextColor3 = BobloNEXT.Theme.Text
		nameLabel.TextSize = 13
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Position = UDim2.fromOffset(70, 0)
		nameLabel.Size = UDim2.new(1, -70 - 68, 1, 0)
		nameLabel.ZIndex = Z.Content + 3
		nameLabel.Parent = row
 
		local timeLabel = Instance.new("TextLabel")
		timeLabel.BackgroundTransparency = 1
		timeLabel.FontFace = BobloNEXT.Theme.FontRegular
		timeLabel.Text = formatSeconds(item.Seconds)
		timeLabel.TextColor3 = BobloNEXT.Theme.TextDim
		timeLabel.TextSize = 12
		timeLabel.TextXAlignment = Enum.TextXAlignment.Right
		timeLabel.AnchorPoint = Vector2.new(1, 0)
		timeLabel.Position = UDim2.new(1, 0, 0, 0)
		timeLabel.Size = UDim2.fromOffset(60, ROW_H)
		timeLabel.ZIndex = Z.Content + 3
		timeLabel.Parent = row
 
		return row
	end
 
	local function renderRows(items)
		clearRows()
		emptyLabel.Visible = #items == 0
 
		for i, item in ipairs(items) do
			if i > limit then break end
			table.insert(rowFrames, buildRow(i, item))
		end
	end
 
	renderRows({})
 
	if not service then
		return { Instance = container }
	end
 
	local function maskName(letters, stars)
		local name = LocalPlayer.Name or ""
		return name:sub(1, letters) .. stars
	end
 
	jan:Add(revealBtn.MouseButton1Click:Connect(function()
		revealMe = not revealMe
		revealIcon.Image = ResolveIcon(revealMe and "eye" or "eye-off")
		BobloNEXT:Notify({
			Title = "Leaderboard",
			Text  = revealMe
				and "Your avatar and more of your name will show on the leaderboard."
				or "Back to anonymous -- only 2 letters of your name will show.",
			Type  = "info",
			Duration = 3,
		})
	end))
 
	local alive = true
	jan:Add(function() alive = false end)
 
	task.spawn(function()
		while alive and container.Parent do
			local payload = revealMe
				and { UserId = LocalPlayer.UserId, NamePreview = maskName(4, "*******") }
				or { UserId = 0, NamePreview = maskName(2, "********") }
			service:Heartbeat(payload)
 
			local items, err = service:GetLeaderboard(limit)
			if alive and container.Parent and items then
				for _, item in ipairs(items) do
					item.IsYou = item.Identity == service.Identity
				end
				renderRows(items)
			end
			task.wait(interval)
		end
	end)
 
	return { Instance = container }
end
 
function Tab:AddGradientCard(opts)
	opts = opts or {}
	local title = opts.Title or "Card"
	local hasDesc = opts.Description and opts.Description ~= ""
	local colorA = opts.ColorA or Color3.fromRGB(88, 101, 242)
	local colorB = opts.ColorB or Color3.fromRGB(52, 58, 138)
	local height = hasDesc and 56 or 44
 
	local card = Instance.new("Frame")
	card.Name = title .. "GradientCard"
	card.BackgroundColor3 = colorA
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, height)
	card.ZIndex = Z.Content
	card.Parent = self._page
	Corner(card, BobloNEXT.Theme.CornerRadiusSm)
 
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(colorA, colorB)
	gradient.Rotation = 100
	gradient.Parent = card
 
	self._window:_RegisterSearchable(self, title, card)
 
	local PAD = 14
	local rightReserve = opts.Callback and 32 or PAD
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = BobloNEXT.Theme.Font
	titleLabel.Text = title
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Position = UDim2.fromOffset(PAD, hasDesc and 9 or 0)
	titleLabel.Size = UDim2.new(1, -(PAD + rightReserve), 0, 18)
	titleLabel.ZIndex = Z.Content + 1
	titleLabel.Parent = card
 
	if hasDesc then
		local descLabel = Instance.new("TextLabel")
		descLabel.BackgroundTransparency = 1
		descLabel.FontFace = BobloNEXT.Theme.FontRegular
		descLabel.Text = opts.Description
		descLabel.TextColor3 = Color3.new(1, 1, 1)
		descLabel.TextTransparency = 0.3
		descLabel.TextSize = 12
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextTruncate = Enum.TextTruncate.AtEnd
		descLabel.Position = UDim2.fromOffset(PAD, 29)
		descLabel.Size = UDim2.new(1, -(PAD + rightReserve), 0, 14)
		descLabel.ZIndex = Z.Content + 1
		descLabel.Parent = card
	end
 
	if opts.Callback then
		local chev = Instance.new("ImageLabel")
		chev.BackgroundTransparency = 1
		chev.Image = ResolveIcon("chevron-right")
		chev.ImageColor3 = Color3.new(1, 1, 1)
		chev.ImageTransparency = 0.2
		chev.Size = UDim2.fromOffset(14, 14)
		chev.AnchorPoint = Vector2.new(1, 0.5)
		chev.Position = UDim2.new(1, -14, 0.5, 0)
		chev.ZIndex = Z.Content + 1
		chev.Parent = card
 
		local veil = Instance.new("Frame")
		veil.Name = "HoverVeil"
		veil.BackgroundColor3 = Color3.new(1, 1, 1)
		veil.BackgroundTransparency = 1
		veil.BorderSizePixel = 0
		veil.Size = UDim2.fromScale(1, 1)
		veil.ZIndex = Z.Content + 2
		veil.Parent = card
		Corner(veil, BobloNEXT.Theme.CornerRadiusSm)
 
		local click = Instance.new("TextButton")
		click.Text = ""
		click.AutoButtonColor = false
		click.BackgroundTransparency = 1
		click.Size = UDim2.fromScale(1, 1)
		click.ZIndex = Z.Content + 3
		click.Parent = card
 
		click.MouseEnter:Connect(function()
			Tween(veil, { BackgroundTransparency = 0.9 }, 0.15)
			Tween(chev, { Position = UDim2.new(1, -10, 0.5, 0) }, 0.15)
		end)
		click.MouseLeave:Connect(function()
			Tween(veil, { BackgroundTransparency = 1 }, 0.15)
			Tween(chev, { Position = UDim2.new(1, -14, 0.5, 0) }, 0.15)
		end)
		click.MouseButton1Click:Connect(function()
			Tween(veil, { BackgroundTransparency = 0.8 }, 0.08)
			task.delay(0.08, function()
				if veil.Parent then Tween(veil, { BackgroundTransparency = 0.9 }, 0.15) end
			end)
			task.spawn(opts.Callback)
		end)
	end
 
	return { Instance = card, Destroy = function() card:Destroy() end }
end
 
function Tab:AddToggle(opts)
	opts = opts or {}
	local state = opts.Default == true
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local card = BaseCard(self._page, height)
 
	local textX = AddLeadingIcon(card, opts.Icon, height)
	AddTitleDesc(card, textX, 66, opts.Text or "Toggle", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Toggle", card)
 
	local switchBg = Instance.new("Frame")
	switchBg.AnchorPoint = Vector2.new(1, 0.5)
	switchBg.Position = UDim2.new(1, -14, 0.5, 0)
	switchBg.Size = UDim2.fromOffset(40, 22)
	switchBg.BackgroundColor3 = state and BobloNEXT.Theme.Accent or BobloNEXT.Theme.SurfaceHigh
	switchBg.BackgroundTransparency = state and 0 or 0.32
	switchBg.BorderSizePixel = 0
	switchBg.ZIndex = Z.Content + 1
	switchBg.Parent = card
	Corner(switchBg, 11)
 
	-- The disabled state stays translucent so the window background remains visible
	-- through the control instead of turning into a flat gray pill.
	local switchStroke = Stroke(
		switchBg,
		state and BobloNEXT.Theme.AccentSoft or BobloNEXT.Theme.Neutral,
		1,
		state and 0.88 or 0.72
	)
 
	local switchGradient = Instance.new("UIGradient")
	switchGradient.Rotation = 90
	switchGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, BobloNEXT.Theme.AccentSoft),
		ColorSequenceKeypoint.new(1, BobloNEXT.Theme.Accent),
	})
	switchGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, state and 0 or 0.76),
		NumberSequenceKeypoint.new(1, state and 0 or 0.94),
	})
	switchGradient.Parent = switchBg
 
	local switchScale = Instance.new("UIScale")
	switchScale.Scale = 1
	switchScale.Parent = switchBg
 
	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(16, 16)
	knob.Position = state and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.BackgroundColor3 = state and BobloNEXT.Theme.OnAccent or BobloNEXT.Theme.TextSoft
	knob.BackgroundTransparency = state and 0 or 0.06
	knob.BorderSizePixel = 0
	knob.ZIndex = Z.Content + 2
	knob.Parent = switchBg
	Corner(knob, 8)
 
	ThemeBind(switchBg, "BackgroundColor3", function(theme)
		return state and theme.Accent or theme.SurfaceHigh
	end)
	ThemeBind(switchStroke, "Color", function(theme)
		return state and theme.AccentSoft or theme.Neutral
	end)
	ThemeBind(switchGradient, "Color", function(theme)
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, theme.AccentSoft),
			ColorSequenceKeypoint.new(1, theme.Accent),
		})
	end)
	ThemeBind(knob, "BackgroundColor3", function(theme)
		return state and theme.OnAccent or theme.TextSoft
	end)

	local click = Instance.new("TextButton")
	click.Text = ""
	click.AutoButtonColor = false
	click.BackgroundTransparency = 1
	click.Size = UDim2.fromScale(1, 1)
	click.ZIndex = Z.Content + 3
	click.Parent = card
 
	local function render()
		local anim = 0.28
		local style, dir = Enum.EasingStyle.Quint, Enum.EasingDirection.InOut
		Tween(switchBg, {
			BackgroundColor3 = state and BobloNEXT.Theme.Accent or BobloNEXT.Theme.SurfaceHigh,
			BackgroundTransparency = state and 0 or 0.32,
		}, anim, style, dir)
		Tween(switchStroke, {
			Color = state and BobloNEXT.Theme.AccentSoft or BobloNEXT.Theme.Neutral,
			Transparency = state and 0.88 or 0.72,
		}, anim, style, dir)
		switchGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, state and 0 or 0.76),
			NumberSequenceKeypoint.new(1, state and 0 or 0.94),
		})
		Tween(knob, {
			BackgroundColor3 = state and BobloNEXT.Theme.OnAccent or BobloNEXT.Theme.TextSoft,
			BackgroundTransparency = state and 0 or 0.06,
			Position = state and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
		}, anim, style, dir)
	end
 
	local signal = MakeSignal()
	local function fireChanged(newState)
		if opts.Callback then task.spawn(opts.Callback, newState) end
		signal.Fire(newState)
	end
 
	local locked = opts.Locked == true
	click.MouseButton1Click:Connect(function()
		if locked then return end
		Tween(switchScale, { Scale = 0.91 }, 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(0.08, function()
			if switchScale.Parent then
				Tween(switchScale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			end
		end)
		state = not state
		render()
		fireChanged(state)
	end)
 
	card.MouseEnter:Connect(function()
		if not locked then
			Tween(card, { BackgroundTransparency = 0.93 }, 0.15)
			if not state then
				Tween(switchStroke, { Transparency = 0.55 }, 0.15)
				Tween(switchBg, { BackgroundTransparency = 0.24 }, 0.15)
			end
		end
	end)
	card.MouseLeave:Connect(function()
		Tween(card, { BackgroundTransparency = 0.96 }, 0.15)
		if not state then
			Tween(switchStroke, { Transparency = 0.72 }, 0.15)
			Tween(switchBg, { BackgroundTransparency = 0.32 }, 0.15)
		end
	end)
 
	return RegisterFlag(opts, {
		Instance = card,
		Set = function(_, value, silent)
			state = value == true
			render()
			if not silent then fireChanged(state) end
		end,
		Get = function() return state end,
		SetLocked = function(_, v)
			locked = v == true
			card.BackgroundTransparency = locked and 0.98 or 0.96
		end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function() signal.Clear(); card:Destroy() end,
	}, "Toggle")
end
 
local ActiveSliderOwner = nil
 
function Tab:AddSlider(opts)
	opts = opts or {}
	local min = tonumber(opts.Min) or 0
	local max = tonumber(opts.Max) or 100
	if max < min then min, max = max, min end
	local increment = tonumber(opts.Increment) or 1
	local value = math.clamp(tonumber(opts.Default) or min, min, max)
 
	local hasDesc = opts.Description and opts.Description ~= ""
	local jan = self._janitor
 
	local card = BaseCard(self._page, hasDesc and 76 or 56)
	local textX = AddLeadingIcon(card, opts.Icon, 24)
	local leadingIcon = card:FindFirstChild("LeadingIcon")
	if leadingIcon then
		leadingIcon.AnchorPoint = Vector2.new(0, 0)
		leadingIcon.Position = UDim2.fromOffset(14, 9)
	end
 
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = BobloNEXT.Theme.Font
	label.Text = opts.Text or "Slider"
	label.TextColor3 = BobloNEXT.Theme.Text
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Position = UDim2.fromOffset(textX, 8)
	label.Size = UDim2.new(1, -(textX + 76), 0, 18)
	label.ZIndex = Z.Content + 1
	label.Parent = card
	self._window:_RegisterSearchable(self, opts.Text or "Slider", card)
 
	local descLabel
	if hasDesc then
		descLabel = Instance.new("TextLabel")
		descLabel.BackgroundTransparency = 1
		descLabel.FontFace = BobloNEXT.Theme.FontRegular
		descLabel.Text = opts.Description
		descLabel.TextColor3 = BobloNEXT.Theme.TextDim
		descLabel.TextSize = 12
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.AutomaticSize = Enum.AutomaticSize.Y
		descLabel.Position = UDim2.fromOffset(textX, 26)
		descLabel.Size = UDim2.new(1, -(textX + 14), 0, 14)
		descLabel.ZIndex = Z.Content + 1
		descLabel.Parent = card
	end
 
	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.FontFace = BobloNEXT.Theme.FontRegular
	valueLabel.Text = FormatNumber(value) .. (opts.Suffix or "")
	valueLabel.TextColor3 = BobloNEXT.Theme.TextDim
	valueLabel.TextSize = 13
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.AnchorPoint = Vector2.new(1, 0)
	valueLabel.Position = UDim2.new(1, -14, 0, 8)
	valueLabel.Size = UDim2.fromOffset(62, 18)
	valueLabel.ZIndex = Z.Content + 1
	valueLabel.Parent = card
 
	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 14, 1, -20)
	track.Size = UDim2.new(1, -28, 0, 6)
	-- Nearly transparent white overlay: no gray tint, so the window background
	-- remains visible through the unfilled portion of the slider.
	ThemeBind(track, "BackgroundColor3", "SurfaceHigh")
	track.BackgroundTransparency = 0.91
	track.BorderSizePixel = 0
	track.ZIndex = Z.Content + 1
	track.Parent = card
	Corner(track, 3)
 
	local fill = Instance.new("Frame")
	ThemeBind(fill, "BackgroundColor3", "Accent")
	fill.BackgroundTransparency = 0
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(SafeAlpha(value, min, max), 0, 1, 0)
	fill.ZIndex = Z.Content + 2
	fill.Parent = track
	Corner(fill, 3)
 
	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new(SafeAlpha(value, min, max), 0, 0.5, 0)
	knob.Size = UDim2.fromOffset(12, 12)
	ThemeBind(knob, "BackgroundColor3", "AccentSoft")
	knob.BackgroundTransparency = 0
	knob.BorderSizePixel = 0
	knob.ZIndex = Z.Content + 3
	knob.Parent = track
	Corner(knob, 6)
	local knobStroke = Stroke(knob, BobloNEXT.Theme.Background, 2, 0)
	ThemeBind(knobStroke, "Color", "Background")
 
	if hasDesc then
		local lastW = -1
		local function relayout()
			local w = card.AbsoluteSize.X / GetUIScale()
			if w <= 0 or math.abs(w - lastW) < 1 then return end
			lastW = w
			local _, h = MeasureText(opts.Description, 12, math.max(w - textX - 14, 40))
			card.Size = UDim2.new(1, 0, 0, math.max(76, 26 + h + 8 + 20))
		end
		card:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
		task.defer(relayout)
	end
 
	local function setVisual(alpha, animated, duration)
		if animated then
			Tween(fill, { Size = UDim2.new(alpha, 0, 1, 0) }, duration or 0.16)
			Tween(knob, { Position = UDim2.new(alpha, 0, 0.5, 0) }, duration or 0.16)
		else
			fill.Size = UDim2.new(alpha, 0, 1, 0)
			knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		end
	end
 
	local targetAlpha = SafeAlpha(value, min, max)
	local visualAlpha = targetAlpha
 
	local signal = MakeSignal()
	local function fireChanged(v)
		if opts.Callback then task.spawn(opts.Callback, v) end
		signal.Fire(v)
	end
 
	local function setValueLabel()
		valueLabel.Text = FormatNumber(value) .. (opts.Suffix or "")
	end
 
	local function moveTo(newValue, animated)
		value = math.clamp(newValue, min, max)
		local alpha = SafeAlpha(value, min, max)
		targetAlpha = alpha
		visualAlpha = alpha
		setValueLabel()
		setVisual(alpha, animated ~= false, 0.18)
	end
 
	local dragging = false
	local sliderInput = nil
	local sliderOwner = {}
	local followConn = nil
 
	local function updateFromX(xPos)
		if track.AbsoluteSize.X <= 0 then return end
		targetAlpha = math.clamp((xPos - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local raw = min + targetAlpha * (max - min)
		local newValue = SnapToIncrement(raw, min, max, increment)
		if newValue ~= value then
			value = newValue
			setValueLabel()
			fireChanged(value)
		end
	end
 
	local SLIDER_SMOOTH = 22
 
	local function stopFollow()
		if followConn then
			followConn:Disconnect()
			followConn = nil
		end
	end
 
	local function releaseSlider()
		if ActiveSliderOwner == sliderOwner then ActiveSliderOwner = nil end
		dragging = false
		sliderInput = nil
		stopFollow()
	end
	jan:Add(releaseSlider)
	jan:Add(card.Destroying:Connect(releaseSlider))
	jan:Add(UserInputService.WindowFocusReleased:Connect(releaseSlider))
 
	local hitBox = Instance.new("TextButton")
	hitBox.Name = "SliderHitBox"
	hitBox.Text = ""
	hitBox.AutoButtonColor = false
	hitBox.BackgroundTransparency = 1
	hitBox.AnchorPoint = Vector2.new(0.5, 0.5)
	hitBox.Position = UDim2.fromScale(0.5, 0.5)
	hitBox.Size = UDim2.new(1, 8, 0, 26)
	hitBox.ZIndex = Z.Content + 4
	hitBox.Parent = track
 
	jan:Add(hitBox.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if dragging or ActiveSliderOwner ~= nil then return end
		ActiveSliderOwner = sliderOwner
		dragging = true
		sliderInput = input
		updateFromX(input.Position.X)
 
		stopFollow()
		followConn = RunService.RenderStepped:Connect(function(dt)
			if not track.Parent then stopFollow() return end
			local a = 1 - math.exp(-SLIDER_SMOOTH * dt)
			visualAlpha = visualAlpha + (targetAlpha - visualAlpha) * a
			if math.abs(targetAlpha - visualAlpha) < 0.001 then
				visualAlpha = targetAlpha
			end
			setVisual(visualAlpha, false)
		end)
		jan:Add(followConn)
	end))
 
	jan:Add(UserInputService.InputChanged:Connect(function(input)
		if not dragging or ActiveSliderOwner ~= sliderOwner then return end
		if input == sliderInput
			or (sliderInput and sliderInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement) then
			updateFromX(input.Position.X)
		end
	end))
 
	jan:Add(UserInputService.InputEnded:Connect(function(input)
		if not dragging or ActiveSliderOwner ~= sliderOwner then return end
		if input ~= sliderInput
			and not (sliderInput and sliderInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1) then
			return
		end
		releaseSlider()
		targetAlpha = SafeAlpha(value, min, max)
		visualAlpha = targetAlpha
		setVisual(targetAlpha, true, 0.12)
	end))
 
	return RegisterFlag(opts, {
		Instance = card,
		Set = function(_, v, silent)
			moveTo(SnapToIncrement(tonumber(v) or min, min, max, increment), true)
			if not silent then fireChanged(value) end
		end,
		Get = function() return value end,
		SetRange = function(_, newMin, newMax)
			min, max = newMin, newMax
			moveTo(math.clamp(value, min, max), true)
		end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function() stopFollow(); signal.Clear(); card:Destroy() end,
	}, "Slider")
end
 
local function ComputePopupPosition(window, card, w, h)
	local s = GetUIScale()
	local realW, realH = w * s, h * s
 
	local view = ViewportSize()
	local winPos = window.AbsolutePosition
	local winSize = window.AbsoluteSize
	local cardPos = card.AbsolutePosition
 
	local px = winPos.X + winSize.X + 12
	if px + realW > view.X - 8 then
		px = winPos.X - realW - 12
	end
	px = SafeClamp(px, 8, view.X - realW - 8)
 
	local py = cardPos.Y - realH - 8
	py = SafeClamp(py, winPos.Y + 8, winPos.Y + winSize.Y - realH - 8)
	py = SafeClamp(py, 8, view.Y - realH - 8)
 
	return math.round(px / s), math.round(py / s)
end
 
function Tab:AddDropdown(opts)
	opts = opts or {}
	local options = opts.Options or {}
	local isMulti = opts.MultiSelect == true
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local jan = self._janitor
 
	local selected
	if isMulti then
		selected = {}
		if type(opts.Default) == "table" then
			for _, v in ipairs(opts.Default) do selected[v] = true end
		end
	else
		selected = opts.Default or options[1]
	end
 
	local signal = MakeSignal()
	local function fireChanged(newValue)
		if opts.Callback then task.spawn(opts.Callback, newValue) end
		signal.Fire(newValue)
	end
 
	local function getSelectedList()
		local list = {}
		for _, name in ipairs(options) do
			if isMulti and selected[name] then table.insert(list, name) end
		end
		return list
	end
 
	local function isOptionSelected(name)
		if isMulti then return selected[name] == true end
		return name == selected
	end
 
	local function formatValue()
		if isMulti then
			local list = getSelectedList()
			if #list == 0 then return "None" end
			if #list == 1 then return list[1] end
			return #list .. " selected"
		end
		return tostring(selected or "None")
	end
 
	local card = BaseCard(self._page, height)
	local textX = AddLeadingIcon(card, opts.Icon, height)
 
	AddTitleDesc(card, textX, 166, opts.Text or "Dropdown", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Dropdown", card)
 
	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.FontFace = BobloNEXT.Theme.FontRegular
	valueLabel.Text = formatValue()
	ThemeBind(valueLabel, "TextColor3", "TextDim")
	valueLabel.TextSize = 13
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.AnchorPoint = Vector2.new(1, 0.5)
	valueLabel.Position = UDim2.new(1, -34, 0.5, 0)
	valueLabel.Size = UDim2.fromOffset(120, height)
	valueLabel.ZIndex = Z.Content + 1
	valueLabel.Parent = card
 
	local chevron = Instance.new("ImageLabel")
	chevron.BackgroundTransparency = 1
	chevron.Image = ResolveIcon("chevron-down")
	ThemeBind(chevron, "ImageColor3", "TextDim")
	chevron.Size = UDim2.fromOffset(14, 14)
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.new(1, -14, 0.5, 0)
	chevron.ZIndex = Z.Content + 1
	chevron.Parent = card
 
	local click = Instance.new("TextButton")
	click.Text = ""
	click.AutoButtonColor = false
	click.BackgroundTransparency = 1
	click.Size = UDim2.fromScale(1, 1)
	click.ZIndex = Z.Content + 3
	click.Parent = card
 
	local popupOpen = false
	local popupFrame, popupBackdrop, followConn, scrollConn
	local optionButtons = {}
 
	local function closePopup()
		if not popupOpen then return end
		popupOpen = false
		RegisterPopupClose(closePopup)
		Tween(chevron, { Rotation = 0 }, 0.15)
 
		if followConn then followConn:Disconnect(); followConn = nil end
		if scrollConn then scrollConn:Disconnect(); scrollConn = nil end
		table.clear(optionButtons)
 
		if popupBackdrop then popupBackdrop:Destroy(); popupBackdrop = nil end
 
		if popupFrame then
			local pf = popupFrame
			popupFrame = nil
			Tween(pf, { Size = UDim2.new(0, pf.Size.X.Offset, 0, 0) }, 0.4,
				Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			Tween(pf, { BackgroundTransparency = 1 }, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(0.4, function() if pf then pf:Destroy() end end)
		end
	end
 
	local function refreshOptionVisual(name)
		local entry = optionButtons[name]
		if not entry then return end
		local sel = isOptionSelected(name)
		Tween(entry.button, { BackgroundTransparency = sel and 0.9 or 1 }, 0.1)
		Tween(entry.label, { TextColor3 = sel and BobloNEXT.Theme.Text or BobloNEXT.Theme.TextDim }, 0.1)
		if entry.check then
			Tween(entry.check, { BackgroundTransparency = sel and 0.05 or 0.9 }, 0.1)
		end
		if entry.checkIcon then
			Tween(entry.checkIcon, { ImageTransparency = sel and 0 or 1 }, 0.1)
		end
	end
 
	local function openPopup()
		if popupOpen then return end
		popupOpen = true
		RegisterPopupOpen(closePopup)
		Tween(chevron, { Rotation = 180 }, 0.15)
 
		local root = BobloNEXT._Root
		local mainWindow = self._window and self._window._gui or root
 
		local rowH, padV = 30, 12
		local contentH = #options * rowH + math.max(#options - 1, 0) * 2 + padV
		local targetHeight = math.min(contentH, 220, math.max(1, (ViewportSize().Y - 16) / GetUIScale()))
 
		local popupW = 140
		for _, name in ipairs(options) do
			local w = MeasureText(tostring(name), 13, 1000)
			popupW = math.max(popupW, w + 66)
		end
		popupW = math.min(popupW, ViewportSize().X / GetUIScale() - 24)
 
		popupBackdrop = MakePopupBackdrop(closePopup)
 
		popupFrame = Instance.new("CanvasGroup")
		popupFrame.Name = "DropdownPopup"
		popupFrame.Active = true
		ThemeBind(popupFrame, "BackgroundColor3", "Background")
		popupFrame.BackgroundTransparency = 1
		popupFrame.BorderSizePixel = 0
		popupFrame.ZIndex = Z.Popup
		popupFrame.Size = UDim2.new(0, popupW, 0, 0)
		popupFrame.Parent = root
		Corner(popupFrame, 10)
		local popupStroke = Stroke(popupFrame, BobloNEXT.Theme.Border, 1, 0.72)
		ThemeBind(popupStroke, "Color", "Border")
		GlassLayer(popupFrame, 10, 0.985)
 
		local px, py = ComputePopupPosition(mainWindow, card, popupW, targetHeight)
		popupFrame.Position = UDim2.fromOffset(px, py)
 
		local optionsHolder = Instance.new("ScrollingFrame")
		optionsHolder.Name = "Options"
		optionsHolder.BackgroundTransparency = 1
		optionsHolder.BorderSizePixel = 0
		optionsHolder.Size = UDim2.fromScale(1, 1)
		optionsHolder.ScrollingDirection = Enum.ScrollingDirection.Y
		optionsHolder.ScrollBarThickness = 0
		optionsHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
		optionsHolder.CanvasSize = UDim2.new(0, 0, 0, 0)
		optionsHolder.ZIndex = Z.Popup + 1
		optionsHolder.Parent = popupFrame
 
		local optPad = Instance.new("UIPadding")
		optPad.PaddingTop = UDim.new(0, 6)
		optPad.PaddingBottom = UDim.new(0, 6)
		optPad.PaddingLeft = UDim.new(0, 6)
		optPad.PaddingRight = UDim.new(0, 16)
		optPad.Parent = optionsHolder
 
		local optLayout = Instance.new("UIListLayout")
		optLayout.Padding = UDim.new(0, 2)
		optLayout.SortOrder = Enum.SortOrder.LayoutOrder
		optLayout.Parent = optionsHolder
 
		AddScrollbar(optionsHolder)
		AddContentScrollThumb(optionsHolder, optLayout, popupFrame, {
			Add = function(_, conn) scrollConn = conn end,
		})
 
		for i, optionName in ipairs(options) do
			local optBtn = Instance.new("TextButton")
			optBtn.Text = ""
			optBtn.AutoButtonColor = false
			optBtn.BackgroundColor3 = BobloNEXT.Theme.Accent
			optBtn.BackgroundTransparency = isOptionSelected(optionName) and 0.9 or 1
			optBtn.BorderSizePixel = 0
			optBtn.Size = UDim2.new(1, 0, 0, rowH)
			optBtn.LayoutOrder = i
			optBtn.ZIndex = Z.Popup + 2
			optBtn.Parent = optionsHolder
			Corner(optBtn, 8)
 
			local optLabel = Instance.new("TextLabel")
			optLabel.BackgroundTransparency = 1
			optLabel.FontFace = BobloNEXT.Theme.FontRegular
			optLabel.Text = tostring(optionName)
			optLabel.TextColor3 = isOptionSelected(optionName) and BobloNEXT.Theme.Text or BobloNEXT.Theme.TextDim
			optLabel.TextSize = 13
			optLabel.TextXAlignment = Enum.TextXAlignment.Left
			optLabel.TextTruncate = Enum.TextTruncate.AtEnd
			optLabel.Position = UDim2.fromOffset(10, 0)
			optLabel.Size = UDim2.new(1, -34, 1, 0)
			optLabel.ZIndex = Z.Popup + 3
			optLabel.Parent = optBtn
 
			local entry = { button = optBtn, label = optLabel }
 
			if isMulti then
				local check = Instance.new("Frame")
				check.Name = "Check"
				check.AnchorPoint = Vector2.new(1, 0.5)
				check.Position = UDim2.new(1, -10, 0.5, 0)
				check.Size = UDim2.fromOffset(14, 14)
				check.BackgroundColor3 = BobloNEXT.Theme.Accent
				check.BackgroundTransparency = isOptionSelected(optionName) and 0.05 or 0.9
				check.BorderSizePixel = 0
				check.ZIndex = Z.Popup + 3
				check.Parent = optBtn
				Corner(check, 4)
				local checkStroke = Stroke(check, BobloNEXT.Theme.AccentSoft, 1, 0.55)
				ThemeBind(checkStroke, "Color", "AccentSoft")
 
				local checkIcon = Instance.new("ImageLabel")
				checkIcon.Name = "Icon"
				checkIcon.BackgroundTransparency = 1
				checkIcon.Image = ResolveIcon("check")
				ThemeBind(checkIcon, "ImageColor3", "OnAccent")
				checkIcon.ImageTransparency = isOptionSelected(optionName) and 0 or 1
				checkIcon.Size = UDim2.fromOffset(10, 10)
				checkIcon.AnchorPoint = Vector2.new(0.5, 0.5)
				checkIcon.Position = UDim2.fromScale(0.5, 0.5)
				checkIcon.ZIndex = Z.Popup + 4
				checkIcon.Parent = check
 
				entry.check = check
				entry.checkIcon = checkIcon
			elseif isOptionSelected(optionName) then
				local check = Instance.new("ImageLabel")
				check.Name = "SingleCheck"
				check.BackgroundTransparency = 1
				check.Image = ResolveIcon("check")
				ThemeBind(check, "ImageColor3", "Accent")
				check.Size = UDim2.fromOffset(14, 14)
				check.AnchorPoint = Vector2.new(1, 0.5)
				check.Position = UDim2.new(1, -10, 0.5, 0)
				check.ZIndex = Z.Popup + 3
				check.Parent = optBtn
			end
 
			optionButtons[optionName] = entry
 
			optBtn.MouseEnter:Connect(function()
				if not isOptionSelected(optionName) then
					Tween(optBtn, { BackgroundTransparency = 0.85 }, 0.1)
				end
			end)
			optBtn.MouseLeave:Connect(function()
				if not isOptionSelected(optionName) then
					Tween(optBtn, { BackgroundTransparency = 1 }, 0.1)
				end
			end)
 
			optBtn.MouseButton1Click:Connect(function()
				if isMulti then
					selected[optionName] = (not selected[optionName]) or nil
					refreshOptionVisual(optionName)
					valueLabel.Text = formatValue()
					fireChanged(getSelectedList())
				else
					selected = optionName
					valueLabel.Text = formatValue()
					fireChanged(optionName)
					closePopup()
				end
			end)
		end
 
		Tween(popupFrame, {
			Size = UDim2.new(0, popupW, 0, targetHeight),
			BackgroundTransparency = 0.15,
		}, 0.44, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		Tween(popupStroke, { Transparency = 0.85 }, 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
 
		followConn = RunService.RenderStepped:Connect(function()
			if not popupFrame or not card.Parent then return end
			local nx, ny = ComputePopupPosition(mainWindow, card, popupW, targetHeight)
			popupFrame.Position = UDim2.fromOffset(nx, ny)
		end)
		jan:Add(followConn)
	end
 
	click.MouseButton1Click:Connect(function()
		if popupOpen then closePopup() else openPopup() end
	end)
 
	card.MouseEnter:Connect(function() Tween(card, { BackgroundTransparency = 0.93 }, 0.15) end)
	card.MouseLeave:Connect(function() Tween(card, { BackgroundTransparency = 0.96 }, 0.15) end)
 
	return RegisterFlag(opts, {
		Instance = card,
		Set = function(_, v, silent)
			if isMulti then
				selected = {}
				if type(v) == "table" then
					for _, name in ipairs(v) do selected[name] = true end
				end
			else
				selected = v
			end
			valueLabel.Text = formatValue()
			for name in pairs(optionButtons) do refreshOptionVisual(name) end
			if not silent then
				fireChanged(isMulti and getSelectedList() or selected)
			end
		end,
		Get = function()
			if isMulti then return getSelectedList() end
			return selected
		end,
		SetOptions = function(_, newOptions)
			options = newOptions or {}
			closePopup()
			valueLabel.Text = formatValue()
		end,
		Refresh = function(_, newOptions)
			options = newOptions or options
			closePopup()
			valueLabel.Text = formatValue()
		end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function() closePopup(); signal.Clear(); card:Destroy() end,
	}, "Dropdown")
end
 
function Tab:AddTextbox(opts)
	opts = opts or {}
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local card = BaseCard(self._page, height)
 
	local textX = AddLeadingIcon(card, opts.Icon, height)
 
	local iconGap, rightPad, pillMinW = 29, 12, 90
	local titleReserve = pillMinW + 26
 
	local _, _, refreshTextLayout = AddTitleDesc(card, textX, function() return titleReserve end, opts.Text or "Textbox", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Textbox", card)
 
	local pill = Instance.new("Frame")
	pill.AnchorPoint = Vector2.new(1, 0.5)
	pill.Position = UDim2.new(1, -14, 0.5, 0)
	pill.Size = UDim2.fromOffset(pillMinW, 26)
	ThemeBind(pill, "BackgroundColor3", "SurfaceHigh")
	pill.BackgroundTransparency = 0.9
	pill.BorderSizePixel = 0
	pill.ZIndex = Z.Content + 2
	pill.Parent = card
	Corner(pill, 8)
	local pillStroke = Stroke(pill, BobloNEXT.Theme.Border, 1, 0.65)
	ThemeBind(pillStroke, "Color", "Border")
 
	local penIcon = Instance.new("ImageLabel")
	penIcon.BackgroundTransparency = 1
	penIcon.Image = ResolveIcon("pencil")
	ThemeBind(penIcon, "ImageColor3", "TextDim")
	penIcon.Size = UDim2.fromOffset(13, 13)
	penIcon.AnchorPoint = Vector2.new(0, 0.5)
	penIcon.Position = UDim2.new(0, 10, 0.5, 0)
	penIcon.ZIndex = Z.Content + 3
	penIcon.Parent = pill
 
	local box = Instance.new("TextBox")
	box.ClearTextOnFocus = false
	box.FontFace = BobloNEXT.Theme.FontRegular
	box.PlaceholderText = opts.Placeholder or ""
	ThemeBind(box, "PlaceholderColor3", "TextSoft")
	box.Text = opts.Default or ""
	ThemeBind(box, "TextColor3", "Text")
	box.TextSize = 13
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Center
	box.TextTruncate = Enum.TextTruncate.AtEnd
	box.ClipsDescendants = true
	box.BackgroundTransparency = 1
	box.Position = UDim2.fromOffset(iconGap, 0)
	box.Size = UDim2.new(1, -(iconGap + 10), 1, 0)
	box.ZIndex = Z.Content + 3
	box.Parent = pill
 
	local currentPillW = pillMinW
 
	local function resizePill(animated)
		local sample = box.Text ~= "" and box.Text or box.PlaceholderText
		local textW = MeasureText(sample, 13, 2000)
		local desiredW = iconGap + textW + rightPad
 
		local realCardW = card.AbsoluteSize.X > 0 and card.AbsoluteSize.X or 400
		local cardW = realCardW / GetUIScale()
		local maxW = math.max(pillMinW, math.floor(cardW * 0.5))
		local targetW = math.clamp(desiredW, pillMinW, maxW)
 
		if math.abs(targetW - currentPillW) < 1 then return end
		currentPillW = targetW
		titleReserve = targetW + 26
		refreshTextLayout()
 
		if animated == false then
			pill.Size = UDim2.fromOffset(targetW, 26)
		else
			Tween(pill, { Size = UDim2.fromOffset(targetW, 26) }, 0.16,
				Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		end
	end
 
	box:GetPropertyChangedSignal("Text"):Connect(function() resizePill(true) end)
	card:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() resizePill(false) end)
	task.defer(function() resizePill(false) end)
 
	box.Focused:Connect(function()
		Tween(pillStroke, { Color = BobloNEXT.Theme.Accent, Transparency = 0.3 }, 0.15)
		Tween(pill, { BackgroundTransparency = 0.82 }, 0.15)
	end)
 
	local signal = MakeSignal()
	local function fireChanged(text, enterPressed)
		if opts.Callback then task.spawn(opts.Callback, text, enterPressed) end
		signal.Fire(text, enterPressed)
	end
 
	box.FocusLost:Connect(function(enterPressed)
		Tween(pillStroke, { Color = BobloNEXT.Theme.Border, Transparency = 0.65 }, 0.15)
		Tween(pill, { BackgroundTransparency = 0.9 }, 0.15)
		fireChanged(box.Text, enterPressed)
	end)
 
	return RegisterFlag(opts, {
		Instance = card,
		Set = function(_, v, silent)
			box.Text = tostring(v or "")
			resizePill()
			if not silent then fireChanged(box.Text, false) end
		end,
		Get = function() return box.Text end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function() signal.Clear(); card:Destroy() end,
	}, "Textbox")
end
 
local function MiniField(parent, label, width, zBase)
	zBase = zBase or Z.Popup
 
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(width, 36)
	holder.ZIndex = zBase + 1
	holder.Parent = parent
 
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.FontFace = BobloNEXT.Theme.FontRegular
	lbl.Text = label
	lbl.TextColor3 = BobloNEXT.Theme.TextDim
	lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Size = UDim2.new(1, 0, 0, 12)
	lbl.ZIndex = zBase + 2
	lbl.Parent = holder
 
	local field = Instance.new("Frame")
	field.Position = UDim2.fromOffset(0, 12)
	field.Size = UDim2.new(1, 0, 0, 24)
	field.BackgroundColor3 = Color3.new(1, 1, 1)
	field.BackgroundTransparency = 0.92
	field.BorderSizePixel = 0
	field.ZIndex = zBase + 2
	field.Parent = holder
	Corner(field, 7)
	local fieldStroke = Stroke(field, Color3.new(1, 1, 1), 1, 0.88)
 
	local box = Instance.new("TextBox")
	box.ClearTextOnFocus = false
	box.FontFace = BobloNEXT.Theme.FontRegular
	box.Text = ""
	box.TextColor3 = BobloNEXT.Theme.Text
	box.TextSize = 13
	box.TextXAlignment = Enum.TextXAlignment.Center
	box.TextYAlignment = Enum.TextYAlignment.Center
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromScale(1, 1)
	box.ZIndex = zBase + 3
	box.Parent = field
 
	box.Focused:Connect(function()
		Tween(fieldStroke, { Color = BobloNEXT.Theme.Accent, Transparency = 0.3 }, 0.15)
		Tween(field, { BackgroundTransparency = 0.84 }, 0.15)
	end)
	box.FocusLost:Connect(function()
		Tween(fieldStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.88 }, 0.15)
		Tween(field, { BackgroundTransparency = 0.92 }, 0.15)
	end)
 
	return holder, box
end
 
function Tab:AddColorPicker(opts)
	opts = opts or {}
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local jan = self._janitor
 
	local card = BaseCard(self._page, height)
	local textX = AddLeadingIcon(card, opts.Icon, height)
	AddTitleDesc(card, textX, 52, opts.Text or "Color", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Color", card)
 
	local color = opts.Default or Color3.fromRGB(255, 255, 255)
	local hue, sat, val = Color3.toHSV(color)
 
	local swatchHolder = Instance.new("Frame")
	swatchHolder.AnchorPoint = Vector2.new(1, 0.5)
	swatchHolder.Position = UDim2.new(1, -14, 0.5, 0)
	swatchHolder.Size = UDim2.fromOffset(24, 24)
	swatchHolder.BackgroundColor3 = Color3.new(1, 1, 1)
	swatchHolder.BackgroundTransparency = 0.9
	swatchHolder.BorderSizePixel = 0
	swatchHolder.ZIndex = Z.Content + 1
	swatchHolder.Parent = card
	Corner(swatchHolder, 6)
	local swatchStroke = Stroke(swatchHolder, Color3.new(1, 1, 1), 1, 0.85)
 
	local swatch = Instance.new("Frame")
	swatch.AnchorPoint = Vector2.new(0.5, 0.5)
	swatch.Position = UDim2.fromScale(0.5, 0.5)
	swatch.Size = UDim2.fromOffset(16, 16)
	swatch.BackgroundColor3 = color
	swatch.BorderSizePixel = 0
	swatch.ZIndex = Z.Content + 2
	swatch.Parent = swatchHolder
	Corner(swatch, 4)
 
	local click = Instance.new("TextButton")
	click.Text = ""
	click.AutoButtonColor = false
	click.BackgroundTransparency = 1
	click.Size = UDim2.fromScale(1, 1)
	click.ZIndex = Z.Content + 3
	click.Parent = card
 
	local popupOpen = false
	local popupFrame, popupBackdrop, followConn
	local svCursor, hueCursor, svBox, hueBar, satGradient
	local hexBox, rBox, gBox, bBox
	local originalHue, originalSat, originalVal
	local draggingSV, draggingHue = false, false
	local colorInput = nil
	local dragEndedAt = 0
 
	local function currentColor()
		return Color3.fromHSV(hue, sat, val)
	end
 
	local function syncFields()
		if svCursor then svCursor.Position = UDim2.new(sat, 0, 1 - val, 0) end
		if hueCursor then hueCursor.Position = UDim2.new(hue, 0, 0.5, 0) end
		if svBox then svBox.BackgroundColor3 = Color3.new(1, 1, 1) end
		if satGradient then
			satGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(hue, 1, 1))
		end
 
		local c = currentColor()
		local r = math.floor(c.R * 255 + 0.5)
		local g = math.floor(c.G * 255 + 0.5)
		local b = math.floor(c.B * 255 + 0.5)
		if hexBox and not hexBox:IsFocused() then hexBox.Text = "#" .. c:ToHex():upper() end
		if rBox and not rBox:IsFocused() then rBox.Text = tostring(r) end
		if gBox and not gBox:IsFocused() then gBox.Text = tostring(g) end
		if bBox and not bBox:IsFocused() then bBox.Text = tostring(b) end
	end
 
	local signal = MakeSignal()
	local lastFired = nil
 
	local function ColorsClose(a, b)
		if a == nil or b == nil then return false end
		return math.abs(a.R - b.R) < 0.001
			and math.abs(a.G - b.G) < 0.001
			and math.abs(a.B - b.B) < 0.001
	end
 
	local function applyColor(fireCallback)
		local c = currentColor()
		swatch.BackgroundColor3 = c
		syncFields()
		if fireCallback then
			if not ColorsClose(c, lastFired) then
				lastFired = c
				if opts.Callback then task.spawn(opts.Callback, c) end
				signal.Fire(c)
			end
		end
	end
 
	local function closePopup()
		if not popupOpen then return end
		popupOpen = false
		draggingSV, draggingHue = false, false
		colorInput = nil
		RegisterPopupClose(closePopup)
		Tween(swatchStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.85 }, 0.15)
 
		if followConn then followConn:Disconnect(); followConn = nil end
		if popupBackdrop then popupBackdrop:Destroy(); popupBackdrop = nil end
 
		if popupFrame then
			local pf = popupFrame
			popupFrame = nil
			svCursor, hueCursor, svBox, hueBar, satGradient = nil, nil, nil, nil, nil
			hexBox, rBox, gBox, bBox = nil, nil, nil, nil
			Tween(pf, { Size = UDim2.new(0, pf.Size.X.Offset, 0, 0) }, 0.4,
				Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			Tween(pf, { BackgroundTransparency = 1 }, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			task.delay(0.4, function() if pf then pf:Destroy() end end)
		end
	end
 
	local function updateSV(inputPos)
		if not svBox or svBox.AbsoluteSize.X <= 0 then return end
		local rel, sz = svBox.AbsolutePosition, svBox.AbsoluteSize
		sat = math.clamp((inputPos.X - rel.X) / sz.X, 0, 1)
		val = 1 - math.clamp((inputPos.Y - rel.Y) / sz.Y, 0, 1)
		applyColor(true)
	end
 
	local function updateHue(inputPos)
		if not hueBar or hueBar.AbsoluteSize.X <= 0 then return end
		local rel, sz = hueBar.AbsolutePosition, hueBar.AbsoluteSize
		hue = math.clamp((inputPos.X - rel.X) / sz.X, 0, 1)
		applyColor(true)
	end
 
	jan:Add(UserInputService.InputChanged:Connect(function(input)
		if not popupFrame then return end
		if input ~= colorInput
			and not (colorInput and colorInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement) then
			return
		end
		if draggingSV then updateSV(input.Position) end
		if draggingHue then updateHue(input.Position) end
	end))
 
	jan:Add(UserInputService.InputEnded:Connect(function(input)
		if input == colorInput
			or (colorInput and colorInput.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1) then
			if draggingSV or draggingHue then
				dragEndedAt = os.clock()
			end
			draggingSV, draggingHue = false, false
			colorInput = nil
		end
	end))
 
	local function requestCloseFromBackdrop()
		if draggingSV or draggingHue then return end
		if os.clock() - dragEndedAt < 0.2 then return end
		closePopup()
	end
 
	local function openPopup()
		if popupOpen then return end
		popupOpen = true
		originalHue, originalSat, originalVal = hue, sat, val
		lastFired = currentColor()
		RegisterPopupOpen(closePopup)
		Tween(swatchStroke, { Color = BobloNEXT.Theme.Accent, Transparency = 0.3 }, 0.15)
 
		local root = BobloNEXT._Root
		local mainWindow = self._window and self._window._gui or root
		local popupW, popupH = 208, math.min(290, math.max(1, (ViewportSize().Y - 16) / GetUIScale()))
 
		popupBackdrop = MakePopupBackdrop(requestCloseFromBackdrop)
 
		popupFrame = Instance.new("ScrollingFrame")
		popupFrame.CanvasSize = UDim2.fromOffset(0, 290)
		popupFrame.ScrollingDirection = Enum.ScrollingDirection.Y
		popupFrame.ScrollBarThickness = 3
		popupFrame.ScrollBarImageColor3 = BobloNEXT.Theme.TextDim
		popupFrame.ScrollBarImageTransparency = 0.35
		popupFrame.BorderSizePixel = 0
		popupFrame.Name = "ColorPickerPopup"
		popupFrame.Active = true
		popupFrame.BackgroundColor3 = BobloNEXT.Theme.Background
		popupFrame.BackgroundTransparency = 1
		popupFrame.BorderSizePixel = 0
		popupFrame.ClipsDescendants = true
		popupFrame.ZIndex = Z.Popup
		popupFrame.Size = UDim2.new(0, popupW, 0, 0)
		popupFrame.Parent = root
		Corner(popupFrame, 10)
		local popupStroke = Stroke(popupFrame, Color3.new(1, 1, 1), 1, 0.92)
		GlassLayer(popupFrame, 10, 0.985)
 
		local px, py = ComputePopupPosition(mainWindow, card, popupW, popupH)
		popupFrame.Position = UDim2.fromOffset(px, py)
 
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 14)
		pad.PaddingBottom = UDim.new(0, 14)
		pad.PaddingLeft = UDim.new(0, 14)
		pad.PaddingRight = UDim.new(0, 14)
		pad.Parent = popupFrame
 
		local innerW = popupW - 28
 
		svBox = Instance.new("Frame")
		svBox.Active = true
		svBox.Position = UDim2.fromOffset(0, 0)
		svBox.Size = UDim2.fromOffset(innerW, 104)
		svBox.BackgroundColor3 = Color3.new(1, 1, 1)
		svBox.BorderSizePixel = 0
		svBox.ClipsDescendants = true
		svBox.ZIndex = Z.Popup + 1
		svBox.Parent = popupFrame
		Corner(svBox, 8)
 
		satGradient = Instance.new("UIGradient")
		satGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(hue, 1, 1))
		satGradient.Parent = svBox
 
		local valOverlay = Instance.new("Frame")
		valOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
		valOverlay.BorderSizePixel = 0
		valOverlay.Size = UDim2.fromScale(1, 1)
		valOverlay.ZIndex = Z.Popup + 1
		valOverlay.Parent = svBox
		local valGradient = Instance.new("UIGradient")
		valGradient.Rotation = 90
		valGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		valGradient.Parent = valOverlay
 
		local svCursorLayer = Instance.new("Frame")
		svCursorLayer.BackgroundTransparency = 1
		svCursorLayer.BorderSizePixel = 0
		svCursorLayer.ClipsDescendants = false
		svCursorLayer.Position = svBox.Position
		svCursorLayer.Size = svBox.Size
		svCursorLayer.ZIndex = Z.Popup + 2
		svCursorLayer.Parent = popupFrame
 
		svCursor = Instance.new("Frame")
		svCursor.AnchorPoint = Vector2.new(0.5, 0.5)
		svCursor.Position = UDim2.new(sat, 0, 1 - val, 0)
		svCursor.Size = UDim2.fromOffset(16, 16)
		svCursor.BackgroundTransparency = 1
		svCursor.ZIndex = Z.Popup + 3
		svCursor.Parent = svCursorLayer
		Corner(svCursor, 8)
		Stroke(svCursor, Color3.new(0, 0, 0), 2, 0.15)
 
		local svCursorInner = Instance.new("Frame")
		svCursorInner.AnchorPoint = Vector2.new(0.5, 0.5)
		svCursorInner.Position = UDim2.fromScale(0.5, 0.5)
		svCursorInner.Size = UDim2.fromOffset(11, 11)
		svCursorInner.BackgroundTransparency = 1
		svCursorInner.ZIndex = Z.Popup + 4
		svCursorInner.Parent = svCursor
		Corner(svCursorInner, 6)
		Stroke(svCursorInner, Color3.new(1, 1, 1), 2, 0)
 
		hueBar = Instance.new("Frame")
		hueBar.Active = true
		hueBar.Position = UDim2.fromOffset(0, 114)
		hueBar.Size = UDim2.fromOffset(innerW, 10)
		hueBar.BackgroundColor3 = Color3.new(1, 1, 1)
		hueBar.BorderSizePixel = 0
		hueBar.ClipsDescendants = true
		hueBar.ZIndex = Z.Popup + 1
		hueBar.Parent = popupFrame
		Corner(hueBar, 5)
 
		local hueGradient = Instance.new("UIGradient")
		hueGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.000, Color3.fromHSV(0.000, 1, 1)),
			ColorSequenceKeypoint.new(0.166, Color3.fromHSV(0.166, 1, 1)),
			ColorSequenceKeypoint.new(0.333, Color3.fromHSV(0.333, 1, 1)),
			ColorSequenceKeypoint.new(0.500, Color3.fromHSV(0.500, 1, 1)),
			ColorSequenceKeypoint.new(0.666, Color3.fromHSV(0.666, 1, 1)),
			ColorSequenceKeypoint.new(0.833, Color3.fromHSV(0.833, 1, 1)),
			ColorSequenceKeypoint.new(1.000, Color3.fromHSV(1.000, 1, 1)),
		})
		hueGradient.Parent = hueBar
 
		local hueCursorLayer = Instance.new("Frame")
		hueCursorLayer.BackgroundTransparency = 1
		hueCursorLayer.BorderSizePixel = 0
		hueCursorLayer.ClipsDescendants = false
		hueCursorLayer.Position = hueBar.Position
		hueCursorLayer.Size = hueBar.Size
		hueCursorLayer.ZIndex = Z.Popup + 2
		hueCursorLayer.Parent = popupFrame
 
		hueCursor = Instance.new("Frame")
		hueCursor.AnchorPoint = Vector2.new(0.5, 0.5)
		hueCursor.Position = UDim2.new(hue, 0, 0.5, 0)
		hueCursor.Size = UDim2.fromOffset(6, 10)
		hueCursor.BackgroundColor3 = Color3.new(1, 1, 1)
		hueCursor.BorderSizePixel = 0
		hueCursor.ZIndex = Z.Popup + 3
		hueCursor.Parent = hueCursorLayer
		Corner(hueCursor, 3)
		Stroke(hueCursor, Color3.new(0, 0, 0), 1, 0.4)
 
		local hexHolder, hexRef = MiniField(popupFrame, "HEX", innerW, Z.Popup)
		hexHolder.Position = UDim2.fromOffset(0, 136)
		hexBox = hexRef
 
		local rgbRow = Instance.new("Frame")
		rgbRow.BackgroundTransparency = 1
		rgbRow.Position = UDim2.fromOffset(0, 182)
		rgbRow.Size = UDim2.fromOffset(innerW, 36)
		rgbRow.ZIndex = Z.Popup + 1
		rgbRow.Parent = popupFrame
 
		local rHolder, rRef = MiniField(rgbRow, "R", 54, Z.Popup)
		rHolder.Position = UDim2.fromOffset(0, 0)
		rBox = rRef
 
		local gHolder, gRef = MiniField(rgbRow, "G", 54, Z.Popup)
		gHolder.Position = UDim2.fromOffset(62, 0)
		gBox = gRef
 
		local bHolder, bRef = MiniField(rgbRow, "B", 56, Z.Popup)
		bHolder.Position = UDim2.fromOffset(124, 0)
		bBox = bRef
 
		local btnRow = Instance.new("Frame")
		btnRow.BackgroundTransparency = 1
		btnRow.Position = UDim2.fromOffset(0, 232)
		btnRow.Size = UDim2.fromOffset(innerW, 30)
		btnRow.ZIndex = Z.Popup + 1
		btnRow.Parent = popupFrame
 
		local function MakeButton(text, x, w, filled)
			local btn = Instance.new("TextButton")
			btn.Position = UDim2.fromOffset(x, 0)
			btn.Size = UDim2.fromOffset(w, 30)
			btn.FontFace = BobloNEXT.Theme.Font
			btn.Text = text
			btn.TextSize = 13
			btn.AutoButtonColor = false
			btn.BorderSizePixel = 0
			btn.ZIndex = Z.Popup + 2
			if filled then
				btn.BackgroundColor3 = BobloNEXT.Theme.Accent
				btn.BackgroundTransparency = 0
				btn.TextColor3 = BobloNEXT.Theme.Background
			else
				btn.BackgroundColor3 = Color3.new(1, 1, 1)
				btn.BackgroundTransparency = 0.92
				btn.TextColor3 = BobloNEXT.Theme.Text
			end
			btn.Parent = btnRow
			Corner(btn, 8)
			if not filled then Stroke(btn, Color3.new(1, 1, 1), 1, 0.88) end
			return btn
		end
 
		local halfW = (innerW - 10) / 2
		local cancelBtn = MakeButton("Cancel", 0, halfW, false)
		local doneBtn   = MakeButton("Done", halfW + 10, halfW, true)
 
		cancelBtn.Activated:Connect(function()
			hue, sat, val = originalHue, originalSat, originalVal
			applyColor(true)
			closePopup()
		end)
		doneBtn.Activated:Connect(closePopup)
 
		svBox.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				if draggingSV or draggingHue then return end
				draggingSV = true
				colorInput = input
				updateSV(input.Position)
			end
		end)
 
		hueBar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				if draggingSV or draggingHue then return end
				draggingHue = true
				colorInput = input
				updateHue(input.Position)
			end
		end)
 
		hexBox:GetPropertyChangedSignal("Text"):Connect(function()
			local filtered = hexBox.Text:gsub("[^%x]", "")
			filtered = filtered:sub(1, 6)
			if filtered ~= hexBox.Text then hexBox.Text = filtered end
		end)
 
		hexBox.FocusLost:Connect(function()
			local clean = hexBox.Text:gsub("#", "")
			if #clean == 3 then
				clean = clean:sub(1, 1):rep(2) .. clean:sub(2, 2):rep(2) .. clean:sub(3, 3):rep(2)
			end
			if #clean == 6 then
				local ok, c = pcall(Color3.fromHex, clean)
				if ok and c then
					hue, sat, val = Color3.toHSV(c)
					applyColor(true)
					return
				end
			end
			syncFields()
		end)
 
		local function filterDigits(b)
			b:GetPropertyChangedSignal("Text"):Connect(function()
				local filtered = b.Text:gsub("%D", ""):sub(1, 3)
				if filtered ~= b.Text then b.Text = filtered end
			end)
		end
		filterDigits(rBox); filterDigits(gBox); filterDigits(bBox)
 
		local function onRGBCommit()
			local r = math.clamp(tonumber(rBox.Text) or 0, 0, 255)
			local g = math.clamp(tonumber(gBox.Text) or 0, 0, 255)
			local b = math.clamp(tonumber(bBox.Text) or 0, 0, 255)
			hue, sat, val = Color3.toHSV(Color3.fromRGB(r, g, b))
			applyColor(true)
		end
		rBox.FocusLost:Connect(onRGBCommit)
		gBox.FocusLost:Connect(onRGBCommit)
		bBox.FocusLost:Connect(onRGBCommit)
 
		syncFields()
 
		Tween(popupFrame, {
			Size = UDim2.new(0, popupW, 0, popupH),
			BackgroundTransparency = 0.15,
		}, 0.44, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		Tween(popupStroke, { Transparency = 0.85 }, 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
 
		followConn = RunService.RenderStepped:Connect(function()
			if not popupFrame or not card.Parent then return end
			local nx, ny = ComputePopupPosition(mainWindow, card, popupW, popupH)
			popupFrame.Position = UDim2.fromOffset(nx, ny)
		end)
		jan:Add(followConn)
	end
 
	click.MouseButton1Click:Connect(function()
		if popupOpen then closePopup() else openPopup() end
	end)
 
	card.MouseEnter:Connect(function() Tween(card, { BackgroundTransparency = 0.93 }, 0.15) end)
	card.MouseLeave:Connect(function() Tween(card, { BackgroundTransparency = 0.96 }, 0.15) end)
 
	return RegisterFlag(opts, {
		Instance = card,
		Set = function(_, c, silent)
			hue, sat, val = Color3.toHSV(c)
			applyColor(not silent)
			if silent then lastFired = currentColor() end
		end,
		Get = function() return currentColor() end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function() closePopup(); signal.Clear(); card:Destroy() end,
	}, "ColorPicker")
end
 
function Tab:AddKeybind(opts)
	opts = opts or {}
	local hasDesc = opts.Description and opts.Description ~= ""
	local height = hasDesc and 56 or 44
	local jan = self._janitor
 
	local card = BaseCard(self._page, height)
	local textX = AddLeadingIcon(card, opts.Icon, height)
	AddTitleDesc(card, textX, 128, opts.Text or "Keybind", opts.Description, height)
	self._window:_RegisterSearchable(self, opts.Text or "Keybind", card)
 
	local currentKey = opts.Default
 
	local pill = Instance.new("Frame")
	pill.AnchorPoint = Vector2.new(1, 0.5)
	pill.Position = UDim2.new(1, -14, 0.5, 0)
	pill.Size = UDim2.fromOffset(104, 26)
	pill.BackgroundColor3 = Color3.new(1, 1, 1)
	pill.BackgroundTransparency = 0.9
	pill.BorderSizePixel = 0
	pill.ZIndex = Z.Content + 2
	pill.Parent = card
	Corner(pill, 8)
	local pillStroke = Stroke(pill, Color3.new(1, 1, 1), 1, 0.88)
 
	local keyIcon = Instance.new("ImageLabel")
	keyIcon.BackgroundTransparency = 1
	keyIcon.Image = ResolveIcon("keyboard")
	keyIcon.ImageColor3 = BobloNEXT.Theme.TextDim
	keyIcon.Size = UDim2.fromOffset(13, 13)
	keyIcon.AnchorPoint = Vector2.new(0, 0.5)
	keyIcon.Position = UDim2.new(0, 10, 0.5, 0)
	keyIcon.ZIndex = Z.Content + 3
	keyIcon.Parent = pill
 
	local keyLabel = Instance.new("TextLabel")
	keyLabel.BackgroundTransparency = 1
	keyLabel.FontFace = BobloNEXT.Theme.FontRegular
	keyLabel.Text = currentKey and currentKey.Name or "None"
	keyLabel.TextColor3 = BobloNEXT.Theme.Text
	keyLabel.TextSize = 13
	keyLabel.TextTruncate = Enum.TextTruncate.AtEnd
	keyLabel.TextXAlignment = Enum.TextXAlignment.Left
	keyLabel.Position = UDim2.fromOffset(29, 0)
	keyLabel.Size = UDim2.new(1, -37, 1, 0)
	keyLabel.ZIndex = Z.Content + 3
	keyLabel.Parent = pill
 
	local click = Instance.new("TextButton")
	click.Text = ""
	click.AutoButtonColor = false
	click.BackgroundTransparency = 1
	click.Size = UDim2.fromScale(1, 1)
	click.ZIndex = Z.Content + 4
	click.Parent = pill
 
	local listening = false
	local listenConn = nil
	local signal = MakeSignal()
 
	local function fireChanged(key)
		signal.Fire(key)
	end
 
	local function stopListening()
		listening = false
		KeybindCapturing = false
		if listenConn then listenConn:Disconnect(); listenConn = nil end
		Tween(pillStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.88 }, 0.15)
		Tween(pill, { BackgroundTransparency = 0.9 }, 0.15)
		keyLabel.Text = currentKey and currentKey.Name or "None"
	end
 
	local function startListening()
		if listening then return end
		listening = true
		KeybindCapturing = true
		keyLabel.Text = "..."
		Tween(pillStroke, { Color = BobloNEXT.Theme.Accent, Transparency = 0.3 }, 0.15)
		Tween(pill, { BackgroundTransparency = 0.82 }, 0.15)
 
		listenConn = UserInputService.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
 
			if input.KeyCode == Enum.KeyCode.Escape then
				stopListening()
				return
			end
			if input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
				currentKey = nil
				stopListening()
				fireChanged(nil)
				return
			end
 
			currentKey = input.KeyCode
			stopListening()
			if opts.Callback then task.spawn(opts.Callback, currentKey, "bind") end
			fireChanged(currentKey)
		end)
		jan:Add(listenConn)
	end
 
	click.MouseButton1Click:Connect(startListening)
 
	jan:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if listening or KeybindCapturing or gameProcessed then return end
		if UserInputService:GetFocusedTextBox() then return end
		if currentKey
			and input.UserInputType == Enum.UserInputType.Keyboard
			and input.KeyCode == currentKey then
			if opts.Callback then task.spawn(opts.Callback, currentKey, "press") end
		end
	end))
 
	card.MouseEnter:Connect(function() Tween(card, { BackgroundTransparency = 0.93 }, 0.15) end)
	card.MouseLeave:Connect(function() Tween(card, { BackgroundTransparency = 0.96 }, 0.15) end)
 
	return RegisterFlag(opts, {
		Instance = card,
		Set = function(_, key, silent)
			currentKey = key
			keyLabel.Text = key and key.Name or "None"
			if not silent then fireChanged(key) end
		end,
		Get = function() return currentKey end,
		OnChanged = function(_, fn) return signal.Connect(fn) end,
		Destroy = function() stopListening(); signal.Clear(); card:Destroy() end,
	}, "Keybind")
end
 
local ConsoleColors = {
	[Enum.MessageType.MessageInfo]    = Color3.fromRGB(120, 170, 255),
	[Enum.MessageType.MessageWarning] = Color3.fromRGB(255, 190, 90),
	[Enum.MessageType.MessageError]   = Color3.fromRGB(255, 105, 105),
	[Enum.MessageType.MessageOutput]  = nil,
}
 
function Tab:AddConsole(opts)
	opts = opts or {}
	local height = opts.Height or 200
	local maxLogs = opts.MaxLogs or 300
	local jan = self._janitor
 
	local container = Instance.new("Frame")
	container.Name = "Console"
	container.BackgroundColor3 = BobloNEXT.Theme.Surface
	container.BackgroundTransparency = 0.35
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Size = UDim2.new(1, 0, 0, height)
	container.ZIndex = Z.Content
	container.Parent = self._page
	Corner(container, BobloNEXT.Theme.CornerRadiusSm)
	Stroke(container, Color3.new(1, 1, 1), 1, 0.92)
 
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 34)
	header.ZIndex = Z.Content + 1
	header.Parent = container
 
	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingLeft = UDim.new(0, 12)
	headerPad.PaddingRight = UDim.new(0, 8)
	headerPad.Parent = header
 
	local titleRow = Instance.new("Frame")
	titleRow.BackgroundTransparency = 1
	titleRow.Size = UDim2.new(1, -70, 1, 0)
	titleRow.ZIndex = Z.Content + 2
	titleRow.Parent = header
 
	local titleLayout = Instance.new("UIListLayout")
	titleLayout.FillDirection = Enum.FillDirection.Horizontal
	titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	titleLayout.Padding = UDim.new(0, 7)
	titleLayout.Parent = titleRow
 
	local titleIcon = Instance.new("ImageLabel")
	titleIcon.BackgroundTransparency = 1
	titleIcon.Image = ResolveIcon("terminal")
	titleIcon.ImageColor3 = BobloNEXT.Theme.TextDim
	titleIcon.Size = UDim2.fromOffset(14, 14)
	titleIcon.LayoutOrder = 1
	titleIcon.ZIndex = Z.Content + 3
	titleIcon.Parent = titleRow
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = BobloNEXT.Theme.Font
	titleLabel.Text = opts.Title or "Debug Console"
	titleLabel.TextColor3 = BobloNEXT.Theme.Text
	titleLabel.TextSize = 13
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.AutomaticSize = Enum.AutomaticSize.X
	titleLabel.Size = UDim2.fromOffset(0, 14)
	titleLabel.LayoutOrder = 2
	titleLabel.ZIndex = Z.Content + 3
	titleLabel.Parent = titleRow
 
	local controls = Instance.new("Frame")
	controls.BackgroundTransparency = 1
	controls.AnchorPoint = Vector2.new(1, 0.5)
	controls.Position = UDim2.new(1, 0, 0.5, 0)
	controls.Size = UDim2.fromOffset(58, 24)
	controls.ZIndex = Z.Content + 2
	controls.Parent = header
 
	local controlsLayout = Instance.new("UIListLayout")
	controlsLayout.FillDirection = Enum.FillDirection.Horizontal
	controlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	controlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	controlsLayout.Padding = UDim.new(0, 4)
	controlsLayout.Parent = controls
 
	local function iconButton(icon, order)
		local btn = Instance.new("TextButton")
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundColor3 = Color3.new(1, 1, 1)
		btn.BackgroundTransparency = 1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.fromOffset(24, 24)
		btn.LayoutOrder = order
		btn.ZIndex = Z.Content + 3
		btn.Parent = controls
		Corner(btn, 7)
 
		local ic = Instance.new("ImageLabel")
		ic.BackgroundTransparency = 1
		ic.Image = ResolveIcon(icon)
		ic.ImageColor3 = BobloNEXT.Theme.TextDim
		ic.Size = UDim2.fromOffset(13, 13)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.ZIndex = Z.Content + 4
		ic.Parent = btn
 
		jan:Add(btn.MouseEnter:Connect(function()
			Tween(btn, { BackgroundTransparency = 0.9 }, 0.12)
			Tween(ic, { ImageColor3 = BobloNEXT.Theme.Text }, 0.12)
		end))
		jan:Add(btn.MouseLeave:Connect(function()
			Tween(btn, { BackgroundTransparency = 1 }, 0.12)
			Tween(ic, { ImageColor3 = BobloNEXT.Theme.TextDim }, 0.12)
		end))
 
		return btn, ic
	end
 
	local copyBtn, copyIcon = iconButton("copy", 1)
	local clearBtn = iconButton("trash-2", 2)
 
	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = Color3.new(1, 1, 1)
	divider.BackgroundTransparency = 0.92
	divider.BorderSizePixel = 0
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.Position = UDim2.fromOffset(0, 34)
	divider.ZIndex = Z.Content + 1
	divider.Parent = container
 
	local logsScroll = Instance.new("ScrollingFrame")
	logsScroll.Name = "Logs"
	logsScroll.BackgroundTransparency = 1
	logsScroll.BorderSizePixel = 0
	logsScroll.Position = UDim2.fromOffset(0, 35)
	logsScroll.Size = UDim2.new(1, 0, 1, -35)
	logsScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	logsScroll.ScrollBarThickness = 0
	logsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	logsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	logsScroll.ZIndex = Z.Content + 1
	logsScroll.Parent = container
 
	local logsPad = Instance.new("UIPadding")
	logsPad.PaddingTop = UDim.new(0, 8)
	logsPad.PaddingBottom = UDim.new(0, 8)
	logsPad.PaddingLeft = UDim.new(0, 10)
	logsPad.PaddingRight = UDim.new(0, 10)
	logsPad.Parent = logsScroll
 
	local logsLayout = Instance.new("UIListLayout")
	logsLayout.Padding = UDim.new(0, 4)
	logsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	logsLayout.Parent = logsScroll
 
	AddScrollbar(logsScroll)
	AddContentScrollThumb(logsScroll, logsLayout, container, jan)
 
	local emptyState = Instance.new("Frame")
	emptyState.Name = "EmptyState"
	emptyState.BackgroundTransparency = 1
	emptyState.Position = UDim2.fromOffset(0, 35)
	emptyState.Size = UDim2.new(1, 0, 1, -35)
	emptyState.ZIndex = Z.Content + 2
	emptyState.Parent = container
 
	local emptyLayout = Instance.new("UIListLayout")
	emptyLayout.FillDirection = Enum.FillDirection.Vertical
	emptyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	emptyLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	emptyLayout.Padding = UDim.new(0, 6)
	emptyLayout.Parent = emptyState
 
	local emptyIcon = Instance.new("ImageLabel")
	emptyIcon.BackgroundTransparency = 1
	emptyIcon.Image = ResolveIcon("frown")
	emptyIcon.ImageColor3 = BobloNEXT.Theme.TextDim
	emptyIcon.Size = UDim2.fromOffset(22, 22)
	emptyIcon.LayoutOrder = 1
	emptyIcon.ZIndex = Z.Content + 3
	emptyIcon.Parent = emptyState
 
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.FontFace = BobloNEXT.Theme.FontRegular
	emptyLabel.Text = "No logs at the moment"
	emptyLabel.TextColor3 = BobloNEXT.Theme.TextDim
	emptyLabel.TextSize = 12
	emptyLabel.AutomaticSize = Enum.AutomaticSize.XY
	emptyLabel.Size = UDim2.fromOffset(0, 14)
	emptyLabel.LayoutOrder = 2
	emptyLabel.ZIndex = Z.Content + 3
	emptyLabel.Parent = emptyState
 
	local logs = {}
	local logCount = 0
	local counter = 0
	local autoScroll = true
 
	local function trimLogs()
		while logCount > maxLogs do
			local oldest = table.remove(logs, 1)
			if oldest then
				oldest:Destroy()
				logCount = logCount - 1
			else
				break
			end
		end
	end
 
	local function escapeRich(text)
		return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
	end
 
	local function addLog(message, messageType)
		message = tostring(message or "")
		if message == "" then return end
		trimLogs()
 
		counter = counter + 1
		local color = ConsoleColors[messageType] or BobloNEXT.Theme.Text
 
		local entry = Instance.new("TextLabel")
		entry.Name = "Entry"
		entry.BackgroundTransparency = 1
		entry.RichText = true
		entry.FontFace = BobloNEXT.Theme.FontRegular
		entry.TextSize = 12
		entry.TextWrapped = true
		entry.TextXAlignment = Enum.TextXAlignment.Left
		entry.TextYAlignment = Enum.TextYAlignment.Top
		entry.LineHeight = 1.25
		entry.AutomaticSize = Enum.AutomaticSize.Y
		entry.Size = UDim2.new(1, 0, 0, 14)
		entry.LayoutOrder = counter
		entry.ZIndex = Z.Content + 2
		entry.Text = string.format(
			'<font color="#%s" transparency="0.45">[%s]</font> <font color="#%s">%s</font>',
			BobloNEXT.Theme.TextDim:ToHex(), os.date("%H:%M:%S"),
			color:ToHex(), escapeRich(message)
		)
		entry.Parent = logsScroll
 
		table.insert(logs, entry)
		logCount = logCount + 1
		emptyState.Visible = false
 
		if autoScroll then
			task.defer(function()
				logsScroll.CanvasPosition = Vector2.new(0, logsScroll.AbsoluteCanvasSize.Y)
			end)
		end
	end
 
	jan:Add(logsScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local atBottom = logsScroll.CanvasPosition.Y >= logsScroll.AbsoluteCanvasSize.Y - logsScroll.AbsoluteWindowSize.Y - 20
		autoScroll = atBottom
	end))
 
	copyBtn.MouseButton1Click:Connect(function()
		local setclipboard = hasFn("setclipboard")
		if not setclipboard then return end
 
		local lines = {}
		for _, entry in ipairs(logs) do
			local clean = entry.Text
				:gsub('<font[^>]*>', "")
				:gsub("</font>", "")
				:gsub("&lt;", "<")
				:gsub("&gt;", ">")
				:gsub("&amp;", "&")
			table.insert(lines, clean)
		end
		setclipboard(table.concat(lines, "\n"))
 
		Tween(copyIcon, { ImageColor3 = Color3.fromRGB(120, 220, 140) }, 0.1)
		task.delay(0.4, function()
			if copyIcon.Parent then
				Tween(copyIcon, { ImageColor3 = BobloNEXT.Theme.TextDim }, 0.15)
			end
		end)
	end)
 
	local function clearLogs()
		for _, entry in ipairs(logs) do
			entry:Destroy()
		end
		table.clear(logs)
		logCount = 0
		emptyState.Visible = true
	end
 
	clearBtn.MouseButton1Click:Connect(clearLogs)
 
	if opts.AutoCapture ~= false then
		local LogService = game:GetService("LogService")
		jan:Add(LogService.MessageOut:Connect(addLog))
	end
 
	return {
		Instance = container,
		Log = function(_, message, messageType) addLog(message, messageType) end,
		Clear = function() clearLogs() end,
		Destroy = function() container:Destroy() end,
	}
end
 
function Tab:AddTable(opts)
	opts = opts or {}
	local jan = self._janitor
	local title = opts.Title or "Table"
	local hasDesc = opts.Description and opts.Description ~= ""
	local columns = opts.Columns or {}
	local rowHeight = opts.RowHeight or 30
	local bodyHeight = opts.Height or 200
	local sortable = opts.Sortable ~= false
	local striped = opts.Striped ~= false
 
	local totalWeight = 0
	for _, col in ipairs(columns) do
		col.Weight = col.Weight or 1
		totalWeight = totalWeight + col.Weight
	end
	if totalWeight <= 0 then totalWeight = 1 end
 
	local function colAlign(col)
		if col.Align == "Right" then return Enum.TextXAlignment.Right end
		if col.Align == "Center" then return Enum.TextXAlignment.Center end
		return Enum.TextXAlignment.Left
	end
 
	local function colX(index)
		local w = 0
		for i = 1, index - 1 do w = w + columns[i].Weight end
		return w / totalWeight
	end
 
	local PAD = 12
	local HEADER_H = hasDesc and 32 or 16
	local COLHEAD_H = 26
	local GAP1, GAP2 = 10, 6
	local colHeadY = PAD + HEADER_H + GAP1
	local scrollY = colHeadY + COLHEAD_H + GAP2
	local totalHeight = scrollY + bodyHeight + PAD
 
	local container = Instance.new("Frame")
	container.Name = "Table"
	container.BackgroundColor3 = BobloNEXT.Theme.Surface
	container.BackgroundTransparency = 0.35
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Size = UDim2.new(1, 0, 0, totalHeight)
	container.ZIndex = Z.Content
	container.Parent = self._page
	Corner(container, BobloNEXT.Theme.CornerRadiusSm)
	Stroke(container, Color3.new(1, 1, 1), 1, 0.92)
	self._window:_RegisterSearchable(self, title, container)
 
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = BobloNEXT.Theme.Font
	titleLabel.Text = title
	titleLabel.TextColor3 = BobloNEXT.Theme.Text
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.Position = UDim2.fromOffset(PAD, PAD)
	titleLabel.Size = UDim2.new(1, -PAD * 2, 0, 16)
	titleLabel.ZIndex = Z.Content + 1
	titleLabel.Parent = container
 
	if hasDesc then
		local descLabel = Instance.new("TextLabel")
		descLabel.BackgroundTransparency = 1
		descLabel.FontFace = BobloNEXT.Theme.FontRegular
		descLabel.Text = opts.Description
		descLabel.TextColor3 = BobloNEXT.Theme.TextDim
		descLabel.TextSize = 12
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.Position = UDim2.fromOffset(PAD, PAD + 18)
		descLabel.Size = UDim2.new(1, -PAD * 2, 0, 14)
		descLabel.ZIndex = Z.Content + 1
		descLabel.Parent = container
	end
 
	local colHead = Instance.new("Frame")
	colHead.Name = "ColumnHeader"
	colHead.BackgroundTransparency = 1
	colHead.Position = UDim2.fromOffset(PAD, colHeadY)
	colHead.Size = UDim2.new(1, -PAD * 2, 0, COLHEAD_H)
	colHead.ZIndex = Z.Content + 1
	colHead.Parent = container
 
	local sortState = { Key = nil, Asc = true }
	local headerLabels = {}
 
	for ci, col in ipairs(columns) do
		local x0 = colX(ci)
		local wFrac = col.Weight / totalWeight
 
		local cellBtn = Instance.new("TextButton")
		cellBtn.Name = "Col" .. ci
		cellBtn.Text = ""
		cellBtn.AutoButtonColor = false
		cellBtn.BackgroundTransparency = 1
		cellBtn.Position = UDim2.new(x0, ci > 1 and 4 or 0, 0, 0)
		cellBtn.Size = UDim2.new(wFrac, ci > 1 and -4 or 0, 1, 0)
		cellBtn.ZIndex = Z.Content + 2
		cellBtn.Parent = colHead
 
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.FontFace = BobloNEXT.Theme.Font
		lbl.Text = tostring(col.Label or col.Key or "")
		lbl.TextColor3 = BobloNEXT.Theme.TextDim
		lbl.TextSize = 12
		lbl.TextXAlignment = colAlign(col)
		lbl.TextTruncate = Enum.TextTruncate.AtEnd
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.ZIndex = Z.Content + 3
		lbl.Parent = cellBtn
 
		headerLabels[col.Key] = { Lbl = lbl, Text = tostring(col.Label or col.Key or "") }
 
		if sortable then
			cellBtn.MouseEnter:Connect(function()
				if sortState.Key ~= col.Key then Tween(lbl, { TextColor3 = BobloNEXT.Theme.Text }, 0.12) end
			end)
			cellBtn.MouseLeave:Connect(function()
				if sortState.Key ~= col.Key then Tween(lbl, { TextColor3 = BobloNEXT.Theme.TextDim }, 0.12) end
			end)
		end
	end
 
	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = Color3.new(1, 1, 1)
	divider.BackgroundTransparency = 0.92
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromOffset(0, colHeadY + COLHEAD_H)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.ZIndex = Z.Content + 1
	divider.Parent = container
 
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, scrollY)
	scroll.Size = UDim2.new(1, 0, 0, bodyHeight)
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 0
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ZIndex = Z.Content + 1
	scroll.Parent = container
 
	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingLeft = UDim.new(0, PAD)
	scrollPad.PaddingRight = UDim.new(0, PAD)
	scrollPad.Parent = scroll
 
	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Parent = scroll
 
	AddScrollbar(scroll)
	AddContentScrollThumb(scroll, rowsLayout, container, jan)
 
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.FontFace = BobloNEXT.Theme.FontRegular
	emptyLabel.Text = "No rows"
	emptyLabel.TextColor3 = BobloNEXT.Theme.TextDim
	emptyLabel.TextSize = 12
	emptyLabel.Position = UDim2.fromOffset(PAD, scrollY + 10)
	emptyLabel.Size = UDim2.new(1, -PAD * 2, 0, 16)
	emptyLabel.Visible = false
	emptyLabel.ZIndex = Z.Content + 1
	emptyLabel.Parent = container
 
	local currentRows = {}
	local rowFrames = {}
 
	local function clearRowFrames()
		for _, f in ipairs(rowFrames) do f:Destroy() end
		table.clear(rowFrames)
	end
 
	local function renderRows()
		clearRowFrames()
		emptyLabel.Visible = #currentRows == 0
		for ri, row in ipairs(currentRows) do
			local rowFrame = Instance.new("Frame")
			rowFrame.Name = "Row" .. ri
			rowFrame.BackgroundColor3 = Color3.new(1, 1, 1)
			rowFrame.BackgroundTransparency = (striped and ri % 2 == 0) and 0.97 or 1
			rowFrame.BorderSizePixel = 0
			rowFrame.LayoutOrder = ri
			rowFrame.Size = UDim2.new(1, 0, 0, rowHeight)
			rowFrame.ZIndex = Z.Content + 2
			rowFrame.Parent = scroll
 
			for ci, col in ipairs(columns) do
				local x0 = colX(ci)
				local wFrac = col.Weight / totalWeight
 
				local cell = Instance.new("TextLabel")
				cell.Name = "Cell" .. ci
				cell.BackgroundTransparency = 1
				cell.FontFace = BobloNEXT.Theme.FontRegular
				cell.Text = tostring(row[col.Key] == nil and "" or row[col.Key])
				cell.TextColor3 = BobloNEXT.Theme.Text
				cell.TextSize = 12
				cell.TextXAlignment = colAlign(col)
				cell.TextTruncate = Enum.TextTruncate.AtEnd
				cell.Position = UDim2.new(x0, ci > 1 and 4 or 0, 0, 0)
				cell.Size = UDim2.new(wFrac, ci > 1 and -4 or 0, 1, 0)
				cell.ZIndex = Z.Content + 3
				cell.Parent = rowFrame
			end
 
			table.insert(rowFrames, rowFrame)
		end
	end
 
	local function compareValues(av, bv)
		local an, bn = tonumber(av), tonumber(bv)
		if an and bn then
			if an == bn then return 0 end
			return an < bn and -1 or 1
		end
		local as, bs = tostring(av or ""), tostring(bv or "")
		if as == bs then return 0 end
		return as < bs and -1 or 1
	end
 
	local function applySort()
		if not sortState.Key then return end
		table.sort(currentRows, function(a, b)
			local c = compareValues(a[sortState.Key], b[sortState.Key])
			if sortState.Asc then return c < 0 else return c > 0 end
		end)
		renderRows()
	end
 
	if sortable then
		for ci, col in ipairs(columns) do
			local cellBtn = colHead:FindFirstChild("Col" .. ci)
			if cellBtn then
				cellBtn.MouseButton1Click:Connect(function()
					if sortState.Key == col.Key then
						sortState.Asc = not sortState.Asc
					else
						sortState.Key = col.Key
						sortState.Asc = true
					end
					for key, info in pairs(headerLabels) do
						local arrow = ""
						if key == sortState.Key then arrow = sortState.Asc and "  \226\150\178" or "  \226\150\188" end
						info.Lbl.Text = info.Text .. arrow
						info.Lbl.TextColor3 = (key == sortState.Key) and BobloNEXT.Theme.Text or BobloNEXT.Theme.TextDim
					end
					applySort()
				end)
			end
		end
	end
 
	local api = {
		Instance = container,
		SetRows = function(_, rows)
			currentRows = rows or {}
			if sortState.Key then applySort() else renderRows() end
		end,
		GetRows = function() return currentRows end,
		Destroy = function() container:Destroy() end,
	}
 
	api:SetRows(opts.Rows or {})
 
	return api
end
 
local function Serialize(value)
	local t = typeof(value)
	if t == "Color3" then
		return { __t = "Color3", r = value.R, g = value.G, b = value.B }
	elseif t == "EnumItem" then
		return { __t = "Enum", v = tostring(value) }
	elseif t == "table" then
		local out = {}
		for i, v in ipairs(value) do out[i] = Serialize(v) end
		return out
	end
	return value
end
 
local function Deserialize(value)
	if type(value) ~= "table" then return value end
	if value.__t == "Color3" then
		return Color3.new(value.r, value.g, value.b)
	elseif value.__t == "Enum" then
		local parts = string.split(value.v, ".")
		local ok, result = pcall(function()
			return Enum[parts[2]][parts[3]]
		end)
		return ok and result or nil
	end
	local out = {}
	for i, v in ipairs(value) do out[i] = Deserialize(v) end
	return out
end
 
function Tab:AddCardGrid(opts)
	opts = opts or {}
	local height = opts.Height or 380
	local sorts = opts.Sorts or {}
	local pageSize = opts.PageSize or 20
	local showSearch = opts.Search ~= false
	local descriptionHeight = opts.DescriptionHeight or 28
	local showNativeScrollbar = opts.ShowScrollbar == true
	local cardPadding = opts.CardPadding or 10
 
	local outer = Instance.new("Frame")
	outer.Name = "CardGrid"
	outer.BackgroundColor3 = Color3.new(1, 1, 1)
	outer.BackgroundTransparency = 0.97
	outer.BorderSizePixel = 0
	outer.Size = UDim2.new(1, 0, 0, height)
	outer.ZIndex = Z.Content
	outer.Parent = self._page
	Corner(outer, BobloNEXT.Theme.CornerRadiusSm)
	Stroke(outer, Color3.new(1, 1, 1), 1, 0.95)
	self._window:_RegisterSearchable(self, opts.Title or "Cards", outer)
 
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = Z.Content + 1
	content.Parent = outer
 
	local OUTER_V_PAD = opts.OuterPadding or 18
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, OUTER_V_PAD)
	pad.PaddingBottom = UDim.new(0, OUTER_V_PAD)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = content
 
	local TOP_H, TABS_H = 32, 28
	local headerH = 0
	if showSearch then headerH = headerH + TOP_H end
	if #sorts > 1 then
		if headerH > 0 then headerH = headerH + 8 end
		headerH = headerH + TABS_H
	end
	if headerH > 0 then headerH = headerH + 10 end
 
	local searchBox
	if showSearch then
		local searchPill = Instance.new("Frame")
		searchPill.BackgroundColor3 = Color3.new(1, 1, 1)
		searchPill.BackgroundTransparency = 0.92
		searchPill.BorderSizePixel = 0
		searchPill.Size = UDim2.new(1, 0, 0, TOP_H)
		searchPill.ZIndex = Z.Content + 1
		searchPill.Parent = content
		Corner(searchPill, 9)
		local searchStroke = Stroke(searchPill, Color3.new(1, 1, 1), 1, 0.88)
 
		local searchIcon = Instance.new("ImageLabel")
		searchIcon.BackgroundTransparency = 1
		searchIcon.Image = ResolveIcon("search")
		searchIcon.ImageColor3 = BobloNEXT.Theme.TextDim
		searchIcon.Size = UDim2.fromOffset(13, 13)
		searchIcon.AnchorPoint = Vector2.new(0, 0.5)
		searchIcon.Position = UDim2.new(0, 10, 0.5, 0)
		searchIcon.ZIndex = Z.Content + 2
		searchIcon.Parent = searchPill
 
		searchBox = Instance.new("TextBox")
		searchBox.ClearTextOnFocus = false
		searchBox.FontFace = BobloNEXT.Theme.FontRegular
		searchBox.PlaceholderText = opts.SearchPlaceholder or "Search by name / tags..."
		searchBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 122)
		searchBox.Text = ""
		searchBox.TextColor3 = BobloNEXT.Theme.Text
		searchBox.TextSize = 13
		searchBox.TextXAlignment = Enum.TextXAlignment.Left
		searchBox.TextYAlignment = Enum.TextYAlignment.Center
		searchBox.BackgroundTransparency = 1
		searchBox.ClipsDescendants = true
		searchBox.Position = UDim2.fromOffset(30, 0)
		searchBox.Size = UDim2.new(1, -40, 1, 0)
		searchBox.ZIndex = Z.Content + 2
		searchBox.Parent = searchPill
 
		searchBox.Focused:Connect(function()
			Tween(searchStroke, { Color = BobloNEXT.Theme.Accent, Transparency = 0.3 }, 0.15)
		end)
		searchBox.FocusLost:Connect(function()
			Tween(searchStroke, { Color = Color3.new(1, 1, 1), Transparency = 0.88 }, 0.15)
		end)
	end
 
	local currentSort = opts.DefaultSort or sorts[1]
	local sortButtons = {}
	if #sorts > 1 then
		local tabsRow = Instance.new("Frame")
		tabsRow.BackgroundTransparency = 1
		tabsRow.Position = UDim2.fromOffset(0, showSearch and (TOP_H + 8) or 0)
		tabsRow.Size = UDim2.new(1, 0, 0, TABS_H)
		tabsRow.ZIndex = Z.Content + 1
		tabsRow.Parent = content
 
		local tabsLayout = Instance.new("UIListLayout")
		tabsLayout.FillDirection = Enum.FillDirection.Horizontal
		tabsLayout.Padding = UDim.new(0, 6)
		tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		tabsLayout.Parent = tabsRow
 
		for i, sortName in ipairs(sorts) do
			local btn = Instance.new("TextButton")
			btn.AutoButtonColor = false
			btn.Text = ""
			btn.BackgroundColor3 = Color3.new(1, 1, 1)
			btn.BackgroundTransparency = (sortName == currentSort) and 0.85 or 1
			btn.BorderSizePixel = 0
			btn.AutomaticSize = Enum.AutomaticSize.X
			btn.Size = UDim2.fromOffset(0, TABS_H)
			btn.LayoutOrder = i
			btn.ZIndex = Z.Content + 1
			btn.Parent = tabsRow
			Corner(btn, 7)
 
			local btnPad = Instance.new("UIPadding")
			btnPad.PaddingLeft = UDim.new(0, 10)
			btnPad.PaddingRight = UDim.new(0, 10)
			btnPad.Parent = btn
 
			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.FontFace = BobloNEXT.Theme.Font
			lbl.Text = string.upper(sortName)
			lbl.TextColor3 = (sortName == currentSort) and BobloNEXT.Theme.Text or BobloNEXT.Theme.TextDim
			lbl.TextSize = 11
			lbl.AutomaticSize = Enum.AutomaticSize.X
			lbl.Size = UDim2.fromOffset(0, TABS_H)
			lbl.ZIndex = Z.Content + 2
			lbl.Parent = btn
 
			sortButtons[sortName] = { Button = btn, Label = lbl }
		end
	end
 
	local gridScroll = Instance.new("ScrollingFrame")
	gridScroll.BackgroundTransparency = 1
	gridScroll.BorderSizePixel = 0
	gridScroll.Position = UDim2.fromOffset(0, headerH)
	gridScroll.Size = UDim2.new(1, 0, 1, -headerH)
	gridScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	gridScroll.ScrollingEnabled = true
	gridScroll.Active = true
	gridScroll.ElasticBehavior = Enum.ElasticBehavior.Never
	gridScroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	gridScroll.ScrollBarThickness = showNativeScrollbar and (opts.ScrollBarThickness or 4) or 0
	gridScroll.ScrollBarImageColor3 = BobloNEXT.Theme.TextDim
	gridScroll.ScrollBarImageTransparency = 0.35
	gridScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	gridScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	gridScroll.ZIndex = Z.Content + 1
	gridScroll.Parent = content
 
	-- Reserve room for the visible scrollbar so cards never sit underneath it.
	local GRID_RIGHT_PAD = gridScroll.ScrollBarThickness > 0 and (gridScroll.ScrollBarThickness + 6) or 16
	local GRID_TOP_PAD = 8
	local GRID_BOTTOM_PAD = 8
	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingTop = UDim.new(0, GRID_TOP_PAD)
	gridPad.PaddingRight = UDim.new(0, GRID_RIGHT_PAD)
	gridPad.Parent = gridScroll
 
	local MIN_CELL_W = opts.CardMinWidth or opts.CardWidth or 190
	local FIXED_COLUMNS = opts.Columns
	local MAX_COLUMNS = opts.MaxColumns
	local CELL_H = opts.CardHeight or 88
	local CELL_GAP = 8
 
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellPadding = UDim2.fromOffset(CELL_GAP, CELL_GAP)
	gridLayout.CellSize = UDim2.fromOffset(MIN_CELL_W, CELL_H)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = gridScroll
 
	local function updateGridCanvas()
		gridScroll.CanvasSize = UDim2.new(
			0, 0, 0,
			math.max(0, (gridLayout.AbsoluteContentSize.Y / GetUIScale()) + GRID_TOP_PAD + GRID_BOTTOM_PAD)
		)
	end
	gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateGridCanvas)
	task.defer(updateGridCanvas)
 
	local SAFETY_MARGIN = 4
	local currentColumns = 1
	local function relayoutGridColumns()
		local availableW = (gridScroll.AbsoluteSize.X / GetUIScale()) - GRID_RIGHT_PAD - SAFETY_MARGIN
		if availableW <= 0 then return end
		local columns = FIXED_COLUMNS and math.max(1, FIXED_COLUMNS)
			or math.max(1, math.floor((availableW + CELL_GAP) / (MIN_CELL_W + CELL_GAP)))
		if not FIXED_COLUMNS and MAX_COLUMNS then columns = math.min(columns, math.max(1, MAX_COLUMNS)) end
		local cellW = math.floor((availableW - (columns - 1) * CELL_GAP) / columns)
		currentColumns = columns
		gridLayout.CellSize = UDim2.fromOffset(math.max(1, cellW), CELL_H)
	end
	gridScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayoutGridColumns)
	task.defer(relayoutGridColumns)
 
	if not showNativeScrollbar then
		AddScrollbar(gridScroll)
		AddContentScrollThumb(gridScroll, gridLayout, outer, self._janitor)
	end
 
	local MAX_OUTER_H = opts.Height or 300
	local showingCards = false
 
	local function applyOuterHeight(target)
		Tween(outer, { Size = UDim2.new(1, 0, 0, target) }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end
 
	local EMPTY_STATE_H = 220
	local function resizeOuterEmpty()
		showingCards = false
		if opts.FixedHeight then
			applyOuterHeight(MAX_OUTER_H)
			return
		end
		applyOuterHeight(math.min(headerH + OUTER_V_PAD + EMPTY_STATE_H + OUTER_V_PAD, MAX_OUTER_H))
	end
 
	local function resizeOuterToGridContent()
		if not showingCards then return end
		if opts.FixedHeight then
			applyOuterHeight(MAX_OUTER_H)
			return
		end
		local contentH = gridLayout.AbsoluteContentSize.Y
		if contentH <= 0 then return end
		local target = math.min(headerH + OUTER_V_PAD + contentH + OUTER_V_PAD, MAX_OUTER_H)
		applyOuterHeight(target)
	end
	gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resizeOuterToGridContent)
 
	local statusHolder = Instance.new("Frame")
	statusHolder.BackgroundTransparency = 1
	statusHolder.Position = UDim2.fromOffset(0, headerH)
	statusHolder.Size = UDim2.new(1, 0, 1, -headerH)
	statusHolder.Visible = false
	statusHolder.ZIndex = Z.Content + 2
	statusHolder.Parent = content
 
	local statusLayout = Instance.new("UIListLayout")
	statusLayout.FillDirection = Enum.FillDirection.Vertical
	statusLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	statusLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	statusLayout.Padding = UDim.new(0, 6)
	statusLayout.Parent = statusHolder
 
	local statusIcon = Instance.new("ImageLabel")
	statusIcon.BackgroundTransparency = 1
	statusIcon.ImageColor3 = BobloNEXT.Theme.TextDim
	statusIcon.Size = UDim2.fromOffset(24, 24)
	statusIcon.LayoutOrder = 1
	statusIcon.Visible = false
	statusIcon.ZIndex = Z.Content + 3
	statusIcon.Parent = statusHolder
 
	local statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.FontFace = BobloNEXT.Theme.FontRegular
	statusLabel.TextColor3 = BobloNEXT.Theme.TextDim
	statusLabel.TextSize = 12
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Center
	statusLabel.AutomaticSize = Enum.AutomaticSize.Y
	statusLabel.Size = UDim2.new(1, -20, 0, 16)
	statusLabel.LayoutOrder = 2
	statusLabel.ZIndex = Z.Content + 3
	statusLabel.Parent = statusHolder
 
	local STATUS_ICONS = { loading = "loader-circle", empty = "frown", error = "triangle-alert" }
 
	local function openCardMenu(anchor, actions)
		if type(actions) ~= "table" or #actions == 0 then return end
 
		local popup, backdrop
		local function closeMenu()
			RegisterPopupClose(closeMenu)
			if backdrop then backdrop:Destroy(); backdrop = nil end
			if popup then popup:Destroy(); popup = nil end
		end
 
		RegisterPopupOpen(closeMenu)
		backdrop = MakePopupBackdrop(closeMenu)
 
		local rowH, gap, pad = 32, 2, 8
		local popupW = 190
		local popupH = pad * 2 + #actions * rowH + math.max(0, #actions - 1) * gap
		local scale = GetUIScale()
		local view = ViewportSize()
		local anchorPos, anchorSize = anchor.AbsolutePosition, anchor.AbsoluteSize
		local px = (anchorPos.X + anchorSize.X) / scale - popupW
		local py = (anchorPos.Y + anchorSize.Y) / scale + 5
		px = SafeClamp(px, 8, view.X / scale - popupW - 8)
		py = SafeClamp(py, 8, view.Y / scale - popupH - 8)
 
		popup = Instance.new("CanvasGroup")
		popup.Name = "CardActionsPopup"
		popup.Active = true
		popup.BackgroundColor3 = BobloNEXT.Theme.Background
		popup.BackgroundTransparency = 0.04
		popup.BorderSizePixel = 0
		popup.Position = UDim2.fromOffset(math.round(px), math.round(py))
		popup.Size = UDim2.fromOffset(popupW, popupH)
		popup.ZIndex = Z.Popup
		popup.Parent = BobloNEXT._Root
		Corner(popup, 10)
		Stroke(popup, Color3.new(1, 1, 1), 1, 0.9)
		GlassLayer(popup, 10, 0.985)
 
		local actionsHolder = Instance.new("Frame")
		actionsHolder.Name = "Actions"
		actionsHolder.BackgroundTransparency = 1
		actionsHolder.Size = UDim2.fromScale(1, 1)
		actionsHolder.ZIndex = Z.Popup + 1
		actionsHolder.Parent = popup
 
		local popupPad = Instance.new("UIPadding")
		popupPad.PaddingTop = UDim.new(0, pad)
		popupPad.PaddingBottom = UDim.new(0, pad)
		popupPad.PaddingLeft = UDim.new(0, pad)
		popupPad.PaddingRight = UDim.new(0, pad)
		popupPad.Parent = actionsHolder
 
		local popupLayout = Instance.new("UIListLayout")
		popupLayout.Padding = UDim.new(0, gap)
		popupLayout.SortOrder = Enum.SortOrder.LayoutOrder
		popupLayout.Parent = actionsHolder
 
		for i, action in ipairs(actions) do
			local button = Instance.new("TextButton")
			button.Name = "Action" .. i
			button.Text = ""
			button.AutoButtonColor = false
			button.BackgroundColor3 = Color3.new(1, 1, 1)
			button.BackgroundTransparency = 1
			button.BorderSizePixel = 0
			button.Size = UDim2.new(1, 0, 0, rowH)
			button.LayoutOrder = i
			button.ZIndex = Z.Popup + 1
			button.Parent = actionsHolder
			Corner(button, 7)
 
			local icon = Instance.new("ImageLabel")
			icon.BackgroundTransparency = 1
			icon.Image = ResolveIcon(action.Icon or "circle")
			icon.ImageColor3 = action.Danger and BobloNEXT.Theme.Danger or BobloNEXT.Theme.TextDim
			icon.Size = UDim2.fromOffset(14, 14)
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, 9, 0.5, 0)
			icon.ZIndex = Z.Popup + 2
			icon.Parent = button
 
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.FontFace = BobloNEXT.Theme.FontRegular
			label.Text = tostring(action.Text or "Action")
			label.TextColor3 = action.Danger and BobloNEXT.Theme.Danger or BobloNEXT.Theme.Text
			label.TextSize = 12
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.Position = UDim2.fromOffset(31, 0)
			label.Size = UDim2.new(1, -39, 1, 0)
			label.ZIndex = Z.Popup + 2
			label.Parent = button
 
			button.MouseEnter:Connect(function()
				Tween(button, { BackgroundTransparency = 0.9 }, 0.1)
			end)
			button.MouseLeave:Connect(function()
				Tween(button, { BackgroundTransparency = 1 }, 0.1)
			end)
			button.MouseButton1Click:Connect(function()
				closeMenu()
				if action.Callback then task.spawn(action.Callback) end
			end)
		end
	end
 
	local function buildCard(item, animDelay)
		local cell = Instance.new("Frame")
		cell.Name = "GridCard"
		cell.BackgroundColor3 = Color3.new(1, 1, 1)
		cell.BackgroundTransparency = 1
		cell.BorderSizePixel = 0
		cell.ClipsDescendants = true
		cell.ZIndex = Z.Content + 2
		cell.Parent = gridScroll
		Corner(cell, BobloNEXT.Theme.CornerRadiusSm)
		local cellStroke = Stroke(cell, Color3.new(1, 1, 1), 1, 1)
 
		local cellScale = Instance.new("UIScale")
		cellScale.Scale = 0.9
		cellScale.Parent = cell
 
		task.delay(animDelay or 0, function()
			if not cell.Parent then return end
			Tween(cell, { BackgroundTransparency = 0.94 }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			Tween(cellStroke, { Transparency = 0.9 }, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			Tween(cellScale, { Scale = 1 }, 0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end)
 
		local cellPad = Instance.new("UIPadding")
		cellPad.PaddingTop = UDim.new(0, cardPadding)
		cellPad.PaddingBottom = UDim.new(0, cardPadding)
		cellPad.PaddingLeft = UDim.new(0, cardPadding)
		cellPad.PaddingRight = UDim.new(0, cardPadding)
		cellPad.Parent = cell
 
		local textX = 0
		if item.Icon then
			local ICON_BOX = 24
			local iconHolder = Instance.new("Frame")
			iconHolder.BackgroundColor3 = Color3.new(1, 1, 1)
			iconHolder.BackgroundTransparency = 0.9
			iconHolder.BorderSizePixel = 0
			iconHolder.Size = UDim2.fromOffset(ICON_BOX, ICON_BOX)
			iconHolder.ZIndex = Z.Content + 3
			iconHolder.Parent = cell
			Corner(iconHolder, 7)
 
			local iconImg = Instance.new("ImageLabel")
			iconImg.BackgroundTransparency = 1
			iconImg.Image = ResolveIcon(item.Icon)
			iconImg.ImageColor3 = BobloNEXT.Theme.Accent
			iconImg.Size = UDim2.fromOffset(13, 13)
			iconImg.AnchorPoint = Vector2.new(0.5, 0.5)
			iconImg.Position = UDim2.fromScale(0.5, 0.5)
			iconImg.ZIndex = Z.Content + 4
			iconImg.Parent = iconHolder
 
			textX = ICON_BOX + 8
		end
 
		local hasPrimaryAction = item.Callback ~= nil
		local hasSecondaryAction = item.SecondaryCallback ~= nil
		local hasMenuAction = item.Menu and #item.Menu > 0
		local trailingReserve = (hasPrimaryAction and 26 or 0)
			+ (hasSecondaryAction and 30 or 0)
			+ (hasMenuAction and 30 or 0)
		if hasPrimaryAction then
 
			local actionBadge = Instance.new("Frame")
			actionBadge.Name = "LoadBadge"
			actionBadge.BackgroundColor3 = BobloNEXT.Theme.Accent
			actionBadge.BackgroundTransparency = 0.8
			actionBadge.BorderSizePixel = 0
			actionBadge.AnchorPoint = Vector2.new(1, 0)
			actionBadge.Position = UDim2.new(1, 0, 0, 0)
			actionBadge.Size = UDim2.fromOffset(22, 22)
			actionBadge.ZIndex = Z.Content + 6
			actionBadge.Parent = cell
			Corner(actionBadge, 7)
 
			local actionIcon = Instance.new("ImageLabel")
			actionIcon.BackgroundTransparency = 1
			actionIcon.Image = ResolveIcon(item.ActionIcon or "download")
			actionIcon.ImageColor3 = BobloNEXT.Theme.Accent
			actionIcon.Size = UDim2.fromOffset(12, 12)
			actionIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			actionIcon.Position = UDim2.fromScale(0.5, 0.5)
			actionIcon.ZIndex = Z.Content + 7
			actionIcon.Parent = actionBadge
 
			local actionClick = Instance.new("TextButton")
			actionClick.Text = ""
			actionClick.AutoButtonColor = false
			actionClick.BackgroundTransparency = 1
			actionClick.Size = UDim2.fromScale(1, 1)
			actionClick.ZIndex = Z.Content + 8
			actionClick.Parent = actionBadge
			actionClick.MouseButton1Click:Connect(function()
				item.Callback()
			end)
		end
 
		if hasSecondaryAction then
			local secondaryBadge = Instance.new("Frame")
			secondaryBadge.Name = "SecondaryActionBadge"
			secondaryBadge.BackgroundColor3 = item.SecondaryDanger
				and Color3.fromRGB(225, 76, 88)
				or BobloNEXT.Theme.Accent
			secondaryBadge.BackgroundTransparency = item.SecondaryDanger and 0.82 or 0.8
			secondaryBadge.BorderSizePixel = 0
			secondaryBadge.AnchorPoint = Vector2.new(1, 0)
			secondaryBadge.Position = UDim2.new(1, hasPrimaryAction and -30 or 0, 0, 0)
			secondaryBadge.Size = UDim2.fromOffset(22, 22)
			secondaryBadge.ZIndex = Z.Content + 6
			secondaryBadge.Parent = cell
			Corner(secondaryBadge, 7)
 
			local secondaryIcon = Instance.new("ImageLabel")
			secondaryIcon.BackgroundTransparency = 1
			secondaryIcon.Image = ResolveIcon(item.SecondaryIcon or "trash-2")
			secondaryIcon.ImageColor3 = item.SecondaryDanger
				and Color3.fromRGB(255, 125, 135)
				or BobloNEXT.Theme.Accent
			secondaryIcon.Size = UDim2.fromOffset(12, 12)
			secondaryIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			secondaryIcon.Position = UDim2.fromScale(0.5, 0.5)
			secondaryIcon.ZIndex = Z.Content + 7
			secondaryIcon.Parent = secondaryBadge
 
			local secondaryClick = Instance.new("TextButton")
			secondaryClick.Text = ""
			secondaryClick.AutoButtonColor = false
			secondaryClick.BackgroundTransparency = 1
			secondaryClick.Size = UDim2.fromScale(1, 1)
			secondaryClick.ZIndex = Z.Content + 8
			secondaryClick.Parent = secondaryBadge
			secondaryClick.MouseButton1Click:Connect(function()
				item.SecondaryCallback()
			end)
		end
 
		if hasMenuAction then
			local menuBadge = Instance.new("Frame")
			menuBadge.Name = "MenuBadge"
			menuBadge.BackgroundColor3 = BobloNEXT.Theme.Accent
			menuBadge.BackgroundTransparency = 0.8
			menuBadge.BorderSizePixel = 0
			menuBadge.AnchorPoint = Vector2.new(1, 0)
			menuBadge.Position = UDim2.new(
				1,
				-((hasPrimaryAction and 30 or 0) + (hasSecondaryAction and 30 or 0)),
				0,
				0
			)
			menuBadge.Size = UDim2.fromOffset(22, 22)
			menuBadge.ZIndex = Z.Content + 6
			menuBadge.Parent = cell
			Corner(menuBadge, 7)
 
			local menuIcon = Instance.new("ImageLabel")
			menuIcon.BackgroundTransparency = 1
			menuIcon.Image = ResolveIcon("Lucide:settings")
			menuIcon.ImageColor3 = BobloNEXT.Theme.Accent
			menuIcon.Size = UDim2.fromOffset(12, 12)
			menuIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			menuIcon.Position = UDim2.fromScale(0.5, 0.5)
			menuIcon.ZIndex = Z.Content + 7
			menuIcon.Parent = menuBadge
 
			local menuClick = Instance.new("TextButton")
			menuClick.Text = ""
			menuClick.AutoButtonColor = false
			menuClick.BackgroundTransparency = 1
			menuClick.Size = UDim2.fromScale(1, 1)
			menuClick.ZIndex = Z.Content + 8
			menuClick.Parent = menuBadge
			menuClick.MouseButton1Click:Connect(function()
				openCardMenu(menuBadge, item.Menu)
			end)
		end
 
		local cursorY = 0
 
		local titleLbl = Instance.new("TextLabel")
		titleLbl.BackgroundTransparency = 1
		titleLbl.FontFace = BobloNEXT.Theme.Font
		titleLbl.Text = item.Title or "Untitled"
		titleLbl.TextColor3 = BobloNEXT.Theme.Text
		titleLbl.TextSize = 13
		titleLbl.TextXAlignment = Enum.TextXAlignment.Left
		titleLbl.TextYAlignment = Enum.TextYAlignment.Center
		titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
		titleLbl.Position = UDim2.fromOffset(textX, item.Icon and 4 or cursorY)
		titleLbl.Size = UDim2.new(1, -(textX + trailingReserve), 0, item.Icon and 24 or 16)
		titleLbl.ZIndex = Z.Content + 3
		titleLbl.Parent = cell
		cursorY = math.max(item.Icon and (24 + 6) or 0, cursorY + 16 + 3)
 
		if item.Description and item.Description ~= "" then
 
			local descLbl = Instance.new("TextLabel")
			descLbl.BackgroundTransparency = 1
			descLbl.FontFace = BobloNEXT.Theme.FontRegular
			descLbl.Text = item.Description
			descLbl.TextColor3 = BobloNEXT.Theme.TextDim
			descLbl.TextSize = 11
			descLbl.TextWrapped = true
			descLbl.TextTruncate = Enum.TextTruncate.None
			descLbl.TextXAlignment = Enum.TextXAlignment.Left
			descLbl.TextYAlignment = Enum.TextYAlignment.Top
			descLbl.Position = UDim2.fromOffset(0, cursorY)
			descLbl.Size = UDim2.new(1, -trailingReserve, 0, descriptionHeight)
			descLbl.ZIndex = Z.Content + 3
			descLbl.Parent = cell
			cursorY = cursorY + descriptionHeight + 3
		end
 
		if item.Byline and item.Byline ~= "" then
			local bylineLbl = Instance.new("TextLabel")
			bylineLbl.BackgroundTransparency = 1
			bylineLbl.FontFace = BobloNEXT.Theme.FontRegular
			bylineLbl.Text = item.Byline
			bylineLbl.TextColor3 = BobloNEXT.Theme.TextDim
			bylineLbl.TextTransparency = 0.25
			bylineLbl.TextSize = 10
			bylineLbl.TextXAlignment = Enum.TextXAlignment.Left
			bylineLbl.TextTruncate = Enum.TextTruncate.AtEnd
			bylineLbl.Position = UDim2.fromOffset(0, cursorY)
			bylineLbl.Size = UDim2.new(1, -trailingReserve, 0, 12)
			bylineLbl.ZIndex = Z.Content + 3
			bylineLbl.Parent = cell
		end
 
		if item.Stats and #item.Stats > 0 then
			local statsRow = Instance.new("Frame")
			statsRow.BackgroundTransparency = 1
			statsRow.AnchorPoint = Vector2.new(0, 1)
			statsRow.Position = UDim2.new(0, 0, 1, 0)
			statsRow.Size = UDim2.new(1, 0, 0, 16)
			statsRow.ZIndex = Z.Content + 3
			statsRow.Parent = cell
 
			local statsLayout = Instance.new("UIListLayout")
			statsLayout.FillDirection = Enum.FillDirection.Horizontal
			statsLayout.Padding = UDim.new(0, 10)
			statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
			statsLayout.Parent = statsRow
 
			for i, stat in ipairs(item.Stats) do
 
				local statFrame = Instance.new(stat.Callback and "TextButton" or "Frame")
				statFrame.BackgroundTransparency = 1
				statFrame.AutomaticSize = Enum.AutomaticSize.X
				statFrame.Size = UDim2.fromOffset(0, 14)
				statFrame.LayoutOrder = i
				statFrame.ZIndex = Z.Content + 3
				statFrame.Parent = statsRow
				if stat.Callback then
					statFrame.Text = ""
					statFrame.AutoButtonColor = false
				end
 
				local statLayout = Instance.new("UIListLayout")
				statLayout.FillDirection = Enum.FillDirection.Horizontal
				statLayout.VerticalAlignment = Enum.VerticalAlignment.Center
				statLayout.Padding = UDim.new(0, 3)
				statLayout.Parent = statFrame
 
				local statIcon = Instance.new("ImageLabel")
				statIcon.BackgroundTransparency = 1
				statIcon.Image = ResolveIcon(stat.Icon or "circle")
				statIcon.ImageColor3 = BobloNEXT.Theme.TextDim
				statIcon.Size = UDim2.fromOffset(11, 11)
				statIcon.LayoutOrder = 1
				statIcon.ZIndex = Z.Content + 4
				statIcon.Parent = statFrame
 
				local statLbl = Instance.new("TextLabel")
				statLbl.BackgroundTransparency = 1
				statLbl.FontFace = BobloNEXT.Theme.FontRegular
				statLbl.Text = tostring(stat.Text or "")
				statLbl.TextColor3 = BobloNEXT.Theme.TextDim
				statLbl.TextSize = 10
				statLbl.AutomaticSize = Enum.AutomaticSize.X
				statLbl.Size = UDim2.fromOffset(0, 12)
				statLbl.LayoutOrder = 2
				statLbl.ZIndex = Z.Content + 4
				statLbl.Parent = statFrame
 
				if stat.Callback then
					statFrame.MouseEnter:Connect(function()
						Tween(statIcon, { ImageColor3 = BobloNEXT.Theme.Accent }, 0.1)
						Tween(statLbl, { TextColor3 = BobloNEXT.Theme.Accent }, 0.1)
					end)
					statFrame.MouseLeave:Connect(function()
						Tween(statIcon, { ImageColor3 = BobloNEXT.Theme.TextDim }, 0.1)
						Tween(statLbl, { TextColor3 = BobloNEXT.Theme.TextDim }, 0.1)
					end)
					statFrame.MouseButton1Click:Connect(function()
						task.spawn(stat.Callback)
					end)
				end
			end
		end
 
		if item.Callback then
 
			local hasInteractiveStat = false
			if item.Stats then
				for _, stat in ipairs(item.Stats) do
					if stat.Callback then hasInteractiveStat = true end
				end
			end
 
			local click = Instance.new("TextButton")
			click.Text = ""
			click.AutoButtonColor = false
			click.BackgroundTransparency = 1
			click.Size = hasInteractiveStat and UDim2.new(1, 0, 1, -20) or UDim2.fromScale(1, 1)
			click.ZIndex = Z.Content + 5
			click.Parent = cell
 
			click.MouseEnter:Connect(function()
				Tween(cell, { BackgroundTransparency = 0.88 }, 0.12)
				Tween(cellStroke, { Transparency = 0.8 }, 0.12)
			end)
			click.MouseLeave:Connect(function()
				Tween(cell, { BackgroundTransparency = 0.94 }, 0.12)
				Tween(cellStroke, { Transparency = 0.9 }, 0.12)
			end)
			click.MouseButton1Click:Connect(function()
				task.spawn(item.Callback)
			end)
		end
 
		return cell
	end
 
	local currentQuery = ""
	local loadToken = 0
 
	local function clearGrid()
		for _, child in ipairs(gridScroll:GetChildren()) do
			if child.Name == "GridCard" then child:Destroy() end
		end
	end
 
	local function setStatus(msg, kind)
		local visible = msg ~= nil and msg ~= ""
		statusLabel.Text = msg or ""
		statusHolder.Visible = visible
		local iconName = visible and STATUS_ICONS[kind]
		statusIcon.Visible = iconName ~= nil
		if iconName then
			statusIcon.Image = ResolveIcon(iconName)
		end
	end
 
	local function computeCellHeight(items)
		local hasIcon, hasDesc, hasByline, hasStats = false, false, false, false
		for _, item in ipairs(items) do
			if item.Icon then hasIcon = true end
			if item.Description and item.Description ~= "" then hasDesc = true end
			if item.Byline and item.Byline ~= "" then hasByline = true end
			if item.Stats and #item.Stats > 0 then hasStats = true end
		end
		local h = 20
		h = h + (hasIcon and 24 or 16) + 3
		if hasDesc then h = h + descriptionHeight + 3 end
		if hasByline then h = h + 12 end
		if hasStats then h = h + 16 + 4 end
		return h
	end
 
	local function refresh()
		if not opts.Fetch then return end
		loadToken = loadToken + 1
		local myToken = loadToken
		clearGrid()
		setStatus(opts.LoadingText or "Loading...", "loading")
		resizeOuterEmpty()
		task.spawn(function()
			local ok, items, fetchErr = pcall(opts.Fetch, {
				Query = currentQuery,
				Sort = currentSort,
				PageSize = pageSize,
			})
			if myToken ~= loadToken then return end
			if not ok then
				setStatus(opts.ErrorText or tostring(items), "error")
				resizeOuterEmpty()
				return
			end
			if fetchErr then
				setStatus(opts.ErrorText or tostring(fetchErr), "error")
				resizeOuterEmpty()
				return
			end
			items = items or {}
			if #items == 0 then
				setStatus(opts.EmptyText or "Nothing here yet.", "empty")
				resizeOuterEmpty()
				return
			end
			setStatus(nil)
			if opts.AutoCardHeight ~= false then
				CELL_H = math.max(computeCellHeight(items), opts.MinCardHeight or 0)
				gridLayout.CellSize = UDim2.new(
					gridLayout.CellSize.X.Scale, gridLayout.CellSize.X.Offset,
					0, CELL_H
				)
			end
			showingCards = true
			for i, item in ipairs(items) do
 
				buildCard(item, math.min(i - 1, 8) * 0.035)
			end
 
			task.spawn(function()
				RunService.Heartbeat:Wait()
				RunService.Heartbeat:Wait()
				if myToken == loadToken then resizeOuterToGridContent() end
			end)
		end)
	end
 
	if searchBox then
		local debounceToken = 0
		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			currentQuery = searchBox.Text
			debounceToken = debounceToken + 1
			local myDebounce = debounceToken
			task.delay(0.35, function()
				if myDebounce == debounceToken then refresh() end
			end)
		end)
	end
 
	for sortName, entry in pairs(sortButtons) do
		entry.Button.MouseButton1Click:Connect(function()
			if currentSort == sortName then return end
			currentSort = sortName
			for otherName, otherEntry in pairs(sortButtons) do
				local active = otherName == currentSort
				Tween(otherEntry.Button, { BackgroundTransparency = active and 0.85 or 1 }, 0.12)
				Tween(otherEntry.Label, { TextColor3 = active and BobloNEXT.Theme.Text or BobloNEXT.Theme.TextDim }, 0.12)
			end
			refresh()
		end)
	end
 
	if opts.AutoLoad ~= false and opts.Fetch then
		task.defer(refresh)
	end
 
	return {
		Instance = outer,
		Refresh = refresh,
		SetQuery = function(_, q)
			currentQuery = q or ""
			if searchBox then searchBox.Text = currentQuery end
			refresh()
		end,
		SetSort = function(_, s)
			currentSort = s
			refresh()
		end,
		Destroy = function() outer:Destroy() end,
	}
end
 
function BobloNEXT:GetConfig()
	local data = {}
	for flag, api in pairs(BobloNEXT.Flags) do
		if api.Get then
			local ok, value = pcall(api.Get)
			if ok then data[flag] = Serialize(value) end
		end
	end
	return data
end
 
function BobloNEXT:SetConfig(data, silent)
	if type(data) ~= "table" then return false end
	for flag, raw in pairs(data) do
		local api = BobloNEXT.Flags[flag]
		if api and api.Set then
			pcall(api.Set, api, Deserialize(raw), silent ~= false)
		end
	end
	return true
end
 
function BobloNEXT:ListUIElements()
	local out = {}
	for flag, api in pairs(BobloNEXT.Flags) do
		local ok, value = pcall(api.Get)
		table.insert(out, {
			Flag  = flag,
			Kind  = api.Kind,
			Label = api.Label,
			Value = ok and value or nil,
		})
	end
	table.sort(out, function(a, b) return a.Flag < b.Flag end)
	return out
end
 
function BobloNEXT:SetUIElementValue(flag, value, silent)
	local api = BobloNEXT.Flags[flag]
	if not api or not api.Set then
		return false, "Unknown UI element: " .. tostring(flag)
	end
	local ok, err = pcall(api.Set, api, value, silent ~= false)
	if not ok then return false, tostring(err) end
	return true
end
 
local CONFIGS_FOLDER = "BobloNEXT/Configs"
 
local function EnsureConfigsFolder()
	if not (fn_isfolder and fn_makefolder) then return false end
	local ok = pcall(function()
		if not fn_isfolder("BobloNEXT") then fn_makefolder("BobloNEXT") end
		if not fn_isfolder(CONFIGS_FOLDER) then fn_makefolder(CONFIGS_FOLDER) end
	end)
	return ok
end
 
local function SafeConfigName(name)
	name = tostring(name or "config"):gsub("[^%w_%- ]", "_"):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then name = "config" end
	return name
end
 
local function ConfigPath(name)
	return CONFIGS_FOLDER .. "/" .. SafeConfigName(name) .. ".json"
end
 
local function LegacyConfigPath(name)
	return "BobloNEXT/" .. SafeConfigName(name) .. ".json"
end
 
local function BuildConfigEnvelope(name, data, meta)
	meta = meta or {}
	return {
		Schema      = 1,
		Name        = name,
		Description = meta.Description or "",
		Tags        = meta.Tags or {},
		CreatedAt   = meta.CreatedAt or os.time(),
		Data        = data,
	}
end
 
local function ReadConfigFile(path)
	if not (fn_isfile and fn_readfile) then return nil, "readfile unavailable" end
	local existsOk, exists = pcall(fn_isfile, path)
	if not existsOk or not exists then return nil, "config does not exist" end
	local ok, raw = pcall(fn_readfile, path)
	if not ok then return nil, raw end
	local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
	if not decodeOk then return nil, "failed to decode config" end
	if type(decoded) ~= "table" then return nil, "malformed config" end
 
	if decoded.Data == nil then
		return BuildConfigEnvelope(nil, decoded, {}), nil
	end
	return decoded, nil
end
 
function BobloNEXT:SaveConfig(name, opts)
	if not fn_writefile then return false, "writefile unavailable" end
	opts = opts or {}
	EnsureConfigsFolder()
	name = name or "config"
	local envelope = BuildConfigEnvelope(name, BobloNEXT:GetConfig(), opts)
	local ok, err = pcall(function()
		fn_writefile(ConfigPath(name), HttpService:JSONEncode(envelope))
	end)
	return ok, err
end
 
function BobloNEXT:LoadConfig(name, silent)
	name = name or "config"
	local envelope, err = ReadConfigFile(ConfigPath(name))
	if not envelope then
		envelope, err = ReadConfigFile(LegacyConfigPath(name))
	end
	if not envelope then return false, err end
	return BobloNEXT:SetConfig(envelope.Data, silent)
end
 
function BobloNEXT:GetConfigMeta(name)
	local envelope, err = ReadConfigFile(ConfigPath(name))
	if not envelope then return nil, err end
	return {
		Name        = envelope.Name or name,
		Description = envelope.Description or "",
		Tags        = envelope.Tags or {},
		CreatedAt   = envelope.CreatedAt,
	}
end
 
function BobloNEXT:GetSavedConfig(name)
	local envelope, err = ReadConfigFile(ConfigPath(name))
	if not envelope then return nil, err end
	return envelope, nil
end
 
function BobloNEXT:ListConfigs()
	if not fn_listfiles then return {}, "listfiles unavailable" end
	EnsureConfigsFolder()
	local ok, files = pcall(fn_listfiles, CONFIGS_FOLDER)
	if not ok or type(files) ~= "table" then return {}, "failed to list configs" end
 
	local out = {}
	for _, path in ipairs(files) do
		if tostring(path):match("%.json$") then
			local envelope = ReadConfigFile(path)
			if envelope then
				local fileName = tostring(path):match("([^/\\]+)%.json$") or envelope.Name
				table.insert(out, {
					Name        = envelope.Name or fileName,
					FileName    = fileName,
					Description = envelope.Description or "",
					Tags        = envelope.Tags or {},
					CreatedAt   = envelope.CreatedAt or 0,
				})
			end
		end
	end
 
	table.sort(out, function(a, b) return (a.CreatedAt or 0) > (b.CreatedAt or 0) end)
	return out, nil
end
 
function BobloNEXT:DeleteConfig(name)
	if not (fn_isfile and fn_delfile) then return false, "delfile unavailable" end
	local path = ConfigPath(name)
	local ok, exists = pcall(fn_isfile, path)
	if not ok or not exists then return false, "config does not exist" end
	local delOk, err = pcall(fn_delfile, path)
	return delOk, err
end
 
function BobloNEXT:RenameConfig(oldName, newName)
	local envelope, err = ReadConfigFile(ConfigPath(oldName))
	if not envelope then return false, err end
	envelope.Name = newName
	local ok, writeErr = pcall(function()
		EnsureConfigsFolder()
		fn_writefile(ConfigPath(newName), HttpService:JSONEncode(envelope))
	end)
	if not ok then return false, writeErr end
	if ConfigPath(oldName) ~= ConfigPath(newName) then
		pcall(fn_delfile, ConfigPath(oldName))
	end
	return true
end
 
function BobloNEXT:CreateSnapshot()
	return { Data = BobloNEXT:GetConfig(), CreatedAt = os.time() }
end
 
function BobloNEXT:RestoreSnapshot(snapshot, silent)
	if type(snapshot) ~= "table" or type(snapshot.Data) ~= "table" then
		return false, "invalid snapshot"
	end
	return BobloNEXT:SetConfig(snapshot.Data, silent)
end
 
local CLOUD_IDENTITY_PATH = "BobloNEXT/cloud_identity.json"
 
local function LoadCloudIdentity()
	if fn_isfile and fn_readfile then
		local existsOk, exists = pcall(fn_isfile, CLOUD_IDENTITY_PATH)
		if existsOk and exists then
			local ok, raw = pcall(fn_readfile, CLOUD_IDENTITY_PATH)
			if ok then
				local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
				if decodeOk and type(decoded) == "table" and decoded.Id then
					decoded.Tokens = decoded.Tokens or {}
					return decoded
				end
			end
		end
	end
	return nil
end
 
local function SaveCloudIdentity(identity)
	if not fn_writefile then return end
	EnsureAssetsFolder()
	pcall(fn_writefile, CLOUD_IDENTITY_PATH, HttpService:JSONEncode(identity))
end
 
local function GetOrCreateCloudIdentity()
	local identity = LoadCloudIdentity()
	if identity then return identity end
	identity = { Id = HttpService:GenerateGUID(false), Tokens = {} }
	SaveCloudIdentity(identity)
	return identity
end
 
local CLOUD_PUBLISH_COOLDOWN = 15
local LastCloudPublishAt = 0
 
function BobloNEXT:CloudService(opts)
	opts = opts or {}
	local baseUrl = opts.BaseUrl
	local scriptId = opts.Script or "default"
	local identity = GetOrCreateCloudIdentity()
	local httpRequest = (syn and syn.request) or http_request or request
 
	local function apiRequest(method, path, body, extraHeaders)
		if not httpRequest then
			return nil, "Your executor doesn't support HTTP requests."
		end
		if not baseUrl or baseUrl == "" then
			return nil, "No cloud BaseUrl configured -- point CloudService's BaseUrl at your own backend."
		end
 
		local headers = {
			["Content-Type"] = "application/json",
			["X-BobloNEXT-Identity"] = identity.Id,
			["X-BobloNEXT-Script"] = scriptId,
		}
		if extraHeaders then
			for k, v in pairs(extraHeaders) do headers[k] = v end
		end
 
		local ok, res = pcall(httpRequest, {
			Url = baseUrl .. path,
			Method = method,
			Headers = headers,
			Body = body and HttpService:JSONEncode(body) or nil,
		})
		if not ok then return nil, tostring(res) end
 
		if res.StatusCode and (res.StatusCode < 200 or res.StatusCode >= 300) then
			local message = res.Body
			local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(res.Body) end)
			if decodeOk and type(decoded) == "table" and decoded.error then
				message = tostring(decoded.error)
			end
			return nil, "HTTP " .. tostring(res.StatusCode) .. ": " .. tostring(message)
		end
 
		if res.Body == nil or res.Body == "" then return {}, nil end
		local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(res.Body) end)
		if not decodeOk then return nil, "Failed to decode response." end
		return decoded, nil
	end
 
	local api = { Identity = identity.Id }
 
	function api:List(state)
		state = state or {}
		local query = "?sort=" .. HttpService:UrlEncode(state.Sort or "top")
		if state.Query and state.Query ~= "" then
			query = query .. "&q=" .. HttpService:UrlEncode(state.Query)
		end
		if state.Cursor then
			query = query .. "&cursor=" .. HttpService:UrlEncode(tostring(state.Cursor))
		end
		query = query .. "&limit=" .. tostring(state.PageSize or 20)
 
		local decoded, err = apiRequest("GET", "/configs" .. query)
		if not decoded then return nil, err end
		return decoded.Items or {}, decoded.NextCursor
	end
 
	function api:ListMine()
		local decoded, err = apiRequest("GET", "/configs/mine")
		if not decoded then return nil, err end
		return decoded.Items or {}
	end
 
	function api:GetByShareCode(shareCode)
		return apiRequest("GET", "/configs/code/" .. HttpService:UrlEncode(tostring(shareCode)))
	end
 
	function api:Publish(meta, data)
		meta = meta or {}
		local now = os.clock()
		if now - LastCloudPublishAt < CLOUD_PUBLISH_COOLDOWN then
			return nil, string.format(
				"Please wait %ds before publishing again.",
				math.ceil(CLOUD_PUBLISH_COOLDOWN - (now - LastCloudPublishAt))
			)
		end
 
		local cleanName, nameBlocked = BobloNEXT:SanitizeText(meta.Name, { MaxLength = 60 })
		if nameBlocked or cleanName == "" then
			return nil, "Name was empty or blocked by the content filter."
		end
		local cleanDesc, descBlocked = BobloNEXT:SanitizeText(meta.Description or "", { MaxLength = 280 })
		if descBlocked then
			return nil, "Description was blocked by the content filter."
		end
 
		local cleanTags = {}
		for _, tag in ipairs(meta.Tags or {}) do
			local cleanTag = BobloNEXT:SanitizeText(tag, { MaxLength = 24 })
			if cleanTag ~= "" then table.insert(cleanTags, cleanTag) end
			if #cleanTags >= 8 then break end
		end
 
		LastCloudPublishAt = now
 
		local decoded, err = apiRequest("POST", "/configs", {
			Name = cleanName,
			Description = cleanDesc,
			Tags = cleanTags,
			Data = data or BobloNEXT:GetConfig(),
		})
		if not decoded then return nil, err end
 
		if decoded.Id and decoded.OwnerToken then
			identity.Tokens[decoded.Id] = decoded.OwnerToken
			SaveCloudIdentity(identity)
		end
		return decoded
	end
 
	function api:Delete(id)
		local token = identity.Tokens[id]
		if not token then
			return false, "You don't have publish rights for this config on this device."
		end
		local decoded, err = apiRequest("DELETE", "/configs/" .. id, nil, {
			["X-BobloNEXT-Owner-Token"] = token,
		})
		if not decoded then return false, err end
		identity.Tokens[id] = nil
		SaveCloudIdentity(identity)
		return true
	end
 
	function api:Like(id)
		local decoded, err = apiRequest("POST", "/configs/" .. id .. "/like")
		if not decoded then return false, err end
		return true
	end
 
	function api:Download(id)
		return apiRequest("POST", "/configs/" .. id .. "/download")
	end
 
	function api:SendChatMessage(userId, text)
		return apiRequest("POST", "/chat/send", { UserId = userId, Text = text })
	end
 
	function api:PollChatMessages(sinceId)
		local decoded, err = apiRequest("GET", "/chat?since=" .. tostring(sinceId or 0))
		if not decoded then return nil, err end
		return decoded.Messages or {}
	end
 
	function api:ReportChatMessage(messageId)
		local decoded, err = apiRequest("POST", "/chat/" .. tostring(messageId) .. "/report")
		if not decoded then return false, err end
		return true
	end
 
	function api:Heartbeat(payload)
		local decoded, err = apiRequest("POST", "/presence/heartbeat", payload)
		if not decoded then return false, err end
		return true
	end
 
	function api:GetActiveCount()
		local decoded, err = apiRequest("GET", "/presence/count")
		if not decoded then return nil, err end
		return decoded.Count or 0
	end
 
	function api:GetLeaderboard(limit)
		local decoded, err = apiRequest("GET", "/presence/leaderboard?limit=" .. tostring(limit or 10))
		if not decoded then return nil, err end
		return decoded.Items or {}
	end
 
	return api
end
 
function BobloNEXT:CreateAIAssistant(opts)
	opts = opts or {}
	local providers = opts.Providers or {}
	local tools = opts.Tools or (opts.Window and opts.Window:_BuildDefaultChatTools()) or {}
	local systemPrompt = opts.SystemPrompt
		or (opts.Window and opts.Window:_BuildDefaultSystemPrompt())
		or "You are a helpful assistant."
	local maxRounds = opts.MaxRounds or 6
	local maxTokens = opts.MaxTokens or 2048
	local httpRequest = (syn and syn.request) or http_request or request
 
	local function toOpenAITools()
		local out = {}
		for _, tool in ipairs(tools) do
			table.insert(out, {
				type = "function",
				["function"] = {
					name        = tool.Name,
					description = tool.Description,
					parameters  = tool.Parameters,
				},
			})
		end
		return out
	end
 
	local persistPath = nil
	if opts.Persist then
		persistPath = ASSETS_FOLDER .. "/" .. SafeConfigName(tostring(opts.Persist)) .. ".chat.json"
	end
 
	local function loadHistory()
		if not (persistPath and fn_isfile and fn_readfile) then return nil end
		local existsOk, exists = pcall(fn_isfile, persistPath)
		if not existsOk or not exists then return nil end
		local ok, raw = pcall(fn_readfile, persistPath)
		if not ok then return nil end
		local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
		if decodeOk and type(decoded) == "table" then return decoded end
		return nil
	end
 
	local conversation = loadHistory() or { { role = "system", content = systemPrompt } }
 
	local function saveHistory()
		if not (persistPath and fn_writefile) then return end
		EnsureAssetsFolder()
		pcall(fn_writefile, persistPath, HttpService:JSONEncode(conversation))
	end
 
	local function callProvider(provider, messages)
		local body = HttpService:JSONEncode({
			model      = provider.Model,
			messages   = messages,
			tools      = toOpenAITools(),
			max_tokens = maxTokens,
		})
 
		local ok, res = pcall(httpRequest, {
			Url = provider.Endpoint,
			Method = "POST",
			Headers = {
				["Authorization"] = "Bearer " .. tostring(provider.ApiKey),
				["Content-Type"]  = "application/json",
			},
			Body = body,
		})
		if not ok then return nil, tostring(res), false end
 
		if res.StatusCode and res.StatusCode ~= 200 then
			local message = res.Body
			local parseOk, parsed = pcall(function() return HttpService:JSONDecode(res.Body) end)
			if parseOk and type(parsed) == "table" then
				local errField = parsed.error
				if type(errField) == "table" and errField.message then
					message = tostring(errField.message)
				elseif type(errField) == "string" then
					message = errField
				end
			end
			local rateLimited = res.StatusCode == 429
			if rateLimited then message = message .. " (daily free-tier limit)" end
			return nil, provider.Name .. " API error " .. tostring(res.StatusCode) .. ": " .. message, rateLimited
		end
 
		local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(res.Body) end)
		if not decodeOk then return nil, provider.Name .. ": failed to decode API response.", false end
		return decoded, nil, false
	end
 
	local function callAI(messages)
		if not httpRequest then
			return nil, "Your executor doesn't support HTTP requests."
		end
		local lastErr = "No AI provider configured -- add at least one entry with an ApiKey to Providers."
		for _, provider in ipairs(providers) do
			if provider.ApiKey and provider.ApiKey ~= "" then
				local decoded, err, rateLimited = callProvider(provider, messages)
				if decoded then return decoded end
				lastErr = err
				if not rateLimited then return nil, lastErr end
			end
		end
		return nil, lastErr
	end
 
	local assistant = {}
	local stopRequested = false
	local busy = false
 
	function assistant:Stop()
		stopRequested = true
	end
 
	function assistant:IsBusy()
		return busy
	end
 
	function assistant:GetHistory()
		return conversation
	end
 
	function assistant:Reset()
		table.clear(conversation)
		table.insert(conversation, { role = "system", content = systemPrompt })
		saveHistory()
	end
 
	function assistant:Ask(panel, userText)
		table.insert(conversation, { role = "user", content = userText })
		panel:ShowTyping()
		stopRequested = false
		busy = true
 
		for _ = 1, maxRounds do
			if stopRequested then
				busy = false
				panel:HideTyping()
				panel:AddMessage("assistant", "(stopped)")
				saveHistory()
				return
			end
 
			local response, err = callAI(conversation)
			if not response then
				busy = false
				panel:HideTyping()
				panel:AddMessage("assistant", "Error: " .. tostring(err))
				saveHistory()
				return
			end
 
			local choice  = response.choices and response.choices[1]
			local message = choice and choice.message
			if not message then
				busy = false
				panel:HideTyping()
				panel:AddMessage("assistant", "Error: empty response from API.")
				saveHistory()
				return
			end
 
			table.insert(conversation, message)
 
			local calls = message.tool_calls
			local hasCalls = calls and #calls > 0
			local content = message.content or ""
 
			local _, fenceCount = content:gsub("```", "")
			local truncated = choice.finish_reason == "length" or fenceCount % 2 == 1
 
			if message.content and message.content ~= "" then
				if not hasCalls and not truncated then panel:HideTyping() end
				panel:AddMessage("assistant", message.content)
			end
 
			if hasCalls then
				for _, call in ipairs(calls) do
					local argsOk, args = pcall(function()
						return HttpService:JSONDecode(call["function"].arguments)
					end)
					local result = panel:HandleToolCall(call["function"].name, argsOk and args or {})
					table.insert(conversation, {
						role = "tool",
						tool_call_id = call.id,
						content = HttpService:JSONEncode(result == nil and {} or result),
					})
				end
			elseif truncated then
				table.insert(conversation, {
					role = "user",
					content = "You got cut off. Continue exactly where you left off -- don't repeat "
						.. "anything, don't restart the explanation.",
				})
			else
				busy = false
				panel:HideTyping()
				saveHistory()
				return
			end
		end
 
		busy = false
		panel:HideTyping()
		panel:AddMessage("assistant",
			"(stopped after several rounds of tool calls/continuations -- ask me to continue if you need to)")
		saveHistory()
	end
 
	return assistant
end
 
local function DestroyAllWindowJanitors()
	for _, win in ipairs(BobloNEXT._Windows) do
		win._destroyed = true
		if win._janitor then win._janitor:Destroy() end
	end
	table.clear(BobloNEXT._Windows)
end
 
BobloNEXT._Root.Destroying:Connect(function()
	AcrylicShuttingDown = true
	DestroyAllWindowJanitors()
	DestroyAllAcrylicControllers()
	LibJanitor:Destroy()
end)
 
function BobloNEXT:Unload()
	CloseAnyOpenPopup()
	AcrylicShuttingDown = true
	DestroyAllWindowJanitors()
	DestroyAllAcrylicControllers()
	LibJanitor:Destroy()
	if BobloNEXT._Root then BobloNEXT._Root:Destroy() end
end
 
do
	local globalTable = GetGlobalTable()
	globalTable.__BobloNEXT_Unload = function()
		pcall(function() BobloNEXT:Unload() end)
	end
end
 
return BobloNEXT

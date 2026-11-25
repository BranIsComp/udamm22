-- Immediate Boot Probe (Delta / Mobile Executor Compatible)
local __uda_log_buffer = {}
local function udaLog(msg)
	local text = "[uda] " .. tostring(msg)
	table.insert(__uda_log_buffer, text)
	pcall(function()
		if type(rconsoleprint) == "function" then
			rconsoleprint(text .. "\n")
		elseif type(printconsole) == "function" then
			printconsole(text)
		end
	end)
	pcall(function()
		print(text)
	end)
	pcall(function()
		warn(text)
	end)
end

pcall(function()
	local env = (type(getgenv) == "function" and getgenv()) or _G
	if env then
		env.__UDA_LOGS = __uda_log_buffer
	end
end)

local function __uda_main()
	udaLog("Script started.")
	if not game:IsLoaded() then
		udaLog("game:IsLoaded() false at start - running immediately without blocking.")
	else
		udaLog("game:IsLoaded() true at start.")
	end

	-- --- Services -----------------------------------------------------------------
	local Players           = game:GetService("Players")
	local RunService        = game:GetService("RunService")
	local TweenService      = game:GetService("TweenService")
	local UserInputService  = game:GetService("UserInputService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local HttpService       = game:GetService("HttpService")
	local Stats             = game:GetService("Stats")
	local VirtualUser       = game:GetService("VirtualUser")

	local LocalPlayer = Players.LocalPlayer
	if not LocalPlayer then
		udaLog("LocalPlayer nil initially - polling briefly...")
		local deadline = os.clock() + 2
		while not LocalPlayer and os.clock() < deadline do
			LocalPlayer = Players.LocalPlayer
			if not LocalPlayer then
				task.wait(0.1)
			end
		end
	end

	if not LocalPlayer then
		udaLog("LocalPlayer still nil - aborting cleanly.")
		return
	end
	udaLog("LocalPlayer ready: " .. tostring(LocalPlayer.Name))

	-- --- Safe Executor Environment & Globals --------------------------------------
	local _env = (type(getgenv) == "function" and getgenv()) or _G or {}
	local _gethui = (type(gethui) == "function" and gethui) or (_env and type(_env.gethui) == "function" and _env.gethui) or nil
	local _firetouchinterest = (type(firetouchinterest) == "function" and firetouchinterest)
		or (_env and type(_env.firetouchinterest) == "function" and _env.firetouchinterest)
		or nil
	local _hookmetamethod = (type(hookmetamethod) == "function" and hookmetamethod)
		or (_env and type(_env.hookmetamethod) == "function" and _env.hookmetamethod)
		or nil
	local _getnamecallmethod = (type(getnamecallmethod) == "function" and getnamecallmethod)
		or (_env and type(_env.getnamecallmethod) == "function" and _env.getnamecallmethod)
		or nil
	local _newcclosure = (type(newcclosure) == "function" and newcclosure)
		or (_env and type(_env.newcclosure) == "function" and _env.newcclosure)
		or function(fn) return fn end
	local _checkcaller = (type(checkcaller) == "function" and checkcaller)
		or (_env and type(_env.checkcaller) == "function" and _env.checkcaller)
		or function() return false end
	local _loadstring = (type(loadstring) == "function" and loadstring)
		or (_env and type(_env.loadstring) == "function" and _env.loadstring)
		or nil

	local function getExecModule()
		if type(_env) == "table" and type(_env.module) == "table" then
			return _env.module
		end
		if type(_G) == "table" and type(_G.module) == "table" then
			return _G.module
		end
		if type(shared) == "table" and type(shared.module) == "table" then
			return shared.module
		end
		return nil
	end

	-- --- Safe UI Parent (Broad mobile executor compatibility) ----------------------
	local function tryParentScreenGui(sg, targetParent)
		if not sg or not targetParent then return false end
		local ok = pcall(function()
			sg.Parent = targetParent
		end)
		if not ok then return false end
		task.wait()
		local isIn = false
		pcall(function()
			isIn = (sg.Parent == targetParent) or (sg.Parent ~= nil and sg:IsDescendantOf(targetParent))
		end)
		return isIn
	end

	local function canCreateScreenGuiIn(targetParent)
		if not targetParent then return false end
		local ok, result = pcall(function()
			local probe = Instance.new("ScreenGui")
			probe.Name = "__uda_probe_sg"
			probe.ResetOnSpawn = false
			probe.Parent = targetParent
			task.wait()
			local valid = (probe.Parent == targetParent) or (probe.Parent ~= nil and probe:IsDescendantOf(targetParent))
			probe:Destroy()
			return valid
		end)
		return ok and result == true
	end

	local function resolveGuiParents()
		local parents = {}
		local seen = {}

		local function addCandidate(p, label)
			if p and not seen[p] then
				seen[p] = true
				table.insert(parents, { inst = p, name = label })
			end
		end

		if _gethui then
			local okHui, hui = pcall(_gethui)
			if okHui and hui then
				addCandidate(hui, "gethui()")
			end
		end

		local okCore, coreGui = pcall(function()
			return game:GetService("CoreGui")
		end)
		if okCore and coreGui then
			addCandidate(coreGui, "CoreGui")
		end

		local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:FindFirstChild("PlayerGui")
		if pg then
			addCandidate(pg, "PlayerGui")
		end

		local usable = {}
		for _, item in ipairs(parents) do
			local okSg = canCreateScreenGuiIn(item.inst)
			udaLog("Candidate " .. item.name .. " ScreenGui check: " .. tostring(okSg))
			if okSg then
				table.insert(usable, item)
			end
		end

		if #usable > 0 then
			udaLog("Selected GUI parent: " .. usable[1].name)
			return usable[1].inst, usable
		end

		for _, item in ipairs(parents) do
			udaLog("Using fallback parent: " .. item.name)
			return item.inst, parents
		end

		return workspace, {}
	end

	local GuiParent, AllGuiParents = resolveGuiParents()

	-- --- Theme Presets & Moving RGB / Custom Border Controller --------------------
	local COLOR_PRESETS = {
		["Cyan Pulse"] = {
			Accent     = Color3.fromRGB(92, 218, 255),
			AccentSoft = Color3.fromRGB(52, 138, 178),
			AccentGlow = Color3.fromRGB(155, 240, 255),
			BorderFlow = Color3.fromRGB(52, 225, 165),
			TabActive  = Color3.fromRGB(22, 34, 48),
			PetalA     = Color3.fromRGB(145, 235, 255),
			PetalB     = Color3.fromRGB(92, 218, 255),
			PetalC     = Color3.fromRGB(120, 245, 205),
		},
		["Sakura Blossom"] = {
			Accent     = Color3.fromRGB(255, 130, 178),
			AccentSoft = Color3.fromRGB(195, 72, 122),
			AccentGlow = Color3.fromRGB(255, 192, 216),
			BorderFlow = Color3.fromRGB(255, 92, 148),
			TabActive  = Color3.fromRGB(46, 22, 34),
			PetalA     = Color3.fromRGB(255, 182, 208),
			PetalB     = Color3.fromRGB(255, 125, 175),
			PetalC     = Color3.fromRGB(255, 218, 232),
		},
		["Crimson Eclipse"] = {
			Accent     = Color3.fromRGB(255, 75, 92),
			AccentSoft = Color3.fromRGB(175, 34, 48),
			AccentGlow = Color3.fromRGB(255, 145, 155),
			BorderFlow = Color3.fromRGB(255, 120, 65),
			TabActive  = Color3.fromRGB(48, 20, 26),
			PetalA     = Color3.fromRGB(255, 120, 132),
			PetalB     = Color3.fromRGB(255, 70, 88),
			PetalC     = Color3.fromRGB(255, 170, 120),
		},
		["Violet Nebula"] = {
			Accent     = Color3.fromRGB(178, 115, 255),
			AccentSoft = Color3.fromRGB(112, 62, 195),
			AccentGlow = Color3.fromRGB(214, 178, 255),
			BorderFlow = Color3.fromRGB(245, 110, 220),
			TabActive  = Color3.fromRGB(36, 22, 50),
			PetalA     = Color3.fromRGB(205, 162, 255),
			PetalB     = Color3.fromRGB(172, 105, 255),
			PetalC     = Color3.fromRGB(245, 145, 230),
		},
		["Emerald Matrix"] = {
			Accent     = Color3.fromRGB(72, 235, 155),
			AccentSoft = Color3.fromRGB(34, 152, 98),
			AccentGlow = Color3.fromRGB(152, 255, 204),
			BorderFlow = Color3.fromRGB(92, 218, 255),
			TabActive  = Color3.fromRGB(20, 42, 34),
			PetalA     = Color3.fromRGB(132, 248, 190),
			PetalB     = Color3.fromRGB(72, 235, 155),
			PetalC     = Color3.fromRGB(185, 255, 220),
		},
		["Solar Gold"] = {
			Accent     = Color3.fromRGB(255, 196, 68),
			AccentSoft = Color3.fromRGB(185, 126, 28),
			AccentGlow = Color3.fromRGB(255, 228, 145),
			BorderFlow = Color3.fromRGB(255, 120, 68),
			TabActive  = Color3.fromRGB(46, 36, 18),
			PetalA     = Color3.fromRGB(255, 218, 128),
			PetalB     = Color3.fromRGB(255, 190, 62),
			PetalC     = Color3.fromRGB(255, 156, 92),
		},
	}

	local PRESET_ORDER = {
		"Cyan Pulse",
		"Sakura Blossom",
		"Crimson Eclipse",
		"Violet Nebula",
		"Emerald Matrix",
		"Solar Gold",
	}

	local function destroyOldGuisIn(parent)
		if not parent then return end
		pcall(function()
			for _, name in ipairs({ "fu8rj82n", "UdaBlossomBg", "UdaToggle", "_RoleNotif" }) do
				for _, child in ipairs(parent:GetChildren()) do
					if child.Name == name then
						pcall(function() child:Destroy() end)
					end
				end
			end
		end)
	end

	-- --- Library (Clean UI + Moving RGB/Color Bar Border + 5-Petal Blossoms) ------
	local Library = (function()
		local function DestroyYep()
			for _, entry in ipairs(AllGuiParents or {}) do
				destroyOldGuisIn(entry.inst)
			end
			destroyOldGuisIn(GuiParent)
		end

		DestroyYep()

		local Lib = {}

		local THEME = {
			WindowBg      = Color3.fromRGB(12, 14, 21),
			PanelBg       = Color3.fromRGB(16, 19, 28),
			CardBg        = Color3.fromRGB(21, 25, 36),
			CardHover     = Color3.fromRGB(27, 32, 46),
			TabIdle       = Color3.fromRGB(18, 21, 31),
			TabActive     = Color3.fromRGB(22, 34, 48),
			Accent        = Color3.fromRGB(92, 218, 255),
			AccentSoft    = Color3.fromRGB(52, 138, 178),
			AccentGlow    = Color3.fromRGB(155, 240, 255),
			BorderFlow    = Color3.fromRGB(52, 225, 165),
			ToggleOn      = Color3.fromRGB(52, 198, 132),
			ToggleOff     = Color3.fromRGB(42, 47, 61),
			TextPrimary   = Color3.fromRGB(244, 247, 253),
			TextSecondary = Color3.fromRGB(152, 164, 184),
			Border        = Color3.fromRGB(34, 40, 54),
			InputBg       = Color3.fromRGB(11, 13, 19),
			PetalA        = Color3.fromRGB(145, 235, 255),
			PetalB        = Color3.fromRGB(92, 218, 255),
			PetalC        = Color3.fromRGB(120, 245, 205),
		}

		Lib.THEME = THEME
		Lib.Presets = COLOR_PRESETS
		Lib.PresetOrder = PRESET_ORDER

		local themeSubscribers = {}
		local activePresetName = "Cyan Pulse"
		local rgbBorderEnabled = true
		local borderColorOverride = nil
		local borderAnimSpeed = 1.15
		local blossomsEnabled = true

		local function registerThemeHook(fn)
			table.insert(themeSubscribers, fn)
		end

		local function notifyThemeChanged()
			for i = #themeSubscribers, 1, -1 do
				local ok = pcall(themeSubscribers[i], THEME)
				if not ok then
					table.remove(themeSubscribers, i)
				end
			end
		end

		local function buildMovingBarColorSequence(th)
			if borderColorOverride and typeof(borderColorOverride) == "Color3" then
				local h, s, v = borderColorOverride:ToHSV()
				local sat = math.clamp(s, 0.35, 1)
				local val = math.clamp(v, 0.45, 1)
				local cDark = Color3.fromHSV(h, math.clamp(sat * 0.85, 0.2, 1), math.clamp(val * 0.38, 0.14, 0.65))
				local cMid  = Color3.fromHSV(h, sat, val)
				local cBright = Color3.fromHSV(h, math.clamp(sat * 0.28, 0.05, 0.6), math.clamp(val + (1 - val) * 0.65, 0.6, 1))
				return ColorSequence.new({
					ColorSequenceKeypoint.new(0.00, cDark),
					ColorSequenceKeypoint.new(0.16, cDark),
					ColorSequenceKeypoint.new(0.28, cMid),
					ColorSequenceKeypoint.new(0.36, cBright),
					ColorSequenceKeypoint.new(0.44, cMid),
					ColorSequenceKeypoint.new(0.56, cDark),
					ColorSequenceKeypoint.new(0.76, cDark),
					ColorSequenceKeypoint.new(0.88, cMid),
					ColorSequenceKeypoint.new(0.94, cBright),
					ColorSequenceKeypoint.new(1.00, cDark),
				})
			end

			return ColorSequence.new({
				ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 45, 75)),
				ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 200, 35)),
				ColorSequenceKeypoint.new(0.34, Color3.fromRGB(45, 245, 125)),
				ColorSequenceKeypoint.new(0.51, Color3.fromRGB(40, 205, 255)),
				ColorSequenceKeypoint.new(0.68, Color3.fromRGB(115, 85, 255)),
				ColorSequenceKeypoint.new(0.85, Color3.fromRGB(255, 55, 195)),
				ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 45, 75)),
			})
		end

		function Lib:SetPreset(presetName)
			local preset = COLOR_PRESETS[presetName]
			if not preset then return end
			activePresetName = presetName
			THEME.Accent = preset.Accent
			THEME.AccentSoft = preset.AccentSoft
			THEME.AccentGlow = preset.AccentGlow
			THEME.BorderFlow = preset.BorderFlow
			THEME.TabActive = preset.TabActive
			THEME.PetalA = preset.PetalA
			THEME.PetalB = preset.PetalB
			THEME.PetalC = preset.PetalC
			notifyThemeChanged()
		end

		function Lib:SetBorderColorMode(modeName, customColor)
			if modeName == "Rainbow RGB" or not modeName then
				borderColorOverride = nil
			elseif customColor and typeof(customColor) == "Color3" then
				borderColorOverride = customColor
			else
				borderColorOverride = nil
			end
			notifyThemeChanged()
		end

		function Lib:SetRgbBorderEnabled(on)
			rgbBorderEnabled = (on ~= false)
			notifyThemeChanged()
		end

		function Lib:IsRgbBorderEnabled()
			return rgbBorderEnabled
		end

		function Lib:GetPresetName()
			return activePresetName
		end

		function Lib:SetBlossomsEnabled(on)
			blossomsEnabled = (on == true)
			notifyThemeChanged()
		end

		function Lib:IsBlossomsEnabled()
			return blossomsEnabled
		end

		local function addStroke(instance, color, thickness, transparency)
			local stroke = Instance.new("UIStroke")
			stroke.Color = color or THEME.Border
			stroke.Thickness = thickness or 1
			stroke.Transparency = transparency or 0.35
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = instance
			return stroke
		end

		local function bindHover(card, stroke, baseColor, hoverColor)
			card.MouseEnter:Connect(function()
				TweenService:Create(card, TweenInfo.new(0.12), { BackgroundColor3 = hoverColor or THEME.CardHover }):Play()
				if stroke then
					TweenService:Create(stroke, TweenInfo.new(0.12), { Color = THEME.AccentSoft, Transparency = 0.25 }):Play()
				end
			end)
			card.MouseLeave:Connect(function()
				TweenService:Create(card, TweenInfo.new(0.14), { BackgroundColor3 = baseColor or THEME.CardBg }):Play()
				if stroke then
					TweenService:Create(stroke, TweenInfo.new(0.14), { Color = THEME.Border, Transparency = 0.45 }):Play()
				end
			end)
		end

		local function createBlossomFlower(parent, sizePx, petalColor, centerColor, alpha)
			local holder = Instance.new("Frame")
			holder.BackgroundTransparency = 1
			holder.BorderSizePixel = 0
			holder.AnchorPoint = Vector2.new(0.5, 0.5)
			holder.Size = UDim2.fromOffset(sizePx, sizePx)
			holder.Parent = parent

			local petalFrames = {}
			local petalCount = 5
			local petalW = math.max(5, math.floor(sizePx * 0.42))
			local petalH = math.max(7, math.floor(sizePx * 0.54))
			local orbitRadius = sizePx * 0.22

			for p = 1, petalCount do
				local angleDeg = (p - 1) * (360 / petalCount)
				local rad = math.rad(angleDeg - 90)
				local px = 0.5 + (math.cos(rad) * orbitRadius) / sizePx
				local py = 0.5 + (math.sin(rad) * orbitRadius) / sizePx

				local leaf = Instance.new("Frame")
				leaf.Name = "Petal_" .. p
				leaf.BackgroundColor3 = petalColor
				leaf.BackgroundTransparency = alpha
				leaf.BorderSizePixel = 0
				leaf.AnchorPoint = Vector2.new(0.5, 0.5)
				leaf.Position = UDim2.fromScale(px, py)
				leaf.Size = UDim2.fromOffset(petalW, petalH)
				leaf.Rotation = angleDeg
				leaf.Parent = holder

				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(1, 0)
				c.Parent = leaf

				table.insert(petalFrames, leaf)
			end

			local centerSize = math.max(3, math.floor(sizePx * 0.24))
			local core = Instance.new("Frame")
			core.Name = "BlossomCore"
			core.BackgroundColor3 = centerColor
			core.BackgroundTransparency = math.clamp(alpha - 0.08, 0.05, 0.85)
			core.BorderSizePixel = 0
			core.AnchorPoint = Vector2.new(0.5, 0.5)
			core.Position = UDim2.fromScale(0.5, 0.5)
			core.Size = UDim2.fromOffset(centerSize, centerSize)
			core.ZIndex = 3
			core.Parent = holder

			local coreCorner = Instance.new("UICorner")
			coreCorner.CornerRadius = UDim.new(1, 0)
			coreCorner.Parent = core

			return holder, petalFrames, core
		end

		local function computeResponsiveWindowSize()
			local cam = workspace.CurrentCamera
			local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
			local w = math.clamp(math.floor(vp.X * 0.78), 320, 524)
			local h = math.clamp(math.floor(vp.Y * 0.76), 240, 360)
			local px = math.max(8, math.floor((vp.X - w) * 0.5))
			local py = math.max(44, math.floor((vp.Y - h) * 0.5))
			return w, h, px, py
		end

		function Lib:CreateWindow(windowname, windowinfo)
			local fu8rj82n = Instance.new("ScreenGui")
			local BorderShell = Instance.new("Frame")
			local BorderShellCorner = Instance.new("UICorner")
			local Frame = Instance.new("Frame")
			local FrameCorner = Instance.new("UICorner")
			local HeaderBar = Instance.new("Frame")
			local HeaderCorner = Instance.new("UICorner")
			local DashBoard = Instance.new("Frame")
			local DashBoardCorner = Instance.new("UICorner")
			local TabContainer = Instance.new("Frame")
			local TabContainer_2 = Instance.new("UIListLayout")
			local PageContainer = Instance.new("Frame")
			local PageContainerCorner = Instance.new("UICorner")
			local PageFolder = Instance.new("Folder")
			local Title = Instance.new("TextLabel")
			local SubtitleBadge = Instance.new("TextLabel")
			local Yep = Instance.new("TextButton")
			local Cre = Instance.new("ImageLabel")
			local YepTitle = Instance.new("TextLabel")
			local YepCorner = Instance.new("UICorner")

			fu8rj82n.Name = "fu8rj82n"
			fu8rj82n.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			fu8rj82n.ResetOnSpawn = false
			fu8rj82n.DisplayOrder = 15
			fu8rj82n.Enabled = true
			tryParentScreenGui(fu8rj82n, GuiParent)

			local blossomGui = Instance.new("ScreenGui")
			blossomGui.Name = "UdaBlossomBg"
			blossomGui.IgnoreGuiInset = true
			blossomGui.ResetOnSpawn = false
			blossomGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			blossomGui.DisplayOrder = 14
			tryParentScreenGui(blossomGui, GuiParent)

			local blossomCanvas = Instance.new("Frame")
			blossomCanvas.Name = "BlossomCanvas"
			blossomCanvas.Parent = blossomGui
			blossomCanvas.BackgroundTransparency = 1
			blossomCanvas.Size = UDim2.fromScale(1, 1)
			blossomCanvas.ClipsDescendants = true
			blossomCanvas.Visible = false

			local blossoms = {}
			local BLOSSOM_COUNT = 24
			local blossomColors = { THEME.PetalA, THEME.PetalB, THEME.PetalC }

			for i = 1, BLOSSOM_COUNT do
				local baseAlpha = 0.22 + (i % 4) * 0.09
				local sz = math.random(18, 28)
				local col = blossomColors[((i - 1) % #blossomColors) + 1]
				local flowerHolder, petalFrames, core = createBlossomFlower(
					blossomCanvas,
					sz,
					col,
					THEME.AccentGlow,
					baseAlpha
				)

				local startX = math.random()
				local startY = math.random()
				flowerHolder.Position = UDim2.fromScale(startX, startY)
				flowerHolder.Rotation = math.random(0, 360)

				table.insert(blossoms, {
					holder = flowerHolder,
					petals = petalFrames,
					core = core,
					x = startX,
					y = startY,
					fallSpeed = 0.048 + (i % 7) * 0.012,
					swayAmp = 0.018 + (i % 5) * 0.007,
					swayFreq = 1.0 + (i % 6) * 0.25,
					spinSpeed = ((i % 2 == 0) and 1 or -1) * (36 + (i % 5) * 18),
					phase = i * 0.83,
					colorIdx = ((i - 1) % #blossomColors) + 1,
				})
			end

			local winW, winH, winX, winY = computeResponsiveWindowSize()
			local borderPad = 3
			local dashW = math.clamp(math.floor(winW * 0.25), 86, 130)
			local gapW = 8
			local pageX = 8 + dashW + gapW
			local pageW = math.max(180, winW - pageX - 8)
			local contentTopY = math.floor(winH * 0.145)
			local contentH = math.max(160, winH - contentTopY - 8)
			local elemW = math.max(164, pageW - 22)

			BorderShell.Name = "MainFrame"
			BorderShell.Parent = fu8rj82n
			BorderShell.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			BorderShell.BackgroundTransparency = 0
			BorderShell.BorderSizePixel = 0
			BorderShell.Position = UDim2.fromOffset(winX, winY)
			BorderShell.Size = UDim2.fromOffset(winW, winH)
			BorderShell.Visible = true
			BorderShell.ZIndex = 1

			BorderShellCorner.CornerRadius = UDim.new(0, 14)
			BorderShellCorner.Name = "BorderShellCorner"
			BorderShellCorner.Parent = BorderShell

			local perimeterGrad = Instance.new("UIGradient")
			perimeterGrad.Name = "MovingRgbBorderGradient"
			perimeterGrad.Parent = BorderShell
			perimeterGrad.Color = buildMovingBarColorSequence(THEME)

			Frame.Name = "InnerWindowFrame"
			Frame.Parent = BorderShell
			Frame.BackgroundColor3 = THEME.WindowBg
			Frame.BackgroundTransparency = 0
			Frame.BorderSizePixel = 0
			Frame.Position = UDim2.fromOffset(borderPad, borderPad)
			Frame.Size = UDim2.new(1, -(borderPad * 2), 1, -(borderPad * 2))
			Frame.Visible = true
			Frame.ZIndex = 2

			FrameCorner.CornerRadius = UDim.new(0, 12)
			FrameCorner.Name = "FrameCorner"
			FrameCorner.Parent = Frame

			HeaderBar.Name = "HeaderBar"
			HeaderBar.Parent = Frame
			HeaderBar.BackgroundColor3 = THEME.PanelBg
			HeaderBar.BorderSizePixel = 0
			HeaderBar.Position = UDim2.new(0.018, 0, 0.022, 0)
			HeaderBar.Size = UDim2.new(0.964, 0, 0, 34)

			HeaderCorner.CornerRadius = UDim.new(0, 8)
			HeaderCorner.Parent = HeaderBar
			local headerStroke = addStroke(HeaderBar, THEME.Border, 1, 0.45)

			local StatusDot = Instance.new("Frame")
			StatusDot.Name = "StatusDot"
			StatusDot.Parent = HeaderBar
			StatusDot.BackgroundColor3 = THEME.ToggleOn
			StatusDot.BorderSizePixel = 0
			StatusDot.Position = UDim2.new(0.022, 0, 0.5, -4)
			StatusDot.Size = UDim2.fromOffset(8, 8)
			Instance.new("UICorner", StatusDot).CornerRadius = UDim.new(1, 0)

			DashBoard.Name = "DashBoard"
			DashBoard.Parent = Frame
			DashBoard.BackgroundColor3 = THEME.PanelBg
			DashBoard.BorderSizePixel = 0
			DashBoard.Position = UDim2.fromOffset(8, contentTopY)
			DashBoard.Size = UDim2.fromOffset(dashW, contentH)

			DashBoardCorner.CornerRadius = UDim.new(0, 8)
			DashBoardCorner.Name = "DashBoardCorner"
			DashBoardCorner.Parent = DashBoard
			local dashStroke = addStroke(DashBoard, THEME.Border, 1, 0.45)

			TabContainer.Name = "TabContainer"
			TabContainer.Parent = DashBoard
			TabContainer.BackgroundTransparency = 1
			TabContainer.Position = UDim2.new(0.04, 0, 0.028, 0)
			TabContainer.Size = UDim2.new(0.92, 0, 0.944, 0)

			TabContainer_2.Name = "TabContainerLayout"
			TabContainer_2.Parent = TabContainer
			TabContainer_2.HorizontalAlignment = Enum.HorizontalAlignment.Center
			TabContainer_2.SortOrder = Enum.SortOrder.LayoutOrder
			TabContainer_2.Padding = UDim.new(0, 5)

			PageContainer.Name = "PageContainer"
			PageContainer.Parent = Frame
			PageContainer.BackgroundColor3 = THEME.PanelBg
			PageContainer.BorderSizePixel = 0
			PageContainer.Position = UDim2.fromOffset(pageX, contentTopY)
			PageContainer.Size = UDim2.fromOffset(pageW, contentH)

			PageContainerCorner.CornerRadius = UDim.new(0, 8)
			PageContainerCorner.Name = "PageContainerCorner"
			PageContainerCorner.Parent = PageContainer
			local pageStroke = addStroke(PageContainer, THEME.Border, 1, 0.45)

			PageFolder.Name = "PageFolder"
			PageFolder.Parent = PageContainer

			Title.Name = "Title"
			Title.Parent = HeaderBar
			Title.BackgroundTransparency = 1
			Title.Position = UDim2.new(0.052, 0, 0, 0)
			Title.Size = UDim2.new(0.50, 0, 1, 0)
			Title.Font = Enum.Font.GothamBold
			Title.Text = windowname
			Title.TextColor3 = THEME.TextPrimary
			Title.TextSize = 13
			Title.TextXAlignment = Enum.TextXAlignment.Left

			SubtitleBadge.Name = "SubtitleBadge"
			SubtitleBadge.Parent = HeaderBar
			SubtitleBadge.BackgroundColor3 = THEME.CardBg
			SubtitleBadge.Position = UDim2.new(0.58, 0, 0.2, 0)
			SubtitleBadge.Size = UDim2.new(0, 74, 0.6, 0)
			SubtitleBadge.Font = Enum.Font.GothamBold
			SubtitleBadge.Text = windowinfo or "uda"
			SubtitleBadge.TextColor3 = THEME.Accent
			SubtitleBadge.TextSize = 10
			Instance.new("UICorner", SubtitleBadge).CornerRadius = UDim.new(0, 6)
			local badgeStroke = addStroke(SubtitleBadge, THEME.AccentSoft, 1, 0.45)

			Yep.Name = "Yep"
			Yep.Parent = HeaderBar
			Yep.BackgroundTransparency = 1
			Yep.Position = UDim2.new(1, -38, 0.15, 0)
			Yep.Size = UDim2.new(0, 32, 0.7, 0)
			Yep.AutoButtonColor = false
			Yep.Text = ""

			Cre.Name = "Cre"
			Cre.Parent = Yep
			Cre.BackgroundTransparency = 1
			Cre.Size = UDim2.new(1, 0, 1, 0)
			Cre.Image = "rbxassetid://4384401360"
			Cre.ScaleType = Enum.ScaleType.Fit

			YepTitle.Name = "YepTitle"
			YepTitle.Parent = Yep
			YepTitle.BackgroundColor3 = THEME.CardBg
			YepTitle.BackgroundTransparency = 1
			YepTitle.Position = UDim2.new(-2.4, 0, 1.2, 0)
			YepTitle.Size = UDim2.new(0, 110, 0, 24)
			YepTitle.Font = Enum.Font.GothamSemibold
			YepTitle.Text = windowinfo or "uda"
			YepTitle.TextColor3 = THEME.TextPrimary
			YepTitle.TextSize = 10
			YepTitle.TextTransparency = 1
			YepCorner.Name = "YepCorner"
			YepCorner.Parent = YepTitle
			addStroke(YepTitle, THEME.Border, 1, 0.45)

			Cre.MouseEnter:Connect(function()
				YepTitle.BackgroundTransparency = 0.1
				YepTitle.TextTransparency = 0
				Cre.ImageColor3 = THEME.Accent
			end)

			Cre.MouseLeave:Connect(function()
				YepTitle.BackgroundTransparency = 1
				YepTitle.TextTransparency = 1
				Cre.ImageColor3 = Color3.fromRGB(255, 255, 255)
			end)

			local activeWinDragInput = nil
			local winDragStart = nil
			local winStartPos = nil

			BorderShell.InputBegan:Connect(function(input)
				if activeWinDragInput then return end
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					activeWinDragInput = input
					winDragStart = input.Position
					winStartPos = BorderShell.Position
				end
			end)

			UserInputService.InputChanged:Connect(function(input)
				if input == activeWinDragInput and winDragStart and winStartPos then
					if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
						local delta = input.Position - winDragStart
						BorderShell.Position = UDim2.new(
							winStartPos.X.Scale,
							winStartPos.X.Offset + delta.X,
							winStartPos.Y.Scale,
							winStartPos.Y.Offset + delta.Y
						)
					end
				end
			end)

			UserInputService.InputEnded:Connect(function(input)
				if input == activeWinDragInput then
					activeWinDragInput = nil
					winDragStart = nil
					winStartPos = nil
				end
			end)

			local PageYep = {}
			local allTabs = {}
			local activeTabButton = nil
			local dynamicColorAppliers = {}

			local function addColorHook(fn)
				table.insert(dynamicColorAppliers, fn)
			end

			local function applyBorderModeVisual(th)
				if rgbBorderEnabled then
					BorderShell.BackgroundTransparency = 0
					BorderShell.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					perimeterGrad.Enabled = true
					perimeterGrad.Color = buildMovingBarColorSequence(th)
					Frame.Position = UDim2.fromOffset(borderPad, borderPad)
					Frame.Size = UDim2.new(1, -(borderPad * 2), 1, -(borderPad * 2))
				else
					perimeterGrad.Enabled = false
					BorderShell.BackgroundTransparency = 1
					Frame.Position = UDim2.fromOffset(0, 0)
					Frame.Size = UDim2.fromScale(1, 1)
				end
			end

			registerThemeHook(function(th)
				SubtitleBadge.TextColor3 = th.Accent
				badgeStroke.Color = th.AccentSoft
				applyBorderModeVisual(th)

				blossomColors = { th.PetalA, th.PetalB, th.PetalC }
				for _, b in ipairs(blossoms) do
					local col = blossomColors[b.colorIdx] or th.Accent
					for _, leaf in ipairs(b.petals) do
						leaf.BackgroundColor3 = col
					end
					if b.core then
						b.core.BackgroundColor3 = th.AccentGlow
					end
				end

				for _, entry in ipairs(allTabs) do
					local isActive = (entry.button == activeTabButton)
					entry.button.BackgroundColor3 = isActive and th.TabActive or th.TabIdle
					entry.button.TextColor3 = isActive and th.Accent or th.TextSecondary
					entry.stroke.Color = isActive and th.AccentSoft or th.Border
					entry.indicator.BackgroundColor3 = th.Accent
					entry.page.ScrollBarImageColor3 = th.AccentSoft
				end

				for i = #dynamicColorAppliers, 1, -1 do
					local ok = pcall(dynamicColorAppliers[i], th)
					if not ok then
						table.remove(dynamicColorAppliers, i)
					end
				end
			end)

			applyBorderModeVisual(THEME)

			local elapsedAnim = 0
			RunService.RenderStepped:Connect(function(dt)
				local isOpen = BorderShell.Visible and fu8rj82n.Enabled
				local showBlossoms = isOpen and blossomsEnabled
				blossomCanvas.Visible = showBlossoms

				if not isOpen then
					return
				end

				elapsedAnim = elapsedAnim + dt * borderAnimSpeed
				if rgbBorderEnabled and perimeterGrad.Enabled then
					perimeterGrad.Rotation = (elapsedAnim * 165) % 360
				end

				if showBlossoms then
					local clampedDt = math.min(dt, 0.05)
					for _, b in ipairs(blossoms) do
						b.y = b.y + b.fallSpeed * clampedDt
						b.phase = b.phase + b.swayFreq * clampedDt
						if b.y > 1.07 then
							b.y = -0.07
							b.x = math.random() * 0.96 + 0.02
						end
						local swayX = math.clamp(b.x + math.sin(b.phase) * b.swayAmp, 0.01, 0.99)
						b.holder.Position = UDim2.fromScale(swayX, b.y)
						b.holder.Rotation = (b.holder.Rotation + b.spinSpeed * clampedDt) % 360
					end
				end
			end)

			function PageYep:addPage(pagename, scrollsize, visible, elementspacing)
				local Tab = Instance.new("TextButton")
				local TabCorner = Instance.new("UICorner")
				local TabIndicator = Instance.new("Frame")
				local Home = Instance.new("ScrollingFrame")
				local PageLayout = Instance.new("UIListLayout")
				local PagePad = Instance.new("UIPadding")

				local safeScroll = scrollsize or 4
				local safeSpacing = math.max(elementspacing or 8, 8)
				local isInitVisible = visible or false

				Tab.Name = "Tab"
				Tab.Parent = TabContainer
				Tab.BackgroundColor3 = isInitVisible and THEME.TabActive or THEME.TabIdle
				Tab.BorderSizePixel = 0
				Tab.Size = UDim2.new(1, -4, 0, 30)
				Tab.AutoButtonColor = false
				Tab.Font = Enum.Font.GothamBold
				Tab.Text = pagename or "Page"
				Tab.TextColor3 = isInitVisible and THEME.Accent or THEME.TextSecondary
				Tab.TextSize = 11
				Tab.TextTransparency = 0

				TabCorner.CornerRadius = UDim.new(0, 7)
				TabCorner.Name = "TabCorner"
				TabCorner.Parent = Tab

				local tabStroke = addStroke(Tab, isInitVisible and THEME.AccentSoft or THEME.Border, 1, isInitVisible and 0.25 or 0.6)

				TabIndicator.Name = "Indicator"
				TabIndicator.Parent = Tab
				TabIndicator.BackgroundColor3 = THEME.Accent
				TabIndicator.BorderSizePixel = 0
				TabIndicator.Position = UDim2.new(0, 5, 0.22, 0)
				TabIndicator.Size = UDim2.new(0, 3, 0.56, 0)
				TabIndicator.Visible = isInitVisible
				Instance.new("UICorner", TabIndicator).CornerRadius = UDim.new(1, 0)

				Home.Name = "Page"
				Home.Parent = PageFolder
				Home.Active = true
				Home.ScrollingEnabled = true
				Home.ElasticBehavior = Enum.ElasticBehavior.Never
				Home.BackgroundTransparency = 1
				Home.BorderSizePixel = 0
				Home.Position = UDim2.new(0, 0, 0.015, 0)
				Home.Size = UDim2.new(1, 0, 0.97, 0)
				Home.ScrollBarThickness = 3
				Home.ScrollBarImageColor3 = THEME.AccentSoft
				Home.CanvasSize = UDim2.new(0, 0, safeScroll, 0)
				Home.Visible = isInitVisible

				if isInitVisible then
					activeTabButton = Tab
				end

				table.insert(allTabs, { button = Tab, stroke = tabStroke, indicator = TabIndicator, page = Home })

				PagePad.Parent = Home
				PagePad.PaddingTop = UDim.new(0, 8)
				PagePad.PaddingBottom = UDim.new(0, 12)

				PageLayout.Name = "PageLayout"
				PageLayout.Parent = Home
				PageLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
				PageLayout.SortOrder = Enum.SortOrder.LayoutOrder
				PageLayout.Padding = UDim.new(0, safeSpacing)

				Tab.MouseButton1Click:Connect(function()
					activeTabButton = Tab
					for _, v in ipairs(PageFolder:GetChildren()) do
						if v:IsA("ScrollingFrame") then
							v.Visible = false
						end
					end
					Home.Visible = true
					for _, entry in ipairs(allTabs) do
						local isActive = entry.button == Tab
						TweenService:Create(entry.button, TweenInfo.new(0.14), {
							BackgroundColor3 = isActive and THEME.TabActive or THEME.TabIdle,
							TextColor3 = isActive and THEME.Accent or THEME.TextSecondary,
						}):Play()
						entry.stroke.Color = isActive and THEME.AccentSoft or THEME.Border
						entry.stroke.Transparency = isActive and 0.25 or 0.6
						entry.indicator.Visible = isActive
					end
				end)

				local PageElements = {}

				function PageElements:addLabel(labelname, labelinfo)
					local LabelHolder = Instance.new("Frame")
					local LabelHolderCorner = Instance.new("UICorner")
					local LabelTitle = Instance.new("TextLabel")
					local LabelInfo = Instance.new("TextLabel")

					LabelHolder.Name = "LabelHolder"
					LabelHolder.Parent = Home
					LabelHolder.BackgroundColor3 = THEME.CardBg
					LabelHolder.BorderSizePixel = 0
					LabelHolder.Size = UDim2.fromOffset(elemW, 42)

					LabelHolderCorner.CornerRadius = UDim.new(0, 8)
					LabelHolderCorner.Parent = LabelHolder
					local st = addStroke(LabelHolder, THEME.Border, 1, 0.45)
					bindHover(LabelHolder, st, THEME.CardBg, THEME.CardHover)

					LabelTitle.Parent = LabelHolder
					LabelTitle.BackgroundTransparency = 1
					LabelTitle.Position = UDim2.new(0.035, 0, 0.12, 0)
					LabelTitle.Size = UDim2.new(0.93, 0, 0, 16)
					LabelTitle.Font = Enum.Font.GothamBold
					LabelTitle.Text = labelname or ""
					LabelTitle.TextColor3 = THEME.TextPrimary
					LabelTitle.TextSize = 12
					LabelTitle.TextXAlignment = Enum.TextXAlignment.Left

					LabelInfo.Parent = LabelHolder
					LabelInfo.BackgroundTransparency = 1
					LabelInfo.Position = UDim2.new(0.035, 0, 0.54, 0)
					LabelInfo.Size = UDim2.new(0.93, 0, 0, 14)
					LabelInfo.Font = Enum.Font.Gotham
					LabelInfo.Text = labelinfo or ""
					LabelInfo.TextColor3 = THEME.TextSecondary
					LabelInfo.TextSize = 10
					LabelInfo.TextXAlignment = Enum.TextXAlignment.Left
				end

				function PageElements:addButton(buttonname, callback)
					local ButtonHolder = Instance.new("Frame")
					local Button = Instance.new("TextButton")
					local ButtonCorner = Instance.new("UICorner")

					local cb = callback or function() end

					ButtonHolder.Name = "ButtonHolder"
					ButtonHolder.Parent = Home
					ButtonHolder.BackgroundColor3 = THEME.CardBg
					ButtonHolder.BorderSizePixel = 0
					ButtonHolder.Size = UDim2.fromOffset(elemW, 36)

					local holderCorner = Instance.new("UICorner")
					holderCorner.CornerRadius = UDim.new(0, 8)
					holderCorner.Parent = ButtonHolder
					local holderStroke = addStroke(ButtonHolder, THEME.AccentSoft, 1, 0.4)

					Button.Name = "Button"
					Button.Parent = ButtonHolder
					Button.BackgroundColor3 = THEME.CardBg
					Button.BorderSizePixel = 0
					Button.Size = UDim2.new(1, 0, 1, 0)
					Button.AutoButtonColor = false
					Button.Font = Enum.Font.GothamBold
					Button.Text = buttonname
					Button.TextColor3 = THEME.Accent
					Button.TextSize = 12

					ButtonCorner.CornerRadius = UDim.new(0, 8)
					ButtonCorner.Parent = Button
					bindHover(Button, holderStroke, THEME.CardBg, THEME.CardHover)

					addColorHook(function(th)
						holderStroke.Color = th.AccentSoft
						Button.TextColor3 = th.Accent
					end)

					Button.MouseButton1Click:Connect(function()
						TweenService:Create(Button, TweenInfo.new(0.08), { BackgroundColor3 = THEME.TabActive }):Play()
						task.delay(0.11, function()
							if Button and Button.Parent then
								TweenService:Create(Button, TweenInfo.new(0.14), { BackgroundColor3 = THEME.CardBg }):Play()
							end
						end)
						pcall(cb)
					end)
				end

				function PageElements:addToggle(togglename, callback, initialEnabled)
					local ToggleHolder = Instance.new("Frame")
					local ToggleHolderCorner = Instance.new("UICorner")
					local ToggleTitle = Instance.new("TextLabel")
					local ToggleButton = Instance.new("TextButton")
					local ToggleFrame = Instance.new("Frame")
					local ToggleFrameCorner = Instance.new("UICorner")
					local ToggleBall = Instance.new("Frame")
					local ToggleBallCorner = Instance.new("UICorner")

					local cb = callback or function() end
					local ToggleEnabled = false

					ToggleHolder.Name = "ToggleHolder"
					ToggleHolder.Parent = Home
					ToggleHolder.BackgroundColor3 = THEME.CardBg
					ToggleHolder.BorderSizePixel = 0
					ToggleHolder.Size = UDim2.fromOffset(elemW, 36)

					ToggleHolderCorner.CornerRadius = UDim.new(0, 8)
					ToggleHolderCorner.Parent = ToggleHolder
					local holderStroke = addStroke(ToggleHolder, THEME.Border, 1, 0.45)
					bindHover(ToggleHolder, holderStroke, THEME.CardBg, THEME.CardHover)

					ToggleTitle.Parent = ToggleHolder
					ToggleTitle.BackgroundTransparency = 1
					ToggleTitle.Position = UDim2.new(0.035, 0, 0, 0)
					ToggleTitle.Size = UDim2.new(0.72, 0, 1, 0)
					ToggleTitle.Font = Enum.Font.GothamSemibold
					ToggleTitle.Text = togglename or ""
					ToggleTitle.TextColor3 = THEME.TextPrimary
					ToggleTitle.TextSize = 11
					ToggleTitle.TextXAlignment = Enum.TextXAlignment.Left
					ToggleTitle.TextTruncate = Enum.TextTruncate.AtEnd

					ToggleButton.Parent = ToggleHolder
					ToggleButton.BackgroundTransparency = 1
					ToggleButton.Position = UDim2.new(0.74, 0, 0.1, 0)
					ToggleButton.Size = UDim2.new(0.24, 0, 0.8, 0)
					ToggleButton.AutoButtonColor = false
					ToggleButton.Text = ""

					ToggleFrame.Parent = ToggleButton
					ToggleFrame.BackgroundColor3 = THEME.ToggleOff
					ToggleFrame.BorderSizePixel = 0
					ToggleFrame.AnchorPoint = Vector2.new(1, 0.5)
					ToggleFrame.Position = UDim2.new(1, -2, 0.5, 0)
					ToggleFrame.Size = UDim2.fromOffset(42, 22)

					ToggleFrameCorner.CornerRadius = UDim.new(1, 0)
					ToggleFrameCorner.Parent = ToggleFrame

					ToggleBall.Parent = ToggleFrame
					ToggleBall.BackgroundColor3 = Color3.fromRGB(246, 249, 255)
					ToggleBall.Position = UDim2.new(0, 3, 0.5, -8)
					ToggleBall.Size = UDim2.fromOffset(16, 16)

					ToggleBallCorner.CornerRadius = UDim.new(1, 0)
					ToggleBallCorner.Parent = ToggleBall

					local function applyVisual(on, animate)
						ToggleEnabled = on
						if on then
							ToggleFrame.BackgroundColor3 = THEME.ToggleOn
							if animate then
								TweenService:Create(ToggleBall, TweenInfo.new(0.13), {
									Position = UDim2.new(1, -19, 0.5, -8)
								}):Play()
							else
								ToggleBall.Position = UDim2.new(1, -19, 0.5, -8)
							end
						else
							ToggleFrame.BackgroundColor3 = THEME.ToggleOff
							if animate then
								TweenService:Create(ToggleBall, TweenInfo.new(0.13), {
									Position = UDim2.new(0, 3, 0.5, -8)
								}):Play()
							else
								ToggleBall.Position = UDim2.new(0, 3, 0.5, -8)
							end
						end
					end

					ToggleButton.MouseButton1Click:Connect(function()
						applyVisual(not ToggleEnabled, true)
						pcall(cb, ToggleEnabled)
					end)

					if initialEnabled then
						applyVisual(true, false)
						task.defer(function() pcall(cb, true) end)
					end

					return {
						Set = function(_, on, animate)
							applyVisual(on == true, animate ~= false)
						end,
						Get = function()
							return ToggleEnabled
						end,
					}
				end

				function PageElements:addTextBox(textboxname, textboxdefault, callback)
					local TextBoxHolder = Instance.new("Frame")
					local TextBoxHolderCorner = Instance.new("UICorner")
					local TextBoxTitle = Instance.new("TextLabel")
					local TextBox = Instance.new("TextBox")
					local TextBoxCorner = Instance.new("UICorner")

					local cb = callback or function() end

					TextBoxHolder.Name = "TextBoxHolder"
					TextBoxHolder.Parent = Home
					TextBoxHolder.BackgroundColor3 = THEME.CardBg
					TextBoxHolder.BorderSizePixel = 0
					TextBoxHolder.Size = UDim2.fromOffset(elemW, 36)

					TextBoxHolderCorner.CornerRadius = UDim.new(0, 8)
					TextBoxHolderCorner.Parent = TextBoxHolder
					local holderStroke = addStroke(TextBoxHolder, THEME.Border, 1, 0.45)
					bindHover(TextBoxHolder, holderStroke, THEME.CardBg, THEME.CardHover)

					TextBoxTitle.Parent = TextBoxHolder
					TextBoxTitle.BackgroundTransparency = 1
					TextBoxTitle.Position = UDim2.new(0.035, 0, 0, 0)
					TextBoxTitle.Size = UDim2.new(0.60, 0, 1, 0)
					TextBoxTitle.Font = Enum.Font.GothamSemibold
					TextBoxTitle.Text = textboxname or ""
					TextBoxTitle.TextColor3 = THEME.TextPrimary
					TextBoxTitle.TextSize = 11
					TextBoxTitle.TextXAlignment = Enum.TextXAlignment.Left

					TextBox.Parent = TextBoxHolder
					TextBox.BackgroundColor3 = THEME.InputBg
					TextBox.BorderSizePixel = 0
					TextBox.Position = UDim2.new(0.66, 0, 0.16, 0)
					TextBox.Size = UDim2.new(0.31, 0, 0.68, 0)
					TextBox.Font = Enum.Font.GothamMedium
					TextBox.Text = tostring(textboxdefault or "")
					TextBox.PlaceholderText = "Value..."
					TextBox.TextColor3 = THEME.TextPrimary
					TextBox.TextSize = 11
					TextBox.ClearTextOnFocus = true

					TextBoxCorner.CornerRadius = UDim.new(0, 5)
					TextBoxCorner.Parent = TextBox
					local boxStroke = addStroke(TextBox, THEME.AccentSoft, 1, 0.4)

					addColorHook(function(th)
						boxStroke.Color = th.AccentSoft
					end)

					TextBox.Focused:Connect(function()
						TextBox.Text = ""
					end)

					TextBox.FocusLost:Connect(function()
						pcall(cb, TextBox.Text)
					end)
				end

				function PageElements:addSlider(slidername, minVal, maxVal, defaultVal, stepVal, callback)
					local minN = tonumber(minVal) or 0
					local maxN = tonumber(maxVal) or 100
					if maxN <= minN then maxN = minN + 1 end
					local stepN = tonumber(stepVal) or 1
					if stepN <= 0 then stepN = 1 end

					local cb = callback or function() end

					local function roundStep(raw)
						local clamped = math.clamp(raw, minN, maxN)
						local stepped = minN + math.floor(((clamped - minN) / stepN) + 0.5) * stepN
						stepped = math.clamp(stepped, minN, maxN)
						if stepN >= 1 then
							return math.floor(stepped + 0.5)
						end
						return math.floor(stepped * 100 + 0.5) / 100
					end

					local currentValue = roundStep(tonumber(defaultVal) or minN)

					local SliderHolder = Instance.new("Frame")
					local SliderHolderCorner = Instance.new("UICorner")
					local SliderTitle = Instance.new("TextLabel")
					local NumberBox = Instance.new("TextBox")
					local NumberBoxCorner = Instance.new("UICorner")
					local TrackBg = Instance.new("Frame")
					local TrackBgCorner = Instance.new("UICorner")
					local TrackFill = Instance.new("Frame")
					local TrackFillCorner = Instance.new("UICorner")
					local Thumb = Instance.new("Frame")
					local ThumbCorner = Instance.new("UICorner")
					local HitArea = Instance.new("TextButton")

					SliderHolder.Name = "SliderHolder"
					SliderHolder.Parent = Home
					SliderHolder.BackgroundColor3 = THEME.CardBg
					SliderHolder.BorderSizePixel = 0
					SliderHolder.Size = UDim2.fromOffset(elemW, 56)

					SliderHolderCorner.CornerRadius = UDim.new(0, 8)
					SliderHolderCorner.Parent = SliderHolder
					local holderStroke = addStroke(SliderHolder, THEME.Border, 1, 0.45)
					bindHover(SliderHolder, holderStroke, THEME.CardBg, THEME.CardHover)

					SliderTitle.Parent = SliderHolder
					SliderTitle.BackgroundTransparency = 1
					SliderTitle.Position = UDim2.new(0.035, 0, 0.08, 0)
					SliderTitle.Size = UDim2.new(0.64, 0, 0, 20)
					SliderTitle.Font = Enum.Font.GothamSemibold
					SliderTitle.Text = slidername or "Slider"
					SliderTitle.TextColor3 = THEME.TextPrimary
					SliderTitle.TextSize = 11
					SliderTitle.TextXAlignment = Enum.TextXAlignment.Left
					SliderTitle.TextTruncate = Enum.TextTruncate.AtEnd

					NumberBox.Name = "SliderInput"
					NumberBox.Parent = SliderHolder
					NumberBox.BackgroundColor3 = THEME.InputBg
					NumberBox.BorderSizePixel = 0
					NumberBox.Position = UDim2.new(0.70, 0, 0.1, 0)
					NumberBox.Size = UDim2.new(0.265, 0, 0, 22)
					NumberBox.Font = Enum.Font.GothamBold
					NumberBox.Text = ""
					NumberBox.PlaceholderText = tostring(currentValue)
					NumberBox.PlaceholderColor3 = THEME.TextSecondary
					NumberBox.TextColor3 = THEME.Accent
					NumberBox.TextSize = 11
					NumberBox.ClearTextOnFocus = true

					NumberBoxCorner.CornerRadius = UDim.new(0, 5)
					NumberBoxCorner.Parent = NumberBox
					local numStroke = addStroke(NumberBox, THEME.AccentSoft, 1, 0.4)

					TrackBg.Name = "TrackBg"
					TrackBg.Parent = SliderHolder
					TrackBg.BackgroundColor3 = THEME.ToggleOff
					TrackBg.BorderSizePixel = 0
					TrackBg.Position = UDim2.new(0.035, 0, 0.68, 0)
					TrackBg.Size = UDim2.new(0.93, 0, 0, 8)

					TrackBgCorner.CornerRadius = UDim.new(1, 0)
					TrackBgCorner.Parent = TrackBg

					TrackFill.Name = "TrackFill"
					TrackFill.Parent = TrackBg
					TrackFill.BackgroundColor3 = THEME.Accent
					TrackFill.BorderSizePixel = 0
					TrackFill.Size = UDim2.new(0, 0, 1, 0)

					TrackFillCorner.CornerRadius = UDim.new(1, 0)
					TrackFillCorner.Parent = TrackFill

					Thumb.Name = "Thumb"
					Thumb.Parent = TrackBg
					Thumb.BackgroundColor3 = Color3.fromRGB(245, 248, 255)
					Thumb.BorderSizePixel = 0
					Thumb.AnchorPoint = Vector2.new(0.5, 0.5)
					Thumb.Position = UDim2.new(0, 0, 0.5, 0)
					Thumb.Size = UDim2.fromOffset(17, 17)

					ThumbCorner.CornerRadius = UDim.new(1, 0)
					ThumbCorner.Parent = Thumb
					local thumbStroke = addStroke(Thumb, THEME.Accent, 2, 0)

					addColorHook(function(th)
						NumberBox.TextColor3 = th.Accent
						numStroke.Color = th.AccentSoft
						TrackFill.BackgroundColor3 = th.Accent
						thumbStroke.Color = th.Accent
					end)

					HitArea.Name = "HitArea"
					HitArea.Parent = SliderHolder
					HitArea.BackgroundTransparency = 1
					HitArea.Position = UDim2.new(0.02, 0, 0.48, 0)
					HitArea.Size = UDim2.new(0.96, 0, 0, 28)
					HitArea.Text = ""
					HitArea.AutoButtonColor = false

					local function applyValue(newVal, fireCb, syncBox)
						currentValue = roundStep(newVal)
						local alpha = (currentValue - minN) / (maxN - minN)
						alpha = math.clamp(alpha, 0, 1)
						TrackFill.Size = UDim2.new(alpha, 0, 1, 0)
						Thumb.Position = UDim2.new(alpha, 0, 0.5, 0)
						NumberBox.PlaceholderText = tostring(currentValue)
						if syncBox and not NumberBox:IsFocused() then
							NumberBox.Text = ""
						end
						if fireCb then
							pcall(cb, currentValue)
						end
					end

					applyValue(currentValue, false, true)

					local function setFromScreenX(screenX)
						local absPos = TrackBg.AbsolutePosition.X
						local absSize = TrackBg.AbsoluteSize.X
						if absSize <= 0 then return end
						local alpha = math.clamp((screenX - absPos) / absSize, 0, 1)
						local raw = minN + alpha * (maxN - minN)
						applyValue(raw, true, true)
					end

					local activeSliderInput = nil
					local savedScrollEnabled = nil

					local function beginDrag(input)
						if activeSliderInput then return end
						if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
							activeSliderInput = input
							savedScrollEnabled = Home.ScrollingEnabled
							Home.ScrollingEnabled = false
							setFromScreenX(input.Position.X)
						end
					end

					local function endDrag(input)
						if input == activeSliderInput then
							setFromScreenX(input.Position.X)
							activeSliderInput = nil
							if savedScrollEnabled ~= nil then
								Home.ScrollingEnabled = savedScrollEnabled
								savedScrollEnabled = nil
							end
						end
					end

					HitArea.InputBegan:Connect(beginDrag)
					Thumb.InputBegan:Connect(beginDrag)

					UserInputService.InputChanged:Connect(function(input)
						if input == activeSliderInput then
							if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
								setFromScreenX(input.Position.X)
							end
						end
					end)

					UserInputService.InputEnded:Connect(endDrag)
					HitArea.InputEnded:Connect(endDrag)

					NumberBox.Focused:Connect(function()
						NumberBox.Text = ""
					end)

					NumberBox.FocusLost:Connect(function()
						local rawText = NumberBox.Text
						if rawText == nil or rawText:match("^%s*$") then
							NumberBox.Text = ""
							return
						end
						local parsed = tonumber(rawText)
						if parsed then
							applyValue(parsed, true, true)
						end
						NumberBox.Text = ""
					end)
				end

				function PageElements:addDropdown(dropdownname, list, scrollsize, callback, initialValue)
					local DropdownHolder = Instance.new("Frame")
					local DropdownHolderCorner = Instance.new("UICorner")
					local DropdownTitle = Instance.new("TextLabel")
					local DropdownButton = Instance.new("TextButton")
					local DropdownArrow = Instance.new("TextLabel")
					local DropdownContainer = Instance.new("Frame")
					local DropdownContainerCorner = Instance.new("UICorner")
					local DropdownOptionContainer = Instance.new("ScrollingFrame")
					local DropdownOptionContainerLayout = Instance.new("UIListLayout")

					local cb = callback or function() end
					local DropDownEnabled = false
					local safeDropScroll = scrollsize or 5
					local selectedValue = initialValue and tostring(initialValue)
						or ((list and list[1]) and tostring(list[1]) or "")

					DropdownHolder.Name = "DropdownHolder"
					DropdownHolder.Parent = Home
					DropdownHolder.BackgroundColor3 = THEME.CardBg
					DropdownHolder.BorderSizePixel = 0
					DropdownHolder.Size = UDim2.fromOffset(elemW, 36)

					DropdownHolderCorner.CornerRadius = UDim.new(0, 8)
					DropdownHolderCorner.Parent = DropdownHolder
					local holderStroke = addStroke(DropdownHolder, THEME.Border, 1, 0.45)
					bindHover(DropdownHolder, holderStroke, THEME.CardBg, THEME.CardHover)

					DropdownTitle.Parent = DropdownHolder
					DropdownTitle.BackgroundTransparency = 1
					DropdownTitle.Position = UDim2.new(0.035, 0, 0, 0)
					DropdownTitle.Size = UDim2.new(0.40, 0, 1, 0)
					DropdownTitle.Font = Enum.Font.GothamSemibold
					DropdownTitle.Text = dropdownname or "Dropdown"
					DropdownTitle.TextColor3 = THEME.TextPrimary
					DropdownTitle.TextSize = 11
					DropdownTitle.TextXAlignment = Enum.TextXAlignment.Left

					local SelectedLabel = Instance.new("TextLabel")
					SelectedLabel.Parent = DropdownHolder
					SelectedLabel.BackgroundTransparency = 1
					SelectedLabel.Position = UDim2.new(0.44, 0, 0, 0)
					SelectedLabel.Size = UDim2.new(0.47, 0, 1, 0)
					SelectedLabel.Font = Enum.Font.GothamMedium
					SelectedLabel.Text = selectedValue
					SelectedLabel.TextColor3 = THEME.Accent
					SelectedLabel.TextSize = 10
					SelectedLabel.TextXAlignment = Enum.TextXAlignment.Right
					SelectedLabel.TextTruncate = Enum.TextTruncate.AtEnd

					DropdownArrow.Parent = DropdownHolder
					DropdownArrow.BackgroundTransparency = 1
					DropdownArrow.Position = UDim2.new(0.92, 0, 0, 0)
					DropdownArrow.Size = UDim2.new(0.06, 0, 1, 0)
					DropdownArrow.Font = Enum.Font.GothamBold
					DropdownArrow.Text = ""
					DropdownArrow.TextColor3 = THEME.TextSecondary
					DropdownArrow.TextSize = 12

					DropdownButton.Parent = DropdownHolder
					DropdownButton.BackgroundTransparency = 1
					DropdownButton.Size = UDim2.new(1, 0, 1, 0)
					DropdownButton.Text = ""

					DropdownContainer.Name = "DropdownContainer"
					DropdownContainer.Parent = DropdownHolder
					DropdownContainer.BackgroundColor3 = THEME.PanelBg
					DropdownContainer.BorderSizePixel = 0
					DropdownContainer.ClipsDescendants = true
					DropdownContainer.Position = UDim2.new(0, 0, 1.15, 0)
					DropdownContainer.Size = UDim2.new(1, 0, 0, 0)
					DropdownContainer.Visible = false
					DropdownContainer.ZIndex = 10

					DropdownContainerCorner.CornerRadius = UDim.new(0, 8)
					DropdownContainerCorner.Parent = DropdownContainer
					local dropStroke = addStroke(DropdownContainer, THEME.AccentSoft, 1, 0.35)

					DropdownOptionContainer.Parent = DropdownContainer
					DropdownOptionContainer.Active = true
					DropdownOptionContainer.BackgroundTransparency = 1
					DropdownOptionContainer.BorderSizePixel = 0
					DropdownOptionContainer.Position = UDim2.new(0, 0, 0.04, 0)
					DropdownOptionContainer.Size = UDim2.new(1, 0, 0.92, 0)
					DropdownOptionContainer.CanvasSize = UDim2.new(0, 0, safeDropScroll, 0)
					DropdownOptionContainer.ScrollBarThickness = 3
					DropdownOptionContainer.ScrollBarImageColor3 = THEME.AccentSoft
					DropdownOptionContainer.ZIndex = 11

					DropdownOptionContainerLayout.Parent = DropdownOptionContainer
					DropdownOptionContainerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
					DropdownOptionContainerLayout.SortOrder = Enum.SortOrder.LayoutOrder
					DropdownOptionContainerLayout.Padding = UDim.new(0, 5)

					local optionButtons = {}

					local function refreshOptionVisuals(th)
						SelectedLabel.TextColor3 = th.Accent
						dropStroke.Color = th.AccentSoft
						DropdownOptionContainer.ScrollBarImageColor3 = th.AccentSoft
						if DropDownEnabled then
							DropdownArrow.TextColor3 = th.Accent
						end
						for _, opt in ipairs(optionButtons) do
							local isSel = (opt.valueStr == selectedValue)
							opt.btn.TextColor3 = isSel and th.Accent or th.TextPrimary
							opt.btn.BackgroundColor3 = isSel and th.TabActive or th.CardBg
						end
					end

					addColorHook(refreshOptionVisuals)

					local function makeelements(bool)
						for _, v in ipairs(Home:GetChildren()) do
							if v:IsA("Frame") and v ~= DropdownHolder then
								v.Visible = bool
							end
						end
					end

					local function closeDropdown()
						DropDownEnabled = false
						DropdownArrow.Text = ""
						DropdownArrow.TextColor3 = THEME.TextSecondary
						DropdownContainer:TweenSize(UDim2.new(1, 0, 0, 0), "Out", "Quad", 0.18, true)
						task.wait(0.18)
						DropdownContainer.Visible = false
						makeelements(true)
					end

					DropdownButton.MouseButton1Click:Connect(function()
						if not DropDownEnabled then
							DropDownEnabled = true
							makeelements(false)
							DropdownContainer.Visible = true
							DropdownContainer:TweenSize(UDim2.new(1, 0, 0, 136), "Out", "Quad", 0.18, true)
							DropdownArrow.Text = "^"
							DropdownArrow.TextColor3 = THEME.Accent
							Home.CanvasPosition = Vector2.new(0, 0)
						else
							closeDropdown()
						end
					end)

					for _, v in ipairs(list or {}) do
						local Option = Instance.new("TextButton")
						local OptionCorner = Instance.new("UICorner")
						local valStr = tostring(v)
						local isInitSel = (valStr == selectedValue)

						Option.Name = "Option"
						Option.Parent = DropdownOptionContainer
						Option.BackgroundColor3 = isInitSel and THEME.TabActive or THEME.CardBg
						Option.BorderSizePixel = 0
						Option.Size = UDim2.new(0.95, 0, 0, 26)
						Option.AutoButtonColor = false
						Option.Font = Enum.Font.GothamSemibold
						Option.Text = valStr
						Option.TextColor3 = isInitSel and THEME.Accent or THEME.TextPrimary
						Option.TextSize = 11
						Option.ZIndex = 12

						OptionCorner.CornerRadius = UDim.new(0, 5)
						OptionCorner.Parent = Option

						table.insert(optionButtons, { btn = Option, valueStr = valStr })

						Option.MouseButton1Click:Connect(function()
							for _, sibling in ipairs(Option.Parent:GetChildren()) do
								if sibling:IsA("TextButton") and sibling ~= Option then
									sibling.TextColor3 = THEME.TextPrimary
									sibling.BackgroundColor3 = THEME.CardBg
								end
							end
							Option.TextColor3 = THEME.Accent
							Option.BackgroundColor3 = THEME.TabActive
							selectedValue = valStr
							SelectedLabel.Text = selectedValue
							pcall(cb, v)
							closeDropdown()
						end)
					end

					return {
						SetValue = function(_, val)
							selectedValue = tostring(val)
							SelectedLabel.Text = selectedValue
							refreshOptionVisuals(THEME)
						end,
					}
				end

				return PageElements
			end

			return PageYep
		end

		return Lib
	end)()

	-- --- State & Configuration ----------------------------------------------------
	local Murderer, Sheriff = nil, nil
	local roles = {}
	local highlightedPlayers = {}
	local currentTween = nil
	local invis_on = false
	local coinCooldowns = {}

	local config = {
		farmMode            = "Nearest + XP Farm",
		farmSpeed           = 24,
		murdererSafeRadius  = 35,
		stealthAutoFarm     = false,
		auraDistance        = 20,
		walkSpeedVal        = 16,
		jumpPowerVal        = 50,
		selectedEmote       = "dab",
		rcCarCustomName     = nil,

		themePreset         = "Cyan Pulse",
		rgbBorderEnabled    = true,
		borderColorMode     = "Rainbow RGB",
		blossomsEnabled     = true,
		autoSaveEnabled     = false,

		st_stealthAutoFarm  = false,
		st_autoFarm         = false,
		st_autoGrabGun      = false,
		st_dodgeKnife       = false,
		st_autoEndRound     = false,
		st_playerChams      = false,
		st_skeletonESP      = false,
		st_coinESP          = false,
		st_roleNotif        = false,
		st_gunCham          = false,
		st_nameESP          = false,
		st_renderOffFocus   = false,
		st_autoEmote        = false,
		st_killAura         = false,
		st_autoKillAll      = false,
		st_silentAim        = false,
		st_killMurderer     = false,
		st_autoShootMurd    = false,
		st_walkSpeed        = false,
		st_jumpPower        = false,
		st_infiniteJump     = false,
		st_noclip           = false,
		st_antiFling        = false,
		st_antiAfk          = false,
	}

	local SETTINGS_FILE = "uda_mm2_settings.json"

	local function saveSettings()
		pcall(function()
			local writeFile = (type(writefile) == "function" and writefile)
				or (_env and type(_env.writefile) == "function" and _env.writefile)
				or (type(syn) == "table" and type(syn.write_file) == "function" and syn.write_file)
				or (type(filesystem) == "table" and type(filesystem.writefile) == "function" and filesystem.writefile)
			if not writeFile then return end
			local data = {}
			for k, v in pairs(config) do
				data["cfg_" .. k] = v
			end
			writeFile(SETTINGS_FILE, HttpService:JSONEncode(data))
		end)
	end

	local function autoSave()
		if config.autoSaveEnabled then
			saveSettings()
		end
	end

	local function loadSettings()
		pcall(function()
			local readFile = (type(readfile) == "function" and readfile)
				or (_env and type(_env.readfile) == "function" and _env.readfile)
				or (type(syn) == "table" and type(syn.read_file) == "function" and syn.read_file)
				or (type(filesystem) == "table" and type(filesystem.readfile) == "function" and filesystem.readfile)
			if not readFile then return end
			local ok, raw = pcall(readFile, SETTINGS_FILE)
			if not ok or not raw or raw == "" then return end
			local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
			if not ok2 or type(data) ~= "table" then return end
			for k, v in pairs(data) do
				local cfgKey = k:match("^cfg_(.+)$")
				if cfgKey and config[cfgKey] ~= nil then
					config[cfgKey] = v
				end
			end
		end)
	end

	loadSettings()

	local state = {
		autoFarm        = false,
		autoGrabGun     = false,
		dodgeKnife      = false,
		autoEndRound    = false,
		flingTarget     = false,
		spectateTarget  = false,
		loopGoToTarget  = false,
		flingSheriff    = false,
		flingMurderer   = false,
		playerChams     = false,
		skeletonESP     = false,
		coinESP         = false,
		roleNotif       = false,
		gunCham         = false,
		nameESP         = false,
		renderOffFocus  = false,
		autoEmote       = false,
		killAura        = false,
		autoKillAll     = false,
		silentAim       = false,
		killMurderer    = false,
		autoShootMurd   = false,
		coinTracker     = false,
		unboxNotif      = false,
		walkSpeed       = false,
		jumpPower       = false,
		noclip          = false,
		infiniteJump    = false,
		rcActive        = false,
		antiFling       = false,
		antiAfk         = false,
	}

	local noclipConnection  = nil
	local ijConnection      = nil
	local unboxConnection   = nil
	local rcRideConnection  = nil
	local rcDismountGuardConn = nil
	local focusLostConn     = nil
	local focusGainedConn   = nil
	local silentAimConn     = nil
	local silentAimHooked   = false
	local antiAfkIdledConn  = nil

	-- --- Forward-declared Character & Role Helpers (defined before physics loop) -
	local function safeChar()
		return LocalPlayer.Character
	end

	local function safeHRP()
		local c = safeChar()
		return c and c:FindFirstChild("HumanoidRootPart")
	end

	local function safeHum()
		local c = safeChar()
		return c and c:FindFirstChildOfClass("Humanoid")
	end

	local function IsAlive(Player, rolesTable)
		if not Player then return false end
		local char = Player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not char or not hum or hum.Health <= 0 then return false end

		local role = rolesTable and rolesTable[Player.Name]
		if not role then
			return char:FindFirstChild("HumanoidRootPart") ~= nil
		end
		if not role.Killed and not role.Dead then return true end
		if char:FindFirstChild("HumanoidCloned") then return true end
		return false
	end

	-- --- Unified Physics / Collision Coordinator (FPS-optimized + safe dismount) -
	local physStepConn = nil
	local charBaseParts = {}
	local lastPhysChar = nil

	local function refreshCharBaseParts(char)
		do local __t=charBaseParts for __k in next,__t do __t[__k]=nil end end
		if not char then return end
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then
				table.insert(charBaseParts, part)
			end
		end
	end

	local function ensurePhysicsCoordinator()
		if physStepConn then return end
		physStepConn = RunService.Stepped:Connect(function()
			local char = LocalPlayer.Character
			if not char then
				lastPhysChar = nil
				do local __t=charBaseParts for __k in next,__t do __t[__k]=nil end end
				return
			end
			if char ~= lastPhysChar then
				lastPhysChar = char
				refreshCharBaseParts(char)
			end

			local alive = IsAlive(LocalPlayer, roles)
			local forceNoCollide = state.noclip
				or state.rcActive
				or (state.autoFarm and alive)
				or (config.stealthAutoFarm and state.autoFarm and alive)

			for i = #charBaseParts, 1, -1 do
				local part = charBaseParts[i]
				if not part or not part.Parent then
					table.remove(charBaseParts, i)
				elseif forceNoCollide then
					if part.CanCollide then
						part.CanCollide = false
					end
				elseif not state.antiFling then
					local n = part.Name
					if (n == "UpperTorso" or n == "LowerTorso" or n == "Torso" or n == "HumanoidRootPart") and not part.CanCollide then
						part.CanCollide = true
					end
				end
			end

			if state.antiFling then
				for _, player in ipairs(Players:GetPlayers()) do
					if player ~= LocalPlayer and player.Character then
						for _, p in ipairs(player.Character:GetDescendants()) do
							if p:IsA("BasePart") and p.CanCollide then
								p.CanCollide = false
							end
						end
					end
				end
			end
		end)
	end

	ensurePhysicsCoordinator()

	local webhookUrl              = ""
	local webhookIntervalSeconds  = 60
	local coinsEarned             = {}
	local lastBagCounts           = {}

	-- --- Window & Pages (Exact Order: Main, Visuals, Target, Roles, Player, Misc, Settings)
	udaLog("Creating Library window...")
	local Window = Library:CreateWindow("uda | mm2", "uda")

	local MainPage     = Window:addPage("Main",     5, true,  9)
	local VisualsPage  = Window:addPage("Visuals",  5, false, 9)
	local TargetPage   = Window:addPage("Target",   5, false, 9)
	local RolesPage    = Window:addPage("Roles",    5, false, 9)
	local PlayerPage   = Window:addPage("Player",   5, false, 9)
	local MiscPage     = Window:addPage("Misc",     6, false, 9)
	local SettingsPage = Window:addPage("Settings", 4, false, 9)
	udaLog("Window & pages created.")

	-- --- Mobile / Toggle Button ---------------------------------------------------
	local toggleGui = Instance.new("ScreenGui")
	toggleGui.Name = "UdaToggle"
	toggleGui.ResetOnSpawn = false
	toggleGui.IgnoreGuiInset = true
	toggleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	toggleGui.DisplayOrder = 20
	toggleGui.Enabled = true
	tryParentScreenGui(toggleGui, GuiParent)

	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Name = "ToggleBtn"
	toggleBtn.Size = UDim2.fromOffset(52, 52)
	toggleBtn.Position = UDim2.new(1, -64, 0, 56)
	toggleBtn.AnchorPoint = Vector2.new(1, 0)
	toggleBtn.BackgroundColor3 = Color3.fromRGB(14, 17, 25)
	toggleBtn.TextColor3 = Library.THEME.Accent
	toggleBtn.Font = Enum.Font.GothamBold
	toggleBtn.TextSize = 11
	toggleBtn.Text = "UDA"
	toggleBtn.AutoButtonColor = false
	toggleBtn.Visible = true
	toggleBtn.Parent = toggleGui

	local toggleBtnCorner = Instance.new("UICorner")
	toggleBtnCorner.CornerRadius = UDim.new(0, 12)
	toggleBtnCorner.Parent = toggleBtn

	local toggleBtnStroke = Instance.new("UIStroke")
	toggleBtnStroke.Color = Library.THEME.AccentSoft
	toggleBtnStroke.Thickness = 1.4
	toggleBtnStroke.Transparency = 0.2
	toggleBtnStroke.Parent = toggleBtn

	local function getMainFrame()
		for _, entry in ipairs(AllGuiParents or {}) do
			local sg = entry.inst and entry.inst:FindFirstChild("fu8rj82n")
			local fr = sg and sg:FindFirstChildOfClass("Frame")
			if fr then return fr end
		end
		local sg = GuiParent and GuiParent:FindFirstChild("fu8rj82n")
		return sg and sg:FindFirstChildOfClass("Frame")
	end

	local guiVisible = true
	local activeToggleDragInput = nil
	local tbDragStart = nil
	local tbStartPos = nil
	local tbMoved = false

	local function refreshToggleBtnTheme()
		if not guiVisible then
			toggleBtn.TextColor3 = Color3.fromRGB(255, 105, 105)
			toggleBtnStroke.Color = Color3.fromRGB(165, 55, 55)
		else
			toggleBtn.TextColor3 = Library.THEME.Accent
			toggleBtnStroke.Color = Library.THEME.AccentSoft
		end
	end

	toggleBtn.InputBegan:Connect(function(input)
		if activeToggleDragInput then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			activeToggleDragInput = input
			tbMoved = false
			tbDragStart = input.Position
			tbStartPos = toggleBtn.Position
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input == activeToggleDragInput and tbDragStart and tbStartPos then
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				local delta = input.Position - tbDragStart
				if delta.Magnitude > 6 then
					tbMoved = true
				end
				if tbMoved then
					toggleBtn.Position = UDim2.new(
						tbStartPos.X.Scale,
						tbStartPos.X.Offset + delta.X,
						tbStartPos.Y.Scale,
						tbStartPos.Y.Offset + delta.Y
					)
				end
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input == activeToggleDragInput then
			activeToggleDragInput = nil
		end
	end)

	toggleBtn.MouseButton1Click:Connect(function()
		if tbMoved then return end
		local frame = getMainFrame()
		if frame then
			guiVisible = not guiVisible
			frame.Visible = guiVisible
			refreshToggleBtnTheme()
		end
	end)

	-- --- Utilities ----------------------------------------------------------------
	local function Equip(toolName)
		local char = safeChar()
		if char and char:FindFirstChild(toolName) then
			return char:FindFirstChild(toolName)
		end
		local hum = safeHum()
		local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
		local tool = bp and bp:FindFirstChild(toolName)
		if hum and tool then
			hum:EquipTool(tool)
			return tool
		end
		return nil
	end

	local _cachedMapModel = nil
	local _cachedCoinContainer = nil
	local _cachedSpawns = nil
	local _lastMapCacheCheck = 0

	local function isLobbyContainer(inst)
		if not inst then return false end
		local lower = string.lower(inst.Name)
		return string.find(lower, "lobby", 1, true) ~= nil
	end

	local function isExcludedTopLevel(inst)
		if not inst or not inst:IsA("Model") then return true end
		if Players:GetPlayerFromCharacter(inst) then return true end
		if isLobbyContainer(inst) then return true end
		local n = string.lower(inst.Name)
		if n == "petcontainer" or n == "debris" or n == "effects" then
			return true
		end
		return false
	end

	local function refreshMapContainers()
		local now = os.clock()
		if (now - _lastMapCacheCheck) < 0.75
			and _cachedMapModel and _cachedMapModel.Parent == workspace
			and ((_cachedCoinContainer and _cachedCoinContainer.Parent) or (_cachedSpawns and _cachedSpawns.Parent)) then
			return
		end
		_lastMapCacheCheck = now
		_cachedMapModel = nil
		_cachedCoinContainer = nil
		_cachedSpawns = nil

		for _, model in ipairs(workspace:GetChildren()) do
			if not isExcludedTopLevel(model) then
				local cc = model:FindFirstChild("CoinContainer", true)
				local sp = model:FindFirstChild("Spawns", true)
				if cc or sp then
					_cachedMapModel = model
					_cachedCoinContainer = cc
					_cachedSpawns = sp
					return
				end
			end
		end

		for _, container in ipairs(workspace:GetChildren()) do
			if (container:IsA("Model") or container:IsA("Folder"))
				and not Players:GetPlayerFromCharacter(container)
				and not isLobbyContainer(container) then
				if not _cachedCoinContainer then
					_cachedCoinContainer = container:FindFirstChild("CoinContainer", true)
				end
				if not _cachedSpawns then
					_cachedSpawns = container:FindFirstChild("Spawns", true)
				end
				if _cachedCoinContainer or _cachedSpawns then
					_cachedMapModel = container
					return
				end
			end
		end
	end

	local function TargetModel(target)
		refreshMapContainers()
		if target == "CoinContainer" then
			return (_cachedCoinContainer and _cachedCoinContainer.Parent) and _cachedCoinContainer or nil
		end
		if target == "Spawns" then
			return (_cachedSpawns and _cachedSpawns.Parent) and _cachedSpawns or nil
		end
		if target == "Map" then
			return (_cachedMapModel and _cachedMapModel.Parent) and _cachedMapModel or nil
		end
		return nil
	end

	local function getPartOrModelCFrame(obj)
		if not obj or not obj.Parent then return nil end
		if obj:IsA("BasePart") then
			return obj.CFrame
		elseif obj:IsA("Model") then
			if obj.PrimaryPart then
				return obj.PrimaryPart.CFrame
			end
			local part = obj:FindFirstChildWhichIsA("BasePart", true)
			if part then
				return part.CFrame
			end
		elseif obj:IsA("Attachment") then
			return obj.WorldCFrame
		end
		return nil
	end

	local function resolveLobbyDestination()
		for _, folder in ipairs(workspace:GetChildren()) do
			if (folder:IsA("Model") or folder:IsA("Folder")) and isLobbyContainer(folder) then
				for _, obj in ipairs(folder:GetDescendants()) do
					if obj:IsA("SpawnLocation") then
						return CFrame.new(obj.Position + Vector3.new(0, 4.5, 0))
					end
				end
				local fallbackPart = folder:FindFirstChild("Spawn", true)
					or folder:FindFirstChild("LobbySpawn", true)
					or folder:FindFirstChildWhichIsA("BasePart", true)
				if fallbackPart then
					local cf = getPartOrModelCFrame(fallbackPart)
					if cf then
						return cf * CFrame.new(0, 4.5, 0)
					end
				end
			end
		end

		local activeMap = TargetModel("Map")
		for _, obj in ipairs(workspace:GetDescendants()) do
			if obj:IsA("SpawnLocation") and (not activeMap or not obj:IsDescendantOf(activeMap)) then
				return CFrame.new(obj.Position + Vector3.new(0, 4.5, 0))
			end
		end

		return nil
	end

	local function resolveMapDestination()
		local spawns = TargetModel("Spawns")
		if spawns then
			local validSpawns = {}
			for _, sp in ipairs(spawns:GetDescendants()) do
				local cf = getPartOrModelCFrame(sp)
				if cf and cf.Position.Y > (workspace.FallenPartsDestroyHeight + 10) then
					table.insert(validSpawns, cf)
				end
			end
			if #validSpawns > 0 then
				return validSpawns[math.random(1, #validSpawns)] * CFrame.new(0, 4.5, 0)
			end
		end

		local mapModel = TargetModel("Map")
		if mapModel then
			local coinContainer = TargetModel("CoinContainer")
			if coinContainer then
				for _, coin in ipairs(coinContainer:GetChildren()) do
					local visual = coin:FindFirstChild("CoinVisual") or coin:FindFirstChildWhichIsA("BasePart")
					if visual and visual:IsA("BasePart") and visual.Position.Y > (workspace.FallenPartsDestroyHeight + 10) then
						return CFrame.new(visual.Position + Vector3.new(0, 4.5, 0))
					end
				end
			end
			local part = mapModel:FindFirstChildWhichIsA("BasePart", true)
			local cf = getPartOrModelCFrame(part)
			if cf then
				return cf * CFrame.new(0, 5, 0)
			end
		end

		return nil
	end

	-- --- Stealth & Tween Teleport -------------------------------------------------
	local TWEEN_MIN = 0.08
	local TWEEN_MAX = 4.0

	local function cancelActiveTween()
		if currentTween then
			pcall(function() currentTween:Cancel() end)
			currentTween = nil
		end
	end

	local function directTeleport(targetCF)
		local char = safeChar()
		local hrp = safeHRP()
		local hum = safeHum()
		if not hrp or not targetCF then return false end

		cancelActiveTween()

		if hum and hum.Sit then
			hum.Sit = false
			task.wait()
		end

		local prevAnchored = hrp.Anchored
		hrp.Anchored = true
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero

		if char and char.PrimaryPart then
			pcall(function() char:PivotTo(targetCF) end)
		end
		hrp.CFrame = targetCF

		task.wait(0.05)
		if safeHRP() then
			safeHRP().AssemblyLinearVelocity = Vector3.zero
			safeHRP().AssemblyAngularVelocity = Vector3.zero
			safeHRP().Anchored = prevAnchored
		end
		return true
	end

	local function tween_teleport(TargetFrame, speed, SlowDown, fullywait, coin)
		local hrp = safeHRP()
		if not hrp or not TargetFrame then return end

		cancelActiveTween()

		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero

		local dist = (hrp.Position - TargetFrame.Position).Magnitude
		local effectiveSpeed = math.max(speed or config.farmSpeed, 1)

		if effectiveSpeed >= 2500 or dist <= 2 then
			directTeleport(TargetFrame)
			return
		end

		local duration = math.clamp(dist / effectiveSpeed, TWEEN_MIN, TWEEN_MAX)
		local style = SlowDown and Enum.EasingStyle.Quad or Enum.EasingStyle.Linear
		local dir = SlowDown and Enum.EasingDirection.Out or Enum.EasingDirection.In

		local tween = TweenService:Create(hrp, TweenInfo.new(duration, style, dir), { CFrame = TargetFrame })
		currentTween = tween
		tween:Play()

		if fullywait and coin then
			repeat
				task.wait(0.03)
			until not CoinAttribute(coin, true) or TrackCoinBag() or not IsAlive(LocalPlayer, roles) or not state.autoFarm
		else
			local startClock = os.clock()
			while tween.PlaybackState == Enum.PlaybackState.Playing and (os.clock() - startClock) < duration do
				task.wait(0.03)
				if not state.autoFarm then
					pcall(function() tween:Cancel() end)
					break
				end
			end
		end

		if currentTween == tween then
			currentTween = nil
		end
	end

	local function teleportToLobbyAction()
		local destCF = resolveLobbyDestination()
		if not destCF then
			warn("[uda] Teleport To Lobby: No lobby spawn found.")
			return
		end
		local hum = safeHum()
		if hum then hum.Sit = false end
		directTeleport(destCF)
		task.delay(0.15, function()
			local h = safeHRP()
			local freshDest = resolveLobbyDestination() or destCF
			if h and (h.Position - freshDest.Position).Magnitude > 14 then
				directTeleport(freshDest)
			end
		end)
	end

	local function teleportToMapAction()
		local destCF = resolveMapDestination()
		if not destCF then
			warn("[uda] Teleport To Map: No active map spawn found.")
			return
		end
		local hum = safeHum()
		if hum then hum.Sit = false end
		directTeleport(destCF)
		task.delay(0.15, function()
			local h = safeHRP()
			local freshDest = resolveMapDestination() or destCF
			if h and (h.Position - freshDest.Position).Magnitude > 14 then
				directTeleport(freshDest)
			end
		end)
	end

	local function findGunDrop()
		local spawns = TargetModel("Spawns")
		if spawns and spawns.Parent then
			local g = spawns.Parent:FindFirstChild("GunDrop", true)
			if g then return g end
		end
		local mapModel = TargetModel("Map")
		if mapModel then
			local g = mapModel:FindFirstChild("GunDrop", true)
			if g then return g end
		end
		return workspace:FindFirstChild("GunDrop", true)
	end

	local function Fetch(itemName)
		for _, player in ipairs(Players:GetPlayers()) do
			local bp = player:FindFirstChildOfClass("Backpack")
			if (bp and bp:FindFirstChild(itemName)) or
				(player.Character and player.Character:FindFirstChild(itemName)) then
				return player.Name
			end
		end
		return nil
	end

	local function setCharacterAttributes(walkSpeed, jumpPower)
		local hum = safeHum()
		if hum then
			if walkSpeed then hum.WalkSpeed = walkSpeed end
			if jumpPower then hum.JumpPower = jumpPower end
		end
	end

	function CoinAttribute(part, CheckCoin)
		if not part or not part.Parent or not part:IsA("BasePart") then return false end
		local hrp = safeHRP()
		if not hrp then return false end

		local dist = (part.Position - hrp.Position).Magnitude
		if dist <= 5 and _firetouchinterest then
			pcall(function()
				_firetouchinterest(part, hrp, 1)
				task.wait(0.02)
				_firetouchinterest(part, hrp, 0)
			end)
		end
		if dist <= 2.5 then
			part.Name = "uda_collected"
		end
		if part:GetAttribute("Collected") ~= true and CheckCoin then
			return true
		end
		return false
	end

	function TrackCoinBag()
		local elite = LocalPlayer:GetAttribute("Elite")
		local role = roles[LocalPlayer.Name]
		if role then
			local coins = tonumber(role.Coins) or 0
			if elite ~= nil and coins >= 50 then return true end
			if elite == nil and coins >= 40 then return true end
		end

		local bagAttr = LocalPlayer:GetAttribute("CoinBagFull") or LocalPlayer:GetAttribute("BagFull")
		if bagAttr == true then return true end

		local ok, maxReached = pcall(function()
			local pg = LocalPlayer:FindFirstChild("PlayerGui")
			if not pg then return false end
			for _, gui in ipairs(pg:GetDescendants()) do
				if gui:IsA("TextLabel") and gui.Visible then
					local txt = gui.Text
					local cur, cap = txt:match("(%d+)%s*/%s*(%d+)")
					if cur and cap and tonumber(cur) and tonumber(cap) and tonumber(cur) >= tonumber(cap) and tonumber(cap) >= 10 then
						return true
					end
				end
			end
			return false
		end)
		if ok and maxReached then return true end

		return false
	end

	-- --- High-Precision Ping-Compensated Aim & Ballistics -------------------------
	local BULLET_SPEED = 240
	local VELOCITY_SAMPLES = 8
	local velocityHistory = {}

	local function getMotionState(hrp, playerName)
		local now = os.clock()
		local entry = velocityHistory[playerName]
		if not entry or entry.hrp ~= hrp then
			entry = { hrp = hrp, samples = {}, times = {}, lastPos = hrp.Position, lastTime = now }
			velocityHistory[playerName] = entry
		end

		local dtPos = math.max(now - entry.lastTime, 0.008)
		local empiricalVel = (hrp.Position - entry.lastPos) / dtPos
		entry.lastPos = hrp.Position
		entry.lastTime = now

		local asmVel = hrp.AssemblyLinearVelocity
		local rawVel = (asmVel.Magnitude > 0.5) and asmVel:Lerp(empiricalVel, 0.25) or empiricalVel

		table.insert(entry.samples, rawVel)
		table.insert(entry.times, now)
		if #entry.samples > VELOCITY_SAMPLES then
			table.remove(entry.samples, 1)
			table.remove(entry.times, 1)
		end

		local weightedSum = Vector3.zero
		local weightTotal = 0
		for i, v in ipairs(entry.samples) do
			local w = i * i
			weightedSum = weightedSum + v * w
			weightTotal = weightTotal + w
		end
		local smoothVel = weightTotal > 0 and (weightedSum / weightTotal) or rawVel

		local accel = Vector3.zero
		if #entry.samples >= 2 then
			local prevVel = entry.samples[#entry.samples - 1]
			local dt = math.max(now - entry.times[#entry.times - 1], 0.012)
			accel = (rawVel - prevVel) / dt
			if accel.Magnitude > 140 then
				accel = accel.Unit * 140
			end
		end

		return smoothVel, accel
	end

	local function getPingSeconds()
		local ok, pingMs = pcall(function()
			return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
		end)
		if not ok or type(pingMs) ~= "number" then
			return 0.05
		end
		return math.clamp((pingMs / 1000) * 0.65 + 0.025, 0.015, 0.85)
	end

	local function getBestTargetPart(char)
		if not char then return nil end
		local upper = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local head = char:FindFirstChild("Head")
		return upper or hrp or head
	end

	local function PredictTargetCFrame(targetChar, playerName, originPos)
		if not targetChar then return CFrame.new() end
		local hrp = targetChar:FindFirstChild("HumanoidRootPart")
		local aimPart = getBestTargetPart(targetChar) or hrp
		if not hrp or not aimPart then
			return aimPart and aimPart.CFrame or CFrame.new()
		end

		local partOffset = aimPart.Position - hrp.Position
		local smoothVel, accel = getMotionState(hrp, playerName)
		local humanoid = targetChar:FindFirstChildOfClass("Humanoid")
		local moveDir = humanoid and humanoid.MoveDirection or Vector3.zero
		local walkSpeed = humanoid and humanoid.WalkSpeed or 16
		local onGround = not humanoid or (humanoid.FloorMaterial ~= Enum.Material.Air)

		local horizVel = Vector3.new(smoothVel.X, 0, smoothVel.Z)
		if moveDir.Magnitude > 0.1 then
			local inputVel = moveDir.Unit * math.max(horizVel.Magnitude, walkSpeed)
			horizVel = horizVel:Lerp(inputVel, onGround and 0.45 or 0.15)
		elseif horizVel.Magnitude < 1.5 then
			horizVel = Vector3.zero
		end

		local vertVel = smoothVel.Y
		local gravity = onGround and 0 or -workspace.Gravity
		local effectiveVel = Vector3.new(horizVel.X, vertVel, horizVel.Z)
		local effectiveAccel = Vector3.new(accel.X * 0.2, gravity, accel.Z * 0.2)

		local pingSec = getPingSeconds()
		local refOrigin = originPos or (safeHRP() and safeHRP().Position) or hrp.Position
		local leadTime = pingSec
		local predictedBase = hrp.Position

		for _ = 1, 5 do
			predictedBase = hrp.Position
				+ effectiveVel * leadTime
				+ 0.5 * effectiveAccel * (leadTime * leadTime)
			local dist = ((predictedBase + partOffset) - refOrigin).Magnitude
			leadTime = (dist / BULLET_SPEED) + pingSec
		end

		if not onGround and predictedBase.Y < hrp.Position.Y - 6 then
			predictedBase = Vector3.new(predictedBase.X, hrp.Position.Y - 3, predictedBase.Z)
		end

		return CFrame.new(predictedBase + partOffset)
	end

	-- --- Visibility & Wallbang Check ----------------------------------------------
	local function isPlayerVisible(player)
		local char = safeChar()
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then return false end
		if player ~= LocalPlayer and player.Character then
			local targetPart = getBestTargetPart(player.Character) or player.Character:FindFirstChild("HumanoidRootPart")
			if not targetPart then return false end
			local dir = targetPart.Position - root.Position
			if dir.Magnitude < 0.01 then return true end
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { char }
			local hit = workspace:Raycast(root.Position, dir.Unit * math.min(dir.Magnitude, 999), params)
			return not hit or hit.Instance:IsDescendantOf(player.Character)
		end
		return false
	end

	-- --- Gun & Shoot Remote Helpers -----------------------------------------------
	local _cachedShootRemote = nil

	local function getEquippedOrBackpackGun()
		local char = safeChar()
		local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
		return (char and char:FindFirstChild("Gun"))
			or (bp and bp:FindFirstChild("Gun"))
	end

	local function isGunReady(gun)
		if not gun then return false end
		local handle = gun:FindFirstChild("Handle")
		if not handle then return false end
		local reload = handle:FindFirstChild("Reload")
		if reload and reload:IsA("Sound") and reload.Playing then
			return false
		end
		if gun:GetAttribute("Cooldown") == true or gun:GetAttribute("Reloading") == true then
			return false
		end
		return true
	end

	local function getGunOriginCF(gun, hrp)
		local handle = gun and gun:FindFirstChild("Handle")
		if handle then
			local muzzle = handle:FindFirstChild("Muzzle")
				or handle:FindFirstChild("MuzzleAttachment")
				or handle:FindFirstChild("Barrel")
			if muzzle then
				if muzzle:IsA("Attachment") then
					return muzzle.WorldCFrame
				elseif muzzle:IsA("BasePart") then
					return muzzle.CFrame
				end
			end
			return handle.CFrame
		end
		return hrp.CFrame * CFrame.new(0, 0.5, -1.5)
	end

	local function getShootRemote(gun)
		if _cachedShootRemote and _cachedShootRemote.Parent then
			return _cachedShootRemote
		end
		_cachedShootRemote = nil

		local searchTargets = {}
		if gun then table.insert(searchTargets, gun) end
		local char = safeChar()
		if char then
			local charGun = char:FindFirstChild("Gun")
			if charGun and charGun ~= gun then table.insert(searchTargets, charGun) end
		end

		for _, container in ipairs(searchTargets) do
			local knifeLocal = container:FindFirstChild("KnifeLocal")
			if knifeLocal then
				local createBeam = knifeLocal:FindFirstChild("CreateBeam")
				if createBeam and createBeam:IsA("RemoteFunction") then
					_cachedShootRemote = createBeam
					return _cachedShootRemote
				end
			end

			local direct = container:FindFirstChild("Shoot")
			if direct and (direct:IsA("RemoteEvent") or direct:IsA("RemoteFunction")) then
				_cachedShootRemote = direct
				return _cachedShootRemote
			end

			for _, v in ipairs(container:GetDescendants()) do
				if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
					local lower = string.lower(v.Name)
					if lower:find("shoot") or lower:find("beam") or lower:find("fire") then
						_cachedShootRemote = v
						return _cachedShootRemote
					end
				end
			end
		end

		local rem = ReplicatedStorage:FindFirstChild("Remotes")
		if rem then
			for _, v in ipairs(rem:GetDescendants()) do
				if (v:IsA("RemoteEvent") or v:IsA("RemoteFunction")) and string.lower(v.Name):find("shoot") then
					_cachedShootRemote = v
					return _cachedShootRemote
				end
			end
		end

		return nil
	end

	local _firingSilentShot = false

	local function fireGunRemote(remote, originCF, targetCF)
		if not remote or _firingSilentShot then return false end
		_firingSilentShot = true
		local ok = false
		local aimedOrigin = CFrame.new(originCF.Position, targetCF.Position)
		if remote:IsA("RemoteFunction") then
			task.spawn(function()
				pcall(function()
					remote:InvokeServer(1, targetCF.Position, "AH2")
				end)
			end)
			ok = true
		elseif remote:IsA("RemoteEvent") then
			pcall(function()
				remote:FireServer(aimedOrigin, targetCF)
			end)
			ok = true
		end
		_firingSilentShot = false
		return ok
	end

	local function ShootMurderer(blatantSnap)
		if not Murderer then return false end
		local murderer = Players:FindFirstChild(Murderer)
		if not murderer or not murderer.Character or not IsAlive(murderer, roles) then return false end
		local murdererHRP = murderer.Character:FindFirstChild("HumanoidRootPart")
		if not murdererHRP then return false end

		local char = safeChar()
		local hrp = safeHRP()
		if not char or not hrp then return false end

		local gun = getEquippedOrBackpackGun()
		if not gun or not isGunReady(gun) then return false end

		if gun.Parent ~= char then
			Equip("Gun")
			task.wait(0.03)
			char = safeChar()
			gun = char and char:FindFirstChild("Gun")
			if not gun then return false end
		end

		local originCF = getGunOriginCF(gun, hrp)
		local predictedCF = PredictTargetCFrame(murderer.Character, Murderer, originCF.Position)

		if blatantSnap then
			local lookAtPos = Vector3.new(predictedCF.Position.X, hrp.Position.Y, predictedCF.Position.Z)
			if (lookAtPos - hrp.Position).Magnitude > 0.1 then
				hrp.CFrame = CFrame.new(hrp.Position, lookAtPos)
			end
			originCF = getGunOriginCF(gun, hrp)
			predictedCF = PredictTargetCFrame(murderer.Character, Murderer, originCF.Position)
		end

		local shootRemote = getShootRemote(gun)
		if shootRemote then
			return fireGunRemote(shootRemote, originCF, predictedCF)
		end
		return false
	end

	-- --- BodyVelocity Helpers ----------------------------------------------------
	local function BodyVelocity()
		local hrp = safeHRP()
		if hrp and not hrp:FindFirstChild("BodyVelocity") then
			local bv = Instance.new("BodyVelocity")
			bv.Name = "BodyVelocity"
			bv.Velocity = Vector3.zero
			bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
			bv.Parent = hrp
		end
	end

	local function DestroyBody()
		local hrp = safeHRP()
		local bv = hrp and hrp:FindFirstChild("BodyVelocity")
		if bv then bv:Destroy() end
	end

	-- --- Stealth Auto Farm -------------------------------------------------------
	local FAR_COIN_THRESH = 200
	local stealthPickupActive = false

	local function ghostChar(on)
		local char = safeChar()
		if not char then return end
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				part.LocalTransparencyModifier = on and 0.85 or 0
				if on then
					part.CanCollide = false
				end
			end
		end
		for _, acc in ipairs(char:GetChildren()) do
			if acc:IsA("Accessory") then
				local h = acc:FindFirstChild("Handle")
				if h and h:IsA("BasePart") then
					h.LocalTransparencyModifier = on and 0.85 or 0
				end
			end
		end
	end

	local function unfreezeChar()
		local hrp = safeHRP()
		if hrp then
			for _, name in ipairs({ "_sfBP", "_sfBG", "BodyVelocity" }) do
				local obj = hrp:FindFirstChild(name)
				if obj then obj:Destroy() end
			end
			hrp.Anchored = false
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end
	end

	local function isCoinSafeFromMurderer(coinPos)
		if not Murderer or Murderer == LocalPlayer.Name then return true end
		local mPlayer = Players:FindFirstChild(Murderer)
		local mHRP = mPlayer and mPlayer.Character and mPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not mHRP then return true end
		return (coinPos - mHRP.Position).Magnitude >= (config.murdererSafeRadius or 35)
	end

	local function stealthCollectCoin(coin, hrp)
		if stealthPickupActive or not coin or not coin.Parent then return false end
		local visual = coin:FindFirstChild("CoinVisual")
		if not visual or not visual:IsA("BasePart") then return false end

		stealthPickupActive = true
		ghostChar(true)

		local targetCF = CFrame.new(visual.Position + Vector3.new(0, 1.35, 0))
		local dist = (hrp.Position - targetCF.Position).Magnitude

		if dist > FAR_COIN_THRESH then
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			hrp.CFrame = targetCF * CFrame.new(0, 2, 0)
			task.wait(0.06)
		end

		local speed = math.max((config.farmSpeed or 24) * 1.15, 22)
		local duration = math.clamp(dist / speed, 0.05, 2.5)

		cancelActiveTween()

		local tween = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.In), { CFrame = targetCF })
		currentTween = tween
		tween:Play()

		local deadline = os.clock() + duration + 0.35
		repeat
			task.wait(0.03)
			if (hrp.Position - visual.Position).Magnitude <= 4.5 then
				if _firetouchinterest then
					pcall(function()
						_firetouchinterest(visual, hrp, 1)
						task.wait(0.02)
						_firetouchinterest(visual, hrp, 0)
					end)
				end
				if (hrp.Position - visual.Position).Magnitude <= 2.5 then
					coin.Name = "uda_collected"
					break
				end
			end
		until not coin.Parent
			or coin.Name == "uda_collected"
			or coin:GetAttribute("Collected") == true
			or TrackCoinBag()
			or not IsAlive(LocalPlayer, roles)
			or not state.autoFarm
			or not config.stealthAutoFarm
			or os.clock() > deadline

		if currentTween == tween then
			pcall(function() tween:Cancel() end)
			currentTween = nil
		end

		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		stealthPickupActive = false
		return true
	end

	local function isCoinReady(coin)
		if not coin or not coin.Parent then return false end
		if coin.Name == "uda_collected" then return false end
		if coin:GetAttribute("Collected") == true then return false end
		local visual = coin:FindFirstChild("CoinVisual")
		if not visual or not visual:IsA("BasePart") then return false end
		local cd = coinCooldowns[coin]
		if cd and os.clock() < cd then return false end
		return true
	end

	local function findCoin(hrp, mode)
		local container = TargetModel("CoinContainer")
		if not container then return nil end

		local safePool = {}
		local fallbackPool = {}

		for _, coin in ipairs(container:GetChildren()) do
			if coin.Name == "Coin_Server" and isCoinReady(coin) then
				local visual = coin:FindFirstChild("CoinVisual")
				if visual and visual:IsA("BasePart") then
					local dist = (visual.Position - hrp.Position).Magnitude
					local entry = { coin = coin, dist = dist }
					table.insert(fallbackPool, entry)
					if not config.stealthAutoFarm or isCoinSafeFromMurderer(visual.Position) then
						table.insert(safePool, entry)
					end
				end
			end
		end

		local pool = (#safePool > 0) and safePool or fallbackPool
		if #pool == 0 then return nil end

		if mode == "random" then
			return pool[math.random(1, #pool)].coin
		end

		table.sort(pool, function(a, b) return a.dist < b.dist end)
		return pool[1].coin
	end

	local function resetCharacter()
		pcall(function()
			local hrp = safeHRP()
			if not hrp then return end
			local lobbyCF = resolveLobbyDestination()
			if lobbyCF then
				tween_teleport(lobbyCF, 5000)
			end
		end)
	end

	local function teleportToCoin(targetCoin, humanoidRootPart)
		if TrackCoinBag() or not isCoinReady(targetCoin) then return end
		local visual = targetCoin:FindFirstChild("CoinVisual")
		if not visual or not visual:IsA("BasePart") then return end

		coinCooldowns[targetCoin] = os.clock() + 0.85

		local targetPos = visual.Position
		local dist      = (humanoidRootPart.Position - targetPos).Magnitude
		local targetCF  = CFrame.new(targetPos.X, targetPos.Y + 1.2, targetPos.Z)

		if config.stealthAutoFarm then
			local ok = pcall(stealthCollectCoin, targetCoin, humanoidRootPart)
			if not ok then
				ghostChar(true)
				humanoidRootPart.AssemblyLinearVelocity  = Vector3.zero
				humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
				humanoidRootPart.CFrame = targetCF
				task.wait(0.08)
			end
		else
			ghostChar(false)
			if dist > FAR_COIN_THRESH then
				humanoidRootPart.CFrame = targetCF * CFrame.new(0, 8, 0)
				task.wait(0.25)
			end
			tween_teleport(targetCF, dist > FAR_COIN_THRESH and 5000 or config.farmSpeed, false, true, targetCoin)
		end
	end

	local function AutoFarmTick(currentMode)
		local ok, err = pcall(function()
			local char = safeChar()
			local hum = char and char:FindFirstChild("Humanoid")
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hum or not hrp then return end

			if TrackCoinBag() and hum.Health > 0 and IsAlive(LocalPlayer, roles) then
				resetCharacter()
				return
			end

			if IsAlive(LocalPlayer, roles) then
				local mode = (currentMode == "Nearest" or currentMode == "Nearest + XP Farm") and "closest" or "random"
				local targetCoin = findCoin(hrp, mode)
				if targetCoin then
					BodyVelocity()
					teleportToCoin(targetCoin, hrp)
				end
			end
		end)
		if not ok then warn("[uda] AutoFarm: " .. tostring(err)) end
	end

	-- --- ESP ----------------------------------------------------------------------
	local ROLE_COLORS = {
		Murderer = Color3.fromRGB(225, 0, 0),
		Sheriff  = Color3.fromRGB(0, 0, 225),
		Hero     = Color3.fromRGB(0, 0, 225),
	}
	local DEFAULT_COLOR = Color3.fromRGB(76, 215, 134)
	local DEAD_COLOR    = Color3.fromRGB(255, 255, 255)

	local function ManageHighlights()
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer then
				if player.Character then
					local h = player.Character:FindFirstChild("Highlight")
					if not h then
						h = Instance.new("Highlight")
						h.Name = "Highlight"
						h.Parent = player.Character
						highlightedPlayers[player] = h
					end
					if IsAlive(player, roles) then
						local role = roles[player.Name]
						h.FillColor = (role and ROLE_COLORS[role.Role]) or DEFAULT_COLOR
					else
						h.FillColor = DEAD_COLOR
					end
				else
					local h = highlightedPlayers[player]
					if h then h:Destroy() end
					highlightedPlayers[player] = nil
				end
			end
		end
	end

	local function DestroyHighlights()
		for _, h in pairs(highlightedPlayers) do
			if h then pcall(function() h:Destroy() end) end
		end
		do local __t=highlightedPlayers for __k in next,__t do __t[__k]=nil end end
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				local head = player.Character:FindFirstChild("Head")
				local tag = head and head:FindFirstChild("UsernameTag")
				if tag then tag:Destroy() end
			end
		end
	end

	local function createUsernameTag(player)
		if player == LocalPlayer then return end
		local char = player.Character
		local head = char and char:FindFirstChild("Head")
		if head and not head:FindFirstChild("UsernameTag") then
			local bb = Instance.new("BillboardGui")
			bb.Name = "UsernameTag"
			bb.Adornee = head
			bb.Parent = head
			bb.Size = UDim2.new(0, 200, 0, 50)
			bb.StudsOffset = Vector3.new(0, 2.5, 0)
			bb.AlwaysOnTop = true

			local lbl = Instance.new("TextLabel", bb)
			lbl.Text = player.Name
			lbl.TextSize = 20
			lbl.BackgroundTransparency = 1
			lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
			lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
			lbl.TextStrokeTransparency = 0.5
			lbl.Size = UDim2.new(1, 0, 1, 0)
			lbl.Font = Enum.Font.SourceSansBold
		end
	end

	-- --- Curved Skeleton ESP ------------------------------------------------------
	local activeSkeletonCurves = {}
	local skeletonHeartbeatConn = nil
	local CURVE_SEGMENTS = 3
	local SKELETON_THICKNESS = 4.2

	local R15_CURVE_SPECS = {
		{ a = "Head",         b = "UpperTorso",   bend = Vector3.new(0, 0, 0.08) },
		{ a = "UpperTorso",   b = "LowerTorso",   bend = Vector3.new(0, 0, -0.06) },
		{ a = "LowerTorso",   b = "LeftUpperLeg", bend = Vector3.new(-0.08, -0.04, 0.06) },
		{ a = "LowerTorso",   b = "RightUpperLeg",bend = Vector3.new(0.08, -0.04, 0.06) },
		{ a = "LeftUpperLeg", b = "LeftLowerLeg", bend = Vector3.new(0, 0, -0.10) },
		{ a = "RightUpperLeg",b = "RightLowerLeg",bend = Vector3.new(0, 0, -0.10) },
		{ a = "LeftLowerLeg", b = "LeftFoot",     bend = Vector3.new(0, -0.02, 0.08) },
		{ a = "RightLowerLeg",b = "RightFoot",    bend = Vector3.new(0, -0.02, 0.08) },
		{ a = "UpperTorso",   b = "LeftUpperArm", bend = Vector3.new(-0.10, 0.05, 0.05) },
		{ a = "UpperTorso",   b = "RightUpperArm",bend = Vector3.new(0.10, 0.05, 0.05) },
		{ a = "LeftUpperArm", b = "LeftLowerArm", bend = Vector3.new(-0.04, 0, 0.12) },
		{ a = "RightUpperArm",b = "RightLowerArm",bend = Vector3.new(0.04, 0, 0.12) },
		{ a = "LeftLowerArm", b = "LeftHand",     bend = Vector3.new(0, 0, 0.06) },
		{ a = "RightLowerArm",b = "RightHand",    bend = Vector3.new(0, 0, 0.06) },
	}

	local R6_CURVE_SPECS = {
		{ a = "Head",     b = "Torso",     bend = Vector3.new(0, 0, 0.08) },
		{ a = "Torso",    b = "Left Arm",  bend = Vector3.new(-0.12, 0.04, 0.08) },
		{ a = "Torso",    b = "Right Arm", bend = Vector3.new(0.12, 0.04, 0.08) },
		{ a = "Torso",    b = "Left Leg",  bend = Vector3.new(-0.08, -0.04, -0.06) },
		{ a = "Torso",    b = "Right Leg", bend = Vector3.new(0.08, -0.04, -0.06) },
	}

	local function evalQuadraticBezier(p0, p1, p2, t)
		local inv = 1 - t
		return (inv * inv) * p0 + (2 * inv * t) * p1 + (t * t) * p2
	end

	local function getSkeletonColor(player)
		local role = roles and roles[player.Name]
		if role then
			if role.Role == "Murderer" then return Color3.fromRGB(255, 65, 65) end
			if role.Role == "Sheriff" or role.Role == "Hero" then return Color3.fromRGB(80, 145, 255) end
		end
		return Color3.fromRGB(90, 245, 195)
	end

	local function clearAllSkeletons()
		if skeletonHeartbeatConn then
			skeletonHeartbeatConn:Disconnect()
			skeletonHeartbeatConn = nil
		end
		do local __t=activeSkeletonCurves for __k in next,__t do __t[__k]=nil end end
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				local f = player.Character:FindFirstChild("_SkeletonESP")
				if f then f:Destroy() end
			end
		end
	end

	local function rebuildSkeletons()
		clearAllSkeletons()
		if not state.skeletonESP then return end

		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer and player.Character then
				local char = player.Character
				local root = char:FindFirstChild("HumanoidRootPart")
				local folder = Instance.new("Folder")
				folder.Name = "_SkeletonESP"
				folder.Parent = char

				local color = getSkeletonColor(player)
				local specs = char:FindFirstChild("UpperTorso") and R15_CURVE_SPECS or R6_CURVE_SPECS

				for _, spec in ipairs(specs) do
					local a = char:FindFirstChild(spec.a)
					local b = char:FindFirstChild(spec.b)
					if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
						local segments = {}
						for _ = 1, CURVE_SEGMENTS do
							local line = Instance.new("LineHandleAdornment")
							line.Name = "CurvedBoneSeg"
							line.Adornee = a
							line.Parent = folder
							line.Color3 = color
							line.Thickness = SKELETON_THICKNESS
							line.AlwaysOnTop = true
							line.ZIndex = 5
							table.insert(segments, line)
						end
						table.insert(activeSkeletonCurves, {
							segments = segments,
							a = a,
							b = b,
							root = root,
							bend = spec.bend,
						})
					end
				end
			end
		end

		skeletonHeartbeatConn = RunService.Heartbeat:Connect(function()
			local cam = workspace.CurrentCamera
			local camPos = cam and cam.CFrame.Position or Vector3.zero
			for i = #activeSkeletonCurves, 1, -1 do
				local curve = activeSkeletonCurves[i]
				local a, b, segments = curve.a, curve.b, curve.segments
				if not a or not a.Parent or not b or not b.Parent or not segments[1] or not segments[1].Parent then
					table.remove(activeSkeletonCurves, i)
				else
					local p0 = a.Position
					if (p0 - camPos).Magnitude > 260 then
						for s = 1, CURVE_SEGMENTS do
							segments[s].Visible = false
						end
					else
					local p2 = b.Position
					local span = p2 - p0
					local spanLen = span.Magnitude
					if spanLen >= 0.01 then
						local refCF = (curve.root and curve.root.Parent) and curve.root.CFrame or a.CFrame
						local bendOffset = refCF:VectorToWorldSpace(curve.bend * (spanLen * 2.2))
						local p1 = (p0 + p2) * 0.5 + bendOffset
						local invACF = a.CFrame:Inverse()

						local prevPt = p0
						for s = 1, CURVE_SEGMENTS do
							local t = s / CURVE_SEGMENTS
							local nextPt = (s == CURVE_SEGMENTS) and p2 or evalQuadraticBezier(p0, p1, p2, t)
							local segVec = nextPt - prevPt
							local segLen = segVec.Magnitude
							local line = segments[s]
							if segLen >= 0.005 then
								local cf = CFrame.new(prevPt, nextPt) * CFrame.new(0, 0, -segLen / 2)
								line.CFrame = invACF * cf
								line.Length = segLen
								line.Visible = true
							else
								line.Length = 0.005
								line.Visible = false
							end
							prevPt = nextPt
						end
					end
					end
				end
			end
		end)
	end

	-- --- Coin ESP (Clean Highlight Only - No Billboard/Dot on Top) ---------------
	local coinESPFolder = nil
	local COIN_CHAM_YELLOW = Color3.fromRGB(255, 225, 0)
	local roleAssignedAtClock = nil
	local lastTrackedRoleForCountdown = nil

	local function clearCoinESP()
		if coinESPFolder then
			coinESPFolder:Destroy()
			coinESPFolder = nil
		end
	end

	local function isInRoleCountdownGrace()
		local myRole = roles and roles[LocalPlayer.Name]
		local currentRoleName = (myRole and myRole.Role)
			or (Murderer == LocalPlayer.Name and "Murderer")
			or (Sheriff == LocalPlayer.Name and "Sheriff")
			or nil

		if currentRoleName then
			if currentRoleName ~= lastTrackedRoleForCountdown then
				lastTrackedRoleForCountdown = currentRoleName
				roleAssignedAtClock = os.clock()
			end
			if roleAssignedAtClock and (os.clock() - roleAssignedAtClock) < 10 then
				return true
			end
		else
			lastTrackedRoleForCountdown = nil
			roleAssignedAtClock = nil
		end

		local ok, hasCountdown = pcall(function()
			local pg = LocalPlayer:FindFirstChild("PlayerGui")
			if not pg then return false end
			for _, gui in ipairs(pg:GetDescendants()) do
				if gui:IsA("TextLabel") and gui.Visible then
					local lower = string.lower(gui.Text)
					if string.find(lower, "starting in", 1, true)
						or string.find(lower, "round starts in", 1, true)
						or string.find(lower, "countdown", 1, true) then
						return true
					end
				end
			end
			return false
		end)
		return ok and hasCountdown
	end

	local function isCoinObject(inst)
		if not inst or not inst.Parent then return false end
		if inst.Name == "uda_collected" then return false end
		if inst:GetAttribute("Collected") == true then return false end
		local n = string.lower(inst.Name)
		return inst.Name == "Coin_Server"
			or inst.Name == "CoinVisual"
			or string.find(n, "coin", 1, true) ~= nil
	end

	local function getCoinAdornee(coinObj)
		if not coinObj or not coinObj.Parent then return nil end
		if coinObj:IsA("Model") then
			return coinObj.PrimaryPart or coinObj:FindFirstChild("CoinVisual", true) or coinObj:FindFirstChildWhichIsA("BasePart", true) or coinObj
		elseif coinObj:IsA("BasePart") then
			return coinObj
		end
		return coinObj:FindFirstChildWhichIsA("BasePart", true) or coinObj
	end

	local function findAllCoinEntries()
		local results = {}
		local seen = {}

		local function addCoin(obj)
			if not obj or not obj.Parent or seen[obj] then return end
			if obj.Name == "uda_collected" or obj:GetAttribute("Collected") == true then return end
			if not isCoinObject(obj) then return end

			local targetModelOrPart = obj:IsA("BasePart") and obj.Name == "CoinVisual" and obj.Parent or obj
			if seen[targetModelOrPart] then return end
			seen[targetModelOrPart] = true

			local adornee = getCoinAdornee(targetModelOrPart)
			if adornee then
				table.insert(results, { container = targetModelOrPart, adornee = adornee })
			end
		end

		local container = TargetModel("CoinContainer")
		if container then
			for _, child in ipairs(container:GetDescendants()) do
				addCoin(child)
			end
		end

		if #results == 0 then
			local mapModel = TargetModel("Map")
			if mapModel then
				for _, child in ipairs(mapModel:GetDescendants()) do
					if child.Name == "Coin_Server" or (child:IsA("BasePart") and string.find(string.lower(child.Name), "coin", 1, true)) then
						addCoin(child)
					end
				end
			end
		end

		return results
	end

	local function syncCoinESP()
		if isInRoleCountdownGrace() or TrackCoinBag() then
			clearCoinESP()
			return
		end

		if not coinESPFolder or not coinESPFolder.Parent then
			coinESPFolder = Instance.new("Folder")
			coinESPFolder.Name = "_CoinESP"
			coinESPFolder.Parent = workspace
		end

		local entries = findAllCoinEntries()
		local validContainers = {}
		for _, entry in ipairs(entries) do
			validContainers[entry.container] = true
		end

		for _, child in ipairs(coinESPFolder:GetChildren()) do
			local tagVal = child:FindFirstChild("CoinRef")
			local refObj = tagVal and tagVal.Value
			if not refObj or not refObj.Parent or not validContainers[refObj] or refObj.Name == "uda_collected" or refObj:GetAttribute("Collected") == true then
				child:Destroy()
			end
		end

		local existingRefs = {}
		for _, child in ipairs(coinESPFolder:GetChildren()) do
			local tagVal = child:FindFirstChild("CoinRef")
			if tagVal and tagVal.Value then
				existingRefs[tagVal.Value] = true
			end
		end

		for _, entry in ipairs(entries) do
			if not existingRefs[entry.container] then
				local group = Instance.new("Folder")
				group.Name = "CoinESPItem"
				group.Parent = coinESPFolder

				local refVal = Instance.new("ObjectValue")
				refVal.Name = "CoinRef"
				refVal.Value = entry.container
				refVal.Parent = group

				local hl = Instance.new("Highlight")
				hl.Name = "_CoinCham"
				hl.Adornee = entry.container:IsA("Model") and entry.container or entry.adornee
				hl.FillColor = COIN_CHAM_YELLOW
				hl.OutlineColor = COIN_CHAM_YELLOW
				hl.FillTransparency = 0.25
				hl.OutlineTransparency = 0
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.Parent = group
			end
		end
	end

	-- --- Role Notification --------------------------------------------------------
	local lastNotifiedRole = nil
	local lastRoundRoleSnapshot = {}

	local function formatRoleBanner(roleName)
		if roleName == "Murderer" then
			return "YOU ARE THE MURDERER", Color3.fromRGB(255, 65, 65)
		elseif roleName == "Sheriff" or roleName == "Hero" then
			return "YOU ARE THE SHERIFF", Color3.fromRGB(75, 145, 255)
		else
			return "YOU ARE INNOCENT", Color3.fromRGB(76, 215, 134)
		end
	end

	local function showRoleNotification(roleText, roleColor)
		local existing = GuiParent:FindFirstChild("_RoleNotif")
		if existing then existing:Destroy() end

		local sg = Instance.new("ScreenGui")
		sg.Name = "_RoleNotif"
		sg.ResetOnSpawn = false
		sg.IgnoreGuiInset = true
		sg.DisplayOrder = 50
		tryParentScreenGui(sg, GuiParent)

		local frame = Instance.new("Frame", sg)
		frame.Size = UDim2.new(0, 320, 0, 64)
		frame.Position = UDim2.new(0.5, -160, 0, 76)
		frame.BackgroundColor3 = Color3.fromRGB(14, 17, 25)
		frame.BackgroundTransparency = 0.08
		frame.BorderSizePixel = 0
		Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 11)
		local st = Instance.new("UIStroke", frame)
		st.Color = roleColor
		st.Thickness = 1.4
		st.Transparency = 0.25

		local bar = Instance.new("Frame", frame)
		bar.Size = UDim2.new(0, 7, 1, 0)
		bar.BackgroundColor3 = roleColor
		bar.BorderSizePixel = 0
		Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 6)

		local lbl = Instance.new("TextLabel", frame)
		lbl.Size = UDim2.new(1, -22, 1, 0)
		lbl.Position = UDim2.new(0, 16, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = roleText
		lbl.TextColor3 = roleColor
		lbl.TextSize = 20
		lbl.Font = Enum.Font.GothamBold
		lbl.TextXAlignment = Enum.TextXAlignment.Left

		task.delay(3.2, function()
			if sg and sg.Parent then sg:Destroy() end
		end)
	end

	local function pollRolesAndNotify()
		pcall(function()
			Murderer = Fetch("Knife")
			Sheriff = Fetch("Gun")
			local getData = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
			if getData and getData:IsA("RemoteFunction") then
				local newRoles = getData:InvokeServer()
				if type(newRoles) == "table" then
					roles = newRoles
				end
			end
		end)

		if not state.roleNotif then
			lastNotifiedRole = nil
			return
		end

		local activeMap = TargetModel("Spawns")
		local myRoleEntry = roles and roles[LocalPlayer.Name]
		local roleName = (myRoleEntry and myRoleEntry.Role)
			or (Murderer == LocalPlayer.Name and "Murderer")
			or (Sheriff == LocalPlayer.Name and "Sheriff")
			or (activeMap and "Innocent")
			or nil

		if roleName and (roleName ~= lastNotifiedRole or (activeMap and not lastRoundRoleSnapshot[LocalPlayer.Name])) then
			lastNotifiedRole = roleName
			lastRoundRoleSnapshot[LocalPlayer.Name] = roleName
			local text, color = formatRoleBanner(roleName)
			pcall(showRoleNotification, text, color)
		elseif not roleName and not activeMap then
			lastNotifiedRole = nil
			do local __t=lastRoundRoleSnapshot for __k in next,__t do __t[__k]=nil end end
		end
	end

	-- --- RC Car -------------------------------------------------------------------
	local RC_SIT_OFFSET = CFrame.new(0, 2.2, 0)
	local rcSavedPlatformStand = false
	local rcOriginalCollides = {}
	local rcSeatWeld = nil
	local rcLastSafePos = nil

	local function isSafeGroundCFrame(cf)
		if not cf then return false end
		return cf.Position.Y > (workspace.FallenPartsDestroyHeight + 12)
	end

	local function findNearestSolidGround(originPos)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local exclude = {}
		local char = safeChar()
		if char then table.insert(exclude, char) end
		local pet = workspace:FindFirstChild("PetContainer")
		if pet then table.insert(exclude, pet) end
		params.FilterDescendantsInstances = exclude

		local downHit = workspace:Raycast(originPos + Vector3.new(0, 6, 0), Vector3.new(0, -180, 0), params)
		if downHit and downHit.Instance and downHit.Instance.CanCollide and downHit.Position.Y > (workspace.FallenPartsDestroyHeight + 10) then
			return CFrame.new(downHit.Position + Vector3.new(0, 2.1, 0))
		end

		local spawns = TargetModel("Spawns")
		if spawns then
			for _, sp in ipairs(spawns:GetDescendants()) do
				if sp:IsA("BasePart") then
					local cf = sp.CFrame * CFrame.new(0, 2.5, 0)
					if isSafeGroundCFrame(cf) then return cf end
				end
			end
		end

		local lobbyCF = resolveLobbyDestination()
		if lobbyCF and isSafeGroundCFrame(lobbyCF) then
			return lobbyCF
		end

		return nil
	end

	local function getCarBody(car)
		if not car then return nil end
		if car.PrimaryPart then return car.PrimaryPart end
		for _, name in ipairs({ "Body", "Chassis", "Main", "Base", "Seat", "VehicleSeat", "Hitbox" }) do
			local found = car:FindFirstChild(name, true)
			if found and found:IsA("BasePart") then return found end
		end
		local largest, maxVol = nil, 0
		for _, p in ipairs(car:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency < 1 then
				local vol = p.Size.X * p.Size.Y * p.Size.Z
				if vol > maxVol then
					maxVol = vol
					largest = p
				end
			end
		end
		if largest then return largest end
		for _, p in ipairs(car:GetDescendants()) do
			if p:IsA("BasePart") then return p end
		end
		return nil
	end

	local function findRCCar()
		local pet = workspace:FindFirstChild("PetContainer")
		if pet then
			local cars = pet:FindFirstChild("RCCars")
			if cars then
				if config.rcCarCustomName and config.rcCarCustomName ~= "" then
					local named = cars:FindFirstChild(config.rcCarCustomName)
					if named then return named end
				end
				local owned = cars:FindFirstChild(LocalPlayer.Name) or cars:FindFirstChild(LocalPlayer.Name .. "'s RCCar")
				if owned then return owned end
				for _, obj in ipairs(cars:GetChildren()) do
					if obj:GetAttribute("Owner") == LocalPlayer.Name or obj:FindFirstChild(LocalPlayer.Name) then
						return obj
					end
				end
				for _, obj in ipairs(cars:GetChildren()) do
					if obj:IsA("Model") or obj:IsA("BasePart") then return obj end
				end
			end
		end

		if config.rcCarCustomName and config.rcCarCustomName ~= "" then
			local lowerTarget = string.lower(config.rcCarCustomName)
			for _, obj in ipairs(workspace:GetDescendants()) do
				if (obj:IsA("Model") or obj:IsA("BasePart")) and string.lower(obj.Name) == lowerTarget then
					return obj
				end
			end
		end

		local hrp = safeHRP()
		local bestCar, bestDist = nil, math.huge
		for _, obj in ipairs(workspace:GetDescendants()) do
			if obj:IsA("Model") then
				local lower = string.lower(obj.Name)
				if lower == "rccar" or lower:find("rc_car") or lower:find("rc car") then
					local body = getCarBody(obj)
					if body then
						local d = hrp and (body.Position - hrp.Position).Magnitude or 0
						if d < bestDist then
							bestDist = d
							bestCar = obj
						end
					end
				end
			end
		end
		return bestCar
	end

	local function setCharNoCollideForRC(char, enable)
		if enable then
			do local __t=rcOriginalCollides for __k in next,__t do __t[__k]=nil end end
			for _, part in ipairs(char:GetDescendants()) do
				if part:IsA("BasePart") then
					rcOriginalCollides[part] = part.CanCollide
					part.CanCollide = false
				end
			end
		else
			for part, orig in pairs(rcOriginalCollides) do
				if part and part.Parent then
					part.CanCollide = orig
				end
			end
			do local __t=rcOriginalCollides for __k in next,__t do __t[__k]=nil end end
		end
	end

	local function clearRCSeatWeld()
		if rcSeatWeld then
			pcall(function() rcSeatWeld:Destroy() end)
			rcSeatWeld = nil
		end
		local hrp = safeHRP()
		if hrp then
			local leftover = hrp:FindFirstChild("_rcWeld")
			if leftover then pcall(function() leftover:Destroy() end) end
		end
	end

	local function MountRCCar()
		if rcRideConnection then
			rcRideConnection:Disconnect()
			rcRideConnection = nil
		end
		clearRCSeatWeld()

		local car = findRCCar()
		if not car then return false end
		local char = safeChar()
		local hrp = safeHRP()
		local hum = safeHum()
		if not char or not hrp or not hum then return false end
		local body = car:IsA("BasePart") and car or getCarBody(car)
		if not body then return false end

		local groundCF = findNearestSolidGround(hrp.Position)
		if groundCF then
			rcLastSafePos = groundCF
		elseif isSafeGroundCFrame(hrp.CFrame) then
			rcLastSafePos = hrp.CFrame + Vector3.new(0, 2.2, 0)
		end

		local seat = car:FindFirstChildWhichIsA("Seat", true) or car:FindFirstChildWhichIsA("VehicleSeat", true)
		if seat and not seat.Occupant then
			pcall(function()
				hrp.CFrame = seat.CFrame + Vector3.new(0, 1, 0)
				seat:Sit(hum)
			end)
		end

		setCharNoCollideForRC(char, true)
		rcSavedPlatformStand = hum.PlatformStand
		hum.Sit = true

		rcRideConnection = RunService.Heartbeat:Connect(function()
			if not body or not body.Parent or not state.rcActive then
				if rcRideConnection then rcRideConnection:Disconnect() rcRideConnection = nil end
				return
			end
			local c = safeChar()
			local h = safeHRP()
			local hu = safeHum()
			if not c or not h or not hu or hu.Health <= 0 then return end

			if not hu.Sit then
				hu.Sit = true
			end

			local carGround = findNearestSolidGround(body.Position)
			if carGround then
				rcLastSafePos = carGround
			end

			h.CFrame = body.CFrame * RC_SIT_OFFSET
			h.AssemblyLinearVelocity = body.AssemblyLinearVelocity
			h.AssemblyAngularVelocity = Vector3.zero
		end)

		return true
	end

	local function DismountRCCar()
		if rcRideConnection then
			rcRideConnection:Disconnect()
			rcRideConnection = nil
		end
		if rcDismountGuardConn then
			rcDismountGuardConn:Disconnect()
			rcDismountGuardConn = nil
		end
		clearRCSeatWeld()

		local char = safeChar()
		local hrp = safeHRP()
		local hum = safeHum()

		if char then
			for _, desc in ipairs(char:GetDescendants()) do
				if desc:IsA("Weld") or desc:IsA("WeldConstraint") or desc:IsA("ManualWeld") then
					if desc.Name == "SeatWeld" or desc.Name == "_rcWeld" then
						pcall(function() desc:Destroy() end)
					end
				end
			end
		end

		local groundSitCF = nil
		if hrp then
			groundSitCF = findNearestSolidGround(hrp.Position)
		end
		if not groundSitCF and rcLastSafePos and isSafeGroundCFrame(rcLastSafePos) then
			groundSitCF = rcLastSafePos
		end
		if not groundSitCF then
			local spawns = TargetModel("Spawns")
			if spawns then
				for _, sp in ipairs(spawns:GetDescendants()) do
					if sp:IsA("BasePart") and isSafeGroundCFrame(sp.CFrame) then
						groundSitCF = CFrame.new(sp.CFrame.Position + Vector3.new(0, 2.2, 0))
						break
					end
				end
			end
		end

		if hrp then
			hrp.Anchored = true
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			if groundSitCF then
				hrp.CFrame = groundSitCF
			elseif isSafeGroundCFrame(hrp.CFrame) then
				hrp.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 2, 0))
			end
		end

		if char then
			refreshCharBaseParts(char)
			if state.noclip or (state.autoFarm and IsAlive(LocalPlayer, roles)) then
				for _, part in ipairs(charBaseParts) do
					if part and part.Parent then
						part.CanCollide = false
					end
				end
			else
				setCharNoCollideForRC(char, false)
				for _, part in ipairs(charBaseParts) do
					if part and part.Parent then
						local n = part.Name
						if n == "HumanoidRootPart" or n == "UpperTorso" or n == "LowerTorso" or n == "Torso" or n == "LeftUpperLeg" or n == "RightUpperLeg" or n == "Left Leg" or n == "Right Leg" then
							part.CanCollide = true
						end
					end
				end
			end
		end

		if hum then
			hum.PlatformStand = false
			hum.Sit = true
			pcall(function() hum:ChangeState(Enum.HumanoidStateType.Seated) end)
		end

		local guardStart = os.clock()
		rcDismountGuardConn = RunService.Heartbeat:Connect(function()
			local h = safeHRP()
			local hu = safeHum()
			if not h or not hu or (os.clock() - guardStart) > 0.85 then
				if rcDismountGuardConn then
					rcDismountGuardConn:Disconnect()
					rcDismountGuardConn = nil
				end
				if h and h.Anchored then
					h.AssemblyLinearVelocity = Vector3.zero
					h.AssemblyAngularVelocity = Vector3.zero
					h.Anchored = false
				end
				if hu then
					hu.PlatformStand = false
					hu.Sit = false
					hu.WalkSpeed = state.walkSpeed and (config.walkSpeedVal or 16) or 16
					hu.JumpPower = state.jumpPower and (config.jumpPowerVal or 50) or 50
					pcall(function() hu:ChangeState(Enum.HumanoidStateType.GettingUp) end)
				end
				return
			end

			if not hu.Sit then hu.Sit = true end
			if groundSitCF and (h.Position.Y < groundSitCF.Position.Y - 2.5 or h.Position.Y < (workspace.FallenPartsDestroyHeight + 15)) then
				h.CFrame = groundSitCF
			end
			h.AssemblyLinearVelocity = Vector3.zero
			h.AssemblyAngularVelocity = Vector3.zero
		end)
	end

	-- --- Bomb ---------------------------------------------------------------------
	local selectedTarget = nil

	local function getTargetPlayerCharacter(name)
		if not name then return nil end
		local p = Players:FindFirstChild(name)
		if p and p.Character then
			return p.Character
		end
		return workspace:FindFirstChild(name)
	end

	local function findDroppedBomb()
		for _, obj in ipairs(workspace:GetChildren()) do
			local name = string.lower(obj.Name)
			if string.find(name, "prank") or string.find(name, "bomb") then
				if obj:IsA("Model") then
					return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
				elseif obj:IsA("BasePart") then
					return obj
				end
			end
		end
		return nil
	end

	local function detonateBombOnTarget(bombPart)
		if not selectedTarget then return end
		local targetChar = getTargetPlayerCharacter(selectedTarget)
		local targetHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
		if not targetHRP or not bombPart then return end

		pcall(function()
			bombPart.Anchored = false
			bombPart.CanCollide = true
			bombPart.Massless = false
			bombPart.CFrame = targetHRP.CFrame
			bombPart.AssemblyLinearVelocity = Vector3.zero
			bombPart.AssemblyAngularVelocity = Vector3.zero

			task.wait()

			local angle = math.random() * math.pi * 2
			bombPart.AssemblyLinearVelocity = Vector3.new(math.cos(angle) * 500, 800, math.sin(angle) * 500)
			bombPart.AssemblyAngularVelocity = Vector3.new(math.random(-50, 50), math.random(-50, 50), math.random(-50, 50))
		end)
	end

	local function BombTarget()
		if not selectedTarget then return end
		local targetChar = getTargetPlayerCharacter(selectedTarget)
		if not targetChar then return end

		local dropped = findDroppedBomb()
		if dropped then
			detonateBombOnTarget(dropped)
			return
		end

		local char = safeChar()
		local bomb = char and (char:FindFirstChild("PrankBomb") or char:FindFirstChild("Bomb"))
		if bomb and bomb:IsA("Tool") then
			local hum = safeHum()
			if hum then hum:UnequipTools() end
			task.wait(0.1)
		end

		local deadline = os.clock() + 2
		local found
		repeat
			task.wait(0.05)
			found = findDroppedBomb()
		until found or os.clock() > deadline

		if found then
			detonateBombOnTarget(found)
		end
	end

	-- --- Movement & Anti-AFK Helpers ----------------------------------------------
	local function startNoclip()
		if noclipConnection then noclipConnection:Disconnect() noclipConnection = nil end
		ensurePhysicsCoordinator()
	end

	local function stopNoclip()
		if noclipConnection then
			noclipConnection:Disconnect()
			noclipConnection = nil
		end
	end

	local function startInfiniteJump()
		if ijConnection then ijConnection:Disconnect() end
		ijConnection = UserInputService.JumpRequest:Connect(function()
			local hum = safeHum()
			if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
		end)
	end

	local function stopInfiniteJump()
		if ijConnection then
			ijConnection:Disconnect()
			ijConnection = nil
		end
	end

	local function startAntiAfk()
		if antiAfkIdledConn then
			antiAfkIdledConn:Disconnect()
			antiAfkIdledConn = nil
		end
		antiAfkIdledConn = LocalPlayer.Idled:Connect(function()
			if not state.antiAfk then return end
			pcall(function()
				local cam = workspace.CurrentCamera
				local cf = cam and cam.CFrame or CFrame.new()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new(0, 0), cf)
			end)
		end)
	end

	local function stopAntiAfk()
		if antiAfkIdledConn then
			antiAfkIdledConn:Disconnect()
			antiAfkIdledConn = nil
		end
	end

	-- --- Main Page ----------------------------------------------------------------
	MainPage:addDropdown("Farm Mode", { "Nearest + XP Farm", "Nearest", "Randomize" }, 2, function(val)
		config.farmMode = val
		autoSave()
	end, config.farmMode)

	MainPage:addToggle("Stealth Auto Farm", function(enabled)
		config.stealthAutoFarm = enabled
		config.st_stealthAutoFarm = enabled
		if not enabled then
			ghostChar(false)
			unfreezeChar()
			stealthPickupActive = false
		end
		autoSave()
	end, config.st_stealthAutoFarm)

	MainPage:addSlider("Farm Tween Speed", 10, 80, config.farmSpeed, 1, function(val)
		config.farmSpeed = val
		autoSave()
	end)

	MainPage:addSlider("Murderer Safe Radius", 15, 100, config.murdererSafeRadius, 5, function(val)
		config.murdererSafeRadius = val
		autoSave()
	end)

	MainPage:addToggle("Auto Farm", function(enabled)
		state.autoFarm = enabled
		config.st_autoFarm = enabled
		autoSave()
		if enabled then
			task.spawn(function()
				while state.autoFarm do
					AutoFarmTick(config.farmMode)
					task.wait(0.06)
				end
				ghostChar(false)
				unfreezeChar()
				stealthPickupActive = false
				DestroyBody()
			end)
		else
			cancelActiveTween()
			ghostChar(false)
			unfreezeChar()
			stealthPickupActive = false
			DestroyBody()
		end
	end, config.st_autoFarm)

	MainPage:addToggle("Auto Grab Gun", function(enabled)
		state.autoGrabGun = enabled
		config.st_autoGrabGun = enabled
		autoSave()
		if enabled then
			task.spawn(function()
				while state.autoGrabGun do
					pcall(function()
						if Murderer then
							local localHRP = safeHRP()
							local gunDrop = findGunDrop()
							if IsAlive(LocalPlayer, roles) and Murderer ~= LocalPlayer.Name and
								localHRP and gunDrop and (TrackCoinBag() or not state.autoFarm) then
								gunDrop.CFrame = localHRP.CFrame
							end
						end
					end)
					task.wait(0.08)
				end
			end)
		end
	end, config.st_autoGrabGun)

	MainPage:addToggle("Dodge Thrown Knife", function(enabled)
		state.dodgeKnife = enabled
		config.st_dodgeKnife = enabled
		autoSave()
		if enabled then
			task.spawn(function()
				local lastDodge = 0
				while state.dodgeKnife do
					pcall(function()
						local now = os.clock()
						local hrp = safeHRP()
						if not hrp then return end
						for _, child in ipairs(workspace:GetChildren()) do
							if child.Name == "ThrowingKnife" then
								local blade = child:FindFirstChild("BladePosition")
								if blade then
									local dist = (blade.Position - hrp.Position).Magnitude
									if dist <= 15 and (now - lastDodge) > 0.4 then
										lastDodge = now
										local orig = hrp.CFrame
										hrp.CFrame = orig * CFrame.new(0, 100, 0)
										task.wait(0.2)
										if safeHRP() then
											safeHRP().CFrame = orig
										end
									end
								end
							end
						end
					end)
					task.wait(0.03)
				end
			end)
		end
	end, config.st_dodgeKnife)

	MainPage:addToggle("Auto End Round", function(enabled)
		state.autoEndRound = enabled
		config.st_autoEndRound = enabled
		autoSave()
		if enabled then
			task.spawn(function()
				while state.autoEndRound do
					local murderer = Murderer and Players:FindFirstChild(Murderer)
					if murderer and not IsAlive(LocalPlayer, roles) and Murderer ~= LocalPlayer.Name then
						pcall(function()
							local mod = getExecModule()
							if mod and type(mod.fling) == "function" then
								mod:fling(murderer)
							end
						end)
						task.wait(3)
					else
						task.wait(0.25)
					end
				end
			end)
		end
	end, config.st_autoEndRound)

	MainPage:addButton("Teleport To Lobby", function()
		pcall(teleportToLobbyAction)
	end)

	MainPage:addButton("Teleport To Map", function()
		pcall(teleportToMapAction)
	end)

	-- --- Visuals Page -------------------------------------------------------------
	VisualsPage:addToggle("Player Chams", function(enabled)
		state.playerChams = enabled
		config.st_playerChams = enabled
		autoSave()
		if enabled then
			task.spawn(function()
				while state.playerChams do
					ManageHighlights()
					task.wait(0.2)
				end
				DestroyHighlights()
			end)
		else
			DestroyHighlights()
		end
	end, config.st_playerChams)

	VisualsPage:addToggle("Skeleton ESP", function(enabled)
		state.skeletonESP = enabled
		config.st_skeletonESP = enabled
		autoSave()
		if enabled then
			rebuildSkeletons()
			task.spawn(function()
				while state.skeletonESP do
					task.wait(2)
					if state.skeletonESP then
						rebuildSkeletons()
					end
				end
			end)
		else
			clearAllSkeletons()
		end
	end, config.st_skeletonESP)

	VisualsPage:addToggle("Coin ESP", function(enabled)
		state.coinESP = enabled
		config.st_coinESP = enabled
		autoSave()
		if enabled then
			syncCoinESP()
			task.spawn(function()
				while state.coinESP do
					pcall(syncCoinESP)
					task.wait(0.35)
				end
				clearCoinESP()
			end)
		else
			clearCoinESP()
		end
	end, config.st_coinESP)

	local function clearGunCham()
		local gunDrop = findGunDrop()
		if gunDrop then
			local esp = gunDrop:FindFirstChild("GunESP")
			if esp then esp:Destroy() end
		end
	end

	VisualsPage:addToggle("Gun Cham", function(enabled)
		state.gunCham = enabled
		config.st_gunCham = enabled
		autoSave()
		if enabled then
			task.spawn(function()
				while state.gunCham do
					local gunDrop = findGunDrop()
					if gunDrop and not gunDrop:FindFirstChild("GunESP") then
						local esp = Instance.new("Highlight")
						esp.Name = "GunESP"
						esp.FillTransparency = 0.5
						esp.FillColor = Color3.fromRGB(128, 225, 0)
						esp.OutlineColor = Color3.fromRGB(0, 163, 0)
						esp.OutlineTransparency = 0
						esp.Parent = gunDrop
					end
					task.wait(0.25)
				end
				clearGunCham()
			end)
		else
			clearGunCham()
		end
	end, config.st_gunCham)

	local function clearNameTags()
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character and player.Character:FindFirstChild("Head") then
				local tag = player.Character.Head:FindFirstChild("UsernameTag")
				if tag then tag:Destroy() end
			end
		end
	end

	VisualsPage:addToggle("Name ESP", function(enabled)
		state.nameESP = enabled
		config.st_nameESP = enabled
		autoSave()
		if enabled then
			task.spawn(function()
				while state.nameESP do
					for _, player in ipairs(Players:GetPlayers()) do
						if player.Character then
							createUsernameTag(player)
						end
					end
					task.wait(0.75)
				end
				clearNameTags()
			end)
		else
			clearNameTags()
		end
	end, config.st_nameESP)

	-- --- Target Page -------------------------------------------------------------
	local playerList = {}

	local function refreshPlayerList()
		do local __t=playerList for __k in next,__t do __t[__k]=nil end end
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer then
				table.insert(playerList, player.Name)
			end
		end
	end

	refreshPlayerList()
	selectedTarget = playerList[1] or nil

	TargetPage:addDropdown("Target", playerList, 3, function(val)
		selectedTarget = val
	end, selectedTarget)

	TargetPage:addToggle("Fling Target", function(enabled)
		state.flingTarget = enabled
		if enabled then
			task.spawn(function()
				while state.flingTarget do
					pcall(function()
						local target = selectedTarget and Players:FindFirstChild(selectedTarget)
						local mod = getExecModule()
						if target and mod and type(mod.fling) == "function" then
							mod:fling(target)
						end
					end)
					task.wait(3)
				end
			end)
		end
	end)

	TargetPage:addToggle("Spectate Target", function(enabled)
		state.spectateTarget = enabled
		if enabled then
			task.spawn(function()
				while state.spectateTarget do
					local targetChar = getTargetPlayerCharacter(selectedTarget)
					if targetChar and targetChar:FindFirstChild("Head") then
						workspace.CurrentCamera.CameraSubject = targetChar.Head
					end
					task.wait(0.05)
				end
				local char = safeChar()
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if hum then
					workspace.CurrentCamera.CameraSubject = hum
					workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
				end
			end)
		end
	end)

	TargetPage:addToggle("Loop Go To Target", function(enabled)
		state.loopGoToTarget = enabled
		if enabled then
			task.spawn(function()
				while state.loopGoToTarget do
					pcall(function()
						local hrp = safeHRP()
						local targetChar = getTargetPlayerCharacter(selectedTarget)
						local targetHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
						if hrp and targetHRP then
							hrp.CFrame = targetHRP.CFrame
						end
					end)
					task.wait(0.03)
				end
			end)
		end
	end)

	TargetPage:addButton("Teleport To Target", function()
		local hrp = safeHRP()
		local targetChar = getTargetPlayerCharacter(selectedTarget)
		local targetHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
		if hrp and targetHRP then
			hrp.CFrame = targetHRP.CFrame
		end
	end)

	TargetPage:addButton("Fling Bomb To Target", function()
		pcall(BombTarget)
	end)

	TargetPage:addToggle("Fling Sheriff", function(enabled)
		state.flingSheriff = enabled
		if enabled then
			task.spawn(function()
				while state.flingSheriff do
					pcall(function()
						local target = Sheriff and Players:FindFirstChild(Sheriff)
						local mod = getExecModule()
						if target and Sheriff ~= LocalPlayer.Name and mod and type(mod.fling) == "function" then
							mod:fling(target)
						end
					end)
					task.wait(3)
				end
			end)
		end
	end)

	TargetPage:addToggle("Fling Murderer", function(enabled)
		state.flingMurderer = enabled
		if enabled then
			task.spawn(function()
				while state.flingMurderer do
					pcall(function()
						local target = Murderer and Players:FindFirstChild(Murderer)
						local mod = getExecModule()
						if target and Murderer ~= LocalPlayer.Name and mod and type(mod.fling) == "function" then
							mod:fling(target)
						end
					end)
					task.wait(3)
				end
			end)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		if player ~= LocalPlayer and not table.find(playerList, player.Name) then
			table.insert(playerList, player.Name)
			if not selectedTarget then
				selectedTarget = player.Name
			end
		end
		if state.skeletonESP then rebuildSkeletons() end
	end)

	Players.PlayerRemoving:Connect(function(player)
		for i, name in ipairs(playerList) do
			if name == player.Name then
				table.remove(playerList, i)
				break
			end
		end
		if selectedTarget == player.Name then
			selectedTarget = playerList[1] or nil
		end
		velocityHistory[player.Name] = nil
		if state.skeletonESP then rebuildSkeletons() end
	end)

	-- --- Roles Page ---------------------------------------------------------------
	RolesPage:addSlider("Aura Distance (studs)", 5, 60, config.auraDistance, 1, function(val)
		config.auraDistance = val
		autoSave()
	end)

	local _cachedStabTrack = nil
	local _cachedStabHum = nil
	local _knifeDrawnByAura = false
	local _manualStowUntil = 0
	local _lastKnifeEquippedTick = 0
	local _lastManualEquipOrUnequipTick = 0
	local FALLBACK_STAB_ANIM_ID = "rbxassetid://2467567750"

	local function markManualStow(duration)
		_manualStowUntil = os.clock() + (duration or 1.25)
		_lastManualEquipOrUnequipTick = os.clock()
		_knifeDrawnByAura = false

		local char = safeChar()
		local hum = safeHum()
		if char and char:FindFirstChild("Knife") then
			pcall(function()
				if hum then
					hum:UnequipTools()
				end
				local knife = char:FindFirstChild("Knife")
				local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
				if knife and knife.Parent == char and knife:IsA("Tool") and bp then
					knife.Parent = bp
				end
			end)
		end

		pcall(function()
			if _cachedStabTrack and _cachedStabTrack.IsPlaying then
				_cachedStabTrack:Stop(0.05)
			end
		end)
	end

	local function isManualStowActive()
		return os.clock() < _manualStowUntil
	end

	local function stopStabAnimationIfIdle()
		pcall(function()
			if _cachedStabTrack and _cachedStabTrack.IsPlaying then
				_cachedStabTrack:Stop(0.08)
			end
		end)
	end

	local function hookCharacterKnifeStowWatch(char)
		if not char then return end

		char.ChildRemoved:Connect(function(child)
			if child and child:IsA("Tool") and child.Name == "Knife" then
				if (os.clock() - _lastKnifeEquippedTick) > 0.08 then
					markManualStow(1.35)
				end
			end
		end)

		char.ChildAdded:Connect(function(child)
			if child and child:IsA("Tool") and child.Name == "Knife" then
				if (os.clock() - _lastKnifeEquippedTick) > 0.12 then
					_manualStowUntil = 0
					_lastManualEquipOrUnequipTick = os.clock()
				end
			end
		end)
	end

	if LocalPlayer.Character then
		hookCharacterKnifeStowWatch(LocalPlayer.Character)
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if input.KeyCode == Enum.KeyCode.One or input.KeyCode == Enum.KeyCode.Two or input.KeyCode == Enum.KeyCode.Three or input.KeyCode == Enum.KeyCode.Backspace then
				local char = safeChar()
				if char and char:FindFirstChild("Knife") then
					markManualStow(1.35)
				end
			end
		end
	end)

	local function pullOutKnifeAndAnimate(hum, forceReplay)
		if isManualStowActive() then
			return nil
		end

		local char = safeChar()
		local h = hum or safeHum()
		if not char or not h or h.Health <= 0 then return nil end

		local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
		local bpKnife = bp and bp:FindFirstChild("Knife")
		local eqKnife = char:FindFirstChild("Knife")

		if not eqKnife and bpKnife then
			_lastKnifeEquippedTick = os.clock()
			_knifeDrawnByAura = true
			pcall(function()
				h:EquipTool(bpKnife)
			end)
			local deadline = os.clock() + 0.25
			repeat
				task.wait(0.02)
				if isManualStowActive() then
					return nil
				end
				char = safeChar()
				eqKnife = char and char:FindFirstChild("Knife")
			until eqKnife or os.clock() > deadline
		end

		local knife = eqKnife or (char and char:FindFirstChild("Knife"))
		if not knife or isManualStowActive() then return nil end

		pcall(function()
			knife:Activate()
		end)

		local animObj = nil
		for _, desc in ipairs(knife:GetDescendants()) do
			if desc:IsA("Animation") then
				local n = string.lower(desc.Name)
				if n:find("stab") or n:find("slash") or n:find("swing") or n:find("attack") or n:find("equip") then
					animObj = desc
					break
				end
				if not animObj then
					animObj = desc
				end
			end
		end

		pcall(function()
			local animator = h:FindFirstChildOfClass("Animator") or h
			if _cachedStabHum ~= h then
				_cachedStabTrack = nil
				_cachedStabHum = h
			end

			if not _cachedStabTrack then
				local animToLoad = animObj
				if not animToLoad then
					animToLoad = Instance.new("Animation")
					animToLoad.AnimationId = FALLBACK_STAB_ANIM_ID
				end
				_cachedStabTrack = animator:LoadAnimation(animToLoad)
				_cachedStabTrack.Priority = Enum.AnimationPriority.Action
			end

			if _cachedStabTrack then
				if forceReplay or not _cachedStabTrack.IsPlaying then
					_cachedStabTrack:Stop(0.02)
					_cachedStabTrack:Play(0.05, 1, 1.35)
				end
			end
		end)

		return knife
	end

	local function tryKillWithKnife(knife, targetHRP)
		if not knife or not knife.Parent or not targetHRP or not targetHRP.Parent then return end
		if isManualStowActive() then return end
		local handle = knife:FindFirstChild("Handle")

		local events = knife:FindFirstChild("Events")
		if events then
			local ht = events:FindFirstChild("HandleTouched")
			if ht and ht:IsA("RemoteEvent") then
				pcall(function() ht:FireServer(targetHRP) end)
			end
			for _, ev in ipairs(events:GetChildren()) do
				if ev:IsA("RemoteEvent") and ev ~= ht then
					pcall(function() ev:FireServer(targetHRP) end)
				end
			end
		end

		for _, v in ipairs(knife:GetDescendants()) do
			if v:IsA("RemoteEvent") and (not events or not v:IsDescendantOf(events)) then
				pcall(function() v:FireServer(targetHRP) end)
			end
		end

		if handle and _firetouchinterest then
			pcall(function()
				_firetouchinterest(targetHRP, handle, 0)
				_firetouchinterest(targetHRP, handle, 1)
			end)
		end
	end

	RolesPage:addToggle("Kill Aura", function(enabled)
		state.killAura = enabled
		config.st_killAura = enabled
		autoSave()
		if enabled then
			_manualStowUntil = 0
			task.spawn(function()
				local lastSwingTime = 0
				while state.killAura do
					pcall(function()
						local char = safeChar()
						local hrp  = char and char:FindFirstChild("HumanoidRootPart")
						local hum  = safeHum()
						if not char or not hrp or not hum or hum.Health <= 0 then return end

						if isManualStowActive() then
							stopStabAnimationIfIdle()
							return
						end

						local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
						local hasKnife = char:FindFirstChild("Knife") or (bp and bp:FindFirstChild("Knife"))
						if Murderer ~= LocalPlayer.Name and not hasKnife then return end

						local targets = {}
						for _, v in ipairs(Players:GetPlayers()) do
							if v ~= LocalPlayer and v.Character and IsAlive(v, roles) then
								local er = v.Character:FindFirstChild("HumanoidRootPart")
								if er then
									local dist = (er.Position - hrp.Position).Magnitude
									if dist <= config.auraDistance then
										table.insert(targets, { hrp = er, dist = dist })
									end
								end
							end
						end

						if #targets == 0 then
							stopStabAnimationIfIdle()
							return
						end

						table.sort(targets, function(a, b) return a.dist < b.dist end)

						local wasUnequipped = (char:FindFirstChild("Knife") == nil)
						local knife = pullOutKnifeAndAnimate(hum, true)
						if not knife or not knife.Parent or isManualStowActive() then return end

						local now = os.clock()
						if wasUnequipped or (now - lastSwingTime) >= 0.28 then
							lastSwingTime = now
							pullOutKnifeAndAnimate(hum, true)
						end

						for _, entry in ipairs(targets) do
							if not state.killAura or isManualStowActive() then break end
							local er = entry.hrp
							local freshHRP = safeHRP()
							if er and er.Parent and freshHRP then
								if (er.Position - freshHRP.Position).Magnitude <= config.auraDistance then
									tryKillWithKnife(knife, er)
									task.wait(0.06)
								end
							end
						end
					end)

					task.wait(0.06)
				end
				stopStabAnimationIfIdle()
				_knifeDrawnByAura = false
			end)
		else
			stopStabAnimationIfIdle()
			_knifeDrawnByAura = false
		end
	end, config.st_killAura)

	RolesPage:addToggle("Auto Kill All", function(enabled)
		state.autoKillAll = enabled
		config.st_autoKillAll = enabled
		autoSave()
		if enabled then
			_manualStowUntil = 0
			task.spawn(function()
				while state.autoKillAll do
					if not isManualStowActive() then
						local char = safeChar()
						local hum = safeHum()
						local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
						local hasKnife = (char and char:FindFirstChild("Knife")) or (bp and bp:FindFirstChild("Knife"))
						if (Murderer == LocalPlayer.Name or hasKnife) and hum then
							pcall(function()
								local knife = pullOutKnifeAndAnimate(hum, true)
								if not knife then return end
								for _, player in ipairs(Players:GetPlayers()) do
									if not state.autoKillAll or isManualStowActive() then break end
									if player ~= LocalPlayer and player.Character and IsAlive(player, roles) then
										local tHRP = player.Character:FindFirstChild("HumanoidRootPart")
										if tHRP then
											tryKillWithKnife(knife, tHRP)
										end
									end
								end
							end)
						end
					end
					task.wait(0.15)
				end
				stopStabAnimationIfIdle()
			end)
		else
			stopStabAnimationIfIdle()
		end
	end, config.st_autoKillAll)

	-- --- Silent Aim ---------------------------------------------------------------
	local silentAimActiveGun = nil
	local silentAimTapConn = nil

	local function disconnectSilentAim()
		if silentAimConn then
			silentAimConn:Disconnect()
			silentAimConn = nil
		end
		if silentAimTapConn then
			silentAimTapConn:Disconnect()
			silentAimTapConn = nil
		end
		silentAimActiveGun = nil
	end

	local function getSilentAimTarget(ignoreWallCheck)
		local myHRP = safeHRP()
		if not myHRP then return nil, nil end

		if Murderer and Murderer ~= LocalPlayer.Name then
			local mp = Players:FindFirstChild(Murderer)
			if mp and mp.Character and IsAlive(mp, roles) then
				local hrp = mp.Character:FindFirstChild("HumanoidRootPart")
				if hrp and (ignoreWallCheck or isPlayerVisible(mp)) then
					return mp, hrp
				end
			end
		end

		local closest, closestHRP, closestDist = nil, nil, math.huge
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer and p.Character and IsAlive(p, roles) then
				local pHRP = p.Character:FindFirstChild("HumanoidRootPart")
				if pHRP and (ignoreWallCheck or isPlayerVisible(p)) then
					local dist = (pHRP.Position - myHRP.Position).Magnitude
					if dist < closestDist then
						closest     = p
						closestHRP  = pHRP
						closestDist = dist
					end
				end
			end
		end
		return closest, closestHRP
	end

	local function installSilentAimNamecallHook()
		if silentAimHooked then return end
		if not _hookmetamethod or not _getnamecallmethod then return end
		silentAimHooked = true

		pcall(function()
			local oldNamecall
			oldNamecall = _hookmetamethod(game, "__namecall", _newcclosure(function(self, ...)
				local method = _getnamecallmethod()
				if state.silentAim and not _firingSilentShot and not _checkcaller() and (method == "FireServer" or method == "InvokeServer") then
					local lowerName = string.lower(self.Name)
					if lowerName == "shoot" or lowerName == "createbeam" or lowerName:find("shoot") then
						local char = safeChar()
						local hrp = safeHRP()
						local gun = char and char:FindFirstChild("Gun")
						if gun and hrp and isGunReady(gun) then
							local targetPlayer, targetHRP = getSilentAimTarget(false)
							if not targetHRP then
								targetPlayer, targetHRP = getSilentAimTarget(true)
							end
							if targetPlayer and targetPlayer.Character and targetHRP then
								local originCF = getGunOriginCF(gun, hrp)
								local predictedCF = PredictTargetCFrame(targetPlayer.Character, targetPlayer.Name, originCF.Position)
								local aimedOrigin = CFrame.new(originCF.Position, predictedCF.Position)
								_firingSilentShot = true
								local ret
								if method == "InvokeServer" then
									ret = oldNamecall(self, 1, predictedCF.Position, "AH2")
								else
									ret = oldNamecall(self, aimedOrigin, predictedCF)
								end
								_firingSilentShot = false
								return ret
							end
						end
					end
				end
				return oldNamecall(self, ...)
			end))
		end)
	end

	local function triggerSilentAimForGun(gun)
		if not state.silentAim or _firingSilentShot then return end
		local char = safeChar()
		local hrp = safeHRP()
		local activeGun = gun or (char and char:FindFirstChild("Gun"))
		if not activeGun or not char or not hrp or activeGun.Parent ~= char then return end
		if not isGunReady(activeGun) then return end

		local targetPlayer, targetHRP = getSilentAimTarget(false)
		if not targetHRP then
			targetPlayer, targetHRP = getSilentAimTarget(true)
		end
		if not targetPlayer or not targetPlayer.Character or not targetHRP then return end

		local dist = (targetHRP.Position - hrp.Position).Magnitude
		if dist > 450 then return end

		local originCF = getGunOriginCF(activeGun, hrp)
		local aimCF    = PredictTargetCFrame(targetPlayer.Character, targetPlayer.Name, originCF.Position)

		local shootRemote = getShootRemote(activeGun)
		if shootRemote then
			fireGunRemote(shootRemote, originCF, aimCF)
		end
	end

	local function hookGunForSilentAim(gun)
		if silentAimActiveGun == gun then return end
		disconnectSilentAim()
		silentAimActiveGun = gun

		silentAimConn = gun.Activated:Connect(function()
			if not state.silentAim then return end
			task.defer(function()
				triggerSilentAimForGun(gun)
			end)
		end)

		silentAimTapConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if not state.silentAim or gameProcessed then return end
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				local char = safeChar()
				if char and char:FindFirstChild("Gun") == gun then
					task.defer(function()
						triggerSilentAimForGun(gun)
					end)
				end
			end
		end)
	end

	RolesPage:addToggle("Silent Aim", function(enabled)
		state.silentAim = enabled
		config.st_silentAim = enabled
		autoSave()
		if not enabled then
			disconnectSilentAim()
			return
		end

		installSilentAimNamecallHook()

		task.spawn(function()
			while state.silentAim do
				local char = safeChar()
				local gun  = char and char:FindFirstChild("Gun")

				if gun then
					hookGunForSilentAim(gun)
				else
					if silentAimActiveGun then
						disconnectSilentAim()
					end
				end
				task.wait(0.1)
			end
			disconnectSilentAim()
		end)
	end, config.st_silentAim)

	RolesPage:addToggle("Kill Murderer (Blatant)", function(enabled)
		state.killMurderer = enabled
		config.st_killMurderer = enabled
		autoSave()
		if enabled then
			task.spawn(function()
				while state.killMurderer do
					pcall(function()
						if Murderer and Murderer ~= LocalPlayer.Name then
							local gun = getEquippedOrBackpackGun()
							if gun and IsAlive(LocalPlayer, roles) then
								Equip("Gun")
								ShootMurderer(true)
							end
						end
					end)
					task.wait(0.06)
				end
			end)
		end
	end, config.st_killMurderer)

	local _lastAutoShot = 0
	local AUTO_SHOOT_INTERVAL = 0.25
	local AUTO_SHOOT_MAX_RANGE = 450

	RolesPage:addToggle("Auto Shoot Murderer", function(enabled)
		state.autoShootMurd = enabled
		config.st_autoShootMurd = enabled
		autoSave()
		if enabled then
			task.spawn(function()
				while state.autoShootMurd do
					pcall(function()
						local now = os.clock()
						if (now - _lastAutoShot) < AUTO_SHOOT_INTERVAL then return end
						if not Murderer or Murderer == LocalPlayer.Name then return end
						if not IsAlive(LocalPlayer, roles) then return end

						local char = safeChar()
						local hrp  = safeHRP()
						if not char or not hrp then return end

						local gun = getEquippedOrBackpackGun()
						if not gun or not isGunReady(gun) then return end

						local murderer    = Players:FindFirstChild(Murderer)
						local murdererHRP = murderer and murderer.Character and murderer.Character:FindFirstChild("HumanoidRootPart")
						if not murdererHRP or not IsAlive(murderer, roles) then return end

						if (murdererHRP.Position - hrp.Position).Magnitude > AUTO_SHOOT_MAX_RANGE then return end
						if not isPlayerVisible(murderer) then return end

						_lastAutoShot = now
						Equip("Gun")
						ShootMurderer(true)
					end)
					task.wait(0.04)
				end
			end)
		end
	end, config.st_autoShootMurd)

	-- --- Player Page --------------------------------------------------------------
	PlayerPage:addSlider("Walk Speed Value", 16, 100, config.walkSpeedVal, 1, function(val)
		config.walkSpeedVal = val
		autoSave()
	end)

	PlayerPage:addToggle("Walk Speed", function(enabled)
		state.walkSpeed = enabled
		config.st_walkSpeed = enabled
		autoSave()
		if enabled then
			task.spawn(function()
				while state.walkSpeed do
					setCharacterAttributes(config.walkSpeedVal)
					task.wait(0.05)
				end
				setCharacterAttributes(16)
			end)
		else
			setCharacterAttributes(16)
		end
	end, config.st_walkSpeed)

	PlayerPage:addSlider("Jump Power Value", 50, 150, config.jumpPowerVal, 1, function(val)
		config.jumpPowerVal = val
		autoSave()
	end)

	PlayerPage:addToggle("Jump Power", function(enabled)
		state.jumpPower = enabled
		config.st_jumpPower = enabled
		autoSave()
		if enabled then
			task.spawn(function()
				while state.jumpPower do
					setCharacterAttributes(nil, config.jumpPowerVal)
					task.wait(0.05)
				end
				setCharacterAttributes(nil, 50)
			end)
		else
			setCharacterAttributes(nil, 50)
		end
	end, config.st_jumpPower)

	PlayerPage:addToggle("Infinite Jump", function(enabled)
		state.infiniteJump = enabled
		config.st_infiniteJump = enabled
		autoSave()
		if enabled then startInfiniteJump() else stopInfiniteJump() end
	end, config.st_infiniteJump)

	PlayerPage:addToggle("Noclip", function(enabled)
		state.noclip = enabled
		config.st_noclip = enabled
		autoSave()
		if enabled then startNoclip() else stopNoclip() end
	end, config.st_noclip)

	PlayerPage:addToggle("Invisible [FE]", function(enabled)
		if enabled then
			invis_on = true
			local hrp = safeHRP()
			local char = safeChar()
			if not hrp or not char then return end
			local savedpos = hrp.CFrame
			task.wait()
			char:MoveTo(Vector3.new(-25, 6000, 100))
			task.wait(0.35)
			local Seat = Instance.new("Seat", workspace)
			Seat.Anchored = false
			Seat.CanCollide = false
			Seat.Name = "invischair"
			Seat.Transparency = 1
			Seat.Position = Vector3.new(-25.95, 84, 3537.55)
			local Weld = Instance.new("Weld", Seat)
			Weld.Part0 = Seat
			Weld.Part1 = safeHRP()
			task.wait()
			Seat.CFrame = savedpos
		else
			invis_on = false
			local invisChair = workspace:FindFirstChild("invischair")
			if invisChair then invisChair:Destroy() end
		end
	end)

	PlayerPage:addToggle("Anti Fling", function(enabled)
		state.antiFling = enabled
		config.st_antiFling = enabled
		autoSave()
		if enabled then
			ensurePhysicsCoordinator()
		end
	end, config.st_antiFling)

	-- --- Misc Page ----------------------------------------------------------------
	MiscPage:addToggle("Role Notification", function(enabled)
		state.roleNotif = enabled
		config.st_roleNotif = enabled
		autoSave()
		lastNotifiedRole = nil
		do local __t=lastRoundRoleSnapshot for __k in next,__t do __t[__k]=nil end end
		if enabled then
			task.defer(pollRolesAndNotify)
		end
	end, config.st_roleNotif)

	MiscPage:addToggle("3D Rendering Off When Tabbed", function(enabled)
		state.renderOffFocus = enabled
		config.st_renderOffFocus = enabled
		autoSave()
		if focusLostConn then focusLostConn:Disconnect() focusLostConn = nil end
		if focusGainedConn then focusGainedConn:Disconnect() focusGainedConn = nil end

		if enabled then
			focusLostConn = UserInputService.WindowFocusReleased:Connect(function()
				if state.renderOffFocus then
					RunService:Set3dRenderingEnabled(false)
				end
			end)
			focusGainedConn = UserInputService.WindowFocused:Connect(function()
				RunService:Set3dRenderingEnabled(true)
			end)
		else
			RunService:Set3dRenderingEnabled(true)
		end
	end, config.st_renderOffFocus)

	local _cachedEmoteRemote = nil
	local _emoteModule = nil

	local function getEmoteModule()
		if _emoteModule then return _emoteModule end
		local mod = getExecModule()
		if mod and type(mod.emote) == "function" then
			_emoteModule = mod
			return _emoteModule
		end
		pcall(function()
			if typeof(game.HttpGet) == "function" and _loadstring then
				local src = game:HttpGet("https://raw.smokingscripts.org/module")
				if src and #src > 0 then
					local fn = _loadstring(src)
					if type(fn) == "function" then
						local loaded = fn()
						if type(loaded) == "table" and type(loaded.emote) == "function" then
							_emoteModule = loaded
						end
					end
				end
			end
		end)
		return _emoteModule
	end

	local function findEmoteRemote()
		if _cachedEmoteRemote and _cachedEmoteRemote.Parent then
			return _cachedEmoteRemote
		end

		local rem = ReplicatedStorage:FindFirstChild("Remotes")
		if rem then
			local gameplay = rem:FindFirstChild("Gameplay")
			if gameplay then
				for _, v in ipairs(gameplay:GetChildren()) do
					if v:IsA("RemoteEvent") and string.find(string.lower(v.Name), "emote") then
						_cachedEmoteRemote = v
						return v
					end
				end
			end
			for _, v in ipairs(rem:GetChildren()) do
				if v:IsA("RemoteEvent") and string.find(string.lower(v.Name), "emote") then
					_cachedEmoteRemote = v
					return v
				end
			end
		end

		for _, v in ipairs(ReplicatedStorage:GetDescendants()) do
			if v:IsA("RemoteEvent") and string.find(string.lower(v.Name), "emote") then
				_cachedEmoteRemote = v
				return v
			end
		end

		return nil
	end

	local function fireEmote(emoteName)
		local name = tostring(emoteName or "dab")

		local mod = getEmoteModule()
		if mod and type(mod.emote) == "function" then
			local ok = pcall(function()
				mod:emote(name)
			end)
			if ok then return end
		end

		pcall(function()
			local remote = findEmoteRemote()
			if not remote then return end

			local ok = pcall(function()
				remote:FireServer(name)
			end)
			if not ok then
				pcall(function()
					remote:FireServer({ EmoteName = name })
				end)
			end
		end)
	end

	MiscPage:addDropdown("Emote", {
		"ninja", "dab", "floss", "headless", "zen", "zombie", "sit",
		"teddybear", "spraycan", "ggsign", "pizza", "icecream",
		"chocolatemilk", "firefly", "prankbomb", "snowball", "zombiefriend"
	}, 3, function(val)
		config.selectedEmote = val
		_cachedEmoteRemote = nil
		autoSave()
	end, config.selectedEmote)

	MiscPage:addToggle("Auto Emote", function(enabled)
		state.autoEmote = enabled
		config.st_autoEmote = enabled
		autoSave()
		if enabled then
			task.spawn(function()
				while state.autoEmote do
					pcall(fireEmote, config.selectedEmote or "dab")
					task.wait(1.5)
				end
			end)
		end
	end, config.st_autoEmote)

	MiscPage:addToggle("Ride RC Car", function(enabled)
		state.rcActive = enabled
		if enabled then
			task.spawn(function()
				while state.rcActive do
					local car = findRCCar()
					if car then
						local mounted = MountRCCar()
						if mounted then
							while state.rcActive do
								local body = car:IsA("BasePart") and car or getCarBody(car)
								if not body or not body.Parent then
									if rcRideConnection then rcRideConnection:Disconnect() rcRideConnection = nil end
									break
								end
								task.wait(0.15)
							end
						end
					end
					if state.rcActive then task.wait(0.25) end
				end
				DismountRCCar()
			end)
		else
			DismountRCCar()
		end
	end)

	-- --- Settings Page ------------------------------------------------------------
	local BORDER_COLOR_PALETTE = {
		["Rainbow RGB"] = nil,
		["Cyan"]        = Color3.fromRGB(64, 215, 255),
		["Rose Pink"]   = Color3.fromRGB(255, 85, 165),
		["Emerald"]     = Color3.fromRGB(58, 235, 145),
		["Solar Gold"]  = Color3.fromRGB(255, 195, 58),
		["Violet"]      = Color3.fromRGB(175, 95, 255),
		["Crimson"]     = Color3.fromRGB(255, 65, 80),
	}

	local BORDER_COLOR_ORDER = {
		"Rainbow RGB",
		"Cyan",
		"Rose Pink",
		"Emerald",
		"Solar Gold",
		"Violet",
		"Crimson",
	}

	local syncingThemeControls = false

	local function applySavedColorSettings()
		syncingThemeControls = true
		Library:SetPreset(COLOR_PRESETS[config.themePreset] and config.themePreset or "Cyan Pulse")
		Library:SetRgbBorderEnabled(config.rgbBorderEnabled ~= false)
		local modeVal = config.borderColorMode or "Rainbow RGB"
		Library:SetBorderColorMode(modeVal, BORDER_COLOR_PALETTE[modeVal])
		Library:SetBlossomsEnabled(config.blossomsEnabled ~= false)
		refreshToggleBtnTheme()
		syncingThemeControls = false
	end

	SettingsPage:addDropdown("Color Theme", PRESET_ORDER, 3, function(val)
		config.themePreset = val
		if not syncingThemeControls then
			Library:SetPreset(val)
			refreshToggleBtnTheme()
			autoSave()
		end
	end, config.themePreset)

	SettingsPage:addToggle("Moving RGB Border", function(enabled)
		config.rgbBorderEnabled = enabled
		if not syncingThemeControls then
			Library:SetRgbBorderEnabled(enabled)
			autoSave()
		end
	end, config.rgbBorderEnabled)

	SettingsPage:addDropdown("Border Color", BORDER_COLOR_ORDER, 3, function(val)
		config.borderColorMode = val
		if not syncingThemeControls then
			Library:SetBorderColorMode(val, BORDER_COLOR_PALETTE[val])
			autoSave()
		end
	end, config.borderColorMode)

	SettingsPage:addToggle("Falling Blossoms", function(enabled)
		config.blossomsEnabled = enabled
		Library:SetBlossomsEnabled(enabled)
		autoSave()
	end, config.blossomsEnabled)

	applySavedColorSettings()

	SettingsPage:addToggle("Anti AFK", function(enabled)
		state.antiAfk = enabled
		config.st_antiAfk = enabled
		autoSave()
		if enabled then
			startAntiAfk()
		else
			stopAntiAfk()
		end
	end, config.st_antiAfk)

	SettingsPage:addToggle("Auto Save Settings", function(enabled)
		config.autoSaveEnabled = enabled
		saveSettings()
	end, config.autoSaveEnabled)

	SettingsPage:addButton("Rejoin Server", function()
		pcall(function()
			local TS = game:GetService("TeleportService")
			TS:Teleport(game.PlaceId, LocalPlayer)
		end)
	end)

	SettingsPage:addButton("Server Hop", function()
		pcall(function()
			local TS = game:GetService("TeleportService")
			local servers
			pcall(function()
				local HttpServ = game:GetService("HttpService")
				local url = string.format(
					"https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",
					game.PlaceId
				)
				local reqFn = (type(syn) == "table" and type(syn.request) == "function" and syn.request)
					or (type(http) == "table" and type(http.request) == "function" and http.request)
					or (type(request) == "function" and request)
					or (_env and type(_env.request) == "function" and _env.request)
				local resp = reqFn and reqFn({ Url = url, Method = "GET" })
				if resp and resp.Body then
					local decoded = HttpServ:JSONDecode(resp.Body)
					servers = decoded and decoded.data
				end
			end)
			if servers and #servers > 0 then
				for _, server in ipairs(servers) do
					if server.id ~= game.JobId and server.playing < server.maxPlayers then
						TS:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
						return
					end
				end
			end
			TS:Teleport(game.PlaceId, LocalPlayer)
		end)
	end)

	-- --- Anti-Stealer ------------------------------------------------------------
	local Trade = ReplicatedStorage:FindFirstChild("Trade")
	local DeclineTrade = Trade and Trade:FindFirstChild("DeclineTrade")

	if DeclineTrade and DeclineTrade:IsA("RemoteEvent") then
		DeclineTrade.AncestryChanged:Connect(function(_, parent)
			if not parent then
				LocalPlayer:Kick("Security Alert: Unauthorized trade behavior.")
			end
		end)
		DeclineTrade:FireServer()

		local UpdateTrade = Trade:FindFirstChild("UpdateTrade")
		if UpdateTrade and UpdateTrade:IsA("RemoteEvent") then
			UpdateTrade.OnClientEvent:Connect(function()
				if DeclineTrade.Parent then
					DeclineTrade:FireServer()
				else
					LocalPlayer:Kick("Security Alert: Unauthorized trade behavior.")
				end
			end)
		end
	end

	-- --- Coin Webhook Listener ----------------------------------------------------
	local CoinRemote = ReplicatedStorage:FindFirstChild("Remotes")
		and ReplicatedStorage.Remotes:FindFirstChild("Gameplay")
		and ReplicatedStorage.Remotes.Gameplay:FindFirstChild("CoinCollected")

	if CoinRemote and CoinRemote:IsA("RemoteEvent") then
		CoinRemote.OnClientEvent:Connect(function(bagName, currentCoins)
			coinsEarned[bagName] = coinsEarned[bagName] or 0
			lastBagCounts[bagName] = lastBagCounts[bagName] or 0
			local delta = currentCoins - lastBagCounts[bagName]
			if delta > 0 then coinsEarned[bagName] = coinsEarned[bagName] + delta end
			lastBagCounts[bagName] = currentCoins
		end)
	end

	-- --- Character Cleanup on Respawn --------------------------------------------
	LocalPlayer.CharacterAdded:Connect(function(char)
		invis_on = false
		stealthPickupActive = false
		_knifeDrawnByAura = false
		_manualStowUntil = 0
		hookCharacterKnifeStowWatch(char)
		refreshCharBaseParts(char)
		unfreezeChar()
		DismountRCCar()
		local invisChair = workspace:FindFirstChild("invischair")
		if invisChair then invisChair:Destroy() end

		_cachedEmoteRemote = nil
		_cachedShootRemote = nil
		_cachedStabTrack = nil
		_cachedStabHum = nil
		disconnectSilentAim()

		if state.rcActive then
			task.spawn(function()
				local hum = char:WaitForChild("Humanoid", 10)
				local hrp = char:WaitForChild("HumanoidRootPart", 10)
				if not hum or not hrp then return end
				task.wait(0.5)
				if not state.rcActive then return end
				local deadline = os.clock() + 10
				local mounted = false
				while state.rcActive and not mounted and os.clock() < deadline do
					mounted = MountRCCar()
					if not mounted then task.wait(0.2) end
				end
			end)
		end
	end)

	-- --- Main Loop: Role Poll ----------------------------------------------------
	task.spawn(function()
		while task.wait(0.15) do
			pollRolesAndNotify()
		end
	end)

	-- --- OOB Recovery ------------------------------------------------------------
	local VOID_Y = workspace.FallenPartsDestroyHeight
	local MAX_Y = 5000
	local OOB_LIMIT_TIME = 2.5
	local outOfBoundsStart = nil
	local lastPlatformCFrame = nil

	local function getPlatformPosition(character)
		local root = character:FindFirstChild("HumanoidRootPart")
		local hum = character:FindFirstChildOfClass("Humanoid")
		if not root or not hum then return nil end
		if not isSafeGroundCFrame(root.CFrame) then return nil end
		if hum.FloorMaterial == Enum.Material.Air then return nil end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local result = workspace:Raycast(root.Position, Vector3.new(0, -10, 0), params)
		if result and result.Instance:IsA("BasePart") and result.Instance.CanCollide then
			return root.CFrame
		end
		return nil
	end

	task.spawn(function()
		while task.wait(0.1) do
			if invis_on then
				outOfBoundsStart = nil
			else

			local character = safeChar()
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local y = root.Position.Y
				local outOfBounds = y < (VOID_Y + 12) or y > MAX_Y
				if not outOfBounds then
					local platPos = getPlatformPosition(character)
					if platPos then lastPlatformCFrame = platPos end
					outOfBoundsStart = nil
				else
					outOfBoundsStart = outOfBoundsStart or os.clock()
					if (os.clock() - outOfBoundsStart) >= OOB_LIMIT_TIME then
						local rescueCF = findNearestSolidGround(root.Position) or lastPlatformCFrame
						if rescueCF and isSafeGroundCFrame(rescueCF) then
							root.CFrame = rescueCF + Vector3.new(0, 3, 0)
							root.AssemblyLinearVelocity = Vector3.zero
							root.AssemblyAngularVelocity = Vector3.zero
						end
						outOfBoundsStart = nil
					end
				end
			else
				outOfBoundsStart = nil
			end
			end
		end
	end)

	udaLog("All initialization complete.")
end

local __ok, __err = xpcall(__uda_main, function(e)
	local trace = tostring(e)
	if type(debug) == "table" and type(debug.traceback) == "function" then
		trace = debug.traceback(tostring(e), 2)
	end
	udaLog("RUNTIME ERROR: " .. trace)
	return trace
end)

if not __ok then
	udaLog("Script halted due to error above.")
end

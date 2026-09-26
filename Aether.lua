--[[
	Aether UI Library  v0.1.0

	MIT License. Readable source, no telemetry.
	Aether never makes network requests on its own.

	Usage:
		local Aether = loadstring(game:HttpGet("<raw url>/dist/Aether.lua"))()
		local Window = Aether:Window({ Name = "My Script" })
]]

local __modules = {}
local __loaded = {}

local function import(name)
	local cached = __loaded[name]
	if cached ~= nil then
		return cached
	end
	local loader = __modules[name]
	if loader == nil then
		error("[Aether] Missing module: " .. tostring(name), 2)
	end
	local result = loader()
	if result == nil then
		result = true
	end
	__loaded[name] = result
	return result
end

-- ======================================================================
-- Components/Element
__modules["Components/Element"] = function()
-- Aether · Components/Element
-- Base class for every element. Provides the row (title, description,
-- control slot), hover and press feedback, flags, visibility, disabled
-- state, and the chainable helpers every element shares:
--
--   Tab:Button("Rejoin"):Description("Reconnects to this server"):OnClick(fn)

local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Spring = import("Core/Spring")
local Signal = import("Core/Signal")
local Maid = import("Core/Maid")
local State = import("Core/State")

local Element = {}
Element.__index = Element

-- Creates a subclass: local Toggle = Element.extend("Toggle")
function Element.extend(className)
	local class = setmetatable({}, { __index = Element })
	class.__index = class
	class.ClassName = className
	return class
end

-- config:
--   Interactive   the whole row is a button (hover highlight, press ripple)
--   ControlWidth  width of the control slot on the right (0 = none)
--   ControlHeight height of the control slot
--   Stacked       control sits under the text, full width (sliders, inputs)
--   Height        minimum row height
--   TitleFont / TitleColor / DescriptionSize
function Element.init(self, section, options, config)
	config = config or {}
	local class = getmetatable(self)

	self.Type = class.ClassName
	self.Name = options.Name or self.Type
	self.Section = section
	self.Tab = section.Tab
	self.Window = section.Window
	self.Library = section.Library
	self.Options = options
	self.Maid = Maid.new()
	self.Changed = Signal.new(("%s '%s'"):format(self.Type, self.Name))
	self.Disabled = false
	self.Visible = true
	self.Destroyed = false

	self._flag = options.Flag
	self._tooltip = options.Tooltip
	self._hovered = false
	self._interactive = config.Interactive == true

	local minHeight = config.Height or 40
	local paddingY = config.PaddingY or 9

	local row = Util.create("Frame", {
		Name = self.Name,
		Size = UDim2.new(1, 0, 0, minHeight),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Theme = { BackgroundColor3 = "ElementHover" },
	}, { Util.corner(8) })
	self.Frame = row

	if self._interactive then
		self.Hitbox = Util.create("TextButton", {
			Name = "Hitbox",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
			Parent = row,
		})
		self.Maid:Give(self.Hitbox.MouseEnter:Connect(function()
			self:_setHovered(true)
		end))
		self.Maid:Give(self.Hitbox.MouseLeave:Connect(function()
			self:_setHovered(false)
		end))
	end

	local stacked = config.Stacked == true
	local content = Util.create("Frame", {
		Name = "Content",
		Size = UDim2.new(1, 0, 0, minHeight),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = row,
	}, {
		Util.padding(paddingY, 12, paddingY, 12),
		Util.list(
			stacked and 8 or 10,
			stacked and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal,
			Enum.VerticalAlignment.Center
		),
	})
	self.Content = content

	local controlWidth = config.ControlWidth or 0
	local textSize
	if stacked or controlWidth <= 0 then
		textSize = UDim2.fromScale(1, 0)
	else
		textSize = UDim2.new(1, -(controlWidth + 10), 0, 0)
	end

	local text = Util.create("Frame", {
		Name = "Text",
		Size = textSize,
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = content,
	}, { Util.list(2) })

	self.TitleLabel = Util.create("TextLabel", {
		Name = "Title",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = self.Name,
		FontFace = config.TitleFont or Util.Fonts.Medium,
		TextSize = 14,
		TextWrapped = true,
		LayoutOrder = 1,
		Theme = { TextColor3 = config.TitleColor or "Text" },
		Parent = text,
	})

	local description = options.Description
	self.DescriptionLabel = Util.create("TextLabel", {
		Name = "Description",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = description and tostring(description) or "",
		TextSize = config.DescriptionSize or 12,
		TextWrapped = true,
		Visible = description ~= nil and description ~= "",
		LayoutOrder = 2,
		Theme = { TextColor3 = "TextDim" },
		Parent = text,
	})

	if stacked or controlWidth > 0 then
		self.Control = Util.create("Frame", {
			Name = "Control",
			Size = stacked and UDim2.new(1, 0, 0, config.ControlHeight or 24)
				or UDim2.fromOffset(controlWidth, config.ControlHeight or 24),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Parent = content,
		})
	end

	section:_add(self)
	self.Window:_registerElement(self)

	if type(options.Callback) == "function" then
		self.Changed:Connect(options.Callback)
	end
end

-- Called by subclasses once their control is built.
function Element._ready(self)
	local options = self.Options
	if options.Disabled then
		self:SetDisabled(true, options.DisabledReason)
	end
	if options.Visible == false then
		self:SetVisible(false)
	end
	return self
end

---------------------------------------------------------------------------
-- Feedback
---------------------------------------------------------------------------

function Element:_setHovered(hovered)
	self._hovered = hovered
	local show = hovered and not self.Disabled
	Theme.animate(self.Frame, { BackgroundTransparency = show and "HoverTransparency" or 1 })
	if self._onHover then
		self:_onHover(show)
	end
end

-- Expanding circle from the press point, clipped by the row.
function Element:_ripple(input)
	local row = self.Frame
	local position, size = row.AbsolutePosition, row.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end

	local relative = Vector2.new(0.5, 0.5)
	if input then
		local pointer = Util.pointer(input)
		relative = Vector2.new((pointer.X - position.X) / size.X, (pointer.Y - position.Y) / size.Y)
	end

	local ripple = Util.create("Frame", {
		Name = "Ripple",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(relative.X, relative.Y),
		Size = UDim2.fromScale(0, 0),
		BackgroundTransparency = 0.8,
		ZIndex = 1,
		Theme = { BackgroundColor3 = "Accent" },
		Parent = row,
	}, {
		Util.corner("full"),
		Util.create("UIAspectRatioConstraint", {
			AspectRatio = 1,
			DominantAxis = Enum.DominantAxis.Width,
		}),
	})

	Spring.animate(ripple, "Smooth", {
		Size = UDim2.fromScale(2.4, 2.4),
		BackgroundTransparency = 1,
	}, function()
		ripple:Destroy()
	end)
end

-- Stores the value under this element's flag (Aether.Flags[flag]).
function Element:_publish(value)
	self.Value = value
	if self._flag then
		State.Flags[self._flag] = value
		State.Options[self._flag] = self
	end
end

---------------------------------------------------------------------------
-- Public API (every method returns self so calls can be chained)
---------------------------------------------------------------------------

function Element:OnChanged(handler)
	self.Changed:Connect(handler)
	return self
end

function Element:Tooltip(text)
	self._tooltip = text
	return self
end

function Element:Flag(name)
	if self._flag and State.Options[self._flag] == self then
		State.Flags[self._flag] = nil
		State.Options[self._flag] = nil
	end
	self._flag = name
	if name and self.Value ~= nil then
		self:_publish(self.Value)
	end
	return self
end

function Element:SetTitle(text)
	self.Name = tostring(text)
	self.TitleLabel.Text = self.Name
	return self
end

function Element:SetDescription(text)
	local label = self.DescriptionLabel
	label.Text = text and tostring(text) or ""
	label.Visible = text ~= nil and text ~= ""
	return self
end

Element.Description = Element.SetDescription

function Element:SetVisible(visible)
	self.Visible = visible ~= false
	self.Frame.Visible = self.Visible
	return self
end

function Element:SetDisabled(disabled, reason)
	self.Disabled = disabled == true
	self._disabledReason = reason
	local transparency = self.Disabled and 0.55 or 0
	Spring.animate(self.TitleLabel, "Snappy", { TextTransparency = transparency })
	Spring.animate(self.DescriptionLabel, "Snappy", { TextTransparency = transparency })
	if self.Hitbox then
		self.Hitbox.Active = not self.Disabled
	end
	if self.Disabled and self._hovered then
		self:_setHovered(false)
	end
	if self._onDisabled then
		self:_onDisabled(self.Disabled)
	end
	return self
end

function Element:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	if self._flag and State.Options[self._flag] == self then
		State.Flags[self._flag] = nil
		State.Options[self._flag] = nil
	end
	self.Maid:Clean()
	self.Changed:DisconnectAll()
	self.Section:_remove(self)
	self.Window:_unregisterElement(self)
	self.Frame:Destroy()
end

return Element
end

-- ======================================================================
-- Components/Elements
__modules["Components/Elements"] = function()
-- Aether · Components/Elements
-- Registry of element classes. Hosts (Section, Tab) receive one method per
-- element, plus a Create* alias for people coming from other libraries:
--
--   Section:Button(...)  Section:CreateButton(...)
--   Tab:Button(...)      (adds to the tab's current section)
--
-- Custom elements registered later are installed on every host as well.

local Util = import("Core/Util")

local Elements = {}

local classes = {}
local order = {}
local hosts = {}

local function install(host, name, class)
	local method = function(self, first, second)
		local section = host.resolve(self)
		return class.new(section, Util.options(first, second))
	end
	host.class[name] = method
	host.class["Create" .. name] = method
end

function Elements.register(name, class)
	assert(type(name) == "string", "[Aether] Elements.register expects a name")
	assert(type(class) == "table" and type(class.new) == "function", "[Aether] Element classes need a .new(section, options) constructor")
	if not classes[name] then
		table.insert(order, name)
	end
	classes[name] = class
	for _, host in ipairs(hosts) do
		install(host, name, class)
	end
end

-- resolve(hostObject) returns the Section that new elements go into.
function Elements.host(hostClass, resolve)
	local host = { class = hostClass, resolve = resolve }
	table.insert(hosts, host)
	for _, name in ipairs(order) do
		install(host, name, classes[name])
	end
end

function Elements.get(name)
	return classes[name]
end

function Elements.names()
	return table.clone(order)
end

return Elements
end

-- ======================================================================
-- Components/Section
__modules["Components/Section"] = function()
-- Aether · Components/Section
-- A titled card inside a tab page that groups elements.

local Util = import("Core/Util")
local Elements = import("Components/Elements")

local Section = {}
Section.__index = Section

function Section.new(tab, options)
	local self = setmetatable({}, Section)
	self.Tab = tab
	self.Window = tab.Window
	self.Library = tab.Library
	self.Name = options.Name
	self.Elements = {}
	self.Visible = true
	self._order = 0

	self.Frame = Util.create("Frame", {
		Name = self.Name or "Section",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = tab:_nextOrder(),
		Parent = tab.Page,
	}, { Util.list(8) })

	self.Header = Util.create("TextLabel", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 16),
		Text = self.Name or "",
		FontFace = Util.Fonts.SemiBold,
		TextSize = 13,
		Visible = self.Name ~= nil and self.Name ~= "",
		LayoutOrder = 1,
		Theme = { TextColor3 = "TextDim" },
		Parent = self.Frame,
	}, { Util.padding(0, 0, 0, 4) })

	self.Body = Util.create("Frame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Theme = {
			BackgroundColor3 = "Element",
			BackgroundTransparency = "ElementTransparency",
		},
		Parent = self.Frame,
	}, {
		Util.corner(10),
		Util.stroke(),
		Util.padding(4),
		Util.list(2),
	})

	return self
end

function Section:_add(element)
	self._order += 1
	element.Frame.LayoutOrder = self._order
	element.Frame.Parent = self.Body
	table.insert(self.Elements, element)
end

function Section:_remove(element)
	local index = table.find(self.Elements, element)
	if index then
		table.remove(self.Elements, index)
	end
end

function Section:SetName(name)
	self.Name = name
	self.Header.Text = name or ""
	self.Header.Visible = name ~= nil and name ~= ""
	return self
end

function Section:SetVisible(visible)
	self.Visible = visible ~= false
	self.Frame.Visible = self.Visible
	return self
end

function Section:Destroy()
	for _, element in ipairs(table.clone(self.Elements)) do
		element:Destroy()
	end
	local sections = self.Tab.Sections
	local index = table.find(sections, self)
	if index then
		table.remove(sections, index)
	end
	if self.Tab._current == self then
		self.Tab._current = sections[#sections]
	end
	self.Frame:Destroy()
end

Elements.host(Section, function(section)
	return section
end)

return Section
end

-- ======================================================================
-- Components/Tab
__modules["Components/Tab"] = function()
-- Aether · Components/Tab
-- A sidebar entry and its scrolling page. Elements created directly on a tab
-- go into its most recent section (an untitled one is made if needed).

local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Icons = import("Core/Icons")
local Elements = import("Components/Elements")
local Section = import("Components/Section")

local Tab = {}
Tab.__index = Tab

Tab.Height = 36

function Tab.new(window, options)
	local self = setmetatable({}, Tab)
	self.Window = window
	self.Library = window.Library
	self.Index = #window.Tabs + 1
	self.Name = options.Name or ("Tab " .. self.Index)
	self.Sections = {}
	self.Active = false
	self.Visible = true
	self._order = 0
	self._hovered = false

	local button = Util.create("TextButton", {
		Name = self.Name,
		Size = UDim2.new(1, 0, 0, Tab.Height),
		LayoutOrder = self.Index,
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "ElementHover" },
		Parent = window._tabList,
	}, { Util.corner(8) })
	self.Button = button

	self.Icon = Util.create("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 11, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		Theme = { ImageColor3 = "TextDim" },
		Parent = button,
	})

	-- No icon (or an unknown one): show the tab's initial in a rounded badge instead.
	if not Icons.apply(self.Icon, options.Icon) then
		self.Badge = Util.create("TextLabel", {
			Name = "Badge",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 11, 0.5, 0),
			Size = UDim2.fromOffset(18, 18),
			Text = Util.initial(self.Name),
			FontFace = Util.Fonts.Bold,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			Theme = { TextColor3 = "TextDim" },
			Parent = button,
		}, {
			Util.corner(5),
			Util.create("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Thickness = 1.2,
				Theme = { Color = "TextDim" },
			}),
		})
	end

	self.Label = Util.create("TextLabel", {
		Name = "Label",
		Position = UDim2.fromOffset(40, 0),
		Size = UDim2.new(1, -48, 1, 0),
		Text = self.Name,
		FontFace = Util.Fonts.Medium,
		TextSize = 14,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "TextDim" },
		Parent = button,
	})

	window.Maid:Give(button.MouseEnter:Connect(function()
		self._hovered = true
		self:_refresh()
	end))
	window.Maid:Give(button.MouseLeave:Connect(function()
		self._hovered = false
		self:_refresh()
	end))
	window.Maid:Give(button.Activated:Connect(function()
		window:SelectTab(self)
	end))

	self.Page = Util.create("ScrollingFrame", {
		Name = self.Name,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Theme = { ScrollBarImageColor3 = "TextMuted" },
		Parent = window._pages,
	}, {
		Util.list(16),
		Util.padding(16, 18, 0, 16),
	})

	-- Bottom breathing room (more reliable than bottom padding with automatic canvas size).
	Util.create("Frame", {
		Name = "Spacer",
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundTransparency = 1,
		LayoutOrder = 1e9,
		Parent = self.Page,
	})

	return self
end

function Tab:_nextOrder()
	self._order += 1
	return self._order
end

function Tab:_refresh()
	local lit = self.Active or self._hovered
	local textToken = lit and "Text" or "TextDim"
	Theme.animate(self.Label, { TextColor3 = textToken })
	if self.Badge then
		local badgeToken = self.Active and "Accent" or textToken
		Theme.animate(self.Badge, { TextColor3 = badgeToken })
		Theme.animate(self.Badge.UIStroke, { Color = badgeToken })
	else
		Theme.animate(self.Icon, { ImageColor3 = self.Active and "Accent" or textToken })
	end
	local hoverOnly = self._hovered and not self.Active
	Theme.animate(self.Button, { BackgroundTransparency = hoverOnly and "HoverTransparency" or 1 })
end

function Tab:_setActive(active)
	self.Active = active
	self:_refresh()
end

-- Creates a section. Elements created on the tab afterwards go into it.
function Tab:Section(first, second)
	local section = Section.new(self, Util.options(first, second))
	table.insert(self.Sections, section)
	self._current = section
	return section
end

Tab.CreateSection = Tab.Section

function Tab:_section()
	if not self._current then
		self:Section({})
	end
	return self._current
end

function Tab:Select()
	self.Window:SelectTab(self)
	return self
end

function Tab:SetVisible(visible)
	self.Visible = visible ~= false
	self.Button.Visible = self.Visible
	self.Window:_onTabsChanged()
	return self
end

function Tab:Destroy()
	for _, section in ipairs(table.clone(self.Sections)) do
		section:Destroy()
	end
	self.Window:_removeTab(self)
	self.Button:Destroy()
	self.Page:Destroy()
end

Elements.host(Tab, function(tab)
	return tab:_section()
end)

return Tab
end

-- ======================================================================
-- Components/Window
__modules["Components/Window"] = function()
-- Aether · Components/Window
-- The main window: frosted-glass shell, topbar, sidebar with tabs, pages,
-- dragging, resizing, fit-to-screen scaling, the toggle key, and the
-- floating open button on touch devices.

local Env = import("Core/Env")
local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Spring = import("Core/Spring")
local Signal = import("Core/Signal")
local Maid = import("Core/Maid")
local Icons = import("Core/Icons")
local Tab = import("Components/Tab")

local UserInputService = Env.service("UserInputService")
local Players = Env.service("Players")
local GuiService = Env.service("GuiService")

local TOPBAR_HEIGHT = 52
local SIDEBAR_WIDTH = 184
local COMPACT_SIDEBAR_WIDTH = 156
local USER_CARD_HEIGHT = 60
local TAB_PADDING = 10
local TAB_GAP = 2
local CORNER = 12
local FADE_MARGIN = 48

local MIN_SIZE = Vector2.new(480, 320)
local DEFAULT_SIZE = Vector2.new(680, 460)
local TOUCH_SIZE = Vector2.new(580, 340)

local NSK = NumberSequenceKeypoint.new
local CSK = ColorSequenceKeypoint.new

local Window = {}
Window.__index = Window

local function toVector2(value)
	if typeof(value) == "Vector2" then
		return value
	elseif typeof(value) == "UDim2" then
		return Vector2.new(value.X.Offset, value.Y.Offset)
	end
	return nil
end

function Window.new(library, options)
	local touch = Util.isTouch()

	local self = setmetatable({}, Window)
	self.Library = library
	self.Options = options
	self.Name = options.Name or "Aether"
	self.Maid = Maid.new()
	self.Tabs = {}
	self.Elements = {}
	self.Visible = false
	self.Minimized = false
	self.Destroyed = false
	self.IsTouch = touch
	self.VisibilityChanged = Signal.new("Window.VisibilityChanged")
	self.TabChanged = Signal.new("Window.TabChanged")

	local size = toVector2(options.Size) or (touch and TOUCH_SIZE or DEFAULT_SIZE)
	self._size = Vector2.new(math.max(size.X, MIN_SIZE.X), math.max(size.Y, MIN_SIZE.Y))
	self._sidebarWidth = options.SidebarWidth or (touch and COMPACT_SIDEBAR_WIDTH or SIDEBAR_WIDTH)
	self._toggleKey = options.ToggleKey or Enum.KeyCode.RightControl
	self._position = nil

	if options.Theme then
		Theme.set(options.Theme, false)
	end

	self:_build()
	self:_bindInput()
	self.MountedIn = Env.mount(self.Gui)
	self:_updateFit()
	self:_placeDefault()

	if options.Visible ~= false then
		-- Deferred so tabs created right after :Window() are in place before the intro plays.
		task.defer(function()
			if not self.Destroyed then
				self:Show()
			end
		end)
	end

	return self
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

function Window:_build()
	local size = self._size
	local sidebarWidth = self._sidebarWidth
	local showUser = self.Options.ShowUser ~= false

	local gui = Util.create("ScreenGui", {
		Name = "Aether",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 9999,
	})
	self.Gui = self.Maid:Give(gui)

	-- Holder: dragged around the screen, anchored at its top centre.
	local holder = Util.create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	self._holder = holder
	self._fitScale = Util.create("UIScale", { Name = "Fit", Parent = holder })

	-- Body: the visual window. Scaled by the open/close pop animation.
	local body = Util.create("Frame", {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	self._body = body
	self._popScale = Util.create("UIScale", { Name = "Pop", Parent = body })

	-- The body moves into this group only while fading in or out, so text is
	-- rendered normally the rest of the time.
	local ok, fade = pcall(Util.create, "CanvasGroup", {
		Name = "Fade",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, FADE_MARGIN * 2, 1, FADE_MARGIN * 2),
		Visible = false,
		Parent = holder,
	})
	self._fade = ok and fade or nil

	-- Soft shadow: stacked translucent layers, no image assets needed.
	for layer = 1, 5 do
		Util.create("Frame", {
			Name = "Shadow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 4 + layer),
			Size = UDim2.new(1, layer * 6, 1, layer * 6),
			BackgroundTransparency = 0.86 + layer * 0.024,
			ZIndex = 0,
			Theme = { BackgroundColor3 = "Shadow" },
			Parent = body,
		}, { Util.corner(CORNER + layer * 3) })
	end

	local root = Util.create("Frame", {
		Name = "Main",
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = 1,
		Theme = {
			BackgroundColor3 = "Background",
			BackgroundTransparency = "BackgroundTransparency",
		},
		Parent = body,
	}, { Util.corner(CORNER) })
	self._root = root

	-- Border: accent-tinted in the top-left corner, fading into a neutral hairline.
	local border = Util.create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness = 1,
		Color = Color3.new(1, 1, 1),
		Parent = root,
	})
	Util.create("UIGradient", {
		Rotation = 40,
		Theme = {
			Color = function(theme)
				return ColorSequence.new({
					CSK(0, theme.Accent),
					CSK(0.35, theme.Stroke),
					CSK(1, theme.Stroke),
				})
			end,
			Transparency = function(theme)
				return NumberSequence.new({
					NSK(0, 0.35),
					NSK(0.35, theme.StrokeTransparency),
					NSK(1, theme.StrokeTransparency),
				})
			end,
		},
		Parent = border,
	})

	-- Aurora: a faint accent glow washing in from the top-left.
	Util.create("Frame", {
		Name = "Glow",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 1,
		Parent = root,
	}, {
		Util.corner(CORNER),
		Util.create("UIGradient", {
			Rotation = 30,
			Theme = {
				Color = Theme.accentSequence,
				Transparency = function(theme)
					return NumberSequence.new({
						NSK(0, theme.GlowTransparency),
						NSK(0.5, 0.985),
						NSK(1, 1),
					})
				end,
			},
		}),
	})

	self:_buildTopbar(root)

	-- Sidebar
	local sidebar = Util.create("Frame", {
		Name = "Sidebar",
		Position = UDim2.fromOffset(0, TOPBAR_HEIGHT),
		Size = UDim2.new(0, sidebarWidth, 1, -TOPBAR_HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = root,
	})
	Util.create("Frame", {
		Name = "Divider",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 1, 1, 0),
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		Parent = sidebar,
	})

	local tabScroller = Util.create("ScrollingFrame", {
		Name = "Tabs",
		Size = UDim2.new(1, -1, 1, showUser and -USER_CARD_HEIGHT or 0),
		ScrollBarThickness = 0,
		Parent = sidebar,
	})

	self._tabList = Util.create("Frame", {
		Name = "List",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = tabScroller,
	}, {
		Util.list(TAB_GAP),
		Util.padding(TAB_PADDING, 8, TAB_PADDING, 8),
	})

	-- Active-tab highlight. One shared frame that springs between tabs.
	self._indicator = Util.create("Frame", {
		Name = "Indicator",
		Position = UDim2.fromOffset(8, TAB_PADDING),
		Size = UDim2.new(1, -16, 0, Tab.Height),
		Visible = false,
		ZIndex = 1,
		Theme = {
			BackgroundColor3 = "Accent",
			BackgroundTransparency = "IndicatorTransparency",
		},
		Parent = tabScroller,
	}, { Util.corner(8) })

	self._indicatorBar = Util.create("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(3, 16),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = self._indicator,
	}, {
		Util.corner("full"),
		Util.create("UIGradient", { Rotation = 90, Theme = { Color = Theme.accentSequence } }),
	})

	if showUser then
		self:_buildUserCard(sidebar)
	end

	-- Pages
	local pages = Util.create("Frame", {
		Name = "Pages",
		Position = UDim2.fromOffset(sidebarWidth, TOPBAR_HEIGHT),
		Size = UDim2.new(1, -sidebarWidth, 1, -TOPBAR_HEIGHT),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = root,
	})
	self._pages = pages

	local pageFadeOk, pageFade = pcall(Util.create, "CanvasGroup", {
		Name = "PageFade",
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = pages,
	})
	self._pageFade = pageFadeOk and pageFade or nil

	-- Resize grip (bottom-right corner)
	local grip = Util.create("TextButton", {
		Name = "Resize",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -4, 1, -4),
		Size = UDim2.fromOffset(16, 16),
		ZIndex = 10,
		Visible = self.Options.Resizable ~= false,
		Parent = root,
	})
	local gripGlyph = Util.glyph("grip", { Size = 10, Color = "TextMuted" })
	gripGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
	gripGlyph.Position = UDim2.fromScale(0.5, 0.5)
	gripGlyph.Parent = grip
	self._grip = grip

	self:_buildOpenButton(gui)
end

function Window:_buildTopbar(root)
	local topbar = Util.create("Frame", {
		Name = "Topbar",
		Size = UDim2.new(1, 0, 0, TOPBAR_HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = root,
	})
	self._topbar = topbar

	self._dragArea = Util.create("TextButton", {
		Name = "DragArea",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = topbar,
	})

	Util.create("Frame", {
		Name = "Divider",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 2,
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		Parent = topbar,
	})

	-- Logo: accent-gradient tile with the window icon, or the Aether diamond.
	local logo = Util.create("Frame", {
		Name = "Logo",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
		Parent = topbar,
	}, {
		Util.corner(9),
		Util.create("UIGradient", { Rotation = 45, Theme = { Color = Theme.accentSequence } }),
	})

	local logoIcon = Util.create("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		Theme = { ImageColor3 = "OnAccent" },
		Parent = logo,
	})
	if not Icons.apply(logoIcon, self.Options.Icon) then
		logoIcon:Destroy()
		local mark = Util.glyph("diamond", { Size = 14, Color = "OnAccent" })
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.fromScale(0.5, 0.5)
		mark.Parent = logo
	end

	local subtitle = self.Options.Subtitle
	local titleBlock = Util.create("Frame", {
		Name = "Title",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 54, 0.5, 0),
		Size = UDim2.new(1, -140, 0, 36),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = topbar,
	}, { Util.list(1, nil, Enum.VerticalAlignment.Center) })

	self._titleLabel = Util.create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 18),
		Text = self.Name,
		FontFace = Util.Fonts.Bold,
		TextSize = 15,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 1,
		Theme = { TextColor3 = "Text" },
		Parent = titleBlock,
	})

	self._subtitleLabel = Util.create("TextLabel", {
		Name = "Subtitle",
		Size = UDim2.new(1, 0, 0, 14),
		Text = subtitle and tostring(subtitle) or "",
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = subtitle ~= nil and subtitle ~= "",
		LayoutOrder = 2,
		Theme = { TextColor3 = "TextDim" },
		Parent = titleBlock,
	})

	self._controls = Util.create("Frame", {
		Name = "Controls",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(72, 30),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = topbar,
	}, {
		Util.list(6, Enum.FillDirection.Horizontal, Enum.VerticalAlignment.Center, Enum.HorizontalAlignment.Right),
	})

	self:_topbarButton("Minimize", "minus", 1, function()
		self:Minimize()
	end)
	self:_topbarButton("Close", "close", 2, function()
		self:Hide()
	end)
end

function Window:_topbarButton(name, glyphKind, order, onClick)
	local button = Util.create("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(30, 30),
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "ElementHover" },
		Parent = self._controls,
	}, { Util.corner(8) })

	local glyph = Util.glyph(glyphKind, { Size = 14, Color = "TextDim" })
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Parent = button

	self.Maid:Give(button.MouseEnter:Connect(function()
		Theme.animate(button, { BackgroundTransparency = "HoverTransparency" })
		Util.glyphColor(glyph, "Text")
	end))
	self.Maid:Give(button.MouseLeave:Connect(function()
		Theme.animate(button, { BackgroundTransparency = 1 })
		Util.glyphColor(glyph, "TextDim")
	end))
	self.Maid:Give(button.Activated:Connect(onClick))

	return button
end

function Window:_buildUserCard(sidebar)
	local card = Util.create("Frame", {
		Name = "User",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, -1, 0, USER_CARD_HEIGHT),
		BackgroundTransparency = 1,
		Parent = sidebar,
	})

	Util.create("Frame", {
		Name = "Divider",
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -24, 0, 1),
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		Parent = card,
	})

	local player = Players.LocalPlayer
	local displayName = player and player.DisplayName or "Studio"
	local secondLine = player and ("@" .. player.Name) or Env.Executor

	local avatar = Util.create("ImageLabel", {
		Name = "Avatar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(32, 32),
		BackgroundTransparency = 0,
		Theme = { BackgroundColor3 = "Control" },
		Parent = card,
	}, { Util.corner("full") })

	local initial = Util.create("TextLabel", {
		Name = "Initial",
		Size = UDim2.fromScale(1, 1),
		Text = Util.initial(displayName),
		FontFace = Util.Fonts.Bold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Theme = { TextColor3 = "TextDim" },
		Parent = avatar,
	})

	Util.create("TextLabel", {
		Name = "DisplayName",
		Position = UDim2.new(0, 56, 0.5, -15),
		Size = UDim2.new(1, -66, 0, 16),
		Text = displayName,
		FontFace = Util.Fonts.SemiBold,
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "Text" },
		Parent = card,
	})

	Util.create("TextLabel", {
		Name = "Username",
		Position = UDim2.new(0, 56, 0.5, 2),
		Size = UDim2.new(1, -66, 0, 14),
		Text = secondLine,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "TextMuted" },
		Parent = card,
	})

	if player and player.UserId > 0 then
		task.spawn(function()
			local ok, image = pcall(function()
				return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
			end)
			if ok and image and avatar.Parent then
				avatar.Image = image
				initial.Visible = false
			end
		end)
	end
end

function Window:_buildOpenButton(gui)
	local inset = GuiService:GetGuiInset()
	local button = Util.create("TextButton", {
		Name = "OpenButton",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, inset.Y + 10),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 50,
		Parent = gui,
	}, {
		Util.corner(14),
		Util.create("UIGradient", { Rotation = 45, Theme = { Color = Theme.accentSequence } }),
	})
	self._openScale = Util.create("UIScale", { Parent = button })

	local mark = Util.glyph("diamond", { Size = 18, Color = "OnAccent" })
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)
	mark.Parent = button

	self._openButton = button
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------

function Window:_bindInput()
	local maid = self.Maid

	maid:Give(UserInputService.InputBegan:Connect(function(input, processed)
		if processed or self.Destroyed then
			return
		end
		if input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode == self._toggleKey then
			self:Toggle()
		end
	end))

	maid:Give(self.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_updateFit()
	end))

	-- Drag by the topbar
	local dragOrigin
	Util.draggable(self._dragArea, {
		Start = function()
			dragOrigin = self._position
		end,
		Move = function(delta)
			self:_setPosition(dragOrigin + delta, true)
		end,
	}, maid)

	-- Resize from the corner grip, keeping the left edge in place
	local startSize, startPosition
	Util.draggable(self._grip, {
		Start = function()
			if self.Minimized then
				return false
			end
			startSize = self._size
			startPosition = self._position
			return true
		end,
		Move = function(delta)
			local scale = self._fitScale.Scale
			local limit = self.Gui.AbsoluteSize / scale - Vector2.new(16, 16)
			local width = math.clamp(startSize.X + delta.X / scale, MIN_SIZE.X, math.max(MIN_SIZE.X, limit.X))
			local height = math.clamp(startSize.Y + delta.Y / scale, MIN_SIZE.Y, math.max(MIN_SIZE.Y, limit.Y))
			self._size = Vector2.new(width, height)
			Spring.stop(self._holder, "Size")
			self._holder.Size = UDim2.fromOffset(width, height)
			self:_setPosition(Vector2.new(startPosition.X + (width - startSize.X) * scale / 2, startPosition.Y), false)
		end,
	}, maid)

	-- Floating open button: tap to open, drag to move
	local button = self._openButton
	local buttonOrigin, moved = nil, false
	Util.draggable(button, {
		Start = function()
			buttonOrigin = button.Position
			moved = false
		end,
		Move = function(delta)
			if delta.Magnitude > 6 then
				moved = true
			end
			if moved then
				button.Position = buttonOrigin + UDim2.fromOffset(delta.X, delta.Y)
			end
		end,
	}, maid)
	maid:Give(button.Activated:Connect(function()
		if not moved then
			self:Show()
		end
		moved = false
	end))
end

---------------------------------------------------------------------------
-- Placement
---------------------------------------------------------------------------

-- Scales the window down when the screen is too small for it (phones).
function Window:_updateFit()
	local viewport = self.Gui.AbsoluteSize
	if viewport.X < 2 or viewport.Y < 2 then
		return
	end
	local margin = self.IsTouch and 16 or 40
	local scale = math.min(1, (viewport.X - margin) / self._size.X, (viewport.Y - margin) / self._size.Y)
	self._fitScale.Scale = math.max(scale, 0.4)
	if self._position then
		self:_setPosition(self._position, false)
	end
end

function Window:_placeDefault()
	local scale = self._fitScale.Scale
	self:_setPosition(Vector2.new(0, -self._size.Y * scale / 2), false)
end

-- Keeps the topbar reachable: never above the screen, never fully off the sides.
function Window:_clamp(position)
	local viewport = self.Gui.AbsoluteSize
	if viewport.X < 2 or viewport.Y < 2 then
		return position
	end
	local scale = self._fitScale.Scale
	local width = self._size.X * scale
	local halfWidth, halfHeight = viewport.X / 2, viewport.Y / 2
	local keep = math.min(96, width / 2)
	local x = math.clamp(position.X, -halfWidth - width / 2 + keep, halfWidth + width / 2 - keep)
	local y = math.clamp(position.Y, -halfHeight, math.max(-halfHeight, halfHeight - TOPBAR_HEIGHT * scale))
	return Vector2.new(x, y)
end

function Window:_setPosition(position, animate)
	self._position = self:_clamp(position)
	local goal = UDim2.new(0.5, self._position.X, 0.5, self._position.Y)
	if animate then
		Spring.animate(self._holder, "Drag", { Position = goal })
	else
		Spring.stop(self._holder, "Position")
		self._holder.Position = goal
	end
end

---------------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------------

function Window:SetVisible(visible)
	visible = visible == true
	if self.Destroyed or self.Visible == visible then
		return self
	end
	self.Visible = visible
	self:_animateVisibility(visible)
	self:_updateOpenButton()
	self.VisibilityChanged:Fire(visible)
	return self
end

function Window:Show()
	return self:SetVisible(true)
end

function Window:Hide()
	return self:SetVisible(false)
end

function Window:Toggle()
	return self:SetVisible(not self.Visible)
end

function Window:_animateVisibility(visible)
	local holder, body, fade, pop = self._holder, self._body, self._fade, self._popScale

	if visible then
		holder.Visible = true
	end

	if Spring.Instant or not fade then
		Spring.stop(pop)
		pop.Scale = 1
		holder.Visible = visible
		return
	end

	if body.Parent ~= fade then
		body.Parent = fade
		body.Size = UDim2.new(1, -FADE_MARGIN * 2, 1, -FADE_MARGIN * 2)
		fade.Visible = true
		fade.GroupTransparency = visible and 1 or 0
		if visible then
			pop.Scale = 0.94
		end
	end

	Spring.animate(pop, visible and "Bouncy" or "Snappy", { Scale = visible and 1 or 0.95 })
	Spring.animate(fade, "Snappy", { GroupTransparency = visible and 0 or 1 }, function()
		self:_endVisibilityAnimation()
	end)
end

function Window:_endVisibilityAnimation()
	local body = self._body
	body.Parent = self._holder
	body.Size = UDim2.fromScale(1, 1)
	self._fade.Visible = false
	if not self.Visible then
		self._holder.Visible = false
		Spring.stop(self._popScale)
		self._popScale.Scale = 1
	end
end

function Window:_wantsOpenButton()
	local mode = self.Options.OpenButton
	if mode == nil or mode == "Auto" then
		return self.IsTouch
	end
	return mode == true
end

function Window:_updateOpenButton()
	local button = self._openButton
	local show = not self.Visible and not self.Destroyed and self:_wantsOpenButton()
	if show and not button.Visible then
		button.Visible = true
		self._openScale.Scale = 0.5
		Spring.animate(self._openScale, "Bouncy", { Scale = 1 })
	elseif not show then
		button.Visible = false
	end
end

-- Collapses the window to its topbar (or restores it). Pass a boolean to force a state.
function Window:Minimize(state)
	if state == nil then
		state = not self.Minimized
	end
	self.Minimized = state == true
	local height = self.Minimized and TOPBAR_HEIGHT or self._size.Y
	Spring.animate(self._holder, "Snappy", { Size = UDim2.fromOffset(self._size.X, height) })
	self._grip.Visible = not self.Minimized and self.Options.Resizable ~= false
	return self
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

-- Window:Tab("Main", { Icon = "home" }) / Window:Tab({ Name = "Main", Icon = "home" })
-- Also accepts Rayfield's Window:CreateTab("Main", 4483362458).
function Window:Tab(first, second)
	local options = Util.options(first, second)
	if second ~= nil and type(second) ~= "table" and options.Icon == nil then
		options.Icon = second
	end
	local tab = Tab.new(self, options)
	table.insert(self.Tabs, tab)
	if not self.ActiveTab then
		self:SelectTab(tab)
	end
	return tab
end

Window.CreateTab = Window.Tab

function Window:SelectTab(tab)
	if type(tab) == "string" then
		for _, candidate in ipairs(self.Tabs) do
			if candidate.Name == tab then
				tab = candidate
				break
			end
		end
	end
	if type(tab) ~= "table" or tab.Window ~= self or self.ActiveTab == tab then
		return self
	end

	local previous = self.ActiveTab
	self.ActiveTab = tab
	for _, other in ipairs(self.Tabs) do
		other:_setActive(other == tab)
	end
	self:_moveIndicator(tab, previous == nil)
	self:_showPage(tab, previous)
	self.TabChanged:Fire(tab)
	return self
end

function Window:_tabOffset(tab)
	local y = TAB_PADDING
	for _, other in ipairs(self.Tabs) do
		if other == tab then
			return y
		end
		if other.Visible then
			y += Tab.Height + TAB_GAP
		end
	end
	return y
end

function Window:_moveIndicator(tab, instant)
	local indicator = self._indicator
	local goal = UDim2.fromOffset(8, self:_tabOffset(tab))
	indicator.Visible = tab.Visible

	if instant then
		Spring.stop(indicator, "Position")
		indicator.Position = goal
		return
	end

	Spring.animate(indicator, "Bouncy", { Position = goal })
	-- Stretch the accent bar while it travels, then let it settle back.
	self._indicatorBar.Size = UDim2.fromOffset(3, 28)
	Spring.animate(self._indicatorBar, "Gentle", { Size = UDim2.fromOffset(3, 16) })
end

function Window:_showPage(tab, previous)
	self:_finishPageFade()
	if previous then
		previous.Page.Visible = false
	end

	local page = tab.Page
	page.Visible = true

	local fade = self._pageFade
	if not previous or not fade or Spring.Instant then
		return
	end

	local direction = tab.Index > previous.Index and 1 or -1
	page.Parent = fade
	self._fadingPage = page
	fade.Visible = true
	fade.GroupTransparency = 1
	fade.Position = UDim2.fromOffset(0, 18 * direction)
	Spring.animate(fade, "Smooth", {
		GroupTransparency = 0,
		Position = UDim2.new(),
	}, function()
		self:_finishPageFade()
	end)
end

function Window:_finishPageFade()
	local page = self._fadingPage
	if not page then
		return
	end
	self._fadingPage = nil
	local fade = self._pageFade
	Spring.stop(fade)
	fade.Visible = false
	fade.GroupTransparency = 0
	fade.Position = UDim2.new()
	if page.Parent then
		page.Parent = self._pages
	end
end

function Window:_onTabsChanged()
	if self.ActiveTab then
		self:_moveIndicator(self.ActiveTab, true)
	end
end

function Window:_removeTab(tab)
	local index = table.find(self.Tabs, tab)
	if index then
		table.remove(self.Tabs, index)
	end
	if self._fadingPage == tab.Page then
		self:_finishPageFade()
	end
	if self.ActiveTab == tab then
		self.ActiveTab = nil
		local nextTab = self.Tabs[math.min(index or 1, #self.Tabs)]
		if nextTab then
			self:SelectTab(nextTab)
		else
			self._indicator.Visible = false
		end
	else
		self:_onTabsChanged()
	end
end

---------------------------------------------------------------------------
-- Elements (used by search, configs and cleanup)
---------------------------------------------------------------------------

function Window:_registerElement(element)
	table.insert(self.Elements, element)
end

function Window:_unregisterElement(element)
	local index = table.find(self.Elements, element)
	if index then
		table.remove(self.Elements, index)
	end
end

---------------------------------------------------------------------------
-- Misc
---------------------------------------------------------------------------

function Window:SetTitle(title, subtitle)
	if title ~= nil then
		self.Name = tostring(title)
		self._titleLabel.Text = self.Name
	end
	if subtitle ~= nil then
		self._subtitleLabel.Text = tostring(subtitle)
		self._subtitleLabel.Visible = subtitle ~= ""
	end
	return self
end

function Window:SetToggleKey(key)
	if typeof(key) == "EnumItem" then
		self._toggleKey = key
	end
	return self
end

function Window:GetToggleKey()
	return self._toggleKey
end

function Window:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	for _, element in ipairs(table.clone(self.Elements)) do
		element:Destroy()
	end
	self.VisibilityChanged:DisconnectAll()
	self.TabChanged:DisconnectAll()
	self.Maid:Clean()
	local windows = self.Library.Windows
	local index = table.find(windows, self)
	if index then
		table.remove(windows, index)
	end
end

return Window
end

-- ======================================================================
-- Core/Env
__modules["Core/Env"] = function()
-- Aether · Core/Env
-- The only place that touches executor-specific functions. Every one of them
-- has a safe fallback, so the same build also runs inside Roblox Studio.
-- Aether never makes network requests on its own.

local Env = {}

local function fn(value)
	if type(value) == "function" then
		return value
	end
	return nil
end

local cloneref = fn(cloneref) or function(instance)
	return instance
end

local services = {}

-- game:GetService, wrapped in cloneref when the executor provides it.
function Env.service(name)
	local service = services[name]
	if not service then
		service = cloneref(game:GetService(name))
		services[name] = service
	end
	return service
end

Env.IsStudio = Env.service("RunService"):IsStudio()

Env.Executor = Env.IsStudio and "Roblox Studio" or "Unknown"
do
	local identify = fn(identifyexecutor) or fn(getexecutorname)
	if identify then
		local ok, name = pcall(identify)
		if ok and type(name) == "string" and name ~= "" then
			Env.Executor = name
		end
	end
end

---------------------------------------------------------------------------
-- File system (configs). Falls back to an in-memory store when the executor
-- has no file functions, so saving and loading still work for the session.
---------------------------------------------------------------------------

local nativeWrite = fn(writefile)
local nativeRead = fn(readfile)
local nativeIsFile = fn(isfile)
local nativeIsFolder = fn(isfolder)
local nativeMakeFolder = fn(makefolder)
local nativeList = fn(listfiles)
local nativeDelete = fn(delfile)

Env.CanSaveFiles = nativeWrite ~= nil and nativeRead ~= nil

local memory = {}

local function normalize(path)
	return (string.gsub(tostring(path), "\\", "/"))
end

local function folderOf(path)
	return string.match(path, "^(.*)/[^/]*$") or ""
end

function Env.makeFolder(path)
	path = normalize(path)
	if path == "" or not nativeMakeFolder then
		return
	end
	local current = ""
	for part in string.gmatch(path, "[^/]+") do
		current = current == "" and part or current .. "/" .. part
		local exists = false
		if nativeIsFolder then
			local ok, result = pcall(nativeIsFolder, current)
			exists = ok and result == true
		end
		if not exists then
			pcall(nativeMakeFolder, current)
		end
	end
end

function Env.fileExists(path)
	path = normalize(path)
	if not Env.CanSaveFiles then
		return memory[path] ~= nil
	end
	if nativeIsFile then
		local ok, result = pcall(nativeIsFile, path)
		return ok and result == true
	end
	local ok, content = pcall(nativeRead, path)
	return ok and type(content) == "string"
end

function Env.readFile(path)
	path = normalize(path)
	if not Env.CanSaveFiles then
		return memory[path]
	end
	if not Env.fileExists(path) then
		return nil
	end
	local ok, content = pcall(nativeRead, path)
	if ok and type(content) == "string" then
		return content
	end
	return nil
end

function Env.writeFile(path, content)
	path = normalize(path)
	if not Env.CanSaveFiles then
		memory[path] = content
		return true
	end
	Env.makeFolder(folderOf(path))
	return (pcall(nativeWrite, path, content))
end

function Env.deleteFile(path)
	path = normalize(path)
	if not Env.CanSaveFiles then
		memory[path] = nil
		return true
	end
	if not nativeDelete then
		return false
	end
	return (pcall(nativeDelete, path))
end

-- File names (not full paths) inside a folder, sorted.
function Env.listFiles(folder)
	folder = normalize(folder)
	local results = {}

	if Env.CanSaveFiles then
		if nativeList then
			local ok, list = pcall(nativeList, folder)
			if ok and type(list) == "table" then
				for _, path in ipairs(list) do
					local name = string.match(normalize(path), "([^/]+)$")
					if name then
						table.insert(results, name)
					end
				end
			end
		end
	else
		local prefix = folder .. "/"
		for path in pairs(memory) do
			if string.sub(path, 1, #prefix) == prefix and not string.find(path, "/", #prefix + 1, true) then
				table.insert(results, string.sub(path, #prefix + 1))
			end
		end
	end

	table.sort(results)
	return results
end

---------------------------------------------------------------------------
-- Clipboard
---------------------------------------------------------------------------

local nativeClipboard = fn(setclipboard) or fn(toclipboard) or fn(set_clipboard)

Env.CanCopy = nativeClipboard ~= nil

function Env.copy(text)
	if not nativeClipboard then
		return false
	end
	return (pcall(nativeClipboard, tostring(text)))
end

---------------------------------------------------------------------------
-- Mounting the ScreenGui: hidden UI container > CoreGui > PlayerGui.
---------------------------------------------------------------------------

local nativeGetHui = fn(gethui) or fn(get_hidden_gui)
local protectGui = (type(syn) == "table" and fn(syn.protect_gui)) or fn(protectgui)

local function tryParent(gui, parent)
	local ok = pcall(function()
		gui.Parent = parent
	end)
	return ok and gui.Parent == parent
end

function Env.mount(gui)
	if nativeGetHui then
		local ok, container = pcall(nativeGetHui)
		if ok and typeof(container) == "Instance" and tryParent(gui, container) then
			return "gethui"
		end
	end

	if protectGui then
		pcall(protectGui, gui)
	end
	if tryParent(gui, Env.service("CoreGui")) then
		return "CoreGui"
	end

	local player = Env.service("Players").LocalPlayer
	if player then
		local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
		if playerGui and tryParent(gui, playerGui) then
			return "PlayerGui"
		end
	end

	error("[Aether] Could not find anywhere to show the interface", 2)
end

return Env
end

-- ======================================================================
-- Core/IconPack
__modules["Core/IconPack"] = function()
-- Aether · Core/IconPack  (generated by tools/gen-icons.js, do not edit)
--
-- 1573 Lucide icons (https://lucide.dev), Lucide v0.363.0.
-- Lucide is ISC licensed, Copyright (c) Lucide Contributors.
-- Roblox sprite sheets from lucide-roblox v0.1.3 (MIT, Latte Softworks),
-- https://github.com/latte-soft/lucide-roblox
--
-- Data format: "name:SXY;" where S is the sheet number and X/Y index into Offsets.

return {
	LucideVersion = "0.363.0",
	Size = 48,
	Sheets = { 16898612629, 16898612819, 16898613044, 16898613353, 16898613509, 16898613613, 16898613699, 16898613777, 16898613869 },
	Offsets = { 0, 49, 98, 147, 196, 257, 306, 355, 404, 453, 514, 563, 612, 661, 710, 759, 771, 808, 820, 857, 869, 906, 918, 955, 967 },
	Data = table.concat({
		"a-arrow-down:1g0;a-arrow-up:10g;a-large-small:1g5;accessibility:15g;activity:1ag;activity-square:1ga;",
		"air-vent:1i0;airplay:1g1;alarm-check:11g;alarm-clock:15i;alarm-clock-check:10i;alarm-clock-minus:1i5;",
		"alarm-clock-off:1g6;alarm-clock-plus:16g;alarm-minus:1ia;alarm-plus:1gb;alarm-smoke:1bg;album:1ai;",
		"alert-circle:1k0;alert-octagon:1i1;alert-triangle:1g2;align-center:10k;align-center-horizontal:12g;",
		"align-center-vertical:11i;align-end-horizontal:1k5;align-end-vertical:1i6;",
		"align-horizontal-distribute-center:1g7;align-horizontal-distribute-end:17g;",
		"align-horizontal-distribute-start:16i;align-horizontal-justify-center:15k;align-horizontal-justify-end:1ka;",
		"align-horizontal-justify-start:1ib;align-horizontal-space-around:1gc;align-horizontal-space-between:1cg;",
		"align-justify:1bi;align-left:1ak;align-right:1m0;align-start-horizontal:1k1;align-start-vertical:1i2;",
		"align-vertical-distribute-center:1g3;align-vertical-distribute-end:13g;align-vertical-distribute-start:12i;",
		"align-vertical-justify-center:11k;align-vertical-justify-end:10m;align-vertical-justify-start:1m5;",
		"align-vertical-space-around:1k6;align-vertical-space-between:1i7;ambulance:1g8;ampersand:18g;ampersands:17i;",
		"anchor:16k;angry:15m;annoyed:1ma;antenna:1kb;anvil:1ic;aperture:1gd;app-window:1ci;app-window-mac:1dg;",
		"apple:1bk;archive:1m1;archive-restore:1am;archive-x:1o0;area-chart:1k2;armchair:1i3;arrow-big-down:14g;",
		"arrow-big-down-dash:1g4;arrow-big-left:12k;arrow-big-left-dash:13i;arrow-big-right:10o;",
		"arrow-big-right-dash:11m;arrow-big-up:1m6;arrow-big-up-dash:1o5;arrow-down:1o1;arrow-down-0-1:1k7;",
		"arrow-down-1-0:1i8;arrow-down-a-z:1g9;arrow-down-circle:19g;arrow-down-from-line:18i;arrow-down-left:15o;",
		"arrow-down-left-from-circle:17k;arrow-down-left-square:16m;arrow-down-narrow-wide:1oa;arrow-down-right:1id;",
		"arrow-down-right-from-circle:1mb;arrow-down-right-square:1kc;arrow-down-square:1ge;arrow-down-to-dot:1eg;",
		"arrow-down-to-line:1di;arrow-down-up:1ck;arrow-down-wide-narrow:1bm;arrow-down-z-a:1ao;arrow-left:12m;",
		"arrow-left-circle:1m2;arrow-left-from-line:1k3;arrow-left-right:1i4;arrow-left-square:14i;",
		"arrow-left-to-line:13k;arrow-right:19i;arrow-right-circle:11o;arrow-right-from-line:1o6;arrow-right-left:1m7;",
		"arrow-right-square:1k8;arrow-right-to-line:1i9;arrow-up:1o7;arrow-up-0-1:18k;arrow-up-1-0:17m;arrow-up-a-z:16o;",
		"arrow-up-circle:1ob;arrow-up-down:1mc;arrow-up-from-dot:1kd;arrow-up-from-line:1ie;arrow-up-left:1dk;",
		"arrow-up-left-from-circle:1gf;arrow-up-left-square:1ei;arrow-up-narrow-wide:1cm;arrow-up-right:1m3;",
		"arrow-up-right-from-circle:1bo;arrow-up-right-square:1o2;arrow-up-square:1k4;arrow-up-to-line:14k;",
		"arrow-up-wide-narrow:13m;arrow-up-z-a:12o;arrows-up-from-line:1m8;asterisk:1k9;at-sign:19k;atom:18m;",
		"audio-lines:17o;audio-waveform:1oc;award:1md;axe:1ke;axis-3d:1if;baby:1gh;backpack:1ek;badge:1do;",
		"badge-alert:1dm;badge-cent:1co;badge-check:1o3;badge-dollar-sign:1m4;badge-euro:14m;badge-help:13o;",
		"badge-indian-rupee:1o8;badge-info:1m9;badge-japanese-yen:19m;badge-minus:18o;badge-percent:1od;badge-plus:1me;",
		"badge-pound-sterling:1kf;badge-russian-ruble:1ih;badge-swiss-franc:1gj;badge-x:1em;baggage-claim:1o4;ban:14o;",
		"banana:1o9;banknote:19o;bar-chart:1of;bar-chart-2:1oe;bar-chart-3:1mf;bar-chart-4:1kh;bar-chart-big:1ij;",
		"bar-chart-horizontal:1eo;bar-chart-horizontal-big:1gl;barcode:1mh;baseline:1kj;bath:1il;battery:1oj;",
		"battery-charging:1gn;battery-full:1oh;battery-low:1mj;battery-medium:1kl;battery-warning:1in;beaker:1ml;",
		"bean:1ol;bean-off:1kn;bed:2g0;bed-double:1mn;bed-single:1on;beef:20g;beer:25g;beer-off:2g5;bell:2i5;",
		"bell-dot:2ga;bell-electric:2ag;bell-minus:2i0;bell-off:2g1;bell-plus:21g;bell-ring:20i;",
		"between-horizontal-end:2g6;between-horizontal-start:26g;between-vertical-end:25i;between-vertical-start:2ia;",
		"bike:2gb;binary:2bg;biohazard:2ai;bird:2k0;bitcoin:2i1;blend:2g2;blinds:22g;blocks:21i;bluetooth:2g7;",
		"bluetooth-connected:20k;bluetooth-off:2k5;bluetooth-searching:2i6;bold:27g;bolt:26i;bomb:25k;bone:2ka;book:2ic;",
		"book-a:2ib;book-audio:2gc;book-check:2cg;book-copy:2bi;book-dashed:2ak;book-down:2m0;book-headphones:2k1;",
		"book-heart:2i2;book-image:2g3;book-key:23g;book-lock:22i;book-marked:21k;book-minus:20m;book-open:2i7;",
		"book-open-check:2m5;book-open-text:2k6;book-plus:2g8;book-text:28g;book-type:27i;book-up:25m;book-up-2:26k;",
		"book-user:2ma;book-x:2kb;bookmark:2am;bookmark-check:2gd;bookmark-minus:2dg;bookmark-plus:2ci;bookmark-x:2bk;",
		"boom-box:2o0;bot:2k2;bot-message-square:2m1;box:2g4;box-select:2i3;boxes:24g;braces:23i;brackets:22k;brain:2o5;",
		"brain-circuit:21m;brain-cog:20o;brick-wall:2m6;briefcase:2g9;briefcase-business:2k7;briefcase-medical:2i8;",
		"bring-to-front:29g;brush:28i;bug:25o;bug-off:27k;bug-play:26m;building:2mb;building-2:2oa;bus:2id;",
		"bus-front:2kc;cable:2eg;cable-car:2ge;cake:2ck;cake-slice:2di;calculator:2bm;calendar:27m;calendar-check:2o1;",
		"calendar-check-2:2ao;calendar-clock:2m2;calendar-days:2k3;calendar-fold:2i4;calendar-heart:24i;",
		"calendar-minus:22m;calendar-minus-2:23k;calendar-off:21o;calendar-plus:2m7;calendar-plus-2:2o6;",
		"calendar-range:2k8;calendar-search:2i9;calendar-x:28k;calendar-x-2:29i;camera:2ob;camera-off:26o;",
		"candlestick-chart:2mc;candy:2gf;candy-cane:2kd;candy-off:2ie;cannabis:2ei;captions:2cm;captions-off:2dk;",
		"car:2m3;car-front:2bo;car-taxi-front:2o2;caravan:2k4;carrot:24k;case-lower:23m;case-sensitive:22o;",
		"case-upper:2o7;cassette-tape:2m8;cast:2k9;castle:29k;cat:28m;cctv:27o;check:2ek;check-check:2oc;",
		"check-circle:2ke;check-circle-2:2md;check-square:2gh;check-square-2:2if;chef-hat:2dm;cherry:2co;",
		"chevron-down:24m;chevron-down-circle:2o3;chevron-down-square:2m4;chevron-first:23o;chevron-last:2o8;",
		"chevron-left:28o;chevron-left-circle:2m9;chevron-left-square:29m;chevron-right:2kf;chevron-right-circle:2od;",
		"chevron-right-square:2me;chevron-up:2em;chevron-up-circle:2ih;chevron-up-square:2gj;chevrons-down:2o4;",
		"chevrons-down-up:2do;chevrons-left:2o9;chevrons-left-right:24o;chevrons-right:2oe;chevrons-right-left:29o;",
		"chevrons-up:2kh;chevrons-up-down:2mf;chrome:2ij;church:2gl;cigarette:2of;cigarette-off:2eo;circle:3g7;",
		"circle-alert:2mh;circle-arrow-down:2kj;circle-arrow-left:2il;circle-arrow-out-down-left:2gn;",
		"circle-arrow-out-down-right:2oh;circle-arrow-out-up-left:2mj;circle-arrow-out-up-right:2kl;",
		"circle-arrow-right:2in;circle-arrow-up:2oj;circle-check:2kn;circle-check-big:2ml;circle-chevron-down:2ol;",
		"circle-chevron-left:2mn;circle-chevron-right:2on;circle-chevron-up:3g0;circle-dashed:30g;circle-divide:3g5;",
		"circle-dollar-sign:35g;circle-dot:3ag;circle-dot-dashed:3ga;circle-ellipsis:3i0;circle-equal:3g1;",
		"circle-fading-plus:31g;circle-gauge:30i;circle-help:3i5;circle-minus:3g6;circle-off:36g;circle-parking:3ia;",
		"circle-parking-off:35i;circle-pause:3gb;circle-percent:3bg;circle-play:3ai;circle-plus:3k0;circle-power:3i1;",
		"circle-slash:32g;circle-slash-2:3g2;circle-stop:31i;circle-user:3k5;circle-user-round:30k;circle-x:3i6;",
		"circuit-board:37g;citrus:36i;clapperboard:35k;clipboard:31k;clipboard-check:3ka;clipboard-copy:3ib;",
		"clipboard-edit:3gc;clipboard-list:3cg;clipboard-minus:3bi;clipboard-paste:3ak;clipboard-pen:3k1;",
		"clipboard-pen-line:3m0;clipboard-plus:3i2;clipboard-signature:3g3;clipboard-type:33g;clipboard-x:32i;clock:3gd;",
		"clock-1:30m;clock-10:3m5;clock-11:3k6;clock-12:3i7;clock-2:3g8;clock-3:38g;clock-4:37i;clock-5:36k;clock-6:35m;",
		"clock-7:3ma;clock-8:3kb;clock-9:3ic;cloud:3m6;cloud-cog:3dg;cloud-download:3ci;cloud-drizzle:3bk;cloud-fog:3am;",
		"cloud-hail:3o0;cloud-lightning:3m1;cloud-moon:3i3;cloud-moon-rain:3k2;cloud-off:3g4;cloud-rain:33i;",
		"cloud-rain-wind:34g;cloud-snow:32k;cloud-sun:30o;cloud-sun-rain:31m;cloud-upload:3o5;cloudy:3k7;clover:3i8;",
		"club:3g9;code:37k;code-2:39g;code-xml:38i;codepen:36m;codesandbox:35o;coffee:3oa;cog:3mb;coins:3kc;columns:3di;",
		"columns-2:3id;columns-3:3ge;columns-4:3eg;combine:3ck;command:3bm;compass:3ao;component:3o1;computer:3m2;",
		"concierge-bell:3k3;cone:3i4;construction:34i;contact:31o;contact-2:33k;contact-round:32m;container:3o6;",
		"contrast:3m7;cookie:3k8;cooking-pot:3i9;copy:3mc;copy-check:39i;copy-minus:38k;copy-plus:37m;copy-slash:36o;",
		"copy-x:3ob;copyleft:3kd;copyright:3ie;corner-down-left:3gf;corner-down-right:3ei;corner-left-down:3dk;",
		"corner-left-up:3cm;corner-right-down:3bo;corner-right-up:3o2;corner-up-left:3m3;corner-up-right:3k4;cpu:34k;",
		"creative-commons:33m;credit-card:32o;croissant:3o7;crop:3m8;cross:3k9;crosshair:39k;crown:38m;cuboid:37o;",
		"cup-soda:3oc;currency:3md;cylinder:3ke;database:3ek;database-backup:3if;database-zap:3gh;delete:3dm;",
		"dessert:3co;diameter:3o3;diamond:34m;diamond-percent:3m4;dice-1:33o;dice-2:3o8;dice-3:3m9;dice-4:39m;",
		"dice-5:38o;dice-6:3od;dices:3me;diff:3kf;disc:3do;disc-2:3ih;disc-3:3gj;disc-album:3em;divide:3o9;",
		"divide-circle:3o4;divide-square:34o;dna:3oe;dna-off:39o;dock:3mf;dog:3kh;dollar-sign:3ij;donut:3gl;",
		"door-closed:3eo;door-open:3of;dot:3mh;download:3il;download-cloud:3kj;drafting-compass:3gn;drama:3oh;",
		"dribbble:3mj;drill:3kl;droplet:3in;droplets:3oj;drum:3ml;drumstick:3kn;dumbbell:3ol;ear:3on;ear-off:3mn;",
		"earth:40g;earth-lock:4g0;eclipse:4g5;egg:4ag;egg-fried:45g;egg-off:4ga;ellipsis:4g1;ellipsis-vertical:4i0;",
		"equal:40i;equal-not:41g;eraser:4i5;euro:4g6;expand:46g;external-link:45i;eye:4gb;eye-off:4ia;facebook:4bg;",
		"factory:4ai;fan:4k0;fast-forward:4i1;feather:4g2;fence:42g;ferris-wheel:41i;figma:40k;file:4id;",
		"file-archive:4k5;file-audio:4g7;file-audio-2:4i6;file-axis-3d:47g;file-badge:45k;file-badge-2:46i;",
		"file-bar-chart:4ib;file-bar-chart-2:4ka;file-box:4gc;file-check:4bi;file-check-2:4cg;file-clock:4ak;",
		"file-code:4k1;file-code-2:4m0;file-cog:4i2;file-diff:4g3;file-digit:43g;file-down:42i;file-edit:41k;",
		"file-heart:40m;file-image:4m5;file-input:4k6;file-json:4g8;file-json-2:4i7;file-key:47i;file-key-2:48g;",
		"file-line-chart:46k;file-lock:4ma;file-lock-2:45m;file-minus:4ic;file-minus-2:4kb;file-music:4gd;",
		"file-output:4dg;file-pen:4bk;file-pen-line:4ci;file-pie-chart:4am;file-plus:4m1;file-plus-2:4o0;",
		"file-question:4k2;file-scan:4i3;file-search:44g;file-search-2:4g4;file-signature:43i;file-sliders:42k;",
		"file-spreadsheet:41m;file-stack:40o;file-symlink:4o5;file-terminal:4m6;file-text:4k7;file-type:4g9;",
		"file-type-2:4i8;file-up:49g;file-video:47k;file-video-2:48i;file-volume:45o;file-volume-2:46m;file-warning:4oa;",
		"file-x:4kc;file-x-2:4mb;files:4ge;film:4eg;filter:4ck;filter-x:4di;fingerprint:4bm;fire-extinguisher:4ao;",
		"fish:4k3;fish-off:4o1;fish-symbol:4m2;flag:42m;flag-off:4i4;flag-triangle-left:44i;flag-triangle-right:43k;",
		"flame:4o6;flame-kindling:41o;flashlight:4k8;flashlight-off:4m7;flask-conical:49i;flask-conical-off:4i9;",
		"flask-round:48k;flip-horizontal:46o;flip-horizontal-2:47m;flip-vertical:4mc;flip-vertical-2:4ob;flower:4ie;",
		"flower-2:4kd;focus:4gf;fold-horizontal:4ei;fold-vertical:4dk;folder:48o;folder-archive:4cm;folder-check:4bo;",
		"folder-clock:4o2;folder-closed:4m3;folder-cog:4k4;folder-dot:44k;folder-down:43m;folder-edit:42o;",
		"folder-git:4m8;folder-git-2:4o7;folder-heart:4k9;folder-input:49k;folder-kanban:48m;folder-key:47o;",
		"folder-lock:4oc;folder-minus:4md;folder-open:4if;folder-open-dot:4ke;folder-output:4gh;folder-pen:4ek;",
		"folder-plus:4dm;folder-root:4co;folder-search:4m4;folder-search-2:4o3;folder-symlink:44m;folder-sync:43o;",
		"folder-tree:4o8;folder-up:4m9;folder-x:49m;folders:4od;footprints:4me;forklift:4kf;form-input:4ih;forward:4gj;",
		"frame:4em;framer:4do;frown:4o4;fuel:44o;fullscreen:4o9;function-square:49o;gallery-horizontal:4mf;",
		"gallery-horizontal-end:4oe;gallery-thumbnails:4kh;gallery-vertical:4gl;gallery-vertical-end:4ij;gamepad:4of;",
		"gamepad-2:4eo;gantt-chart:4kj;gantt-chart-square:4mh;gauge:4gn;gauge-circle:4il;gavel:4oh;gem:4mj;ghost:4kl;",
		"gift:4in;git-branch:4ml;git-branch-plus:4oj;git-commit-horizontal:4kn;git-commit-vertical:4ol;git-compare:4on;",
		"git-compare-arrows:4mn;git-fork:5g0;git-graph:50g;git-merge:5g5;git-pull-request:51g;",
		"git-pull-request-arrow:55g;git-pull-request-closed:5ga;git-pull-request-create:5i0;",
		"git-pull-request-create-arrow:5ag;git-pull-request-draft:5g1;github:50i;gitlab:5i5;glass-water:5g6;glasses:56g;",
		"globe:5gb;globe-2:55i;globe-lock:5ia;goal:5bg;grab:5ai;graduation-cap:5k0;grape:5i1;grid-2x2:5g2;grid-3x3:52g;",
		"grip:5k5;grip-horizontal:51i;grip-vertical:50k;group:5i6;guitar:5g7;ham:57g;hammer:56i;hand:5bi;hand-coins:55k;",
		"hand-heart:5ka;hand-helping:5ib;hand-metal:5gc;hand-platter:5cg;handshake:5ak;hard-drive:5i2;",
		"hard-drive-download:5m0;hard-drive-upload:5k1;hard-hat:5g3;hash:53g;haze:52i;hdmi-port:51k;heading:57i;",
		"heading-1:50m;heading-2:5m5;heading-3:5k6;heading-4:5i7;heading-5:5g8;heading-6:58g;headphones:56k;headset:55m;",
		"heart:5dg;heart-crack:5ma;heart-handshake:5kb;heart-off:5ic;heart-pulse:5gd;heater:5ci;help-circle:5bk;",
		"helping-hand:5am;hexagon:5o0;highlighter:5m1;history:5k2;home:5i3;hop:54g;hop-off:5g4;hospital:53i;hotel:52k;",
		"hourglass:51m;ice-cream:5k7;ice-cream-2:50o;ice-cream-bowl:5o5;ice-cream-cone:5m6;image:56m;image-down:5i8;",
		"image-minus:5g9;image-off:59g;image-plus:58i;image-up:57k;images:55o;import:5oa;inbox:5mb;indent:5ge;",
		"indent-decrease:5kc;indent-increase:5id;indian-rupee:5eg;infinity:5di;info:5ck;inspection-panel:5bm;",
		"instagram:5ao;italic:5o1;iteration-ccw:5m2;iteration-cw:5k3;japanese-yen:5i4;joystick:54i;kanban:51o;",
		"kanban-square:52m;kanban-square-dashed:53k;key:5k8;key-round:5o6;key-square:5m7;keyboard:59i;",
		"keyboard-music:5i9;lamp:5kd;lamp-ceiling:58k;lamp-desk:57m;lamp-floor:56o;lamp-wall-down:5ob;lamp-wall-up:5mc;",
		"land-plot:5ie;landmark:5gf;languages:5ei;laptop:5bo;laptop-2:5dk;laptop-minimal:5cm;lasso:5m3;lasso-select:5o2;",
		"laugh:5k4;layers:52o;layers-2:54k;layers-3:53m;layout:5oc;layout-dashboard:5o7;layout-grid:5m8;layout-list:5k9;",
		"layout-panel-left:59k;layout-panel-top:58m;layout-template:57o;leaf:5md;leafy-green:5ke;library:5ek;",
		"library-big:5if;library-square:5gh;life-buoy:5dm;ligature:5co;lightbulb:5m4;lightbulb-off:5o3;line-chart:54m;",
		"link:5m9;link-2:5o8;link-2-off:53o;linkedin:59m;list:5kh;list-checks:58o;list-collapse:5od;list-end:5me;",
		"list-filter:5kf;list-minus:5ih;list-music:5gj;list-ordered:5em;list-plus:5do;list-restart:5o4;list-start:54o;",
		"list-todo:5o9;list-tree:59o;list-video:5oe;list-x:5mf;loader:5eo;loader-2:5ij;loader-circle:5gl;locate:5kj;",
		"locate-fixed:5of;locate-off:5mh;lock:5mj;lock-keyhole:5gn;lock-keyhole-open:5il;lock-open:5oh;log-in:5kl;",
		"log-out:5in;lollipop:5oj;luggage:5ml;m-square:5kn;magnet:5ol;mail:6i0;mail-check:5mn;mail-minus:5on;",
		"mail-open:6g0;mail-plus:60g;mail-question:6g5;mail-search:65g;mail-warning:6ga;mail-x:6ag;mailbox:6g1;",
		"mails:61g;map:66g;map-pin:6i5;map-pin-off:60i;map-pinned:6g6;martini:65i;maximize:6gb;maximize-2:6ia;medal:6bg;",
		"megaphone:6k0;megaphone-off:6ai;meh:6i1;memory-stick:6g2;menu:61i;menu-square:62g;merge:60k;message-circle:6bi;",
		"message-circle-code:6k5;message-circle-dashed:6i6;message-circle-heart:6g7;message-circle-more:67g;",
		"message-circle-off:66i;message-circle-plus:65k;message-circle-question:6ka;message-circle-reply:6ib;",
		"message-circle-warning:6gc;message-circle-x:6cg;message-square:67i;message-square-code:6ak;",
		"message-square-dashed:6m0;message-square-diff:6k1;message-square-dot:6i2;message-square-heart:6g3;",
		"message-square-more:63g;message-square-off:62i;message-square-plus:61k;message-square-quote:60m;",
		"message-square-reply:6m5;message-square-share:6k6;message-square-text:6i7;message-square-warning:6g8;",
		"message-square-x:68g;messages-square:66k;mic:6ic;mic-2:65m;mic-off:6ma;mic-vocal:6kb;microscope:6gd;",
		"microwave:6dg;milestone:6ci;milk:6am;milk-off:6bk;minimize:6m1;minimize-2:6o0;minus:6g4;minus-circle:6k2;",
		"minus-square:6i3;monitor:68i;monitor-check:64g;monitor-dot:63i;monitor-down:62k;monitor-off:61m;",
		"monitor-pause:60o;monitor-play:6o5;monitor-smartphone:6m6;monitor-speaker:6k7;monitor-stop:6i8;monitor-up:6g9;",
		"monitor-x:69g;moon:66m;moon-star:67k;more-horizontal:65o;more-vertical:6oa;mountain:6kc;mountain-snow:6mb;",
		"mouse:6bm;mouse-pointer:6ck;mouse-pointer-2:6id;mouse-pointer-click:6ge;mouse-pointer-square:6di;",
		"mouse-pointer-square-dashed:6eg;move:69i;move-3d:6ao;move-diagonal:6m2;move-diagonal-2:6o1;move-down:64i;",
		"move-down-left:6k3;move-down-right:6i4;move-horizontal:63k;move-left:62m;move-right:61o;move-up:6k8;",
		"move-up-left:6o6;move-up-right:6m7;move-vertical:6i9;music:6ob;music-2:68k;music-3:67m;music-4:66o;",
		"navigation:6gf;navigation-2:6kd;navigation-2-off:6mc;navigation-off:6ie;network:6ei;newspaper:6dk;nfc:6cm;",
		"notebook:6k4;notebook-pen:6bo;notebook-tabs:6o2;notebook-text:6m3;notepad-text:63m;notepad-text-dashed:64k;",
		"nut:6o7;nut-off:62o;octagon:68m;octagon-alert:6m8;octagon-pause:6k9;octagon-x:69k;option:67o;orbit:6oc;",
		"outdent:6md;package:6m4;package-2:6ke;package-check:6if;package-minus:6gh;package-open:6ek;package-plus:6dm;",
		"package-search:6co;package-x:6o3;paint-bucket:64m;paint-roller:63o;paintbrush:6m9;paintbrush-2:6o8;palette:69m;",
		"palmtree:68o;panel-bottom:6gj;panel-bottom-close:6od;panel-bottom-dashed:6me;panel-bottom-inactive:6kf;",
		"panel-bottom-open:6ih;panel-left:6o9;panel-left-close:6em;panel-left-dashed:6do;panel-left-inactive:6o4;",
		"panel-left-open:64o;panel-right:6ij;panel-right-close:69o;panel-right-dashed:6oe;panel-right-inactive:6mf;",
		"panel-right-open:6kh;panel-top:6kj;panel-top-close:6gl;panel-top-dashed:6eo;panel-top-inactive:6of;",
		"panel-top-open:6mh;panels-left-bottom:6il;panels-right-bottom:6gn;panels-top-left:6oh;paperclip:6mj;",
		"parentheses:6kl;parking-circle:6oj;parking-circle-off:6in;parking-meter:6ml;parking-square:6ol;",
		"parking-square-off:6kn;party-popper:6mn;pause:70g;pause-circle:6on;pause-octagon:7g0;paw-print:7g5;pc-case:75g;",
		"pen:7g1;pen-line:7ga;pen-square:7ag;pen-tool:7i0;pencil:7i5;pencil-line:71g;pencil-ruler:70i;pentagon:7g6;",
		"percent:7gb;percent-circle:76g;percent-diamond:75i;percent-square:7ia;person-standing:7bg;phone:70k;",
		"phone-call:7ai;phone-forwarded:7k0;phone-incoming:7i1;phone-missed:7g2;phone-off:72g;phone-outgoing:71i;pi:7i6;",
		"pi-square:7k5;piano:7g7;pickaxe:77g;picture-in-picture:75k;picture-in-picture-2:76i;pie-chart:7ka;",
		"piggy-bank:7ib;pilcrow:7cg;pilcrow-square:7gc;pill:7bi;pin:7m0;pin-off:7ak;pipette:7k1;pizza:7i2;plane:72i;",
		"plane-landing:7g3;plane-takeoff:73g;play:7m5;play-circle:71k;play-square:70m;plug:78g;plug-2:7k6;plug-zap:7g8;",
		"plug-zap-2:7i7;plus:75m;plus-circle:77i;plus-square:76k;pocket:7kb;pocket-knife:7ma;podcast:7ic;pointer:7dg;",
		"pointer-off:7gd;popcorn:7ci;popsicle:7bk;pound-sterling:7am;power:7i3;power-circle:7o0;power-off:7m1;",
		"power-square:7k2;presentation:7g4;printer:74g;projector:73i;proportions:72k;puzzle:71m;pyramid:70o;qr-code:7o5;",
		"quote:7m6;rabbit:7k7;radar:7i8;radiation:7g9;radical:79g;radio:76m;radio-receiver:78i;radio-tower:77k;",
		"radius:75o;rail-symbol:7oa;rainbow:7mb;rat:7kc;ratio:7id;receipt:7k3;receipt-cent:7ge;receipt-euro:7eg;",
		"receipt-indian-rupee:7di;receipt-japanese-yen:7ck;receipt-pound-sterling:7bm;receipt-russian-ruble:7ao;",
		"receipt-swiss-franc:7o1;receipt-text:7m2;rectangle-ellipsis:7i4;rectangle-horizontal:74i;",
		"rectangle-vertical:73k;recycle:72m;redo:7m7;redo-2:71o;redo-dot:7o6;refresh-ccw:7i9;refresh-ccw-dot:7k8;",
		"refresh-cw:78k;refresh-cw-off:79i;refrigerator:77m;regex:76o;remove-formatting:7ob;repeat:7ie;repeat-1:7mc;",
		"repeat-2:7kd;replace:7ei;replace-all:7gf;reply:7cm;reply-all:7dk;rewind:7bo;ribbon:7o2;rocket:7m3;",
		"rocking-chair:7k4;roller-coaster:74k;rotate-3d:73m;rotate-ccw:7o7;rotate-ccw-square:72o;rotate-cw:7k9;",
		"rotate-cw-square:7m8;route:78m;route-off:79k;router:77o;rows:7if;rows-2:7oc;rows-3:7md;rows-4:7ke;rss:7gh;",
		"ruler:7ek;russian-ruble:7dm;sailboat:7co;salad:7o3;sandwich:7m4;satellite:73o;satellite-dish:74m;save:7m9;",
		"save-all:7o8;scale:78o;scale-3d:79m;scaling:7od;scan:7o4;scan-barcode:7me;scan-eye:7kf;scan-face:7ih;",
		"scan-line:7gj;scan-search:7em;scan-text:7do;scatter-chart:74o;school:79o;school-2:7o9;scissors:7ij;",
		"scissors-line-dashed:7oe;scissors-square:7kh;scissors-square-dashed-bottom:7mf;screen-share:7eo;",
		"screen-share-off:7gl;scroll:7mh;scroll-text:7of;search:7mj;search-check:7kj;search-code:7il;search-slash:7gn;",
		"search-x:7oh;send:7oj;send-horizontal:7kl;send-to-back:7in;separator-horizontal:7ml;separator-vertical:7kn;",
		"server:8g0;server-cog:7ol;server-crash:7mn;server-off:7on;settings:8g5;settings-2:80g;shapes:85g;share:8ag;",
		"share-2:8ga;sheet:8i0;shell:8g1;shield:8k0;shield-alert:81g;shield-ban:80i;shield-check:8i5;",
		"shield-ellipsis:8g6;shield-half:86g;shield-minus:85i;shield-off:8ia;shield-plus:8gb;shield-question:8bg;",
		"shield-x:8ai;ship:8g2;ship-wheel:8i1;shirt:82g;shopping-bag:81i;shopping-basket:80k;shopping-cart:8k5;",
		"shovel:8i6;shower-head:8g7;shrink:87g;shrub:86i;shuffle:85k;sigma:8ib;sigma-square:8ka;signal:8m0;",
		"signal-high:8gc;signal-low:8cg;signal-medium:8bi;signal-zero:8ak;signpost:8i2;signpost-big:8k1;siren:8g3;",
		"skip-back:83g;skip-forward:82i;skull:81k;slack:80m;slash:8m5;slice:8k6;sliders:88g;sliders-horizontal:8i7;",
		"sliders-vertical:8g8;smartphone:85m;smartphone-charging:87i;smartphone-nfc:86k;smile:8kb;smile-plus:8ma;",
		"snail:8ic;snowflake:8gd;sofa:8dg;soup:8ci;space:8bk;spade:8am;sparkle:8o0;sparkles:8m1;speaker:8k2;speech:8i3;",
		"spell-check:84g;spell-check-2:8g4;spline:83i;split:80o;split-square-horizontal:82k;split-square-vertical:81m;",
		"spray-can:8o5;sprout:8m6;square:8ke;square-activity:8k7;square-arrow-down:89g;square-arrow-down-left:8i8;",
		"square-arrow-down-right:8g9;square-arrow-left:88i;square-arrow-out-down-left:87k;",
		"square-arrow-out-down-right:86m;square-arrow-out-up-left:85o;square-arrow-out-up-right:8oa;",
		"square-arrow-right:8mb;square-arrow-up:8ge;square-arrow-up-left:8kc;square-arrow-up-right:8id;",
		"square-asterisk:8eg;square-bottom-dashed-scissors:8di;square-check:8bm;square-check-big:8ck;",
		"square-chevron-down:8ao;square-chevron-left:8o1;square-chevron-right:8m2;square-chevron-up:8k3;square-code:8i4;",
		"square-dashed-bottom:83k;square-dashed-bottom-code:84i;square-dashed-kanban:82m;",
		"square-dashed-mouse-pointer:81o;square-divide:8o6;square-dot:8m7;square-equal:8k8;square-function:8i9;",
		"square-gantt-chart:89i;square-kanban:88k;square-library:87m;square-m:86o;square-menu:8ob;square-minus:8mc;",
		"square-mouse-pointer:8kd;square-parking:8gf;square-parking-off:8ie;square-pen:8ei;square-percent:8dk;",
		"square-pi:8cm;square-pilcrow:8bo;square-play:8o2;square-plus:8m3;square-power:8k4;square-radical:84k;",
		"square-scissors:83m;square-sigma:82o;square-slash:8o7;square-split-horizontal:8m8;square-split-vertical:8k9;",
		"square-stack:89k;square-terminal:88m;square-user:8oc;square-user-round:87o;square-x:8md;squircle:8if;",
		"squirrel:8gh;stamp:8ek;star:8o3;star-half:8dm;star-off:8co;step-back:8m4;step-forward:84m;stethoscope:83o;",
		"sticker:8o8;sticky-note:8m9;stop-circle:89m;store:88o;stretch-horizontal:8od;stretch-vertical:8me;",
		"strikethrough:8kf;subscript:8ih;subtitles:8gj;sun:8o9;sun-dim:8em;sun-medium:8do;sun-moon:8o4;sun-snow:84o;",
		"sunrise:89o;sunset:8oe;superscript:8mf;swatch-book:8kh;swiss-franc:8ij;switch-camera:8gl;sword:8eo;swords:8of;",
		"syringe:8mh;table:8in;table-2:8kj;table-cells-merge:8il;table-cells-split:8gn;table-columns-split:8oh;",
		"table-properties:8mj;table-rows-split:8kl;tablet:8ml;tablet-smartphone:8oj;tablets:8kn;tag:8ol;tags:8mn;",
		"tally-1:8on;tally-2:9g0;tally-3:90g;tally-4:9g5;tally-5:95g;tangent:9ga;target:9ag;telescope:9i0;tent:91g;",
		"tent-tree:9g1;terminal:9i5;terminal-square:90i;test-tube:95i;test-tube-2:9g6;test-tube-diagonal:96g;",
		"test-tubes:9ia;text:9g2;text-cursor:9bg;text-cursor-input:9gb;text-quote:9ai;text-search:9k0;text-select:9i1;",
		"theater:92g;thermometer:9k5;thermometer-snowflake:91i;thermometer-sun:90k;thumbs-down:9i6;thumbs-up:9g7;",
		"ticket:9cg;ticket-check:97g;ticket-minus:96i;ticket-percent:95k;ticket-plus:9ka;ticket-slash:9ib;ticket-x:9gc;",
		"timer:9m0;timer-off:9bi;timer-reset:9ak;toggle-left:9k1;toggle-right:9i2;tornado:9g3;torus:93g;touchpad:91k;",
		"touchpad-off:92i;tower-control:90m;toy-brick:9m5;tractor:9k6;traffic-cone:9i7;train-front:98g;",
		"train-front-tunnel:9g8;train-track:97i;tram-front:96k;trash:9ma;trash-2:95m;tree-deciduous:9kb;tree-palm:9ic;",
		"tree-pine:9gd;trees:9dg;trello:9ci;trending-down:9bk;trending-up:9am;triangle:9k2;triangle-alert:9o0;",
		"triangle-right:9m1;trophy:9i3;truck:9g4;turtle:94g;tv:92k;tv-2:93i;twitch:91m;twitter:90o;type:9o5;",
		"umbrella:9k7;umbrella-off:9m6;underline:9i8;undo:98i;undo-2:9g9;undo-dot:99g;unfold-horizontal:97k;",
		"unfold-vertical:96m;ungroup:95o;university:9oa;unlink:9kc;unlink-2:9mb;unlock:9ge;unlock-keyhole:9id;",
		"unplug:9eg;upload:9ck;upload-cloud:9di;usb:9bm;user:9dk;user-2:9ao;user-check:9m2;user-check-2:9o1;",
		"user-circle:9i4;user-circle-2:9k3;user-cog:93k;user-cog-2:94i;user-minus:91o;user-minus-2:92m;user-plus:9m7;",
		"user-plus-2:9o6;user-round:9ob;user-round-check:9k8;user-round-cog:9i9;user-round-minus:99i;",
		"user-round-plus:98k;user-round-search:97m;user-round-x:96o;user-search:9mc;user-square:9ie;user-square-2:9kd;",
		"user-x:9ei;user-x-2:9gf;users:9o2;users-2:9cm;users-round:9bo;utensils:9k4;utensils-crossed:9m3;",
		"utility-pole:94k;variable:93m;vault:92o;vegan:9o7;venetian-mask:9m8;vibrate:99k;vibrate-off:9k9;video:97o;",
		"video-off:98m;videotape:9oc;view:9md;voicemail:9ke;volume:9dm;volume-1:9if;volume-2:9gh;volume-x:9ek;vote:9co;",
		"wallet:93o;wallet-2:9o3;wallet-cards:9m4;wallet-minimal:94m;wallpaper:9o8;wand:98o;wand-2:9m9;",
		"wand-sparkles:99m;warehouse:9od;washing-machine:9me;watch:9kf;waves:9ih;waypoints:9gj;webcam:9em;webhook:9o4;",
		"webhook-off:9do;weight:94o;wheat:99o;wheat-off:9o9;whole-word:9oe;wifi:9kh;wifi-off:9mf;wind:9ij;wine:9eo;",
		"wine-off:9gl;workflow:9of;worm:9mh;wrap-text:9kj;wrench:9il;x:9kl;x-circle:9gn;x-octagon:9oh;x-square:9mj;",
		"youtube:9in;zap:9ml;zap-off:9oj;zoom-in:9kn;zoom-out:9ol;",
	}),
}
end

-- ======================================================================
-- Core/Icons
__modules["Core/Icons"] = function()
-- Aether · Core/Icons
-- Resolves icon references: Lucide names ("sword"), numeric asset ids, or
-- full "rbxassetid://" strings. Unknown names fall back gracefully.

local Log = import("Core/Log")
local IconPack = import("Core/IconPack")

local Icons = {}

Icons.LucideVersion = IconPack.LucideVersion

-- lower-case name -> { Image = "rbxassetid://...", RectOffset = Vector2?, RectSize = Vector2? }
local map = {}
local packLoaded = false
local warned = {}

-- Names people commonly reach for that Lucide spells differently.
local ALIASES = {
	house = "home",
	gear = "settings",
	cog = "settings",
	close = "x",
	cross = "x",
	person = "user",
	profile = "user",
	people = "users",
	["trash-can"] = "trash-2",
	delete = "trash-2",
	warning = "alert-triangle",
	danger = "alert-octagon",
	error = "alert-circle",
	success = "check-circle",
	information = "info",
	world = "globe",
	teleport = "map-pin",
	combat = "swords",
	visuals = "eye",
	player = "user",
	misc = "layers",
	config = "save",
}

-- The Lucide pack is decoded on first use, so loading Aether stays instant.
local function loadPack()
	if packLoaded then
		return
	end
	packLoaded = true
	local sheets, offsets, size = IconPack.Sheets, IconPack.Offsets, IconPack.Size
	local rectSize = Vector2.new(size, size)
	for name, sheet, x, y in string.gmatch(IconPack.Data, "([%w%-]+):(%d)(%w)(%w);") do
		if map[name] == nil then
			map[name] = {
				Image = "rbxassetid://" .. tostring(sheets[tonumber(sheet)]),
				RectOffset = Vector2.new(offsets[tonumber(x, 36) + 1], offsets[tonumber(y, 36) + 1]),
				RectSize = rectSize,
			}
		end
	end
	for alias, target in pairs(ALIASES) do
		if map[alias] == nil and map[target] ~= nil then
			map[alias] = map[target]
		end
	end
end

-- Adds (or overrides) a named icon: Icons.register("logo", "rbxassetid://123")
function Icons.register(name, image, rectOffset, rectSize)
	loadPack()
	map[string.lower(name)] = {
		Image = image,
		RectOffset = rectOffset,
		RectSize = rectSize,
	}
end

function Icons.has(name)
	loadPack()
	return type(name) == "string" and map[string.lower(name)] ~= nil
end

-- Every available icon name, sorted (useful for icon pickers).
function Icons.names()
	loadPack()
	local names = {}
	for name in pairs(map) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function Icons.resolve(icon)
	if icon == nil or icon == false or icon == "" then
		return nil
	end
	if type(icon) == "number" then
		return { Image = "rbxassetid://" .. tostring(icon) }
	end
	if type(icon) ~= "string" then
		return nil
	end
	if string.find(icon, "^rbxasset") or string.find(icon, "^https?://") then
		return { Image = icon }
	end
	if string.match(icon, "^%d+$") then
		return { Image = "rbxassetid://" .. icon }
	end

	loadPack()
	local name = string.lower(icon)
	local entry = map[name]
	if entry then
		return entry
	end

	-- Newer Lucide releases put the shape first ("circle-check"); this pack
	-- uses the older order ("check-circle"). Accept both.
	local shape, rest = string.match(name, "^(%a+)%-(.+)$")
	if shape == "circle" or shape == "square" or shape == "triangle" or shape == "octagon" then
		entry = map[rest .. "-" .. shape]
		if entry then
			map[name] = entry
			return entry
		end
	end

	if not warned[icon] then
		warned[icon] = true
		Log.warn(("Unknown icon '%s'. Use a Lucide icon name or an rbxassetid."):format(icon))
	end
	return nil
end

-- Applies an icon to an ImageLabel/ImageButton. Returns false (and hides the
-- image) when the icon can't be resolved, so callers can show a fallback.
function Icons.apply(image, icon)
	local resolved = Icons.resolve(icon)
	if resolved then
		image.Image = resolved.Image
		image.ImageRectOffset = resolved.RectOffset or Vector2.zero
		image.ImageRectSize = resolved.RectSize or Vector2.zero
		image.Visible = true
		return true
	end
	image.Image = ""
	image.Visible = false
	return false
end

return Icons
end

-- ======================================================================
-- Core/Log
__modules["Core/Log"] = function()
-- Aether · Core/Log
-- Collects library messages. Problems are reported with warn() instead of
-- error(), so a broken callback never takes the whole interface down.

local Log = {}

local MAX_ENTRIES = 250

local entries = {}
local listeners = {}

-- When true, info messages are printed to the output as well.
Log.Debug = false

local function push(level, message)
	local entry = {
		Level = level,
		Message = tostring(message),
		Time = os.time(),
	}

	table.insert(entries, entry)
	if #entries > MAX_ENTRIES then
		table.remove(entries, 1)
	end

	if level == "error" or level == "warn" then
		warn("[Aether] " .. entry.Message)
	elseif Log.Debug then
		print("[Aether] " .. entry.Message)
	end

	for _, listener in ipairs(table.clone(listeners)) do
		task.spawn(pcall, listener, entry)
	end

	return entry
end

function Log.info(message)
	return push("info", message)
end

function Log.warn(message)
	return push("warn", message)
end

function Log.error(message)
	return push("error", message)
end

function Log.entries()
	return table.clone(entries)
end

-- Calls fn(entry) for every new message. Returns a function that stops listening.
function Log.listen(fn)
	table.insert(listeners, fn)
	return function()
		local index = table.find(listeners, fn)
		if index then
			table.remove(listeners, index)
		end
	end
end

return Log
end

-- ======================================================================
-- Core/Maid
__modules["Core/Maid"] = function()
-- Aether · Core/Maid
-- Holds everything that must be cleaned up later (connections, instances,
-- threads, functions, objects with Destroy) and releases it in one call.

local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _items = {} }, Maid)
end

-- Adds an item and returns it, so creation and registration fit on one line.
function Maid:Give(item)
	if item ~= nil then
		table.insert(self._items, item)
	end
	return item
end

local function release(item)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		task.cancel(item)
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		end
	end
end

function Maid:Clean()
	local items = self._items
	self._items = {}
	for index = #items, 1, -1 do
		pcall(release, items[index])
	end
end

Maid.Destroy = Maid.Clean

return Maid
end

-- ======================================================================
-- Core/Signal
__modules["Core/Signal"] = function()
-- Aether · Core/Signal
-- Lightweight signal. Every handler runs in its own protected thread: an
-- error is logged, and a handler that yields never blocks the interface.

local Log = import("Core/Log")

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local handlers = self._signal._handlers
	local index = table.find(handlers, self)
	if index then
		table.remove(handlers, index)
	end
end

Connection.Destroy = Connection.Disconnect

local Signal = {}
Signal.__index = Signal

function Signal.new(name)
	return setmetatable({
		_handlers = {},
		_name = name or "signal",
	}, Signal)
end

function Signal:Connect(handler)
	assert(type(handler) == "function", "[Aether] Signal:Connect expects a function")
	local connection = setmetatable({
		Connected = true,
		_handler = handler,
		_signal = self,
	}, Connection)
	table.insert(self._handlers, connection)
	return connection
end

function Signal:Once(handler)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

local function run(name, handler, ...)
	local ok, err = xpcall(handler, debug.traceback, ...)
	if not ok then
		Log.error(("Callback error in %s:\n%s"):format(name, tostring(err)))
	end
end

function Signal:Fire(...)
	for _, connection in ipairs(table.clone(self._handlers)) do
		if connection.Connected then
			task.spawn(run, self._name, connection._handler, ...)
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, connection in ipairs(self._handlers) do
		connection.Connected = false
	end
	table.clear(self._handlers)
end

Signal.Destroy = Signal.DisconnectAll

return Signal
end

-- ======================================================================
-- Core/Spring
__modules["Core/Spring"] = function()
-- Aether · Core/Spring
-- Analytic damped-spring animator. Every animated property in Aether goes
-- through here, so motion stays consistent and can be switched off globally.
--
--   Spring.animate(frame, "Bouncy", { Position = goal }, onComplete)
--   Spring.target(frame, dampingRatio, frequencyHz, { Size = goal })
--
-- Retargeting a property mid-flight keeps its velocity, so interrupted
-- animations never jump. Retargeting also cancels that property's pending
-- onComplete callback.

local Env = import("Core/Env")
local Log = import("Core/Log")

local RunService = Env.service("RunService")

local Spring = {}

-- When true, every animation jumps straight to its goal (reduced motion).
Spring.Instant = false

-- { damping ratio, frequency in Hz }
Spring.Presets = {
	Smooth = { 1, 3.2 }, -- calm, no overshoot
	Snappy = { 1, 5 }, -- fast, no overshoot
	Bouncy = { 0.62, 3.8 }, -- visible overshoot
	Gentle = { 0.8, 2.6 }, -- slight overshoot, slower
	Quick = { 1, 9 }, -- nearly instant
	Drag = { 1, 11 }, -- follows the pointer with a hint of smoothing
}

local TAU = math.pi * 2
local POSITION_EPSILON = 1e-3
local VELOCITY_EPSILON = 1e-2

local function clamp01(value)
	return math.clamp(value, 0, 1)
end

-- Each animatable type is flattened into a list of numbers and rebuilt after every step.
local codecs = {
	number = {
		pack = function(value)
			return { value }
		end,
		unpack = function(t)
			return t[1]
		end,
	},
	UDim = {
		pack = function(value)
			return { value.Scale, value.Offset }
		end,
		unpack = function(t)
			return UDim.new(t[1], t[2])
		end,
	},
	UDim2 = {
		pack = function(value)
			return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
		end,
		unpack = function(t)
			return UDim2.new(t[1], t[2], t[3], t[4])
		end,
	},
	Vector2 = {
		pack = function(value)
			return { value.X, value.Y }
		end,
		unpack = function(t)
			return Vector2.new(t[1], t[2])
		end,
	},
	Vector3 = {
		pack = function(value)
			return { value.X, value.Y, value.Z }
		end,
		unpack = function(t)
			return Vector3.new(t[1], t[2], t[3])
		end,
	},
	Color3 = {
		pack = function(value)
			return { value.R, value.G, value.B }
		end,
		unpack = function(t)
			return Color3.new(clamp01(t[1]), clamp01(t[2]), clamp01(t[3]))
		end,
	},
}

Spring.Animatable = {}
for kind in pairs(codecs) do
	Spring.Animatable[kind] = true
end

-- [Instance] = { [property] = state }
local active = {}
local connection = nil

-- Advances one spring by dt using the closed-form solution of a damped
-- harmonic oscillator, so it stays stable at any frame rate.
-- Returns true once every component has settled.
local function step(state, dt)
	local damping = state.damping
	local omega = state.frequency * TAU
	local position, velocity, goal = state.position, state.velocity, state.goal
	local settled = true

	if damping == 1 then
		local decay = math.exp(-omega * dt)
		for i = 1, #position do
			local x0 = position[i] - goal[i]
			local v0 = velocity[i]
			local c = v0 + omega * x0
			local x = decay * (x0 + c * dt)
			local v = decay * (v0 - omega * c * dt)
			position[i] = goal[i] + x
			velocity[i] = v
			if math.abs(x) > POSITION_EPSILON or math.abs(v) > VELOCITY_EPSILON then
				settled = false
			end
		end
	elseif damping < 1 then
		local alpha = omega * math.sqrt(1 - damping * damping)
		local decay = math.exp(-damping * omega * dt)
		local cosine = math.cos(alpha * dt)
		local sine = math.sin(alpha * dt)
		for i = 1, #position do
			local x0 = position[i] - goal[i]
			local v0 = velocity[i]
			local b = (v0 + damping * omega * x0) / alpha
			local x = decay * (x0 * cosine + b * sine)
			local v = decay * (v0 * cosine - sine * (x0 * alpha + damping * omega * b))
			position[i] = goal[i] + x
			velocity[i] = v
			if math.abs(x) > POSITION_EPSILON or math.abs(v) > VELOCITY_EPSILON then
				settled = false
			end
		end
	else
		local root = math.sqrt(damping * damping - 1)
		local r1 = -omega * (damping - root)
		local r2 = -omega * (damping + root)
		local e1 = math.exp(r1 * dt)
		local e2 = math.exp(r2 * dt)
		for i = 1, #position do
			local x0 = position[i] - goal[i]
			local v0 = velocity[i]
			local c2 = (v0 - r1 * x0) / (r2 - r1)
			local c1 = x0 - c2
			local x = c1 * e1 + c2 * e2
			local v = r1 * c1 * e1 + r2 * c2 * e2
			position[i] = goal[i] + x
			velocity[i] = v
			if math.abs(x) > POSITION_EPSILON or math.abs(v) > VELOCITY_EPSILON then
				settled = false
			end
		end
	end

	return settled
end

local function runCallback(callback)
	local ok, err = pcall(callback)
	if not ok then
		Log.error("Animation callback failed: " .. tostring(err))
	end
end

local function finish(state)
	local records = state.records
	state.records = nil
	if not records then
		return
	end
	for _, record in ipairs(records) do
		if not record.cancelled then
			record.remaining -= 1
			if record.remaining <= 0 then
				record.cancelled = true
				task.spawn(runCallback, record.callback)
			end
		end
	end
end

local function cancel(state)
	if state.records then
		for _, record in ipairs(state.records) do
			record.cancelled = true
		end
		state.records = nil
	end
end

local function setProperty(instance, name, value)
	instance[name] = value
end

local function onFrame(dt)
	-- Iterate over snapshots: callbacks and property-changed handlers may start new animations.
	local instances = {}
	for instance in pairs(active) do
		table.insert(instances, instance)
	end

	for _, instance in ipairs(instances) do
		local properties = active[instance]
		if properties then
			local names = {}
			for name in pairs(properties) do
				table.insert(names, name)
			end

			for _, name in ipairs(names) do
				local state = properties[name]
				if state then
					local settled = step(state, dt)
					local value = settled and state.goalValue or state.codec.unpack(state.position)
					local ok = pcall(setProperty, instance, name, value)
					if settled or not ok then
						properties[name] = nil
						finish(state)
					end
				end
			end

			if next(properties) == nil and active[instance] == properties then
				active[instance] = nil
			end
		end
	end

	if next(active) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Animates properties of an instance towards goals.
function Spring.target(instance, damping, frequency, goals, onComplete)
	assert(typeof(instance) == "Instance", "[Aether] Spring.target expects an Instance")
	damping = math.max(tonumber(damping) or 1, 0.05)
	frequency = math.max(tonumber(frequency) or 4, 0.05)

	if Spring.Instant then
		for property, goal in pairs(goals) do
			Spring.stop(instance, property)
			instance[property] = goal
		end
		if onComplete then
			task.defer(runCallback, onComplete)
		end
		return
	end

	local properties = active[instance]
	if not properties then
		properties = {}
		active[instance] = properties
	end

	local record = nil
	if onComplete then
		record = { remaining = 0, callback = onComplete, cancelled = false }
	end

	for property, goal in pairs(goals) do
		local kind = typeof(goal)
		local codec = codecs[kind]
		if not codec then
			error(("[Aether] Spring cannot animate %s (type %s)"):format(tostring(property), kind), 2)
		end

		local state = properties[property]
		if state and state.kind ~= kind then
			cancel(state)
			state = nil
		end

		if state then
			cancel(state)
		else
			local ok, current = pcall(function()
				return instance[property]
			end)
			if not ok or typeof(current) ~= kind then
				error(("[Aether] %s.%s cannot be animated to a %s"):format(instance.ClassName, tostring(property), kind), 2)
			end
			local position = codec.pack(current)
			state = {
				kind = kind,
				codec = codec,
				position = position,
				velocity = table.create(#position, 0),
			}
			properties[property] = state
		end

		state.goal = codec.pack(goal)
		state.goalValue = goal
		state.damping = damping
		state.frequency = frequency

		if record then
			record.remaining += 1
			state.records = { record }
		end
	end

	if record and record.remaining == 0 then
		task.defer(runCallback, onComplete)
	end

	if not connection then
		connection = RunService.Heartbeat:Connect(onFrame)
	end
end

-- Same as Spring.target, using a named preset from Spring.Presets.
function Spring.animate(instance, preset, goals, onComplete)
	local config = Spring.Presets[preset] or Spring.Presets.Snappy
	Spring.target(instance, config[1], config[2], goals, onComplete)
end

-- Stops animating one property (or every property) of an instance where it currently is.
function Spring.stop(instance, property)
	local properties = active[instance]
	if not properties then
		return
	end
	if property then
		local state = properties[property]
		if state then
			cancel(state)
			properties[property] = nil
		end
	else
		for _, state in pairs(properties) do
			cancel(state)
		end
		table.clear(properties)
	end
	if next(properties) == nil then
		active[instance] = nil
	end
end

function Spring.isAnimating(instance, property)
	local properties = active[instance]
	if not properties then
		return false
	end
	if property then
		return properties[property] ~= nil
	end
	return next(properties) ~= nil
end

function Spring.stopAll()
	for _, properties in pairs(active) do
		for _, state in pairs(properties) do
			cancel(state)
		end
	end
	table.clear(active)
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

return Spring
end

-- ======================================================================
-- Core/State
__modules["Core/State"] = function()
-- Aether · Core/State
-- Shared library state: current flag values, and the element that owns each flag.

return {
	Flags = {},
	Options = {},
}
end

-- ======================================================================
-- Core/Theme
__modules["Core/Theme"] = function()
-- Aether · Core/Theme
-- Instances bind their properties to theme tokens ("Accent", "TextDim"...).
-- Switching themes re-resolves every binding and springs to the new colours.
--
-- A token can be:
--   "Name"            a key of the current theme
--   function(theme)   computed from the current theme (gradients, sequences)
--   any other value   a literal (e.g. 1 for fully transparent)

local Signal = import("Core/Signal")
local Spring = import("Core/Spring")
local Log = import("Core/Log")

local Theme = {}

Theme.Changed = Signal.new("Theme.Changed")

local hex = Color3.fromHex

-- Tokens every theme provides. Missing keys fall back to the Aether theme.
local AETHER = {
	Accent = hex("#8B5CF6"),
	AccentSecondary = hex("#3B82F6"),
	OnAccent = hex("#FFFFFF"),

	Background = hex("#0D0D16"),
	BackgroundTransparency = 0.06,

	-- Cards and hover states are white washes over the background, which
	-- is what makes the window read as frosted glass.
	Element = hex("#FFFFFF"),
	ElementTransparency = 0.965,
	ElementHover = hex("#FFFFFF"),
	HoverTransparency = 0.945,
	IndicatorTransparency = 0.84,

	Control = hex("#2A2A3D"),

	Stroke = hex("#FFFFFF"),
	StrokeTransparency = 0.9,
	Divider = hex("#FFFFFF"),
	DividerTransparency = 0.93,

	Text = hex("#F4F4F8"),
	TextDim = hex("#A6A6BA"),
	TextMuted = hex("#6F6F86"),

	Success = hex("#22C55E"),
	Warning = hex("#F59E0B"),
	Danger = hex("#F43F5E"),

	Shadow = hex("#000000"),
	GlowTransparency = 0.82,
}

Theme.Presets = {
	Aether = AETHER,
	Midnight = {
		Accent = hex("#6366F1"),
		AccentSecondary = hex("#22D3EE"),
		Background = hex("#0A0E1A"),
	},
	Ocean = {
		Accent = hex("#22D3EE"),
		AccentSecondary = hex("#14B8A6"),
		OnAccent = hex("#04161A"),
		Background = hex("#07141A"),
	},
	Rose = {
		Accent = hex("#F43F5E"),
		AccentSecondary = hex("#FB923C"),
		Background = hex("#150B0F"),
	},
	Emerald = {
		Accent = hex("#10B981"),
		AccentSecondary = hex("#84CC16"),
		OnAccent = hex("#04150E"),
		Background = hex("#08130F"),
	},
	Mono = {
		Accent = hex("#FAFAFA"),
		AccentSecondary = hex("#A1A1AA"),
		OnAccent = hex("#0B0B0C"),
		Background = hex("#0B0B0C"),
		GlowTransparency = 0.9,
	},
	Light = {
		Accent = hex("#7C3AED"),
		AccentSecondary = hex("#2563EB"),
		Background = hex("#F5F5FA"),
		BackgroundTransparency = 0.04,
		Element = hex("#FFFFFF"),
		ElementTransparency = 0.25,
		ElementHover = hex("#000000"),
		HoverTransparency = 0.95,
		IndicatorTransparency = 0.88,
		Control = hex("#DCDCE6"),
		Stroke = hex("#000000"),
		StrokeTransparency = 0.9,
		Divider = hex("#000000"),
		DividerTransparency = 0.92,
		Text = hex("#15151D"),
		TextDim = hex("#565669"),
		TextMuted = hex("#8C8C9E"),
		Shadow = hex("#1B1B3A"),
		GlowTransparency = 0.86,
	},
}

local function merge(base, overrides)
	local result = table.clone(base)
	for key, value in pairs(overrides) do
		result[key] = value
	end
	return result
end

local current = table.clone(AETHER)
Theme.Name = "Aether"

-- [Instance] = { [property] = token }
local bindings = {}

local function resolve(token)
	local kind = type(token)
	if kind == "string" then
		local value = current[token]
		if value == nil then
			error(("[Aether] Unknown theme token '%s'"):format(token), 3)
		end
		return value
	elseif kind == "function" then
		return token(current)
	end
	return token
end

Theme.resolve = resolve

function Theme.get(token)
	return resolve(token)
end

function Theme.current()
	return table.clone(current)
end

local function entryFor(instance)
	local entry = bindings[instance]
	if not entry then
		entry = {}
		bindings[instance] = entry
		instance.Destroying:Connect(function()
			bindings[instance] = nil
		end)
	end
	return entry
end

-- Binds properties to tokens and applies them immediately.
function Theme.bind(instance, map)
	local entry = entryFor(instance)
	for property, token in pairs(map) do
		entry[property] = token
		instance[property] = resolve(token)
	end
	return instance
end

-- Rebinds properties to new tokens and springs to their values (hover, active states...).
function Theme.animate(instance, map, preset)
	local entry = entryFor(instance)
	local goals = nil
	for property, token in pairs(map) do
		entry[property] = token
		local value = resolve(token)
		if Spring.Animatable[typeof(value)] then
			goals = goals or {}
			goals[property] = value
		else
			Spring.stop(instance, property)
			instance[property] = value
		end
	end
	if goals then
		Spring.animate(instance, preset or "Snappy", goals)
	end
	return instance
end

function Theme.unbind(instance, property)
	local entry = bindings[instance]
	if not entry then
		return
	end
	if property then
		entry[property] = nil
	else
		bindings[instance] = nil
	end
end

-- Switches theme. `theme` is a preset name, or a table of overrides applied
-- on top of the current theme. Returns true on success.
function Theme.set(theme, animate)
	if type(theme) == "string" then
		local preset = Theme.Presets[theme]
		if not preset then
			Log.warn(("Unknown theme '%s'. Available: %s"):format(tostring(theme), table.concat(Theme.names(), ", ")))
			return false
		end
		current = merge(AETHER, preset)
		Theme.Name = theme
	elseif type(theme) == "table" then
		current = merge(current, theme)
		Theme.Name = type(theme.Name) == "string" and theme.Name or "Custom"
	else
		return false
	end

	for instance, entry in pairs(bindings) do
		local goals = nil
		for property, token in pairs(entry) do
			local ok, value = pcall(resolve, token)
			if ok then
				if animate and Spring.Animatable[typeof(value)] then
					goals = goals or {}
					goals[property] = value
				else
					Spring.stop(instance, property)
					pcall(function()
						instance[property] = value
					end)
				end
			end
		end
		if goals then
			pcall(Spring.animate, instance, "Smooth", goals)
		end
	end

	Theme.Changed:Fire(Theme.Name)
	return true
end

function Theme.register(name, theme)
	assert(type(name) == "string" and type(theme) == "table", "[Aether] Theme.register(name, table)")
	Theme.Presets[name] = theme
end

function Theme.names()
	local names = {}
	for name in pairs(Theme.Presets) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function Theme.clear()
	table.clear(bindings)
end

---------------------------------------------------------------------------
-- Computed tokens shared by several components
---------------------------------------------------------------------------

function Theme.accentSequence(theme)
	return ColorSequence.new(theme.Accent, theme.AccentSecondary)
end

return Theme
end

-- ======================================================================
-- Core/Util
__modules["Core/Util"] = function()
-- Aether · Core/Util
-- Instance creation, layout helpers, fonts, pointer and drag handling, and
-- asset-free vector glyphs.

local Env = import("Core/Env")
local Theme = import("Core/Theme")

local UserInputService = Env.service("UserInputService")
local GuiService = Env.service("GuiService")

local Util = {}

---------------------------------------------------------------------------
-- Fonts: Builder Sans (Roblox's modern UI font), with Gotham as a fallback.
---------------------------------------------------------------------------

local family = "rbxasset://fonts/families/GothamSSm.json"
pcall(function()
	family = Font.fromEnum(Enum.Font.BuilderSans).Family
end)

local monoFamily = "rbxasset://fonts/families/RobotoMono.json"
pcall(function()
	monoFamily = Font.fromEnum(Enum.Font.RobotoMono).Family
end)

Util.Fonts = {
	Regular = Font.new(family, Enum.FontWeight.Regular),
	Medium = Font.new(family, Enum.FontWeight.Medium),
	SemiBold = Font.new(family, Enum.FontWeight.SemiBold),
	Bold = Font.new(family, Enum.FontWeight.Bold),
	Mono = Font.new(monoFamily, Enum.FontWeight.Regular),
}

---------------------------------------------------------------------------
-- Instance creation
---------------------------------------------------------------------------

local CLASS_DEFAULTS = {
	Frame = {
		BorderSizePixel = 0,
	},
	CanvasGroup = {
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
	},
	ScrollingFrame = {
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = 0.4,
	},
	TextLabel = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = Util.Fonts.Regular,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	},
	TextButton = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		FontFace = Util.Fonts.Medium,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "",
	},
	TextBox = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		FontFace = Util.Fonts.Regular,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		PlaceholderText = "",
	},
	ImageLabel = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	},
	ImageButton = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
	},
}

-- Util.create("Frame", { Size = ..., Theme = { BackgroundColor3 = "Accent" }, Parent = x }, { children })
-- Parent is assigned last so the instance is fully set up before it appears.
function Util.create(className, properties, children)
	local instance = Instance.new(className)

	local defaults = CLASS_DEFAULTS[className]
	if defaults then
		for key, value in pairs(defaults) do
			instance[key] = value
		end
	end

	local parent, themed = nil, nil
	if properties then
		for key, value in pairs(properties) do
			if key == "Parent" then
				parent = value
			elseif key == "Theme" then
				themed = value
			else
				instance[key] = value
			end
		end
	end

	if themed then
		Theme.bind(instance, themed)
	end

	if children then
		for _, child in ipairs(children) do
			child.Parent = instance
		end
	end

	if parent then
		instance.Parent = parent
	end

	return instance
end

function Util.corner(radius)
	return Util.create("UICorner", {
		CornerRadius = radius == "full" and UDim.new(1, 0) or UDim.new(0, radius or 8),
	})
end

function Util.padding(top, right, bottom, left)
	right = right or top
	bottom = bottom or top
	left = left or right
	return Util.create("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right),
		PaddingBottom = UDim.new(0, bottom),
		PaddingLeft = UDim.new(0, left),
	})
end

function Util.list(padding, direction, verticalAlignment, horizontalAlignment)
	return Util.create("UIListLayout", {
		Padding = UDim.new(0, padding or 0),
		FillDirection = direction or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = verticalAlignment or Enum.VerticalAlignment.Top,
		HorizontalAlignment = horizontalAlignment or Enum.HorizontalAlignment.Left,
	})
end

function Util.stroke(colorToken, transparencyToken, thickness)
	return Util.create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness = thickness or 1,
		Theme = {
			Color = colorToken or "Stroke",
			Transparency = transparencyToken or "StrokeTransparency",
		},
	})
end

---------------------------------------------------------------------------
-- Options: every constructor accepts ("Name", { ... }) or ({ Name = ..., ... }).
---------------------------------------------------------------------------

function Util.options(first, second)
	local options = {}
	if type(first) == "table" then
		for key, value in pairs(first) do
			options[key] = value
		end
	elseif first ~= nil then
		options.Name = tostring(first)
	end
	if type(second) == "table" then
		for key, value in pairs(second) do
			options[key] = value
		end
	end
	-- Friendly aliases used by other popular libraries.
	if options.Name == nil and options.Title ~= nil then
		options.Name = tostring(options.Title)
	end
	if options.Description == nil and options.Desc ~= nil then
		options.Description = options.Desc
	end
	return options
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------

function Util.isTouch()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Pointer position in the same space as AbsolutePosition inside a
-- ScreenGui with IgnoreGuiInset = true.
function Util.pointer(input)
	if input and input.UserInputType == Enum.UserInputType.Touch then
		local inset = GuiService:GetGuiInset()
		return Vector2.new(input.Position.X, input.Position.Y) + inset
	end
	return UserInputService:GetMouseLocation()
end

local function isPress(input)
	local kind = input.UserInputType
	return kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
end

Util.isPress = isPress

-- Tracks a press on `handle` and reports pointer movement until release.
--   callbacks.Start(input) -> return false to ignore this press
--   callbacks.Move(delta, pointer)
--   callbacks.End()
function Util.draggable(handle, callbacks, maid)
	local activeInput = nil
	local startPointer = nil

	local function finish()
		if not activeInput then
			return
		end
		activeInput = nil
		if callbacks.End then
			callbacks.End()
		end
	end

	maid:Give(handle.InputBegan:Connect(function(input)
		if activeInput or not isPress(input) then
			return
		end
		if callbacks.Start and callbacks.Start(input) == false then
			return
		end
		activeInput = input
		startPointer = Util.pointer(input)

		local changed
		changed = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				changed:Disconnect()
				if activeInput == input then
					finish()
				end
			end
		end)
	end))

	maid:Give(UserInputService.InputChanged:Connect(function(input)
		if not activeInput then
			return
		end
		if activeInput.UserInputType == Enum.UserInputType.Touch then
			if input ~= activeInput then
				return
			end
		elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		local pointer = Util.pointer(input)
		callbacks.Move(pointer - startPointer, pointer)
	end))

	maid:Give(UserInputService.InputEnded:Connect(function(input)
		if not activeInput then
			return
		end
		if input == activeInput or (input.UserInputType == Enum.UserInputType.MouseButton1 and activeInput.UserInputType == Enum.UserInputType.MouseButton1) then
			finish()
		end
	end))
end

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------

-- First visible character of a string (UTF-8 safe), upper-cased.
function Util.initial(text)
	local first = string.match(tostring(text or ""), "[%w]") or string.match(tostring(text or ""), utf8.charpattern) or "?"
	return string.upper(first)
end

local KEY_NAMES = {
	RightControl = "RightCtrl",
	LeftControl = "LeftCtrl",
	RightShift = "RightShift",
	LeftShift = "LeftShift",
	RightAlt = "RightAlt",
	LeftAlt = "LeftAlt",
	Return = "Enter",
	MouseButton1 = "MB1",
	MouseButton2 = "MB2",
	MouseButton3 = "MB3",
}

function Util.keyName(key)
	if typeof(key) ~= "EnumItem" then
		return tostring(key)
	end
	return KEY_NAMES[key.Name] or key.Name
end

---------------------------------------------------------------------------
-- Glyphs: small vector icons drawn with frames. No image assets, so they
-- are always crisp, always load, and follow the theme.
---------------------------------------------------------------------------

local function bar(parent, length, thickness, position, rotation, color)
	return Util.create("Frame", {
		Name = "Stroke",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(length, thickness),
		Rotation = rotation,
		Theme = { BackgroundColor3 = color },
		Parent = parent,
	}, { Util.corner("full") })
end

local function dot(parent, size, position, color)
	return Util.create("Frame", {
		Name = "Stroke",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(size, size),
		Theme = { BackgroundColor3 = color },
		Parent = parent,
	}, { Util.corner("full") })
end

-- Util.glyph("chevron-right", { Size = 14, Color = "TextDim", Thickness = 2 })
function Util.glyph(kind, options)
	options = options or {}
	local size = options.Size or 16
	local color = options.Color or "TextDim"
	local thickness = options.Thickness or 2

	local container = Util.create("Frame", {
		Name = "Glyph",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
	})

	local function at(x, y)
		return UDim2.new(0.5, x, 0.5, y)
	end

	if kind == "minus" then
		bar(container, math.floor(size * 0.72), thickness, at(0, 0), 0, color)
	elseif kind == "plus" then
		bar(container, math.floor(size * 0.72), thickness, at(0, 0), 0, color)
		bar(container, math.floor(size * 0.72), thickness, at(0, 0), 90, color)
	elseif kind == "close" then
		local length = math.floor(size * 0.8)
		bar(container, length, thickness, at(0, 0), 45, color)
		bar(container, length, thickness, at(0, 0), -45, color)
	elseif kind == "chevron-right" or kind == "chevron-down" then
		local length = size * 0.5
		local offset = length * 0.34
		if kind == "chevron-right" then
			bar(container, length, thickness, at(0, -offset), 45, color)
			bar(container, length, thickness, at(0, offset), -45, color)
		else
			bar(container, length, thickness, at(-offset, 0), 45, color)
			bar(container, length, thickness, at(offset, 0), -45, color)
		end
	elseif kind == "check" then
		bar(container, size * 0.34, thickness, at(-size * 0.2, size * 0.06), 45, color)
		bar(container, size * 0.62, thickness, at(size * 0.1, -size * 0.04), -50, color)
	elseif kind == "diamond" then
		Util.create("Frame", {
			Name = "Stroke",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = at(0, 0),
			Size = UDim2.fromOffset(math.floor(size * 0.62), math.floor(size * 0.62)),
			Rotation = 45,
			Theme = { BackgroundColor3 = color },
			Parent = container,
		}, { Util.corner(2) })
	elseif kind == "search" then
		local ring = math.floor(size * 0.62)
		Util.create("Frame", {
			Name = "Ring",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = at(-size * 0.08, -size * 0.08),
			Size = UDim2.fromOffset(ring, ring),
			BackgroundTransparency = 1,
			Parent = container,
		}, {
			Util.corner("full"),
			Util.create("UIStroke", { Name = "Ring", Thickness = thickness, Theme = { Color = color } }),
		})
		bar(container, size * 0.3, thickness, at(size * 0.3, size * 0.3), 45, color)
	elseif kind == "grip" then
		local gap = size / 3
		for row = 0, 2 do
			for column = 0, 2 - row do
				dot(container, 2, UDim2.fromOffset(size - gap * column - 1, size - gap * row - 1), color)
			end
		end
	end

	return container
end

-- Springs every stroke of a glyph to a new colour token.
function Util.glyphColor(glyph, token)
	for _, part in ipairs(glyph:GetDescendants()) do
		if part:IsA("Frame") and part.Name == "Stroke" then
			Theme.animate(part, { BackgroundColor3 = token })
		elseif part:IsA("UIStroke") and part.Name == "Ring" then
			Theme.animate(part, { Color = token })
		end
	end
end

return Util
end

-- ======================================================================
-- Elements/Button
__modules["Elements/Button"] = function()
-- Aether · Elements/Button
--   Tab:Button({ Name = "Rejoin", Description = "...", Callback = fn })
--   Tab:Button("Rejoin"):OnClick(fn)

local Util = import("Core/Util")
local Spring = import("Core/Spring")
local Element = import("Components/Element")
local Elements = import("Components/Elements")

local Button = Element.extend("Button")

function Button.new(section, options)
	local self = setmetatable({}, Button)
	Element.init(self, section, options, {
		Interactive = true,
		ControlWidth = 16,
		ControlHeight = 16,
	})
	self.Clicked = self.Changed

	local chevron = Util.glyph("chevron-right", { Size = 14, Color = "TextMuted" })
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.fromScale(1, 0.5)
	chevron.Parent = self.Control
	self._chevron = chevron

	self.Maid:Give(self.Hitbox.InputBegan:Connect(function(input)
		if Util.isPress(input) and not self.Disabled then
			self:_ripple(input)
		end
	end))
	self.Maid:Give(self.Hitbox.Activated:Connect(function()
		self:Press()
	end))

	return self:_ready()
end

-- Runs the callbacks as if the button was clicked.
function Button:Press()
	if not self.Disabled and not self.Destroyed then
		self.Changed:Fire()
	end
	return self
end

function Button:OnClick(handler)
	return self:OnChanged(handler)
end

function Button:_onHover(hovered)
	Util.glyphColor(self._chevron, hovered and "Text" or "TextMuted")
	Spring.animate(self._chevron, "Bouncy", { Position = UDim2.new(1, hovered and 3 or 0, 0.5, 0) })
end

Elements.register("Button", Button)

return Button
end

-- ======================================================================
-- Elements/Label
__modules["Elements/Label"] = function()
-- Aether · Elements/Label
--   Tab:Label("Status: ready")   label:SetText("Status: running")

local Util = import("Core/Util")
local Element = import("Components/Element")
local Elements = import("Components/Elements")

local Label = Element.extend("Label")

function Label.new(section, options)
	local self = setmetatable({}, Label)
	Element.init(self, section, options, {
		Height = 34,
		PaddingY = 8,
		TitleFont = Util.Fonts.Regular,
		TitleColor = "TextDim",
	})
	return self:_ready()
end

function Label:SetText(text)
	return self:SetTitle(text)
end

Label.Set = Label.SetText

Elements.register("Label", Label)

return Label
end

-- ======================================================================
-- Elements/Paragraph
__modules["Elements/Paragraph"] = function()
-- Aether · Elements/Paragraph
--   Tab:Paragraph({ Title = "Welcome", Content = "Thanks for using my script." })

local Util = import("Core/Util")
local Element = import("Components/Element")
local Elements = import("Components/Elements")

local Paragraph = Element.extend("Paragraph")

function Paragraph.new(section, options)
	if options.Description == nil then
		options.Description = options.Content or options.Text
	end
	local self = setmetatable({}, Paragraph)
	Element.init(self, section, options, {
		PaddingY = 11,
		TitleFont = Util.Fonts.SemiBold,
		DescriptionSize = 13,
	})
	return self:_ready()
end

function Paragraph:SetContent(text)
	return self:SetDescription(text)
end

-- paragraph:Set({ Title = "...", Content = "..." }) or paragraph:Set("new content")
function Paragraph:Set(data)
	if type(data) == "table" then
		if data.Title ~= nil then
			self:SetTitle(data.Title)
		end
		if data.Content ~= nil then
			self:SetContent(data.Content)
		end
	else
		self:SetContent(data)
	end
	return self
end

Elements.register("Paragraph", Paragraph)

return Paragraph
end

-- ======================================================================
-- init
__modules["init"] = function()
-- Aether UI Library · entry point
--
--   local Aether = loadstring(game:HttpGet(url))()
--   local Window = Aether:Window({ Name = "My Script", Subtitle = "v1.0" })
--   local Main = Window:Tab({ Name = "Main", Icon = "home" })
--   Main:Button("Hello", { Callback = function() print("hi") end })

local Env = import("Core/Env")
local Log = import("Core/Log")
local Signal = import("Core/Signal")
local Spring = import("Core/Spring")
local Theme = import("Core/Theme")
local Icons = import("Core/Icons")
local Util = import("Core/Util")
local State = import("Core/State")
local Elements = import("Components/Elements")
local Window = import("Components/Window")

-- Built-in elements register themselves when loaded.
import("Elements/Label")
import("Elements/Paragraph")
import("Elements/Button")

local Aether = {
	Version = "0.1.0",
	Flags = State.Flags,
	Options = State.Options,
	Windows = {},
	Unloaded = Signal.new("Aether.Unloaded"),
	IsUnloaded = false,

	-- Advanced: the building blocks, for custom elements and effects.
	Env = Env,
	Log = Log,
	Spring = Spring,
	Theme = Theme,
	Icons = Icons,
	Util = Util,
}

function Aether:Window(first, second)
	local window = Window.new(self, Util.options(first, second))
	table.insert(self.Windows, window)
	return window
end

Aether.CreateWindow = Aether.Window

-- Aether:SetTheme("Ocean") or Aether:SetTheme({ Accent = Color3.fromRGB(255, 120, 80) })
function Aether:SetTheme(theme)
	Theme.set(theme, true)
	return self
end

function Aether:GetThemes()
	return Theme.names()
end

function Aether:RegisterTheme(name, theme)
	Theme.register(name, theme)
	return self
end

-- Adds a custom element type: every tab and section gets a :<name>() method.
function Aether:RegisterElement(name, class)
	Elements.register(name, class)
	return self
end

Aether.Element = import("Components/Element")

-- Turns every animation off (accessibility / low-end devices).
function Aether:SetReducedMotion(enabled)
	Spring.Instant = enabled == true
	return self
end

-- Removes every window and disconnects everything Aether created.
function Aether:Unload()
	if self.IsUnloaded then
		return
	end
	self.IsUnloaded = true
	for _, window in ipairs(table.clone(self.Windows)) do
		window:Destroy()
	end
	table.clear(self.Windows)
	Spring.stopAll()
	Theme.clear()
	self.Unloaded:Fire()
end

Aether.Destroy = Aether.Unload

return Aether
end

return import("init")

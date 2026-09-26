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
-- control slot, optional collapsible panel), hover/press feedback, flags,
-- config ids, visibility, disabled state, tooltips, the right-click /
-- long-press menu, drag-out-to-pin, and the chainable helpers:
--
--   Tab:Button("Rejoin"):Description("Reconnects to this server"):OnClick(fn)

local Env = import("Core/Env")
local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Spring = import("Core/Spring")
local Signal = import("Core/Signal")
local Maid = import("Core/Maid")
local State = import("Core/State")

local UserInputService = Env.service("UserInputService")

local LONG_PRESS = 0.45
local DRAG_THRESHOLD = 14

local Element = {}
Element.__index = Element

-- Class capabilities (subclasses override).
Element.Saveable = false -- has a value that configs store
Element.Pinnable = false -- can become a floating widget
Element.Bindable = false -- can get a key bind from the context menu

-- Creates a subclass: local Toggle = Element.extend("Toggle")
function Element.extend(className)
	local class = setmetatable({}, { __index = Element })
	class.__index = class
	class.ClassName = className
	return class
end

--[[ config:
	Clickable      the header acts as a button (hover, ripple, self:_onClick())
	Hover          highlight on hover (default: true when Clickable)
	ControlWidth   width of the control slot on the right (inline layout)
	ControlHeight  height of the control slot
	Stacked        control sits under the text, full width (sliders)
	Aside          width of a slot to the right of the title (stacked layout)
	Panel          adds a collapsible panel under the header (dropdowns, pickers)
	NoText         no title/description block
	Height, PaddingY, TitleFont, TitleColor, DescriptionSize
]]
function Element.init(self, section, options, config)
	config = config or {}
	local class = getmetatable(self)
	local window = section.Window

	self.Type = class.ClassName
	self.Name = options.Name or self.Type
	self.Section = section
	self.Tab = section.Tab
	self.Window = window
	self.Library = section.Library
	self.Options = options
	self.Maid = Maid.new()
	self.Changed = Signal.new(("%s '%s'"):format(self.Type, self.Name))
	self.Disabled = false
	self.Visible = true
	self.Destroyed = false

	self._flag = options.Flag
	self._autoId = table.concat({ section.Tab.Name, section.Name or "", self.Name }, "/")
	self._tooltip = options.Tooltip
	self._hovered = false
	self._save = options.Save ~= false

	local touch = window.IsTouch
	local minHeight = config.Height or (touch and 46 or 40)
	local paddingY = config.PaddingY or 9
	local stacked = config.Stacked == true

	local row = Util.create("Frame", {
		Name = self.Name,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "ElementHover" },
	}, {
		Util.corner(8),
		Util.list(0),
	})
	self.Frame = row

	local main = Util.create("Frame", {
		Name = "Main",
		Size = UDim2.new(1, 0, 0, minHeight),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		LayoutOrder = 1,
		Parent = row,
	})
	self.Main = main

	if config.Clickable then
		self.Hitbox = Util.create("TextButton", {
			Name = "Hitbox",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
			Parent = main,
		})
		self.Maid:Give(self.Hitbox.Activated:Connect(function()
			if self._suppressClick then
				self._suppressClick = false
				return
			end
			if not self.Disabled and self._onClick then
				self:_onClick()
			end
		end))
		self.Maid:Give(self.Hitbox.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 and not self.Disabled then
				self:_ripple(input)
			end
		end))
	end

	local inner = Util.create("Frame", {
		Name = "Inner",
		Size = UDim2.new(1, 0, 0, minHeight),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = main,
	}, {
		Util.padding(paddingY, 12, paddingY, 12),
		Util.list(
			stacked and 8 or 10,
			stacked and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal,
			Enum.VerticalAlignment.Center
		),
	})
	self.Inner = inner

	-- Text block (title + description). In the stacked layout it shares a
	-- header row with the optional aside slot.
	local textParent = inner
	if stacked and not config.NoText then
		textParent = Util.create("Frame", {
			Name = "Header",
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Parent = inner,
		}, { Util.list(10, Enum.FillDirection.Horizontal, Enum.VerticalAlignment.Center) })
	end

	self._controlWidth = config.ControlWidth or 0
	self._asideWidth = config.Aside or 0
	self._stacked = stacked

	if not config.NoText then
		local text = Util.create("Frame", {
			Name = "Text",
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Parent = textParent,
		}, { Util.list(2) })
		self.TextBlock = text

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

		if stacked and self._asideWidth > 0 then
			self.Aside = Util.create("Frame", {
				Name = "Aside",
				Size = UDim2.fromOffset(self._asideWidth, 24),
				BackgroundTransparency = 1,
				LayoutOrder = 2,
				Parent = textParent,
			})
		end
	end

	if stacked or self._controlWidth > 0 then
		self.Control = Util.create("Frame", {
			Name = "Control",
			Size = stacked and UDim2.new(1, 0, 0, config.ControlHeight or 24)
				or UDim2.fromOffset(self._controlWidth, config.ControlHeight or 24),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Parent = inner,
		})
	end
	self:_layoutText()

	if config.Panel then
		self.Panel = Util.create("Frame", {
			Name = "Panel",
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			LayoutOrder = 2,
			Parent = row,
		})
		self.PanelInner = Util.create("Frame", {
			Name = "Inner",
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = self.Panel,
		}, {
			Util.padding(0, 12, 10, 12),
			Util.list(6),
		})
		self.Expanded = false
	end

	-- Hover, tooltip, context menu, long press and drag-to-pin.
	local hover = config.Hover
	if hover == nil then
		hover = config.Clickable == true
	end
	self._hover = hover
	self.Maid:Give(row.MouseEnter:Connect(function()
		self:_setHovered(true)
	end))
	self.Maid:Give(row.MouseLeave:Connect(function()
		self:_setHovered(false)
	end))
	self:_bindGestures(self.Hitbox or self.TextBlock or main)

	section:_add(self)
	window:_registerElement(self)

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
	self.Window:_elementReady(self)
	return self
end

-- Keeps the text block from overlapping the control/aside slots.
function Element:_layoutText()
	local text = self.TextBlock
	if not text then
		if self.Control and not self._stacked then
			self.Control.Size = UDim2.new(1, 0, 0, self.Control.Size.Y.Offset)
		end
		return
	end
	local reserved = 0
	if self._stacked then
		reserved = self._asideWidth > 0 and self._asideWidth + 10 or 0
	elseif self._controlWidth > 0 then
		reserved = self._controlWidth + 10
	end
	text.Size = UDim2.new(1, -reserved, 0, 0)
end

-- Resizes the inline control slot (e.g. when a key chip appears).
function Element:_setControlWidth(width)
	self._controlWidth = width
	if self.Control and not self._stacked then
		self.Control.Size = UDim2.fromOffset(width, self.Control.Size.Y.Offset)
	end
	self:_layoutText()
end

---------------------------------------------------------------------------
-- Feedback
---------------------------------------------------------------------------

function Element:_setHovered(hovered)
	self._hovered = hovered
	local show = hovered and self._hover and not self.Disabled
	Theme.animate(self.Frame, { BackgroundTransparency = show and "HoverTransparency" or 1 })
	if self._onHover then
		self:_onHover(hovered and not self.Disabled)
	end
	if hovered then
		self.Window:_scheduleTooltip(self)
	else
		self.Window:_hideTooltip(self)
	end
end

function Element:_tooltipText()
	if self.Disabled and self._disabledReason then
		return self._disabledReason
	end
	return self._tooltip
end

-- Expanding circle from the press point, clipped by the header.
function Element:_ripple(input)
	local main = self.Main
	local position, size = main.AbsolutePosition, main.AbsoluteSize
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
		BackgroundTransparency = 0.82,
		ZIndex = 1,
		Theme = { BackgroundColor3 = "Accent" },
		Parent = main,
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

-- Briefly highlights the row (used by the command palette's "reveal").
function Element:Flash()
	local row = self.Frame
	Theme.animate(row, { BackgroundColor3 = "Accent", BackgroundTransparency = 0.8 }, "Quick")
	task.delay(0.35, function()
		if not self.Destroyed then
			Theme.animate(row, { BackgroundColor3 = "ElementHover", BackgroundTransparency = 1 }, "Smooth")
		end
	end)
	return self
end

---------------------------------------------------------------------------
-- Gestures: right-click / long-press menu and drag-out-to-pin
---------------------------------------------------------------------------

function Element:_bindGestures(target)
	local pressInput, pressStart, longPressThread, dragging = nil, nil, nil, false

	local function cancelLongPress()
		if longPressThread then
			pcall(task.cancel, longPressThread)
			longPressThread = nil
		end
	end

	self.Maid:Give(target.InputBegan:Connect(function(input)
		if self.Destroyed then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton2 then
			self.Window:_openContextMenu(self, Util.pointer(input))
		elseif kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			pressInput = input
			pressStart = Util.pointer(input)
			dragging = false
			if kind == Enum.UserInputType.Touch then
				cancelLongPress()
				longPressThread = task.delay(LONG_PRESS, function()
					longPressThread = nil
					if pressInput == input and not dragging and not self.Destroyed then
						self._suppressClick = true
						self.Window:_openContextMenu(self, pressStart)
					end
				end)
			end
		end
	end))

	self.Maid:Give(UserInputService.InputChanged:Connect(function(input)
		if not pressInput then
			return
		end
		local isTouch = pressInput.UserInputType == Enum.UserInputType.Touch
		if isTouch and input ~= pressInput then
			return
		elseif not isTouch and input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		local pointer = Util.pointer(input)
		if not dragging and (pointer - pressStart).Magnitude > DRAG_THRESHOLD then
			cancelLongPress()
			-- Only mouse drags pin; on touch a moving finger means scrolling.
			if not isTouch and self.Pinnable and not self.Disabled then
				dragging = true
				self._suppressClick = true
				self.Window:_beginPinDrag(self, pointer)
			else
				pressInput = nil
			end
		elseif dragging then
			self.Window:_updatePinDrag(self, pointer)
		end
	end))

	self.Maid:Give(UserInputService.InputEnded:Connect(function(input)
		if not pressInput then
			return
		end
		local matches = input == pressInput
			or (input.UserInputType == Enum.UserInputType.MouseButton1 and pressInput.UserInputType == Enum.UserInputType.MouseButton1)
		if not matches then
			return
		end
		cancelLongPress()
		pressInput = nil
		if dragging then
			dragging = false
			self.Window:_endPinDrag(self, Util.pointer(input))
			-- Activated may not fire after a drag; don't swallow the next real click.
			task.defer(function()
				self._suppressClick = false
			end)
		end
	end))
end

---------------------------------------------------------------------------
-- Values, flags and configs
---------------------------------------------------------------------------

-- Stores the value under this element's flag (Aether.Flags[flag]).
function Element:_publish(value)
	self.Value = value
	self.CurrentValue = value -- Rayfield's name for it
	if self._flag then
		State.Flags[self._flag] = value
		State.Options[self._flag] = self
	end
end

-- Stable id used by configs and pinned widgets: the flag, or "Tab/Section/Name".
function Element:GetId()
	return self._flag or self._autoId
end

-- JSON-safe form of the value (overridden by elements with rich values).
function Element:_serialize()
	return self.Value
end

function Element:_deserialize(data)
	if self.Set then
		self:Set(data, false, true)
	end
end

-- Human-readable value (command palette, "Copy value").
function Element:_display()
	local value = self.Value
	if value == nil then
		return ""
	end
	return tostring(value)
end

function Element:Reset()
	if self._default ~= nil and self.Set then
		self:Set(self._default)
	end
	return self
end

---------------------------------------------------------------------------
-- Collapsible panel (dropdowns, color pickers)
---------------------------------------------------------------------------

function Element:_setExpanded(expanded, height)
	if not self.Panel then
		return
	end
	self.Expanded = expanded == true
	local goal = UDim2.new(1, 0, 0, self.Expanded and height or 0)
	Spring.animate(self.Panel, self.Expanded and "Gentle" or "Snappy", { Size = goal })
	if self._onExpanded then
		self:_onExpanded(self.Expanded)
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
	-- The id changed: saved values and pins for the new id apply now.
	self.Window:_elementReady(self)
	return self
end

function Element:SetTitle(text)
	self.Name = tostring(text)
	if self.TitleLabel then
		self.TitleLabel.Text = self.Name
	end
	self.Window:_elementText(self)
	return self
end

function Element:SetDescription(text)
	local label = self.DescriptionLabel
	if label then
		label.Text = text and tostring(text) or ""
		label.Visible = text ~= nil and text ~= ""
	end
	self.Window:_elementText(self)
	return self
end

-- Pins this element as a floating widget (position in screen pixels, optional).
function Element:Pin(position)
	self.Window:Pin(self, position)
	return self
end

function Element:Unpin()
	self.Window:Unpin(self)
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
	local transparency = self.Disabled and 0.5 or 0
	if self.TitleLabel then
		Spring.animate(self.TitleLabel, "Snappy", { TextTransparency = transparency })
		Spring.animate(self.DescriptionLabel, "Snappy", { TextTransparency = transparency })
	end

	-- A transparent button over the header swallows clicks while disabled.
	if self.Disabled and not self._blocker then
		self._blocker = Util.create("TextButton", {
			Name = "Blocker",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 10,
			Parent = self.Main,
		})
	end
	if self._blocker then
		self._blocker.Visible = self.Disabled
	end
	if self.Control then
		for _, part in ipairs(self.Control:GetDescendants()) do
			if part:IsA("GuiButton") or part:IsA("TextBox") then
				part.Active = not self.Disabled
			end
		end
	end
	if self.Disabled and self.Expanded then
		self:_setExpanded(false, 0)
	end
	if self._hovered then
		self:_setHovered(true)
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
	self.Window:_unregisterElement(self)
	self.Maid:Clean()
	self.Changed:DisconnectAll()
	self.Section:_remove(self)
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
	host.class[name] = function(self, first, second)
		return class.new(host.resolve(self), Util.options(first, second))
	end
	-- Create* keeps Rayfield's callback shapes for scripts that are switching over.
	host.class["Create" .. name] = function(self, first, second)
		local options = Util.options(first, second)
		options.__compat = "Rayfield"
		return class.new(host.resolve(self), options)
	end
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
-- Components/KeyChip
__modules["Components/KeyChip"] = function()
-- Aether · Components/KeyChip
-- The small key badge used by toggles, buttons and the Keybind element.
-- Click it to rebind: the next key press becomes the bind, Escape cancels,
-- Backspace clears. Also watches the bound key and reports presses.

local Env = import("Core/Env")
local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Spring = import("Core/Spring")

local UserInputService = Env.service("UserInputService")
local TextService = Env.service("TextService")

local KeyChip = {}
KeyChip.__index = KeyChip

-- The chip currently waiting for a key, if any (binds are paused meanwhile).
KeyChip.Listening = nil

local ALIASES = {
	ctrl = "LeftControl",
	control = "LeftControl",
	rightctrl = "RightControl",
	leftctrl = "LeftControl",
	shift = "LeftShift",
	alt = "LeftAlt",
	enter = "Return",
	esc = "Escape",
	del = "Delete",
	space = "Space",
	mb1 = "MouseButton1",
	mb2 = "MouseButton2",
	mb3 = "MouseButton3",
}

local MOUSE_BUTTONS = {
	MouseButton1 = true,
	MouseButton2 = true,
	MouseButton3 = true,
}

-- Accepts Enum.KeyCode / Enum.UserInputType items or names ("F", "RightCtrl", "MouseButton2").
function KeyChip.parse(key)
	if key == nil or key == false or key == "" or key == "None" then
		return nil
	end
	if typeof(key) == "EnumItem" then
		return key
	end
	if type(key) ~= "string" then
		return nil
	end
	local name = ALIASES[string.lower(key)] or key
	if #name == 1 then
		name = string.upper(name)
	end
	if MOUSE_BUTTONS[name] then
		return Enum.UserInputType[name]
	end
	local ok, item = pcall(function()
		return Enum.KeyCode[name]
	end)
	if ok and item then
		return item
	end
	return nil
end

-- True when the input matches a key (KeyCode or mouse button).
function KeyChip.matches(key, input)
	if key == nil then
		return false
	end
	if key.EnumType == Enum.KeyCode then
		return input.KeyCode == key
	end
	return input.UserInputType == key
end

local measureFont = Enum.Font.GothamMedium
pcall(function()
	measureFont = Enum.Font.BuilderSansMedium
end)

local function textWidth(text)
	local ok, size = pcall(function()
		return TextService:GetTextSize(text, 12, measureFont, Vector2.new(1000, 100))
	end)
	if ok and size then
		return size.X
	end
	return #text * 7
end

--[[ options:
	Parent, LayoutOrder, Maid
	Key             initial key
	ShowWhenEmpty   show "None" instead of hiding when unbound
	AllowNone       Backspace/Delete clears the bind (default true)
	AllowMouse      mouse buttons 2/3 can be bound (default true)
	OnChanged(key)  the bind changed
	OnResize(width) the chip's width changed (0 when hidden)
	OnTriggered(began, input) the bound key was pressed (true) or released (false)
]]
function KeyChip.new(options)
	local self = setmetatable({}, KeyChip)
	self.Key = nil
	self.Listening = false
	self._options = options
	self._showWhenEmpty = options.ShowWhenEmpty == true
	self._allowNone = options.AllowNone ~= false
	self._allowMouse = options.AllowMouse ~= false

	local button = Util.create("TextButton", {
		Name = "KeyChip",
		Size = UDim2.fromOffset(40, 24),
		Text = "",
		FontFace = Util.Fonts.Medium,
		TextSize = 12,
		LayoutOrder = options.LayoutOrder or 1,
		Theme = {
			BackgroundColor3 = "Input",
			BackgroundTransparency = "InputTransparency",
			TextColor3 = "TextDim",
		},
		Parent = options.Parent,
	}, {
		Util.corner(6),
		Util.stroke(),
	})
	self.Button = button
	self._stroke = button:FindFirstChildOfClass("UIStroke")

	local maid = options.Maid
	maid:Give(button.Activated:Connect(function()
		if self.Listening then
			self:StopListening()
		else
			self:Listen()
		end
	end))

	maid:Give(UserInputService.InputBegan:Connect(function(input, processed)
		if self.Listening then
			self:_capture(input)
			return
		end
		if processed or KeyChip.Listening or not self.Key or not button.Parent then
			return
		end
		if KeyChip.matches(self.Key, input) and options.OnTriggered then
			options.OnTriggered(true, input)
		end
	end))

	maid:Give(UserInputService.InputEnded:Connect(function(input)
		if self.Listening or not self.Key or not options.OnTriggered then
			return
		end
		if KeyChip.matches(self.Key, input) then
			options.OnTriggered(false, input)
		end
	end))

	maid:Give(function()
		if KeyChip.Listening == self then
			KeyChip.Listening = nil
		end
	end)

	self:SetKey(options.Key, true)
	return self
end

function KeyChip:_render()
	local button = self.Button
	local text
	if self.Listening then
		text = "..."
	elseif self.Key then
		text = Util.keyName(self.Key)
	else
		text = "None"
	end
	button.Text = text

	local visible = self.Listening or self.Key ~= nil or self._showWhenEmpty
	button.Visible = visible
	local width = visible and math.max(28, math.ceil(textWidth(text)) + 18) or 0
	if visible then
		Spring.animate(button, "Snappy", { Size = UDim2.fromOffset(width, 24) })
	end
	if self._options.OnResize then
		self._options.OnResize(width)
	end
end

function KeyChip:SetKey(key, silent)
	self.Key = KeyChip.parse(key)
	self:_render()
	if not silent and self._options.OnChanged then
		self._options.OnChanged(self.Key)
	end
	return self
end

function KeyChip:Listen()
	if KeyChip.Listening and KeyChip.Listening ~= self then
		KeyChip.Listening:StopListening()
	end
	KeyChip.Listening = self
	self.Listening = true
	self._listenStarted = os.clock()
	Theme.animate(self.Button, { TextColor3 = "Accent" })
	if self._stroke then
		Theme.animate(self._stroke, { Color = "Accent", Transparency = 0.2 })
	end
	self:_render()

	-- Give up after a few seconds so the chip never gets stuck.
	local started = self._listenStarted
	task.delay(6, function()
		if self.Listening and self._listenStarted == started then
			self:StopListening()
		end
	end)
	return self
end

function KeyChip:StopListening()
	if KeyChip.Listening == self then
		KeyChip.Listening = nil
	end
	self.Listening = false
	Theme.animate(self.Button, { TextColor3 = "TextDim" })
	if self._stroke then
		Theme.animate(self._stroke, { Color = "Stroke", Transparency = "StrokeTransparency" })
	end
	self:_render()
	return self
end

function KeyChip:_capture(input)
	-- Ignore the click that started listening.
	if os.clock() - (self._listenStarted or 0) < 0.05 then
		return
	end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.Keyboard then
		local code = input.KeyCode
		if code == Enum.KeyCode.Escape then
			self:StopListening()
		elseif code == Enum.KeyCode.Backspace or code == Enum.KeyCode.Delete then
			self:StopListening()
			if self._allowNone then
				self:SetKey(nil)
			end
		elseif code ~= Enum.KeyCode.Unknown then
			self:StopListening()
			self:SetKey(code)
		end
	elseif (kind == Enum.UserInputType.MouseButton2 or kind == Enum.UserInputType.MouseButton3) and self._allowMouse then
		self:StopListening()
		self:SetKey(kind)
	elseif kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
		self:StopListening()
	end
end

return KeyChip
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

Section.Set = Section.SetName

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
-- Aether Â· Components/Tab
-- A sidebar entry and its scrolling page. Elements created directly on a tab
-- go into its most recent section (an untitled one is made if needed).

local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Icons = import("Core/Icons")
local Tooltip = import("Features/Tooltip")
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
	self.IconName = options.Icon
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
	self._button = button

	self._icon = Util.create("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 11, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		Theme = { ImageColor3 = "TextDim" },
		Parent = button,
	})

	-- No icon (or an unknown one): show the tab's initial in a rounded badge instead.
	if not Icons.apply(self._icon, options.Icon) then
		self._badge = Util.create("TextLabel", {
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

	self._label = Util.create("TextLabel", {
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
		-- In the icon-only sidebar the name moves into a tooltip.
		if self._compact then
			Tooltip.schedule(self, function()
				return self.Name
			end)
		end
	end))
	window.Maid:Give(button.MouseLeave:Connect(function()
		self._hovered = false
		self:_refresh()
		Tooltip.hide(self)
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

	self:_setCompact(window._compact == true)
	return self
end

function Tab:_nextOrder()
	self._order += 1
	return self._order
end

function Tab:_refresh()
	local lit = self.Active or self._hovered
	local textToken = lit and "Text" or "TextDim"
	Theme.animate(self._label, { TextColor3 = textToken })
	if self._badge then
		local badgeToken = self.Active and "Accent" or textToken
		Theme.animate(self._badge, { TextColor3 = badgeToken })
		Theme.animate(self._badge.UIStroke, { Color = badgeToken })
	else
		Theme.animate(self._icon, { ImageColor3 = self.Active and "Accent" or textToken })
	end
	local hoverOnly = self._hovered and not self.Active
	Theme.animate(self._button, { BackgroundTransparency = hoverOnly and "HoverTransparency" or 1 })
end

function Tab:_setActive(active)
	self.Active = active
	self:_refresh()
end

function Tab:_setCompact(compact)
	self._compact = compact
	self._label.Visible = not compact
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
	self._button.Visible = self.Visible
	self.Window:_onTabsChanged()
	return self
end

function Tab:Destroy()
	for _, section in ipairs(table.clone(self.Sections)) do
		section:Destroy()
	end
	self.Window:_removeTab(self)
	self._button:Destroy()
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
-- dragging, resizing, fit-to-screen scaling, the toggle key, the floating
-- open button on touch devices, and the glue to the feature modules
-- (command palette, pins, configs, menus, tooltips, dialogs).

local Env = import("Core/Env")
local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Spring = import("Core/Spring")
local Signal = import("Core/Signal")
local Maid = import("Core/Maid")
local Icons = import("Core/Icons")
local Tab = import("Components/Tab")
local KeyChip = import("Components/KeyChip")
local Config = import("Features/Config")
local Pins = import("Features/Pins")
local Palette = import("Features/Palette")
local Dialog = import("Features/Dialog")
local Tooltip = import("Features/Tooltip")
local ContextMenu = import("Features/ContextMenu")
local Notifications = import("Features/Notifications")
local Settings = import("Features/Settings")

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

local COMPACT_SIDEBAR = 56
local COMPACT_BREAKPOINT = 560

local MIN_SIZE = Vector2.new(400, 300)
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
	self._toggleKey = KeyChip.parse(options.ToggleKey) or Enum.KeyCode.RightControl
	if options.PaletteKey == false then
		self._paletteKey = nil
	else
		self._paletteKey = KeyChip.parse(options.PaletteKey) or Enum.KeyCode.K
	end
	self._position = nil
	self._prefs = {}

	if options.Theme then
		if type(options.Theme) == "table" then
			Theme.set(options.Theme, false)
		else
			Theme.set(tostring(options.Theme), false)
		end
	end

	self.Config = Config.new(self)
	self.Pins = Pins.new(self)
	self.Palette = Palette.new(self)

	self:_build()
	self:_bindInput()
	self.MountedIn = Env.mount(self.Gui)
	self:_updateFit()
	self:_placeDefault()

	-- Saved interface preferences (theme, toggle key, pinned widgets) and the
	-- autoload config. Values for elements created later wait for them.
	self:_loadPrefs()
	if options.AutoLoad ~= false then
		self.Config:LoadAutoload()
	end

	-- AutoSave = true / "name": every change is saved shortly after it happens
	-- and restored on the next run (Rayfield scripts restore it with
	-- Aether:LoadConfiguration() instead).
	if options.AutoSave == true then
		self._autoSave = "autosave"
	elseif type(options.AutoSave) == "string" and options.AutoSave ~= "" then
		self._autoSave = Config.sanitize(options.AutoSave)
	end
	if self._autoSave and not options.__deferAutoSave then
		self:_loadAutoSave()
	end
	self.Maid:Give(self.Pins.Changed:Connect(function()
		self:_savePrefs()
	end))

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
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = root,
	})
	self._sidebar = sidebar
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
	self:_applySidebar(true)

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
	local searchWidth = self.IsTouch and 30 or 124
	local controlsWidth = searchWidth + 30 + 30 + 12
	local titleBlock = Util.create("Frame", {
		Name = "Title",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 54, 0.5, 0),
		Size = UDim2.new(1, -(54 + controlsWidth + 24), 0, 36),
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
		Size = UDim2.fromOffset(controlsWidth, 30),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = topbar,
	}, {
		Util.list(6, Enum.FillDirection.Horizontal, Enum.VerticalAlignment.Center, Enum.HorizontalAlignment.Right),
	})

	self:_buildSearchButton(searchWidth)
	self:_topbarButton("Minimize", "minus", 1, function()
		self:Minimize()
	end)
	self:_topbarButton("Close", "close", 2, function()
		self:Hide()
		-- On desktop there's no floating button, so say how to get back (once).
		if not self._hideHintShown and not self:_wantsOpenButton() then
			self._hideHintShown = true
			self:Notify({
				Title = self.Name .. " is hidden",
				Content = ("Press %s to show it again."):format(Util.keyName(self._toggleKey)),
			})
		end
	end)
end

-- "Search  Ctrl K" chip on desktop, a search icon on touch devices.
function Window:_buildSearchButton(width)
	local button = Util.create("TextButton", {
		Name = "Search",
		Size = UDim2.fromOffset(width, 30),
		LayoutOrder = 0,
		Theme = {
			BackgroundColor3 = "Input",
			BackgroundTransparency = "InputTransparency",
		},
		Parent = self._controls,
	}, {
		Util.corner(8),
		Util.stroke(),
	})

	local icon = Util.icon("search", 14, "TextDim")
	icon.AnchorPoint = Vector2.new(self.IsTouch and 0.5 or 0, 0.5)
	icon.Position = self.IsTouch and UDim2.fromScale(0.5, 0.5) or UDim2.new(0, 10, 0.5, 0)
	icon.Parent = button

	if not self.IsTouch then
		Util.create("TextLabel", {
			Name = "Label",
			Position = UDim2.fromOffset(30, 0),
			Size = UDim2.new(1, -80, 1, 0),
			Text = "Search",
			TextSize = 13,
			Theme = { TextColor3 = "TextDim" },
			Parent = button,
		})
		Util.create("TextLabel", {
			Name = "Shortcut",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(42, 18),
			Text = "Ctrl K",
			FontFace = Util.Fonts.Medium,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundTransparency = 0,
			Visible = self._paletteKey ~= nil,
			Theme = {
				BackgroundColor3 = "Input",
				BackgroundTransparency = "InputTransparency",
				TextColor3 = "TextMuted",
			},
			Parent = button,
		}, { Util.corner(4) })
	end

	self.Maid:Give(button.MouseEnter:Connect(function()
		Util.glyphColor(icon, "Text")
	end))
	self.Maid:Give(button.MouseLeave:Connect(function()
		Util.glyphColor(icon, "TextDim")
	end))
	self.Maid:Give(button.Activated:Connect(function()
		self.Palette:Toggle()
	end))
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

	local nameLabel = Util.create("TextLabel", {
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

	local usernameLabel = Util.create("TextLabel", {
		Name = "Username",
		Position = UDim2.new(0, 56, 0.5, 2),
		Size = UDim2.new(1, -66, 0, 14),
		Text = secondLine,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "TextMuted" },
		Parent = card,
	})
	self._userText = { nameLabel, usernameLabel }

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
		if KeyChip.Listening then
			return
		end
		if input.KeyCode ~= Enum.KeyCode.Unknown and KeyChip.matches(self._toggleKey, input) then
			self:Toggle()
		elseif self._paletteKey and input.KeyCode == self._paletteKey
			and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl))
		then
			self.Palette:Toggle()
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
			self:_applySidebar(false)
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

-- Sidebar = "Auto" (default) collapses to icons when the window is narrow;
-- "Full" and "Compact" force one style.
function Window:_wantsCompactSidebar()
	local mode = self.Options.Sidebar
	if mode == "Compact" then
		return true
	elseif mode == "Full" then
		return false
	end
	return self._size.X < COMPACT_BREAKPOINT
end

function Window:_applySidebar(instant)
	local compact = self:_wantsCompactSidebar()
	if compact == self._compact then
		return
	end
	self._compact = compact
	local width = compact and COMPACT_SIDEBAR or self._sidebarWidth
	local goals = {
		[self._sidebar] = { Size = UDim2.new(0, width, 1, -TOPBAR_HEIGHT) },
		[self._pages] = {
			Position = UDim2.fromOffset(width, TOPBAR_HEIGHT),
			Size = UDim2.new(1, -width, 1, -TOPBAR_HEIGHT),
		},
	}
	for instance, goal in pairs(goals) do
		if instant then
			Spring.stop(instance)
			for property, value in pairs(goal) do
				instance[property] = value
			end
		else
			Spring.animate(instance, "Snappy", goal)
		end
	end
	for _, tab in ipairs(self.Tabs) do
		tab:_setCompact(compact)
	end
	if self._userText then
		for _, label in ipairs(self._userText) do
			label.Visible = not compact
		end
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
	-- Keep it in the saved layout so the widget returns with the element.
	self.Pins:Unpin(element, true)
	Tooltip.hide(element)
end

-- Hooks called by elements
function Window:_elementReady(element)
	self.Config:_elementReady(element)
	self.Pins:_elementReady(element)
	if self._autoSave and element.Saveable and not element._autoSaveHooked then
		element._autoSaveHooked = true
		local queue = function()
			self:_queueAutoSave()
		end
		element.Maid:Give(element.Changed:Connect(queue))
		if element.BindChanged then
			element.Maid:Give(element.BindChanged:Connect(queue))
		end
	end
end

function Window:_queueAutoSave()
	if not self._autoSave or self._loadingAutoSave or self._autoSaveQueued then
		return
	end
	self._autoSaveQueued = true
	task.delay(1, function()
		self._autoSaveQueued = false
		if not self.Destroyed then
			self.Config:Save(self._autoSave)
		end
	end)
end

-- Loads the AutoSave config (values for elements created later wait for them).
function Window:_loadAutoSave()
	if not self._autoSave then
		return false
	end
	self._loadingAutoSave = true
	local ok = self.Config:Load(self._autoSave)
	self._loadingAutoSave = false
	return ok
end

function Window:_elementText(element)
	self.Pins:_elementText(element)
end

function Window:_scheduleTooltip(element)
	Tooltip.schedule(element, function()
		return element:_tooltipText()
	end)
end

function Window:_hideTooltip(element)
	Tooltip.hide(element)
end

function Window:_beginPinDrag(element, pointer)
	Tooltip.hide()
	self.Pins:BeginDrag(element, pointer)
end

function Window:_updatePinDrag(element, pointer)
	self.Pins:UpdateDrag(element, pointer)
end

function Window:_endPinDrag(element, pointer)
	self.Pins:EndDrag(element, pointer)
end

-- Right-click / long-press menu for an element.
function Window:_openContextMenu(element, pointer)
	if element.Destroyed then
		return
	end
	local items = {}

	if Pins.canPin(element) then
		if self.Pins:IsPinned(element) then
			table.insert(items, { Text = "Unpin widget", Icon = "pin-off", Callback = function()
				self.Pins:Unpin(element)
			end })
		else
			table.insert(items, { Text = "Pin to screen", Icon = "pin", Callback = function()
				self.Pins:Pin(element, pointer + Vector2.new(12, 12))
			end })
		end
	end

	if element.Bindable and element.Keybind then
		local key = element:GetKeybind()
		table.insert(items, {
			Text = key and "Change key bind" or "Add key bind",
			Icon = "keyboard",
			Hint = key and Util.keyName(key) or nil,
			Callback = function()
				element:Keybind(element:GetKeybind())
				element._chip:Listen()
			end,
		})
		if key then
			table.insert(items, { Text = "Remove key bind", Icon = "x", Callback = function()
				element:Keybind(nil)
			end })
		end
	end

	if element.Saveable then
		if #items > 0 then
			table.insert(items, { Separator = true })
		end
		if Env.CanCopy then
			table.insert(items, { Text = "Copy value", Icon = "copy", Callback = function()
				Env.copy(element:_display())
			end })
		end
		if element._default ~= nil then
			table.insert(items, { Text = "Reset to default", Icon = "rotate-ccw", Callback = function()
				element:Reset()
			end })
		end
	end

	if #items > 0 then
		Tooltip.hide()
		ContextMenu.open(items, pointer)
	end
end

---------------------------------------------------------------------------
-- Features
---------------------------------------------------------------------------

-- Current scale of the window on screen (fit-to-screen × open animation).
function Window:_uiScale()
	local width = self._root.AbsoluteSize.X
	return width > 0 and width / self._size.X or 1
end

-- Shows the window, opens the element's tab and scrolls it into view.
function Window:Reveal(element)
	if type(element) ~= "table" or element.Window ~= self or element.Destroyed then
		return self
	end
	self:Show()
	if self.Minimized then
		self:Minimize(false)
	end
	self:SelectTab(element.Tab)
	task.delay(0.06, function()
		if element.Destroyed or self.Destroyed then
			return
		end
		local page = element.Tab.Page
		local scale = self:_uiScale()
		local offset = (element.Frame.AbsolutePosition.Y - page.AbsolutePosition.Y) / scale + page.CanvasPosition.Y
		Spring.animate(page, "Smooth", { CanvasPosition = Vector2.new(0, math.max(0, offset - 24)) })
		element:Flash()
		if element.Type == "Dropdown" then
			element:Open()
		elseif element.Type == "ColorPicker" and not element.Expanded then
			element:_onClick()
		elseif element.Type == "Input" then
			element:Focus()
		elseif element.Type == "Keybind" then
			element:Listen()
		end
	end)
	return self
end

function Window:Notify(options)
	return Notifications.notify(options)
end

function Window:Dialog(options)
	ContextMenu.close()
	Tooltip.hide()
	return Dialog.open(self, options)
end

function Window:OpenPalette()
	self.Palette:Open()
	return self
end

-- Adds the ready-made settings tab (theme, keys, configs, share codes, unload).
function Window:SettingsTab(options)
	return Settings.build(self, options)
end

-- Config API (see Features/Config): Window:SaveConfig("Legit"), Window:LoadConfig("Legit")...
function Window:SaveConfig(name)
	return self.Config:Save(name)
end

function Window:LoadConfig(name)
	return self.Config:Load(name)
end

function Window:DeleteConfig(name)
	return self.Config:Delete(name)
end

function Window:ListConfigs()
	return self.Config:List()
end

function Window:ExportConfig()
	return self.Config:Export()
end

function Window:ImportConfig(code)
	return self.Config:Import(code)
end

function Window:SetAutoload(name)
	return self.Config:SetAutoload(name)
end

-- Pins an element as a floating widget (position in screen pixels, optional).
function Window:Pin(element, position)
	return self.Pins:Pin(element, position)
end

function Window:Unpin(element)
	self.Pins:Unpin(element)
	return self
end

-- Copies the config share code; falls back to putting it in an input box.
function Window:_copyShareCode(fallbackInput)
	local code = self.Config:Export()
	if Env.copy(code) then
		self:Notify({ Title = "Config code copied", Content = "Anyone can paste it into their settings tab.", Type = "Success" })
	elseif fallbackInput then
		fallbackInput:Set(code, true)
		self:Notify({ Title = "Copy the code from the box", Content = "Your executor can't copy to the clipboard.", Type = "Warning" })
	else
		self:Notify({ Title = "Clipboard unavailable", Content = "Open the settings tab to copy the code by hand.", Type = "Warning" })
	end
end

---------------------------------------------------------------------------
-- Interface preferences
---------------------------------------------------------------------------

function Window:_loadPrefs()
	if self.Options.SavePrefs == false then
		return
	end
	local prefs = self.Config:LoadPrefs()
	if type(prefs) ~= "table" then
		return
	end
	self._prefs = prefs
	if type(prefs.Theme) == "table" then
		Theme.deserialize(prefs.Theme, false)
	end
	local key = KeyChip.parse(prefs.ToggleKey)
	if key then
		self._toggleKey = key
	end
	if prefs.ReducedMotion == true then
		self.Library:SetReducedMotion(true)
	end
	self.Pins:Load(prefs.Pins)
end

-- Saves preferences shortly after a change. themeChosen = the user picked a theme.
function Window:_savePrefs(themeChosen)
	if self.Options.SavePrefs == false or self.Destroyed then
		return
	end
	if themeChosen then
		self._saveTheme = true
	end
	if self._prefsQueued then
		return
	end
	self._prefsQueued = true
	task.delay(0.4, function()
		self._prefsQueued = false
		if self.Destroyed then
			return
		end
		local prefs = self._prefs
		prefs.ToggleKey = self._toggleKey.Name
		prefs.ReducedMotion = self.Library.ReducedMotion == true
		prefs.Pins = self.Pins:Serialize()
		if self._saveTheme then
			prefs.Theme = Theme.serialize()
		end
		self.Config:SavePrefs(prefs)
	end)
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

-- window:SetToggleKey("K") / window:SetToggleKey(Enum.KeyCode.K)
function Window:SetToggleKey(key)
	local parsed = KeyChip.parse(key)
	if parsed then
		self._toggleKey = parsed
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
	self.Palette:Close()
	ContextMenu.close()
	Tooltip.hide()
	for _, element in ipairs(table.clone(self.Elements)) do
		element:Destroy()
	end
	self.Pins:Destroy()
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
-- Core/Base64
__modules["Core/Base64"] = function()
-- Aether · Core/Base64
-- Plain Lua Base64 (standard alphabet, with padding) for share codes.

local Base64 = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local decodeMap = {}
for index = 1, #ALPHABET do
	decodeMap[string.byte(ALPHABET, index)] = index - 1
end

function Base64.encode(data)
	local out = table.create(math.ceil(#data / 3) * 4)
	for index = 1, #data, 3 do
		local a, b, c = string.byte(data, index, index + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1 = math.floor(n / 262144) % 64
		local c2 = math.floor(n / 4096) % 64
		local c3 = math.floor(n / 64) % 64
		local c4 = n % 64
		table.insert(out, string.sub(ALPHABET, c1 + 1, c1 + 1))
		table.insert(out, string.sub(ALPHABET, c2 + 1, c2 + 1))
		table.insert(out, b and string.sub(ALPHABET, c3 + 1, c3 + 1) or "=")
		table.insert(out, c and string.sub(ALPHABET, c4 + 1, c4 + 1) or "=")
	end
	return table.concat(out)
end

-- Returns the decoded string, or nil if the input isn't valid Base64.
function Base64.decode(text)
	text = string.gsub(text, "%s", "")
	if #text % 4 ~= 0 then
		return nil
	end
	local out = {}
	for index = 1, #text, 4 do
		local values = {}
		local padding = 0
		for offset = 0, 3 do
			local byte = string.byte(text, index + offset)
			if byte == 61 then -- "="
				padding += 1
				values[offset + 1] = 0
			else
				local value = decodeMap[byte]
				if value == nil or padding > 0 then
					return nil
				end
				values[offset + 1] = value
			end
		end
		local n = values[1] * 262144 + values[2] * 4096 + values[3] * 64 + values[4]
		local a = math.floor(n / 65536) % 256
		local b = math.floor(n / 256) % 256
		local c = n % 256
		if padding == 0 then
			table.insert(out, string.char(a, b, c))
		elseif padding == 1 then
			table.insert(out, string.char(a, b))
		elseif padding == 2 then
			table.insert(out, string.char(a))
		else
			return nil
		end
	end
	return table.concat(out)
end

return Base64
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
-- Core/Fuzzy
__modules["Core/Fuzzy"] = function()
-- Aether · Core/Fuzzy
-- Small fuzzy matcher for the command palette: every query character must
-- appear in order. Consecutive matches, word starts and exact substrings
-- score higher; shorter texts win ties.

local Fuzzy = {}

-- Word starts: the first character, anything after a separator, and
-- camelCase humps ("WalkSpeed" starts a word at "S").
local function isBoundary(original, index)
	if index == 1 then
		return true
	end
	local previous = string.sub(original, index - 1, index - 1)
	if string.find(previous, "[%s%-_/%.]") then
		return true
	end
	local current = string.sub(original, index, index)
	return string.find(previous, "%l") ~= nil and string.find(current, "%u") ~= nil
end

-- Returns score, matchedIndices (or nil when the query doesn't match).
function Fuzzy.match(query, text)
	query = string.lower(query)
	local lower = string.lower(text)
	if query == "" then
		return 0, {}
	end

	local indices = {}
	local score = 0
	local queryIndex = 1
	local previous = -1
	for index = 1, #lower do
		if queryIndex > #query then
			break
		end
		if string.sub(lower, index, index) == string.sub(query, queryIndex, queryIndex) then
			local bonus = 1
			if index == previous + 1 then
				bonus += 4
			end
			if isBoundary(text, index) then
				bonus += 6
			end
			score += bonus
			table.insert(indices, index)
			previous = index
			queryIndex += 1
		end
	end
	if queryIndex <= #query then
		return nil
	end

	local exact = string.find(lower, query, 1, true)
	if exact then
		score += 12
		if exact == 1 then
			score += 8
		end
	end
	score -= (#lower - #query) * 0.05
	return score, indices
end

local function escape(text)
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- RichText with the matched characters coloured.
function Fuzzy.highlight(text, indices, hexColor)
	if not indices or #indices == 0 then
		return escape(text)
	end
	local marked = {}
	for _, index in ipairs(indices) do
		marked[index] = true
	end
	local parts = {}
	for index = 1, #text do
		local char = escape(string.sub(text, index, index))
		if marked[index] then
			table.insert(parts, ('<font color="#%s">%s</font>'):format(hexColor, char))
		else
			table.insert(parts, char)
		end
	end
	return table.concat(parts)
end

Fuzzy.escape = escape

return Fuzzy
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
	Input = hex("#FFFFFF"),
	InputTransparency = 0.95,

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
		Input = hex("#000000"),
		InputTransparency = 0.955,
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
-- Serialization (theme share codes, saved preferences)
---------------------------------------------------------------------------

-- The current theme as JSON-safe data: colours as hex, numbers as numbers.
function Theme.serialize()
	local tokens = {}
	for key, value in pairs(current) do
		if typeof(value) == "Color3" then
			tokens[key] = "#" .. value:ToHex()
		elseif type(value) == "number" then
			tokens[key] = value
		end
	end
	return { Name = Theme.Name, Tokens = tokens }
end

-- Applies serialized theme data. Unknown keys and bad values are skipped.
function Theme.deserialize(data, animate)
	if type(data) ~= "table" or type(data.Tokens) ~= "table" then
		return false
	end
	local overrides = {}
	for key, value in pairs(data.Tokens) do
		local base = AETHER[key]
		if typeof(base) == "Color3" and type(value) == "string" then
			local ok, color = pcall(Color3.fromHex, value)
			if ok then
				overrides[key] = color
			end
		elseif type(base) == "number" and type(value) == "number" then
			overrides[key] = math.clamp(value, 0, 1)
		end
	end
	if next(overrides) == nil then
		return false
	end
	-- Start from the default theme so every token is defined.
	current = table.clone(AETHER)
	overrides.Name = type(data.Name) == "string" and data.Name or "Custom"
	return Theme.set(overrides, animate)
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
local Icons = import("Core/Icons")

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

-- A Lucide icon as an ImageLabel, tinted with a theme token.
function Util.icon(name, size, colorToken)
	local image = Util.create("ImageLabel", {
		Name = "Icon",
		Size = UDim2.fromOffset(size or 16, size or 16),
		Theme = { ImageColor3 = colorToken or "TextDim" },
	})
	Icons.apply(image, name)
	return image
end

-- Changes the icon shown by an image created with Util.icon.
function Util.iconSet(image, name)
	return Icons.apply(image, name)
end

-- Springs every stroke of a glyph (or an icon image) to a new colour token.
function Util.glyphColor(glyph, token)
	if glyph:IsA("ImageLabel") then
		Theme.animate(glyph, { ImageColor3 = token })
		return
	end
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
--   Tab:Button("Rejoin"):OnClick(fn):Keybind("R")

local Util = import("Core/Util")
local Spring = import("Core/Spring")
local Element = import("Components/Element")
local Elements = import("Components/Elements")
local KeyChip = import("Components/KeyChip")

local Button = Element.extend("Button")
Button.Pinnable = true
Button.Bindable = true

local CHEVRON_WIDTH = 16

function Button.new(section, options)
	local self = setmetatable({}, Button)
	Element.init(self, section, options, {
		Clickable = true,
		ControlWidth = CHEVRON_WIDTH,
		ControlHeight = 26,
	})
	self.Clicked = self.Changed

	Util.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = self.Control,
	})

	-- The chevron sits in a fixed slot so its hover nudge doesn't fight the layout.
	local slot = Util.create("Frame", {
		Name = "ChevronSlot",
		Size = UDim2.fromOffset(CHEVRON_WIDTH, 16),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = self.Control,
	})
	local chevron = Util.glyph("chevron-right", { Size = 14, Color = "TextMuted" })
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.fromScale(1, 0.5)
	chevron.Parent = slot
	self._chevron = chevron

	if options.Keybind then
		self:Keybind(options.Keybind)
	end

	return self:_ready()
end

function Button:_onClick()
	self:Press()
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

-- Rayfield: button:Set("New name")
function Button:Set(text)
	return self:SetTitle(text)
end

function Button:_onHover(hovered)
	Util.glyphColor(self._chevron, hovered and "Text" or "TextMuted")
	Spring.animate(self._chevron, "Bouncy", { Position = UDim2.new(1, hovered and 3 or 0, 0.5, 0) })
end

-- Binds a key that presses the button: button:Keybind("R") / button:Keybind(Enum.KeyCode.R)
function Button:Keybind(key)
	if not self._chip then
		self._chip = KeyChip.new({
			Parent = self.Control,
			LayoutOrder = 1,
			Maid = self.Maid,
			AllowNone = true,
			OnResize = function(width)
				self:_setControlWidth(CHEVRON_WIDTH + (width > 0 and width + 8 or 0))
			end,
			OnTriggered = function(began)
				if began then
					self:Press()
				end
			end,
		})
	end
	self._chip:SetKey(key)
	return self
end

function Button:GetKeybind()
	return self._chip and self._chip.Key or nil
end

function Button:_display()
	return self._chip and self._chip.Key and ("Key: " .. Util.keyName(self._chip.Key)) or ""
end

Elements.register("Button", Button)

return Button
end

-- ======================================================================
-- Elements/ColorPicker
__modules["Elements/ColorPicker"] = function()
-- Aether · Elements/ColorPicker
--   Tab:ColorPicker({ Name = "ESP color", Default = Color3.fromRGB(139, 92, 246), Callback = function(color) end })
--   Transparency = 0.2 adds a transparency bar; the callback then gets (color, transparency).
-- Includes a hex field and a rainbow mode.

local Env = import("Core/Env")
local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Spring = import("Core/Spring")
local Element = import("Components/Element")
local Elements = import("Components/Elements")

local RunService = Env.service("RunService")

local ColorPicker = Element.extend("ColorPicker")
ColorPicker.Saveable = true
ColorPicker.Pinnable = false

local SV_HEIGHT = 120
local BAR_HEIGHT = 14
local ROW_HEIGHT = 28
local GAP = 6
local RAINBOW_SPEED = 0.2 -- hue cycles per second
local RAINBOW_RATE = 1 / 20 -- max callback rate in rainbow mode

local function toColor(value)
	if typeof(value) == "Color3" then
		return value
	end
	if type(value) == "string" then
		local ok, color = pcall(Color3.fromHex, value)
		if ok then
			return color
		end
	end
	return nil
end

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
	ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
	ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
	ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
	ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
	ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
})

local function cursorRing(size)
	return Util.create("Frame", {
		Name = "Cursor",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, {
		Util.corner("full"),
		Util.create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }),
	})
end

function ColorPicker.new(section, options)
	local self = setmetatable({}, ColorPicker)
	local color = toColor(options.Default or options.Color or options.Value) or Color3.fromRGB(139, 92, 246)
	local transparency = tonumber(options.Transparency or options.Alpha)
	self._hasAlpha = transparency ~= nil
	self.Transparency = transparency or 0
	self.Rainbow = false

	Element.init(self, section, options, {
		Clickable = true,
		ControlWidth = 44,
		ControlHeight = 24,
		Panel = true,
	})

	self._swatch = Util.create("Frame", {
		Name = "Swatch",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		Parent = self.Control,
	}, {
		Util.corner(6),
		Util.stroke(),
	})

	local panel = self.PanelInner

	-- Saturation / value square
	local sv = Util.create("TextButton", {
		Name = "SV",
		Size = UDim2.new(1, 0, 0, SV_HEIGHT),
		BackgroundColor3 = Color3.new(1, 0, 0),
		BackgroundTransparency = 0,
		LayoutOrder = 1,
		Parent = panel,
	}, { Util.corner(6) })
	Util.create("Frame", {
		Name = "White",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = sv,
	}, {
		Util.corner(6),
		Util.create("UIGradient", {
			Transparency = NumberSequence.new(0, 1),
		}),
	})
	Util.create("Frame", {
		Name = "Black",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		ZIndex = 2,
		Parent = sv,
	}, {
		Util.corner(6),
		Util.create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new(1, 0),
		}),
	})
	self._svCursor = cursorRing(12)
	self._svCursor.Parent = sv
	self._sv = sv

	-- Hue bar
	local hue = Util.create("TextButton", {
		Name = "Hue",
		Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		LayoutOrder = 2,
		Parent = panel,
	}, {
		Util.corner("full"),
		Util.create("UIGradient", { Color = RAINBOW }),
	})
	self._hueCursor = cursorRing(BAR_HEIGHT + 2)
	self._hueCursor.Parent = hue
	self._hue = hue

	-- Transparency bar (optional)
	if self._hasAlpha then
		local alpha = Util.create("TextButton", {
			Name = "Alpha",
			Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
			BackgroundColor3 = color,
			BackgroundTransparency = 0,
			LayoutOrder = 3,
			Parent = panel,
		}, {
			Util.corner("full"),
			Util.stroke(),
			Util.create("UIGradient", { Transparency = NumberSequence.new(1, 0) }),
		})
		self._alphaCursor = cursorRing(BAR_HEIGHT + 2)
		self._alphaCursor.Parent = alpha
		self._alpha = alpha
	end

	-- Hex field, RGB readout and rainbow switch
	local row = Util.create("Frame", {
		Name = "Row",
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = panel,
	}, { Util.list(8, Enum.FillDirection.Horizontal, Enum.VerticalAlignment.Center) })

	self._hex = Util.create("TextBox", {
		Name = "Hex",
		Size = UDim2.fromOffset(84, ROW_HEIGHT),
		FontFace = Util.Fonts.Mono,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		Theme = {
			BackgroundColor3 = "Input",
			BackgroundTransparency = "InputTransparency",
			TextColor3 = "Text",
		},
		Parent = row,
	}, { Util.corner(6) })

	self._rgb = Util.create("TextLabel", {
		Name = "RGB",
		Size = UDim2.new(1, -176, 1, 0),
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
		Theme = { TextColor3 = "TextMuted" },
		Parent = row,
	})

	self._rainbowButton = Util.create("TextButton", {
		Name = "Rainbow",
		Size = UDim2.fromOffset(76, ROW_HEIGHT),
		Text = "Rainbow",
		TextSize = 12,
		LayoutOrder = 3,
		Theme = {
			BackgroundColor3 = "Input",
			BackgroundTransparency = "InputTransparency",
			TextColor3 = "TextDim",
		},
		Parent = row,
	}, {
		Util.corner(6),
		Util.stroke(),
	})

	-- Input
	Util.draggable(sv, {
		Start = function(input)
			self:_pickSV(Util.pointer(input))
		end,
		Move = function(_, pointer)
			self:_pickSV(pointer)
		end,
	}, self.Maid)
	Util.draggable(hue, {
		Start = function(input)
			self:_pickHue(Util.pointer(input))
		end,
		Move = function(_, pointer)
			self:_pickHue(pointer)
		end,
	}, self.Maid)
	if self._alpha then
		Util.draggable(self._alpha, {
			Start = function(input)
				self:_pickAlpha(Util.pointer(input))
			end,
			Move = function(_, pointer)
				self:_pickAlpha(pointer)
			end,
		}, self.Maid)
	end

	self.Maid:Give(self._hex.FocusLost:Connect(function()
		local text = string.gsub(self._hex.Text, "[^%x]", "")
		local parsed = #text == 6 and toColor(text) or nil
		if parsed then
			self:SetRainbow(false)
			self:Set(parsed, self.Transparency)
		else
			self:_render()
		end
	end))

	self.Maid:Give(self._rainbowButton.Activated:Connect(function()
		self:SetRainbow(not self.Rainbow)
	end))

	self._h, self._s, self._v = color:ToHSV()
	self._default = { Color = color, Transparency = self.Transparency }
	self:_publish(color)
	self:_render()

	if options.Rainbow then
		self:SetRainbow(true)
	end
	return self:_ready()
end

local function relative(frame, pointer)
	local position, size = frame.AbsolutePosition, frame.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return 0, 0
	end
	return math.clamp((pointer.X - position.X) / size.X, 0, 1), math.clamp((pointer.Y - position.Y) / size.Y, 0, 1)
end

function ColorPicker:_pickSV(pointer)
	if self.Disabled then
		return
	end
	local x, y = relative(self._sv, pointer)
	self._s, self._v = x, 1 - y
	self:SetRainbow(false)
	self:_commitHSV()
end

function ColorPicker:_pickHue(pointer)
	if self.Disabled then
		return
	end
	local x = relative(self._hue, pointer)
	self._h = math.clamp(x, 0, 0.9999)
	self:SetRainbow(false)
	self:_commitHSV()
end

function ColorPicker:_pickAlpha(pointer)
	if self.Disabled then
		return
	end
	local x = relative(self._alpha, pointer)
	self:Set(self.Value, 1 - x)
end

function ColorPicker:_commitHSV(silent)
	self:_apply(Color3.fromHSV(self._h, self._s, self._v), self.Transparency, silent, false, true)
end

-- Updates the value; keepHSV avoids losing hue/saturation at black or grey.
function ColorPicker:_apply(color, transparency, silent, force, keepHSV)
	transparency = math.clamp(tonumber(transparency) or self.Transparency, 0, 1)
	local changed = self.Value == nil or color:ToHex() ~= self.Value:ToHex() or math.abs(transparency - self.Transparency) > 1e-3
	if not keepHSV then
		self._h, self._s, self._v = color:ToHSV()
	end
	self.Transparency = transparency
	self:_publish(color)
	self:_render()
	if (changed or force) and not silent then
		if self._hasAlpha then
			self.Changed:Fire(color, transparency)
		else
			self.Changed:Fire(color)
		end
	end
end

function ColorPicker:_render()
	local color = self.Value
	self._swatch.BackgroundColor3 = color
	self._swatch.BackgroundTransparency = self._hasAlpha and self.Transparency * 0.85 or 0
	self._sv.BackgroundColor3 = Color3.fromHSV(self._h, 1, 1)
	self._svCursor.Position = UDim2.fromScale(self._s, 1 - self._v)
	self._hueCursor.Position = UDim2.fromScale(self._h, 0.5)
	if self._alpha then
		self._alpha.BackgroundColor3 = color
		self._alphaCursor.Position = UDim2.fromScale(1 - self.Transparency, 0.5)
	end
	if not self._hex:IsFocused() then
		self._hex.Text = "#" .. string.upper(color:ToHex())
	end
	self._rgb.Text = ("%d, %d, %d"):format(
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

function ColorPicker:_publish(value)
	Element._publish(self, value)
	self.Color = value -- Rayfield's name for it
end

function ColorPicker:_panelHeight()
	local height = SV_HEIGHT + GAP + BAR_HEIGHT + GAP + ROW_HEIGHT + 10
	if self._hasAlpha then
		height += BAR_HEIGHT + GAP
	end
	return height
end

function ColorPicker:_onClick()
	self:_setExpanded(not self.Expanded, self:_panelHeight())
end

-- picker:Set(Color3.new(1, 0, 0)) · picker:Set("#FF0000") · picker:Set(color, 0.5)
function ColorPicker:Set(color, transparency, silent, force)
	-- Configs call Set(data, silent, force) with a table.
	if type(color) == "table" then
		force, silent = silent, transparency
		transparency = color.Transparency
		if color.Rainbow ~= nil then
			self:SetRainbow(color.Rainbow == true)
		end
		color = color.Color
	elseif type(transparency) == "boolean" then
		force, silent, transparency = silent, transparency, nil
	end
	local parsed = toColor(color)
	if not parsed then
		return self
	end
	self:_apply(parsed, transparency, silent, force)
	return self
end

function ColorPicker:Get()
	return self.Value, self.Transparency
end

function ColorPicker:SetRainbow(enabled)
	enabled = enabled == true
	if enabled == self.Rainbow then
		return self
	end
	self.Rainbow = enabled
	Theme.animate(self._rainbowButton, { TextColor3 = enabled and "Accent" or "TextDim" })
	if self._rainbowConnection then
		self._rainbowConnection:Disconnect()
		self._rainbowConnection = nil
	end
	if enabled then
		local sinceFire = 0
		if self._s < 0.2 then
			self._s = 1
		end
		if self._v < 0.2 then
			self._v = 1
		end
		self._rainbowConnection = self.Maid:Give(RunService.Heartbeat:Connect(function(dt)
			if self.Disabled then
				return
			end
			self._h = (self._h + dt * RAINBOW_SPEED) % 1
			sinceFire += dt
			local fire = sinceFire >= RAINBOW_RATE
			if fire then
				sinceFire = 0
			end
			self:_commitHSV(not fire)
		end))
	end
	return self
end

function ColorPicker:_serialize()
	return {
		Color = self.Value:ToHex(),
		Transparency = self.Transparency,
		Rainbow = self.Rainbow,
	}
end

function ColorPicker:_display()
	return "#" .. string.upper(self.Value:ToHex())
end

function ColorPicker:Reset()
	self:SetRainbow(false)
	return self:Set(self._default.Color, self._default.Transparency)
end

function ColorPicker:_onExpanded(expanded)
	Spring.animate(self._swatch, "Bouncy", { Size = expanded and UDim2.new(1, 0, 1, 4) or UDim2.fromScale(1, 1) })
end

Elements.register("ColorPicker", ColorPicker)

return ColorPicker
end

-- ======================================================================
-- Elements/Divider
__modules["Elements/Divider"] = function()
-- Aether · Elements/Divider
--   Tab:Divider()   a thin line between groups of elements

local Util = import("Core/Util")
local Element = import("Components/Element")
local Elements = import("Components/Elements")

local Divider = Element.extend("Divider")

function Divider.new(section, options)
	local self = setmetatable({}, Divider)
	Element.init(self, section, options, {
		NoText = true,
		Stacked = true,
		Height = 13,
		PaddingY = 6,
		ControlHeight = 1,
	})
	Util.create("Frame", {
		Name = "Line",
		Size = UDim2.fromScale(1, 1),
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		Parent = self.Control,
	})
	return self:_ready()
end

Elements.register("Divider", Divider)

return Divider
end

-- ======================================================================
-- Elements/Dropdown
__modules["Elements/Dropdown"] = function()
-- Aether · Elements/Dropdown
--   Tab:Dropdown({ Name = "Weapon", Options = { "Sword", "Bow" }, Default = "Sword", Callback = function(v) end })
--   Tab:Dropdown({ Name = "Targets", Options = players, Multi = true, Callback = function(list) end })
-- Single-select passes a string (or nil); multi-select passes an array.
-- Also accepts Rayfield's CurrentOption / MultipleOptions and Fluent's Values.

local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Spring = import("Core/Spring")
local Element = import("Components/Element")
local Elements = import("Components/Elements")

local Dropdown = Element.extend("Dropdown")
Dropdown.Saveable = true
Dropdown.Pinnable = true

local OPTION_HEIGHT = 30
local OPTION_GAP = 2
local SEARCH_HEIGHT = 30

local function toList(values)
	local list = {}
	if type(values) == "table" then
		for _, value in ipairs(values) do
			table.insert(list, tostring(value))
		end
	end
	return list
end

function Dropdown.new(section, options)
	local self = setmetatable({}, Dropdown)
	self.Multi = options.Multi == true or options.MultipleOptions == true or options.Multiple == true
	self._list = toList(options.Options or options.Values or options.List)
	self.Values = self._list
	self._placeholder = options.Placeholder or "Select..."
	self._allowNone = options.AllowNone == true
	self._maxVisible = options.MaxVisible or 6
	self._search = options.Search
	self._query = ""

	-- Rayfield passes a table to single-select callbacks; CreateDropdown keeps that.
	if options.__compat == "Rayfield" and not self.Multi and type(options.Callback) == "function" then
		local callback = options.Callback
		options.Callback = function(value)
			return callback(value == nil and {} or { value })
		end
	end

	local touch = section.Window.IsTouch
	Element.init(self, section, options, {
		Clickable = true,
		ControlWidth = options.Width or (touch and 150 or 176),
		ControlHeight = 30,
		Panel = true,
	})

	-- Selected value box
	local box = Util.create("Frame", {
		Name = "Box",
		Size = UDim2.fromScale(1, 1),
		Theme = {
			BackgroundColor3 = "Input",
			BackgroundTransparency = "InputTransparency",
		},
		Parent = self.Control,
	}, {
		Util.corner(7),
		Util.stroke(),
	})
	self._box = box

	self._valueLabel = Util.create("TextLabel", {
		Name = "Value",
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -34, 1, 0),
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "TextMuted" },
		Parent = box,
	})

	local chevron = Util.glyph("chevron-down", { Size = 12, Color = "TextDim", Thickness = 2 })
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.new(1, -10, 0.5, 0)
	chevron.Parent = box
	self._chevron = chevron

	-- Panel: optional search box and the option list
	local panel = self.PanelInner
	self._searchBox = Util.create("Frame", {
		Name = "Search",
		Size = UDim2.new(1, 0, 0, SEARCH_HEIGHT),
		LayoutOrder = 1,
		Theme = {
			BackgroundColor3 = "Input",
			BackgroundTransparency = "InputTransparency",
		},
		Parent = panel,
	}, {
		Util.corner(7),
		Util.stroke(),
	})
	local searchIcon = Util.icon("search", 14, "TextMuted")
	searchIcon.AnchorPoint = Vector2.new(0, 0.5)
	searchIcon.Position = UDim2.new(0, 9, 0.5, 0)
	searchIcon.Parent = self._searchBox
	self._searchInput = Util.create("TextBox", {
		Name = "Input",
		Position = UDim2.fromOffset(30, 0),
		Size = UDim2.new(1, -38, 1, 0),
		PlaceholderText = "Search...",
		TextSize = 13,
		Theme = { TextColor3 = "Text", PlaceholderColor3 = "TextMuted" },
		Parent = self._searchBox,
	})

	self._scroller = Util.create("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, 0, 0, OPTION_HEIGHT),
		LayoutOrder = 2,
		ScrollBarThickness = 2,
		Theme = { ScrollBarImageColor3 = "TextMuted" },
		Parent = panel,
	}, { Util.list(OPTION_GAP) })

	self._empty = Util.create("TextLabel", {
		Name = "Empty",
		Size = UDim2.new(1, 0, 0, OPTION_HEIGHT),
		Text = "No results",
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		LayoutOrder = 1e6,
		Theme = { TextColor3 = "TextMuted" },
		Parent = self._scroller,
	})

	self._buttons = {}
	self.Maid:Give(self._searchInput:GetPropertyChangedSignal("Text"):Connect(function()
		self._query = string.lower(tostring(self._searchInput.Text))
		self:_filter()
	end))

	-- Initial value
	local default = options.Default
	if default == nil then
		default = options.CurrentOption
	end
	if default == nil then
		default = options.Value
	end
	self.Value = self.Multi and {} or nil
	self:_buildOptions()
	self:_apply(default)
	self._default = self:_copyValue()
	self:_publish(self:_copyValue())
	self:_refreshDisplay()
	return self:_ready()
end

function Dropdown:_copyValue()
	if self.Multi then
		return table.clone(self.Value or {})
	end
	return self.Value
end

function Dropdown:_publish(value)
	Element._publish(self, value)
	-- Rayfield-style field: always a table.
	if self.Multi then
		self.CurrentOption = table.clone(value or {})
	else
		self.CurrentOption = value == nil and {} or { value }
	end
end

function Dropdown:_isSelected(option)
	if self.Multi then
		return table.find(self.Value, option) ~= nil
	end
	return self.Value == option
end

-- Normalizes any accepted input into the current value (without callbacks).
function Dropdown:_apply(value)
	if self.Multi then
		local wanted = {}
		if type(value) == "table" then
			for _, item in ipairs(value) do
				wanted[tostring(item)] = true
			end
		elseif value ~= nil then
			wanted[tostring(value)] = true
		end
		local result = {}
		for _, option in ipairs(self._list) do
			if wanted[option] then
				table.insert(result, option)
			end
		end
		self.Value = result
	else
		if type(value) == "table" then
			value = value[1]
		end
		value = value ~= nil and tostring(value) or nil
		-- Unknown options are ignored; nil clears the selection.
		if value ~= nil and not table.find(self._list, value) then
			if not table.find(self._list, self.Value) then
				self.Value = nil
			end
			return
		end
		self.Value = value
	end
end

function Dropdown:_buildOptions()
	for _, button in pairs(self._buttons) do
		button:Destroy()
	end
	table.clear(self._buttons)

	for index, option in ipairs(self._list) do
		local button = Util.create("TextButton", {
			Name = option,
			Size = UDim2.new(1, -4, 0, OPTION_HEIGHT),
			LayoutOrder = index,
			BackgroundTransparency = 1,
			Theme = { BackgroundColor3 = "Accent" },
			Parent = self._scroller,
		}, { Util.corner(6) })

		Util.create("TextLabel", {
			Name = "Label",
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -40, 1, 0),
			Text = option,
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Theme = { TextColor3 = "TextDim" },
			Parent = button,
		})

		local check = Util.glyph("check", { Size = 14, Color = "Accent" })
		check.AnchorPoint = Vector2.new(1, 0.5)
		check.Position = UDim2.new(1, -10, 0.5, 0)
		check.Visible = false
		check.Parent = button

		self.Maid:Give(button.MouseEnter:Connect(function()
			if not self:_isSelected(option) then
				Theme.animate(button, { BackgroundColor3 = "ElementHover", BackgroundTransparency = "HoverTransparency" })
			end
		end))
		self.Maid:Give(button.MouseLeave:Connect(function()
			self:_paintOption(option)
		end))
		self.Maid:Give(button.Activated:Connect(function()
			self:_choose(option)
		end))

		self._buttons[option] = button
	end
	self:_filter()
end

function Dropdown:_paintOption(option)
	local button = self._buttons[option]
	if not button then
		return
	end
	local selected = self:_isSelected(option)
	Theme.animate(button, {
		BackgroundColor3 = selected and "Accent" or "ElementHover",
		BackgroundTransparency = selected and 0.86 or 1,
	})
	Theme.animate(button.Label, { TextColor3 = selected and "Text" or "TextDim" })
	button.Glyph.Visible = selected
end

function Dropdown:_filter()
	local visible = 0
	local query = self._query
	for _, option in ipairs(self._list) do
		local button = self._buttons[option]
		local show = query == "" or string.find(string.lower(option), query, 1, true) ~= nil
		button.Visible = show
		if show then
			visible += 1
		end
		self:_paintOption(option)
	end
	self._visibleCount = visible
	self._empty.Visible = visible == 0
	local rows = math.clamp(visible, 1, self._maxVisible)
	self._scroller.Size = UDim2.new(1, 0, 0, rows * OPTION_HEIGHT + (rows - 1) * OPTION_GAP)
	if self.Expanded then
		self:_setExpanded(true, self:_panelHeight())
	end
end

function Dropdown:_searchEnabled()
	if self._search ~= nil then
		return self._search == true
	end
	return #self._list > 7
end

function Dropdown:_panelHeight()
	local rows = math.clamp(self._visibleCount or #self._list, 1, self._maxVisible)
	local list = rows * OPTION_HEIGHT + (rows - 1) * OPTION_GAP
	local search = self._searchBox.Visible and (SEARCH_HEIGHT + 6) or 0
	return search + list + 10
end

function Dropdown:_refreshDisplay()
	local text, placeholder
	if self.Multi then
		local count = #self.Value
		if count == 0 then
			text, placeholder = self._placeholder, true
		elseif count <= 2 then
			text = table.concat(self.Value, ", ")
		else
			text = ("%d selected"):format(count)
		end
	else
		text = self.Value or self._placeholder
		placeholder = self.Value == nil
	end
	self._valueLabel.Text = text
	Theme.animate(self._valueLabel, { TextColor3 = placeholder and "TextMuted" or "Text" })
end

function Dropdown:_choose(option)
	if self.Disabled then
		return
	end
	if self.Multi then
		local value = self:_copyValue()
		local index = table.find(value, option)
		if index then
			table.remove(value, index)
		else
			table.insert(value, option)
		end
		self:Set(value)
	else
		if self.Value == option then
			if self._allowNone then
				self:Set(nil)
			end
		else
			self:Set(option)
		end
		self:Close()
	end
end

function Dropdown:_onClick()
	if self.Expanded then
		self:Close()
	else
		self:Open()
	end
end

function Dropdown:_onExpanded(expanded)
	Spring.animate(self._chevron, "Bouncy", { Rotation = expanded and 180 or 0 })
	local stroke = self._box:FindFirstChildOfClass("UIStroke")
	if stroke then
		Theme.animate(stroke, {
			Color = expanded and "Accent" or "Stroke",
			Transparency = expanded and 0.4 or "StrokeTransparency",
		})
	end
end

function Dropdown:Open()
	if self.Disabled then
		return self
	end
	self._searchBox.Visible = self:_searchEnabled()
	self._searchInput.Text = ""
	self._query = ""
	self:_filter()
	self:_setExpanded(true, self:_panelHeight())
	return self
end

function Dropdown:Close()
	self:_setExpanded(false, 0)
	return self
end

-- dropdown:Set("Bow") · multi: dropdown:Set({ "A", "B" }) · dropdown:Set(nil) clears.
function Dropdown:Set(value, silent, force)
	local before = self.Multi and table.concat(self.Value, "\0") or self.Value
	self:_apply(value)
	local after = self.Multi and table.concat(self.Value, "\0") or self.Value
	for _, option in ipairs(self._list) do
		self:_paintOption(option)
	end
	self:_refreshDisplay()
	if before == after and not force then
		return self
	end
	self:_publish(self:_copyValue())
	if not silent then
		self.Changed:Fire(self:_copyValue())
	end
	return self
end

function Dropdown:Get()
	return self:_copyValue()
end

-- Replaces the option list. The current selection is kept where possible.
function Dropdown:SetOptions(list, keepSelection)
	self._list = toList(list)
	self.Values = self._list
	local previous = self:_copyValue()
	self:_buildOptions()
	if keepSelection == false then
		self:Set(self.Multi and {} or nil)
	else
		self:Set(previous)
	end
	return self
end

Dropdown.Refresh = Dropdown.SetOptions

function Dropdown:Add(option)
	option = tostring(option)
	if not table.find(self._list, option) then
		local list = table.clone(self._list)
		table.insert(list, option)
		self:SetOptions(list)
	end
	return self
end

function Dropdown:Remove(option)
	local list = table.clone(self._list)
	local index = table.find(list, tostring(option))
	if index then
		table.remove(list, index)
		self:SetOptions(list)
	end
	return self
end

function Dropdown:Clear()
	return self:Set(self.Multi and {} or nil)
end

function Dropdown:_serialize()
	return self:_copyValue()
end

function Dropdown:_display()
	if self.Multi then
		return #self.Value == 0 and "None" or table.concat(self.Value, ", ")
	end
	return self.Value or "None"
end

-- Used by pinned widgets: moves a single-select dropdown to the next option.
function Dropdown:Cycle(direction)
	if self.Multi or #self._list == 0 then
		return self
	end
	local index = table.find(self._list, self.Value) or 0
	index = (index - 1 + (direction or 1)) % #self._list + 1
	return self:Set(self._list[index])
end

Elements.register("Dropdown", Dropdown)

return Dropdown
end

-- ======================================================================
-- Elements/Input
__modules["Elements/Input"] = function()
-- Aether · Elements/Input
--   Tab:Input({ Name = "Target", Placeholder = "Username", Callback = function(text) end })
--   Numeric = true keeps only numbers · Live = true fires on every keystroke
--   ClearOnFocus = true empties the box when clicked (Rayfield: RemoveTextAfterFocusLost)

local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Element = import("Components/Element")
local Elements = import("Components/Elements")

local Input = Element.extend("Input")
Input.Saveable = true

function Input.new(section, options)
	local self = setmetatable({}, Input)
	self._numeric = options.Numeric == true
	self._live = options.Live == true or options.Finished == false
	self._maxLength = tonumber(options.MaxLength)
	self._clearAfter = options.RemoveTextAfterFocusLost == true

	local touch = section.Window.IsTouch
	Element.init(self, section, options, {
		ControlWidth = options.Width or (touch and 150 or 176),
		ControlHeight = 30,
	})

	local box = Util.create("Frame", {
		Name = "Box",
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Theme = {
			BackgroundColor3 = "Input",
			BackgroundTransparency = "InputTransparency",
		},
		Parent = self.Control,
	}, {
		Util.corner(7),
		Util.stroke(),
	})
	self._stroke = box:FindFirstChildOfClass("UIStroke")

	local textBox = Util.create("TextBox", {
		Name = "TextBox",
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -20, 1, 0),
		PlaceholderText = tostring(options.Placeholder or options.PlaceholderText or "Type here..."),
		TextSize = 13,
		ClearTextOnFocus = options.ClearOnFocus == true or options.ClearTextOnFocus == true,
		Theme = { TextColor3 = "Text", PlaceholderColor3 = "TextMuted" },
		Parent = box,
	})
	self.TextBox = textBox

	local default = options.Default or options.Value or options.CurrentValue or options.Text or ""
	self._default = tostring(default)
	self._committed = self._default
	textBox.Text = self._default
	self:_publish(self._default)

	self.Maid:Give(textBox.Focused:Connect(function()
		if self._stroke then
			Theme.animate(self._stroke, { Color = "Accent", Transparency = 0.3 })
		end
	end))

	self.Maid:Give(textBox:GetPropertyChangedSignal("Text"):Connect(function()
		local text = textBox.Text
		local cleaned = text
		if self._numeric then
			cleaned = string.gsub(cleaned, "[^%d%.%-]", "")
		end
		if self._maxLength and #cleaned > self._maxLength then
			cleaned = string.sub(cleaned, 1, self._maxLength)
		end
		if cleaned ~= text then
			textBox.Text = cleaned
			return
		end
		if self._live then
			self:_commit(cleaned)
		end
	end))

	self.Maid:Give(textBox.FocusLost:Connect(function(enterPressed)
		if self._stroke then
			Theme.animate(self._stroke, { Color = "Stroke", Transparency = "StrokeTransparency" })
		end
		self:_commit(textBox.Text, enterPressed)
		if self._clearAfter then
			textBox.Text = ""
		end
	end))

	return self:_ready()
end

function Input:_commit(text, enterPressed)
	if text == self._committed then
		return
	end
	self._committed = text
	self:_publish(text)
	self.Changed:Fire(text, enterPressed == true)
end

function Input:Set(text, silent, force)
	text = text == nil and "" or tostring(text)
	if text == self._committed and not force then
		return self
	end
	self._committed = text
	self.TextBox.Text = text
	self:_publish(text)
	if not silent then
		self.Changed:Fire(text, false)
	end
	return self
end

function Input:Get()
	return self.Value
end

function Input:Focus()
	self.TextBox:CaptureFocus()
	return self
end

function Input:SetPlaceholder(text)
	self.TextBox.PlaceholderText = tostring(text)
	return self
end

function Input:_display()
	return self.Value ~= "" and self.Value or "Empty"
end

Elements.register("Input", Input)

return Input
end

-- ======================================================================
-- Elements/Keybind
__modules["Elements/Keybind"] = function()
-- Aether · Elements/Keybind
--   Tab:Keybind({ Name = "Dash", Default = "Q", Callback = function() end })
-- Mode:
--   "Press"  (default) the callback runs on every press
--   "Toggle" each press flips an on/off state: callback(state)
--   "Hold"   callback(true) on press, callback(false) on release
-- OnBindChanged(key) runs when the user picks a different key.

local Util = import("Core/Util")
local Signal = import("Core/Signal")
local Element = import("Components/Element")
local Elements = import("Components/Elements")
local KeyChip = import("Components/KeyChip")

local Keybind = Element.extend("Keybind")
Keybind.Saveable = true
Keybind.Pinnable = true

local MODES = { Press = true, Toggle = true, Hold = true }

function Keybind.new(section, options)
	local self = setmetatable({}, Keybind)
	local mode = options.Mode
	if options.HoldToInteract == true then
		mode = "Hold"
	end
	self.Mode = MODES[mode] and mode or "Press"
	self.State = false

	Element.init(self, section, options, {
		ControlWidth = 40,
		ControlHeight = 26,
		Hover = true,
	})
	self.BindChanged = Signal.new(("Keybind '%s' changed"):format(self.Name))

	Util.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = self.Control,
	})

	self._chip = KeyChip.new({
		Parent = self.Control,
		Maid = self.Maid,
		ShowWhenEmpty = true,
		AllowMouse = options.AllowMouse ~= false,
		OnResize = function(width)
			self:_setControlWidth(math.max(width, 28))
		end,
		OnChanged = function(key)
			self:_publish(key and key.Name or nil)
			self.Key = key
			self.BindChanged:Fire(key)
		end,
		OnTriggered = function(began)
			self:_trigger(began)
		end,
	})

	local default = options.Default or options.Key or options.CurrentKeybind or options.Value
	self._chip:SetKey(default, true)
	self.Key = self._chip.Key
	self._default = self.Key and self.Key.Name or nil
	self:_publish(self._default)

	if type(options.ChangedCallback) == "function" then
		self.BindChanged:Connect(options.ChangedCallback)
	end
	if type(options.OnBindChanged) == "function" then
		self.BindChanged:Connect(options.OnBindChanged)
	end

	return self:_ready()
end

function Keybind:_publish(value)
	Element._publish(self, value)
	self.CurrentKeybind = value or "None" -- Rayfield's name for it
end

function Keybind:_trigger(began)
	if self.Disabled then
		return
	end
	if self.Mode == "Hold" then
		self.State = began
		self.Changed:Fire(began)
	elseif began then
		if self.Mode == "Toggle" then
			self.State = not self.State
			self.Changed:Fire(self.State)
		else
			self.Changed:Fire(true)
		end
	end
end

-- keybind:Set("E") / keybind:Set(Enum.KeyCode.E) / keybind:Set(nil)
function Keybind:Set(key, silent, _force)
	self._chip:SetKey(key, true)
	self.Key = self._chip.Key
	self:_publish(self.Key and self.Key.Name or nil)
	if not silent then
		self.BindChanged:Fire(self.Key)
	end
	return self
end

function Keybind:Get()
	return self.Key
end

function Keybind:OnBindChanged(handler)
	self.BindChanged:Connect(handler)
	return self
end

-- Waits for the user to press a new key, as if they clicked the chip.
function Keybind:Listen()
	self._chip:Listen()
	return self
end

function Keybind:_display()
	return self.Key and Util.keyName(self.Key) or "None"
end

function Keybind:Destroy()
	self.BindChanged:DisconnectAll()
	Element.Destroy(self)
end

Elements.register("Keybind", Keybind)

return Keybind
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
Label.Pinnable = true

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
Paragraph.Pinnable = true

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
-- Elements/Slider
__modules["Elements/Slider"] = function()
-- Aether · Elements/Slider
--   Tab:Slider({ Name = "WalkSpeed", Min = 16, Max = 200, Default = 16, Increment = 1, Suffix = " studs",
--                Callback = function(value) end })
-- Also accepts Rayfield's Range = { min, max } and CurrentValue, and Fluent's Rounding.

local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Spring = import("Core/Spring")
local Signal = import("Core/Signal")
local Element = import("Components/Element")
local Elements = import("Components/Elements")

local Slider = Element.extend("Slider")
Slider.Saveable = true
Slider.Pinnable = true

local VALUE_WIDTH = 72

local function decimalsOf(increment)
	local text = string.format("%.6f", increment):gsub("0+$", "")
	local dot = string.find(text, ".", 1, true)
	return dot and (#text - dot) or 0
end

function Slider.new(section, options)
	local self = setmetatable({}, Slider)

	local min, max = options.Min, options.Max
	if type(options.Range) == "table" then
		min = min or options.Range[1]
		max = max or options.Range[2]
	end
	min = tonumber(min) or 0
	max = tonumber(max) or 100
	if max < min then
		min, max = max, min
	end

	local increment = tonumber(options.Increment or options.Step)
	if not increment and tonumber(options.Rounding) then
		increment = 10 ^ -math.floor(tonumber(options.Rounding))
	end
	if not increment or increment <= 0 then
		increment = 1
	end

	self.Min, self.Max, self.Increment = min, max, increment
	self._decimals = decimalsOf(increment)

	local suffix = options.Suffix and tostring(options.Suffix) or ""
	-- "Bananas" reads better as "10 Bananas"; "%" and "s" stay attached.
	if #suffix > 1 and string.match(suffix, "^%a") then
		suffix = " " .. suffix
	end
	self._suffix = suffix

	Element.init(self, section, options, {
		Stacked = true,
		Aside = VALUE_WIDTH,
		ControlHeight = 18,
		Hover = true,
	})
	self.Released = Signal.new(("Slider '%s' released"):format(self.Name))

	-- Value box: shows the formatted value; click to type an exact number.
	local box = Util.create("TextBox", {
		Name = "Value",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		FontFace = Util.Fonts.Medium,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		ClearTextOnFocus = false,
		Theme = {
			BackgroundColor3 = "Input",
			BackgroundTransparency = "InputTransparency",
			TextColor3 = "Text",
		},
		Parent = self.Aside,
	}, { Util.corner(6) })
	self._box = box

	local track = Util.create("TextButton", {
		Name = "Track",
		Size = UDim2.fromScale(1, 1),
		Parent = self.Control,
	})

	local bar = Util.create("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 6),
		Theme = { BackgroundColor3 = "Control" },
		Parent = track,
	}, { Util.corner("full") })
	self._bar = bar

	self._fill = Util.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = bar,
	}, {
		Util.corner("full"),
		Util.create("UIGradient", { Theme = { Color = Theme.accentSequence } }),
	})

	self._glow = Util.create("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Theme = { BackgroundColor3 = "Accent" },
		Parent = bar,
	}, { Util.corner("full") })

	self._knob = Util.create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(14, 14),
		ZIndex = 3,
		Theme = { BackgroundColor3 = "Text" },
		Parent = bar,
	}, { Util.corner("full") })

	local function setFromPointer(pointer)
		local position, size = bar.AbsolutePosition, bar.AbsoluteSize
		if size.X <= 0 then
			return
		end
		local alpha = math.clamp((pointer.X - position.X) / size.X, 0, 1)
		self:Set(min + (max - min) * alpha)
	end

	Util.draggable(track, {
		Start = function(input)
			if self.Disabled then
				return false
			end
			self._dragging = true
			self:_renderKnob()
			setFromPointer(Util.pointer(input))
			return true
		end,
		Move = function(_, pointer)
			setFromPointer(pointer)
		end,
		End = function()
			self._dragging = false
			self:_renderKnob()
			self.Released:Fire(self.Value)
		end,
	}, self.Maid)

	self.Maid:Give(box.Focused:Connect(function()
		box.Text = self:_format(self.Value, false)
	end))
	self.Maid:Give(box.FocusLost:Connect(function()
		local number = tonumber((string.gsub(box.Text, "[^%d%.%-]", "")))
		if number and not self.Disabled then
			self:Set(number)
		end
		box.Text = self:_format(self.Value, true)
	end))

	local default = tonumber(options.Default or options.CurrentValue or options.Value) or min
	self._default = self:_snap(default)
	self:_publish(self._default)
	self:_render(true)
	return self:_ready()
end

-- Rounds to the increment, clamps to the range and strips float noise.
function Slider:_snap(value)
	local steps = math.floor((value - self.Min) / self.Increment + 0.5)
	local snapped = math.clamp(self.Min + steps * self.Increment, self.Min, self.Max)
	return tonumber(string.format("%." .. self._decimals .. "f", snapped))
end

function Slider:_format(value, withSuffix)
	local text = string.format("%." .. self._decimals .. "f", value)
	if withSuffix then
		text ..= self._suffix
	end
	return text
end

function Slider:_alpha()
	local span = self.Max - self.Min
	return span > 0 and (self.Value - self.Min) / span or 0
end

function Slider:_render(instant)
	local alpha = self:_alpha()
	local fillGoal = { Size = UDim2.fromScale(alpha, 1) }
	local knobGoal = { Position = UDim2.fromScale(alpha, 0.5) }
	if instant then
		Spring.stop(self._fill)
		Spring.stop(self._knob, "Position")
		Spring.stop(self._glow, "Position")
		self._fill.Size = fillGoal.Size
		self._knob.Position = knobGoal.Position
		self._glow.Position = knobGoal.Position
	else
		local preset = self._dragging and "Quick" or "Snappy"
		Spring.animate(self._fill, preset, fillGoal)
		Spring.animate(self._knob, preset, knobGoal)
		Spring.animate(self._glow, preset, knobGoal)
	end
	if not self._box:IsFocused() then
		self._box.Text = self:_format(self.Value, true)
	end
end

function Slider:_renderKnob()
	local active = self._dragging or self._hovered
	local size = self._dragging and 18 or (self._hovered and 16 or 14)
	Spring.animate(self._knob, "Bouncy", { Size = UDim2.fromOffset(size, size) })
	Spring.animate(self._glow, "Snappy", {
		Size = UDim2.fromOffset(active and 26 or 14, active and 26 or 14),
		BackgroundTransparency = active and 0.8 or 1,
	})
end

function Slider:_onHover()
	self:_renderKnob()
end

function Slider:Set(value, silent, force)
	value = tonumber(value)
	if not value then
		return self
	end
	value = self:_snap(value)
	if value == self.Value and not force then
		return self
	end
	self:_publish(value)
	self:_render(false)
	if not silent then
		self.Changed:Fire(value)
	end
	return self
end

function Slider:Get()
	return self.Value
end

-- Changes the range, keeping the value inside it.
function Slider:SetRange(min, max)
	self.Min, self.Max = tonumber(min) or self.Min, tonumber(max) or self.Max
	self:Set(self.Value, true, true)
	return self
end

-- Runs a handler when the user lets go of the slider (good for expensive work).
function Slider:OnRelease(handler)
	self.Released:Connect(handler)
	return self
end

function Slider:_display()
	return self:_format(self.Value, true)
end

function Slider:_onDisabled(disabled)
	Spring.animate(self._knob, "Snappy", { BackgroundTransparency = disabled and 0.5 or 0 })
	Spring.animate(self._fill, "Snappy", { BackgroundTransparency = disabled and 0.5 or 0 })
end

function Slider:Destroy()
	self.Released:DisconnectAll()
	Element.Destroy(self)
end

Elements.register("Slider", Slider)

return Slider
end

-- ======================================================================
-- Elements/Toggle
__modules["Elements/Toggle"] = function()
-- Aether · Elements/Toggle
--   Tab:Toggle({ Name = "Fly", Default = false, Keybind = "F", Callback = function(on) end })
--   Tab:Toggle("Fly"):Keybind("F"):OnChanged(function(on) end)

local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Spring = import("Core/Spring")
local Element = import("Components/Element")
local Elements = import("Components/Elements")
local KeyChip = import("Components/KeyChip")

local Toggle = Element.extend("Toggle")
Toggle.Saveable = true
Toggle.Pinnable = true
Toggle.Bindable = true

local TRACK_WIDTH, TRACK_HEIGHT = 40, 22
local KNOB, KNOB_PRESSED, INSET = 16, 21, 3

function Toggle.new(section, options)
	local self = setmetatable({}, Toggle)
	local default = options.Default
	if default == nil then
		default = options.CurrentValue
	end
	if default == nil then
		default = options.Value
	end
	default = default == true

	Element.init(self, section, options, {
		Clickable = true,
		ControlWidth = TRACK_WIDTH,
		ControlHeight = 26,
	})
	self._default = default
	self._pressed = false

	Util.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = self.Control,
	})

	local track = Util.create("Frame", {
		Name = "Track",
		Size = UDim2.fromOffset(TRACK_WIDTH, TRACK_HEIGHT),
		LayoutOrder = 2,
		Theme = { BackgroundColor3 = "Control" },
		Parent = self.Control,
	}, {
		Util.corner("full"),
		Util.stroke(),
	})

	self._fill = Util.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Parent = track,
	}, {
		Util.corner("full"),
		Util.create("UIGradient", { Theme = { Color = Theme.accentSequence } }),
	})

	self._knob = Util.create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, INSET, 0.5, 0),
		Size = UDim2.fromOffset(KNOB, KNOB),
		ZIndex = 2,
		Theme = { BackgroundColor3 = "TextDim" },
		Parent = track,
	}, { Util.corner("full") })

	-- Knob squish while the pointer is held down, like iOS switches.
	self.Maid:Give(self.Hitbox.InputBegan:Connect(function(input)
		if Util.isPress(input) and not self.Disabled then
			self._pressed = true
			self:_render(false)
		end
	end))
	self.Maid:Give(self.Hitbox.InputEnded:Connect(function(input)
		if Util.isPress(input) and self._pressed then
			self._pressed = false
			self:_render(false)
		end
	end))

	if options.Keybind then
		self:Keybind(options.Keybind)
	end

	self:_publish(default)
	self:_render(true)
	return self:_ready()
end

function Toggle:_render(instant)
	local on = self.Value == true
	local width = self._pressed and KNOB_PRESSED or KNOB
	local x = on and (TRACK_WIDTH - width - INSET) or INSET
	local knobGoal = { Position = UDim2.new(0, x, 0.5, 0), Size = UDim2.fromOffset(width, KNOB) }
	local fillGoal = { BackgroundTransparency = on and 0 or 1 }
	local knobColor = on and "OnAccent" or "TextDim"

	if instant then
		Spring.stop(self._knob)
		Spring.stop(self._fill)
		self._knob.Position = knobGoal.Position
		self._knob.Size = knobGoal.Size
		self._fill.BackgroundTransparency = fillGoal.BackgroundTransparency
		Theme.bind(self._knob, { BackgroundColor3 = knobColor })
	else
		Spring.animate(self._knob, "Bouncy", knobGoal)
		Spring.animate(self._fill, "Snappy", fillGoal)
		Theme.animate(self._knob, { BackgroundColor3 = knobColor })
	end
end

-- toggle:Set(true)  ·  toggle:Set(true, true) sets it without running callbacks.
function Toggle:Set(value, silent, force)
	value = value == true
	if value == self.Value and not force then
		return self
	end
	self:_publish(value)
	self:_render(false)
	if not silent then
		self.Changed:Fire(value)
	end
	return self
end

function Toggle:Toggle()
	return self:Set(not self.Value)
end

function Toggle:Get()
	return self.Value
end

function Toggle:_onClick()
	self:Toggle()
end

function Toggle:_display()
	return self.Value and "On" or "Off"
end

-- Binds a key that flips the toggle: toggle:Keybind("F")
function Toggle:Keybind(key)
	if not self._chip then
		self._chip = KeyChip.new({
			Parent = self.Control,
			LayoutOrder = 1,
			Maid = self.Maid,
			OnResize = function(width)
				self:_setControlWidth(TRACK_WIDTH + (width > 0 and width + 8 or 0))
			end,
			OnTriggered = function(began)
				if began and not self.Disabled then
					self:Toggle()
				end
			end,
		})
	end
	self._chip:SetKey(key)
	return self
end

function Toggle:GetKeybind()
	return self._chip and self._chip.Key or nil
end

function Toggle:_onDisabled(disabled)
	Spring.animate(self._knob, "Snappy", { BackgroundTransparency = disabled and 0.5 or 0 })
end

Elements.register("Toggle", Toggle)

return Toggle
end

-- ======================================================================
-- Features/Compat
__modules["Features/Compat"] = function()
-- Aether · Features/Compat
-- Makes scripts written for Rayfield run on Aether after changing the
-- loadstring line. Window options are translated here; element option names
-- (CurrentValue, Range, CurrentOption, MultipleOptions, CurrentKeybind,
-- HoldToInteract, PlaceholderText, RemoveTextAfterFocusLost...) are accepted
-- by the elements themselves, and the Create* methods keep Rayfield's
-- callback shapes (a single-select dropdown passes a table).
--
-- Not supported: GrabKeyFromSite (Aether never downloads anything on its own;
-- use Check = function(key) ... end with Aether:KeySystem instead).

local Log = import("Core/Log")

local Compat = {}

local RAYFIELD_THEMES = {
	default = "Aether",
	dark = "Aether",
	amberglow = "Rose",
	amethyst = "Midnight",
	bloom = "Rose",
	darkblue = "Midnight",
	green = "Emerald",
	light = "Light",
	ocean = "Ocean",
	serenity = "Ocean",
}

-- Maps a theme name from another library to an Aether theme (or returns it unchanged).
function Compat.themeName(name)
	if type(name) ~= "string" then
		return name
	end
	return RAYFIELD_THEMES[string.lower(name)] or name
end

-- Translates Rayfield window options into Aether ones, in place.
function Compat.windowOptions(options)
	if options.ToggleKey == nil and options.ToggleUIKeybind ~= nil then
		options.ToggleKey = options.ToggleUIKeybind
	end
	if options.Icon == 0 or options.Icon == "0" then
		options.Icon = nil
	end
	if type(options.Theme) == "string" then
		options.Theme = Compat.themeName(options.Theme)
	end

	local saving = options.ConfigurationSaving
	if type(saving) == "table" and saving.Enabled and options.AutoSave == nil then
		options.AutoSave = type(saving.FileName) == "string" and saving.FileName or "config"
		if type(saving.FolderName) == "string" and saving.FolderName ~= "" and options.ConfigFolder == nil then
			options.ConfigFolder = saving.FolderName
		end
		-- Rayfield scripts restore values by calling :LoadConfiguration() at the end.
		options.__deferAutoSave = true
	end
	return options
end

-- Rayfield's KeySettings -> Aether:KeySystem options (nil when no key system).
function Compat.keySystem(options)
	if options.KeySystem ~= true or type(options.KeySettings) ~= "table" then
		return nil
	end
	local settings = options.KeySettings
	if settings.GrabKeyFromSite then
		Log.warn("GrabKeyFromSite isn't supported: Aether never downloads anything on its own. Put the keys in Key, or use Aether:KeySystem with a Check function.")
	end
	local keys = settings.Key
	if type(keys) == "string" then
		keys = { keys }
	end
	return {
		Title = settings.Title or options.Name,
		Subtitle = settings.Subtitle,
		Note = settings.Note,
		Keys = type(keys) == "table" and keys or {},
		SaveKey = settings.SaveKey ~= false,
	}
end

-- Notification actions may be a Rayfield-style dictionary: { Ignore = { Name = ..., Callback = ... } }
function Compat.actionList(actions)
	if type(actions) ~= "table" then
		return nil
	end
	if #actions > 0 then
		return actions
	end
	local list = {}
	for _, action in pairs(actions) do
		if type(action) == "table" then
			table.insert(list, action)
		end
	end
	return #list > 0 and list or nil
end

return Compat
end

-- ======================================================================
-- Features/Config
__modules["Features/Config"] = function()
-- Aether · Features/Config
-- Saves and loads element values, share codes, and interface preferences.
--
-- Every element with a value is saved automatically, keyed by its Flag, or
-- by "Tab/Section/Name" when it has none. Opt out with Save = false.
-- Values for elements that don't exist yet are kept and applied the moment
-- the element is created, so loading never depends on timing.
--
-- Files (executor workspace):
--   Aether/<Window>/configs/<name>.json
--   Aether/<Window>/autoload.txt
--   Aether/<Window>/interface.json    theme, toggle key, pinned widgets...

local Env = import("Core/Env")
local Log = import("Core/Log")
local Base64 = import("Core/Base64")

local HttpService = Env.service("HttpService")

local Config = {}
Config.__index = Config

local CONFIG_PREFIX = "AE1:"

local function sanitize(name)
	name = string.gsub(tostring(name or ""), "[^%w%-_ %.%(%)]", "")
	name = string.gsub(name, "^%s+", "")
	name = string.gsub(name, "%s+$", "")
	return name
end

Config.sanitize = sanitize

local function encode(data)
	local ok, text = pcall(function()
		return HttpService:JSONEncode(data)
	end)
	return ok and text or nil
end

local function decode(text)
	if type(text) ~= "string" then
		return nil
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(text)
	end)
	return ok and type(data) == "table" and data or nil
end

Config.encode = encode
Config.decode = decode

function Config.new(window)
	local options = window.Options
	local folder = options.ConfigFolder
	if type(folder) ~= "string" or folder == "" then
		folder = "Aether/" .. (sanitize(window.Name) ~= "" and sanitize(window.Name) or "Window")
	end
	if options.PerGame then
		folder ..= "/" .. tostring(game.PlaceId)
	end
	return setmetatable({
		Window = window,
		Folder = folder,
		_pending = {},
	}, Config)
end

function Config:_path(name)
	return self.Folder .. "/configs/" .. name .. ".json"
end

local function saveable(element)
	return element.Saveable and element._save and not element.Destroyed
end

-- id -> JSON-safe value for every saveable element.
function Config:Collect()
	local values = {}
	for _, element in ipairs(self.Window.Elements) do
		if saveable(element) then
			local ok, value = pcall(element._serialize, element)
			if ok and value ~= nil then
				values[element:GetId()] = value
			end
		end
	end
	for id, value in pairs(self._pending) do
		if values[id] == nil then
			values[id] = value
		end
	end
	return values
end

-- Applies values; ones for elements that don't exist yet wait for them.
function Config:Apply(values)
	local byId = {}
	for _, element in ipairs(self.Window.Elements) do
		if saveable(element) then
			byId[element:GetId()] = element
		end
	end
	local applied = 0
	for id, value in pairs(values) do
		local element = byId[id]
		if element then
			local ok, err = pcall(element._deserialize, element, value)
			if ok then
				applied += 1
			else
				Log.warn(("Couldn't load a value for '%s': %s"):format(id, tostring(err)))
			end
		else
			self._pending[id] = value
		end
	end
	return applied
end

-- Called when an element finishes building. Deferred so the script that
-- creates the element has finished its line before callbacks run.
function Config:_elementReady(element)
	local id = element:GetId()
	local value = self._pending[id]
	if value == nil or not saveable(element) then
		return
	end
	self._pending[id] = nil
	task.defer(function()
		if not element.Destroyed then
			local ok, err = pcall(element._deserialize, element, value)
			if not ok then
				Log.warn(("Couldn't load a value for '%s': %s"):format(id, tostring(err)))
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Named configs
---------------------------------------------------------------------------

function Config:Save(name)
	name = sanitize(name)
	if name == "" then
		return false, "Enter a name for the config"
	end
	local text = encode({ Aether = 1, Values = self:Collect() })
	if not text then
		return false, "Couldn't encode the config"
	end
	if not Env.writeFile(self:_path(name), text) then
		return false, "Couldn't write the config file"
	end
	return true
end

function Config:Load(name)
	name = sanitize(name)
	if name == "" then
		return false, "Pick a config to load"
	end
	local data = decode(Env.readFile(self:_path(name)))
	if not data then
		return false, ("Config '%s' wasn't found"):format(name)
	end
	if type(data.Values) ~= "table" then
		return false, ("Config '%s' is damaged"):format(name)
	end
	return true, self:Apply(data.Values)
end

function Config:Delete(name)
	name = sanitize(name)
	if name == "" then
		return false, "Pick a config to delete"
	end
	if self:GetAutoload() == name then
		self:SetAutoload(nil)
	end
	return Env.deleteFile(self:_path(name))
end

function Config:List()
	local names = {}
	for _, file in ipairs(Env.listFiles(self.Folder .. "/configs")) do
		local name = string.match(file, "^(.*)%.json$")
		if name then
			table.insert(names, name)
		end
	end
	return names
end

function Config:SetAutoload(name)
	name = name and sanitize(name) or ""
	Env.writeFile(self.Folder .. "/autoload.txt", name)
	return true
end

function Config:GetAutoload()
	local name = Env.readFile(self.Folder .. "/autoload.txt")
	if type(name) == "string" and name ~= "" then
		return name
	end
	return nil
end

function Config:LoadAutoload()
	local name = self:GetAutoload()
	if not name then
		return false
	end
	return self:Load(name)
end

---------------------------------------------------------------------------
-- Share codes
---------------------------------------------------------------------------

function Config:Export()
	return CONFIG_PREFIX .. Base64.encode(encode({ V = self:Collect() }) or "{}")
end

function Config:Import(code)
	code = string.gsub(tostring(code or ""), "%s", "")
	if string.sub(code, 1, #CONFIG_PREFIX) ~= CONFIG_PREFIX then
		return false, "That isn't an Aether config code"
	end
	local json = Base64.decode(string.sub(code, #CONFIG_PREFIX + 1))
	local data = json and decode(json)
	if not data or type(data.V) ~= "table" then
		return false, "The code is incomplete or damaged"
	end
	return true, self:Apply(data.V)
end

---------------------------------------------------------------------------
-- Interface preferences (saved automatically)
---------------------------------------------------------------------------

function Config:SavePrefs(prefs)
	local text = encode(prefs)
	if text then
		Env.writeFile(self.Folder .. "/interface.json", text)
	end
end

function Config:LoadPrefs()
	return decode(Env.readFile(self.Folder .. "/interface.json"))
end

return Config
end

-- ======================================================================
-- Features/ContextMenu
__modules["Features/ContextMenu"] = function()
-- Aether · Features/ContextMenu
-- Right-click (or long-press) menu. Items:
--   { Text = "Pin to screen", Icon = "pin", Callback = fn, Danger = false }
--   { Separator = true }

local Env = import("Core/Env")
local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Spring = import("Core/Spring")
local Maid = import("Core/Maid")
local Log = import("Core/Log")
local Overlay = import("Features/Overlay")

local UserInputService = Env.service("UserInputService")

local ContextMenu = {}

local WIDTH = 204
local ITEM_HEIGHT = 30
local ITEM_GAP = 2
local SEPARATOR_HEIGHT = 9

local current = nil

function ContextMenu.close()
	if not current then
		return
	end
	local menu = current
	current = nil
	Spring.animate(menu.Frame, "Quick", { GroupTransparency = 1 }, function()
		menu.Maid:Clean()
	end)
	menu.Backdrop:Destroy()
end

function ContextMenu.isOpen()
	return current ~= nil
end

function ContextMenu.open(items, pointer)
	ContextMenu.close()
	if #items == 0 then
		return
	end

	local maid = Maid.new()
	local layer = Overlay.layer("Menu")

	local backdrop = Util.create("TextButton", {
		Name = "MenuBackdrop",
		Size = UDim2.fromScale(1, 1),
		Parent = layer,
	})
	maid:Give(backdrop)
	backdrop.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseButton2 or kind == Enum.UserInputType.Touch then
			ContextMenu.close()
		end
	end)

	-- Height is known up front, so the menu can be flipped to stay on screen.
	local height = 10
	for index, item in ipairs(items) do
		height += item.Separator and SEPARATOR_HEIGHT or ITEM_HEIGHT
		if index > 1 then
			height += ITEM_GAP
		end
	end

	local screen = Overlay.size()
	local x = math.clamp(pointer.X, 8, math.max(8, screen.X - WIDTH - 8))
	local y = pointer.Y + 4
	if y + height > screen.Y - 8 then
		y = math.max(8, pointer.Y - height - 4)
	end

	local frame = Util.create("CanvasGroup", {
		Name = "ContextMenu",
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(WIDTH, height),
		GroupTransparency = 1,
		ZIndex = 2,
		Parent = layer,
	}, {
		Util.corner(10),
		Util.padding(1),
	})
	maid:Give(frame)

	local card = Util.create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		Theme = { BackgroundColor3 = "Background" },
		Parent = frame,
	}, {
		Util.corner(9),
		Util.stroke(),
		Util.padding(4),
		Util.list(ITEM_GAP),
	})

	for index, item in ipairs(items) do
		if item.Separator then
			local separator = Util.create("Frame", {
				Name = "Separator",
				Size = UDim2.new(1, 0, 0, SEPARATOR_HEIGHT),
				BackgroundTransparency = 1,
				LayoutOrder = index,
				Parent = card,
			})
			Util.create("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 6, 0.5, 0),
				Size = UDim2.new(1, -12, 0, 1),
				Theme = {
					BackgroundColor3 = "Divider",
					BackgroundTransparency = "DividerTransparency",
				},
				Parent = separator,
			})
		else
			local color = item.Danger and "Danger" or "Text"
			local button = Util.create("TextButton", {
				Name = tostring(item.Text),
				Size = UDim2.new(1, 0, 0, ITEM_HEIGHT),
				LayoutOrder = index,
				BackgroundTransparency = 1,
				Theme = { BackgroundColor3 = "ElementHover" },
				Parent = card,
			}, { Util.corner(6) })

			if item.Icon then
				local icon = Util.icon(item.Icon, 14, item.Danger and "Danger" or "TextDim")
				icon.AnchorPoint = Vector2.new(0, 0.5)
				icon.Position = UDim2.new(0, 9, 0.5, 0)
				icon.Parent = button
			end

			Util.create("TextLabel", {
				Name = "Label",
				Position = UDim2.fromOffset(item.Icon and 31 or 10, 0),
				Size = UDim2.new(1, -40, 1, 0),
				Text = tostring(item.Text),
				TextSize = 13,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Theme = { TextColor3 = color },
				Parent = button,
			})

			if item.Hint then
				Util.create("TextLabel", {
					Name = "Hint",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -9, 0, 0),
					Size = UDim2.new(0, 60, 1, 0),
					Text = tostring(item.Hint),
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Right,
					Theme = { TextColor3 = "TextMuted" },
					Parent = button,
				})
			end

			button.MouseEnter:Connect(function()
				Theme.animate(button, { BackgroundTransparency = "HoverTransparency" }, "Quick")
			end)
			button.MouseLeave:Connect(function()
				Theme.animate(button, { BackgroundTransparency = 1 }, "Quick")
			end)
			button.Activated:Connect(function()
				ContextMenu.close()
				if type(item.Callback) == "function" then
					task.spawn(function()
						local ok, err = pcall(item.Callback)
						if not ok then
							Log.error("Menu action failed: " .. tostring(err))
						end
					end)
				end
			end)
		end
	end

	local scale = Util.create("UIScale", { Scale = 0.94, Parent = frame })
	Spring.animate(scale, "Bouncy", { Scale = 1 })
	Spring.animate(frame, "Quick", { GroupTransparency = 0 })

	maid:Give(UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			ContextMenu.close()
		end
	end))

	current = { Frame = frame, Backdrop = backdrop, Maid = maid }
end

return ContextMenu
end

-- ======================================================================
-- Features/Dialog
__modules["Features/Dialog"] = function()
-- Aether · Features/Dialog
--   Window:Dialog({
--       Title = "Unload?",
--       Content = "This removes the interface.",
--       Buttons = {
--           { Name = "Cancel" },
--           { Name = "Unload", Danger = true, Callback = function() ... end },
--       },
--   })
-- A button with Primary = true gets the accent style. Clicking the dimmed
-- background cancels unless Dismissible = false.

local Env = import("Core/Env")
local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Spring = import("Core/Spring")
local Maid = import("Core/Maid")
local Log = import("Core/Log")

local UserInputService = Env.service("UserInputService")

local Dialog = {}

local function styleButton(button, spec)
	if spec.Primary then
		button.BackgroundColor3 = Color3.new(1, 1, 1)
		button.BackgroundTransparency = 0
		Theme.bind(button, { TextColor3 = "OnAccent" })
		Util.create("UIGradient", { Theme = { Color = Theme.accentSequence }, Parent = button })
	elseif spec.Danger then
		button.BackgroundTransparency = 0
		Theme.bind(button, { BackgroundColor3 = "Danger" })
		button.TextColor3 = Color3.new(1, 1, 1)
	else
		Theme.bind(button, {
			BackgroundColor3 = "Input",
			BackgroundTransparency = "InputTransparency",
			TextColor3 = "Text",
		})
		Util.stroke().Parent = button
	end
end

function Dialog.open(window, options)
	options = options or {}
	local root = window._root
	local maid = Maid.new()
	local closed = false
	local dialog = {}

	local shade = Util.create("TextButton", {
		Name = "DialogShade",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 50,
		Theme = { BackgroundColor3 = "Shadow" },
		Parent = root,
	}, { Util.corner(12) })
	maid:Give(shade)

	local frame = Util.create("CanvasGroup", {
		Name = "Dialog",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(math.min(340, window._size.X - 40), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		GroupTransparency = 1,
		ZIndex = 51,
		Parent = root,
	}, {
		Util.corner(12),
		Util.padding(1),
	})
	maid:Give(frame)
	local scale = Util.create("UIScale", { Scale = 0.94, Parent = frame })

	local card = Util.create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Theme = { BackgroundColor3 = "Background" },
		Parent = frame,
	}, {
		Util.corner(11),
		Util.stroke(),
		Util.padding(18),
		Util.list(8),
	})

	Util.create("TextLabel", {
		Name = "Title",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = tostring(options.Title or "Are you sure?"),
		FontFace = Util.Fonts.Bold,
		TextSize = 16,
		TextWrapped = true,
		LayoutOrder = 1,
		Theme = { TextColor3 = "Text" },
		Parent = card,
	})

	local content = options.Content or options.Description or options.Text
	if content then
		Util.create("TextLabel", {
			Name = "Content",
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = tostring(content),
			TextSize = 13,
			TextWrapped = true,
			LayoutOrder = 2,
			Theme = { TextColor3 = "TextDim" },
			Parent = card,
		})
	end

	local row = Util.create("Frame", {
		Name = "Buttons",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = card,
	}, {
		Util.list(8, Enum.FillDirection.Horizontal, Enum.VerticalAlignment.Bottom, Enum.HorizontalAlignment.Right),
	})

	local function close()
		if closed then
			return
		end
		closed = true
		dialog.Open = false
		Spring.animate(shade, "Snappy", { BackgroundTransparency = 1 })
		Spring.animate(scale, "Snappy", { Scale = 0.96 })
		Spring.animate(frame, "Snappy", { GroupTransparency = 1 }, function()
			maid:Clean()
		end)
	end

	local buttons = options.Buttons or {
		{ Name = "Cancel" },
		{ Name = "OK", Primary = true, Callback = options.Callback },
	}
	for index, spec in ipairs(buttons) do
		local button = Util.create("TextButton", {
			Name = tostring(spec.Name or spec.Title),
			Size = UDim2.fromOffset(0, 32),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = tostring(spec.Name or spec.Title or "OK"),
			FontFace = Util.Fonts.SemiBold,
			TextSize = 13,
			LayoutOrder = index,
			Parent = row,
		}, {
			Util.corner(8),
			Util.padding(0, 16, 0, 16),
		})
		styleButton(button, spec)
		maid:Give(button.Activated:Connect(function()
			close()
			if type(spec.Callback) == "function" then
				task.spawn(function()
					local ok, err = pcall(spec.Callback)
					if not ok then
						Log.error("Dialog button failed: " .. tostring(err))
					end
				end)
			end
		end))
	end

	if options.Dismissible ~= false then
		maid:Give(shade.Activated:Connect(close))
		maid:Give(UserInputService.InputBegan:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Escape then
				close()
			end
		end))
	end

	Spring.animate(shade, "Snappy", { BackgroundTransparency = 0.45 })
	Spring.animate(scale, "Bouncy", { Scale = 1 })
	Spring.animate(frame, "Snappy", { GroupTransparency = 0 })

	dialog.Open = true
	dialog.Close = close
	return dialog
end

return Dialog
end

-- ======================================================================
-- Features/KeySystem
__modules["Features/KeySystem"] = function()
-- Aether · Features/KeySystem (optional)
--
--   local unlocked = Aether:KeySystem({
--       Title = "My Hub",
--       Note = "Join the Discord to get a key.",
--       Link = "https://example.com/key",   -- "Get key" copies this
--       Keys = { "AETHER-1234" },           -- or: Check = function(key) return ... end
--       SaveKey = true,                     -- remember a valid key on this device
--   })
--   if not unlocked then return end
--
-- Aether never contacts any server itself: keys are checked against Keys, or
-- by your own Check function. Yields until a valid key is entered (true) or
-- the prompt is closed (false).

local Env = import("Core/Env")
local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Spring = import("Core/Spring")
local Maid = import("Core/Maid")
local Log = import("Core/Log")
local Overlay = import("Features/Overlay")
local Config = import("Features/Config")
local Notifications = import("Features/Notifications")

local KeySystem = {}

local function trim(text)
	return (string.gsub(tostring(text or ""), "^%s*(.-)%s*$", "%1"))
end

local function makeChecker(options)
	if type(options.Check) == "function" then
		return function(key)
			local ok, result = pcall(options.Check, key)
			if not ok then
				Log.error("Key check failed: " .. tostring(result))
				return false
			end
			return result == true
		end
	end
	local valid = {}
	if type(options.Keys) == "table" then
		for _, key in ipairs(options.Keys) do
			valid[trim(key)] = true
		end
	elseif type(options.Key) == "string" then
		valid[trim(options.Key)] = true
	end
	return function(key)
		return valid[key] == true
	end
end

function KeySystem.prompt(library, options)
	options = options or {}
	local title = tostring(options.Title or options.Name or "Key required")
	local check = makeChecker(options)
	local savePath = "Aether/Keys/" .. (Config.sanitize(title) ~= "" and Config.sanitize(title) or "key") .. ".txt"

	-- A saved key that still passes skips the prompt entirely.
	if options.SaveKey ~= false then
		local saved = Env.readFile(savePath)
		if saved and saved ~= "" and check(trim(saved)) then
			return true
		end
	end

	local maid = Maid.new()
	local layer = Overlay.layer("Palette")
	local thread = coroutine.running()
	local finished = false
	local waiting = false

	local backdrop = Util.create("TextButton", {
		Name = "KeyBackdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	maid:Give(backdrop)

	local width = math.min(380, Overlay.size().X - 32)
	local frame = Util.create("CanvasGroup", {
		Name = "KeySystem",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		GroupTransparency = 1,
		ZIndex = 2,
		Parent = layer,
	}, {
		Util.corner(14),
		Util.padding(1),
	})
	maid:Give(frame)
	local scale = Util.create("UIScale", { Scale = 0.94, Parent = frame })

	local card = Util.create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Theme = { BackgroundColor3 = "Background" },
		Parent = frame,
	}, {
		Util.corner(13),
		Util.padding(20),
		Util.list(12),
	})
	local cardStroke = Util.stroke()
	cardStroke.Parent = card

	-- Header
	local header = Util.create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = card,
	})
	local logo = Util.create("Frame", {
		Name = "Logo",
		Size = UDim2.fromOffset(38, 38),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = header,
	}, {
		Util.corner(11),
		Util.create("UIGradient", { Rotation = 45, Theme = { Color = Theme.accentSequence } }),
	})
	local lock = Util.icon("lock", 18, "OnAccent")
	lock.AnchorPoint = Vector2.new(0.5, 0.5)
	lock.Position = UDim2.fromScale(0.5, 0.5)
	lock.Parent = logo

	Util.create("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(50, 1),
		Size = UDim2.new(1, -80, 0, 20),
		Text = title,
		FontFace = Util.Fonts.Bold,
		TextSize = 16,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "Text" },
		Parent = header,
	})
	Util.create("TextLabel", {
		Name = "Subtitle",
		Position = UDim2.fromOffset(50, 21),
		Size = UDim2.new(1, -80, 0, 16),
		Text = tostring(options.Subtitle or "Enter your key to continue"),
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "TextDim" },
		Parent = header,
	})

	local close = Util.create("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(24, 24),
		Parent = header,
	})
	local closeGlyph = Util.glyph("close", { Size = 11, Color = "TextMuted", Thickness = 1.5 })
	closeGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
	closeGlyph.Position = UDim2.fromScale(0.5, 0.5)
	closeGlyph.Parent = close

	if options.Note then
		Util.create("TextLabel", {
			Name = "Note",
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = tostring(options.Note),
			TextSize = 13,
			TextWrapped = true,
			LayoutOrder = 2,
			Theme = { TextColor3 = "TextDim" },
			Parent = card,
		})
	end

	-- Key field
	local field = Util.create("Frame", {
		Name = "Field",
		Size = UDim2.new(1, 0, 0, 38),
		LayoutOrder = 3,
		Theme = {
			BackgroundColor3 = "Input",
			BackgroundTransparency = "InputTransparency",
		},
		Parent = card,
	}, { Util.corner(8) })
	local fieldStroke = Util.stroke()
	fieldStroke.Parent = field
	local keyIcon = Util.icon("key-round", 15, "TextMuted")
	keyIcon.AnchorPoint = Vector2.new(0, 0.5)
	keyIcon.Position = UDim2.new(0, 12, 0.5, 0)
	keyIcon.Parent = field
	local input = Util.create("TextBox", {
		Name = "Key",
		Position = UDim2.fromOffset(36, 0),
		Size = UDim2.new(1, -48, 1, 0),
		PlaceholderText = tostring(options.Placeholder or "Paste your key here"),
		TextSize = 14,
		ClearTextOnFocus = false,
		Theme = { TextColor3 = "Text", PlaceholderColor3 = "TextMuted" },
		Parent = field,
	})

	local status = Util.create("TextLabel", {
		Name = "Status",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "",
		TextSize = 12,
		TextWrapped = true,
		Visible = false,
		LayoutOrder = 4,
		Theme = { TextColor3 = "Danger" },
		Parent = card,
	})

	-- Buttons
	local row = Util.create("Frame", {
		Name = "Buttons",
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		LayoutOrder = 5,
		Parent = card,
	}, {
		Util.list(8, Enum.FillDirection.Horizontal, Enum.VerticalAlignment.Center, Enum.HorizontalAlignment.Right),
	})

	local hasLink = type(options.Link) == "string" and options.Link ~= ""
	local getKey
	if hasLink then
		getKey = Util.create("TextButton", {
			Name = "GetKey",
			Size = UDim2.new(0.5, -4, 1, 0),
			Text = "Get key",
			FontFace = Util.Fonts.SemiBold,
			TextSize = 13,
			LayoutOrder = 1,
			Theme = {
				BackgroundColor3 = "Input",
				BackgroundTransparency = "InputTransparency",
				TextColor3 = "Text",
			},
			Parent = row,
		}, {
			Util.corner(8),
			Util.stroke(),
		})
	end

	local submit = Util.create("TextButton", {
		Name = "Continue",
		Size = UDim2.new(hasLink and 0.5 or 1, hasLink and -4 or 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		Text = "Continue",
		FontFace = Util.Fonts.SemiBold,
		TextSize = 13,
		LayoutOrder = 2,
		Theme = { TextColor3 = "OnAccent" },
		Parent = row,
	}, {
		Util.corner(8),
		Util.create("UIGradient", { Theme = { Color = Theme.accentSequence } }),
	})

	local function finish(result)
		if finished then
			return
		end
		finished = true
		Spring.animate(backdrop, "Snappy", { BackgroundTransparency = 1 })
		Spring.animate(scale, "Snappy", { Scale = 0.96 })
		Spring.animate(frame, "Snappy", { GroupTransparency = 1 }, function()
			maid:Clean()
		end)
		if type(options.Callback) == "function" then
			task.spawn(options.Callback, result)
		end
		if waiting then
			waiting = false
			task.spawn(thread, result)
		end
	end

	local function shake()
		local base = UDim2.fromScale(0.5, 0.5)
		frame.Position = base + UDim2.fromOffset(14, 0)
		Spring.target(frame, 0.25, 7, { Position = base })
	end

	local checking = false
	local function attempt()
		if checking or finished then
			return
		end
		local key = trim(input.Text)
		if key == "" then
			status.Text = "Enter a key first."
			Theme.bind(status, { TextColor3 = "Danger" })
			status.Visible = true
			shake()
			return
		end
		checking = true
		submit.Text = "Checking..."
		local valid = check(key)
		checking = false
		if finished then
			return
		end
		if valid then
			submit.Text = "Unlocked"
			status.Visible = false
			Theme.animate(fieldStroke, { Color = "Success", Transparency = 0.2 })
			if options.SaveKey ~= false then
				Env.writeFile(savePath, key)
			end
			task.delay(0.45, function()
				finish(true)
			end)
		else
			submit.Text = "Continue"
			status.Text = tostring(options.InvalidText or "That key isn't valid. Check it and try again.")
			Theme.bind(status, { TextColor3 = "Danger" })
			status.Visible = true
			Theme.animate(fieldStroke, { Color = "Danger", Transparency = 0.2 })
			shake()
		end
	end

	maid:Give(submit.Activated:Connect(attempt))
	maid:Give(input.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			attempt()
		end
	end))
	maid:Give(input:GetPropertyChangedSignal("Text"):Connect(function()
		if status.Visible then
			status.Visible = false
			Theme.animate(fieldStroke, { Color = "Stroke", Transparency = "StrokeTransparency" })
		end
	end))
	maid:Give(close.Activated:Connect(function()
		finish(false)
	end))
	if getKey then
		maid:Give(getKey.Activated:Connect(function()
			if Env.copy(options.Link) then
				Notifications.notify({ Title = "Link copied", Content = "Open it in your browser to get a key.", Type = "Success" })
			else
				status.Text = "Get your key at: " .. options.Link
				status.Visible = true
				Theme.bind(status, { TextColor3 = "TextDim" })
			end
		end))
	end

	Spring.animate(backdrop, "Snappy", { BackgroundTransparency = 0.45 })
	Spring.animate(scale, "Bouncy", { Scale = 1 })
	Spring.animate(frame, "Snappy", { GroupTransparency = 0 })

	-- Unload while waiting: resolve as closed.
	maid:Give(library.Unloaded:Connect(function()
		finish(false)
	end))

	if type(options.Callback) == "function" and options.Yield == false then
		return nil
	end
	waiting = true
	return coroutine.yield()
end

return KeySystem
end

-- ======================================================================
-- Features/Notifications
__modules["Features/Notifications"] = function()
-- Aether · Features/Notifications
--   Aether:Notify({ Title = "Saved", Content = "Config 'Legit' saved.", Type = "Success", Duration = 4 })
--   Aether:Notify({ Title = "Teleported", Actions = { { Name = "Undo", Callback = fn } } })
-- Types: Info (default), Success, Warning, Error. Duration = false keeps it until closed.
-- Stacked bottom-right on desktop, top-centre on touch devices. Hovering pauses the timer.

local Env = import("Core/Env")
local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Spring = import("Core/Spring")
local Signal = import("Core/Signal")
local Maid = import("Core/Maid")
local Log = import("Core/Log")
local Overlay = import("Features/Overlay")
local Compat = import("Features/Compat")

local RunService = Env.service("RunService")
local GuiService = Env.service("GuiService")

local Notifications = {}

local WIDTH = 320
local GAP = 10
local MARGIN = 16
local MAX_VISIBLE = 5

local KINDS = {
	info = { Icon = "info", Color = "Accent" },
	success = { Icon = "check-circle", Color = "Success" },
	warning = { Icon = "alert-triangle", Color = "Warning" },
	error = { Icon = "alert-circle", Color = "Danger" },
}

local cards = {} -- oldest first
local heartbeat = nil

local Notification = {}
Notification.__index = Notification

local function layout()
	local touch = Util.isTouch()
	local inset = GuiService:GetGuiInset()
	local offset = 0
	for index = #cards, 1, -1 do
		local card = cards[index]
		local height = card.Frame.AbsoluteSize.Y
		local goal
		if touch then
			goal = UDim2.new(0.5, 0, 0, inset.Y + 10 + offset)
		else
			goal = UDim2.new(1, -MARGIN, 1, -MARGIN - offset)
		end
		card._goal = goal
		if card._entered then
			Spring.animate(card.Frame, "Gentle", { Position = goal })
		elseif height > 0 then
			-- First layout with a real height: slide in from the edge.
			card._entered = true
			card.Frame.Position = touch and (goal + UDim2.fromOffset(0, -18)) or (goal + UDim2.fromOffset(48, 0))
			Spring.animate(card.Frame, "Gentle", { Position = goal })
			Spring.animate(card.Frame, "Snappy", { GroupTransparency = 0 })
		end
		offset += height + GAP
	end
end

local function ensureHeartbeat()
	if heartbeat then
		return
	end
	heartbeat = RunService.Heartbeat:Connect(function(dt)
		for _, card in ipairs(table.clone(cards)) do
			if card.Duration and not card.Paused then
				card.Remaining -= dt
				card._progress.Size = UDim2.fromScale(math.clamp(card.Remaining / card.Duration, 0, 1), 1)
				if card.Remaining <= 0 then
					card:Dismiss()
				end
			end
		end
		if #cards == 0 and heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end
	end)
end

local function actionButton(action, primary, parent, onDone)
	local button = Util.create("TextButton", {
		Name = tostring(action.Name or action.Title or "Action"),
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = tostring(action.Name or action.Title or "OK"),
		TextSize = 12,
		FontFace = Util.Fonts.SemiBold,
		Theme = {
			BackgroundColor3 = "Input",
			BackgroundTransparency = "InputTransparency",
			TextColor3 = primary and "Accent" or "Text",
		},
		Parent = parent,
	}, {
		Util.corner(6),
		Util.stroke(),
		Util.padding(0, 10, 0, 10),
	})
	button.Activated:Connect(function()
		if type(action.Callback) == "function" then
			task.spawn(function()
				local ok, err = pcall(action.Callback)
				if not ok then
					Log.error("Notification action failed: " .. tostring(err))
				end
			end)
		end
		if not action.KeepOpen then
			onDone()
		end
	end)
	return button
end

function Notifications.notify(options)
	if type(options) == "string" then
		options = { Title = options }
	end
	options = options or {}

	local kind = KINDS[string.lower(tostring(options.Type or options.Kind or "info"))] or KINDS.info
	local title = tostring(options.Title or options.Name or "Notification")
	local content = options.Content or options.Description or options.Text
	local duration = options.Duration
	if duration == nil then
		duration = 4 + (content and math.min(#tostring(content) / 40, 4) or 0)
	end
	if duration == false or duration == 0 then
		duration = nil
	end

	local self = setmetatable({}, Notification)
	self.Maid = Maid.new()
	self.Dismissed = Signal.new("Notification.Dismissed")
	self.Duration = duration
	self.Remaining = duration or 0
	self.Paused = false

	local touch = Util.isTouch()
	local layer = Overlay.layer("Notifications")
	local width = touch and math.min(WIDTH, layer.AbsoluteSize.X - 24) or WIDTH

	local frame = Util.create("CanvasGroup", {
		Name = "Notification",
		AnchorPoint = touch and Vector2.new(0.5, 0) or Vector2.new(1, 1),
		Position = touch and UDim2.new(0.5, 0, 0, -200) or UDim2.new(1, 400, 1, -MARGIN),
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		GroupTransparency = 1,
		Parent = layer,
	}, {
		Util.corner(12),
		Util.padding(1),
	})
	self.Frame = frame
	self.Maid:Give(frame)

	local card = Util.create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Theme = { BackgroundColor3 = "Background" },
		Parent = frame,
	}, {
		Util.corner(11),
		Util.stroke(),
		Util.padding(12, 12, 14, 12),
	})

	local tile = Util.create("Frame", {
		Name = "Tile",
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 0.84,
		Theme = { BackgroundColor3 = kind.Color },
		Parent = card,
	}, { Util.corner(8) })
	local icon = Util.icon(options.Icon or options.Image or kind.Icon, 16, kind.Color)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Parent = tile

	local body = Util.create("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -66, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = card,
	}, { Util.list(3) })

	self._title = Util.create("TextLabel", {
		Name = "Title",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = title,
		FontFace = Util.Fonts.SemiBold,
		TextSize = 14,
		TextWrapped = true,
		LayoutOrder = 1,
		Theme = { TextColor3 = "Text" },
		Parent = body,
	})

	self._content = Util.create("TextLabel", {
		Name = "Content",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = content and tostring(content) or "",
		TextSize = 13,
		TextWrapped = true,
		Visible = content ~= nil and content ~= "",
		LayoutOrder = 2,
		Theme = { TextColor3 = "TextDim" },
		Parent = body,
	})

	local actions = Compat.actionList(options.Actions or options.Buttons)
	if actions then
		local row = Util.create("Frame", {
			Name = "Actions",
			Size = UDim2.new(1, 0, 0, 32),
			BackgroundTransparency = 1,
			LayoutOrder = 3,
			Parent = body,
		}, {
			Util.list(6, Enum.FillDirection.Horizontal, Enum.VerticalAlignment.Bottom),
		})
		for index, action in ipairs(actions) do
			actionButton(action, index == 1, row, function()
				self:Dismiss()
			end)
		end
	end

	local close = Util.create("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(20, 20),
		Parent = card,
	})
	local closeGlyph = Util.glyph("close", { Size = 10, Color = "TextMuted", Thickness = 1.5 })
	closeGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
	closeGlyph.Position = UDim2.fromScale(0.5, 0.5)
	closeGlyph.Parent = close
	self.Maid:Give(close.Activated:Connect(function()
		self:Dismiss()
	end))

	-- Time left, shrinking along the bottom edge.
	self._progress = Util.create("Frame", {
		Name = "Progress",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = duration ~= nil,
		ZIndex = 2,
		Parent = frame,
	})
	Util.create("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = frame,
	}, { self._progress })
	self._progress.Size = UDim2.fromScale(1, 1)
	Util.create("UIGradient", { Theme = { Color = Theme.accentSequence }, Parent = self._progress })

	self.Maid:Give(frame.MouseEnter:Connect(function()
		self.Paused = true
	end))
	self.Maid:Give(frame.MouseLeave:Connect(function()
		self.Paused = false
	end))
	self.Maid:Give(frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))

	table.insert(cards, self)
	while #cards > MAX_VISIBLE do
		cards[1]:Dismiss()
	end
	task.defer(layout)
	if duration then
		ensureHeartbeat()
	end

	if type(options.Callback) == "function" then
		self.Dismissed:Connect(options.Callback)
	end
	return self
end

function Notification:Dismiss()
	if self.Leaving then
		return
	end
	self.Leaving = true
	local index = table.find(cards, self)
	if index then
		table.remove(cards, index)
	end
	layout()

	local touch = Util.isTouch()
	local goal = self._goal or self.Frame.Position
	local exit = touch and (goal + UDim2.fromOffset(0, -14)) or (goal + UDim2.fromOffset(56, 0))
	Spring.animate(self.Frame, "Snappy", { GroupTransparency = 1, Position = exit }, function()
		self.Maid:Clean()
	end)
	self.Dismissed:Fire()
	self.Dismissed:DisconnectAll()
end

Notification.Close = Notification.Dismiss

function Notification:Update(options)
	if options.Title ~= nil then
		self._title.Text = tostring(options.Title)
	end
	local content = options.Content or options.Description or options.Text
	if content ~= nil then
		self._content.Text = tostring(content)
		self._content.Visible = content ~= ""
	end
	if options.Duration ~= nil and options.Duration ~= false then
		self.Duration = options.Duration
		self.Remaining = options.Duration
		self._progress.Visible = true
		ensureHeartbeat()
	end
	return self
end

function Notifications.clear()
	for _, card in ipairs(table.clone(cards)) do
		card.Maid:Clean()
	end
	table.clear(cards)
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

return Notifications
end

-- ======================================================================
-- Features/Overlay
__modules["Features/Overlay"] = function()
-- Aether · Features/Overlay
-- A top-level ScreenGui shared by everything that floats above windows:
-- pinned widgets, notifications, the command palette, menus and tooltips.
-- It stays visible when windows are hidden.

local Env = import("Core/Env")
local Util = import("Core/Util")

local Overlay = {}

local ORDER = {
	Widgets = 1,
	Notifications = 2,
	Palette = 3,
	Menu = 4,
	Tooltip = 5,
}

local gui = nil
local layers = {}

function Overlay.gui()
	if gui and gui.Parent then
		return gui
	end
	gui = Util.create("ScreenGui", {
		Name = "AetherOverlay",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10000,
	})
	table.clear(layers)
	Env.mount(gui)
	return gui
end

-- A full-screen, input-transparent frame for one kind of floating content.
function Overlay.layer(name)
	local root = Overlay.gui()
	local layer = layers[name]
	if layer and layer.Parent then
		return layer
	end
	layer = Util.create("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = ORDER[name] or 1,
		Parent = root,
	})
	layers[name] = layer
	return layer
end

function Overlay.size()
	return Overlay.gui().AbsoluteSize
end

function Overlay.destroy()
	if gui then
		gui:Destroy()
		gui = nil
	end
	table.clear(layers)
end

return Overlay
end

-- ======================================================================
-- Features/Palette
__modules["Features/Palette"] = function()
-- Aether · Features/Palette
-- The command palette (Ctrl+K, or the search button in the topbar).
-- Fuzzy-searches every element, tab and built-in command of a window:
--   Toggles flip in place (the palette stays open), buttons press,
--   other elements are revealed: tab selected, scrolled into view, highlighted.
-- Works while the window is hidden, so features can be used without opening it.

local Env = import("Core/Env")
local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Spring = import("Core/Spring")
local Maid = import("Core/Maid")
local Fuzzy = import("Core/Fuzzy")
local Overlay = import("Features/Overlay")

local UserInputService = Env.service("UserInputService")

local Palette = {}
Palette.__index = Palette

local ROW_HEIGHT = 46
local ROW_GAP = 2
local MAX_ROWS = 7
local HEADER = 54
local FOOTER = 34
local LIST_PADDING = 6
local MAX_RESULTS = 60
local MAX_RECENT = 6

local TYPE_ICONS = {
	Toggle = "toggle-right",
	Slider = "sliders-horizontal",
	Button = "mouse-pointer-click",
	Dropdown = "list",
	Input = "text-cursor-input",
	Keybind = "keyboard",
	ColorPicker = "palette",
}

function Palette.new(window)
	return setmetatable({
		Window = window,
		IsOpen = false,
		_built = false,
		_items = {},
		_results = {},
		_rows = {},
		_selected = 1,
		_recent = {},
	}, Palette)
end

function Palette:_width()
	return math.min(580, Overlay.size().X - 32)
end

function Palette:_build()
	self._built = true
	local maid = Maid.new()
	self._maid = maid
	self.Window.Maid:Give(maid)

	local layer = Overlay.layer("Palette")

	local backdrop = Util.create("TextButton", {
		Name = "PaletteBackdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = layer,
	})
	maid:Give(backdrop)
	maid:Give(backdrop.Activated:Connect(function()
		self:Close()
	end))
	self._backdrop = backdrop

	local panel = Util.create("CanvasGroup", {
		Name = "Palette",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.14),
		Size = UDim2.fromOffset(self:_width(), HEADER + FOOTER),
		GroupTransparency = 1,
		Visible = false,
		ZIndex = 2,
		Parent = layer,
	}, {
		Util.corner(14),
		Util.padding(1),
	})
	maid:Give(panel)
	self._panel = panel
	self._scale = Util.create("UIScale", { Parent = panel })

	local card = Util.create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		Theme = { BackgroundColor3 = "Background" },
		Parent = panel,
	}, {
		Util.corner(13),
		Util.stroke(),
	})

	-- Header: search field
	local searchIcon = Util.icon("search", 18, "TextMuted")
	searchIcon.AnchorPoint = Vector2.new(0, 0.5)
	searchIcon.Position = UDim2.new(0, 18, 0, HEADER / 2)
	searchIcon.Parent = card

	local input = Util.create("TextBox", {
		Name = "Query",
		Position = UDim2.fromOffset(48, 0),
		Size = UDim2.new(1, -110, 0, HEADER),
		PlaceholderText = "Search features, tabs and commands...",
		TextSize = 16,
		Theme = { TextColor3 = "Text", PlaceholderColor3 = "TextMuted" },
		Parent = card,
	})
	self._input = input

	local escChip = Util.create("TextLabel", {
		Name = "Esc",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0, HEADER / 2),
		Size = UDim2.fromOffset(34, 22),
		Text = "esc",
		FontFace = Util.Fonts.Medium,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		Theme = {
			BackgroundColor3 = "Input",
			BackgroundTransparency = "InputTransparency",
			TextColor3 = "TextMuted",
		},
		Parent = card,
	}, {
		Util.corner(5),
		Util.stroke(),
	})
	escChip.Visible = not self.Window.IsTouch

	Util.create("Frame", {
		Name = "Divider",
		Position = UDim2.fromOffset(0, HEADER),
		Size = UDim2.new(1, 0, 0, 1),
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		Parent = card,
	})

	-- Results
	local list = Util.create("ScrollingFrame", {
		Name = "Results",
		Position = UDim2.fromOffset(0, HEADER + 1),
		Size = UDim2.new(1, 0, 1, -(HEADER + FOOTER + 2)),
		ScrollBarThickness = 3,
		Theme = { ScrollBarImageColor3 = "TextMuted" },
		Parent = card,
	}, {
		Util.padding(LIST_PADDING, 6, LIST_PADDING, 6),
		Util.list(ROW_GAP),
	})
	self._list = list

	self._empty = Util.create("TextLabel", {
		Name = "Empty",
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		Text = "No matches",
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		LayoutOrder = 1e6,
		Theme = { TextColor3 = "TextMuted" },
		Parent = list,
	})

	-- Footer: hints
	Util.create("Frame", {
		Name = "FooterDivider",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -FOOTER),
		Size = UDim2.new(1, 0, 0, 1),
		Theme = {
			BackgroundColor3 = "Divider",
			BackgroundTransparency = "DividerTransparency",
		},
		Parent = card,
	})
	Util.create("TextLabel", {
		Name = "Hints",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, 0),
		Size = UDim2.new(1, -36, 0, FOOTER),
		Text = self.Window.IsTouch and "Tap a result to run it"
			or "Up/Down to move  ·  Enter to run  ·  Esc to close",
		TextSize = 12,
		Theme = { TextColor3 = "TextMuted" },
		Parent = card,
	})

	maid:Give(input:GetPropertyChangedSignal("Text"):Connect(function()
		if self.IsOpen then
			self:_refresh()
		end
	end))

	maid:Give(input.FocusLost:Connect(function(enterPressed)
		if not self.IsOpen then
			return
		end
		if enterPressed then
			self:_run(self._results[self._selected])
		elseif UserInputService:IsKeyDown(Enum.KeyCode.Escape) then
			self:Close()
		end
	end))

	maid:Give(UserInputService.InputBegan:Connect(function(input)
		if not self.IsOpen then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Down then
			self:_move(1)
		elseif key == Enum.KeyCode.Up then
			self:_move(-1)
		elseif key == Enum.KeyCode.Escape then
			self:Close()
		end
	end))
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

function Palette:_collect()
	local window = self.Window
	local library = window.Library
	local items = {}

	for _, element in ipairs(window.Elements) do
		local icon = TYPE_ICONS[element.Type]
		if icon and element.Visible and not element.Destroyed and element.Section.Visible and element.Tab.Visible then
			local path = element.Tab.Name
			if element.Section.Name and element.Section.Name ~= "" then
				path ..= "  ›  " .. element.Section.Name
			end
			table.insert(items, {
				Id = "element:" .. element:GetId(),
				Kind = "Element",
				Title = element.Name,
				Subtitle = path,
				Icon = icon,
				Element = element,
			})
		end
	end

	for _, tab in ipairs(window.Tabs) do
		if tab.Visible then
			table.insert(items, {
				Id = "tab:" .. tab.Name,
				Kind = "Tab",
				Title = tab.Name,
				Subtitle = "Go to tab",
				Icon = type(tab.IconName) == "string" and tab.IconName or "layout-panel-left",
				Tab = tab,
			})
		end
	end

	local function command(id, title, icon, run, extra)
		local item = {
			Id = "command:" .. id,
			Kind = "Command",
			Title = title,
			Subtitle = "Command",
			Icon = icon,
			Run = run,
		}
		if extra then
			for key, value in pairs(extra) do
				item[key] = value
			end
		end
		table.insert(items, item)
	end

	command("visibility", window.Visible and "Hide window" or "Show window", window.Visible and "eye-off" or "eye", function()
		window:Toggle()
	end, { Value = Util.keyName(window:GetToggleKey()) })
	command("minimize", window.Minimized and "Restore window" or "Minimize window", "minimize-2", function()
		window:Show()
		window:Minimize()
	end)
	for _, name in ipairs(Theme.names()) do
		command("theme:" .. name, "Theme: " .. name, "palette", function()
			library:SetTheme(name)
			window:_savePrefs()
		end, { Value = Theme.Name == name and "Current" or nil })
	end
	command("motion", "Reduced motion", "wind", function()
		library:SetReducedMotion(not library.ReducedMotion)
		window:_savePrefs()
	end, { Value = library.ReducedMotion and "On" or "Off" })
	command("share", "Copy config share code", "share-2", function()
		window:_copyShareCode()
	end)
	command("unload", "Unload interface", "power", function()
		window:Dialog({
			Title = "Unload the interface?",
			Content = "Every window and widget is removed. Run the script again to bring it back.",
			Buttons = {
				{ Name = "Cancel" },
				{ Name = "Unload", Danger = true, Callback = function()
					library:Unload()
				end },
			},
		})
	end, { Danger = true })

	return items
end

function Palette:_find(id)
	for _, item in ipairs(self._items) do
		if item.Id == id then
			return item
		end
	end
	return nil
end

function Palette:_refresh()
	local query = self._input.Text
	local results = {}

	if query == "" then
		local seen = {}
		for _, id in ipairs(self._recent) do
			local item = self:_find(id)
			if item then
				seen[id] = true
				table.insert(results, { Item = item, Recent = true })
			end
		end
		for _, item in ipairs(self._items) do
			if not seen[item.Id] and item.Kind ~= "Command" then
				table.insert(results, { Item = item })
			end
		end
	else
		for _, item in ipairs(self._items) do
			local score, indices = Fuzzy.match(query, item.Title)
			local pathScore = Fuzzy.match(query, item.Subtitle .. " " .. item.Title)
			if score or pathScore then
				-- Matches in the title beat matches that need the tab/section path.
				local best = score or -math.huge
				if pathScore and pathScore * 0.5 > best then
					best = pathScore * 0.5
					indices = nil
				end
				if item.Kind == "Command" then
					best -= 2
				end
				table.insert(results, { Item = item, Score = best, Indices = indices })
			end
		end
		table.sort(results, function(a, b)
			return a.Score > b.Score
		end)
	end

	while #results > MAX_RESULTS do
		table.remove(results)
	end
	self._results = results
	self._selected = 1
	self._list.CanvasPosition = Vector2.zero
	self:_render()
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

function Palette:_row(index)
	local row = self._rows[index]
	if row then
		return row
	end

	local button = Util.create("TextButton", {
		Name = "Result",
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		LayoutOrder = index,
		BackgroundTransparency = 1,
		Theme = { BackgroundColor3 = "Accent" },
		Parent = self._list,
	}, { Util.corner(8) })

	local tile = Util.create("Frame", {
		Name = "Tile",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		Theme = {
			BackgroundColor3 = "Input",
			BackgroundTransparency = "InputTransparency",
		},
		Parent = button,
	}, { Util.corner(8) })
	local icon = Util.icon(nil, 16, "TextDim")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Parent = tile

	local title = Util.create("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(48, 6),
		Size = UDim2.new(1, -170, 0, 18),
		RichText = true,
		FontFace = Util.Fonts.Medium,
		TextSize = 14,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "Text" },
		Parent = button,
	})

	local subtitle = Util.create("TextLabel", {
		Name = "Subtitle",
		Position = UDim2.fromOffset(48, 24),
		Size = UDim2.new(1, -170, 0, 15),
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "TextMuted" },
		Parent = button,
	})

	local value = Util.create("TextLabel", {
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(110, 20),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "TextDim" },
		Parent = button,
	})

	row = {
		Button = button,
		Icon = icon,
		Title = title,
		Subtitle = subtitle,
		Value = value,
	}
	self._maid:Give(button.MouseEnter:Connect(function()
		if self._rows[index] and self._results[index] and self._selected ~= index then
			self._selected = index
			self:_paintSelection()
		end
	end))
	self._maid:Give(button.Activated:Connect(function()
		self:_run(self._results[index])
	end))
	self._rows[index] = row
	return row
end

local function valueOf(item)
	if item.Kind == "Element" then
		local ok, text = pcall(item.Element._display, item.Element)
		return ok and text or ""
	end
	return item.Value or ""
end

function Palette:_render()
	local accentHex = Theme.get("Accent"):ToHex()
	for index, result in ipairs(self._results) do
		local item = result.Item
		local row = self:_row(index)
		row.Button.Visible = true
		row.Title.Text = Fuzzy.highlight(item.Title, result.Indices, accentHex)
		row.Subtitle.Text = result.Recent and ("Recent  ·  " .. item.Subtitle) or item.Subtitle
		row.Value.Text = valueOf(item)
		Util.iconSet(row.Icon, item.Icon)
		Theme.bind(row.Title, { TextColor3 = item.Danger and "Danger" or "Text" })
	end
	for index = #self._results + 1, #self._rows do
		self._rows[index].Button.Visible = false
	end
	self._empty.Visible = #self._results == 0
	self:_paintSelection()
	self:_resize()
end

function Palette:_paintSelection()
	for index, row in pairs(self._rows) do
		local selected = index == self._selected
		Theme.animate(row.Button, { BackgroundTransparency = selected and 0.86 or 1 }, "Quick")
		Theme.animate(row.Icon, { ImageColor3 = selected and "Accent" or "TextDim" }, "Quick")
	end
end

function Palette:_resize()
	local rows = math.clamp(#self._results, 1, MAX_ROWS)
	local listHeight = rows * ROW_HEIGHT + (rows - 1) * ROW_GAP + LIST_PADDING * 2
	local height = HEADER + 1 + listHeight + 1 + FOOTER
	Spring.animate(self._panel, "Snappy", { Size = UDim2.fromOffset(self:_width(), height) })
end

function Palette:_move(direction)
	local count = #self._results
	if count == 0 then
		return
	end
	self._selected = (self._selected - 1 + direction) % count + 1
	self:_paintSelection()

	-- Keep the selection in view.
	local top = LIST_PADDING + (self._selected - 1) * (ROW_HEIGHT + ROW_GAP)
	local visible = math.clamp(count, 1, MAX_ROWS) * (ROW_HEIGHT + ROW_GAP)
	local canvas = self._list.CanvasPosition.Y
	if top < canvas then
		self._list.CanvasPosition = Vector2.new(0, math.max(0, top - LIST_PADDING))
	elseif top + ROW_HEIGHT > canvas + visible then
		self._list.CanvasPosition = Vector2.new(0, top + ROW_HEIGHT - visible + LIST_PADDING)
	end
end

---------------------------------------------------------------------------
-- Running
---------------------------------------------------------------------------

function Palette:_remember(item)
	local index = table.find(self._recent, item.Id)
	if index then
		table.remove(self._recent, index)
	end
	table.insert(self._recent, 1, item.Id)
	while #self._recent > MAX_RECENT do
		table.remove(self._recent)
	end
end

function Palette:_run(result)
	if not result then
		return
	end
	local item = result.Item
	local window = self.Window
	self:_remember(item)

	if item.Kind == "Element" then
		local element = item.Element
		if element.Destroyed then
			return
		end
		if element.Type == "Toggle" then
			if not element.Disabled then
				element:Toggle()
			end
			-- Stay open so several toggles can be flipped in a row.
			task.defer(function()
				if self.IsOpen then
					self:_render()
					self._input:CaptureFocus()
				end
			end)
			return
		elseif element.Type == "Button" then
			self:Close()
			element:Press()
		else
			self:Close()
			window:Reveal(element)
		end
	elseif item.Kind == "Tab" then
		self:Close()
		window:Show()
		window:SelectTab(item.Tab)
	else
		self:Close()
		task.spawn(item.Run)
	end
end

---------------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------------

function Palette:Open()
	if self.IsOpen or self.Window.Destroyed then
		return self
	end
	if not self._built then
		self:_build()
	end
	self.IsOpen = true
	self._items = self:_collect()
	self._input.Text = ""
	self:_refresh()

	local backdrop, panel = self._backdrop, self._panel
	backdrop.Visible = true
	panel.Visible = true
	self._scale.Scale = 0.96
	Spring.animate(backdrop, "Snappy", { BackgroundTransparency = 0.5 })
	Spring.animate(panel, "Snappy", { GroupTransparency = 0 })
	Spring.animate(self._scale, "Bouncy", { Scale = 1 })

	task.defer(function()
		if self.IsOpen then
			self._input:CaptureFocus()
		end
	end)
	return self
end

function Palette:Close()
	if not self.IsOpen then
		return self
	end
	self.IsOpen = false
	self._input:ReleaseFocus()
	local backdrop, panel = self._backdrop, self._panel
	Spring.animate(backdrop, "Snappy", { BackgroundTransparency = 1 })
	Spring.animate(self._scale, "Snappy", { Scale = 0.97 })
	Spring.animate(panel, "Snappy", { GroupTransparency = 1 }, function()
		if not self.IsOpen then
			backdrop.Visible = false
			panel.Visible = false
		end
	end)
	return self
end

function Palette:Toggle()
	if self.IsOpen then
		return self:Close()
	end
	return self:Open()
end

return Palette
end

-- ======================================================================
-- Features/Pins
__modules["Features/Pins"] = function()
-- Aether · Features/Pins
-- Pinned widgets: small floating copies of elements that stay on screen
-- (even while the window is hidden) and stay in sync with the original.
-- Pin by dragging an element out of the window, from the right-click /
-- long-press menu, or with element:Pin().

local Util = import("Core/Util")
local Theme = import("Core/Theme")
local Spring = import("Core/Spring")
local Signal = import("Core/Signal")
local Maid = import("Core/Maid")
local Overlay = import("Features/Overlay")

local Pins = {}
Pins.__index = Pins

local WIDTH = 196

---------------------------------------------------------------------------
-- Widget bodies, one per element type. Each returns update(instant).
---------------------------------------------------------------------------

local builders = {}

local function miniSwitch(parent)
	local track = Util.create("Frame", {
		Name = "Switch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(32, 18),
		Theme = { BackgroundColor3 = "Control" },
		Parent = parent,
	}, { Util.corner("full") })
	local fill = Util.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Parent = track,
	}, {
		Util.corner("full"),
		Util.create("UIGradient", { Theme = { Color = Theme.accentSequence } }),
	})
	local knob = Util.create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		ZIndex = 2,
		Theme = { BackgroundColor3 = "TextDim" },
		Parent = track,
	}, { Util.corner("full") })
	return function(on)
		Spring.animate(knob, "Bouncy", { Position = UDim2.new(0, on and 17 or 3, 0.5, 0) })
		Spring.animate(fill, "Snappy", { BackgroundTransparency = on and 0 or 1 })
		Theme.animate(knob, { BackgroundColor3 = on and "OnAccent" or "TextDim" })
	end
end

builders.Toggle = function(widget, element)
	local body = Util.create("TextButton", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 24),
		Parent = widget.Content,
	})
	local state = Util.create("TextLabel", {
		Name = "State",
		Size = UDim2.new(1, -40, 1, 0),
		TextSize = 13,
		FontFace = Util.Fonts.Medium,
		Theme = { TextColor3 = "Text" },
		Parent = body,
	})
	local setSwitch = miniSwitch(body)
	widget.Maid:Give(body.Activated:Connect(function()
		if not element.Disabled then
			element:Toggle()
		end
	end))
	return function()
		state.Text = element.Value and "On" or "Off"
		setSwitch(element.Value == true)
	end
end

builders.Slider = function(widget, element)
	local value = Util.create("TextLabel", {
		Name = "Value",
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = 13,
		FontFace = Util.Fonts.Medium,
		Theme = { TextColor3 = "Text" },
		Parent = widget.Content,
	})
	local track = Util.create("TextButton", {
		Name = "Track",
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = widget.Content,
	})
	local bar = Util.create("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 4),
		Theme = { BackgroundColor3 = "Control" },
		Parent = track,
	}, { Util.corner("full") })
	local fill = Util.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = bar,
	}, {
		Util.corner("full"),
		Util.create("UIGradient", { Theme = { Color = Theme.accentSequence } }),
	})
	local knob = Util.create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(10, 10),
		Theme = { BackgroundColor3 = "Text" },
		Parent = bar,
	}, { Util.corner("full") })
	Util.create("Frame", {
		Name = "Space",
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		Parent = widget.Content,
	})

	local function setFromPointer(pointer)
		local position, size = bar.AbsolutePosition, bar.AbsoluteSize
		if size.X > 0 and not element.Disabled then
			local alpha = math.clamp((pointer.X - position.X) / size.X, 0, 1)
			element:Set(element.Min + (element.Max - element.Min) * alpha)
		end
	end
	Util.draggable(track, {
		Start = function(input)
			setFromPointer(Util.pointer(input))
		end,
		Move = function(_, pointer)
			setFromPointer(pointer)
		end,
		End = function()
			element.Released:Fire(element.Value)
		end,
	}, widget.Maid)

	return function(instant)
		local alpha = element:_alpha()
		value.Text = element:_display()
		if instant then
			fill.Size = UDim2.fromScale(alpha, 1)
			knob.Position = UDim2.fromScale(alpha, 0.5)
		else
			Spring.animate(fill, "Quick", { Size = UDim2.fromScale(alpha, 1) })
			Spring.animate(knob, "Quick", { Position = UDim2.fromScale(alpha, 0.5) })
		end
	end
end

builders.Button = function(widget, element)
	local button = Util.create("TextButton", {
		Name = "Run",
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		Text = "Run",
		FontFace = Util.Fonts.SemiBold,
		TextSize = 13,
		Theme = { TextColor3 = "OnAccent" },
		Parent = widget.Content,
	}, {
		Util.corner(7),
		Util.create("UIGradient", { Theme = { Color = Theme.accentSequence } }),
	})
	local scale = Util.create("UIScale", { Parent = button })
	widget.Maid:Give(button.Activated:Connect(function()
		if not element.Disabled then
			scale.Scale = 0.94
			Spring.animate(scale, "Bouncy", { Scale = 1 })
			element:Press()
		end
	end))
	return function() end
end

builders.Dropdown = function(widget, element)
	local row = Util.create("Frame", {
		Name = "Row",
		Size = UDim2.new(1, 0, 0, 26),
		Theme = {
			BackgroundColor3 = "Input",
			BackgroundTransparency = "InputTransparency",
		},
		Parent = widget.Content,
	}, { Util.corner(6) })
	local value = Util.create("TextLabel", {
		Name = "Value",
		Position = UDim2.fromOffset(26, 0),
		Size = UDim2.new(1, -52, 1, 0),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "Text" },
		Parent = row,
	})
	local function arrow(direction)
		local button = Util.create("TextButton", {
			Name = direction > 0 and "Next" or "Previous",
			AnchorPoint = Vector2.new(direction > 0 and 1 or 0, 0),
			Position = UDim2.fromScale(direction > 0 and 1 or 0, 0),
			Size = UDim2.new(0, 26, 1, 0),
			Parent = row,
		})
		local glyph = Util.glyph("chevron-right", { Size = 12, Color = "TextDim" })
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.Rotation = direction > 0 and 0 or 180
		glyph.Parent = button
		widget.Maid:Give(button.Activated:Connect(function()
			if not element.Disabled then
				element:Cycle(direction)
			end
		end))
	end
	if not element.Multi then
		arrow(-1)
		arrow(1)
	end
	return function()
		value.Text = element:_display()
	end
end

builders.Keybind = function(widget, element)
	local row = Util.create("Frame", {
		Name = "Row",
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Parent = widget.Content,
	})
	local key = Util.create("TextLabel", {
		Name = "Key",
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 12,
		FontFace = Util.Fonts.Medium,
		BackgroundTransparency = 0,
		Theme = {
			BackgroundColor3 = "Input",
			BackgroundTransparency = "InputTransparency",
			TextColor3 = "Text",
		},
		Parent = row,
	}, {
		Util.corner(5),
		Util.stroke(),
		Util.padding(0, 8, 0, 8),
	})
	local dot = Util.create("Frame", {
		Name = "State",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -2, 0.5, 0),
		Size = UDim2.fromOffset(8, 8),
		Visible = element.Mode ~= "Press",
		Theme = { BackgroundColor3 = "TextMuted" },
		Parent = row,
	}, { Util.corner("full") })
	widget.Maid:Give(element.BindChanged:Connect(function()
		key.Text = element:_display()
	end))
	return function()
		key.Text = element:_display()
		Theme.animate(dot, { BackgroundColor3 = element.State and "Success" or "TextMuted" })
	end
end

local function textBody(widget, getText)
	local label = Util.create("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 13,
		TextWrapped = true,
		Theme = { TextColor3 = "Text" },
		Parent = widget.Content,
	})
	return function()
		label.Text = getText()
	end
end

builders.Label = function(widget, element)
	return textBody(widget, function()
		return element.Name
	end)
end

builders.Paragraph = function(widget, element)
	return textBody(widget, function()
		return element.DescriptionLabel.Text
	end)
end

---------------------------------------------------------------------------
-- Pins
---------------------------------------------------------------------------

function Pins.new(window)
	return setmetatable({
		Window = window,
		Widgets = {}, -- [id] = widget
		Changed = Signal.new("Pins.Changed"),
		_saved = {}, -- [id] = { X, Y } for everything pinned, including elements not created yet
	}, Pins)
end

function Pins.canPin(element)
	return element.Pinnable == true and builders[element.Type] ~= nil
end

-- A label's text is its body, so its header shows where it lives instead.
local function headerText(element)
	if element.Type == "Label" then
		return element.Section.Name or element.Tab.Name
	end
	return element.Name
end

local function clampToScreen(x, y, width, height)
	local screen = Overlay.size()
	return math.clamp(x, 4, math.max(4, screen.X - width - 4)), math.clamp(y, 4, math.max(4, screen.Y - height - 4))
end

function Pins:IsPinned(element)
	return self.Widgets[element:GetId()] ~= nil
end

-- Creates the widget. position: top-left corner in screen pixels (Vector2).
function Pins:Pin(element, position, silent)
	if not Pins.canPin(element) or element.Destroyed then
		return nil
	end
	local id = element:GetId()
	if self.Widgets[id] then
		return self.Widgets[id]
	end

	if not position then
		-- Stack new widgets down the left edge.
		local count = 0
		for _ in pairs(self.Widgets) do
			count += 1
		end
		position = Vector2.new(16, 80 + count * 70)
	end
	local x, y = clampToScreen(position.X, position.Y, WIDTH, 60)

	local maid = Maid.new()
	local frame = Util.create("Frame", {
		Name = "Widget",
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Theme = {
			BackgroundColor3 = "Background",
			BackgroundTransparency = "BackgroundTransparency",
		},
		Parent = Overlay.layer("Widgets"),
	}, {
		Util.corner(10),
		Util.stroke(),
		Util.padding(8, 10, 10, 10),
		Util.list(6),
	})
	maid:Give(frame)

	local header = Util.create("TextButton", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 1,
		Parent = frame,
	})
	local title = Util.create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -22, 1, 0),
		Text = headerText(element),
		FontFace = Util.Fonts.SemiBold,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "TextDim" },
		Parent = header,
	})
	local close = Util.create("TextButton", {
		Name = "Unpin",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(18, 18),
		Parent = header,
	})
	local closeGlyph = Util.glyph("close", { Size = 9, Color = "TextMuted", Thickness = 1.5 })
	closeGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
	closeGlyph.Position = UDim2.fromScale(0.5, 0.5)
	closeGlyph.Parent = close

	local content = Util.create("Frame", {
		Name = "Content",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = frame,
	})

	local widget = {
		Element = element,
		Frame = frame,
		Content = content,
		Maid = maid,
	}
	local update = builders[element.Type](widget, element)
	widget.Update = update
	update(true)

	maid:Give(element.Changed:Connect(function()
		update(false)
	end))
	maid:Give(close.Activated:Connect(function()
		self:Unpin(element)
	end))

	-- Drag by the header; remember where it was left.
	local origin
	Util.draggable(header, {
		Start = function()
			origin = Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset)
		end,
		Move = function(delta)
			local size = frame.AbsoluteSize
			local nx, ny = clampToScreen(origin.X + delta.X, origin.Y + delta.Y, size.X, size.Y)
			Spring.animate(frame, "Drag", { Position = UDim2.fromOffset(nx, ny) })
			self._saved[id] = { X = nx, Y = ny }
		end,
		End = function()
			self.Changed:Fire()
		end,
	}, maid)

	local scale = Util.create("UIScale", { Scale = 0.85, Parent = frame })
	Spring.animate(scale, "Bouncy", { Scale = 1 })

	self.Widgets[id] = widget
	self._saved[id] = { X = x, Y = y }
	widget.Title = title
	if not silent then
		self.Changed:Fire()
	end
	return widget
end

-- Removes a widget. keepSaved = true keeps it in the saved layout (used when
-- an element is destroyed by an unload, so it comes back next time).
function Pins:Unpin(element, keepSaved)
	local id = type(element) == "table" and element:GetId() or element
	local widget = self.Widgets[id]
	if widget then
		self.Widgets[id] = nil
		local frame = widget.Frame
		Spring.animate(frame.UIScale, "Snappy", { Scale = 0.85 }, function()
			widget.Maid:Clean()
		end)
		Spring.animate(frame, "Snappy", { BackgroundTransparency = 1 })
		for _, part in ipairs(frame:GetDescendants()) do
			if part:IsA("GuiObject") then
				part.Visible = false
			end
		end
	end
	if not keepSaved then
		self._saved[id] = nil
		self.Changed:Fire()
	end
end

function Pins:_elementText(element)
	local widget = self.Widgets[element:GetId()]
	if widget then
		widget.Title.Text = headerText(element)
		widget.Update(false)
	end
end

-- Restores a saved pin once its element exists.
function Pins:_elementReady(element)
	local saved = self._saved[element:GetId()]
	if saved and not self.Widgets[element:GetId()] then
		self:Pin(element, Vector2.new(saved.X, saved.Y), true)
	end
end

function Pins:Serialize()
	local list = {}
	for id, position in pairs(self._saved) do
		table.insert(list, { Id = id, X = math.floor(position.X), Y = math.floor(position.Y) })
	end
	return list
end

function Pins:Load(list)
	if type(list) ~= "table" then
		return
	end
	for _, entry in ipairs(list) do
		if type(entry) == "table" and type(entry.Id) == "string" and tonumber(entry.X) and tonumber(entry.Y) then
			self._saved[entry.Id] = { X = tonumber(entry.X), Y = tonumber(entry.Y) }
		end
	end
	for _, element in ipairs(self.Window.Elements) do
		self:_elementReady(element)
	end
end

---------------------------------------------------------------------------
-- Drag an element out of the window to pin it
---------------------------------------------------------------------------

function Pins:BeginDrag(element, pointer)
	self:_endGhost()
	local ghost = Util.create("Frame", {
		Name = "PinGhost",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(pointer.X, pointer.Y),
		Size = UDim2.fromOffset(190, 40),
		BackgroundTransparency = 0.08,
		Theme = { BackgroundColor3 = "Background" },
		Parent = Overlay.layer("Tooltip"),
	}, {
		Util.corner(10),
		Util.stroke(),
	})
	local icon = Util.icon("pin", 14, "Accent")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 12, 0.5, 0)
	icon.Parent = ghost
	Util.create("TextLabel", {
		Name = "Name",
		Position = UDim2.fromOffset(34, 4),
		Size = UDim2.new(1, -44, 0, 16),
		Text = element.Name,
		FontFace = Util.Fonts.SemiBold,
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "Text" },
		Parent = ghost,
	})
	self._ghostHint = Util.create("TextLabel", {
		Name = "Hint",
		Position = UDim2.fromOffset(34, 20),
		Size = UDim2.new(1, -44, 0, 14),
		Text = "Drop outside the window to pin",
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Theme = { TextColor3 = "TextMuted" },
		Parent = ghost,
	})
	local scale = Util.create("UIScale", { Scale = 0.8, Parent = ghost })
	Spring.animate(scale, "Bouncy", { Scale = 1 })
	self._ghost = ghost
	self._ghostReady = false
	self:UpdateDrag(element, pointer)
end

function Pins:_outsideWindow(pointer)
	local root = self.Window._root
	local position, size = root.AbsolutePosition, root.AbsoluteSize
	return not self.Window.Visible
		or pointer.X < position.X
		or pointer.Y < position.Y
		or pointer.X > position.X + size.X
		or pointer.Y > position.Y + size.Y
end

function Pins:UpdateDrag(_element, pointer)
	local ghost = self._ghost
	if not ghost then
		return
	end
	Spring.animate(ghost, "Drag", { Position = UDim2.fromOffset(pointer.X, pointer.Y) })
	local ready = self:_outsideWindow(pointer)
	if ready ~= self._ghostReady then
		self._ghostReady = ready
		local stroke = ghost:FindFirstChildOfClass("UIStroke")
		if stroke then
			Theme.animate(stroke, {
				Color = ready and "Accent" or "Stroke",
				Transparency = ready and 0.2 or "StrokeTransparency",
			})
		end
		self._ghostHint.Text = ready and "Release to pin here" or "Drop outside the window to pin"
	end
end

function Pins:EndDrag(element, pointer)
	local ready = self._ghost and self:_outsideWindow(pointer)
	self:_endGhost()
	if ready then
		self:Pin(element, Vector2.new(pointer.X - WIDTH / 2, pointer.Y - 16))
	end
end

function Pins:_endGhost()
	local ghost = self._ghost
	if not ghost then
		return
	end
	self._ghost = nil
	local scale = ghost:FindFirstChildOfClass("UIScale")
	if scale then
		Spring.animate(scale, "Snappy", { Scale = 0.8 })
	end
	Spring.animate(ghost, "Snappy", { BackgroundTransparency = 1 }, function()
		ghost:Destroy()
	end)
	for _, part in ipairs(ghost:GetDescendants()) do
		if part:IsA("GuiObject") then
			part.Visible = false
		end
	end
end

function Pins:Destroy()
	self:_endGhost()
	for id in pairs(table.clone(self.Widgets)) do
		local widget = self.Widgets[id]
		self.Widgets[id] = nil
		widget.Maid:Clean()
	end
	self.Changed:DisconnectAll()
end

return Pins
end

-- ======================================================================
-- Features/Settings
__modules["Features/Settings"] = function()
-- Aether · Features/Settings
--   Window:SettingsTab()   adds a ready-made tab with:
--     Interface: theme, toggle key, reduced motion
--     Configs:   save, load, delete, autoload
--     Share:     copy / paste config codes and theme codes
--     Session:   version info and unload
-- Everything here uses Save = false, so it never ends up inside configs.

local Env = import("Core/Env")
local Theme = import("Core/Theme")
local Config = import("Features/Config")

local Settings = {}

function Settings.build(window, options)
	options = options or {}
	local library = window.Library
	local config = window.Config

	local tab = window:Tab({ Name = options.Name or "Settings", Icon = options.Icon or "settings" })

	---------------------------------------------------------------------------
	tab:Section("Interface")

	local themeDropdown = tab:Dropdown({
		Name = "Theme",
		Options = Theme.names(),
		Default = Theme.Name,
		Placeholder = "Custom",
		Save = false,
		Callback = function(name)
			if name and name ~= Theme.Name then
				library:SetTheme(name)
				window:_savePrefs(true)
			end
		end,
	})
	window.Maid:Give(Theme.Changed:Connect(function(name)
		-- Custom themes (from codes) aren't in the list: show the "Custom" placeholder.
		themeDropdown:Set(Theme.Presets[name] and name or nil, true)
	end))

	tab:Keybind({
		Name = "Show / hide interface",
		Default = window:GetToggleKey(),
		Save = false,
		OnBindChanged = function(key)
			if key then
				window:SetToggleKey(key)
				window:_savePrefs()
			end
		end,
	})

	tab:Toggle({
		Name = "Reduced motion",
		Description = "Turns animations off",
		Default = library.ReducedMotion == true,
		Save = false,
		Callback = function(on)
			library:SetReducedMotion(on)
			window:_savePrefs()
		end,
	})

	---------------------------------------------------------------------------
	tab:Section("Configs")

	local nameInput = tab:Input({
		Name = "Config name",
		Placeholder = "e.g. Legit",
		Save = false,
	})

	local list = tab:Dropdown({
		Name = "Saved configs",
		Options = config:List(),
		Placeholder = "None yet",
		Save = false,
	})

	local autoloadLabel = tab:Label("Autoload: none")

	local function refresh()
		list:SetOptions(config:List())
		autoloadLabel:SetText("Autoload: " .. (config:GetAutoload() or "none"))
	end
	refresh()

	local function selected()
		return list.Value
	end

	tab:Button({
		Name = "Save config",
		Description = "Saves every setting under the name above",
		Callback = function()
			local name = Config.sanitize(nameInput.Value ~= "" and nameInput.Value or (selected() or ""))
			local ok, err = config:Save(name)
			if ok then
				refresh()
				list:Set(name, true)
				nameInput:Set("", true)
				window:Notify({ Title = "Config saved", Content = ("'%s' is saved."):format(name), Type = "Success" })
			else
				window:Notify({ Title = "Couldn't save", Content = err, Type = "Error" })
			end
		end,
	})

	tab:Button({
		Name = "Load config",
		Callback = function()
			local name = selected()
			local ok, result = config:Load(name or "")
			if ok then
				window:Notify({ Title = "Config loaded", Content = ("'%s' applied %d settings."):format(name, result), Type = "Success" })
			else
				window:Notify({ Title = "Couldn't load", Content = result, Type = "Error" })
			end
		end,
	})

	tab:Button({
		Name = "Load on startup",
		Description = "Loads the selected config every time the script runs",
		Callback = function()
			local name = selected()
			if not name then
				window:Notify({ Title = "Pick a config first", Type = "Warning" })
				return
			end
			config:SetAutoload(name)
			refresh()
			window:Notify({ Title = "Autoload set", Content = ("'%s' will load on startup."):format(name), Type = "Success" })
		end,
	})

	tab:Button({
		Name = "Delete config",
		Callback = function()
			local name = selected()
			if not name then
				window:Notify({ Title = "Pick a config first", Type = "Warning" })
				return
			end
			window:Dialog({
				Title = ("Delete '%s'?"):format(name),
				Content = "This can't be undone.",
				Buttons = {
					{ Name = "Cancel" },
					{ Name = "Delete", Danger = true, Callback = function()
						config:Delete(name)
						refresh()
						window:Notify({ Title = "Config deleted", Content = ("'%s' was removed."):format(name) })
					end },
				},
			})
		end,
	})

	---------------------------------------------------------------------------
	tab:Section("Share")

	local codeInput
	tab:Button({
		Name = "Copy config code",
		Description = "Your settings as one line of text anyone can paste",
		Callback = function()
			window:_copyShareCode(codeInput)
		end,
	})

	codeInput = tab:Input({
		Name = "Paste config code",
		Placeholder = "AE1:...",
		Save = false,
		Callback = function(text)
			if text == "" then
				return
			end
			local ok, result = config:Import(text)
			if ok then
				window:Notify({ Title = "Config imported", Content = ("Applied %d settings."):format(result), Type = "Success" })
			else
				window:Notify({ Title = "Couldn't import", Content = result, Type = "Error" })
			end
			codeInput:Set("", true)
		end,
	})

	local themeInput
	tab:Button({
		Name = "Copy theme code",
		Callback = function()
			local code = library:ExportTheme()
			if Env.copy(code) then
				window:Notify({ Title = "Theme code copied", Type = "Success" })
			else
				themeInput:Set(code, true)
				window:Notify({ Title = "Copy the code below", Content = "Your executor can't copy to the clipboard.", Type = "Warning" })
			end
		end,
	})

	themeInput = tab:Input({
		Name = "Paste theme code",
		Placeholder = "AT1:...",
		Save = false,
		Callback = function(text)
			if text == "" then
				return
			end
			local ok, err = library:ImportTheme(text)
			if ok then
				window:_savePrefs(true)
				window:Notify({ Title = "Theme applied", Type = "Success" })
			else
				window:Notify({ Title = "Couldn't apply theme", Content = err, Type = "Error" })
			end
			themeInput:Set("", true)
		end,
	})

	---------------------------------------------------------------------------
	tab:Section("Session")

	tab:Paragraph({
		Title = "Aether " .. tostring(library.Version),
		Content = ("Executor: %s  ·  Saving: %s"):format(
			Env.Executor,
			Env.CanSaveFiles and "to files" or "this session only"
		),
	})

	tab:Button({
		Name = "Unload interface",
		Description = "Removes every window and widget",
		Callback = function()
			window:Dialog({
				Title = "Unload the interface?",
				Content = "Every window and widget is removed. Run the script again to bring it back.",
				Buttons = {
					{ Name = "Cancel" },
					{ Name = "Unload", Danger = true, Callback = function()
						library:Unload()
					end },
				},
			})
		end,
	})

	return tab
end

return Settings
end

-- ======================================================================
-- Features/Tooltip
__modules["Features/Tooltip"] = function()
-- Aether · Features/Tooltip
-- One shared tooltip that follows the mouse. Shown after a short hover on
-- elements that have :Tooltip("text") (or a disabled reason). Desktop only.

local Env = import("Core/Env")
local Util = import("Core/Util")
local Spring = import("Core/Spring")
local Overlay = import("Features/Overlay")

local UserInputService = Env.service("UserInputService")

local Tooltip = {}

local DELAY = 0.45

local frame, label, owner, follow = nil, nil, nil, nil
local token = 0

local function ensure()
	if frame and frame.Parent then
		return
	end
	frame = Util.create("Frame", {
		Name = "Tooltip",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Visible = false,
		Theme = { BackgroundColor3 = "Background" },
		Parent = Overlay.layer("Tooltip"),
	}, {
		Util.corner(6),
		Util.stroke(),
		Util.padding(6, 9, 6, 9),
	})
	label = Util.create("TextLabel", {
		Name = "Text",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextSize = 12,
		TextWrapped = true,
		Theme = { TextColor3 = "Text" },
		Parent = frame,
	}, {
		Util.create("UISizeConstraint", { MaxSize = Vector2.new(260, 400) }),
	})
end

local function place()
	if not frame then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local screen = Overlay.size()
	local size = frame.AbsoluteSize
	local x = math.clamp(mouse.X + 14, 8, math.max(8, screen.X - size.X - 8))
	local y = mouse.Y + 20
	if y + size.Y > screen.Y - 8 then
		y = mouse.Y - size.Y - 10
	end
	frame.Position = UDim2.fromOffset(x, y)
end

-- Shows getText() near the mouse after a short delay, unless hidden first.
function Tooltip.schedule(newOwner, getText)
	if Util.isTouch() then
		return
	end
	token += 1
	local myToken = token
	owner = newOwner
	task.delay(DELAY, function()
		if token ~= myToken or owner ~= newOwner then
			return
		end
		local text = getText()
		if text == nil or text == "" then
			return
		end
		ensure()
		label.Text = tostring(text)
		frame.Visible = true
		frame.BackgroundTransparency = 0.3
		Spring.animate(frame, "Quick", { BackgroundTransparency = 0 })
		place()
		if follow then
			follow:Disconnect()
		end
		follow = UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				place()
			end
		end)
	end)
end

function Tooltip.hide(target)
	if target ~= nil and target ~= owner then
		return
	end
	token += 1
	owner = nil
	if frame then
		frame.Visible = false
	end
	if follow then
		follow:Disconnect()
		follow = nil
	end
end

function Tooltip.destroy()
	Tooltip.hide()
	if frame then
		frame:Destroy()
		frame = nil
	end
end

return Tooltip
end

-- ======================================================================
-- init
__modules["init"] = function()
-- Aether UI Library · entry point
--
--   local Aether = loadstring(game:HttpGet(url))()
--   local Window = Aether:Window({ Name = "My Script", Subtitle = "v1.0" })
--   local Main = Window:Tab({ Name = "Main", Icon = "home" })
--   Main:Toggle({ Name = "Fly", Keybind = "F", Callback = function(on) end })
--   Window:SettingsTab()

local Env = import("Core/Env")
local Log = import("Core/Log")
local Signal = import("Core/Signal")
local Spring = import("Core/Spring")
local Theme = import("Core/Theme")
local Icons = import("Core/Icons")
local Util = import("Core/Util")
local State = import("Core/State")
local Base64 = import("Core/Base64")
local Elements = import("Components/Elements")
local Element = import("Components/Element")
local Window = import("Components/Window")
local Config = import("Features/Config")
local Overlay = import("Features/Overlay")
local Notifications = import("Features/Notifications")
local Tooltip = import("Features/Tooltip")
local ContextMenu = import("Features/ContextMenu")
local KeySystem = import("Features/KeySystem")
local Compat = import("Features/Compat")

-- Built-in elements register themselves when loaded.
import("Elements/Label")
import("Elements/Paragraph")
import("Elements/Button")
import("Elements/Toggle")
import("Elements/Slider")
import("Elements/Dropdown")
import("Elements/Input")
import("Elements/Keybind")
import("Elements/ColorPicker")
import("Elements/Divider")

local THEME_PREFIX = "AT1:"

local Aether = {
	Version = "0.1.0",
	Flags = State.Flags,
	Options = State.Options,
	Windows = {},
	Unloaded = Signal.new("Aether.Unloaded"),
	IsUnloaded = false,
	ReducedMotion = false,

	-- Advanced: the building blocks, for custom elements and effects.
	Element = Element,
	Env = Env,
	Log = Log,
	Spring = Spring,
	Theme = Theme,
	Icons = Icons,
	Util = Util,
}

function Aether:Window(first, second)
	local options = Compat.windowOptions(Util.options(first, second))

	-- Rayfield-style KeySystem = true + KeySettings: ask for the key first.
	local keyOptions = Compat.keySystem(options)
	if keyOptions and not self:KeySystem(keyOptions) then
		-- No valid key: remove everything and stop the calling script quietly.
		self:Unload()
		coroutine.yield()
	end

	local window = Window.new(self, options)
	table.insert(self.Windows, window)
	return window
end

Aether.CreateWindow = Aether.Window

-- Rayfield compatibility: restores the ConfigurationSaving / AutoSave config.
function Aether:LoadConfiguration()
	for _, window in ipairs(self.Windows) do
		window:_loadAutoSave()
	end
end

function Aether:SetVisibility(visible)
	for _, window in ipairs(self.Windows) do
		window:SetVisible(visible)
	end
end

function Aether:IsVisible()
	local window = self.Windows[1]
	return window ~= nil and window.Visible
end

-- Aether:Notify({ Title = "Done", Content = "...", Type = "Success", Duration = 4 })
function Aether:Notify(options)
	return Notifications.notify(options)
end

-- Yields until a valid key is entered. See Features/KeySystem.
function Aether:KeySystem(options)
	return KeySystem.prompt(self, options)
end

---------------------------------------------------------------------------
-- Themes
---------------------------------------------------------------------------

-- Aether:SetTheme("Ocean") or Aether:SetTheme({ Accent = Color3.fromRGB(255, 120, 80) })
function Aether:SetTheme(theme)
	Theme.set(Compat.themeName(theme), true)
	return self
end

function Aether:GetThemes()
	return Theme.names()
end

function Aether:RegisterTheme(name, theme)
	Theme.register(name, theme)
	return self
end

-- The current theme as a short code others can paste into ImportTheme.
function Aether:ExportTheme()
	return THEME_PREFIX .. Base64.encode(Config.encode(Theme.serialize()) or "{}")
end

function Aether:ImportTheme(code)
	code = string.gsub(tostring(code or ""), "%s", "")
	if string.sub(code, 1, #THEME_PREFIX) ~= THEME_PREFIX then
		return false, "That isn't an Aether theme code"
	end
	local json = Base64.decode(string.sub(code, #THEME_PREFIX + 1))
	local data = json and Config.decode(json)
	if not data or not Theme.deserialize(data, true) then
		return false, "The code is incomplete or damaged"
	end
	return true
end

---------------------------------------------------------------------------
-- Misc
---------------------------------------------------------------------------

-- Adds a custom element type: every tab and section gets a :<name>() method.
function Aether:RegisterElement(name, class)
	Elements.register(name, class)
	return self
end

-- Turns every animation off (accessibility / low-end devices).
function Aether:SetReducedMotion(enabled)
	self.ReducedMotion = enabled == true
	Spring.Instant = self.ReducedMotion
	return self
end

-- Removes every window, widget and notification, and disconnects everything.
function Aether:Unload()
	if self.IsUnloaded then
		return
	end
	self.IsUnloaded = true
	ContextMenu.close()
	Tooltip.destroy()
	for _, window in ipairs(table.clone(self.Windows)) do
		window:Destroy()
	end
	table.clear(self.Windows)
	Notifications.clear()
	Overlay.destroy()
	Spring.stopAll()
	Theme.clear()
	self.Unloaded:Fire()
end

Aether.Destroy = Aether.Unload

return Aether
end

return import("init")

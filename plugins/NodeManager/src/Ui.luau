--!strict
local Janitor = require(script.Parent.Parent.Packages.Janitor)

type ColorBinding = {
	Guide: Enum.StudioStyleGuideColor,
	Modifier: Enum.StudioStyleGuideModifier?,
}

local StyleColor = Enum.StudioStyleGuideColor

local FONT = Enum.Font.BuilderSans
local BOLD_FONT = Enum.Font.BuilderSansBold
local TEXT_SIZE = 14
local OVERLAY_Z_INDEX = 10
local MENU_WIDTH = 190
local MENU_ITEM_HEIGHT = 22
local MENU_MAX_HEIGHT = 320
local PROMPT_WIDTH = 260
local PROMPT_HEIGHT = 96

local Ui = {
	ROW_HEIGHT = 24,
	SPACING = 4,
	LABEL_WIDTH = 92,
	_janitor = Janitor.new(),
	_bindings = {} :: { [Instance]: { [string]: ColorBinding } },
	_widget = nil :: DockWidgetPluginGui?,
	_overlay = nil :: GuiObject?,
	_layoutOrder = 0,
}

export type Ui = typeof(Ui)

-- Weak keys let destroyed instances be collected without having to unregister their bindings.
setmetatable(Ui._bindings, { __mode = "k" })

function Ui.Init(self: Ui, widget: DockWidgetPluginGui)
	self._widget = widget
	self._janitor:Add(settings().Studio.ThemeChanged:Connect(function()
		self:_refreshTheme()
	end))
end

function Ui.Destroy(self: Ui)
	self:CloseOverlay()
	self._janitor:Cleanup()
	table.clear(self._bindings)
	self._widget = nil
end

function Ui.GetColor(self: Ui, guide: Enum.StudioStyleGuideColor, modifier: Enum.StudioStyleGuideModifier?): Color3
	return settings().Studio.Theme:GetColor(guide, modifier)
end

--[=[
	Sets a Color3 property from the Studio theme and keeps it in sync when the theme changes.
]=]
function Ui.Theme(
	self: Ui,
	instance: Instance,
	property: string,
	guide: Enum.StudioStyleGuideColor,
	modifier: Enum.StudioStyleGuideModifier?
)
	local binding = self._bindings[instance]
	if binding == nil then
		binding = {}
		self._bindings[instance] = binding
	end

	local color = { Guide = guide, Modifier = modifier }
	binding[property] = color
	self:_applyColor(instance, property, color)
end

function Ui.Frame(self: Ui, parent: Instance, size: UDim2, position: UDim2?): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = size
	frame.Position = position or UDim2.new()
	frame.LayoutOrder = self:_nextLayoutOrder()
	frame.Parent = parent
	return frame
end

function Ui.Background(self: Ui, object: GuiObject, guide: Enum.StudioStyleGuideColor)
	object.BackgroundTransparency = 0
	self:Theme(object, "BackgroundColor3", guide)
end

function Ui.ListLayout(self: Ui, parent: Instance, direction: Enum.FillDirection, spacing: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, spacing)
	if direction == Enum.FillDirection.Horizontal then
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	layout.Parent = parent
	return layout
end

function Ui.Padding(self: Ui, parent: Instance, pixels: number): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, pixels)
	padding.PaddingBottom = UDim.new(0, pixels)
	padding.PaddingLeft = UDim.new(0, pixels)
	padding.PaddingRight = UDim.new(0, pixels)
	padding.Parent = parent
	return padding
end

function Ui.Label(
	self: Ui,
	parent: Instance,
	text: string,
	size: UDim2,
	guide: Enum.StudioStyleGuideColor?,
	bold: boolean?
): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = size
	label.Font = if bold then BOLD_FONT else FONT
	label.TextSize = TEXT_SIZE
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.LayoutOrder = self:_nextLayoutOrder()
	self:Theme(label, "TextColor3", guide or StyleColor.MainText)
	label.Parent = parent
	return label
end

function Ui.Button(
	self: Ui,
	parent: Instance,
	text: string,
	size: UDim2,
	janitor: Janitor.Janitor,
	onClick: () -> (),
	primary: boolean?
): TextButton
	local button = Instance.new("TextButton")
	button.Size = size
	button.Font = FONT
	button.TextSize = TEXT_SIZE
	button.Text = text
	button.TextTruncate = Enum.TextTruncate.AtEnd
	button.AutoButtonColor = true
	button.BorderSizePixel = 1
	button.LayoutOrder = self:_nextLayoutOrder()
	self:Theme(button, "BackgroundColor3", if primary then StyleColor.MainButton else StyleColor.Button)
	self:Theme(button, "BorderColor3", StyleColor.ButtonBorder)
	self:Theme(button, "TextColor3", if primary then StyleColor.BrightText else StyleColor.ButtonText)
	janitor:Add(button.Activated:Connect(onClick :: any))
	button.Parent = parent
	return button
end

--[=[
	Creates a button with no chrome, used for icon-like toggles inside list rows.
]=]
function Ui.FlatButton(self: Ui, parent: Instance, text: string, size: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Size = size
	button.Font = FONT
	button.TextSize = TEXT_SIZE
	button.Text = text
	button.AutoButtonColor = false
	button.LayoutOrder = self:_nextLayoutOrder()
	self:Theme(button, "TextColor3", StyleColor.MainText)
	button.Parent = parent
	return button
end

--[=[
	A button that shows a checkbox state. It doesn't update itself; `onChange` should trigger a rebuild.
]=]
function Ui.Toggle(
	self: Ui,
	parent: Instance,
	text: string,
	size: UDim2,
	janitor: Janitor.Janitor,
	value: boolean,
	onChange: (value: boolean) -> ()
): TextButton
	local button = self:Button(parent, `{if value then "[x]" else "[  ]"}  {text}`, size, janitor, function()
		onChange(not value)
	end)
	button.TextXAlignment = Enum.TextXAlignment.Left

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.Parent = button

	return button
end

function Ui.Input(
	self: Ui,
	parent: Instance,
	size: UDim2,
	placeholder: string,
	janitor: Janitor.Janitor,
	onCommit: (text: string) -> ()
): TextBox
	local box = Instance.new("TextBox")
	box.Size = size
	box.Font = FONT
	box.TextSize = TEXT_SIZE
	box.Text = ""
	box.PlaceholderText = placeholder
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextTruncate = Enum.TextTruncate.AtEnd
	box.BorderSizePixel = 1
	box.LayoutOrder = self:_nextLayoutOrder()
	self:Theme(box, "BackgroundColor3", StyleColor.InputFieldBackground)
	self:Theme(box, "BorderColor3", StyleColor.InputFieldBorder)
	self:Theme(box, "TextColor3", StyleColor.MainText)
	self:Theme(box, "PlaceholderColor3", StyleColor.DimmedText)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 4)
	padding.Parent = box

	janitor:Add(box.FocusLost:Connect(function()
		onCommit(box.Text)
	end))
	box.Parent = parent
	return box
end

--[=[
	Creates a labelled row and returns the frame that holds the row's control.
]=]
function Ui.Field(self: Ui, parent: Instance, labelText: string): Frame
	local row = self:Frame(parent, UDim2.new(1, 0, 0, self.ROW_HEIGHT))
	self:Label(row, labelText, UDim2.new(0, self.LABEL_WIDTH, 1, 0), StyleColor.DimmedText)
	return self:Frame(row, UDim2.new(1, -self.LABEL_WIDTH, 1, 0), UDim2.fromOffset(self.LABEL_WIDTH, 0))
end

function Ui.SectionHeader(self: Ui, parent: Instance, text: string): TextLabel
	return self:Label(parent, text, UDim2.new(1, 0, 0, self.ROW_HEIGHT), StyleColor.MainText, true)
end

--[=[
	Shows a dropdown menu below `anchor`, or at the mouse when no anchor is given.
]=]
function Ui.ShowMenu(self: Ui, options: { string }, onPick: (index: number) -> (), anchor: GuiObject?)
	if #options == 0 then
		return
	end

	local widget = self:_getWidget()
	local overlay = self:_openOverlay(false)
	local widgetSize = widget.AbsoluteSize

	local height = math.min(#options * MENU_ITEM_HEIGHT + 2, MENU_MAX_HEIGHT, widgetSize.Y - 8)
	local position = if anchor ~= nil
		then anchor.AbsolutePosition + Vector2.new(0, anchor.AbsoluteSize.Y)
		else widget:GetRelativeMousePosition()
	if position.Y + height > widgetSize.Y and anchor ~= nil then
		position = Vector2.new(position.X, anchor.AbsolutePosition.Y - height)
	end
	local x = math.clamp(position.X, 0, math.max(0, widgetSize.X - MENU_WIDTH))
	local y = math.clamp(position.Y, 0, math.max(0, widgetSize.Y - height))

	local menu = Instance.new("ScrollingFrame")
	menu.Position = UDim2.fromOffset(x, y)
	menu.Size = UDim2.fromOffset(MENU_WIDTH, height)
	menu.CanvasSize = UDim2.fromOffset(0, #options * MENU_ITEM_HEIGHT)
	menu.ScrollBarThickness = 6
	menu.BorderSizePixel = 1
	menu.ZIndex = OVERLAY_Z_INDEX
	self:Theme(menu, "BackgroundColor3", StyleColor.MainBackground)
	self:Theme(menu, "BorderColor3", StyleColor.Border)
	self:Theme(menu, "ScrollBarImageColor3", StyleColor.ScrollBar)
	self:ListLayout(menu, Enum.FillDirection.Vertical, 0)

	for index, option in options do
		local item = Instance.new("TextButton")
		item.Size = UDim2.new(1, 0, 0, MENU_ITEM_HEIGHT)
		item.Font = FONT
		item.TextSize = TEXT_SIZE
		item.Text = `  {option}`
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.TextTruncate = Enum.TextTruncate.AtEnd
		item.BorderSizePixel = 0
		item.AutoButtonColor = true
		item.LayoutOrder = index
		item.ZIndex = OVERLAY_Z_INDEX
		self:Theme(item, "BackgroundColor3", StyleColor.MainBackground)
		self:Theme(item, "TextColor3", StyleColor.MainText)
		item.Activated:Connect(function()
			self:CloseOverlay()
			onPick(index)
		end)
		item.Parent = menu
	end

	menu.Parent = overlay
end

--[=[
	Shows a modal text prompt. `onSubmit` runs when the user presses Enter or OK.
]=]
function Ui.Prompt(self: Ui, title: string, initialText: string, onSubmit: (text: string) -> ())
	local overlay = self:_openOverlay(true)

	-- A button rather than a frame so clicks inside the dialog don't fall through and close it.
	local dialog = Instance.new("TextButton")
	dialog.Text = ""
	dialog.AutoButtonColor = false
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	dialog.Position = UDim2.fromScale(0.5, 0.4)
	dialog.Size = UDim2.fromOffset(PROMPT_WIDTH, PROMPT_HEIGHT)
	dialog.BorderSizePixel = 1
	dialog.ZIndex = OVERLAY_Z_INDEX
	self:Theme(dialog, "BackgroundColor3", StyleColor.MainBackground)
	self:Theme(dialog, "BorderColor3", StyleColor.Border)
	self:Padding(dialog, 8)
	self:ListLayout(dialog, Enum.FillDirection.Vertical, 6)
	dialog.Parent = overlay

	local promptJanitor = Janitor.new()
	promptJanitor:LinkToInstance(dialog)

	local submitted = false
	local box: TextBox
	local function submit()
		if submitted then
			return
		end

		submitted = true
		local text = box.Text
		self:CloseOverlay()
		onSubmit(text)
	end

	self:Label(dialog, title, UDim2.new(1, 0, 0, 18), StyleColor.MainText, true).ZIndex = OVERLAY_Z_INDEX
	box = self:Input(dialog, UDim2.new(1, 0, 0, self.ROW_HEIGHT), "", promptJanitor, function() end)
	box.Text = initialText
	box.ZIndex = OVERLAY_Z_INDEX
	promptJanitor:Add(box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			submit()
		end
	end))

	local buttons = self:Frame(dialog, UDim2.new(1, 0, 0, self.ROW_HEIGHT))
	self:ListLayout(buttons, Enum.FillDirection.Horizontal, self.SPACING).HorizontalAlignment =
		Enum.HorizontalAlignment.Right
	self:Button(buttons, "Cancel", UDim2.fromOffset(70, self.ROW_HEIGHT), promptJanitor, function()
		self:CloseOverlay()
	end).ZIndex =
		OVERLAY_Z_INDEX
	self:Button(buttons, "OK", UDim2.fromOffset(70, self.ROW_HEIGHT), promptJanitor, submit, true).ZIndex =
		OVERLAY_Z_INDEX

	task.defer(function()
		if box.Parent ~= nil then
			box:CaptureFocus()
		end
	end)
end

function Ui.CloseOverlay(self: Ui)
	local overlay = self._overlay
	if overlay ~= nil then
		self._overlay = nil
		overlay:Destroy()
	end
end

--[=[
	@priv
]=]
function Ui._openOverlay(self: Ui, dim: boolean): TextButton
	self:CloseOverlay()

	local overlay = Instance.new("TextButton")
	overlay.Name = "Overlay"
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.BorderSizePixel = 0
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = if dim then 0.5 else 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = OVERLAY_Z_INDEX
	overlay.Activated:Connect(function()
		self:CloseOverlay()
	end)
	overlay.Parent = self:_getWidget()

	self._overlay = overlay
	return overlay
end

--[=[
	@priv
]=]
function Ui._getWidget(self: Ui): DockWidgetPluginGui
	return assert(self._widget, "Ui:Init must be called before showing overlays")
end

--[=[
	@priv
]=]
function Ui._nextLayoutOrder(self: Ui): number
	self._layoutOrder += 1
	return self._layoutOrder
end

--[=[
	@priv
]=]
function Ui._refreshTheme(self: Ui)
	for instance, binding in self._bindings do
		if instance.Parent == nil then
			self._bindings[instance] = nil
			continue
		end

		for property, color in binding do
			self:_applyColor(instance, property, color)
		end
	end
end

--[=[
	@priv
]=]
function Ui._applyColor(self: Ui, instance: Instance, property: string, color: ColorBinding)
	-- Bindings address Color3 properties by name, which Luau cannot type statically.
	(instance :: any)[property] = self:GetColor(color.Guide, color.Modifier)
end

return Ui

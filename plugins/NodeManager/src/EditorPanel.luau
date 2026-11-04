--!strict
local Selection = game:GetService("Selection")

local Actions = require(script.Parent.Actions)
local Constants = require(script.Parent.Constants)
local Format = require(script.Parent.Format)
local Janitor = require(script.Parent.Parent.Packages.Janitor)
local NodeAppearance = require(script.Parent.NodeAppearance)
local NodeStore = require(script.Parent.NodeStore)
local NodeTypes = require(script.Parent.NodeTypes)
local Status = require(script.Parent.Status)
local Types = require(script.Parent.Types)
local Ui = require(script.Parent.Ui)

local StyleColor = Enum.StudioStyleGuideColor

local MIXED = "(mixed)"
local SWATCH_SIZE = 18

type Controls = {
	Header: TextLabel,
	Content: Frame,
	Name: TextBox,
	DisplayName: TextBox,
	Type: TextButton,
	Group: TextButton,
	Color: TextBox,
	Size: TextBox,
	Shape: TextButton,
	Image: TextBox,
	Metadata: Frame,
	Visibility: TextButton,
}

local EditorPanel = {
	_janitor = Janitor.new(),
	_metadataJanitor = Janitor.new(),
	_controls = nil :: Controls?,
	_nodes = {} :: { Part },
	_shownText = {} :: { [TextBox]: string },
	_metadataInputs = {} :: { TextBox },
	_refreshQueued = false,
}

export type EditorPanel = typeof(EditorPanel)

function EditorPanel.Init(self: EditorPanel, parent: Frame)
	local scroller = Instance.new("ScrollingFrame")
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.CanvasSize = UDim2.new()
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.ScrollingDirection = Enum.ScrollingDirection.Y
	scroller.ScrollBarThickness = 8
	scroller.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	Ui:Theme(scroller, "ScrollBarImageColor3", StyleColor.ScrollBar)
	Ui:Padding(scroller, 6)
	Ui:ListLayout(scroller, Enum.FillDirection.Vertical, Ui.SPACING)
	scroller.Parent = parent
	self._janitor:Add(scroller)

	local header = Ui:Label(scroller, "", UDim2.new(1, 0, 0, Ui.ROW_HEIGHT), StyleColor.MainText, true)

	local content = Ui:Frame(scroller, UDim2.fromScale(1, 0))
	content.AutomaticSize = Enum.AutomaticSize.Y
	Ui:ListLayout(content, Enum.FillDirection.Vertical, Ui.SPACING)

	local fill = UDim2.fromScale(1, 1)
	local nameInput = self:_createInput(Ui:Field(content, "Name"), "Node name", function(text: string)
		if #self._nodes == 1 then
			Actions:RenameNode(self._nodes[1], text)
		end
	end)

	local displayNameInput = self:_createInput(
		Ui:Field(content, "Display name"),
		"Shown above the node",
		function(text: string)
			Actions:EditNodes("Set node display name", self._nodes, function(node: Part)
				NodeAppearance:SetDisplayName(node, text)
			end)
		end
	)

	local typeButton = Ui:Button(Ui:Field(content, "Type"), "", fill, self._janitor, function()
		self:_chooseType()
	end)

	local groupButton: TextButton
	groupButton = Ui:Button(Ui:Field(content, "Group"), "", fill, self._janitor, function()
		Actions:PromptMoveToGroup(self._nodes, groupButton)
	end)

	local colorInput = self:_createInput(Ui:Field(content, "Color"), "R, G, B or #RRGGBB", function(text: string)
		local color = Format:ParseColor(text)
		if color == nil then
			Status:Error("Enter a color as R, G, B (0-255) or #RRGGBB.")
			self:Refresh()
			return
		end
		self:_setColor(color)
	end)

	local swatches = Ui:Field(content, "")
	Ui:ListLayout(swatches, Enum.FillDirection.Horizontal, 3)

	for _, color in Constants.SWATCHES do
		local swatch = Ui:FlatButton(swatches, "", UDim2.fromOffset(SWATCH_SIZE, SWATCH_SIZE))
		swatch.BackgroundTransparency = 0
		swatch.BackgroundColor3 = color
		swatch.BorderSizePixel = 1
		Ui:Theme(swatch, "BorderColor3", StyleColor.Border)
		self._janitor:Add(swatch.Activated:Connect(function()
			self:_setColor(color)
		end))
	end

	local sizeInput = self:_createInput(Ui:Field(content, "Size"), "Studs", function(text: string)
		local size = tonumber(text)
		if size == nil or size <= 0 then
			Status:Error("Size must be a positive number of studs.")
			self:Refresh()
			return
		end
		Actions:EditNodes("Set node size", self._nodes, function(node: Part)
			NodeAppearance:SetSize(node, size)
		end)
	end)

	local shapeButton = Ui:Button(Ui:Field(content, "Shape"), "", fill, self._janitor, function()
		self:_chooseShape()
	end)

	local imageInput = self:_createInput(Ui:Field(content, "Image"), "Asset id (optional)", function(text: string)
		Actions:EditNodes("Set node image", self._nodes, function(node: Part)
			NodeAppearance:SetImage(node, text)
		end)
	end)

	local metadata = Ui:Frame(content, UDim2.fromScale(1, 0))
	metadata.AutomaticSize = Enum.AutomaticSize.Y
	Ui:ListLayout(metadata, Enum.FillDirection.Vertical, Ui.SPACING)

	local actionsRow = Ui:Frame(content, UDim2.new(1, 0, 0, Ui.ROW_HEIGHT))
	Ui:ListLayout(actionsRow, Enum.FillDirection.Horizontal, Ui.SPACING)

	local third = UDim2.new(1 / 3, -Ui.SPACING, 1, 0)

	Ui:Button(actionsRow, "Focus", third, self._janitor, function()
		Actions:FocusNodes(self._nodes)
	end)

	Ui:Button(actionsRow, "Duplicate", third, self._janitor, function()
		Actions:DuplicateNodes(self._nodes)
	end)

	Ui:Button(actionsRow, "Snap to ground", third, self._janitor, function()
		Actions:SnapNodesToGround(self._nodes)
	end)

	local secondRow = Ui:Frame(content, UDim2.new(1, 0, 0, Ui.ROW_HEIGHT))
	Ui:ListLayout(secondRow, Enum.FillDirection.Horizontal, Ui.SPACING)

	local visibilityButton = Ui:Button(secondRow, "", third, self._janitor, function()
		Actions:ToggleNodesHidden(self._nodes)
	end)

	Ui:Button(secondRow, "Delete", third, self._janitor, function()
		Actions:DeleteNodes(self._nodes)
	end)

	self._controls = {
		Header = header,
		Content = content,
		Name = nameInput,
		DisplayName = displayNameInput,
		Type = typeButton,
		Group = groupButton,
		Color = colorInput,
		Size = sizeInput,
		Shape = shapeButton,
		Image = imageInput,
		Metadata = metadata,
		Visibility = visibilityButton,
	}

	self._janitor:Add(Selection.SelectionChanged:Connect(function()
		self:_queueRefresh()
	end))

	self._janitor:Add(NodeStore.Changed:Connect(function()
		self:_queueRefresh()
	end))

	self._janitor:Add(self._metadataJanitor, "Cleanup")

	self:Refresh()
end

function EditorPanel.Destroy(self: EditorPanel)
	self._janitor:Cleanup()
	self._controls = nil
	table.clear(self._nodes)
	table.clear(self._shownText)
	table.clear(self._metadataInputs)
end

function EditorPanel.Refresh(self: EditorPanel)
	local controls = self._controls
	if controls == nil then
		return
	end

	local nodes = Actions:GetSelectedNodes()
	self._nodes = nodes
	controls.Content.Visible = #nodes > 0

	if #nodes == 0 then
		controls.Header.Text = "Select nodes in the list or viewport to edit them."
		return
	end

	controls.Header.Text = if #nodes == 1 then nodes[1].Name else `{#nodes} nodes selected`

	controls.Name.TextEditable = #nodes == 1
	if #nodes == 1 then
		self:_showText(controls.Name, nodes[1].Name, false)
	else
		self:_showText(controls.Name, "", false)
		controls.Name.PlaceholderText = "(multiple nodes)"
	end

	local displayName, mixedDisplayName = self:_common(nodes, function(node: Part): string
		return NodeAppearance:GetDisplayName(node)
	end)
	self:_showText(controls.DisplayName, displayName, mixedDisplayName)

	local nodeType, mixedType = self:_common(nodes, function(node: Part): string
		return NodeAppearance:GetType(node) or "(none)"
	end)
	controls.Type.Text = `{if mixedType then MIXED else nodeType}  ▾`

	local groupName, mixedGroup = self:_common(nodes, function(node: Part): string
		local group = NodeStore:GetGroupOf(node)
		return if group ~= nil then group.Name else "Ungrouped"
	end)
	controls.Group.Text = `{if mixedGroup then MIXED else groupName}  ▾`

	local color, mixedColor = self:_common(nodes, function(node: Part): Color3
		return node.Color
	end)
	self:_showText(controls.Color, Format:Color(color), mixedColor)

	local size, mixedSize = self:_common(nodes, function(node: Part): number
		return node.Size.Y
	end)
	self:_showText(controls.Size, tostring(math.round(size * 100) / 100), mixedSize)

	local shape, mixedShape = self:_common(nodes, function(node: Part): Enum.PartType
		return node.Shape
	end)
	controls.Shape.Text = `{if mixedShape then MIXED else shape.Name}  ▾`

	local image, mixedImage = self:_common(nodes, function(node: Part): string
		return NodeAppearance:GetImage(node)
	end)
	self:_showText(controls.Image, image, mixedImage)

	local allHidden, mixedHidden = self:_common(nodes, function(node: Part): boolean
		return NodeAppearance:IsHidden(node)
	end)
	controls.Visibility.Text = if allHidden and not mixedHidden then "Show" else "Hide"

	self:_refreshMetadata(controls, nodes)
end

--[=[
	@priv
	Rebuilds one control per field defined by the selected nodes' types.
]=]
function EditorPanel._refreshMetadata(self: EditorPanel, controls: Controls, nodes: { Part })
	for _, input in self._metadataInputs do
		if input:IsFocused() then
			return
		end
	end

	self._metadataJanitor:Cleanup()
	table.clear(self._metadataInputs)
	for _, child in controls.Metadata:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local seen: { [string]: boolean } = {}
	local fields: { Types.Field } = {}
	local anyTyped = false
	for _, nodeType in self:_getTypes(nodes) do
		anyTyped = true
		for _, field in nodeType.Fields do
			if not seen[field.Name] then
				seen[field.Name] = true
				table.insert(fields, field)
			end
		end
	end

	if not anyTyped then
		return
	end

	Ui:SectionHeader(controls.Metadata, "Fields")
	if #fields == 0 then
		local hint = Ui:Label(
			controls.Metadata,
			"This type has no fields. Add them in the Types tab.",
			UDim2.new(1, 0, 0, Ui.ROW_HEIGHT),
			StyleColor.DimmedText
		)
		hint.TextWrapped = true
		return
	end

	table.sort(fields, function(a: Types.Field, b: Types.Field): boolean
		return string.lower(a.Name) < string.lower(b.Name)
	end)

	for _, field in fields do
		self:_createFieldControl(controls, field)
	end
end

--[=[
	@priv
]=]
function EditorPanel._createFieldControl(self: EditorPanel, controls: Controls, field: Types.Field)
	local owners = self:_nodesWithField(field.Name)
	local value, mixed = self:_common(owners, function(node: Part): string
		return NodeTypes:FormatValue(NodeTypes:Coerce(node:GetAttribute(field.Name), field.ValueType))
	end)

	local label = if field.Required then `{field.Name} *` else field.Name
	local row = Ui:Field(controls.Metadata, label)

	if field.ValueType == "boolean" then
		local text = if mixed then MIXED elseif value == "" then "(empty)" else value
		Ui:Button(row, `{text}  (click to toggle)`, UDim2.fromScale(1, 1), self._metadataJanitor, function()
			local enabled = mixed or value ~= "true"
			Actions:EditNodes(`Set node {field.Name}`, self:_nodesWithField(field.Name), function(node: Part)
				node:SetAttribute(field.Name, enabled)
			end)
		end)
		return
	end

	local placeholder = if field.Required then `Required {field.ValueType}` else field.ValueType
	local input = self:_createInput(row, placeholder, function(text: string)
		local parsed: Types.FieldValue? = nil
		if field.ValueType ~= "string" and Format:Trim(text) == "" then
			parsed = nil
		else
			local result, err = NodeTypes:ParseValue(text, field.ValueType)
			if err ~= nil then
				Status:Error(`{field.Name}: {err}`)
				self:Refresh()
				return
			end
			parsed = result
		end

		Actions:EditNodes(`Set node {field.Name}`, self:_nodesWithField(field.Name), function(node: Part)
			node:SetAttribute(field.Name, parsed)
		end)
	end, self._metadataJanitor)
	table.insert(self._metadataInputs, input)
	self:_showText(input, value, mixed)
end

--[=[
	@priv
]=]
function EditorPanel._getTypes(self: EditorPanel, nodes: { Part }): { Types.NodeType }
	local types: { Types.NodeType } = {}
	local seen: { [string]: boolean } = {}
	for _, node in nodes do
		local typeName = NodeAppearance:GetType(node)
		if typeName == nil or seen[typeName] then
			continue
		end

		seen[typeName] = true
		local nodeType = NodeTypes:Get(typeName)
		if nodeType ~= nil then
			table.insert(types, nodeType)
		end
	end

	return types
end

--[=[
	@priv
	Returns the selected nodes whose type defines `fieldName`, so edits never add fields to other types.
]=]
function EditorPanel._nodesWithField(self: EditorPanel, fieldName: string): { Part }
	local fieldsByType: { [string]: boolean } = {}
	for _, nodeType in self:_getTypes(self._nodes) do
		for _, field in nodeType.Fields do
			if field.Name == fieldName then
				fieldsByType[nodeType.Name] = true
			end
		end
	end

	local owners = {}
	for _, node in self._nodes do
		local typeName = NodeAppearance:GetType(node)
		if typeName ~= nil and fieldsByType[typeName] then
			table.insert(owners, node)
		end
	end

	return owners
end

--[=[
	@priv
]=]
function EditorPanel._createInput(
	self: EditorPanel,
	parent: Frame,
	placeholder: string,
	onCommit: (text: string) -> (),
	janitor: Janitor.Janitor?
): TextBox
	local box: TextBox
	box = Ui:Input(parent, UDim2.fromScale(1, 1), placeholder, janitor or self._janitor, function(text: string)
		-- FocusLost also fires when the user clicks away without editing, so only commit real changes.
		if text ~= self._shownText[box] and #self._nodes > 0 then
			self._shownText[box] = text
			onCommit(text)
		end
	end)
	return box
end

--[=[
	@priv
]=]
function EditorPanel._showText(self: EditorPanel, box: TextBox, text: string, mixed: boolean)
	if box:IsFocused() then
		return
	end

	local shown = if mixed then "" else text
	box.Text = shown
	if mixed then
		box.PlaceholderText = MIXED
	end
	self._shownText[box] = shown
end

--[=[
	@priv
	Returns the first node's value and whether any other node differs from it.
]=]
function EditorPanel._common<T>(self: EditorPanel, nodes: { Part }, getter: (node: Part) -> T): (T, boolean)
	local first = getter(nodes[1])
	for index = 2, #nodes do
		if getter(nodes[index]) ~= first then
			return first, true
		end
	end

	return first, false
end

--[=[
	@priv
]=]
function EditorPanel._setColor(self: EditorPanel, color: Color3)
	Actions:EditNodes("Set node color", self._nodes, function(node: Part)
		node.Color = color
	end)
	self:Refresh()
end

--[=[
	@priv
]=]
function EditorPanel._chooseType(self: EditorPanel)
	local controls = self._controls
	if controls == nil then
		return
	end

	local names: { string } = {}
	local options = { "(none)" }
	for _, nodeType in NodeTypes:GetAll() do
		table.insert(names, nodeType.Name)
		table.insert(options, nodeType.Name)
	end

	Ui:ShowMenu(options, function(index: number)
		Actions:SetNodesType(self._nodes, if index == 1 then nil else names[index - 1])
	end, controls.Type)
end

--[=[
	@priv
]=]
function EditorPanel._chooseShape(self: EditorPanel)
	local controls = self._controls
	if controls == nil then
		return
	end

	local options = {}
	for _, shape in Constants.SHAPES do
		table.insert(options, shape.Name)
	end

	Ui:ShowMenu(options, function(index: number)
		local shape = Constants.SHAPES[index]
		Actions:EditNodes("Set node shape", self._nodes, function(node: Part)
			node.Shape = shape
			NodeAppearance:Refresh(node)
		end)
	end, controls.Shape)
end

--[=[
	@priv
]=]
function EditorPanel._queueRefresh(self: EditorPanel)
	if self._refreshQueued then
		return
	end

	self._refreshQueued = true
	task.defer(function()
		self._refreshQueued = false
		self:Refresh()
	end)
end

return EditorPanel

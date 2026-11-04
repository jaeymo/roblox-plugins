--!strict
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

local TYPE_ATTRIBUTES = Constants.TYPE_ATTRIBUTES
local FIELD_ATTRIBUTES = Constants.FIELD_ATTRIBUTES
local SWATCH_SIZE = 18
local CONTROLS_HEIGHT = Ui.ROW_HEIGHT + Ui.SPACING * 2

type Controls = {
	TypeButton: TextButton,
	Body: ScrollingFrame,
}

local TypesPanel = {
	_janitor = Janitor.new(),
	_bodyJanitor = Janitor.new(),
	_controls = nil :: Controls?,
	_selected = nil :: Configuration?,
	_inputs = {} :: { TextBox },
	_rebuildQueued = false,
}

export type TypesPanel = typeof(TypesPanel)

function TypesPanel.Init(self: TypesPanel, parent: Frame)
	local top = Ui:Frame(parent, UDim2.new(1, 0, 0, CONTROLS_HEIGHT))
	Ui:Padding(top, Ui.SPACING)
	Ui:ListLayout(top, Enum.FillDirection.Horizontal, Ui.SPACING)

	local typeButton = Ui:Button(top, "", UDim2.new(0.6, -Ui.SPACING, 1, 0), self._janitor, function()
		self:_chooseType()
	end)
	Ui:Button(top, "+ New Type", UDim2.new(0.4, 0, 1, 0), self._janitor, function()
		Ui:Prompt("New node type name", "", function(name: string)
			self:_createType(name)
		end)
	end, true)

	local body = Instance.new("ScrollingFrame")
	body.Size = UDim2.new(1, 0, 1, -CONTROLS_HEIGHT)
	body.Position = UDim2.fromOffset(0, CONTROLS_HEIGHT)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.ScrollBarThickness = 8
	body.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	Ui:Theme(body, "ScrollBarImageColor3", StyleColor.ScrollBar)
	Ui:Padding(body, 6)
	Ui:ListLayout(body, Enum.FillDirection.Vertical, Ui.SPACING)
	body.Parent = parent
	self._janitor:Add(body)

	self._controls = {
		TypeButton = typeButton,
		Body = body,
	}

	self._janitor:Add(self._bodyJanitor, "Cleanup")
	self._janitor:Add(NodeStore.Changed:Connect(function()
		self:_queueRebuild()
	end))

	self:Rebuild()
end

function TypesPanel.Destroy(self: TypesPanel)
	self._janitor:Cleanup()
	self._controls = nil
	self._selected = nil
	table.clear(self._inputs)
end

function TypesPanel.Rebuild(self: TypesPanel)
	local controls = self._controls
	if controls == nil then
		return
	end

	-- Rebuilding would discard what the user is typing; the commit on focus loss triggers another rebuild.
	for _, input in self._inputs do
		if input:IsFocused() then
			return
		end
	end

	self._bodyJanitor:Cleanup()
	table.clear(self._inputs)
	for _, child in controls.Body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local container = NodeTypes:GetContainer()
	local selected = self._selected
	if selected == nil or container == nil or selected.Parent ~= container then
		local first = NodeTypes:GetAll()[1]
		selected = if first ~= nil then first.Instance else nil
		self._selected = selected
	end

	if selected == nil then
		controls.TypeButton.Text = "No types  ▾"
		self:_hint(
			controls.Body,
			"No node types yet. A type sets the look of its nodes and the attributes (fields) every node of "
				.. "that type carries. Create one with + New Type."
		)
		return
	end

	local nodeType = NodeTypes:Read(selected)
	controls.TypeButton.Text = `Type: {nodeType.Name}  ▾`
	self:_buildAppearance(controls.Body, nodeType)
	self:_buildFields(controls.Body, nodeType)
	self:_buildUsage(controls.Body, nodeType)
end

--[=[
	@priv
]=]
function TypesPanel._buildAppearance(self: TypesPanel, body: ScrollingFrame, nodeType: Types.NodeType)
	local config = nodeType.Instance
	local fill = UDim2.fromScale(1, 1)

	Ui:SectionHeader(body, "Type")
	self:_input(Ui:Field(body, "Name"), nodeType.Name, "Type name", function(text: string)
		local name = Format:Trim(text)
		local err = NodeTypes:ValidateTypeName(name, config)
		if err ~= nil then
			self:_fail(err)
			return
		end

		self:_editType("Rename node type", config, function()
			NodeTypes:RenameType(config, name)
		end)
	end)

	self:_input(Ui:Field(body, "Color"), Format:Color(nodeType.Color), "R, G, B or #RRGGBB", function(text: string)
		local color = Format:ParseColor(text)
		if color == nil then
			self:_fail("Enter a color as R, G, B (0-255) or #RRGGBB.")
			return
		end
		self:_setTypeAttribute(config, TYPE_ATTRIBUTES.COLOR, color)
	end)

	local swatches = Ui:Field(body, "")
	Ui:ListLayout(swatches, Enum.FillDirection.Horizontal, 3)
	for _, color in Constants.SWATCHES do
		local swatch = Ui:FlatButton(swatches, "", UDim2.fromOffset(SWATCH_SIZE, SWATCH_SIZE))
		swatch.BackgroundTransparency = 0
		swatch.BackgroundColor3 = color
		swatch.BorderSizePixel = 1
		Ui:Theme(swatch, "BorderColor3", StyleColor.Border)
		self._bodyJanitor:Add(swatch.Activated:Connect(function()
			self:_setTypeAttribute(config, TYPE_ATTRIBUTES.COLOR, color)
		end))
	end

	self:_input(Ui:Field(body, "Size"), tostring(nodeType.Size), "Studs", function(text: string)
		local size = tonumber(text)
		if size == nil or size <= 0 then
			self:_fail("Size must be a positive number of studs.")
			return
		end
		self:_setTypeAttribute(
			config,
			TYPE_ATTRIBUTES.SIZE,
			math.clamp(size, Constants.MIN_NODE_SIZE, Constants.MAX_NODE_SIZE)
		)
	end)

	local shapeButton: TextButton
	shapeButton = Ui:Button(Ui:Field(body, "Shape"), `{nodeType.Shape.Name}  ▾`, fill, self._bodyJanitor, function()
		local options = {}
		for _, shape in Constants.SHAPES do
			table.insert(options, shape.Name)
		end

		Ui:ShowMenu(options, function(index: number)
			self:_setTypeAttribute(config, TYPE_ATTRIBUTES.SHAPE, Constants.SHAPES[index].Name)
		end, shapeButton)
	end)

	self:_input(Ui:Field(body, "Image"), nodeType.Image, "Asset id (optional)", function(text: string)
		self:_setTypeAttribute(config, TYPE_ATTRIBUTES.IMAGE, NodeAppearance:NormalizeImage(text))
	end)

	Ui:Toggle(
		Ui:Field(body, "Validation"),
		"Must rest on the ground",
		fill,
		self._bodyJanitor,
		nodeType.Grounded,
		function(value: boolean)
			self:_setTypeAttribute(config, TYPE_ATTRIBUTES.GROUNDED, value)
		end
	)
end

--[=[
	@priv
]=]
function TypesPanel._buildFields(self: TypesPanel, body: ScrollingFrame, nodeType: Types.NodeType)
	Ui:SectionHeader(body, "Fields")
	self:_hint(
		body,
		"Every node of this type carries these attributes. With Fill default on, nodes start with the "
			.. "default value; otherwise they start empty. Required fields that are empty are reported by "
			.. "validation."
	)

	for _, field in nodeType.Fields do
		self:_buildField(body, nodeType, field)
	end

	Ui:Button(body, "+ Add Field", UDim2.new(1, 0, 0, Ui.ROW_HEIGHT), self._bodyJanitor, function()
		Ui:Prompt("New field name", "", function(text: string)
			local name = Format:Trim(text)
			local err = NodeTypes:ValidateFieldName(name, nodeType.Instance, nil)
			if err ~= nil then
				self:_fail(err)
				return
			end

			self:_editType("Add node type field", nodeType.Instance, function()
				NodeTypes:CreateField(nodeType.Instance, name)
			end)
		end)
	end)
end

--[=[
	@priv
]=]
function TypesPanel._buildField(self: TypesPanel, body: ScrollingFrame, nodeType: Types.NodeType, field: Types.Field)
	local config = nodeType.Instance
	local card = Ui:Frame(body, UDim2.fromScale(1, 0))
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BorderSizePixel = 1
	Ui:Background(card, StyleColor.TableItem)
	Ui:Theme(card, "BorderColor3", StyleColor.Border)
	Ui:Padding(card, Ui.SPACING)
	Ui:ListLayout(card, Enum.FillDirection.Vertical, Ui.SPACING)

	local header = Ui:Frame(card, UDim2.new(1, 0, 0, Ui.ROW_HEIGHT))
	Ui:ListLayout(header, Enum.FillDirection.Horizontal, Ui.SPACING)

	local nameBox = Ui:Input(header, UDim2.new(0.5, -Ui.SPACING, 1, 0), "Field name", self._bodyJanitor, function(text)
		local name = Format:Trim(text)
		if name == field.Name then
			return
		end

		local err = NodeTypes:ValidateFieldName(name, config, field.Instance)
		if err ~= nil then
			self:_fail(err)
			return
		end

		self:_editType("Rename node type field", config, function()
			NodeTypes:RenameField(nodeType, field, name)
		end)
	end)
	nameBox.Text = field.Name
	table.insert(self._inputs, nameBox)

	local valueTypeButton: TextButton
	valueTypeButton = Ui:Button(
		header,
		`{field.ValueType}  ▾`,
		UDim2.new(0.3, -Ui.SPACING, 1, 0),
		self._bodyJanitor,
		function()
			local valueTypes = NodeTypes:GetValueTypes()
			local options: { string } = {}
			for _, valueType in valueTypes do
				table.insert(options, valueType)
			end

			Ui:ShowMenu(options, function(index: number)
				if valueTypes[index] == field.ValueType then
					return
				end

				local valueType: Types.FieldValueType = valueTypes[index]

				self:_editType("Change node type field type", config, function()
					NodeTypes:SetFieldValueType(nodeType, field, valueType)
				end)
			end, valueTypeButton)
		end
	)

	Ui:Button(header, "Delete", UDim2.new(0.2, 0, 1, 0), self._bodyJanitor, function()
		self:_editType("Delete node type field", config, function()
			NodeTypes:DeleteField(nodeType, field)
		end)
		Status:Info(`Removed field '{field.Name}' from {nodeType.Name} and its nodes. Use Undo to restore it.`)
	end)

	local defaultRow = Ui:Field(card, "Default")
	if field.ValueType == "boolean" then
		Ui:Toggle(defaultRow, "true", UDim2.fromScale(1, 1), self._bodyJanitor, field.Default == true, function(value)
			self:_editType("Set node type field default", config, function()
				NodeTypes:SetFieldDefault(nodeType, field, value)
			end)
		end)
	else
		self:_input(defaultRow, NodeTypes:FormatValue(field.Default), field.ValueType, function(text: string)
			local value, err = NodeTypes:ParseValue(text, field.ValueType)
			if value == nil then
				self:_fail(err or "Invalid default value.")
				return
			end

			self:_editType("Set node type field default", config, function()
				NodeTypes:SetFieldDefault(nodeType, field, value)
			end)
		end)
	end

	local options = Ui:Frame(card, UDim2.new(1, 0, 0, Ui.ROW_HEIGHT))
	Ui:ListLayout(options, Enum.FillDirection.Horizontal, Ui.SPACING)
	local third = UDim2.new(1 / 3, -Ui.SPACING, 1, 0)

	Ui:Toggle(options, "Fill default", third, self._bodyJanitor, field.FillDefault, function(value: boolean)
		self:_editType("Set node type field fill", config, function()
			field.Instance:SetAttribute(FIELD_ATTRIBUTES.FILL_DEFAULT, value)
		end)
	end)

	Ui:Toggle(options, "Required", third, self._bodyJanitor, field.Required, function(value: boolean)
		self:_editType("Set node type field required", config, function()
			field.Instance:SetAttribute(FIELD_ATTRIBUTES.REQUIRED, value)
		end)
	end)

	Ui:Button(options, "Reset nodes", third, self._bodyJanitor, function()
		local count = 0
		self:_editType("Reset node type field", config, function()
			count = NodeTypes:ResetField(nodeType, field)
		end)

		local value = NodeTypes:GetInitialValue(field)
		Status:Info(`Set {field.Name} to {if value == nil then "empty" else `'{tostring(value)}'`} on {count} node(s).`)
	end)
end

--[=[
	@priv
]=]
function TypesPanel._buildUsage(self: TypesPanel, body: ScrollingFrame, nodeType: Types.NodeType)
	local nodes = NodeTypes:GetNodesOfType(nodeType.Name)

	Ui:SectionHeader(body, "Nodes")
	self:_hint(body, `{#nodes} node(s) use this type. Changes here are applied to all of them.`)

	local row = Ui:Frame(body, UDim2.new(1, 0, 0, Ui.ROW_HEIGHT))
	Ui:ListLayout(row, Enum.FillDirection.Horizontal, Ui.SPACING)
	local half = UDim2.new(0.5, -Ui.SPACING, 1, 0)

	Ui:Button(row, "Select nodes", half, self._bodyJanitor, function()
		local current = NodeTypes:GetNodesOfType(nodeType.Name)
		if #current == 0 then
			Status:Error(`No nodes use {nodeType.Name} yet.`)
			return
		end
		Actions:SelectNodes(current, true)
	end)

	Ui:Button(row, "Delete type", half, self._bodyJanitor, function()
		local count = 0
		NodeStore:Edit("Delete node type", function()
			count = NodeTypes:DeleteType(nodeType.Instance)
		end)
		Status:Info(`Deleted type {nodeType.Name}. {count} node(s) are now untyped. Use Undo to restore it.`)
	end)
end

--[=[
	@priv
	Applies a change to a type definition and bakes the result onto every node of that type.
]=]
function TypesPanel._editType(self: TypesPanel, actionName: string, config: Configuration, change: () -> ())
	NodeStore:Edit(actionName, function()
		change()
		NodeTypes:SyncNodes(NodeTypes:Read(config))
	end)
end

--[=[
	@priv
]=]
function TypesPanel._setTypeAttribute(self: TypesPanel, config: Configuration, attribute: string, value: unknown)
	if config:GetAttribute(attribute) == value then
		return
	end

	self:_editType("Edit node type", config, function()
		config:SetAttribute(attribute, value)
	end)
end

--[=[
	@priv
]=]
function TypesPanel._createType(self: TypesPanel, text: string)
	local name = Format:Trim(text)
	local err = NodeTypes:ValidateTypeName(name, nil)
	if err ~= nil then
		self:_fail(err)
		return
	end

	local config: Configuration? = nil
	NodeStore:Edit("Create node type", function()
		config = NodeTypes:CreateType(name)
	end)

	self._selected = config
	self:Rebuild()
	Status:Info(`Created type {name}. Add fields below, then pick it when adding nodes.`)
end

--[=[
	@priv
]=]
function TypesPanel._chooseType(self: TypesPanel)
	local controls = self._controls
	local all = NodeTypes:GetAll()
	if controls == nil or #all == 0 then
		return
	end

	local options = {}
	for _, nodeType in all do
		table.insert(options, nodeType.Name)
	end

	Ui:ShowMenu(options, function(index: number)
		self._selected = all[index].Instance
		self:Rebuild()
	end, controls.TypeButton)
end

--[=[
	@priv
]=]
function TypesPanel._input(
	self: TypesPanel,
	parent: Frame,
	text: string,
	placeholder: string,
	onCommit: (text: string) -> ()
): TextBox
	local box = Ui:Input(parent, UDim2.fromScale(1, 1), placeholder, self._bodyJanitor, function(committed: string)
		if committed ~= text then
			onCommit(committed)
		end
	end)
	box.Text = text
	table.insert(self._inputs, box)
	return box
end

--[=[
	@priv
]=]
function TypesPanel._hint(self: TypesPanel, parent: Instance, text: string): TextLabel
	local hint = Ui:Label(parent, text, UDim2.new(1, 0, 0, 0), StyleColor.DimmedText)
	hint.AutomaticSize = Enum.AutomaticSize.Y
	hint.TextWrapped = true
	return hint
end

--[=[
	@priv
	Reports invalid input and restores the inputs to the stored values.
]=]
function TypesPanel._fail(self: TypesPanel, message: string)
	Status:Error(message)
	self:_queueRebuild()
end

--[=[
	@priv
]=]
function TypesPanel._queueRebuild(self: TypesPanel)
	if self._rebuildQueued then
		return
	end

	self._rebuildQueued = true
	task.defer(function()
		self._rebuildQueued = false
		self:Rebuild()
	end)
end

return TypesPanel

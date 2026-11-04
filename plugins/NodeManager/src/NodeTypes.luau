--!strict
local Constants = require(script.Parent.Constants)
local Format = require(script.Parent.Format)
local NodeAppearance = require(script.Parent.NodeAppearance)
local NodeStore = require(script.Parent.NodeStore)
local Types = require(script.Parent.Types)

local ATTRIBUTES = Constants.ATTRIBUTES
local TYPE_ATTRIBUTES = Constants.TYPE_ATTRIBUTES
local FIELD_ATTRIBUTES = Constants.FIELD_ATTRIBUTES
local MAX_ATTRIBUTE_NAME_LENGTH = 100
local VALUE_TYPES: { Types.FieldValueType } = { "string", "number", "boolean" }
local RESERVED_NAMES = { ATTRIBUTES.TYPE, ATTRIBUTES.DISPLAY_NAME, ATTRIBUTES.IMAGE, ATTRIBUTES.HIDDEN }

--[=[
	Node types are stored in the place under `Nodes/NodeTypes`: one Configuration per type holding its
	appearance as attributes, with one child Configuration per field. None of these methods record undo
	history; callers wrap them in `NodeStore:Edit`.
]=]
local NodeTypes = {}

export type NodeTypes = typeof(NodeTypes)

function NodeTypes.GetValueTypes(self: NodeTypes): { Types.FieldValueType }
	return VALUE_TYPES
end

function NodeTypes.GetContainer(self: NodeTypes): Configuration?
	local root = NodeStore:GetRoot()
	if root == nil then
		return nil
	end

	local container = root:FindFirstChild(Constants.TYPES_NAME)
	return if container ~= nil and container:IsA("Configuration") then container else nil
end

function NodeTypes.GetAll(self: NodeTypes): { Types.NodeType }
	local all = {}
	local container = self:GetContainer()
	if container == nil then
		return all
	end

	for _, child in container:GetChildren() do
		if child:IsA("Configuration") then
			table.insert(all, self:Read(child))
		end
	end

	table.sort(all, function(a: Types.NodeType, b: Types.NodeType): boolean
		return string.lower(a.Name) < string.lower(b.Name)
	end)
	return all
end

function NodeTypes.GetMap(self: NodeTypes): { [string]: Types.NodeType }
	local map = {}
	for _, nodeType in self:GetAll() do
		map[nodeType.Name] = nodeType
	end

	return map
end

function NodeTypes.Get(self: NodeTypes, name: string): Types.NodeType?
	local container = self:GetContainer()
	local config = if container ~= nil then container:FindFirstChild(name) else nil
	return if config ~= nil and config:IsA("Configuration") then self:Read(config) else nil
end

function NodeTypes.GetOf(self: NodeTypes, node: Part): Types.NodeType?
	local name = NodeAppearance:GetType(node)
	return if name ~= nil then self:Get(name) else nil
end

function NodeTypes.Read(self: NodeTypes, config: Configuration): Types.NodeType
	local fields = {}
	for _, child in config:GetChildren() do
		if child:IsA("Configuration") then
			table.insert(fields, self:_readField(child))
		end
	end

	table.sort(fields, function(a: Types.Field, b: Types.Field): boolean
		return string.lower(a.Name) < string.lower(b.Name)
	end)

	local default = Constants.DEFAULT_APPEARANCE
	local color = config:GetAttribute(TYPE_ATTRIBUTES.COLOR)
	local size = config:GetAttribute(TYPE_ATTRIBUTES.SIZE)
	local image = config:GetAttribute(TYPE_ATTRIBUTES.IMAGE)

	return {
		Name = config.Name,
		Color = if typeof(color) == "Color3" then color else default.Color,
		Shape = self:_parseShape(config:GetAttribute(TYPE_ATTRIBUTES.SHAPE)),
		Size = if typeof(size) == "number" and size > 0 then size else default.Size,
		Image = if typeof(image) == "string" then image else default.Image,
		Grounded = config:GetAttribute(TYPE_ATTRIBUTES.GROUNDED) ~= false,
		Fields = fields,
		Instance = config,
	}
end

function NodeTypes.GetNodesOfType(self: NodeTypes, name: string): { Part }
	local nodes = {}
	for _, node in NodeStore:GetNodes() do
		if NodeAppearance:GetType(node) == name then
			table.insert(nodes, node)
		end
	end

	return nodes
end

function NodeTypes.ValidateTypeName(self: NodeTypes, name: string, current: Configuration?): string?
	if name == "" then
		return "Type names cannot be empty."
	end

	for _, nodeType in self:GetAll() do
		if nodeType.Instance ~= current and string.lower(nodeType.Name) == string.lower(name) then
			return `A type named '{nodeType.Name}' already exists.`
		end
	end

	return nil
end

function NodeTypes.ValidateFieldName(
	self: NodeTypes,
	name: string,
	typeConfig: Configuration,
	current: Configuration?
): string?
	if string.match(name, "^[%a_][%w_]*$") == nil then
		return "Field names may only use letters, numbers and underscores, and can't start with a number."
	end

	if #name > MAX_ATTRIBUTE_NAME_LENGTH then
		return `Field names can be at most {MAX_ATTRIBUTE_NAME_LENGTH} characters.`
	end

	if string.sub(name, 1, 3) == "RBX" then
		return "Field names can't start with RBX; Roblox reserves those attribute names."
	end

	for _, reserved in RESERVED_NAMES do
		if string.lower(reserved) == string.lower(name) then
			return `'{reserved}' is used by NodeManager itself.`
		end
	end

	for _, child in typeConfig:GetChildren() do
		if child ~= current and child:IsA("Configuration") and string.lower(child.Name) == string.lower(name) then
			return `This type already has a field named '{child.Name}'.`
		end
	end

	return nil
end

function NodeTypes.CreateType(self: NodeTypes, name: string): Configuration
	local container = self:GetContainer()
	if container == nil then
		local created = Instance.new("Configuration")
		created.Name = Constants.TYPES_NAME
		created.Parent = NodeStore:EnsureRoot()
		container = created
	end

	local default = Constants.DEFAULT_APPEARANCE
	local config = Instance.new("Configuration")
	config.Name = name
	config:SetAttribute(TYPE_ATTRIBUTES.COLOR, default.Color)
	config:SetAttribute(TYPE_ATTRIBUTES.SHAPE, default.Shape.Name)
	config:SetAttribute(TYPE_ATTRIBUTES.SIZE, default.Size)
	config:SetAttribute(TYPE_ATTRIBUTES.IMAGE, default.Image)
	config:SetAttribute(TYPE_ATTRIBUTES.GROUNDED, true)
	config.Parent = container
	return config
end

function NodeTypes.RenameType(self: NodeTypes, config: Configuration, name: string)
	local nodes = self:GetNodesOfType(config.Name)
	config.Name = name
	for _, node in nodes do
		node:SetAttribute(ATTRIBUTES.TYPE, name)
		NodeAppearance:Refresh(node)
	end
end

--[=[
	Deletes the type, leaving its nodes untyped and removing the type's fields from them.
]=]
function NodeTypes.DeleteType(self: NodeTypes, config: Configuration): number
	local nodeType = self:Read(config)
	local nodes = self:GetNodesOfType(nodeType.Name)
	for _, node in nodes do
		self:_stripFields(node, nodeType, nil)
		node:SetAttribute(ATTRIBUTES.TYPE, nil)
		NodeAppearance:Refresh(node)
	end

	config.Parent = nil
	return #nodes
end

--[=[
	Gives `node` a new type (or none). Fields that only the old type defines are removed; fields shared by
	both types with the same value type keep their values.
]=]
function NodeTypes.AssignType(self: NodeTypes, node: Part, nodeType: Types.NodeType?)
	local previous = self:GetOf(node)
	if previous ~= nil then
		self:_stripFields(node, previous, nodeType)
	end

	if nodeType == nil then
		node:SetAttribute(ATTRIBUTES.TYPE, nil)
		NodeAppearance:Refresh(node)
		return
	end

	node:SetAttribute(ATTRIBUTES.TYPE, nodeType.Name)
	NodeAppearance:ApplyAppearance(node, nodeType)
	self:_fillFields(node, nodeType)
end

--[=[
	Bakes the type's appearance and fields onto every node of that type.
]=]
function NodeTypes.SyncNodes(self: NodeTypes, nodeType: Types.NodeType)
	for _, node in self:GetNodesOfType(nodeType.Name) do
		NodeAppearance:ApplyAppearance(node, nodeType)
		self:_fillFields(node, nodeType)
	end
end

function NodeTypes.CreateField(self: NodeTypes, typeConfig: Configuration, name: string): Configuration
	local config = Instance.new("Configuration")
	config.Name = name
	config:SetAttribute(FIELD_ATTRIBUTES.VALUE_TYPE, "string")
	config:SetAttribute(FIELD_ATTRIBUTES.DEFAULT, "")
	config:SetAttribute(FIELD_ATTRIBUTES.FILL_DEFAULT, true)
	config:SetAttribute(FIELD_ATTRIBUTES.REQUIRED, false)
	config.Parent = typeConfig
	return config
end

function NodeTypes.RenameField(self: NodeTypes, nodeType: Types.NodeType, field: Types.Field, name: string)
	for _, node in self:GetNodesOfType(nodeType.Name) do
		local value = node:GetAttribute(field.Name)
		node:SetAttribute(field.Name, nil)
		node:SetAttribute(name, value)
	end

	field.Instance.Name = name
end

function NodeTypes.DeleteField(self: NodeTypes, nodeType: Types.NodeType, field: Types.Field)
	for _, node in self:GetNodesOfType(nodeType.Name) do
		node:SetAttribute(field.Name, nil)
	end

	field.Instance.Parent = nil
end

--[=[
	Changes a field's value type, converting the default and existing node values where they parse as the
	new type. Values that don't convert are cleared and refilled by the next sync.
]=]
function NodeTypes.SetFieldValueType(
	self: NodeTypes,
	nodeType: Types.NodeType,
	field: Types.Field,
	valueType: Types.FieldValueType
)
	local default = self:_convert(field.Default, valueType) or self:GetZero(valueType)
	field.Instance:SetAttribute(FIELD_ATTRIBUTES.VALUE_TYPE, valueType)
	field.Instance:SetAttribute(FIELD_ATTRIBUTES.DEFAULT, default)

	for _, node in self:GetNodesOfType(nodeType.Name) do
		local value = self:Coerce(node:GetAttribute(field.Name), field.ValueType)
		node:SetAttribute(field.Name, if value ~= nil then self:_convert(value, valueType) else nil)
	end
end

--[=[
	Sets a field's default. When the field fills defaults, nodes still holding the old default move to the
	new one; values that were edited per node are left alone.
]=]
function NodeTypes.SetFieldDefault(
	self: NodeTypes,
	nodeType: Types.NodeType,
	field: Types.Field,
	value: Types.FieldValue
)
	if field.FillDefault then
		for _, node in self:GetNodesOfType(nodeType.Name) do
			if node:GetAttribute(field.Name) == field.Default then
				node:SetAttribute(field.Name, value)
			end
		end
	end

	field.Instance:SetAttribute(FIELD_ATTRIBUTES.DEFAULT, value)
end

--[=[
	Overwrites the field on every node of the type with its starting value.
]=]
function NodeTypes.ResetField(self: NodeTypes, nodeType: Types.NodeType, field: Types.Field): number
	local nodes = self:GetNodesOfType(nodeType.Name)
	for _, node in nodes do
		node:SetAttribute(field.Name, self:GetInitialValue(field))
	end

	return #nodes
end

--[=[
	The value a node starts with: the default when the field fills defaults, otherwise empty. Empty is "" for
	strings and no attribute for numbers and booleans.
]=]
function NodeTypes.GetInitialValue(self: NodeTypes, field: Types.Field): Types.FieldValue?
	if field.FillDefault then
		return field.Default
	end

	return if field.ValueType == "string" then "" else nil
end

function NodeTypes.GetZero(self: NodeTypes, valueType: Types.FieldValueType): Types.FieldValue
	if valueType == "number" then
		return 0
	elseif valueType == "boolean" then
		return false
	end

	return ""
end

function NodeTypes.Coerce(self: NodeTypes, value: unknown, valueType: Types.FieldValueType): Types.FieldValue?
	if valueType == "string" and typeof(value) == "string" then
		return value
	elseif valueType == "number" and typeof(value) == "number" then
		return value
	elseif valueType == "boolean" and typeof(value) == "boolean" then
		return value
	end

	return nil
end

function NodeTypes.IsEmpty(self: NodeTypes, value: unknown): boolean
	return value == nil or (typeof(value) == "string" and Format:Trim(value) == "")
end

function NodeTypes.ParseValue(
	self: NodeTypes,
	text: string,
	valueType: Types.FieldValueType
): (Types.FieldValue?, string?)
	local trimmed = Format:Trim(text)
	if valueType == "string" then
		return trimmed, nil
	elseif valueType == "number" then
		local number = tonumber(trimmed)
		if number == nil then
			return nil, `'{trimmed}' is not a number.`
		end
		return number, nil
	end

	local lowered = string.lower(trimmed)
	if lowered == "true" or lowered == "yes" or lowered == "1" then
		return true, nil
	elseif lowered == "false" or lowered == "no" or lowered == "0" then
		return false, nil
	end

	return nil, `'{trimmed}' is not true or false.`
end

function NodeTypes.FormatValue(self: NodeTypes, value: Types.FieldValue?): string
	return if value == nil then "" else tostring(value)
end

--[=[
	@priv
]=]
function NodeTypes._readField(self: NodeTypes, config: Configuration): Types.Field
	local valueType: Types.FieldValueType = self:_parseValueType(config:GetAttribute(FIELD_ATTRIBUTES.VALUE_TYPE))
	local default = self:Coerce(config:GetAttribute(FIELD_ATTRIBUTES.DEFAULT), valueType)

	return {
		Name = config.Name,
		ValueType = valueType,
		Default = if default ~= nil then default else self:GetZero(valueType),
		FillDefault = config:GetAttribute(FIELD_ATTRIBUTES.FILL_DEFAULT) == true,
		Required = config:GetAttribute(FIELD_ATTRIBUTES.REQUIRED) == true,
		Instance = config,
	}
end

--[=[
	@priv
	Adds missing fields and replaces values of the wrong type. With `FillDefault` on, empty values are
	filled with the default too.
]=]
function NodeTypes._fillFields(self: NodeTypes, node: Part, nodeType: Types.NodeType)
	for _, field in nodeType.Fields do
		local value = self:Coerce(node:GetAttribute(field.Name), field.ValueType)
		if value == nil or (field.FillDefault and self:IsEmpty(value)) then
			node:SetAttribute(field.Name, self:GetInitialValue(field))
		end
	end
end

--[=[
	@priv
]=]
function NodeTypes._stripFields(self: NodeTypes, node: Part, previous: Types.NodeType, replacement: Types.NodeType?)
	local kept: { [string]: Types.FieldValueType } = {}
	if replacement ~= nil then
		for _, field in replacement.Fields do
			kept[field.Name] = field.ValueType
		end
	end

	for _, field in previous.Fields do
		if kept[field.Name] ~= field.ValueType then
			node:SetAttribute(field.Name, nil)
		end
	end
end

--[=[
	@priv
]=]
function NodeTypes._convert(
	self: NodeTypes,
	value: Types.FieldValue,
	valueType: Types.FieldValueType
): Types.FieldValue?
	local converted = self:ParseValue(self:FormatValue(value), valueType)
	return converted
end

--[=[
	@priv
]=]
function NodeTypes._parseValueType(self: NodeTypes, value: unknown): Types.FieldValueType
	if value == "number" then
		return "number"
	elseif value == "boolean" then
		return "boolean"
	end

	return "string"
end

--[=[
	@priv
]=]
function NodeTypes._parseShape(self: NodeTypes, value: unknown): Enum.PartType
	for _, shape in Constants.SHAPES do
		if value == shape.Name then
			return shape
		end
	end

	return Constants.DEFAULT_APPEARANCE.Shape
end

return NodeTypes

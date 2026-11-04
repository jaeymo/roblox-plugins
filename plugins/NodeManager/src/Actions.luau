--!strict
local Selection = game:GetService("Selection")
local Workspace = game:GetService("Workspace")

local Constants = require(script.Parent.Constants)
local Format = require(script.Parent.Format)
local NodeAppearance = require(script.Parent.NodeAppearance)
local NodeStore = require(script.Parent.NodeStore)
local NodeTypes = require(script.Parent.NodeTypes)
local Settings = require(script.Parent.Settings)
local Spatial = require(script.Parent.Spatial)
local Status = require(script.Parent.Status)
local Types = require(script.Parent.Types)
local Ui = require(script.Parent.Ui)

local CAMERA_PLACEMENT_RANGE = 1000
local CAMERA_FALLBACK_DISTANCE = 30
local NODE_SPACING = 1

local FOCUS_DISTANCE_SCALE = 2.5
local MIN_FOCUS_RADIUS = 4

type Box = {
	Min: Vector3,
	Max: Vector3,
}

local Actions = {}

export type Actions = typeof(Actions)

function Actions.GetSelectedNodes(self: Actions): { Part }
	local nodes = {}
	for _, instance in Selection:Get() do
		if NodeStore:IsNode(instance) then
			table.insert(nodes, instance :: Part)
		end
	end

	return nodes
end

function Actions.SelectNodes(self: Actions, nodes: { Part }, focus: boolean)
	local instances: { Instance } = {}
	for _, node in nodes do
		if node.Parent ~= nil then
			table.insert(instances, node)
		end
	end

	Selection:Set(instances)
	if focus then
		self:FocusNodes(nodes)
	end
end

function Actions.FocusNodes(self: Actions, nodes: { Part })
	local camera = Workspace.CurrentCamera
	local box: Box = nil :: any

	for _, node in nodes do
		if node.Parent ~= nil then
			box = self:_expandBox(box, self:_getPartBox(node))
		end
	end

	if camera == nil or box == nil then
		return
	end

	local center = (box.Min + box.Max) / 2
	local radius = math.max((box.Max - box.Min).Magnitude / 2, MIN_FOCUS_RADIUS)
	local look = camera.CFrame.LookVector
	camera.CFrame = CFrame.lookAt(center - look * radius * FOCUS_DISTANCE_SCALE, center)
	camera.Focus = CFrame.new(center)
end

--[=[
	Creates a node of the named type, or a plain untyped node when `typeName` is nil.
]=]
function Actions.CreateNode(self: Actions, typeName: string?, group: Folder?)
	local nodeType = if typeName ~= nil then NodeTypes:Get(typeName) else nil
	if typeName ~= nil and nodeType == nil then
		Status:Error(`The node type '{typeName}' no longer exists. Pick another type.`)
		return
	end

	local size = if nodeType ~= nil then nodeType.Size else Constants.DEFAULT_APPEARANCE.Size
	local grounded = if nodeType ~= nil then nodeType.Grounded else true
	local position = self:_getPlacementPosition(size, grounded)
	local node: Part? = nil
	NodeStore:Edit(`Create {typeName or "untyped"} node`, function()
		local created = NodeStore:CreateNode(typeName or "Node", position, group)
		if nodeType ~= nil then
			NodeTypes:AssignType(created, nodeType)
		end
		node = created
	end)

	if node ~= nil then
		Selection:Set({ node })
		Status:Info(`Created {node.Name}.`)
	end
end

function Actions.DuplicateNodes(self: Actions, nodes: { Part })
	if not self:_requireNodes(nodes, "duplicate") then
		return
	end

	local copies: { Instance } = {}
	NodeStore:Edit("Duplicate nodes", function()
		local taken = NodeStore:GetTakenNames()
		for _, node in nodes do
			table.insert(copies, NodeStore:DuplicateNode(node, taken))
		end
	end)

	Selection:Set(copies)
	Status:Info(`Duplicated {#copies} node(s).`)
end

function Actions.DeleteNodes(self: Actions, nodes: { Part })
	if not self:_requireNodes(nodes, "delete") then
		return
	end

	-- Parenting to nil instead of destroying keeps the deletion undoable.
	NodeStore:Edit("Delete nodes", function()
		for _, node in nodes do
			node.Parent = nil
		end
	end)
	Status:Info(`Deleted {#nodes} node(s). Use Undo to restore them.`)
end

--[=[
	Changes the type of every node, removing fields that only the old type defined.
]=]
function Actions.SetNodesType(self: Actions, nodes: { Part }, typeName: string?)
	local nodeType = if typeName ~= nil then NodeTypes:Get(typeName) else nil
	if typeName ~= nil and nodeType == nil then
		Status:Error(`The node type '{typeName}' no longer exists.`)
		return
	end

	self:EditNodes(`Set node type to {typeName or "none"}`, nodes, function(node: Part)
		NodeTypes:AssignType(node, nodeType)
	end)
end

function Actions.RenameNode(self: Actions, node: Part, name: string)
	local trimmed = Format:Trim(name)
	if trimmed == "" then
		Status:Error("Node names cannot be empty.")
		return
	end

	if trimmed == node.Name then
		return
	end

	NodeStore:Edit("Rename node", function()
		node.Name = trimmed
	end)
end

--[=[
	Applies `apply` to every node as one undoable change.
]=]
function Actions.EditNodes(self: Actions, actionName: string, nodes: { Part }, apply: (node: Part) -> ())
	if not self:_requireNodes(nodes, "edit") then
		return
	end

	NodeStore:Edit(actionName, function()
		for _, node in nodes do
			apply(node)
		end
	end)
end

function Actions.SetNodesHidden(self: Actions, nodes: { Part }, hidden: boolean)
	self:EditNodes(if hidden then "Hide nodes" else "Show nodes", nodes, function(node: Part)
		NodeAppearance:SetHidden(node, hidden)
	end)
end

--[=[
	Hides every node when any of them is visible, otherwise shows them all.
]=]
function Actions.ToggleNodesHidden(self: Actions, nodes: { Part })
	local anyVisible = false
	for _, node in nodes do
		if not NodeAppearance:IsHidden(node) then
			anyVisible = true
			break
		end
	end

	self:SetNodesHidden(nodes, anyVisible)
end

function Actions.SnapNodesToGround(self: Actions, nodes: { Part })
	if not self:_requireNodes(nodes, "snap") then
		return
	end

	self:PrepareSpatial()
	local searchDistance = Settings:GetNumber("GroundSearchDistance")
	local surfaceSearchHeight = Settings:GetNumber("SurfaceSearchHeight")
	local missing = 0

	NodeStore:Edit("Snap nodes to ground", function()
		for _, node in nodes do
			local position = Spatial:GetGroundedPosition(node, searchDistance, surfaceSearchHeight)
			if position ~= nil then
				node.CFrame = node.CFrame.Rotation + position
			else
				missing += 1
			end
		end
	end)

	if missing > 0 then
		Status:Error(`{missing} node(s) had no ground within {searchDistance} studs below and were not moved.`)
	else
		Status:Info(`Snapped {#nodes} node(s) to the ground.`)
	end
end

function Actions.CreateGroup(self: Actions, name: string): Folder?
	local trimmed = Format:Trim(name)
	if not self:_validateGroupName(trimmed, nil) then
		return nil
	end

	local group: Folder? = nil
	NodeStore:Edit("Create node group", function()
		group = NodeStore:CreateGroup(trimmed)
	end)

	Status:Info(`Created group '{trimmed}'.`)
	return group
end

function Actions.RenameGroup(self: Actions, group: Folder, name: string)
	local trimmed = Format:Trim(name)
	if trimmed == group.Name or not self:_validateGroupName(trimmed, group) then
		return
	end

	NodeStore:Edit("Rename node group", function()
		group.Name = trimmed
	end)
end

function Actions.DeleteGroup(self: Actions, group: Folder)
	local name = group.Name
	local moved = 0
	NodeStore:Edit("Delete node group", function()
		moved = NodeStore:DeleteGroup(group)
	end)

	Status:Info(`Deleted group '{name}'. {moved} node(s) were moved to Ungrouped.`)
end

function Actions.MoveNodesToGroup(self: Actions, nodes: { Part }, group: Folder?)
	if not self:_requireNodes(nodes, "move") then
		return
	end

	NodeStore:Edit("Move nodes to group", function()
		NodeStore:MoveToGroup(nodes, group)
	end)
	Status:Info(`Moved {#nodes} node(s) to {if group ~= nil then `'{group.Name}'` else "Ungrouped"}.`)
end

--[=[
	Shows a menu of groups (plus a "New group" entry) and moves `nodes` into the chosen one.
]=]
function Actions.PromptMoveToGroup(self: Actions, nodes: { Part }, anchor: GuiObject?)
	if not self:_requireNodes(nodes, "move") then
		return
	end

	local groups = NodeStore:GetGroups()
	local options = { "Ungrouped" }
	for _, group in groups do
		table.insert(options, group.Name)
	end
	table.insert(options, "New group...")

	Ui:ShowMenu(options, function(index: number)
		if index == 1 then
			self:MoveNodesToGroup(nodes, nil)
		elseif index == #options then
			Ui:Prompt("New group name", "", function(name: string)
				local group = self:CreateGroup(name)
				if group ~= nil then
					self:MoveNodesToGroup(nodes, group)
				end
			end)
		else
			self:MoveNodesToGroup(nodes, groups[index - 1])
		end
	end, anchor)
end

function Actions.SetBoundsFromSelection(self: Actions)
	local box: Box? = nil
	for _, instance in Selection:Get() do
		if instance:IsA("BasePart") and not NodeStore:IsNode(instance) then
			box = self:_expandBox(box, self:_getPartBox(instance))
		elseif instance:IsA("Model") then
			local cframe, size = instance:GetBoundingBox()
			box = self:_expandBox(box, self:_getOrientedBox(cframe, size))
		end
	end

	if box == nil then
		Status:Error("Select the parts or models that should define the world bounds.")
		return
	end

	local bounds: Types.Bounds = { Min = box.Min, Max = box.Max }
	NodeStore:Edit("Set node world bounds", function()
		NodeStore:SetBounds(bounds)
	end)
	Status:Info(`World bounds set to {Format:Vector3(box.Min)} .. {Format:Vector3(box.Max)}.`)
end

function Actions.ApplyFixes(self: Actions, issues: { Types.Issue }): { Types.Issue }
	local fixable = {}

	for _, issue in issues do
		if issue.Fix ~= nil and issue.Node.Parent ~= nil then
			table.insert(fixable :: any, issue)
		end
	end

	if #fixable == 0 then
		Status:Error("There are no fixable issues on nodes that still exist.")
		return {}
	end

	self:PrepareSpatial()
	local fixed = {}
	local failures = {}

	NodeStore:Edit("Fix node issues", function()
		for _, issue in fixable :: any do
			local fix = issue.Fix :: Types.Fix
			local ok, reason = fix.Apply(issue.Node)
			if ok then
				table.insert(fixed, issue)
			else
				table.insert(failures, `{issue.Node.Name}: {reason or "the fix could not be applied"}`)
			end
		end
	end)

	if #failures > 0 then
		Status:Error(`Fixed {#fixed} issue(s); {#failures} could not be fixed. {failures[1]}`)
	else
		Status:Info(`Fixed {#fixed} issue(s).`)
	end

	return fixed
end

function Actions.PrepareSpatial(self: Actions)
	local root = NodeStore:GetRoot()
	Spatial:SetExcluded(if root ~= nil then { root } else {})
end

--[=[
	@priv
]=]
function Actions._requireNodes(self: Actions, nodes: { Part }, verb: string): boolean
	if #nodes == 0 then
		Status:Error(`Select one or more nodes to {verb}.`)
		return false
	end

	return true
end

--[=[
	@priv
]=]
function Actions._validateGroupName(self: Actions, name: string, current: Folder?): boolean
	if name == "" then
		Status:Error("Group names cannot be empty.")
		return false
	end

	local existing = NodeStore:FindGroup(name)
	if existing ~= nil and existing ~= current then
		Status:Error(`A group named '{existing.Name}' already exists.`)
		return false
	end

	return true
end

--[=[
	@priv
	Picks where a new node goes: on top of the selected geometry, beside selected nodes, or where the camera
	is looking. Grounded nodes are then dropped onto the surface below.
]=]
function Actions._getPlacementPosition(self: Actions, nodeSize: number, grounded: boolean): Vector3
	self:PrepareSpatial()

	local size = Vector3.one * nodeSize
	local surface = self:_getSelectionSurface(nodeSize) or self:_getCameraSurface()
	local position = Spatial:GetRestingPosition(surface, size)

	if grounded then
		local ground = Spatial:FindGround(position, Settings:GetNumber("GroundSearchDistance"))
		if ground ~= nil then
			position = Spatial:GetRestingPosition(ground.Position, size)
		end
	end

	return position
end

--[=[
	@priv
]=]
function Actions._getSelectionSurface(self: Actions, nodeSize: number): Vector3?
	local box: Box? = nil
	local lastNode: Part? = nil

	for _, instance in Selection:Get() do
		if NodeStore:IsNode(instance) then
			lastNode = instance :: Part
		elseif instance:IsA("BasePart") then
			box = self:_expandBox(box, self:_getPartBox(instance))
		elseif instance:IsA("Model") then
			local cframe, size = instance:GetBoundingBox()
			box = self:_expandBox(box, self:_getOrientedBox(cframe, size))
		elseif instance:IsA("Attachment") then
			box = self:_expandBox(box, { Min = instance.WorldPosition, Max = instance.WorldPosition })
		end
	end

	if box ~= nil then
		local center = (box.Min + box.Max) / 2
		return Vector3.new(center.X, box.Max.Y, center.Z)
	end

	if lastNode ~= nil then
		local offset = lastNode.Size.X / 2 + NODE_SPACING + nodeSize / 2
		return lastNode.Position + Vector3.new(offset, -lastNode.Size.Y / 2, 0)
	end

	return nil
end

--[=[
	@priv
]=]
function Actions._getCameraSurface(self: Actions): Vector3
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return Vector3.zero
	end

	local origin = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local result = Spatial:Raycast(origin, look * CAMERA_PLACEMENT_RANGE)
	if result ~= nil then
		return result.Position
	end

	return origin + look * CAMERA_FALLBACK_DISTANCE
end

--[=[
	@priv
]=]
function Actions._getPartBox(self: Actions, part: BasePart): Box
	return self:_getOrientedBox(part.CFrame, part.Size)
end

--[=[
	@priv
	Returns the world-aligned bounds of an oriented box.
]=]
function Actions._getOrientedBox(self: Actions, cframe: CFrame, size: Vector3): Box
	local half = size / 2
	local right, up, back = cframe.RightVector, cframe.UpVector, cframe.LookVector
	local extents = Vector3.new(
		math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(back.X) * half.Z,
		math.abs(right.Y) * half.X + math.abs(up.Y) * half.Y + math.abs(back.Y) * half.Z,
		math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(back.Z) * half.Z
	)

	return { Min = cframe.Position - extents, Max = cframe.Position + extents }
end

--[=[
	@priv
]=]
function Actions._expandBox(self: Actions, box: Box?, other: Box): Box
	if box == nil then
		return other
	end

	return { Min = box.Min:Min(other.Min), Max = box.Max:Max(other.Max) }
end

return Actions

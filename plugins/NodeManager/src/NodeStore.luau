--!strict
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local PhysicsService = game:GetService("PhysicsService")
local Workspace = game:GetService("Workspace")

local Constants = require(script.Parent.Constants)
local Janitor = require(script.Parent.Parent.Packages.Janitor)
local NodeAppearance = require(script.Parent.NodeAppearance)
local Signal = require(script.Parent.Parent.Packages.Signal)
local Types = require(script.Parent.Types)

local ATTRIBUTES = Constants.ATTRIBUTES

local NodeStore = {
	Changed = Signal.new() :: Signal.Signal<>,
	_janitor = Janitor.new(),
	_rootJanitor = Janitor.new(),
	_root = nil :: Folder?,
	_changeQueued = false,
}

export type NodeStore = typeof(NodeStore)

function NodeStore.Start(self: NodeStore)
	self._janitor:Add(Workspace.ChildAdded:Connect(function(child: Instance)
		if self._root == nil and self:_isRoot(child) then
			self:_bindRoot(child :: Folder)
		end
	end))
	self._janitor:Add(Workspace.ChildRemoved:Connect(function(child: Instance)
		if child == self._root then
			self:_bindRoot(self:_findRoot())
		end
	end))

	self:_bindRoot(self:_findRoot())
end

function NodeStore.Stop(self: NodeStore)
	self._rootJanitor:Cleanup()
	self._janitor:Cleanup()
	self._root = nil
end

function NodeStore.GetRoot(self: NodeStore): Folder?
	return self._root
end

function NodeStore.EnsureRoot(self: NodeStore): Folder
	self:_ensureCollisionGroup()

	local root = self._root
	if root ~= nil then
		return root
	end

	local folder = Instance.new("Folder")
	folder.Name = Constants.ROOT_NAME
	folder:AddTag(Constants.ROOT_TAG)
	folder.Parent = Workspace
	self:_bindRoot(folder)
	return folder
end

function NodeStore.IsNode(self: NodeStore, instance: Instance): boolean
	local root = self._root
	return root ~= nil
		and instance:IsA("Part")
		and instance:HasTag(Constants.NODE_TAG)
		and instance:IsDescendantOf(root)
end

function NodeStore.GetNodes(self: NodeStore): { Part }
	local nodes = {}
	local root = self._root
	if root == nil then
		return nodes
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Part") and descendant:HasTag(Constants.NODE_TAG) then
			table.insert(nodes, descendant)
		end
	end

	return nodes
end

--[=[
	Returns the nodes inside `group`, or the nodes placed directly under the root when `group` is nil.
]=]
function NodeStore.GetGroupNodes(self: NodeStore, group: Folder?): { Part }
	local nodes = {}
	for _, node in self:GetNodes() do
		if self:GetGroupOf(node) == group then
			table.insert(nodes, node)
		end
	end

	return nodes
end

function NodeStore.GetGroups(self: NodeStore): { Folder }
	local groups = {}
	local root = self._root
	if root == nil then
		return groups
	end

	for _, child in root:GetChildren() do
		if child:IsA("Folder") then
			table.insert(groups, child)
		end
	end

	table.sort(groups, function(a: Folder, b: Folder): boolean
		return string.lower(a.Name) < string.lower(b.Name)
	end)

	return groups
end

function NodeStore.IsGroup(self: NodeStore, instance: Instance): boolean
	return instance:IsA("Folder") and self._root ~= nil and instance.Parent == self._root
end

function NodeStore.GetGroupOf(self: NodeStore, node: Part): Folder?
	local root = self._root
	local current: Instance = node
	local parent = current.Parent
	while parent ~= nil and parent ~= root do
		current = parent
		parent = current.Parent
	end

	if parent == root and current ~= node and current:IsA("Folder") then
		return current
	end

	return nil
end

function NodeStore.FindGroup(self: NodeStore, name: string): Folder?
	local lowered = string.lower(name)
	for _, group in self:GetGroups() do
		if string.lower(group.Name) == lowered then
			return group
		end
	end

	return nil
end

function NodeStore.GetBounds(self: NodeStore): Types.Bounds?
	local root = self._root
	if root == nil then
		return nil
	end

	local min = root:GetAttribute(ATTRIBUTES.BOUNDS_MIN)
	local max = root:GetAttribute(ATTRIBUTES.BOUNDS_MAX)
	if typeof(min) ~= "Vector3" or typeof(max) ~= "Vector3" then
		return nil
	end

	return { Min = min:Min(max), Max = min:Max(max) }
end

function NodeStore.GetTakenNames(self: NodeStore): { [string]: boolean }
	local taken = {}
	for _, node in self:GetNodes() do
		taken[node.Name] = true
	end

	return taken
end

function NodeStore.UniqueName(self: NodeStore, base: string, taken: { [string]: boolean }): string
	local index = 1
	while taken[`{base}_{index}`] do
		index += 1
	end

	local name = `{base}_{index}`
	taken[name] = true
	return name
end

--[=[
	Runs `callback` as a single undoable change. If the callback errors, its changes are reverted and the
	error is rethrown.
]=]
function NodeStore.Edit(self: NodeStore, actionName: string, callback: () -> ())
	local recording = ChangeHistoryService:TryBeginRecording(actionName)
	if recording == nil then
		warn(`[{script.Name}] Could not record '{actionName}' for undo; the change will still be applied.`)
	end

	local failure: string? = nil
	local ok = xpcall(callback, function(message: any)
		failure = debug.traceback(tostring(message), 2)
	end)
	if recording ~= nil then
		ChangeHistoryService:FinishRecording(
			recording,
			if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end

	self:_queueChanged()

	if not ok then
		error(failure, 0)
	end
end

function NodeStore.CreateNode(self: NodeStore, baseName: string, position: Vector3, group: Folder?): Part
	local root = self:EnsureRoot()

	local node = Instance.new("Part")
	node.Name = self:UniqueName(baseName, self:GetTakenNames())

	NodeAppearance:ConfigurePhysics(node)
	NodeAppearance:ApplyAppearance(node, Constants.DEFAULT_APPEARANCE)

	node.CFrame = CFrame.new(position)
	node:AddTag(Constants.NODE_TAG)
	node.Parent = group or root

	return node
end

function NodeStore.DuplicateNode(self: NodeStore, node: Part, taken: { [string]: boolean }): Part
	local copy = node:Clone()
	local base = string.match(node.Name, "^(.-)_%d+$") or node.Name

	copy.Name = self:UniqueName(base, taken)
	copy.CFrame = node.CFrame + Vector3.new(node.Size.X + 1, 0, 0)
	copy.Parent = node.Parent
	return copy
end

function NodeStore.CreateGroup(self: NodeStore, name: string): Folder
	local group = Instance.new("Folder")
	group.Name = name
	group.Parent = self:EnsureRoot()
	return group
end

--[=[
	Removes the group but keeps its nodes by moving them to the root.
]=]
function NodeStore.DeleteGroup(self: NodeStore, group: Folder): number
	local root = self:EnsureRoot()
	local nodes = self:GetGroupNodes(group)
	for _, node in nodes do
		node.Parent = root
	end

	group.Parent = nil
	return #nodes
end

function NodeStore.MoveToGroup(self: NodeStore, nodes: { Part }, group: Folder?)
	local parent = group or self:EnsureRoot()
	for _, node in nodes do
		node.Parent = parent
	end
end

function NodeStore.SetBounds(self: NodeStore, bounds: Types.Bounds?)
	local root = self:EnsureRoot()
	root:SetAttribute(ATTRIBUTES.BOUNDS_MIN, if bounds ~= nil then bounds.Min else nil)
	root:SetAttribute(ATTRIBUTES.BOUNDS_MAX, if bounds ~= nil then bounds.Max else nil)
end

--[=[
	@priv
]=]
function NodeStore._isRoot(self: NodeStore, instance: Instance): boolean
	return instance:IsA("Folder") and instance:HasTag(Constants.ROOT_TAG)
end

--[=[
	@priv
]=]
function NodeStore._findRoot(self: NodeStore): Folder?
	for _, child in Workspace:GetChildren() do
		if self:_isRoot(child) then
			return child :: Folder
		end
	end

	return nil
end

--[=[
	@priv
]=]
function NodeStore._bindRoot(self: NodeStore, root: Folder?)
	self._rootJanitor:Cleanup()
	self._root = root

	if root ~= nil then
		self._rootJanitor:Add(root.DescendantAdded:Connect(function(descendant: Instance)
			self:_watch(descendant)
			self:_queueChanged()
		end))
		self._rootJanitor:Add(root.DescendantRemoving:Connect(function(descendant: Instance)
			self._rootJanitor:Remove(descendant)
			self:_queueChanged()
		end))
		self._rootJanitor:Add(root.AttributeChanged:Connect(function()
			self:_queueChanged()
		end))

		for _, descendant in root:GetDescendants() do
			self:_watch(descendant)
		end
	end

	self:_queueChanged()
end

--[=[
	@priv
]=]
function NodeStore._watch(self: NodeStore, instance: Instance)
	-- Configurations under the root are node type and field definitions.
	if not self:IsGroup(instance) and not self:IsNode(instance) and not instance:IsA("Configuration") then
		return
	end

	local function onChanged()
		self:_queueChanged()
	end

	local janitor = Janitor.new()
	janitor:Add(instance:GetPropertyChangedSignal("Name"):Connect(onChanged))
	janitor:Add(instance.AttributeChanged:Connect(onChanged))
	self._rootJanitor:Add(janitor, "Destroy", instance)
end

--[=[
	@priv
]=]
function NodeStore._queueChanged(self: NodeStore)
	if self._changeQueued then
		return
	end

	-- Coalesces bursts of changes (bulk edits, undo, pasting many nodes) into one notification.
	self._changeQueued = true
	task.defer(function()
		self._changeQueued = false
		self.Changed:Fire()
	end)
end

--[=[
	@priv
]=]
function NodeStore._ensureCollisionGroup(self: NodeStore)
	local group = Constants.COLLISION_GROUP
	if PhysicsService:IsCollisionGroupRegistered(group) then
		return
	end

	-- Registration fails once a place reaches the collision group limit; nodes still work without it.
	local ok, err = pcall(function()
		PhysicsService:RegisterCollisionGroup(group)
		PhysicsService:CollisionGroupSetCollidable(group, "Default", false)
	end)
	if not ok then
		warn(`[{script.Name}] Could not register collision group '{group}': {err}`)
	end
end

return NodeStore

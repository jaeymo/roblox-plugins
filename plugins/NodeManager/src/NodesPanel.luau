--!strict
local Selection = game:GetService("Selection")
local UserInputService = game:GetService("UserInputService")

local Actions = require(script.Parent.Actions)
local Janitor = require(script.Parent.Parent.Packages.Janitor)
local NodeAppearance = require(script.Parent.NodeAppearance)
local NodeStore = require(script.Parent.NodeStore)
local NodeTypes = require(script.Parent.NodeTypes)
local Settings = require(script.Parent.Settings)
local Types = require(script.Parent.Types)
local Ui = require(script.Parent.Ui)
local VirtualList = require(script.Parent.VirtualList)

local StyleColor = Enum.StudioStyleGuideColor

local DOUBLE_CLICK_TIME = 0.35
local INDENT = 18
local TOGGLE_WIDTH = 20
local DETAIL_WIDTH = 96
local SWATCH_SIZE = 10
local VISIBLE_GLYPH = "●"
local HIDDEN_GLYPH = "○"
local CONTROLS_HEIGHT = Ui.ROW_HEIGHT * 3 + Ui.SPACING * 4

type GroupEntry = {
	Kind: "Group",
	Group: Folder?,
	Label: string,
	Count: number,
	Collapsed: boolean,
	AllHidden: boolean,
}

type NodeEntry = {
	Kind: "Node",
	Node: Part,
}

type Entry = GroupEntry | NodeEntry

type Controls = {
	Type: TextButton,
	GroupFilter: TextButton,
	List: VirtualList.VirtualList,
}

local NodesPanel = {
	_janitor = Janitor.new(),
	_controls = nil :: Controls?,
	_entries = {} :: { Entry },
	_search = "",
	_groupFilter = "All" :: Types.GroupFilter,
	_collapsed = {} :: { [Folder]: boolean },
	_ungroupedCollapsed = false,
	_selected = {} :: { [Instance]: boolean },
	_anchorIndex = nil :: number?,
	_lastClickNode = nil :: Part?,
	_lastClickTime = 0,
	_typeName = nil :: string?,
}

export type NodesPanel = typeof(NodesPanel)

function NodesPanel.Init(self: NodesPanel, parent: Frame)
	local savedType = Settings:GetString("LastType")
	self._typeName = if savedType ~= "" then savedType else nil

	local controls = Ui:Frame(parent, UDim2.new(1, 0, 0, CONTROLS_HEIGHT))
	Ui:Padding(controls, Ui.SPACING)
	Ui:ListLayout(controls, Enum.FillDirection.Vertical, Ui.SPACING)

	local createRow = Ui:Frame(controls, UDim2.new(1, 0, 0, Ui.ROW_HEIGHT))
	Ui:ListLayout(createRow, Enum.FillDirection.Horizontal, Ui.SPACING)
	local typeButton = Ui:Button(createRow, "", UDim2.new(0.6, -Ui.SPACING, 1, 0), self._janitor, function()
		self:_chooseType()
	end)
	Ui:Button(createRow, "+ Add Node", UDim2.new(0.4, 0, 1, 0), self._janitor, function()
		Actions:CreateNode(self._typeName, self:_getTargetGroup())
	end, true)

	local search = Ui:Input(
		controls,
		UDim2.new(1, 0, 0, Ui.ROW_HEIGHT),
		"Search by name, display name or type",
		self._janitor,
		function() end
	)
	self._janitor:Add(search:GetPropertyChangedSignal("Text"):Connect(function()
		self._search = string.lower(search.Text)
		self:Rebuild()
	end))

	local groupRow = Ui:Frame(controls, UDim2.new(1, 0, 0, Ui.ROW_HEIGHT))
	Ui:ListLayout(groupRow, Enum.FillDirection.Horizontal, Ui.SPACING)
	local groupFilterButton = Ui:Button(groupRow, "", UDim2.new(0.6, -Ui.SPACING, 1, 0), self._janitor, function()
		self:_chooseGroupFilter()
	end)
	Ui:Button(groupRow, "+ Group", UDim2.new(0.4, 0, 1, 0), self._janitor, function()
		Ui:Prompt("New group name", "", function(name: string)
			local group = Actions:CreateGroup(name)
			if group ~= nil then
				self._groupFilter = group
				self:Rebuild()
			end
		end)
	end)

	local list = VirtualList.new(
		parent,
		UDim2.new(1, 0, 1, -CONTROLS_HEIGHT),
		UDim2.fromOffset(0, CONTROLS_HEIGHT),
		Ui.ROW_HEIGHT,
		function(row: Frame): VirtualList.RowBinder
			return self:_createRow(row)
		end
	)
	self._janitor:Add(list, "Destroy")

	self._controls = {
		Type = typeButton,
		GroupFilter = groupFilterButton,
		List = list,
	}

	self._janitor:Add(NodeStore.Changed:Connect(function()
		self:Rebuild()
	end))
	self._janitor:Add(Selection.SelectionChanged:Connect(function()
		self:_syncSelection()
	end))

	self:_syncSelection()
	self:Rebuild()
end

function NodesPanel.Destroy(self: NodesPanel)
	self._janitor:Cleanup()
	self._controls = nil
	table.clear(self._entries)
end

function NodesPanel.Rebuild(self: NodesPanel)
	local controls = self._controls
	if controls == nil then
		return
	end

	local filter = self._groupFilter
	if typeof(filter) == "Instance" and not NodeStore:IsGroup(filter) then
		filter = "All"
		self._groupFilter = filter
	end

	local buckets: { [Folder]: { Part } } = {}
	local ungrouped: { Part } = {}
	for _, node in NodeStore:GetNodes() do
		if not self:_matchesSearch(node) then
			continue
		end

		local group = NodeStore:GetGroupOf(node)
		if group == nil then
			table.insert(ungrouped, node)
			continue
		end

		local bucket = buckets[group]
		if bucket == nil then
			bucket = {}
			buckets[group] = bucket
		end
		table.insert(bucket, node)
	end

	local entries: { Entry } = {}
	for _, group in NodeStore:GetGroups() do
		if filter == "All" or filter == group then
			self:_appendGroup(entries, group, buckets[group] or {}, self._collapsed[group] == true)
		end
	end
	if filter == "All" or filter == "Ungrouped" then
		self:_appendGroup(entries, nil, ungrouped, self._ungroupedCollapsed)
	end

	self._entries = entries
	self:_updateButtons()
	controls.List:SetCount(#entries)
end

--[=[
	@priv
]=]
function NodesPanel._appendGroup(
	self: NodesPanel,
	entries: { Entry },
	group: Folder?,
	nodes: { Part },
	collapsed: boolean
)
	-- Empty groups stay listed so they remain discoverable, except while searching. Ungrouped only appears
	-- when it has nodes.
	local isUngrouped = group == nil
	if #nodes == 0 and (self._search ~= "" or isUngrouped) then
		return
	end

	local allHidden = #nodes > 0
	for _, node in nodes do
		if not NodeAppearance:IsHidden(node) then
			allHidden = false
			break
		end
	end

	local label = if group then group.Name else "Ungrouped"
	local header: GroupEntry = {
		Kind = "Group",
		Group = group,
		Label = label,
		Count = #nodes,
		Collapsed = collapsed,
		AllHidden = allHidden,
	}
	table.insert(entries, header)

	if collapsed then
		return
	end

	local sortKeys: { [Part]: string } = {}
	for _, node in nodes do
		sortKeys[node] = string.lower(node.Name)
	end
	table.sort(nodes, function(a: Part, b: Part): boolean
		return sortKeys[a] < sortKeys[b]
	end)

	for _, node in nodes do
		local entry: NodeEntry = { Kind = "Node", Node = node }
		table.insert(entries, entry)
	end
end

--[=[
	@priv
]=]
function NodesPanel._matchesSearch(self: NodesPanel, node: Part): boolean
	local search = self._search
	if search == "" then
		return true
	end

	return string.find(string.lower(node.Name), search, 1, true) ~= nil
		or string.find(string.lower(NodeAppearance:GetDisplayName(node)), search, 1, true) ~= nil
		or string.find(string.lower(NodeAppearance:GetType(node) or ""), search, 1, true) ~= nil
end

--[=[
	@priv
]=]
function NodesPanel._createRow(self: NodesPanel, row: Frame): VirtualList.RowBinder
	local current: Entry? = nil
	local currentIndex = 0

	local hit = Instance.new("TextButton")
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BorderSizePixel = 0
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	Ui:Theme(hit, "BackgroundColor3", StyleColor.Item, Enum.StudioStyleGuideModifier.Selected)
	hit.Parent = row

	local toggle = Ui:FlatButton(row, "", UDim2.new(0, TOGGLE_WIDTH, 1, 0))
	local arrow = Ui:Label(row, "", UDim2.new(0, 14, 1, 0), StyleColor.DimmedText)
	local swatch = Ui:Frame(row, UDim2.fromOffset(SWATCH_SIZE, SWATCH_SIZE))
	swatch.AnchorPoint = Vector2.new(0, 0.5)
	swatch.BackgroundTransparency = 0
	local title = Ui:Label(row, "", UDim2.new())
	local detail = Ui:Label(row, "", UDim2.new(0, DETAIL_WIDTH, 1, 0), StyleColor.DimmedText)
	detail.TextXAlignment = Enum.TextXAlignment.Right

	self._janitor:Add(toggle.Activated:Connect(function()
		if current ~= nil then
			self:_toggleHidden(current)
		end
	end))
	self._janitor:Add(hit.InputBegan:Connect(function(input: InputObject)
		if current == nil then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_onPrimaryClick(current, currentIndex, input)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:_onSecondaryClick(current)
		end
	end))

	return function(index: number)
		local entry = self._entries[index]
		current = entry
		currentIndex = index

		if entry.Kind == "Group" then
			hit.BackgroundTransparency = 1
			toggle.Position = UDim2.fromOffset(4, 0)
			toggle.Text = if entry.AllHidden then HIDDEN_GLYPH else VISIBLE_GLYPH
			arrow.Visible = true
			arrow.Text = if entry.Collapsed then "▸" else "▾"
			arrow.Position = UDim2.fromOffset(4 + TOGGLE_WIDTH, 0)
			swatch.Visible = false
			title.Text = entry.Label
			title.Font = Enum.Font.BuilderSansBold
			title.Position = UDim2.fromOffset(4 + TOGGLE_WIDTH + 16, 0)
			title.Size = UDim2.new(1, -(4 + TOGGLE_WIDTH + 16 + DETAIL_WIDTH + 8), 1, 0)
			detail.Text = `{entry.Count} node{if entry.Count == 1 then "" else "s"}`
		else
			local node = entry.Node
			local left = 4 + INDENT
			hit.BackgroundTransparency = if self._selected[node] then 0 else 1
			toggle.Position = UDim2.fromOffset(left, 0)
			toggle.Text = if NodeAppearance:IsHidden(node) then HIDDEN_GLYPH else VISIBLE_GLYPH
			arrow.Visible = false
			swatch.Visible = true
			swatch.BackgroundColor3 = node.Color
			swatch.Position = UDim2.new(0, left + TOGGLE_WIDTH + 4, 0.5, 0)
			title.Text = node.Name
			title.Font = Enum.Font.BuilderSans
			title.Position = UDim2.fromOffset(left + TOGGLE_WIDTH + SWATCH_SIZE + 10, 0)
			title.Size = UDim2.new(1, -(left + TOGGLE_WIDTH + SWATCH_SIZE + 10 + DETAIL_WIDTH + 8), 1, 0)
			detail.Text = NodeAppearance:GetType(node) or "(no type)"
		end

		detail.Position = UDim2.new(1, -(DETAIL_WIDTH + 6), 0, 0)
	end
end

--[=[
	@priv
]=]
function NodesPanel._onPrimaryClick(self: NodesPanel, entry: Entry, index: number, input: InputObject)
	if entry.Kind == "Group" then
		if entry.Group ~= nil then
			self._collapsed[entry.Group] = not entry.Collapsed
		else
			self._ungroupedCollapsed = not entry.Collapsed
		end
		self:Rebuild()
		return
	end

	local node = entry.Node
	local anchorIndex = self._anchorIndex
	local ctrl = input:IsModifierKeyDown(Enum.ModifierKey.Ctrl)
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	local shift = input:IsModifierKeyDown(Enum.ModifierKey.Shift)
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)

	if shift and anchorIndex ~= nil then
		local range: { Instance } = {}
		local first = math.min(anchorIndex, index)
		local last = math.min(math.max(anchorIndex, index), #self._entries)
		for rangeIndex = first, last do
			local rangeEntry = self._entries[rangeIndex]
			if rangeEntry.Kind == "Node" then
				table.insert(range, rangeEntry.Node)
			end
		end
		Selection:Set(range)
		return
	end

	self._anchorIndex = index

	if ctrl then
		if self._selected[node] then
			Selection:Remove({ node })
		else
			Selection:Add({ node })
		end
		return
	end

	local now = os.clock()
	local isDoubleClick = self._lastClickNode == node and now - self._lastClickTime <= DOUBLE_CLICK_TIME
	self._lastClickNode = node
	self._lastClickTime = now

	Selection:Set({ node })
	if isDoubleClick then
		Actions:FocusNodes({ node })
	end
end

--[=[
	@priv
]=]
function NodesPanel._onSecondaryClick(self: NodesPanel, entry: Entry)
	if entry.Kind == "Group" then
		self:_showGroupMenu(entry)
		return
	end

	if not self._selected[entry.Node] then
		Selection:Set({ entry.Node })
	end

	local options = { "Focus", "Duplicate", "Snap to ground", "Show / hide", "Move to group...", "Delete" }
	Ui:ShowMenu(options, function(index: number)
		local nodes = Actions:GetSelectedNodes()
		if index == 1 then
			Actions:FocusNodes(nodes)
		elseif index == 2 then
			Actions:DuplicateNodes(nodes)
		elseif index == 3 then
			Actions:SnapNodesToGround(nodes)
		elseif index == 4 then
			Actions:ToggleNodesHidden(nodes)
		elseif index == 5 then
			Actions:PromptMoveToGroup(nodes)
		elseif index == 6 then
			Actions:DeleteNodes(nodes)
		end
	end)
end

--[=[
	@priv
]=]
function NodesPanel._showGroupMenu(self: NodesPanel, entry: GroupEntry)
	local group = entry.Group
	local options = { "Select nodes", "Show all", "Hide all", "Add node here" }

	if group ~= nil then
		table.insert(options, "Rename...")
		table.insert(options, "Delete group (keeps nodes)")
	end

	Ui:ShowMenu(options, function(index: number)
		if index == 1 then
			Actions:SelectNodes(NodeStore:GetGroupNodes(group), true)
		elseif index == 2 then
			Actions:SetNodesHidden(NodeStore:GetGroupNodes(group), false)
		elseif index == 3 then
			Actions:SetNodesHidden(NodeStore:GetGroupNodes(group), true)
		elseif index == 4 then
			Actions:CreateNode(self._typeName, group)
		elseif group ~= nil and index == 5 then
			Ui:Prompt("Rename group", group.Name, function(name: string)
				Actions:RenameGroup(group :: Folder, name)
			end)
		elseif group ~= nil and index == 6 then
			Actions:DeleteGroup(group)
		end
	end)
end

--[=[
	@priv
]=]
function NodesPanel._toggleHidden(self: NodesPanel, entry: Entry)
	if entry.Kind == "Group" then
		Actions:ToggleNodesHidden(NodeStore:GetGroupNodes(entry.Group))
	else
		Actions:ToggleNodesHidden({ entry.Node })
	end
end

--[=[
	@priv
]=]
function NodesPanel._chooseType(self: NodesPanel)
	local controls = self._controls
	if controls == nil then
		return
	end

	local names: { string } = {}
	local options = { if self._typeName == nil then "(none)  ✓" else "(none)" }
	for _, nodeType in NodeTypes:GetAll() do
		table.insert(names, nodeType.Name)
		table.insert(options, if nodeType.Name == self._typeName then `{nodeType.Name}  ✓` else nodeType.Name)
	end

	Ui:ShowMenu(options, function(index: number)
		self._typeName = if index == 1 then nil else names[index - 1]
		Settings:SetString("LastType", self._typeName or "")
		self:_updateButtons()
	end, controls.Type)
end

--[=[
	@priv
]=]
function NodesPanel._chooseGroupFilter(self: NodesPanel)
	local controls = self._controls
	if controls == nil then
		return
	end

	local groups = NodeStore:GetGroups()
	local options = { "All groups", "Ungrouped" }
	for _, group in groups do
		table.insert(options, group.Name)
	end

	Ui:ShowMenu(options, function(index: number)
		if index == 1 then
			self._groupFilter = "All"
		elseif index == 2 then
			self._groupFilter = "Ungrouped"
		else
			self._groupFilter = groups[index - 2]
		end
		self:Rebuild()
	end, controls.GroupFilter)
end

--[=[
	@priv
]=]
function NodesPanel._getTargetGroup(self: NodesPanel): Folder?
	local filter = self._groupFilter
	if typeof(filter) == "Instance" and NodeStore:IsGroup(filter) then
		return filter
	end

	return nil
end

--[=[
	@priv
]=]
function NodesPanel._updateButtons(self: NodesPanel)
	local controls = self._controls
	if controls == nil then
		return
	end

	-- Types can be renamed or deleted from the Types tab, which falls back to creating untyped nodes.
	local typeName = self._typeName
	if typeName ~= nil and NodeTypes:Get(typeName) == nil then
		typeName = nil
		self._typeName = nil
	end
	controls.Type.Text = `Type: {typeName or "(none)"}  ▾`

	local filter = self._groupFilter
	local filterName = if typeof(filter) == "Instance"
		then filter.Name
		elseif filter == "Ungrouped" then "Ungrouped"
		else "All groups"
	controls.GroupFilter.Text = `Group: {filterName}  ▾`
end

--[=[
	@priv
]=]
function NodesPanel._syncSelection(self: NodesPanel)
	table.clear(self._selected)
	for _, instance in Selection:Get() do
		self._selected[instance] = true
	end

	local controls = self._controls
	if controls ~= nil then
		controls.List:Render()
	end
end

return NodesPanel

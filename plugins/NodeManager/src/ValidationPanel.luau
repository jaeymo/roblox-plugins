--!strict
local Actions = require(script.Parent.Actions)
local Janitor = require(script.Parent.Parent.Packages.Janitor)
local NodeStore = require(script.Parent.NodeStore)
local Promise = require(script.Parent.Parent.Packages.Promise)
local Settings = require(script.Parent.Settings)
local Status = require(script.Parent.Status)
local Types = require(script.Parent.Types)
local Ui = require(script.Parent.Ui)
local Validator = require(script.Parent.Validator)
local VirtualList = require(script.Parent.VirtualList)

local StyleColor = Enum.StudioStyleGuideColor

local ISSUE_ROW_HEIGHT = 40
local FIX_BUTTON_WIDTH = 104
local CONTROLS_HEIGHT = Ui.ROW_HEIGHT * 2 + Ui.SPACING * 3

type Controls = {
	Summary: TextLabel,
	FixAll: TextButton,
	List: VirtualList.VirtualList,
}

local ValidationPanel = {
	_janitor = Janitor.new(),
	_controls = nil :: Controls?,
	_scan = nil :: Promise.TypedPromise<{ Types.Issue }>?,
	_issues = {} :: { Types.Issue },
	_fixed = {} :: { [Types.Issue]: boolean },
	_scannedCount = 0,
}

export type ValidationPanel = typeof(ValidationPanel)

function ValidationPanel.Init(self: ValidationPanel, parent: Frame)
	local controlsFrame = Ui:Frame(parent, UDim2.new(1, 0, 0, CONTROLS_HEIGHT))
	Ui:Padding(controlsFrame, Ui.SPACING)
	Ui:ListLayout(controlsFrame, Enum.FillDirection.Vertical, Ui.SPACING)

	local buttons = Ui:Frame(controlsFrame, UDim2.new(1, 0, 0, Ui.ROW_HEIGHT))
	Ui:ListLayout(buttons, Enum.FillDirection.Horizontal, Ui.SPACING)
	Ui:Button(buttons, "Scan Nodes", UDim2.new(0.5, -Ui.SPACING, 1, 0), self._janitor, function()
		self:_runScan()
	end, true)
	local fixAll = Ui:Button(buttons, "Fix All", UDim2.new(0.5, 0, 1, 0), self._janitor, function()
		self:_fixAll()
	end)

	local summary = Ui:Label(
		controlsFrame,
		"Scan to check nodes for placement and metadata problems.",
		UDim2.new(1, 0, 0, Ui.ROW_HEIGHT),
		StyleColor.DimmedText
	)

	local list = VirtualList.new(
		parent,
		UDim2.new(1, 0, 1, -CONTROLS_HEIGHT),
		UDim2.fromOffset(0, CONTROLS_HEIGHT),
		ISSUE_ROW_HEIGHT,
		function(row: Frame): VirtualList.RowBinder
			return self:_createRow(row)
		end
	)
	self._janitor:Add(list, "Destroy")

	self._controls = {
		Summary = summary,
		FixAll = fixAll,
		List = list,
	}

	self._janitor:Add(function()
		self:_cancelScan()
	end)

	self:_updateSummary()
end

function ValidationPanel.Destroy(self: ValidationPanel)
	self._janitor:Cleanup()
	self._controls = nil
	table.clear(self._issues)
	table.clear(self._fixed)
end

--[=[
	@priv
]=]
function ValidationPanel._runScan(self: ValidationPanel)
	local controls = self._controls
	if controls == nil then
		return
	end

	self:_cancelScan()

	local root = NodeStore:GetRoot()
	local nodes = NodeStore:GetNodes()
	if root == nil or #nodes == 0 then
		Status:Error("There are no nodes to validate. Create nodes from the Nodes tab first.")
		return
	end

	local options: Types.ScanOptions = {
		FloatTolerance = Settings:GetNumber("FloatTolerance"),
		GroundSearchDistance = Settings:GetNumber("GroundSearchDistance"),
		DuplicateTolerance = Settings:GetNumber("DuplicateTolerance"),
		SurfaceSearchHeight = Settings:GetNumber("SurfaceSearchHeight"),
	}

	controls.Summary.Text = `Scanning {#nodes} nodes...`
	local startTime = os.clock()

	local scan = Validator:Scan(nodes, root, NodeStore:GetBounds(), options, function(checked: number, total: number)
		controls.Summary.Text = `Scanning... {checked}/{total}`
	end)
	self._scan = scan

	scan:andThen(function(issues: { Types.Issue })
		self:_setIssues(issues, #nodes)
		Status:Info(`Scanned {#nodes} nodes in {string.format("%.2f", os.clock() - startTime)}s.`)
	end)
		:catch(function(err: any)
			self:_updateSummary()
			Status:Error(`Validation failed: {tostring(err)}`)
		end)
		:finally(function()
			if self._scan == scan then
				self._scan = nil
			end
		end)
end

--[=[
	@priv
]=]
function ValidationPanel._cancelScan(self: ValidationPanel)
	local scan = self._scan
	if scan ~= nil then
		self._scan = nil
		scan:cancel()
	end
end

--[=[
	@priv
]=]
function ValidationPanel._setIssues(self: ValidationPanel, issues: { Types.Issue }, scannedCount: number)
	local controls = self._controls
	if controls == nil then
		return
	end

	local sortKeys: { [Types.Issue]: string } = {}
	for _, issue in issues do
		sortKeys[issue] = `{if issue.Severity == "Error" then 0 else 1}{issue.Kind}{string.lower(issue.Node.Name)}`
	end
	table.sort(issues, function(a: Types.Issue, b: Types.Issue): boolean
		return sortKeys[a] < sortKeys[b]
	end)

	self._issues = issues
	self._scannedCount = scannedCount
	table.clear(self._fixed)
	controls.List.Frame.CanvasPosition = Vector2.zero
	controls.List:SetCount(#issues)
	self:_updateSummary()
end

--[=[
	@priv
]=]
function ValidationPanel._fixAll(self: ValidationPanel)
	local pending = {}
	for _, issue in self._issues do
		if issue.Fix ~= nil and not self._fixed[issue] then
			table.insert(pending :: any, issue)
		end
	end

	if #pending == 0 then
		Status:Error("There are no automatically fixable issues. Run a scan first.")
		return
	end

	self:_markFixed(Actions:ApplyFixes(pending))
end

--[=[
	@priv
]=]
function ValidationPanel._markFixed(self: ValidationPanel, fixed: { Types.Issue })
	for _, issue in fixed do
		self._fixed[issue] = true
	end

	local controls = self._controls
	if controls ~= nil then
		controls.List:Render()
	end
	self:_updateSummary()
end

--[=[
	@priv
]=]
function ValidationPanel._updateSummary(self: ValidationPanel)
	local controls = self._controls
	if controls == nil then
		return
	end

	local errors, warnings, fixable = 0, 0, 0
	for _, issue in self._issues do
		if self._fixed[issue] then
			continue
		end

		if issue.Severity == "Error" then
			errors += 1
		else
			warnings += 1
		end

		if issue.Fix ~= nil then
			fixable += 1
		end
	end

	controls.FixAll.Text = if fixable > 0 then `Fix All ({fixable})` else "Fix All"
	if self._scannedCount == 0 then
		return
	end

	if errors + warnings == 0 then
		controls.Summary.Text = `{self._scannedCount} nodes checked. No issues found.`
	else
		controls.Summary.Text = `{self._scannedCount} nodes checked: {errors} error(s), {warnings} warning(s).`
	end
end

--[=[
	@priv
]=]
function ValidationPanel._createRow(self: ValidationPanel, row: Frame): VirtualList.RowBinder
	local current: Types.Issue? = nil
	local half = ISSUE_ROW_HEIGHT / 2

	local hit = Instance.new("TextButton")
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BorderSizePixel = 0
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	hit.Parent = row

	local marker = Ui:Label(row, "●", UDim2.fromOffset(16, half))
	marker.Position = UDim2.fromOffset(6, 2)
	local title = Ui:Label(row, "", UDim2.new(1, -(FIX_BUTTON_WIDTH + 34), 0, half), StyleColor.MainText, true)
	title.Position = UDim2.fromOffset(24, 2)
	local message = Ui:Label(row, "", UDim2.new(1, -(FIX_BUTTON_WIDTH + 34), 0, half - 2), StyleColor.DimmedText)
	message.Position = UDim2.fromOffset(24, half)

	local fixButton = Ui:Button(row, "", UDim2.fromOffset(FIX_BUTTON_WIDTH, Ui.ROW_HEIGHT), self._janitor, function()
		if current ~= nil then
			self:_markFixed(Actions:ApplyFixes({ current }))
		end
	end)
	fixButton.AnchorPoint = Vector2.new(1, 0.5)
	fixButton.Position = UDim2.new(1, -6, 0.5, 0)

	local separator = Ui:Frame(row, UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 1, -1))
	Ui:Background(separator, StyleColor.Separator)

	self._janitor:Add(hit.Activated:Connect(function()
		if current == nil then
			return
		end

		if current.Node.Parent == nil then
			Status:Error(`{current.Node.Name} no longer exists. Run the scan again.`)
			return
		end

		local nodes = { current.Node }
		for _, related in current.Related do
			table.insert(nodes, related :: any)
		end
		Actions:SelectNodes(nodes :: any, true)
	end))

	return function(index: number)
		local issue = self._issues[index]
		current = issue

		local fixed = self._fixed[issue] == true
		local removed = issue.Node.Parent == nil
		Ui:Theme(
			marker,
			"TextColor3",
			if issue.Severity == "Error" then StyleColor.ErrorText else StyleColor.WarningText
		)
		marker.Text = if fixed then "✓" else "●"
		title.Text = if removed then `{issue.Node.Name} (removed)` else issue.Node.Name
		message.Text = issue.Message

		local fix = issue.Fix
		fixButton.Visible = fix ~= nil and not fixed and not removed
		fixButton.Text = if fix ~= nil then fix.Label else ""
	end
end

return ValidationPanel

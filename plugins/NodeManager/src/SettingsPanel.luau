--!strict
local Actions = require(script.Parent.Actions)
local Format = require(script.Parent.Format)
local Janitor = require(script.Parent.Parent.Packages.Janitor)
local NodeStore = require(script.Parent.NodeStore)
local Settings = require(script.Parent.Settings)
local Status = require(script.Parent.Status)
local Types = require(script.Parent.Types)
local Ui = require(script.Parent.Ui)

local StyleColor = Enum.StudioStyleGuideColor

type NumberField = {
	Key: Settings.NumberSetting,
	Label: string,
}

local NUMBER_FIELDS: { NumberField } = {
	{ Key = "FloatTolerance", Label = "Float tolerance" },
	{ Key = "GroundSearchDistance", Label = "Ground search" },
	{ Key = "SurfaceSearchHeight", Label = "Surface search" },
	{ Key = "DuplicateTolerance", Label = "Duplicate radius" },
}

type Controls = {
	BoundsMin: TextBox,
	BoundsMax: TextBox,
}

local SettingsPanel = {
	_janitor = Janitor.new(),
	_controls = nil :: Controls?,
	_shownBounds = "",
}

export type SettingsPanel = typeof(SettingsPanel)

function SettingsPanel.Init(self: SettingsPanel, parent: Frame)
	local scroller = Instance.new("ScrollingFrame")
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.CanvasSize = UDim2.new()
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.ScrollBarThickness = 8
	scroller.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	Ui:Theme(scroller, "ScrollBarImageColor3", StyleColor.ScrollBar)
	Ui:Padding(scroller, 6)
	Ui:ListLayout(scroller, Enum.FillDirection.Vertical, Ui.SPACING)
	scroller.Parent = parent
	self._janitor:Add(scroller)

	Ui:SectionHeader(scroller, "Validation (saved per user, in studs)")
	for _, field in NUMBER_FIELDS do
		local input: TextBox
		input = Ui:Input(
			Ui:Field(scroller, field.Label),
			UDim2.fromScale(1, 1),
			"",
			self._janitor,
			function(text: string)
				local value = tonumber(text)
				if value == nil or value <= 0 then
					Status:Error(`{field.Label} must be a positive number.`)
				else
					Settings:SetNumber(field.Key, value)
				end
				input.Text = tostring(Settings:GetNumber(field.Key))
			end
		)
		input.Text = tostring(Settings:GetNumber(field.Key))
	end

	Ui:SectionHeader(scroller, "World bounds (saved in this place)")
	local boundsMin = Ui:Input(Ui:Field(scroller, "Min"), UDim2.fromScale(1, 1), "x, y, z", self._janitor, function()
		self:_commitBounds()
	end)
	local boundsMax = Ui:Input(Ui:Field(scroller, "Max"), UDim2.fromScale(1, 1), "x, y, z", self._janitor, function()
		self:_commitBounds()
	end)

	local buttons = Ui:Frame(scroller, UDim2.new(1, 0, 0, Ui.ROW_HEIGHT))
	Ui:ListLayout(buttons, Enum.FillDirection.Horizontal, Ui.SPACING)
	Ui:Button(buttons, "Use selection", UDim2.new(0.5, -Ui.SPACING, 1, 0), self._janitor, function()
		Actions:SetBoundsFromSelection()
	end)
	Ui:Button(buttons, "Clear bounds", UDim2.new(0.5, 0, 1, 0), self._janitor, function()
		if NodeStore:GetBounds() == nil then
			return
		end

		NodeStore:Edit("Clear node world bounds", function()
			NodeStore:SetBounds(nil)
		end)
		Status:Info("World bounds cleared.")
	end)

	local hint = Ui:Label(
		scroller,
		"Nodes outside the bounds are reported during validation. Leave both empty to skip the check.",
		UDim2.new(1, 0, 0, 0),
		StyleColor.DimmedText
	)
	hint.AutomaticSize = Enum.AutomaticSize.Y
	hint.TextWrapped = true

	self._controls = {
		BoundsMin = boundsMin,
		BoundsMax = boundsMax,
	}

	self._janitor:Add(NodeStore.Changed:Connect(function()
		self:_refreshBounds()
	end))
	self:_refreshBounds()
end

function SettingsPanel.Destroy(self: SettingsPanel)
	self._janitor:Cleanup()
	self._controls = nil
end

--[=[
	@priv
]=]
function SettingsPanel._refreshBounds(self: SettingsPanel)
	local controls = self._controls
	if controls == nil or controls.BoundsMin:IsFocused() or controls.BoundsMax:IsFocused() then
		return
	end

	local bounds = NodeStore:GetBounds()
	controls.BoundsMin.Text = if bounds ~= nil then Format:Vector3(bounds.Min) else ""
	controls.BoundsMax.Text = if bounds ~= nil then Format:Vector3(bounds.Max) else ""
	self._shownBounds = `{controls.BoundsMin.Text}|{controls.BoundsMax.Text}`
end

--[=[
	@priv
	Saves the bounds once both corners are valid; a half-filled pair is left for the user to finish.
]=]
function SettingsPanel._commitBounds(self: SettingsPanel)
	local controls = self._controls
	if controls == nil then
		return
	end

	-- Focus loss without an edit would otherwise re-save the rounded values shown in the inputs.
	if `{controls.BoundsMin.Text}|{controls.BoundsMax.Text}` == self._shownBounds then
		return
	end

	local minText, maxText = Format:Trim(controls.BoundsMin.Text), Format:Trim(controls.BoundsMax.Text)
	if minText == "" or maxText == "" then
		return
	end

	local min, max = Format:ParseVector3(minText), Format:ParseVector3(maxText)
	if min == nil or max == nil then
		Status:Error("Enter bounds as three numbers separated by commas, such as -500, -50, -500.")
		return
	end

	local bounds: Types.Bounds = { Min = min:Min(max), Max = min:Max(max) }
	NodeStore:Edit("Set node world bounds", function()
		NodeStore:SetBounds(bounds)
	end)
	Status:Info("World bounds saved.")
end

return SettingsPanel

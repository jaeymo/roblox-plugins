--!strict
local EditorPanel = require(script.Parent.EditorPanel)
local Janitor = require(script.Parent.Parent.Packages.Janitor)
local NodeStore = require(script.Parent.NodeStore)
local NodesPanel = require(script.Parent.NodesPanel)
local Settings = require(script.Parent.Settings)
local SettingsPanel = require(script.Parent.SettingsPanel)
local Status = require(script.Parent.Status)
local TypesPanel = require(script.Parent.TypesPanel)
local Ui = require(script.Parent.Ui)
local ValidationPanel = require(script.Parent.ValidationPanel)

local StyleColor = Enum.StudioStyleGuideColor

local TAB_HEIGHT = 28
local STATUS_HEIGHT = 22
local LIST_SHARE = 0.5

type Tab = {
	Button: TextButton,
	Frame: Frame,
}

local App = {
	_janitor = Janitor.new(),
	_tabs = {} :: { Tab },
}

export type App = typeof(App)

function App.Init(self: App, plugin: Plugin, widget: DockWidgetPluginGui)
	Settings:Init(plugin)
	NodeStore:Start()
	Ui:Init(widget)

	local root = Ui:Frame(widget, UDim2.fromScale(1, 1))
	Ui:Background(root, StyleColor.MainBackground)
	self._janitor:Add(root)

	local tabBar = Ui:Frame(root, UDim2.new(1, 0, 0, TAB_HEIGHT))
	Ui:Background(tabBar, StyleColor.Titlebar)
	Ui:ListLayout(tabBar, Enum.FillDirection.Horizontal, 0)

	local content = Ui:Frame(root, UDim2.new(1, 0, 1, -(TAB_HEIGHT + STATUS_HEIGHT)), UDim2.fromOffset(0, TAB_HEIGHT))

	local statusBar = Ui:Frame(root, UDim2.new(1, 0, 0, STATUS_HEIGHT), UDim2.new(0, 0, 1, -STATUS_HEIGHT))
	Ui:Background(statusBar, StyleColor.Titlebar)
	local statusLabel = Ui:Label(statusBar, "Ready.", UDim2.new(1, -12, 1, 0), StyleColor.DimmedText)
	statusLabel.Position = UDim2.fromOffset(6, 0)

	local nodesFrame = self:_addTab(tabBar, content, "Nodes")
	local typesFrame = self:_addTab(tabBar, content, "Types")
	local validateFrame = self:_addTab(tabBar, content, "Validate")
	local settingsFrame = self:_addTab(tabBar, content, "Settings")

	local listArea = Ui:Frame(nodesFrame, UDim2.fromScale(1, LIST_SHARE))
	local editorArea = Ui:Frame(nodesFrame, UDim2.fromScale(1, 1 - LIST_SHARE), UDim2.fromScale(0, LIST_SHARE))
	local divider = Ui:Frame(editorArea, UDim2.new(1, 0, 0, 1))
	Ui:Background(divider, StyleColor.Border)

	NodesPanel:Init(listArea)
	EditorPanel:Init(editorArea)
	TypesPanel:Init(typesFrame)
	ValidationPanel:Init(validateFrame)
	SettingsPanel:Init(settingsFrame)

	self._janitor:Add(Status.Changed:Connect(function(message: string, isError: boolean)
		statusLabel.Text = message
		Ui:Theme(statusLabel, "TextColor3", if isError then StyleColor.ErrorText else StyleColor.DimmedText)
	end))

	self:_selectTab(1)
end

function App.Destroy(self: App)
	NodesPanel:Destroy()
	EditorPanel:Destroy()
	TypesPanel:Destroy()
	ValidationPanel:Destroy()
	SettingsPanel:Destroy()
	self._janitor:Cleanup()
	table.clear(self._tabs)
	Ui:Destroy()
	NodeStore:Stop()
end

--[=[
	@priv
]=]
function App._addTab(self: App, tabBar: Frame, content: Frame, name: string): Frame
	local index = #self._tabs + 1
	local button = Ui:Button(tabBar, name, UDim2.new(0.25, 0, 1, 0), self._janitor, function()
		self:_selectTab(index)
	end)
	button.BorderSizePixel = 0

	local frame = Ui:Frame(content, UDim2.fromScale(1, 1))
	frame.Visible = false

	table.insert(self._tabs, { Button = button, Frame = frame })
	return frame
end

--[=[
	@priv
]=]
function App._selectTab(self: App, selected: number)
	Ui:CloseOverlay()
	for index, tab in self._tabs do
		local active = index == selected
		tab.Frame.Visible = active
		Ui:Theme(tab.Button, "BackgroundColor3", if active then StyleColor.MainBackground else StyleColor.Titlebar)
		Ui:Theme(tab.Button, "TextColor3", if active then StyleColor.MainText else StyleColor.DimmedText)
	end
end

return App

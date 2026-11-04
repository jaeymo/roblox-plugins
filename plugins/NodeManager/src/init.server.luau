--!strict
local App = require(script.App)

local WIDGET_ID = "NodeManager"
local ICON = "rbxasset://textures/ui/GuiImagePlaceholder.png"

local toolbar = plugin:CreateToolbar("NodeManager")
local button = toolbar:CreateButton("NodeManager", "Create, organize and validate world nodes", ICON)
button.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGuiAsync(
	WIDGET_ID,
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 360, 600, 300, 420)
)
widget.Name = WIDGET_ID
widget.Title = "NodeManager"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local started = false

local function syncWidget()
	button:SetActive(widget.Enabled)
	if widget.Enabled and not started then
		started = true
		App:Init(plugin, widget)
	end
end

button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(syncWidget)

plugin.Unloading:Connect(function()
	if started then
		App:Destroy()
	end
end)

syncWidget()

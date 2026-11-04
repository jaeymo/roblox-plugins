--!strict
-- ExamplePlugin entry point. `plugin` is injected by Studio for plugin scripts.
-- Other ModuleScripts in src/ become children of this Script (require via script.ModuleName).

local toolbar = plugin:CreateToolbar("Example Plugin")
local button = toolbar:CreateButton("Hello", "Say hello", "rbxasset://textures/ui/GuiImagePlaceholder.png")
button.ClickableWhenViewportHidden = true

button.Click:Connect(function()
	print("Hello from ExamplePlugin!")
	button:SetActive(false)
end)

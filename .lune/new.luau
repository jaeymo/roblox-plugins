local fs = require("@lune/fs")
local process = require("@lune/process")
local util = require("./util")

local PROJECT_TEMPLATE = [[
{
	"name": "{{NAME}}",
	"tree": {
		"$className": "Folder",
		"Main": {
			"$path": "src"
		},
		"Packages": {
			"$path": "../../Packages"
		}
	}
}
]]

local MAIN_TEMPLATE = [[
--!strict
-- {{NAME}} entry point. `plugin` is injected by Studio for plugin scripts.
-- Other ModuleScripts in src/ become children of this Script (require via script.ModuleName).

local toolbar = plugin:CreateToolbar("{{NAME}}")
local button = toolbar:CreateButton("{{NAME}}", "Open {{NAME}}", "rbxasset://textures/ui/GuiImagePlaceholder.png")
button.ClickableWhenViewportHidden = true

button.Click:Connect(function()
	print("Hello from {{NAME}}!")
	button:SetActive(false)
end)
]]

local name = process.args[1]
if not name or not string.match(name, "^[%a_][%w_%-]*$") then
	print("Usage: lune run new <PluginName>")
	process.exit(1)
end

local dir = `{util.PLUGINS_DIR}/{name}`
if fs.isDir(dir) then
	print(`{dir} already exists.`)
	process.exit(1)
end

local function fill(template: string): string
	return (string.gsub(template, "{{NAME}}", name))
end

fs.writeDir(`{dir}/src`)
fs.writeFile(`{dir}/default.project.json`, fill(PROJECT_TEMPLATE))
fs.writeFile(`{dir}/src/init.server.luau`, fill(MAIN_TEMPLATE))

print(`Created {dir}. Build it with: lune run build {name}`)

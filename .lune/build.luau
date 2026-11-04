local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")
local util = require("./util")

local watch = false
local names = {}
for _, arg in process.args do
	if arg == "--watch" or arg == "-w" then
		watch = true
	else
		table.insert(names, arg)
	end
end

if #names == 0 then
	names = util.listPlugins()
end
if #names == 0 then
	print("No plugins found in plugins/.")
	process.exit(1)
end

for _, name in names do
	if not fs.isFile(`{util.PLUGINS_DIR}/{name}/default.project.json`) then
		print(`Unknown plugin '{name}' (no {util.PLUGINS_DIR}/{name}/default.project.json)`)
		process.exit(1)
	end
end

util.ensurePackages()

local function build(name: string)
	local args = { "build", `{util.PLUGINS_DIR}/{name}`, "--plugin", `{name}.rbxm` }
	if watch then
		table.insert(args, "--watch")
	end
	util.run("rojo", args)
end

if watch then
	for _, name in names do
		task.spawn(build, name)
	end
else
	for _, name in names do
		build(name)
	end
	print(`Built {#names} plugin(s) into Studio's plugins folder. Restart Studio or reload plugins to pick them up.`)
end

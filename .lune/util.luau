local fs = require("@lune/fs")
local process = require("@lune/process")

local util = {}

util.PLUGINS_DIR = "plugins"

function util.run(program: string, args: { string })
	print(`> {program} {table.concat(args, " ")}`)
	local result = process.exec(program, args, { stdio = "forward" })
	if not result.ok then
		print(`'{program}' failed with exit code {result.code}`)
		process.exit(result.code)
	end
end

function util.ensurePackages()
	if not fs.isDir("Packages") then
		fs.writeDir("Packages")
	end
end

function util.listPlugins(): { string }
	local names = {}
	if not fs.isDir(util.PLUGINS_DIR) then
		return names
	end
	for _, name in fs.readDir(util.PLUGINS_DIR) do
		if fs.isFile(`{util.PLUGINS_DIR}/{name}/default.project.json`) then
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

return util

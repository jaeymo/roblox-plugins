local util = require("./util")

util.run("wally", { "install" })
util.ensurePackages()
util.run("rojo", { "sourcemap", "default.project.json", "--output", "sourcemap.json" })
util.run("wally-package-types", { "--sourcemap", "sourcemap.json", "Packages/" })

print("Packages installed.")

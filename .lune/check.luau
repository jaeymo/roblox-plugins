local util = require("./util")

util.run("selene", { "plugins", ".lune" })
util.run("stylua", { "--check", "plugins", ".lune" })

print("All checks passed.")

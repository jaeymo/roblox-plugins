--!strict
local Constants = require(script.Parent.Constants)
local Signal = require(script.Parent.Parent.Packages.Signal)

local Status = {
	Changed = Signal.new() :: Signal.Signal<string, boolean>,
}

export type Status = typeof(Status)

function Status.Info(self: Status, message: string)
	self.Changed:Fire(message, false)
end

function Status.Error(self: Status, message: string)
	warn(`[{Constants.PLUGIN_NAME}] {message}`)
	self.Changed:Fire(message, true)
end

return Status

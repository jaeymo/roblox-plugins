--!strict
export type NumberSetting = "FloatTolerance" | "GroundSearchDistance" | "DuplicateTolerance" | "SurfaceSearchHeight"
export type StringSetting = "LastType"

local NUMBER_DEFAULTS: { [NumberSetting]: number } = {
	FloatTolerance = 1,
	GroundSearchDistance = 500,
	DuplicateTolerance = 0.5,
	SurfaceSearchHeight = 200,
}

local STRING_DEFAULTS: { [StringSetting]: string } = {
	LastType = "",
}

local Settings = {
	_plugin = nil :: Plugin?,
}

export type Settings = typeof(Settings)

function Settings.Init(self: Settings, plugin: Plugin)
	self._plugin = plugin
end

function Settings.GetNumber(self: Settings, key: NumberSetting): number
	local value = self:_getPlugin():GetSetting(key)
	-- Rejects NaN as well as non-numbers left behind by older or hand-edited settings.
	if typeof(value) == "number" and value == value and value > 0 then
		return value
	end

	return NUMBER_DEFAULTS[key]
end

function Settings.SetNumber(self: Settings, key: NumberSetting, value: number)
	self:_getPlugin():SetSetting(key, value)
end

function Settings.GetString(self: Settings, key: StringSetting): string
	local value = self:_getPlugin():GetSetting(key)
	if typeof(value) == "string" then
		return value
	end

	return STRING_DEFAULTS[key]
end

function Settings.SetString(self: Settings, key: StringSetting, value: string)
	self:_getPlugin():SetSetting(key, value)
end

--[=[
	@priv
]=]
function Settings._getPlugin(self: Settings): Plugin
	return assert(self._plugin, "Settings:Init must be called before reading settings")
end

return Settings

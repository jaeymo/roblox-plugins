--!strict
local NUMBER_PATTERN = "%s*(-?%d*%.?%d+)%s*"

local Format = {}

export type Format = typeof(Format)

function Format.Trim(self: Format, text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

function Format.Number(self: Format, value: number): string
	return string.format("%.1f", value)
end

function Format.Vector3(self: Format, value: Vector3): string
	return `{self:Number(value.X)}, {self:Number(value.Y)}, {self:Number(value.Z)}`
end

function Format.ParseVector3(self: Format, text: string): Vector3?
	local x, y, z = string.match(text, `^{NUMBER_PATTERN},{NUMBER_PATTERN},{NUMBER_PATTERN}$`)
	local numberX, numberY, numberZ = tonumber(x), tonumber(y), tonumber(z)
	if numberX == nil or numberY == nil or numberZ == nil then
		return nil
	end

	return Vector3.new(numberX, numberY, numberZ)
end

function Format.Color(self: Format, color: Color3): string
	return `{math.round(color.R * 255)}, {math.round(color.G * 255)}, {math.round(color.B * 255)}`
end

function Format.ParseColor(self: Format, text: string): Color3?
	local trimmed = self:Trim(text)
	local hex = string.match(trimmed, "^#?(%x%x%x%x%x%x)$")
	if hex ~= nil then
		return Color3.fromHex(hex)
	end

	local r, g, b = string.match(trimmed, "^(%d+)%s*,%s*(%d+)%s*,%s*(%d+)$")
	local red, green, blue = tonumber(r), tonumber(g), tonumber(b)
	if red == nil or green == nil or blue == nil or red > 255 or green > 255 or blue > 255 then
		return nil
	end

	return Color3.fromRGB(red, green, blue)
end

return Format

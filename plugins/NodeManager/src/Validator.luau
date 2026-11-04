--!strict
local Constants = require(script.Parent.Constants)
local Format = require(script.Parent.Format)
local NodeAppearance = require(script.Parent.NodeAppearance)
local NodeTypes = require(script.Parent.NodeTypes)
local Promise = require(script.Parent.Parent.Packages.Promise)
local Spatial = require(script.Parent.Spatial)
local Types = require(script.Parent.Types)

local BATCH_SIZE = 200

local Validator = {}

export type Validator = typeof(Validator)

function Validator.Scan(
	self: Validator,
	nodes: { Part },
	root: Folder,
	bounds: Types.Bounds?,
	options: Types.ScanOptions,
	onProgress: (checked: number, total: number) -> ()
): Promise.TypedPromise<{ Types.Issue }>
	return Promise.new(function(resolve: ({ Types.Issue }) -> (), _reject, onCancel)
		local cancelled = false
		onCancel(function()
			cancelled = true
		end)

		Spatial:SetExcluded({ root })
		local types = NodeTypes:GetMap()
		local issues: { Types.Issue } = {}

		for index, node in nodes do
			if node.Parent ~= nil then
				self:_checkNode(node, types, bounds, options, issues)
			end

			if index % BATCH_SIZE == 0 then
				onProgress(index, #nodes)
				task.wait()
				if cancelled then
					return
				end
				Spatial:SetExcluded({ root })
			end
		end

		self:_checkDuplicates(nodes, options.DuplicateTolerance, issues)
		resolve(issues)
	end)
end

--[=[
	@priv
]=]
function Validator._checkNode(
	self: Validator,
	node: Part,
	types: { [string]: Types.NodeType },
	bounds: Types.Bounds?,
	options: Types.ScanOptions,
	issues: { Types.Issue }
)
	local typeName = NodeAppearance:GetType(node)
	local nodeType = if typeName ~= nil then types[typeName] else nil

	self:_checkMetadata(node, typeName, nodeType, issues)
	if bounds ~= nil then
		self:_checkBounds(node, bounds, issues)
	end

	local buried = self:_checkTerrain(node, options, issues)
	local embedded = self:_checkParts(node, issues)

	local grounded = if nodeType ~= nil then nodeType.Grounded else true
	if grounded and not buried and not embedded then
		self:_checkFloating(node, options, issues)
	end
end

--[=[
	@priv
]=]
function Validator._checkMetadata(
	self: Validator,
	node: Part,
	typeName: string?,
	nodeType: Types.NodeType?,
	issues: { Types.Issue }
)
	if typeName == nil then
		return
	end

	if nodeType == nil then
		self:_addIssue(issues, node, "Metadata", "Warning", `Unknown node type '{typeName}'`, {
			Label = "Clear type",
			Apply = function(target: Part): (boolean, string?)
				target:SetAttribute(Constants.ATTRIBUTES.TYPE, nil)
				NodeAppearance:Refresh(target)
				return true, nil
			end,
		})
		return
	end

	local missing = {}
	for _, field in nodeType.Fields do
		if field.Required and NodeTypes:IsEmpty(node:GetAttribute(field.Name)) then
			table.insert(missing, field.Name)
		end
	end

	if #missing > 0 then
		self:_addIssue(issues, node, "Metadata", "Error", `Missing required metadata: {table.concat(missing, ", ")}`)
	end
end

--[=[
	@priv
]=]
function Validator._checkBounds(self: Validator, node: Part, bounds: Types.Bounds, issues: { Types.Issue })
	local position = node.Position
	if position:Min(bounds.Max):Max(bounds.Min) == position then
		return
	end

	self:_addIssue(issues, node, "OutOfBounds", "Error", `Outside the world bounds at {Format:Vector3(position)}`, {
		Label = "Move inside",
		Apply = function(target: Part): (boolean, string?)
			local clamped = target.Position:Min(bounds.Max):Max(bounds.Min)
			target.CFrame = target.CFrame.Rotation + clamped
			return true, nil
		end,
	})
end

--[=[
	@priv
]=]
function Validator._checkTerrain(
	self: Validator,
	node: Part,
	options: Types.ScanOptions,
	issues: { Types.Issue }
): boolean
	local material = Spatial:GetBuriedMaterial(node.Position)
	if material == nil then
		return false
	end

	self:_addIssue(issues, node, "Buried", "Error", `Buried in terrain ({material.Name})`, {
		Label = "Raise to surface",
		Apply = function(target: Part): (boolean, string?)
			local surface = Spatial:FindSurfaceAbove(target.Position, options.SurfaceSearchHeight)
			if surface == nil then
				return false, `no open terrain within {options.SurfaceSearchHeight} studs above`
			end

			target.CFrame = target.CFrame.Rotation + Spatial:GetRestingPosition(surface, target.Size)
			return true, nil
		end,
	})
	return true
end

--[=[
	@priv
]=]
function Validator._checkParts(self: Validator, node: Part, issues: { Types.Issue }): boolean
	local parts = Spatial:GetIntersectingParts(node)
	if #parts == 0 then
		return false
	end

	local others = if #parts > 1 then ` and {#parts - 1} other part(s)` else ""
	self:_addIssue(issues, node, "Embedded", "Error", `Inside solid part '{parts[1]:GetFullName()}'{others}`)
	return true
end

--[=[
	@priv
]=]
function Validator._checkFloating(self: Validator, node: Part, options: Types.ScanOptions, issues: { Types.Issue })
	local result = Spatial:FindGround(node.Position, options.GroundSearchDistance)
	if result == nil then
		self:_addIssue(
			issues,
			node,
			"NoGround",
			"Warning",
			`No ground within {options.GroundSearchDistance} studs below`
		)
		return
	end

	local gap = (node.Position.Y - node.Size.Y / 2) - result.Position.Y
	if gap <= options.FloatTolerance then
		return
	end

	self:_addIssue(
		issues,
		node,
		"Floating",
		"Warning",
		`Floating {Format:Number(gap)} studs above {result.Instance.Name}`,
		{
			Label = "Snap to ground",
			Apply = function(target: Part): (boolean, string?)
				local position =
					Spatial:GetGroundedPosition(target, options.GroundSearchDistance, options.SurfaceSearchHeight)
				if position == nil then
					return false, "no ground found below"
				end

				target.CFrame = target.CFrame.Rotation + position
				return true, nil
			end,
		}
	)
end

--[=[
	@priv 
]=]
function Validator._checkDuplicates(self: Validator, nodes: { Part }, tolerance: number, issues: { Types.Issue })
	local cells: { [string]: { Part } } = {}

	for _, node in nodes do
		if node.Parent == nil then
			continue
		end

		local position = node.Position
		local cellX = math.floor(position.X / tolerance)
		local cellY = math.floor(position.Y / tolerance)
		local cellZ = math.floor(position.Z / tolerance)

		for offsetX = -1, 1 do
			for offsetY = -1, 1 do
				for offsetZ = -1, 1 do
					local bucket = cells[`{cellX + offsetX},{cellY + offsetY},{cellZ + offsetZ}`]
					if bucket == nil then
						continue
					end

					for _, other in bucket do
						local distance = (other.Position - position).Magnitude
						if distance <= tolerance then
							self:_addIssue(
								issues,
								node,
								"Duplicate",
								"Warning",
								`Overlaps '{other.Name}' ({Format:Number(distance)} studs apart)`,
								nil,
								{ other }
							)
						end
					end
				end
			end
		end

		local key = `{cellX},{cellY},{cellZ}`
		local bucket = cells[key]
		if bucket == nil then
			bucket = {}
			cells[key] = bucket
		end
		table.insert(bucket, node)
	end
end

--[=[
	@priv
]=]
function Validator._addIssue(
	self: Validator,
	issues: { Types.Issue },
	node: Part,
	kind: Types.IssueKind,
	severity: Types.Severity,
	message: string,
	fix: Types.Fix?,
	related: { Part }?
)
	table.insert(issues :: any, {
		Kind = kind,
		Severity = severity,
		Node = node,
		Message = message,
		Related = related or {},
		Fix = fix,
	})
end

return Validator

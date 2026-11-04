--!strict
local Workspace = game:GetService("Workspace")

local Constants = require(script.Parent.Constants)

local RESOLUTION = Constants.TERRAIN_RESOLUTION
local SOLID_OCCUPANCY = 0.5

type VoxelGrid<T> = { { { T } } }

local Spatial = {
	_raycastParams = RaycastParams.new(),
	_terrainParams = RaycastParams.new(),
	_overlapParams = OverlapParams.new(),
}

export type Spatial = typeof(Spatial)

function Spatial.SetExcluded(self: Spatial, excluded: { Instance })
	local raycastParams = self._raycastParams
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = excluded
	raycastParams.RespectCanCollide = true
	raycastParams.IgnoreWater = true

	local overlapParams = self._overlapParams
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = excluded
	overlapParams.RespectCanCollide = true

	local terrainParams = self._terrainParams
	terrainParams.FilterType = Enum.RaycastFilterType.Include
	terrainParams.FilterDescendantsInstances = { Workspace.Terrain }
	terrainParams.IgnoreWater = true
end

function Spatial.Raycast(self: Spatial, origin: Vector3, direction: Vector3): RaycastResult?
	return Workspace:Raycast(origin, direction, self._raycastParams)
end

function Spatial.FindGround(self: Spatial, origin: Vector3, maxDistance: number): RaycastResult?
	return self:Raycast(origin, Vector3.new(0, -maxDistance, 0))
end

function Spatial.GetRestingPosition(self: Spatial, surface: Vector3, size: Vector3): Vector3
	return surface + Vector3.new(0, size.Y / 2 + Constants.SURFACE_GAP, 0)
end

--[=[
	Returns where the node should sit to rest on the ground. Nodes buried in terrain are raised to the
	terrain surface above them, because a downward ray cast from inside terrain cannot find that surface.
]=]
function Spatial.GetGroundedPosition(
	self: Spatial,
	node: BasePart,
	searchDistance: number,
	surfaceSearchHeight: number
): Vector3?
	if self:GetBuriedMaterial(node.Position) ~= nil then
		local surface = self:FindSurfaceAbove(node.Position, surfaceSearchHeight)
		return if surface ~= nil then self:GetRestingPosition(surface, node.Size) else nil
	end

	local result = self:FindGround(node.Position, searchDistance)
	return if result ~= nil then self:GetRestingPosition(result.Position, node.Size) else nil
end

function Spatial.GetBuriedMaterial(self: Spatial, position: Vector3): Enum.Material?
	local cellMin = self:_alignToGrid(position)
	local materials, occupancies = self:_readColumn(cellMin, 2)

	local material = materials[1][1][1]
	if not self:_isSolid(material, occupancies[1][1][1], 0) then
		return nil
	end

	if self:_isSolid(materials[1][2][1], occupancies[1][2][1], SOLID_OCCUPANCY) then
		return material
	end

	-- The terrain surface passes through this cell, so compare its real height with the node's centre.
	local top = cellMin.Y + RESOLUTION * 2
	local result = Workspace:Raycast(
		Vector3.new(position.X, top, position.Z),
		Vector3.new(0, position.Y - top, 0),
		self._terrainParams
	)
	if result ~= nil and result.Position.Y > position.Y then
		return material
	end

	return nil
end

function Spatial.FindSurfaceAbove(self: Spatial, position: Vector3, maxHeight: number): Vector3?
	local cellCount = math.max(1, math.ceil(maxHeight / RESOLUTION))
	local cellMin = self:_alignToGrid(position)
	local materials, occupancies = self:_readColumn(cellMin, cellCount)

	for index = 1, cellCount do
		if not self:_isSolid(materials[1][index][1], occupancies[1][index][1], SOLID_OCCUPANCY) then
			-- The surface lies inside this open cell or on top of the solid cell beneath it.
			local openTop = cellMin.Y + index * RESOLUTION
			local result = Workspace:Raycast(
				Vector3.new(position.X, openTop, position.Z),
				Vector3.new(0, -RESOLUTION * 2, 0),
				self._terrainParams
			)
			if result ~= nil then
				return result.Position
			end

			return Vector3.new(position.X, openTop - RESOLUTION, position.Z)
		end
	end

	return nil
end

function Spatial.GetIntersectingParts(self: Spatial, part: BasePart): { BasePart }
	local intersecting = {}
	for _, other in Workspace:GetPartsInPart(part, self._overlapParams) do
		if other ~= Workspace.Terrain then
			table.insert(intersecting, other)
		end
	end

	return intersecting
end

--[=[
	@priv
]=]
function Spatial._alignToGrid(self: Spatial, position: Vector3): Vector3
	return Vector3.new(
		math.floor(position.X / RESOLUTION) * RESOLUTION,
		math.floor(position.Y / RESOLUTION) * RESOLUTION,
		math.floor(position.Z / RESOLUTION) * RESOLUTION
	)
end

--[=[
	@priv
]=]
function Spatial._readColumn(
	self: Spatial,
	cellMin: Vector3,
	cellCount: number
): (VoxelGrid<Enum.Material>, VoxelGrid<number>)
	local region = Region3.new(cellMin, cellMin + Vector3.new(RESOLUTION, RESOLUTION * cellCount, RESOLUTION))
	local materials, occupancies = Workspace.Terrain:ReadVoxels(region, RESOLUTION)
	return materials, occupancies
end

--[=[
	@priv
]=]
function Spatial._isSolid(self: Spatial, material: Enum.Material, occupancy: number, threshold: number): boolean
	return material ~= Enum.Material.Air and material ~= Enum.Material.Water and occupancy > threshold
end

return Spatial

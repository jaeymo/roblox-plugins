--!strict
local PhysicsService = game:GetService("PhysicsService")

local Constants = require(script.Parent.Constants)
local Format = require(script.Parent.Format)
local Types = require(script.Parent.Types)

local ATTRIBUTES = Constants.ATTRIBUTES
local LABEL_WIDTH = 160
local ICON_SIZE = 28
local TITLE_HEIGHT = 18
local LABEL_LIFT = 1.5

local NodeAppearance = {}

export type NodeAppearance = typeof(NodeAppearance)

function NodeAppearance.GetStringAttribute(self: NodeAppearance, instance: Instance, attribute: string): string
	local value = instance:GetAttribute(attribute)
	return if typeof(value) == "string" then value else ""
end

function NodeAppearance.GetType(self: NodeAppearance, node: Instance): string?
	local value = self:GetStringAttribute(node, ATTRIBUTES.TYPE)
	return if value ~= "" then value else nil
end

function NodeAppearance.GetDisplayName(self: NodeAppearance, node: Instance): string
	return self:GetStringAttribute(node, ATTRIBUTES.DISPLAY_NAME)
end

function NodeAppearance.GetImage(self: NodeAppearance, node: Instance): string
	return self:GetStringAttribute(node, ATTRIBUTES.IMAGE)
end

function NodeAppearance.IsHidden(self: NodeAppearance, node: Instance): boolean
	return node:GetAttribute(ATTRIBUTES.HIDDEN) == true
end

function NodeAppearance.ConfigurePhysics(self: NodeAppearance, node: Part)
	node.Anchored = true
	node.CanCollide = false
	node.CanTouch = false
	node.CanQuery = true
	node.CastShadow = false
	node.Massless = true
	node.Material = Enum.Material.SmoothPlastic
	node.TopSurface = Enum.SurfaceType.Smooth
	node.BottomSurface = Enum.SurfaceType.Smooth

	-- The collision group doesn't collide with Default, so default raycasts and overlap queries skip nodes.
	if PhysicsService:IsCollisionGroupRegistered(Constants.COLLISION_GROUP) then
		node.CollisionGroup = Constants.COLLISION_GROUP
	end
end

function NodeAppearance.ApplyAppearance(self: NodeAppearance, node: Part, appearance: Types.Appearance)
	node:SetAttribute(ATTRIBUTES.IMAGE, if appearance.Image ~= "" then appearance.Image else nil)
	node.Color = appearance.Color
	node.Shape = appearance.Shape
	node.Size = Vector3.one * math.clamp(appearance.Size, Constants.MIN_NODE_SIZE, Constants.MAX_NODE_SIZE)
	self:Refresh(node)
end

function NodeAppearance.SetSize(self: NodeAppearance, node: Part, size: number)
	node.Size = Vector3.one * math.clamp(size, Constants.MIN_NODE_SIZE, Constants.MAX_NODE_SIZE)
	self:Refresh(node)
end

function NodeAppearance.SetDisplayName(self: NodeAppearance, node: Part, displayName: string)
	local trimmed = Format:Trim(displayName)
	node:SetAttribute(ATTRIBUTES.DISPLAY_NAME, if trimmed ~= "" then trimmed else nil)
	self:Refresh(node)
end

function NodeAppearance.SetImage(self: NodeAppearance, node: Part, image: string)
	local normalized = self:NormalizeImage(image)
	node:SetAttribute(ATTRIBUTES.IMAGE, if normalized ~= "" then normalized else nil)
	self:Refresh(node)
end

function NodeAppearance.SetHidden(self: NodeAppearance, node: Part, hidden: boolean)
	node:SetAttribute(ATTRIBUTES.HIDDEN, if hidden then true else nil)
	self:Refresh(node)
end

function NodeAppearance.NormalizeImage(self: NodeAppearance, image: string): string
	local trimmed = Format:Trim(image)
	if string.match(trimmed, "^%d+$") ~= nil then
		return `rbxassetid://{trimmed}`
	end

	return trimmed
end

function NodeAppearance.Refresh(self: NodeAppearance, node: Part)
	local hidden = self:IsHidden(node)
	node.Transparency = if hidden then 1 else Constants.VISIBLE_TRANSPARENCY

	local label, icon, title = self:_getLabel(node)
	label.Enabled = not hidden
	label.StudsOffsetWorldSpace = Vector3.new(0, node.Size.Y / 2 + LABEL_LIFT, 0)

	local displayName = self:GetDisplayName(node)
	title.Text = if displayName ~= "" then displayName else self:GetType(node) or node.Name

	local image = self:GetImage(node)
	icon.Image = image
	icon.Visible = image ~= ""
end

--[=[
	@priv
]=]
function NodeAppearance._getLabel(self: NodeAppearance, node: Part): (BillboardGui, ImageLabel, TextLabel)
	local existing = node:FindFirstChild(Constants.LABEL_NAME)
	if existing ~= nil and existing:IsA("BillboardGui") then
		local icon = existing:FindFirstChild("Icon")
		local title = existing:FindFirstChild("Title")
		if icon ~= nil and icon:IsA("ImageLabel") and title ~= nil and title:IsA("TextLabel") then
			return existing, icon, title
		end
	end

	if existing ~= nil then
		existing:Destroy()
	end

	local label = Instance.new("BillboardGui")
	label.Name = Constants.LABEL_NAME
	label.Size = UDim2.fromOffset(LABEL_WIDTH, ICON_SIZE + TITLE_HEIGHT)
	label.LightInfluence = 0
	label.MaxDistance = Constants.LABEL_MAX_DISTANCE
	label.ResetOnSpawn = false

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = label

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.LayoutOrder = 1
	icon.Parent = label

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, TITLE_HEIGHT)
	title.Font = Enum.Font.BuilderSansBold
	title.TextSize = 14
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.3
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.LayoutOrder = 2
	title.Parent = label

	label.Parent = node
	return label, icon, title
end

return NodeAppearance

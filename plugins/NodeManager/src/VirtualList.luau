--!strict
local Janitor = require(script.Parent.Parent.Packages.Janitor)
local Ui = require(script.Parent.Ui)

export type RowBinder = (index: number) -> ()

type Row = {
	Frame: Frame,
	Bind: RowBinder,
}

type Fields = {
	Frame: ScrollingFrame,
	_janitor: Janitor.Janitor,
	_rowHeight: number,
	_count: number,
	_createRow: (row: Frame) -> RowBinder,
	_rows: { Row },
}

local VirtualList = {}
VirtualList.__index = VirtualList

export type VirtualList = typeof(setmetatable({} :: Fields, VirtualList))

function VirtualList.new(
	parent: Instance,
	size: UDim2,
	position: UDim2,
	rowHeight: number,
	createRow: (row: Frame) -> RowBinder
): VirtualList
	local janitor = Janitor.new()

	local frame = Instance.new("ScrollingFrame")
	frame.Size = size
	frame.Position = position
	frame.BorderSizePixel = 0
	frame.CanvasSize = UDim2.new()
	frame.ScrollingDirection = Enum.ScrollingDirection.Y
	frame.ScrollBarThickness = 8
	frame.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	Ui:Theme(frame, "BackgroundColor3", Enum.StudioStyleGuideColor.MainBackground)
	Ui:Theme(frame, "ScrollBarImageColor3", Enum.StudioStyleGuideColor.ScrollBar)
	janitor:Add(frame)

	local self = setmetatable(
		{
			Frame = frame,
			_janitor = janitor,
			_rowHeight = rowHeight,
			_count = 0,
			_createRow = createRow,
			_rows = {},
		} :: Fields,
		VirtualList
	)

	janitor:Add(frame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:Render()
	end))
	janitor:Add(frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:Render()
	end))

	frame.Parent = parent
	return self
end

function VirtualList.SetCount(self: VirtualList, count: number)
	self._count = count
	self.Frame.CanvasSize = UDim2.fromOffset(0, count * self._rowHeight)
	self:Render()
end

function VirtualList.Render(self: VirtualList)
	local frame = self.Frame
	local rowHeight = self._rowHeight
	local first = math.floor(frame.CanvasPosition.Y / rowHeight) + 1
	local visibleCount = math.ceil(frame.AbsoluteSize.Y / rowHeight) + 1

	while #self._rows < visibleCount do
		local rowFrame = Instance.new("Frame")
		rowFrame.BackgroundTransparency = 1
		rowFrame.BorderSizePixel = 0
		rowFrame.Size = UDim2.new(1, 0, 0, rowHeight)
		rowFrame.Visible = false
		rowFrame.Parent = frame
		table.insert(self._rows, { Frame = rowFrame, Bind = self._createRow(rowFrame) })
	end

	for slot, row in self._rows do
		local index = first + slot - 1
		if slot <= visibleCount and index <= self._count then
			row.Frame.Position = UDim2.fromOffset(0, (index - 1) * rowHeight)
			row.Frame.Visible = true
			row.Bind(index)
		else
			row.Frame.Visible = false
		end
	end
end

function VirtualList.Destroy(self: VirtualList)
	self._janitor:Destroy()
	table.clear(self._rows)
end

return VirtualList

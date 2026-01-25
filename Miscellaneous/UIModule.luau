--[[
    UIModule.luau - Config-driven UI component library
    
    Usage:
    local UI = require(...)({
        Services = Services,
        Theme = Theme,
        Content = Content,
        ScreenGui = ScreenGui,
    })
    
    UI.CreateSection({
        Text = "📊 STATS",
        Rows = {
            {Name = "Speed", Label = "Speed:", Color = Theme.Colors.Speed, HasIndicator = true, Tooltip = "..."},
            {Name = "Stamina", Label = "Stamina:", Color = Theme.Colors.Stamina},
        }
    })
    
    -- Access labels:
    UI.Labels.Speed.Number, UI.Labels.Speed.Indicator
    UI.Labels.Stamina
]]

return function(dependencies)
    local Services = dependencies.Services
    local Theme = dependencies.Theme
    local Content = dependencies.Content
    local ScreenGui = dependencies.ScreenGui
    
    local UI = {}
    UI.Labels = {}  -- Stores all value labels by name
    
    local layoutOrder = 0
    
    -- Tooltip UI (shared, moves on hover)
    local TooltipFrame = Instance.new("Frame")
    TooltipFrame.Name = "Tooltip"
    TooltipFrame.Size = UDim2.new(0, 180, 0, 50)
    TooltipFrame.BackgroundColor3 = Theme.Colors.Tooltip
    TooltipFrame.BorderSizePixel = 0
    TooltipFrame.Visible = false
    TooltipFrame.ZIndex = 100
    TooltipFrame.Parent = ScreenGui

    local TooltipCorner = Instance.new("UICorner")
    TooltipCorner.CornerRadius = UDim.new(0, 6)
    TooltipCorner.Parent = TooltipFrame

    local TooltipText = Instance.new("TextLabel")
    TooltipText.Name = "Text"
    TooltipText.Size = UDim2.new(1, -10, 1, -6)
    TooltipText.Position = UDim2.new(0, 5, 0, 3)
    TooltipText.BackgroundTransparency = 1
    TooltipText.Text = ""
    TooltipText.TextColor3 = Theme.Colors.TooltipText
    TooltipText.TextSize = Theme.Sizes.TooltipText
    TooltipText.Font = Theme.Fonts.Secondary
    TooltipText.TextWrapped = true
    TooltipText.TextXAlignment = Enum.TextXAlignment.Left
    TooltipText.TextYAlignment = Enum.TextYAlignment.Top
    TooltipText.ZIndex = 101
    TooltipText.Parent = TooltipFrame
    
    -- Private: Get next layout order
    local function _NextOrder(explicitOrder)
        if explicitOrder then return explicitOrder end
        layoutOrder = layoutOrder + 1
        return layoutOrder
    end
    
    -- Private: Setup tooltip hover behavior
    local function _SetupTooltip(label, tooltipText)
        if not tooltipText then return end
        
        local tooltipConnection = nil
        
        label.MouseEnter:Connect(function()
            TooltipText.Text = tooltipText
            TooltipFrame.Visible = true
            
            tooltipConnection = Services.UserInputService.InputChanged:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseMovement then
                    TooltipFrame.Position = UDim2.new(0, input.Position.X + 15, 0, input.Position.Y + 10)
                end
            end)
            
            local mousePosition = Services.UserInputService:GetMouseLocation()
            TooltipFrame.Position = UDim2.new(0, mousePosition.X + 15, 0, mousePosition.Y + 10)
        end)
        
        label.MouseLeave:Connect(function()
            TooltipFrame.Visible = false
            if tooltipConnection then
                tooltipConnection:Disconnect()
                tooltipConnection = nil
            end
        end)
    end
    
    -- Private: Create a standard row
    local function _CreateRow(config)
        local order = _NextOrder(config.Order)
        
        local Row = Instance.new("Frame")
        Row.Name = config.Name
        Row.Size = UDim2.new(1, 0, 0, Theme.Sizes.Row)
        Row.BackgroundTransparency = 1
        Row.LayoutOrder = order
        Row.Parent = Content
        
        local Label = Instance.new("TextButton")
        Label.Name = "Label"
        Label.Size = UDim2.new(0.55, 0, 1, 0)
        Label.BackgroundTransparency = 1
        Label.Text = config.Label
        Label.TextColor3 = config.Color
        Label.TextSize = Theme.Sizes.LabelText
        Label.Font = Theme.Fonts.Primary
        Label.TextXAlignment = Enum.TextXAlignment.Left
        Label.AutoButtonColor = false
        Label.Parent = Row
        
        _SetupTooltip(Label, config.Tooltip)
        
        local Value = Instance.new("TextLabel")
        Value.Name = "Value"
        Value.Size = UDim2.new(0.45, 0, 1, 0)
        Value.Position = UDim2.new(0.55, 0, 0, 0)
        Value.BackgroundTransparency = 1
        Value.Text = "---"
        Value.TextColor3 = Theme.Colors.Success
        Value.TextSize = Theme.Sizes.ValueText
        Value.Font = Theme.Fonts.Primary
        Value.TextXAlignment = Enum.TextXAlignment.Right
        Value.Parent = Row
        
        return Value
    end
    
    -- Private: Create a row with indicator
    local function _CreateIndicatorRow(config)
        local order = _NextOrder(config.Order)
        
        local Row = Instance.new("Frame")
        Row.Name = config.Name
        Row.Size = UDim2.new(1, 0, 0, Theme.Sizes.Row)
        Row.BackgroundTransparency = 1
        Row.LayoutOrder = order
        Row.Parent = Content
        
        local Label = Instance.new("TextButton")
        Label.Name = "Label"
        Label.Size = UDim2.new(0.55, 0, 1, 0)
        Label.BackgroundTransparency = 1
        Label.Text = config.Label
        Label.TextColor3 = config.Color
        Label.TextSize = Theme.Sizes.LabelText
        Label.Font = Theme.Fonts.Primary
        Label.TextXAlignment = Enum.TextXAlignment.Left
        Label.AutoButtonColor = false
        Label.Parent = Row
        
        _SetupTooltip(Label, config.Tooltip)
        
        local ValueContainer = Instance.new("Frame")
        ValueContainer.Name = "ValueContainer"
        ValueContainer.Size = UDim2.new(0.45, 0, 1, 0)
        ValueContainer.Position = UDim2.new(0.55, 0, 0, 0)
        ValueContainer.BackgroundTransparency = 1
        ValueContainer.ClipsDescendants = true
        ValueContainer.Parent = Row
        
        local Layout = Instance.new("UIListLayout")
        Layout.FillDirection = Enum.FillDirection.Horizontal
        Layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        Layout.VerticalAlignment = Enum.VerticalAlignment.Center
        Layout.SortOrder = Enum.SortOrder.LayoutOrder
        Layout.Padding = UDim.new(0, 2)
        Layout.Parent = ValueContainer
        
        local NumberValue = Instance.new("TextLabel")
        NumberValue.Name = "NumberValue"
        NumberValue.AutomaticSize = Enum.AutomaticSize.X
        NumberValue.Size = UDim2.new(0, 0, 1, 0)
        NumberValue.BackgroundTransparency = 1
        NumberValue.Text = "---"
        NumberValue.TextColor3 = Theme.Colors.Neutral
        NumberValue.TextSize = Theme.Sizes.ValueText
        NumberValue.Font = Theme.Fonts.Primary
        NumberValue.LayoutOrder = 1
        NumberValue.Parent = ValueContainer
        
        local Indicator = Instance.new("TextLabel")
        Indicator.Name = "Indicator"
        Indicator.AutomaticSize = Enum.AutomaticSize.X
        Indicator.Size = UDim2.new(0, 0, 1, 0)
        Indicator.BackgroundTransparency = 1
        Indicator.Text = "–"
        Indicator.TextColor3 = Theme.Colors.Neutral
        Indicator.TextSize = Theme.Sizes.ValueText
        Indicator.Font = Theme.Fonts.Primary
        Indicator.LayoutOrder = 2
        Indicator.Parent = ValueContainer
        
        return {Number = NumberValue, Indicator = Indicator}
    end
    
    -- Private: Create a section divider
    local function _CreateSectionDivider(config)
        local order = _NextOrder(config.Order)
        
        local Container = Instance.new("Frame")
        Container.Name = "Section_" .. config.Text
        Container.Size = UDim2.new(1, 0, 0, Theme.Sizes.Section)
        Container.BackgroundTransparency = 1
        Container.LayoutOrder = order
        Container.Parent = Content
        
        local textSize = Services.TextService:GetTextSize(config.Text, Theme.Sizes.SectionText, Theme.Fonts.Primary, Vector2.new(200, 14))
        local textWidthPercent = (textSize.X + 10) / 200
        
        local LeftLine = Instance.new("Frame")
        LeftLine.Size = UDim2.new(0.02, 0, 0, 1)
        LeftLine.Position = UDim2.new(0, 0, 0.5, 0)
        LeftLine.BackgroundColor3 = Theme.Colors.Stroke
        LeftLine.BorderSizePixel = 0
        LeftLine.Parent = Container
        
        local SectionLabel = Instance.new("TextLabel")
        SectionLabel.Size = UDim2.new(textWidthPercent, 0, 1, 0)
        SectionLabel.Position = UDim2.new(0.04, 0, 0, 0)
        SectionLabel.BackgroundTransparency = 1
        SectionLabel.Text = config.Text
        SectionLabel.TextColor3 = Theme.Colors.SectionText
        SectionLabel.TextSize = Theme.Sizes.SectionText
        SectionLabel.Font = Theme.Fonts.Primary
        SectionLabel.TextXAlignment = Enum.TextXAlignment.Left
        SectionLabel.Parent = Container
        
        local rightLineStart = 0.04 + textWidthPercent + 0.02
        local RightLine = Instance.new("Frame")
        RightLine.Size = UDim2.new(1 - rightLineStart, 0, 0, 1)
        RightLine.Position = UDim2.new(rightLineStart, 0, 0.5, 0)
        RightLine.BackgroundColor3 = Theme.Colors.Stroke
        RightLine.BorderSizePixel = 0
        RightLine.Parent = Container
        
        return Container
    end
    
    -- Public: Create a section with rows
    function UI.CreateSection(config)
        _CreateSectionDivider({Text = config.Text, Order = config.Order})
        
        for _, rowConfig in ipairs(config.Rows) do
            if rowConfig.HasIndicator then
                UI.Labels[rowConfig.Name] = _CreateIndicatorRow(rowConfig)
            else
                UI.Labels[rowConfig.Name] = _CreateRow(rowConfig)
            end
        end
    end
    
    -- Public: Reset layout order (useful if rebuilding UI)
    function UI.ResetOrder()
        layoutOrder = 0
    end
    
    return UI
end

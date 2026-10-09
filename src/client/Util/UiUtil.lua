--!strict
--[[
	UiUtil — tiny client-side UI helpers. Everything is Scale-based so the
	HUD looks right on phone, tablet, and desktop.
]]

local UiUtil = {}

function UiUtil.ScreenGui(name: string): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

function UiUtil.Pill(parent: Instance, text: string, pos: UDim2, size: UDim2): TextLabel
	local bg = Instance.new("Frame")
	bg.BackgroundColor3 = Color3.fromRGB(20, 28, 38)
	bg.BackgroundTransparency = 0.25
	bg.Size = size
	bg.Position = pos
	bg.AnchorPoint = Vector2.new(0.5, 0)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = bg
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.7
	stroke.Thickness = 2
	stroke.Parent = bg
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.6
	label.Text = text
	label.Parent = bg
	bg.Parent = parent
	return label
end

function UiUtil.Button(parent: Instance, text: string, pos: UDim2, size: UDim2): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = size
	btn.Position = pos
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.BackgroundColor3 = Color3.fromRGB(45, 120, 200)
	btn.Font = Enum.Font.GothamBlack
	btn.TextScaled = true
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextStrokeTransparency = 0.6
	btn.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = btn
	btn.Parent = parent
	return btn
end

-- Toast: small message that floats up and fades. Parent to a toast layer.
function UiUtil.Toast(parent: Instance, text: string, color: Color3?)
	local toast = Instance.new("TextLabel")
	toast.Size = UDim2.new(0.5, 0, 0.06, 0)
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 0.82, 0)
	toast.BackgroundColor3 = Color3.fromRGB(20, 28, 38)
	toast.BackgroundTransparency = 0.2
	toast.Font = Enum.Font.GothamBold
	toast.TextScaled = true
	toast.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	toast.TextStrokeTransparency = 0.5
	toast.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.4, 0)
	corner.Parent = toast
	toast.Parent = parent
	-- Float up + fade, then destroy.
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 2.5 do
			local t = os.clock() - t0
			toast.Position = UDim2.new(0.5, 0, 0.82 - t * 0.03, 0)
			if t > 1.5 then
				local a = (t - 1.5) / 1.0
				toast.TextTransparency = a
				toast.BackgroundTransparency = 0.2 + a * 0.8
			end
			task.wait(0.05)
		end
		toast:Destroy()
	end)
end

return UiUtil

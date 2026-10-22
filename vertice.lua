--[[============================================================
	FAST ATTACK v2 - universal (client-side)
	Mesma logica dos "fast attack" classicos, porem disparando por
	RunService.Heartbeat (60-240Hz) em vez de wait() (~30Hz),
	com burst controlado, animacoes aceleradas e remotes cacheados.
============================================================]]--

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP    = Players.LocalPlayer
local Mouse = LP:GetMouse()

--=========================== CONFIG ===========================
local CONFIG = {
	Enabled     = true,
	Keybind     = Enum.KeyCode.F,   -- liga/desliga

	AttackCPS   = 60,      -- tentativas por segundo (60 = 1 por frame em 60fps)
	MaxPerFrame = 4,       -- teto de disparos por frame (evita travar)
	SpeedAnim   = 2.5,     -- multiplicador das animacoes de ataque

	Mode        = "Both",  -- "Remote" | "Tool" | "Both"
	AutoAttack  = false,   -- true = ataca sozinho / false = so com o botao do mouse
	Debug       = false,   -- imprime os remotes encontrados

	Keywords = {"attack","atk","hit","swing","m1","slash","punch","kick","combo","combat","strike","click"},
	Exclude  = {"vfx","fx","sound","sfx","gui","notify","effect","particle","dust","trail","camera","shake","reload","equip","unequip"},

	-- se o jogo exigir argumento no remote (ex: posicao do mouse), ajuste aqui:
	-- RemoteArgs = function() return {Mouse.Hit.Position} end,
	RemoteArgs = function() return {} end,
}

--===================== DETECCAO DE REMOTES ====================
local remotes, busy = {}, {}
local holding = false

local function has(str, list)
	local n = string.lower(str)
	for i = 1, #list do
		if string.find(n, list[i], 1, true) then return true end
	end
	return false
end

local function scan()
	table.clear(remotes)
	local roots = {
		ReplicatedStorage,
		LP:FindFirstChild("PlayerScripts"),
		LP:FindFirstChild("Backpack"),
		LP.Character,
	}
	for i = 1, #roots do
		local root = roots[i]
		if root then
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("RemoteEvent") or d:IsA("UnreliableRemoteEvent") or d:IsA("RemoteFunction") then
					if has(d.Name, CONFIG.Keywords) and not has(d.Name, CONFIG.Exclude) then
						table.insert(remotes, d)
						if CONFIG.Debug then print("[FastAttack] remote:", d:GetFullName()) end
					end
				end
			end
		end
	end
end

--========================== DISPARO ===========================
local function fireRemote(r)
	local args = CONFIG.RemoteArgs()

	if r:IsA("RemoteFunction") then
		if busy[r] then return end          -- nao empilha InvokeServer (ele cede a thread)
		busy[r] = true
		task.spawn(function()
			pcall(r.InvokeServer, r, table.unpack(args))
			busy[r] = nil
		end)
	else
		pcall(r.FireServer, r, table.unpack(args))
	end
end

local function attack()
	local char = LP.Character
	local tool = char and char:FindFirstChildOfClass("Tool")

	if tool and (CONFIG.Mode == "Tool" or CONFIG.Mode == "Both") then
		pcall(function() tool:Activate() end)
	end

	if CONFIG.Mode == "Remote" or CONFIG.Mode == "Both" then
		for i = 1, #remotes do
			fireRemote(remotes[i])
		end
	end
end

--===================== LOOP (Heartbeat) =======================
local acc, last = 0, os.clock()
local interval = 1 / CONFIG.AttackCPS

RunService.Heartbeat:Connect(function()
	if not CONFIG.Enabled then return end
	if not CONFIG.AutoAttack and not holding then return end

	interval = 1 / CONFIG.AttackCPS
	local now = os.clock()
	acc += now - last
	last = now

	local n = 0
	while acc >= interval and n < CONFIG.MaxPerFrame do
		acc -= interval
		n += 1
		attack()
	end

	if acc > interval * CONFIG.MaxPerFrame then acc = 0 end -- anti-acumulo de atraso
end)

--======================= ANIMACOES ============================
local function hookAnims(container)
	if not container then return end
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("Animator") then
			d.AnimationPlayed:Connect(function(track)
				if CONFIG.SpeedAnim ~= 1 then
					pcall(function() track:AdjustSpeed(CONFIG.SpeedAnim) end)
				end
			end)
		end
	end
end

--===================== CICLO DE VIDA ==========================
local function bindCharacter(c)
	hookAnims(c)
	task.delay(0.5, scan)
end

if LP.Character then bindCharacter(LP.Character) end
LP.CharacterAdded:Connect(bindCharacter)
LP.Backpack.ChildAdded:Connect(function() task.delay(0.2, scan) end)
LP.Backpack.ChildRemoved:Connect(function() task.delay(0.2, scan) end)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then holding = true end
	if input.KeyCode == CONFIG.Keybind then
		CONFIG.Enabled = not CONFIG.Enabled
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then holding = false end
end)

scan()

--=========================== GUI ==============================
local parent = (gethui and gethui()) or game:GetService("CoreGui")
local gui = Instance.new("ScreenGui")
gui.Name = "VeniceFastAttack"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
if not pcall(function() gui.Parent = parent end) then
	gui.Parent = LP:WaitForChild("PlayerGui")
end

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(240, 258)
frame.Position = UDim2.new(0, 20, 0, 120)
frame.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

local function mkText(txt, y, x, w, size, color)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(w, 0, 0, 20)
	l.Position = UDim2.new(0, x, 0, y)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamMedium
	l.TextSize = size or 13
	l.TextColor3 = color or Color3.fromRGB(225, 228, 240)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = txt
	l.Parent = frame
	return l
end

local function mkButton(txt, y, x, w)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(w, 0, 0, 26)
	b.Position = UDim2.new(0, x, 0, y)
	b.BackgroundColor3 = Color3.fromRGB(38, 42, 60)
	b.TextColor3 = Color3.fromRGB(232, 234, 245)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 13
	b.BorderSizePixel = 0
	b.Text = txt
	b.Parent = frame
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	return b
end

mkText("Fast Attack v2 - Venice", 8, 12, 0.7, 14, Color3.fromRGB(150, 200, 255))
local status = mkText("", 26, 12, 0.8, 12, Color3.fromRGB(150, 255, 180))

local btnToggle = mkButton("", 50, 10, 0.92)
local btnMode   = mkButton("", 80, 10, 0.92)
mkText("CPS", 112, 12, 0.2, 12)
local btnMinus  = mkButton("-10", 108, 60, 0.18)
local btnPlus   = mkButton("+10", 108, 172, 0.28)
mkText("Anim", 144, 12, 0.2, 12)
local btnAnimM  = mkButton("-", 140, 60, 0.18)
local btnAnimP  = mkButton("+", 140, 172, 0.28)
local btnAuto   = mkButton("", 170, 10, 0.92)
local btnRescan = mkButton("Rescan remotes", 200, 10, 0.92)

local function refresh()
	btnToggle.Text = CON

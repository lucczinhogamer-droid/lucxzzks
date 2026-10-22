loadstring([==[
--[[
   VENICE BF ULTRA  •  v2.0  •  por Venice (venice.ai)
   Fast Attack com DESCOBERTA ADAPTATIVA + Escudo Anti-Cheat

   v2 corrige o Update 30:
     - CombatFramework saiu do PlayerScripts -> 5 rotas de descoberta
     - clique simulado pode dar 0 dano -> 7 metodos + benchmark que
       testa contra um inimigo vivo e escolhe o que REALMENTE acerta
     - botao DIAGNOSTICO pra saber exatamente o que esta falhando

   TECLAS: RightCtrl UI | F FastAtk | C Click | T testar metodos | End PANIC
--]]

local VENICE_VERSION = "2.0"

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local VirtualUser       = game:GetService("VirtualUser")

local LP = Players.LocalPlayer
local PLAYERSCRIPTS = LP:WaitForChild("PlayerScripts", 20)

local genv = (typeof(getgenv) == "function" and getgenv()) or _G
local HUI  = (typeof(gethui) == "function" and gethui()) or LP:WaitForChild("PlayerGui")
local RenderStep = RunService.PreRender or RunService.RenderStepped

local VIM, CAM
pcall(function() VIM = game:GetService("VirtualInputManager") end)
pcall(function() CAM = workspace.CurrentCamera end)

if genv.__VENICE_BF_UNLOAD then pcall(genv.__VENICE_BF_UNLOAD) end

local Config = {
    Enabled          = true,
    FastAttack       = true,
    ClickAttack      = true,
    AttackMethod     = "vu_cam",
    AttackInterval   = 0,
    HitboxRange      = 150,
    AutoRotate       = true,
    AutoTest         = true,
    AutoEquip        = true,
    DisableAntiCheat = true,
    SimRadius        = true,
    SimRadiusValue   = 1000,
    NoCameraShake    = true,
    FPSBoost         = false,
}

local State = {
    Holder = nil, AC = nil, Via = nil,
    Conns = {}, DisabledMap = {}, Unloaded = false,
    Tested = false, LastDamage = 0, LastAttack = 0, Resolved = nil,
}

local function notif(txt)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "VENICE BF ULTRA", Text = tostring(txt), Duration = 3,
        })
    end)
    pcall(print, "[VENICE BF ULTRA] " .. tostring(txt))
end

local function log(txt) pcall(print, "[VENICE v2] " .. tostring(txt)) end

--====================================================================================
-- UTIL
--====================================================================================
local function upvaluesOf(f)
    if typeof(debug) == "table" and typeof(debug.getupvalues) == "function" then
        local ok, u = pcall(debug.getupvalues, f)
        if ok and u then return u end
    end
    if typeof(getupvalues) == "function" then
        local ok, u = pcall(getupvalues, f)
        if ok and u then return u end
    end
    return nil
end

local function looksLikeController(t)
    if typeof(t) ~= "table" then return false end
    local ok1 = pcall(function() return rawget(t, "timeToNextAttack") end)
    if not ok1 or rawget(t, "timeToNextAttack") == nil then return false end
    return rawget(t, "hitboxMagnitude") ~= nil or rawget(t, "attacking") ~= nil
end

local function hasACField(t)
    if typeof(t) ~= "table" then return false end
    local ok = pcall(function() return rawget(t, "activeController") end)
    return ok and rawget(t, "activeController") ~= nil
end

--====================================================================================
-- DESCOBERTA DO CONTROLLER (5 rotas)
--====================================================================================
local function findCombatFramework()
    local cf = PLAYERSCRIPTS:FindFirstChild("CombatFramework")

    -- ROTA 1: require direto
    if cf then
        local ok, mod = pcall(require, cf)
        if ok and typeof(mod) == "table" then
            if hasACField(mod) then return mod, "require(PlayerScripts)" end
            for k, v in pairs(mod) do
                if looksLikeController(v) then return { activeController = v }, "require->" .. tostring(k) end
            end
        end
    end

    -- ROTA 2: getloadedmodules
    if typeof(getloadedmodules) == "function" then
        local ok, mods = pcall(getloadedmodules)
        if ok and mods then
            for _, m in pairs(mods) do
                if typeof(m) == "Instance" and m:IsA("ModuleScript") then
                    local n = m.Name:lower()
                    if n:find("combat") or n:find("framework") then
                        local ok2, mod = pcall(require, m)
                        if ok2 and typeof(mod) == "table" then
                            if hasACField(mod) then return mod, "getloadedmodules:" .. m.Name end
                            for k, v in pairs(mod) do
                                if looksLikeController(v) then return { activeController = v }, "getloadedmodules->" .. tostring(k) end
                            end
                        end
                    end
                end
            end
        end
    end

    -- ROTA 3: getreg + upvalues
    if typeof(getreg) == "function" then
        local ok, reg = pcall(getreg)
        if ok and reg then
            for _, f in pairs(reg) do
                if typeof(f) == "function" then
                    local okE, env = pcall(getfenv, f)
                    if okE and typeof(env) == "table" then
                        local s = rawget(env, "script")
                        if typeof(s) == "Instance" and s.Name:lower():find("combat") then
                            local ups = upvaluesOf(f)
                            if ups then
                                for _, up in pairs(ups) do
                                    if hasACField(up) then return up, "getreg+upvalues" end
                                    if looksLikeController(up) then return { activeController = up }, "getreg+upvalues(ctrl)" end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- ROTA 4: getgc
    if typeof(getgc) == "function" then
        local ok, gc = pcall(getgc, true)
        if ok and gc then
            for _, v in pairs(gc) do
                if hasACField(v) then return v, "getgc" end
            end
            for _, v in pairs(gc) do
                if looksLikeController(v) then return { activeController = v }, "getgc(ctrl)" end
            end
        end
    end

    -- ROTA 5: getsenv
    if typeof(getsenv) == "function" and cf then
        local ok, env = pcall(getsenv, cf)
        if ok and typeof(env) == "table" then
            for _, v in pairs(env) do
                if hasACField(v) then return v, "getsenv" end
                if looksLikeController(v) then return { activeController = v }, "getsenv(ctrl)" end
            end
        end
    end

    return nil, nil
end

local function resolveCombat()
    local holder, via = findCombatFramework()
    if holder then
        State.Holder, State.Via = holder, via
        log("controller encontrado via " .. tostring(via))
        return true
    end
    return false
end

local function getAC()
    if not State.Holder then return nil end
    local ok, ac = pcall(function() return State.Holder.activeController end)
    if ok and typeof(ac) == "table" then State.AC = ac return ac end
    if ok and looksLikeController(State.Holder) then State.AC = State.Holder return State.Holder end
    return nil
end

--====================================================================================
-- INIMIGO MAIS PROXIMO
--====================================================================================
local function nearestEnemy(maxDist)
    local char = LP.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local ef = workspace:FindFirstChild("Enemies")
    if not ef then return nil end
    local best, bestD
    for _, m in ipairs(ef:GetChildren()) do
        if m:IsA("Model") then
            local h = m:FindFirstChildOfClass("Humanoid")
            local r = m:FindFirstChild("HumanoidRootPart")
            if h and r and h.Health > 0 then
                local d = (r.Position - root.Position).Magnitude
                if (not maxDist or d <= maxDist) and (not bestD or d < bestD) then
                    best, bestD = { m = m, h = h, r = r }, d
                end
            end
        end
    end
    return best
end

--====================================================================================
-- EQUIPAR ARMA (fruta na mao = M1 nao e melee)
--====================================================================================
local function isFruitTool(t)
    local ok, wt = pcall(function() return t:GetAttribute("WeaponType") end)
    if ok and wt then
        local s = tostring(wt):lower()
        return s:find("fruit") ~= nil
    end
    return false
end

local function equipWeapon()
    local char = LP.Character
    if not char then return end
    local eq = char:FindFirstChildOfClass("Tool")
    if eq and not isFruitTool(eq) then return end

    local bp = LP:FindFirstChildOfClass("Backpack")
    if not bp then return end
    local fallback
    for _, t in ipairs(bp:GetChildren()) do
        if t:IsA("Tool") then
            local ok, wt = pcall(function() return t:GetAttribute("WeaponType") end)
            local s = ok and wt and tostring(wt):lower() or ""
            if s:find("sword") or s:find("melee") or s:find("combat") or s:find("gun") then
                pcall(function() char.Humanoid:EquipTool(t) end)
                log("arma equipada: " .. t.Name)
                return
            end
            fallback = fallback or t
        end
    end
    if fallback then
        pcall(function() char.Humanoid:EquipTool(fallback) end)
        log("arma equipada (fallback): " .. fallback.Name)
    end
end

--====================================================================================
-- METODOS DE ATAQUE
--====================================================================================
local Attacks = {}
local function addAttack(id, label, fn)
    table.insert(Attacks, { id = id, label = label, fn = fn })
end

addAttack("vu_cam", "VirtualUser + Camera", function()
    VirtualUser:CaptureController()
    VirtualUser:Button1Down(Vector2.new(0, 0), CAM.CFrame)
end)

addAttack("vu_legacy", "VirtualUser legado", function()
    VirtualUser:CaptureController()
    VirtualUser:Button1Down(Vector2.new(0, 1, 0, 1))
end)

addAttack("vu_updown", "VirtualUser Down+Up", function()
    VirtualUser:CaptureController()
    VirtualUser:Button1Down(Vector2.new(0, 0), CAM.CFrame)
    VirtualUser:Button1Up(Vector2.new(0, 0), CAM.CFrame)
end)

addAttack("vim_center", "Mouse no centro da tela", function()
    if not VIM then return end
    local vs = CAM.ViewportSize
    VIM:SendMouseButtonEvent(vs.X / 2, vs.Y / 2, 0, true, game, 1)
    VIM:SendMouseButtonEvent(vs.X / 2, vs.Y / 2, 0, false, game, 1)
end)

addAttack("vim_enemy", "Mouse na posicao do inimigo", function()
    if not VIM then return end
    local t = nearestEnemy(120)
    if not t then return end
    local sp, on = CAM:WorldToViewportPoint(t.r.Position)
    if on then
        VIM:SendMouseButtonEvent(sp.X, sp.Y, 0, true, game, 1)
        VIM:SendMouseButtonEvent(sp.X, sp.Y, 0, false, game, 1)
    end
end)

addAttack("ctrl_attack", "Controller:attack()", function()
    local ac = getAC()
    if ac and typeof(ac.attack) == "function" then ac:attack() end
end)

addAttack("weapon_attack", "Weapon:attack() + hitServerCode", function()
    local ac = getAC()
    if not ac then return end
    local active = rawget(ac, "active")
    if typeof(active) == "table" then
        if active.weapon and typeof(active.weapon.attack) == "function" then active.weapon:attack() end
        if active.attacker and typeof(active.attacker.hitServerCode) == "function" then active.attacker:hitServerCode() end
    end
end)

addAttack("tool_activate", "Tool:Activate()", function()
    local char = LP.Character
    local t = char and char:FindFirstChildOfClass("Tool")
    if t then t:Activate() end
end)

local function attackById(id)
    for _, a in ipairs(Attacks) do
        if a.id == id then return a end
    end
    return nil
end

--====================================================================================
-- BENCHMARK: descobre qual metodo realmente acerta
--====================================================================================
local BenchReport = {}

local function benchmark()
    local results, lines = {}, {}
    table.insert(lines, "== BENCHMARK DE ATAQUE ==")
    table.insert(lines, "executor getreg=" .. tostring(typeof(getreg) == "function") ..
        " getgc=" .. tostring(typeof(getgc) == "function") ..
        " getsenv=" .. tostring(typeof(getsenv) == "function"))
    table.insert(lines, "controller via: " .. tostring(State.Via or "NAO ENCONTRADO"))
    local eq = LP.Character and LP.Character:FindFirstChildOfClass("Tool")
    table.insert(lines, "arma equipada: " .. (eq and eq.Name or "NENHUMA (!!)"))

    for _, a in ipairs(Attacks) do
        local t = nearestEnemy(120)
        if not t then
            table.insert(lines, string.format("%-30s sem inimigo perto", a.label))
            results[a.id] = 0
        else
            local before = t.h.Health
            local deadline = os.clock() + 1.5
            local ok, err = true, nil
            while os.clock() < deadline and t.h.Health > 0 do
                ok, err = pcall(a.fn)
                if not ok then break end
                task.wait(0.05)
            end
            local dealt = before - t.h.Health
            if dealt < 0 then dealt = 0 end
            results[a.id] = dealt
            table.insert(lines, string.format("%-30s %s", a.label,
                (not ok) and ("ERRO: " .. tostring(err)) or
                (dealt > 0 and ("*** DANO " .. math.floor(dealt) .. " ***") or "0 dano")))
        end
    end

    local bestId, bestDealt = nil, 0
    for id, d in pairs(results) do
        if d > bestDealt then bestId, bestDealt = id, d end
    end

    table.insert(lines, "")
    if bestId then
        local a = attackById(bestId)
        table.insert(lines, "VENCEDOR: " .. a.label .. " (" .. math.floor(bestDealt) .. " dano)")
        Config.AttackMethod = bestId
        State.Resolved = bestId
    else
        table.insert(lines, "NADA ACERTOU. Equipe uma ESPADA (nao fruta) e chegue perto de um inimigo.")
        table.insert(lines, "Se nem atacando na mao funciona, o problema e a arma, nao o script.")
    end

    BenchReport = lines
    for _, l in ipairs(lines) do log(l) end
    if typeof(setclipboard) == "function" then pcall(setclipboard, table.concat(lines, "\n")) end
    if bestId then notif("Metodo de ataque: " .. attackById(bestId).label) end
    return bestId
end

--====================================================================================
-- ESCUDO ANTI-CHEAT
--====================================================================================
local function findAntiCheatScripts()
    local found = {}
    for _, root in ipairs({ PLAYERSCRIPTS, ReplicatedStorage }) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("LocalScript") then
                    local n = d.Name:lower()
                    if n == "anticheat" or n == "anti_cheat" or n == "anticheats" or n == "anti cheat" then
                        table.insert(found, d)
                    end
                end
            end
        end
    end
    return found
end

local function applyDisableAntiCheat(on)
    if on then
        local list = findAntiCheatScripts()
        for _, s in ipairs(list) do
            State.DisabledMap[s] = s.Disabled
            pcall(function() s.Disabled = true end)
        end
        notif("Shield ON - " .. #list .. " AntiCheat neutralizado(s)")
    else
        for s, prev in pairs(State.DisabledMap) do
            pcall(function() if s and s.Parent then s.Disabled = prev or false end end)
        end
        State.DisabledMap = {}
        notif("Shield OFF")
    end
end

local function applySimRadius(on)
    if typeof(sethiddenproperty) ~= "function" then return end
    local v = on and Config.SimRadiusValue or 1000
    for _, p in ipairs({ "SimulationRadius", "MaxSimulationRadius", "SimulationRaxNerous" }) do
        pcall(sethiddenproperty, LP, p, v)
    end
end

local function stopCameraShake()
    pcall(function()
        local util = ReplicatedStorage:FindFirstChild("Util")
        if util and util:FindFirstChild("CameraShaker") then require(util.CameraShaker):Stop() end
    end)
    pcall(function()
        local cf = PLAYERSCRIPTS:FindFirstChild("CombatFramework")
        if cf and cf:FindFirstChild("CameraShaker") then require(cf.CameraShaker):Stop() end
    end)
end

local function applyFPSBoost(on)
    if on then
        pcall(function() setfpscap(240) end)
        notif("FPS Boost ON")
    else
        pcall(function() setfpscap(60) end)
        notif("FPS Boost OFF")
    end
end

--====================================================================================
-- LOOP PRINCIPAL
--====================================================================================
local function tuneController()
    local ac = getAC()
    if not ac then return end
    ac.timeToNextAttack   = 0
    ac.attacking          = false
    ac.blocking           = false
    ac.increment          = 4
    ac.hitboxMagnitude    = Config.HitboxRange
    ac.focusStart         = 0
    ac.currentAttackTrack = 0
    if ac.humanoid then pcall(function() ac.humanoid.AutoRotate = Config.AutoRotate end) end
end

local function fireAttack()
    local a = attackById(Config.AttackMethod)
    if a then pcall(a.fn) end
end

local function startLoops()
    -- tuning do fast attack
    table.insert(State.Conns, RenderStep:Connect(function()
        if not Config.Enabled or not Config.FastAttack then return end
        if not State.Holder then resolveCombat() end
        pcall(tuneController)
    end))

    -- ataque
    table.insert(State.Conns, RenderStep:Connect(function()
        if not Config.Enabled or not Config.ClickAttack then return end
        local now = os.clock()
        if Config.AttackInterval > 0 and (now - State.LastAttack) < Config.AttackInterval then return end
        State.LastAttack = now
        fireAttack()
    end))

    -- housekeeping: re-resolve, auto equip, auto test
    task.spawn(function()
        while not State.Unloaded do
            task.wait(2)
            pcall(function()
                if Config.Enabled then
                    if not State.Holder then resolveCombat() end
                    if Config.AutoEquip then equipWeapon() end
                    if Config.AutoTest and not State.Tested and nearestEnemy(60) then
                        State.Tested = true
                        benchmark()
                    end
                end
            end)
        end
    end)

    table.insert(State.Conns, LP.CharacterAdded:Connect(function()
        task.wait(1)
        resolveCombat()
        if Config.AutoEquip then equipWeapon() end
    end))
end

--====================================================================================
-- DIAGNOSTICO (painel selecionavel + clipboard)
--====================================================================================
local function diagnose()
    local lines = {}
    local function L(s) table.insert(lines, tostring(s)) end
    L("VENICE BF ULTRA v" .. VENICE_VERSION .. " - DIAGNOSTICO " .. os.date("%H:%M:%S"))
    L("")
    L("== CAPACIDADES DO EXECUTOR ==")
    for _, c in ipairs({ "getgc","getreg","getupvalues","debug.getupvalues","getsenv","getrawmetatable",
                        "hookfunction","hookmetamethod","getconnections","getloadedmodules","sethiddenproperty" }) do
        local ok, v = pcall(function()
            if c == "debug.getupvalues" then return debug and debug.getupvalues end
            return _G[c] or (getgenv and getgenv()[c])
        end)
        L("  " .. (ok and v ~= nil and "[OK]  " or "[NAO] ") .. c)
    end
    L("")
    L("== PLAYERSCRIPTS ==")
    local ps = LP:FindFirstChild("PlayerScripts")
    if ps then
        local names = {}
        for _, ch in ipairs(ps:GetChildren()) do table.insert(names, ch.Name) end
        L("  " .. table.concat(names, ", "))
    end
    L("  CombatFramework presente: " .. tostring(ps and ps:FindFirstChild("CombatFramework") ~= nil))
    L("")
    L("== DESCOBERTA ==")
    L("  holder: " .. tostring(State.Holder ~= nil) .. "  via: " .. tostring(State.Via))
    local ac = getAC()
    L("  activeController: " .. (ac and "OK" or "NIL (equipe uma espada)"))
    if ac then
        local fields = {}
        for k, v in pairs(ac) do table.insert(fields, tostring(k) .. "=" .. typeof(v)) end
        table.sort(fields)
        L("  campos: " .. table.concat(fields, ", "):sub(1, 500))
    end
    L("")
    L("== ARMA ==")
    local eq = LP.Character and LP.Character:FindFirstChildOfClass("Tool")
    L("  equipada: " .. (eq and eq.Name or "NENHUMA"))
    if eq then
        local ok, wt = pcall(function() return eq:GetAttribute("WeaponType") end)
        L("  WeaponType: " .. tostring(ok and wt))
    end
    L("")
    L("== BENCHMARK ==")
    if #BenchReport > 0 then
        for _, l in ipairs(BenchReport) do L("  " .. l) end
    else
        L("  ainda nao rodou - aperte TESTAR METODOS")
    end

    local txt = table.concat(lines, "\n")
    for _, l in ipairs(lines) do log(l) end
    if typeof(setclipboard) == "function" then pcall(setclipboard, txt) end

    pcall(function()
        local pg = LP:WaitForChild("PlayerGui", 10)
        local old = pg:FindFirstChild("VeniceDiag")
        if old then old:Destroy() end
        local gui = Instance.new("ScreenGui")
        gui.Name = "VeniceDiag"
        gui.ResetOnSpawn = false
        gui.DisplayOrder = 999
        gui.Parent = pg
        local f = Instance.new("Frame")
        f.Size = UDim2.new(0.62, 0, 0.7, 0)
        f.Position = UDim2.new(0.19, 0, 0.15, 0)
        f.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
        f.BorderSizePixel = 0
        f.Active = true
        f.Draggable = true
        f.Parent = gui
        local sc = Instance.new("ScrollingFrame")
        sc.Size = UDim2.new(1, -12, 1, -40)
        sc.Position = UDim2.fromOffset(6, 32)
        sc.BackgroundColor3 = Color3.fromRGB(16, 19, 25)
        sc.BorderSizePixel = 0
        sc.CanvasSize = UDim2.new(0, 0, 0, 3000)
        sc.ScrollBarThickness = 6
        sc.Parent = f
        local box = Instance.new("TextBox")
        box.Size = UDim2.new(1, -8, 1, 0)
        box.Position = UDim2.fromOffset(4, 0)
        box.BackgroundTransparency = 1
        box.ClearTextOnFocus = false
        box.MultiLine = true
        box.TextEditable = false
        box.Font = Enum.Font.Code
        box.TextSize = 12
        box.TextXAlignment = Enum.TextXAlignment.Left
        box.TextYAlignment = Enum.TextYAlignment.Top
        box.TextColor3 = Color3.fromRGB(200, 215, 230)
        box.TextWrapped = true
        box.Text = txt
        box.Parent = sc
        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(1, -80, 0, 26)
        t.Position = UDim2.fromOffset(8, 3)
        t.BackgroundTransparency = 1
        t.Font = Enum.Font.GothamBold
        t.TextSize = 13
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.TextColor3 = Color3.fromRGB(0, 195, 255)
        t.Text = "DIAGNOSTICO (copiado pro clipboard)"
        t.Parent = f
        local x = Instance.new("TextButton")
        x.Size = UDim2.fromOffset(66, 22)
        x.Position = UDim2.new(1, -74, 0, 4)
        x.BackgroundColor3 = Color3.fromRGB(60, 30, 34)
        x.Font = Enum.Font.GothamBold
        x.TextSize = 11
        x.TextColor3 = Color3.fromRGB(255, 200, 200)
        x.Text = "FECHAR"
        x.Parent = f
        x.Activated:Connect(function() gui:Destroy() end)
    end)
end

--====================================================================================
-- UI
--====================================================================================
local UI = { Painters = {} }
local function paintAll() for _, f in ipairs(UI.Painters) do pcall(f) end end

local function buildUI()
    if UI.ScreenGui and UI.ScreenGui.Parent then UI.ScreenGui:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name = "VeniceBFUltra"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent = HUI
    UI.ScreenGui = sg

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 300, 0, 470)
    main.Position = UDim2.new(0, 24, 0, 80)
    main.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
    main.BorderSizePixel = 0
    main.Parent = sg
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Color3.fromRGB(0, 175, 255)
    stroke.Thickness = 1.2
    stroke.Transparency = 0.35

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundColor3 = Color3.fromRGB(23, 23, 32)
    header.BorderSizePixel = 0
    header.Parent = main
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -40, 1, 0)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "VENICE BF ULTRA v" .. VENICE_VERSION
    title.Font = Enum.Font.GothamBold
    title.TextSize = 12
    title.TextColor3 = Color3.fromRGB(0, 195, 255)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local close = Instance.new("TextButton")
    close.Size = UDim2.new(0, 26, 0, 26)
    close.Position = UDim2.new(1, -32, 0, 5)
    close.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
    close.Text = "X"
    close.Font = Enum.Font.GothamBold
    close.TextSize = 12
    close.TextColor3 = Color3.fromRGB(255, 90, 90)
    close.BorderSizePixel = 0
    close.Parent = header
    Instance.new("UICorner", close).CornerRadius = UDim.new(0, 6)
    close.MouseButton1Click:Connect(function() sg.Enabled = false end)

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -16, 0, 30)
    status.Position = UDim2.new(0, 8, 0, 40)
    status.BackgroundColor3 = Color3.fromRGB(12, 26, 34)
    status.BorderSizePixel = 0
    status.Font = Enum.Font.Code
    status.TextSize = 10
    status.TextColor3 = Color3.fromRGB(120, 220, 255)
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextWrapped = true
    status.Parent = main
    Instance.new("UICorner", status).CornerRadius = UDim.new(0, 6)
    local sp = Instance.new("UIPadding", status)
    sp.PaddingLeft = UDim.new(0, 6)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -16, 1, -142)
    scroll.Position = UDim2.new(0, 8, 0, 76)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.ScrollBarImageColor3 = Color3.fromRGB(0, 175, 255)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = main

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 5)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = scroll

    local footer = Instance.new("TextLabel")
    footer.Size = UDim2.new(1, -16, 0, 26)
    footer.Position = UDim2.new(0, 8, 1, -30)
    footer.BackgroundTransparency = 1
    footer.Text = "RightCtrl UI | F FastAtk | C Click | T Testar | End PANIC"
    footer.Font = Enum.Font.Gotham
    footer.TextSize = 10
    footer.TextColor3 = Color3.fromRGB(120, 128, 140)
    footer.Parent = main

    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, i.Position, main.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    local order = 0
    local function newRow(h)
        order += 1
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -6, 0, h)
        row.BackgroundTransparency = 1
        row.LayoutOrder = order
        row.Parent = scroll
        return row
    end
    local function newSection(text)
        order += 1
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -6, 0, 20)
        lbl.BackgroundTransparency = 1
        lbl.LayoutOrder = order
        lbl.Text = "— " .. text .. " —"
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 10
        lbl.TextColor3 = Color3.fromRGB(0, 175, 255)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = scroll
    end
    local function newButton(text, fn, cor)
        local row = newRow(28)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 1, 0)
        b.BackgroundColor3 = cor or Color3.fromRGB(30, 60, 84)
        b.BorderSizePixel = 0
        b.Font = Enum.Font.GothamBold
        b.TextSize = 11
        b.TextColor3 = Color3.fromRGB(220, 240, 255)
        b.Text = text
        b.Parent = row
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        b.MouseButton1Click:Connect(function() pcall(fn) end)
    end
    local function newToggle(text, key, onChange)
        local row = newRow(28)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 11
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.Parent = row
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        local pad = Instance.new("UIPadding", btn)
        pad.PaddingLeft = UDim.new(0, 10)
        local function paint()
            local on = Config[key]
            btn.Text = text .. "   [" .. (on and "ON" or "OFF") .. "]"
            btn.BackgroundColor3 = on and Color3.fromRGB(0, 92, 140) or Color3.fromRGB(32, 32, 42)
            btn.TextColor3 = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 156, 168)
        end
        table.insert(UI.Painters, paint)
        paint()
        btn.MouseButton1Click:Connect(function()
            Config[key] = not Config[key]
            paint()
            if onChange then pcall(onChange, Config[key]) end
        end)
    end
    local function newSlider(text, key, min, max, step, fmt)
        local row = newRow(30)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0, 110, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 11
        lbl.TextColor3 = Color3.fromRGB(200, 206, 216)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row
        local value = Instance.new("TextLabel")
        value.Size = UDim2.new(0, 52, 1, 0)
        value.Position = UDim2.new(1, -52, 0, 0)
        value.BackgroundTransparency = 1
        value.Font = Enum.Font.GothamBold
        value.TextSize = 11
        value.TextColor3 = Color3.fromRGB(0, 195, 255)
        value.TextXAlignment = Enum.TextXAlignment.Right
        value.Parent = row
        local bar = Instance.new("TextButton")
        bar.Size = UDim2.new(1, -172, 0, 6)
        bar.Position = UDim2.new(0, 112, 0, 12)
        bar.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
        bar.Text = ""
        bar.BorderSizePixel = 0
        bar.Parent = row
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(0, 175, 255)
        fill.BorderSizePixel = 0
        fill.Parent = bar
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
        local function paint()
            local a = (Config[key] - min) / (max - min)
            fill.Size = UDim2.new(math.clamp(a, 0, 1), 0, 1, 0)
            value.Text = fmt and fmt(Config[key]) or tostring(Config[key])
        end
        table.insert(UI.Painters, paint)
        paint()
        local held = false
        local function update(x)
            local rel = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
            local v = min + rel * (max - min)
            Config[key] = math.floor(v / step + 0.5) * step
            paint()
        end
        bar.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                held = true
                update(i.Position.X)
            end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if held and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                update(i.Position.X)
            end
        end)
        UserInputService.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                held = false
            end
        end)
    end

    newButton(">> TESTAR METODOS DE ATAQUE <<", function()
        State.Tested = true
        benchmark()
    end, Color3.fromRGB(0, 120, 90))
    newButton("DIAGNOSTICO (copia pro clipboard)", diagnose, Color3.fromRGB(60, 60, 90))

    newSection("ATAQUE")
    newToggle("MASTER", "Enabled")
    newToggle("FAST ATTACK (cooldown 0)", "FastAttack")
    newToggle("CLICK ATTACK", "ClickAttack")
    newToggle("Auto Equip Espada", "AutoEquip")
    newToggle("Auto Testar metodo", "AutoTest")
    newSlider("Intervalo", "AttackInterval", 0, 0.2, 0.005, function(v) return string.format("%.3f", v) end)
    newSlider("Hitbox", "HitboxRange", 20, 400, 5, function(v) return tostring(v) end)
    newToggle("Auto Rotate", "AutoRotate")

    newSection("METODO")
    for _, a in ipairs(Attacks) do
        local row = newRow(26)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 1, 0)
        b.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
        b.BorderSizePixel = 0
        b.Font = Enum.Font.Gotham
        b.TextSize = 10
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.Parent = row
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
        local pad = Instance.new("UIPadding", b)
        pad.PaddingLeft = UDim.new(0, 10)
        local function paint()
            local sel = Config.AttackMethod == a.id
            b.Text = (sel and "> " or "  ") .. a.label
            b.BackgroundColor3 = sel and Color3.fromRGB(0, 92, 140) or Color3.fromRGB(32, 32, 42)
            b.TextColor3 = sel and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 156, 168)
        end
        table.insert(UI.Painters, paint)
        paint()
        b.MouseButton1Click:Connect(function()
            Config.AttackMethod = a.id
            paintAll()
            notif("Metodo: " .. a.label)
        end)
    end

    newSection("ANTI-CHEAT")
    newToggle("Shield Blox Fruits", "DisableAntiCheat", applyDisableAntiCheat)
    newToggle("Simulation Radius", "SimRadius", applySimRadius)
    newToggle("No Camera Shake", "NoCameraShake", function(on) if on then stopCameraShake() end end)
    newToggle("FPS Boost", "FPSBoost", applyFPSBoost)

    -- status live
    task.spawn(function()
        while not State.Unloaded and UI.ScreenGui do
            task.wait(0.5)
            pcall(function()
                local ac = getAC()
                local eq = LP.Character and LP.Character:FindFirstChildOfClass("Tool")
                status.Text = string.format("CF: %s | AC: %s | arma: %s\nmetodo: %s",
                    State.Via or "nao achado",
                    ac and "OK" or "NIL",
                    eq and eq.Name or "NENHUMA",
                    Config.AttackMethod)
                status.TextColor3 = (State.Holder and ac and eq)
                    and Color3.fromRGB(120, 220, 255) or Color3.fromRGB(255, 190, 90)
            end)
        end
    end)
end

local function bindKeys()
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == Enum.KeyCode.RightControl then
            if UI.ScreenGui then UI.ScreenGui.Enabled = not UI.ScreenGui.Enabled end
        elseif input.KeyCode == Enum.KeyCode.F then
            Config.FastAttack = not Config.FastAttack
            paintAll()
        elseif input.KeyCode == Enum.KeyCode.C then
            Config.ClickAttack = not Config.ClickAttack
            paintAll()
        elseif input.KeyCode == Enum.KeyCode.T then
            State.Tested = true
            benchmark()
        elseif input.KeyCode == Enum.KeyCode.End then
            genv.__VENICE_BF_UNLOAD()
        end
    end)
end

genv.__VENICE_BF_UNLOAD = function()
    if State.Unloaded then return end
    State.Unloaded = true
    for _, c in ipairs(State.Conns) do pcall(function() c:Disconnect() end) end
    State.Conns = {}
    applySimRadius(false)
    applyDisableAntiCheat(false)
    pcall(function() setfpscap(60) end)
    if UI.ScreenGui then UI.ScreenGui:Destroy() end
    genv.__VENICE_BF_UNLOAD = nil
    log("Unloaded.")
end

task.spawn(function()
    if not LP.Character then LP.CharacterAdded:Wait() end
    resolveCombat()
    if Config.AutoEquip then task.wait(0.5) equipWeapon() end
    if Config.NoCameraShake then stopCameraShake() end
    if Config.DisableAntiCheat then applyDisableAntiCheat(true) end
    if Config.SimRadius then applySimRadius(true) end
    startLoops()
    buildUI()
    bindKeys()
    notif("v2 carregado. Aperte T pra testar os metodos de ataque.")
end)
]==])()

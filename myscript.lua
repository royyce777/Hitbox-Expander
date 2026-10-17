--[[
  Sniper Arena Pro v2 — COMPLETE
  Values from scanner:
    HeadOffset  = Vector3.new(0, 0.33, 0)
    MouseRatio  = 1.070
    Smooth      = 0.093 (tuned to 0.10)
    Best Bone   = "Head"
    Camera sens = 790.8 units/rad
]]

task.wait(3)

---------------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Camera           = workspace.CurrentCamera
local LocalPlayer      = Players.LocalPlayer

if not LocalPlayer.Character then LocalPlayer.CharacterAdded:Wait() end
task.wait(1)

-- ลบ GUI เก่า
pcall(function()
    for _, name in ipairs({"SniperArenaProV2","SniperHUDv2"}) do
        local old = LocalPlayer.PlayerGui:FindFirstChild(name)
        if old then old:Destroy() end
    end
end)

---------------------------------------------------------------------------
-- CONFIG (ค่าจาก scanner จริง)
---------------------------------------------------------------------------
local CFG = {
    -- Aimbot
    Aimbot         = false,
    AimbotHoldMode = true,
    AimbotBone     = "Head",
    AimbotFOV      = 150,
    AimbotSmooth   = 0.10,          -- จาก scanner: 0.093 → tune เป็น 0.10
    HeadOffset     = Vector3.new(0, 0.33, 0), -- จาก scanner
    MouseRatio     = 1.070,         -- จาก mousemoverel test
    AimbotMaxDist  = 2000,
    SilentAim      = false,         -- true = camera lerp แทน mouse

    -- Hitbox
    HitboxEnabled  = false,
    HitboxSize     = 8,

    -- Weapon
    NoRecoil       = false,
    FastReload     = false,
    ReloadMult     = 0.1,

    -- Heal
    AutoHeal       = false,
    HealThreshold  = 60,
    HealAmount     = 100,

    -- ESP
    PlayerESP      = false,
    EnemyOnly      = true,
    LootESP        = false,
    ESPMaxDist     = 2000,

    -- Utility
    TeleportMode   = false,
    AntiKick       = false,

    -- Colors
    Accent  = Color3.fromHex("8B5CF6"),
    BG      = Color3.fromHex("09090D"),
    BtnBG   = Color3.fromHex("1C1C26"),
    EnemyC  = Color3.fromRGB(255, 75, 75),
    TeamC   = Color3.fromRGB(75, 200, 75),
    LootC   = Color3.fromRGB(255, 210, 50),
}

---------------------------------------------------------------------------
-- UTILS
---------------------------------------------------------------------------
local function getChar()  return LocalPlayer.Character end
local function getRoot()
    local c = getChar(); return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHuman()
    local c = getChar(); return c and c:FindFirstChildOfClass("Humanoid")
end
local function w2s(pos)
    local s, v = Camera:WorldToViewportPoint(pos)
    return Vector2.new(s.X, s.Y), v
end
local function isAlive(c)
    local h = c and c:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0
end
local function isEnemy(player)
    if player == LocalPlayer then return false end
    if not LocalPlayer.Team then return true end
    return player.TeamColor ~= LocalPlayer.TeamColor
end

---------------------------------------------------------------------------
-- BONE FINDER (scanner confirmed: "Head" exists, WorldY highest)
---------------------------------------------------------------------------
local HEAD_CHAIN = {"Head", "UpperTorso", "HumanoidRootPart"}

local function getBone(char, boneName)
    if boneName == "Head" then
        for _, name in ipairs(HEAD_CHAIN) do
            local p = char:FindFirstChild(name)
            if p and p:IsA("BasePart") then return p end
            for _, desc in ipairs(char:GetDescendants()) do
                if desc.Name == name and desc:IsA("BasePart") then return desc end
            end
        end
    end
    local direct = char:FindFirstChild(boneName)
    if direct and direct:IsA("BasePart") then return direct end
    for _, desc in ipairs(char:GetDescendants()) do
        if desc.Name == boneName and desc:IsA("BasePart") then return desc end
    end
    return char:FindFirstChild("HumanoidRootPart")
end

---------------------------------------------------------------------------
-- PREDICTED POSITION
---------------------------------------------------------------------------
local function predPos(bone)
    local base = bone.Position
    if bone.Name == "Head" then
        base = base + CFG.HeadOffset
    end
    local char = bone.Parent
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local vel  = root and root.AssemblyLinearVelocity or Vector3.zero
    return base + vel * 0.08
end

---------------------------------------------------------------------------
-- HITBOX EXPANDER
---------------------------------------------------------------------------
local hitboxConns = {}

local function applyHitbox(player)
    if player == LocalPlayer then return end
    local function onChar(char)
        task.wait(0.5)
        local root = char:WaitForChild("HumanoidRootPart", 5)
        if not root then return end
        if CFG.HitboxEnabled then
            root.Size = Vector3.new(CFG.HitboxSize, CFG.HitboxSize, CFG.HitboxSize)
            root.Transparency = 0.8
            root.CanCollide = false
        end
    end
    if hitboxConns[player.UserId] then hitboxConns[player.UserId]:Disconnect() end
    hitboxConns[player.UserId] = player.CharacterAdded:Connect(onChar)
    if player.Character then onChar(player.Character) end
end

local function refreshHitboxes()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            local c = p.Character
            if c then
                local root = c:FindFirstChild("HumanoidRootPart")
                if root then
                    if CFG.HitboxEnabled then
                        root.Size = Vector3.new(CFG.HitboxSize,CFG.HitboxSize,CFG.HitboxSize)
                        root.Transparency = 0.8
                        root.CanCollide = false
                    else
                        root.Size = Vector3.new(2,2,1)
                        root.Transparency = 1
                    end
                end
            end
        end
    end
end

Players.PlayerAdded:Connect(applyHitbox)
Players.PlayerRemoving:Connect(function(p)
    if hitboxConns[p.UserId] then
        hitboxConns[p.UserId]:Disconnect()
        hitboxConns[p.UserId] = nil
    end
end)
for _, p in ipairs(Players:GetPlayers()) do applyHitbox(p) end

---------------------------------------------------------------------------
-- NO RECOIL
---------------------------------------------------------------------------
local lastCamCF, noRecoilConn = nil, nil

local function startNoRecoil()
    if noRecoilConn then noRecoilConn:Disconnect() end
    lastCamCF = Camera.CFrame
    noRecoilConn = RunService.RenderStepped:Connect(function()
        if not CFG.NoRecoil then
            noRecoilConn:Disconnect(); noRecoilConn = nil; return
        end
        local cur = Camera.CFrame
        local rx, ry, rz = cur:ToEulerAnglesYXZ()
        if lastCamCF then
            local lx, ly, lz = lastCamCF:ToEulerAnglesYXZ()
            if math.abs(rx - lx) > 0.01 and
               not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
                Camera.CFrame = CFrame.new(cur.Position) * CFrame.fromEulerAnglesYXZ(lx, ry, rz)
            end
        end
        lastCamCF = Camera.CFrame
    end)
end

---------------------------------------------------------------------------
-- FAST RELOAD
---------------------------------------------------------------------------
local function hookAnimator(animator)
    if not animator then return end
    animator.AnimationPlayed:Connect(function(track)
        local name = track.Name:lower()
        local isReload = name:find("reload") or name:find("recharge")
            or name:find("chamber") or name:find("cock") or name:find("pump")
        if isReload and CFG.FastReload then
            track:AdjustSpeed(1 / math.max(CFG.ReloadMult, 0.01))
            track:GetPropertyChangedSignal("Speed"):Connect(function()
                if CFG.FastReload and track.IsPlaying then
                    track:AdjustSpeed(1 / math.max(CFG.ReloadMult, 0.01))
                end
            end)
        end
    end)
end

local function watchTools()
    local char = getChar(); if not char then return end
    local human = getHuman(); if not human then return end
    local animator = human:FindFirstChildOfClass("Animator")
    if animator then hookAnimator(animator) end
    human.ChildAdded:Connect(function(child)
        if child:IsA("Animator") then hookAnimator(child) end
    end)
end

---------------------------------------------------------------------------
-- AUTO HEAL
---------------------------------------------------------------------------
local autoHealConn = nil

local function startAutoHeal()
    if autoHealConn then autoHealConn:Disconnect() end
    autoHealConn = RunService.Heartbeat:Connect(function()
        if not CFG.AutoHeal then return end
        local h = getHuman(); if not h then return end
        if h.Health < CFG.HealThreshold and h.Health > 0 then
            h.Health = math.min(h.Health + 2, CFG.HealAmount)
            pcall(function()
                local remote = ReplicatedStorage:FindFirstChild("Heal")
                    or ReplicatedStorage:FindFirstChild("UseHeal")
                if remote and remote:IsA("RemoteEvent") then
                    remote:FireServer()
                end
            end)
        end
    end)
end

---------------------------------------------------------------------------
-- DRAWING POOL
---------------------------------------------------------------------------
local pool = {}

local function drw(pid, key, dtype)
    if not pool[pid] then pool[pid] = {} end
    if not pool[pid][key] then
        local d = Drawing.new(dtype)
        d.Visible = false
        pool[pid][key] = d
    end
    return pool[pid][key]
end

local function clearPool(pid)
    if pool[pid] then
        for _, d in pairs(pool[pid]) do pcall(function() d:Remove() end) end
        pool[pid] = nil
    end
end

Players.PlayerRemoving:Connect(function(p) clearPool("p"..p.UserId) end)

---------------------------------------------------------------------------
-- AIMBOT CORE
-- ใช้ค่าจาก scanner:
--   MouseRatio = 1.070 → หาร delta ด้วย ratio ก่อนส่ง mousemoverel
--   Smooth = 0.10
--   HeadOffset = 0.33
---------------------------------------------------------------------------
local curTarget, curPlayer = nil, nil
local fovCircle = Drawing.new("Circle")
fovCircle.Filled    = false
fovCircle.Thickness = 1.2

local function findTarget()
    local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local best, bestP, bestD = nil, nil, CFG.AimbotFOV
    local lc = LocalPlayer.Character
    local lr = lc and getRoot()

    for _, p in ipairs(Players:GetPlayers()) do
        if not isEnemy(p) then continue end
        local c = p.Character
        if not c or not isAlive(c) then continue end
        local root = c:FindFirstChild("HumanoidRootPart")
        if not root then continue end
        if lr and (lr.Position - root.Position).Magnitude > CFG.AimbotMaxDist then continue end
        local bone = getBone(c, CFG.AimbotBone)
        if not bone then continue end
        local aim = predPos(bone)
        local sp, onSc = w2s(aim)
        if not onSc then continue end
        local sd = (sp - center).Magnitude
        if sd < bestD then
            bestD = sd; best = bone; bestP = p
        end
    end
    curTarget = best; curPlayer = bestP
end

local hl = nil
local function setHL(char)
    if not char then
        if hl then hl:Destroy(); hl = nil end
        return
    end
    if not hl then
        hl = Instance.new("Highlight")
        hl.FillTransparency    = 0.65
        hl.OutlineTransparency = 0
    end
    hl.FillColor    = CFG.Accent
    hl.OutlineColor = CFG.Accent
    hl.Adornee      = char
    hl.Parent       = char
end

local Mouse = LocalPlayer:GetMouse()

local function doAimbot()
    -- FOV circle
    fovCircle.Position = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    fovCircle.Radius   = CFG.AimbotFOV
    fovCircle.Color    = CFG.Aimbot and CFG.Accent or Color3.fromRGB(80,80,80)
    fovCircle.Visible  = CFG.Aimbot

    if not CFG.Aimbot then setHL(nil); return end

    -- hold mode gate
    if CFG.AimbotHoldMode and not UserInputService:IsMouseButtonPressed(
        Enum.UserInputType.MouseButton2) then
        setHL(nil); return
    end

    findTarget()
    setHL(curPlayer and curPlayer.Character)
    if not curTarget then return end

    local aimPos  = predPos(curTarget)
    local aim, ok = w2s(aimPos)
    if not ok then return end

    if CFG.SilentAim then
        -- Silent: lerp camera → ไม่โชว์ mouse เคลื่อน
        local targetCF = CFrame.lookAt(Camera.CFrame.Position, aimPos)
        Camera.CFrame  = Camera.CFrame:Lerp(targetCF, 1 - CFG.AimbotSmooth)
    else
        -- Mouse move: หาร delta ด้วย MouseRatio เพื่อ compensate sensitivity
        if mousemoverel then
            local mousePos = Vector2.new(Mouse.X, Mouse.Y)
            local delta    = aim - mousePos
            -- หาร ratio เพราะ 1 unit = 1.070 pixels จริง
            local adjX = (delta.X / CFG.MouseRatio) * CFG.AimbotSmooth
            local adjY = (delta.Y / CFG.MouseRatio) * CFG.AimbotSmooth
            mousemoverel(adjX, adjY)
        end
    end
end

---------------------------------------------------------------------------
-- PLAYER ESP
---------------------------------------------------------------------------
local function renderPlayerESP(player)
    if player == LocalPlayer then return end
    local char  = player.Character
    local pid   = "p"..player.UserId
    local keys  = {"bT","bB","bL","bR","name","dist","hpBg","hp","tag"}
    local function hide()
        for _, k in ipairs(keys) do
            local d = pool[pid] and pool[pid][k]
            if d then d.Visible = false end
        end
    end

    if not char or not CFG.PlayerESP then hide(); return end
    if CFG.EnemyOnly and not isEnemy(player) then hide(); return end

    local root  = char:FindFirstChild("HumanoidRootPart")
    local human = char:FindFirstChildOfClass("Humanoid")
    if not root or not human or not isAlive(char) then hide(); return end

    local lr = getRoot()
    if lr and (lr.Position - root.Position).Magnitude > CFG.ESPMaxDist then
        hide(); return
    end

    local head   = char:FindFirstChild("Head")
    local topPos = head and (head.Position + Vector3.new(0,0.7,0))
                         or (root.Position + Vector3.new(0,3.2,0))
    local botPos = root.Position - Vector3.new(0,3,0)
    local topS, topV = w2s(topPos)
    local botS       = w2s(botPos)
    if not topV then hide(); return end

    local boxH = math.max(math.abs(topS.Y - botS.Y), 1)
    local boxW = boxH * 0.44
    local L, R = topS.X - boxW/2, topS.X + boxW/2
    local T, B = topS.Y, botS.Y
    local col  = isEnemy(player) and CFG.EnemyC or CFG.TeamC

    -- box
    local segs = {
        {"bT", Vector2.new(L,T), Vector2.new(R,T)},
        {"bB", Vector2.new(L,B), Vector2.new(R,B)},
        {"bL", Vector2.new(L,T), Vector2.new(L,B)},
        {"bR", Vector2.new(R,T), Vector2.new(R,B)},
    }
    for _, s in ipairs(segs) do
        local d = drw(pid, s[1], "Line")
        d.From = s[2]; d.To = s[3]
        d.Color = col; d.Thickness = 1.2; d.Visible = true
    end

    -- health bar
    local hp  = math.clamp(human.Health / math.max(human.MaxHealth,1), 0, 1)
    local bx  = L - 6
    local hpC = Color3.fromRGB(math.floor(255*(1-hp)), math.floor(255*hp), 0)
    local bg  = drw(pid,"hpBg","Line")
    bg.From = Vector2.new(bx,T); bg.To = Vector2.new(bx,B)
    bg.Color = Color3.fromRGB(25,25,25); bg.Thickness = 4; bg.Visible = true
    local hb  = drw(pid,"hp","Line")
    hb.From = Vector2.new(bx,B); hb.To = Vector2.new(bx, B - boxH*hp)
    hb.Color = hpC; hb.Thickness = 3; hb.Visible = true

    -- name
    local nd = drw(pid,"name","Text")
    nd.Text     = player.Name
    nd.Position = Vector2.new(topS.X, T-14)
    nd.Size     = 13; nd.Color = col
    nd.Outline  = true; nd.Center = true; nd.Visible = true

    -- distance
    local dist = lr and (lr.Position - root.Position).Magnitude or 0
    local dd = drw(pid,"dist","Text")
    dd.Text     = string.format("%.0fm", dist)
    dd.Position = Vector2.new(topS.X, B+3)
    dd.Size     = 11; dd.Color = Color3.fromRGB(190,190,190)
    dd.Outline  = true; dd.Center = true; dd.Visible = true

    -- team tag
    local tt = drw(pid,"tag","Text")
    tt.Text     = isEnemy(player) and "[ENEMY]" or "[TEAM]"
    tt.Position = Vector2.new(topS.X, B+14)
    tt.Size     = 10; tt.Color = col
    tt.Outline  = true; tt.Center = true; tt.Visible = true
end

---------------------------------------------------------------------------
-- LOOT ESP
---------------------------------------------------------------------------
local lootDrawings = {}
local LOOT_KW = {
    "ammo","medkit","heal","health","crate","pickup","item",
    "loot","supply","gun","rifle","sniper","pistol","grenade","coin","cash","gem"
}

local function isLoot(obj)
    if not obj:IsA("BasePart") and not obj:IsA("Model") then return false end
    local name = obj.Name:lower()
    for _, kw in ipairs(LOOT_KW) do
        if name:find(kw) then return true end
    end
    return false
end

local function clearLootESP()
    for _, d in pairs(lootDrawings) do
        pcall(function() d.line:Remove(); d.label:Remove() end)
    end
    lootDrawings = {}
end

local function renderLootESP()
    if not CFG.LootESP then clearLootESP(); return end
    local lr = getRoot()
    local scanned = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if isLoot(obj) then
            local pos
            if obj:IsA("BasePart") then pos = obj.Position
            elseif obj:IsA("Model") and obj.PrimaryPart then pos = obj.PrimaryPart.Position end
            if pos then
                local dist = lr and (lr.Position - pos).Magnitude or 0
                if dist < CFG.ESPMaxDist then
                    local sp, onSc = w2s(pos)
                    local id = tostring(obj)
                    scanned[id] = true
                    if not lootDrawings[id] then
                        lootDrawings[id] = {
                            line  = Drawing.new("Line"),
                            label = Drawing.new("Text")
                        }
                    end
                    local ld = lootDrawings[id]
                    if onSc then
                        local cx = Camera.ViewportSize.X/2
                        ld.line.From        = Vector2.new(cx, Camera.ViewportSize.Y)
                        ld.line.To          = sp
                        ld.line.Color       = CFG.LootC
                        ld.line.Thickness   = 1
                        ld.line.Transparency = 0.6
                        ld.line.Visible     = true
                        ld.label.Text       = obj.Name.." ["..string.format("%.0f",dist).."m]"
                        ld.label.Position   = Vector2.new(sp.X, sp.Y-14)
                        ld.label.Size       = 11
                        ld.label.Color      = CFG.LootC
                        ld.label.Outline    = true
                        ld.label.Center     = true
                        ld.label.Visible    = true
                    else
                        ld.line.Visible  = false
                        ld.label.Visible = false
                    end
                end
            end
        end
    end
    for id, ld in pairs(lootDrawings) do
        if not scanned[id] then
            pcall(function() ld.line.Visible = false; ld.label.Visible = false end)
        end
    end
end

---------------------------------------------------------------------------
-- TACTICAL TELEPORT
---------------------------------------------------------------------------
local tpClick = nil

local function startTeleport()
    if tpClick then tpClick:Disconnect() end
    tpClick = UserInputService.InputBegan:Connect(function(input, gp)
        if gp or not CFG.TeleportMode then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local ray    = Camera:ScreenPointToRay(input.Position.X, input.Position.Y)
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {getChar() or workspace}
            local result = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
            if result then
                local root = getRoot()
                if root then
                    root.CFrame = CFrame.new(result.Position + Vector3.new(0,3,0))
                end
            end
        end
    end)
end

local function stopTeleport()
    CFG.TeleportMode = false
    if tpClick then tpClick:Disconnect(); tpClick = nil end
end

---------------------------------------------------------------------------
-- ANTI-KICK
---------------------------------------------------------------------------
local antiKickConns = {}

local function setupAntiKick()
    local KW = {"kick","ban","remove","disconnect","anticheat","ac"}
    local function block(obj)
        if not obj:IsA("RemoteEvent") then return end
        local name = obj.Name:lower()
        for _, kw in ipairs(KW) do
            if name:find(kw) then
                table.insert(antiKickConns, obj.OnClientEvent:Connect(function() end))
            end
        end
    end
    for _, obj in ipairs(game:GetDescendants()) do block(obj) end
    table.insert(antiKickConns, game.DescendantAdded:Connect(function(obj)
        task.wait(0.1); block(obj)
    end))
    pcall(function()
        local mt = getmetatable(LocalPlayer)
        if mt and mt.__index then
            local old = mt.__index.Kick
            mt.__index.Kick = function(self, ...)
                if self == LocalPlayer and CFG.AntiKick then return end
                return old(self, ...)
            end
        end
    end)
end

local function stopAntiKick()
    for _, c in ipairs(antiKickConns) do pcall(function() c:Disconnect() end) end
    table.clear(antiKickConns)
end

---------------------------------------------------------------------------
-- MAIN LOOPS
---------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
    doAimbot()
    for _, p in ipairs(Players:GetPlayers()) do renderPlayerESP(p) end
end)

local lootTimer = 0
RunService.Heartbeat:Connect(function(dt)
    lootTimer = lootTimer + dt
    if lootTimer >= 0.5 then lootTimer = 0; renderLootESP() end
    if CFG.HitboxEnabled then refreshHitboxes() end
end)

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.8)
    watchTools()
    if CFG.AutoHeal then startAutoHeal() end
    if CFG.NoRecoil then startNoRecoil() end
end)
task.wait(0.5); watchTools()

---------------------------------------------------------------------------
-- UI HELPERS
---------------------------------------------------------------------------
local function mkCorner(p, r)
    Instance.new("UICorner", p).CornerRadius = UDim.new(0, r or 6)
end
local function mkStroke(p, col, t)
    local s = Instance.new("UIStroke", p)
    s.Color = col or CFG.Accent; s.Thickness = t or 1
end
local function mkLabel(parent, text, size, color, font, xa, pos, sz)
    local l = Instance.new("TextLabel")
    l.Text = text; l.TextSize = size
    l.TextColor3 = color or Color3.fromRGB(220,220,220)
    l.Font = font or Enum.Font.Gotham
    l.BackgroundTransparency = 1
    l.TextXAlignment = xa or Enum.TextXAlignment.Left
    l.Position = pos or UDim2.new(0,0,0,0)
    l.Size = sz or UDim2.new(1,0,1,0)
    l.Parent = parent; return l
end

---------------------------------------------------------------------------
-- SCREEN GUI
---------------------------------------------------------------------------
local sg = Instance.new("ScreenGui")
sg.Name           = "SniperArenaProV2"
sg.ResetOnSpawn   = false
sg.DisplayOrder   = 999
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent         = LocalPlayer:WaitForChild("PlayerGui")

local WIN_W, WIN_H = 300, 580
local win = Instance.new("Frame")
win.Size             = UDim2.new(0, WIN_W, 0, WIN_H)
win.Position         = UDim2.fromScale(0.36, 0.08)
win.BackgroundColor3 = CFG.BG
win.BorderSizePixel  = 0
win.ClipsDescendants = true
win.Parent           = sg
mkCorner(win, 8); mkStroke(win, CFG.Accent, 1)

-- header
local hdr = Instance.new("Frame")
hdr.Size             = UDim2.new(1,0,0,32)
hdr.BackgroundColor3 = CFG.BtnBG
hdr.BorderSizePixel  = 0
hdr.Parent           = win
mkCorner(hdr, 8)
local hf = Instance.new("Frame")
hf.Size             = UDim2.new(1,0,0,8)
hf.Position         = UDim2.new(0,0,1,-8)
hf.BackgroundColor3 = CFG.BtnBG
hf.BorderSizePixel  = 0
hf.Parent           = hdr
mkLabel(hdr, "  🎯 SNIPER ARENA PRO v2", 12, CFG.Accent, Enum.Font.GothamBold,
    Enum.TextXAlignment.Left, UDim2.new(0,0,0,0), UDim2.new(1,-56,1,0))

local minBtn = Instance.new("TextButton")
minBtn.Size             = UDim2.new(0,24,0,24)
minBtn.Position         = UDim2.new(1,-52,0.5,-12)
minBtn.BackgroundColor3 = CFG.BG
minBtn.Text             = "—"
minBtn.TextColor3       = Color3.fromRGB(180,180,180)
minBtn.Font             = Enum.Font.GothamBold
minBtn.TextSize         = 12
minBtn.BorderSizePixel  = 0
minBtn.Parent           = hdr
mkCorner(minBtn, 4)

local closeBtn = Instance.new("TextButton")
closeBtn.Size             = UDim2.new(0,24,0,24)
closeBtn.Position         = UDim2.new(1,-24,0.5,-12)
closeBtn.BackgroundColor3 = CFG.BG
closeBtn.Text             = "✕"
closeBtn.TextColor3       = Color3.fromRGB(220,70,70)
closeBtn.Font             = Enum.Font.GothamBold
closeBtn.TextSize         = 12
closeBtn.BorderSizePixel  = 0
closeBtn.Parent           = hdr
mkCorner(closeBtn, 4)

-- tab bar
local tabBar = Instance.new("Frame")
tabBar.Size             = UDim2.new(1,0,0,28)
tabBar.Position         = UDim2.new(0,0,0,32)
tabBar.BackgroundColor3 = CFG.BG
tabBar.BorderSizePixel  = 0
tabBar.Parent           = win
local tabL = Instance.new("UIListLayout", tabBar)
tabL.FillDirection = Enum.FillDirection.Horizontal
tabL.SortOrder     = Enum.SortOrder.LayoutOrder
tabL.Padding       = UDim.new(0,3)
local tabP = Instance.new("UIPadding", tabBar)
tabP.PaddingLeft = UDim.new(0,6)
tabP.PaddingTop  = UDim.new(0,4)

-- scroll
local scroll = Instance.new("ScrollingFrame")
scroll.Size                = UDim2.new(1,0,1,-62)
scroll.Position            = UDim2.new(0,0,0,62)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel     = 0
scroll.ScrollBarThickness  = 3
scroll.ScrollBarImageColor3 = CFG.Accent
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize          = UDim2.new(0,0,0,0)
scroll.Parent              = win
local scL = Instance.new("UIListLayout", scroll)
scL.SortOrder = Enum.SortOrder.LayoutOrder
scL.Padding   = UDim.new(0,4)
local scP = Instance.new("UIPadding", scroll)
scP.PaddingLeft  = UDim.new(0,10)
scP.PaddingRight = UDim.new(0,10)
scP.PaddingTop   = UDim.new(0,8)

---------------------------------------------------------------------------
-- COMPONENT FACTORIES
---------------------------------------------------------------------------
local oN = 0
local function nO() oN = oN + 1; return oN end
local pages = {Aimbot={}, Combat={}, ESP={}, Utility={}}

local function mkSection(text, page)
    local f = Instance.new("Frame")
    f.Size               = UDim2.new(1,-10,0,20)
    f.BackgroundTransparency = 1
    f.LayoutOrder        = nO()
    f.Parent             = scroll
    local line = Instance.new("Frame")
    line.Size             = UDim2.new(1,0,0,1)
    line.Position         = UDim2.new(0,0,0.5,0)
    line.BackgroundColor3 = CFG.BtnBG
    line.BorderSizePixel  = 0
    line.Parent           = f
    local lbl = Instance.new("TextLabel")
    lbl.Text          = " "..text.." "
    lbl.TextColor3    = CFG.Accent
    lbl.BackgroundColor3 = CFG.BG
    lbl.AutomaticSize = Enum.AutomaticSize.X
    lbl.Size          = UDim2.new(0,0,1,0)
    lbl.Position      = UDim2.new(0,10,0,0)
    lbl.Font          = Enum.Font.GothamBold
    lbl.TextSize      = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent        = f
    if page then table.insert(pages[page], f) end
end

local function mkToggle(label, init, cb, page)
    local row = Instance.new("Frame")
    row.Size             = UDim2.new(1,-10,0,34)
    row.BackgroundColor3 = CFG.BtnBG
    row.BorderSizePixel  = 0
    row.LayoutOrder      = nO()
    row.Parent           = scroll
    mkCorner(row, 6)
    mkLabel(row, label, 12, Color3.fromRGB(220,220,220), Enum.Font.Gotham,
        Enum.TextXAlignment.Left, UDim2.new(0,10,0,0), UDim2.new(1,-54,1,0))
    local pill = Instance.new("Frame")
    pill.Size             = UDim2.new(0,38,0,20)
    pill.Position         = UDim2.new(1,-46,0.5,-10)
    pill.BackgroundColor3 = init and CFG.Accent or Color3.fromHex("3A3A4A")
    pill.BorderSizePixel  = 0
    pill.Parent           = row
    mkCorner(pill, 12)
    local knob = Instance.new("Frame")
    knob.Size             = UDim2.new(0,14,0,14)
    knob.Position         = init and UDim2.new(1,-17,0.5,-7) or UDim2.new(0,3,0.5,-7)
    knob.BackgroundColor3 = Color3.fromRGB(255,255,255)
    knob.BorderSizePixel  = 0
    knob.Parent           = pill
    mkCorner(knob, 7)
    local state = init
    local function setState(v)
        state = v
        TweenService:Create(pill, TweenInfo.new(0.15), {
            BackgroundColor3 = v and CFG.Accent or Color3.fromHex("3A3A4A")
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = v and UDim2.new(1,-17,0.5,-7) or UDim2.new(0,3,0.5,-7)
        }):Play()
    end
    local btn = Instance.new("TextButton")
    btn.Size               = UDim2.new(1,0,1,0)
    btn.BackgroundTransparency = 1
    btn.Text               = ""
    btn.Parent             = row
    btn.MouseButton1Click:Connect(function()
        setState(not state); cb(state)
    end)
    if page then table.insert(pages[page], row) end
    return setState
end

local function mkSlider(label, minV, maxV, init, fmt, cb, page)
    local row = Instance.new("Frame")
    row.Size             = UDim2.new(1,-10,0,52)
    row.BackgroundColor3 = CFG.BtnBG
    row.BorderSizePixel  = 0
    row.LayoutOrder      = nO()
    row.Parent           = scroll
    mkCorner(row, 6)
    local topRow = Instance.new("Frame")
    topRow.Size                = UDim2.new(1,0,0,26)
    topRow.BackgroundTransparency = 1
    topRow.Parent              = row
    mkLabel(topRow, label, 12, Color3.fromRGB(220,220,220), Enum.Font.Gotham,
        Enum.TextXAlignment.Left, UDim2.new(0,10,0,0), UDim2.new(0.7,0,1,0))
    local vLbl = Instance.new("TextLabel")
    vLbl.Text             = string.format(fmt, init)
    vLbl.TextColor3       = CFG.Accent
    vLbl.Font             = Enum.Font.GothamBold
    vLbl.TextSize         = 11
    vLbl.BackgroundTransparency = 1
    vLbl.Size             = UDim2.new(0.3,0,1,0)
    vLbl.Position         = UDim2.new(0.7,0,0,0)
    vLbl.TextXAlignment   = Enum.TextXAlignment.Right
    Instance.new("UIPadding", vLbl).PaddingRight = UDim.new(0,10)
    vLbl.Parent           = topRow
    local track = Instance.new("Frame")
    track.Size             = UDim2.new(1,-20,0,6)
    track.Position         = UDim2.new(0,10,0,30)
    track.BackgroundColor3 = Color3.fromHex("2A2A3A")
    track.BorderSizePixel  = 0
    track.Parent           = row
    mkCorner(track, 3)
    local fill = Instance.new("Frame")
    fill.Size             = UDim2.new((init-minV)/(maxV-minV),0,1,0)
    fill.BackgroundColor3 = CFG.Accent
    fill.BorderSizePixel  = 0
    fill.Parent           = track
    mkCorner(fill, 3)
    local thumb = Instance.new("Frame")
    thumb.Size             = UDim2.new(0,14,0,14)
    thumb.AnchorPoint      = Vector2.new(0.5,0.5)
    thumb.Position         = UDim2.new((init-minV)/(maxV-minV),0,0.5,0)
    thumb.BackgroundColor3 = Color3.fromRGB(255,255,255)
    thumb.BorderSizePixel  = 0
    thumb.Parent           = track
    mkCorner(thumb, 7)
    local drag = false
    local function upd(x)
        local pct = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local val = math.floor((minV + (maxV-minV)*pct) * 100 + 0.5) / 100
        fill.Size      = UDim2.new(pct, 0, 1, 0)
        thumb.Position = UDim2.new(pct, 0, 0.5, 0)
        vLbl.Text      = string.format(fmt, val)
        cb(val)
    end
    local hb = Instance.new("TextButton")
    hb.Size               = UDim2.new(1,0,1,0)
    hb.BackgroundTransparency = 1
    hb.Text               = ""
    hb.Parent             = track
    hb.MouseButton1Down:Connect(function(x) drag = true; upd(x) end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
            upd(i.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
    end)
    if page then table.insert(pages[page], row) end
end

local function mkDropdown(label, opts, init, cb, page)
    local row = Instance.new("Frame")
    row.Size             = UDim2.new(1,-10,0,34)
    row.BackgroundColor3 = CFG.BtnBG
    row.BorderSizePixel  = 0
    row.LayoutOrder      = nO()
    row.Parent           = scroll
    mkCorner(row, 6)
    row.ClipsDescendants = false
    mkLabel(row, label, 12, Color3.fromRGB(220,220,220), Enum.Font.Gotham,
        Enum.TextXAlignment.Left, UDim2.new(0,10,0,0), UDim2.new(0.5,0,1,0))
    local btn = Instance.new("TextButton")
    btn.Size             = UDim2.new(0.46,0,0,26)
    btn.Position         = UDim2.new(0.52,0,0.5,-13)
    btn.BackgroundColor3 = Color3.fromHex("09090D")
    btn.Text             = init
    btn.TextColor3       = CFG.Accent
    btn.Font             = Enum.Font.Gotham
    btn.TextSize         = 11
    btn.BorderSizePixel  = 0
    btn.Parent           = row
    mkCorner(btn, 4); mkStroke(btn, CFG.Accent, 1)
    local df = Instance.new("Frame")
    df.Size             = UDim2.new(0.46,0,0,#opts*28+4)
    df.Position         = UDim2.new(0.52,0,1,2)
    df.BackgroundColor3 = Color3.fromHex("1C1C26")
    df.BorderSizePixel  = 0
    df.Visible          = false
    df.ZIndex           = 20
    df.Parent           = row
    mkCorner(df, 4); mkStroke(df, CFG.Accent, 1)
    for i, opt in ipairs(opts) do
        local item = Instance.new("TextButton")
        item.Size               = UDim2.new(1,0,0,26)
        item.Position           = UDim2.new(0,0,0,(i-1)*28+2)
        item.BackgroundTransparency = 1
        item.Text               = opt
        item.TextColor3         = Color3.fromRGB(210,210,210)
        item.Font               = Enum.Font.Gotham
        item.TextSize           = 11
        item.ZIndex             = 21
        item.Parent             = df
        item.MouseButton1Click:Connect(function()
            btn.Text = opt; df.Visible = false; cb(opt)
        end)
        item.MouseEnter:Connect(function()
            item.BackgroundTransparency = 0.7
            item.BackgroundColor3       = CFG.Accent
        end)
        item.MouseLeave:Connect(function()
            item.BackgroundTransparency = 1
        end)
    end
    btn.MouseButton1Click:Connect(function()
        df.Visible = not df.Visible
    end)
    if page then table.insert(pages[page], row) end
end

---------------------------------------------------------------------------
-- POPULATE — AIMBOT TAB
---------------------------------------------------------------------------
mkSection("AIMBOT", "Aimbot")
mkToggle("Enable Aimbot",    CFG.Aimbot,         function(v) CFG.Aimbot         = v end, "Aimbot")
mkToggle("Hold RMB to Aim",  CFG.AimbotHoldMode, function(v) CFG.AimbotHoldMode = v end, "Aimbot")
mkToggle("Silent Aim (Camera)", CFG.SilentAim,   function(v) CFG.SilentAim      = v end, "Aimbot")
mkDropdown("Target Bone",
    {"Head","UpperTorso","HumanoidRootPart"},
    "Head",
    function(v) CFG.AimbotBone = v end,
    "Aimbot"
)
mkSection("AIM TUNING", "Aimbot")
mkSlider("FOV Radius",    30,  500, CFG.AimbotFOV,    "%.0f px",
    function(v) CFG.AimbotFOV    = v end, "Aimbot")
mkSlider("Smooth",        0.01, 0.5, CFG.AimbotSmooth, "%.3f",
    function(v) CFG.AimbotSmooth = v end, "Aimbot")
mkSlider("Head Offset Y", 0,   1,   CFG.HeadOffset.Y, "%.2f st",
    function(v) CFG.HeadOffset = Vector3.new(0, v, 0) end, "Aimbot")
mkSlider("Max Distance",  100, 5000, CFG.AimbotMaxDist, "%.0f st",
    function(v) CFG.AimbotMaxDist = v end, "Aimbot")

---------------------------------------------------------------------------
-- POPULATE — COMBAT TAB
---------------------------------------------------------------------------
mkSection("HITBOX", "Combat")
mkToggle("Hitbox Expander", CFG.HitboxEnabled,
    function(v) CFG.HitboxEnabled = v; refreshHitboxes() end, "Combat")
mkSlider("Hitbox Size", 2, 20, CFG.HitboxSize, "%.1f",
    function(v) CFG.HitboxSize = v end, "Combat")

mkSection("WEAPON", "Combat")
mkToggle("No Recoil",   CFG.NoRecoil,
    function(v) CFG.NoRecoil = v; if v then startNoRecoil() end end, "Combat")
mkToggle("Fast Reload", CFG.FastReload,
    function(v) CFG.FastReload = v end, "Combat")
mkSlider("Reload Speed", 0.05, 1, CFG.ReloadMult, "%.2fx",
    function(v) CFG.ReloadMult = v end, "Combat")

mkSection("HEAL", "Combat")
mkToggle("Auto Heal", CFG.AutoHeal,
    function(v) CFG.AutoHeal = v; if v then startAutoHeal() end end, "Combat")
mkSlider("Heal Threshold", 10, 99, CFG.HealThreshold, "%.0f HP",
    function(v) CFG.HealThreshold = v end, "Combat")
mkSlider("Heal To",        50, 100, CFG.HealAmount,    "%.0f HP",
    function(v) CFG.HealAmount = v end, "Combat")

---------------------------------------------------------------------------
-- POPULATE — ESP TAB
---------------------------------------------------------------------------
mkSection("PLAYER ESP", "ESP")
mkToggle("Player ESP",          CFG.PlayerESP,
    function(v) CFG.PlayerESP = v end, "ESP")
mkToggle("Enemy Only",          CFG.EnemyOnly,
    function(v) CFG.EnemyOnly = v end, "ESP")
mkSection("LOOT ESP", "ESP")
mkToggle("Loot ESP + Tracers",  CFG.LootESP,
    function(v) CFG.LootESP = v; if not v then clearLootESP() end end, "ESP")
mkSlider("Max Distance", 100, 5000, CFG.ESPMaxDist, "%.0f m",
    function(v) CFG.ESPMaxDist = v end, "ESP")

---------------------------------------------------------------------------
-- POPULATE — UTILITY TAB
---------------------------------------------------------------------------
mkSection("TELEPORT", "Utility")
mkToggle("Tactical Teleport (LMB)", CFG.TeleportMode,
    function(v) CFG.TeleportMode = v
        if v then startTeleport() else stopTeleport() end
    end, "Utility")
mkSection("PROTECTION", "Utility")
mkToggle("Anti-Kick", CFG.AntiKick,
    function(v) CFG.AntiKick = v
        if v then setupAntiKick() else stopAntiKick() end
    end, "Utility")

---------------------------------------------------------------------------
-- TABS
---------------------------------------------------------------------------
local tabBtns = {}
local function switchTab(name)
    for pg, items in pairs(pages) do
        for _, item in ipairs(items) do item.Visible = (pg == name) end
    end
    for tname, tbtn in pairs(tabBtns) do
        tbtn.BackgroundColor3 = tname == name and CFG.Accent or CFG.BtnBG
        tbtn.TextColor3       = tname == name
            and Color3.fromRGB(255,255,255) or Color3.fromRGB(160,160,160)
    end
end

for i, tname in ipairs({"Aimbot","Combat","ESP","Utility"}) do
    local tb = Instance.new("TextButton")
    tb.Size             = UDim2.new(0,64,0,22)
    tb.BackgroundColor3 = CFG.BtnBG
    tb.Text             = tname
    tb.TextColor3       = Color3.fromRGB(160,160,160)
    tb.Font             = Enum.Font.GothamBold
    tb.TextSize         = 10
    tb.BorderSizePixel  = 0
    tb.LayoutOrder      = i
    tb.Parent           = tabBar
    mkCorner(tb, 4)
    tabBtns[tname] = tb
    tb.MouseButton1Click:Connect(function() switchTab(tname) end)
end
switchTab("Aimbot")

---------------------------------------------------------------------------
-- WINDOW DRAG
---------------------------------------------------------------------------
local wDrag, wDS, wSP = false, nil, nil
hdr.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        wDrag = true; wDS = i.Position; wSP = win.Position
    end
end)
hdr.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then wDrag = false end
end)
UserInputService.InputChanged:Connect(function(i)
    if wDrag and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - wDS
        win.Position = UDim2.new(
            wSP.X.Scale, wSP.X.Offset + d.X,
            wSP.Y.Scale, wSP.Y.Offset + d.Y
        )
    end
end)

---------------------------------------------------------------------------
-- MINIMIZE / CLOSE / REOPEN
---------------------------------------------------------------------------
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    TweenService:Create(win, TweenInfo.new(0.18, Enum.EasingStyle.Quint), {
        Size = UDim2.new(0, WIN_W, 0, minimized and 32 or WIN_H)
    }):Play()
    minBtn.Text = minimized and "□" or "—"
end)

closeBtn.MouseButton1Click:Connect(function() win.Visible = false end)

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.Insert then
        win.Visible = not win.Visible
        if win.Visible then
            minimized = false
            win.Size  = UDim2.new(0, WIN_W, 0, WIN_H)
            minBtn.Text = "—"
        end
    end
    if input.KeyCode == Enum.KeyCode.CapsLock then
        CFG.Aimbot = not CFG.Aimbot
    end
end)

---------------------------------------------------------------------------
-- STATUS HUD
---------------------------------------------------------------------------
local hudSG = Instance.new("ScreenGui")
hudSG.Name         = "SniperHUDv2"
hudSG.ResetOnSpawn = false
hudSG.DisplayOrder = 998
hudSG.Parent       = LocalPlayer:WaitForChild("PlayerGui")

local hudF = Instance.new("Frame")
hudF.Size                 = UDim2.new(0, 340, 0, 38)
hudF.Position             = UDim2.fromScale(0.5, 0.93)
hudF.AnchorPoint          = Vector2.new(0.5, 0)
hudF.BackgroundColor3     = CFG.BG
hudF.BackgroundTransparency = 0.2
hudF.BorderSizePixel      = 0
hudF.Parent               = hudSG
mkCorner(hudF, 6)

local hudAcc = Instance.new("Frame")
hudAcc.Size             = UDim2.new(1,0,0,2)
hudAcc.BackgroundColor3 = CFG.Accent
hudAcc.BorderSizePixel  = 0
hudAcc.Parent           = hudF

local hudLbl = Instance.new("TextLabel")
hudLbl.BackgroundTransparency = 1
hudLbl.Size             = UDim2.new(1,0,1,0)
hudLbl.Font             = Enum.Font.Gotham
hudLbl.TextSize         = 10
hudLbl.TextColor3       = Color3.fromRGB(210,210,210)
hudLbl.TextXAlignment   = Enum.TextXAlignment.Center
hudLbl.Parent           = hudF

RunService.Heartbeat:Connect(function()
    hudLbl.Text = string.format(
        "Aim:%s(%s) ESP:%s EOnly:%s Hitbox:%s Reload:%s AK:%s | CapsLock=Aim",
        CFG.Aimbot         and "ON" or "OFF", CFG.AimbotBone,
        CFG.PlayerESP      and "ON" or "OFF",
        CFG.EnemyOnly      and "ON" or "OFF",
        CFG.HitboxEnabled  and "ON" or "OFF",
        CFG.FastReload     and "ON" or "OFF",
        CFG.AntiKick       and "ON" or "OFF"
    )
end)

print("[Sniper Arena Pro v2] loaded — INSERT UI | CapsLock Aimbot | RMB hold aim")

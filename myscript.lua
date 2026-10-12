--[[
  Sniper Arena Pro
  Features:
    - Hitbox Expander      (ขยาย hitbox ศัตรู)
    - No Recoil            (ล็อค camera recoil)
    - Fast Reload          (ลด reload time)
    - Auto Heal            (heal อัตโนมัติ)
    - Player ESP           (box + name + dist + health)
    - Loot ESP             (แสดง item/loot บนแผนที่)
    - Tactical Teleport    (คลิกจุด teleport ทันที)
    - Anti-Kick            (ป้องกัน kick/ban จาก server)
  Keys: INSERT = show/hide | tab ด้านบน = เลือกหมวด
]]

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

---------------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------------
local CFG = {
    -- Hitbox
    HitboxEnabled  = false,
    HitboxSize     = 8,      -- studs, default char = ~3

    -- No Recoil
    NoRecoil       = false,

    -- Fast Reload
    FastReload     = false,
    ReloadMult     = 0.1,    -- 0.1 = 10x ไว กว่าปกติ

    -- Auto Heal
    AutoHeal       = false,
    HealThreshold  = 60,     -- heal เมื่อ HP ต่ำกว่านี้
    HealAmount     = 100,    -- heal เป็น HP นี้

    -- ESP
    PlayerESP      = false,
    LootESP        = false,
    ESPMaxDist     = 2000,

    -- Teleport
    TeleportMode   = false,  -- click on screen → teleport

    -- Anti-Kick
    AntiKick       = false,

    Accent  = Color3.fromHex("8B5CF6"),
    BG      = Color3.fromHex("09090D"),
    BtnBG   = Color3.fromHex("1C1C26"),
    EnemyC  = Color3.fromRGB(255, 75, 75),
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

---------------------------------------------------------------------------
-- 1. HITBOX EXPANDER
-- ขยาย HumanoidRootPart ของทุก player ใน client side
-- ทำให้ยิงโดน target ง่ายขึ้น แม้ aim ไม่ตรงหัวพอดี
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
    if hitboxConns[player.UserId] then
        hitboxConns[player.UserId]:Disconnect()
    end
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
                        root.Size = Vector3.new(CFG.HitboxSize, CFG.HitboxSize, CFG.HitboxSize)
                        root.Transparency = 0.8
                        root.CanCollide = false
                    else
                        root.Size = Vector3.new(2, 2, 1)
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
-- 2. NO RECOIL
-- lock Camera CFrame Y-axis ไม่ให้กระเด้งขึ้น
---------------------------------------------------------------------------
local lastCamCF = nil
local noRecoilConn = nil

local function startNoRecoil()
    if noRecoilConn then noRecoilConn:Disconnect() end
    lastCamCF = Camera.CFrame
    noRecoilConn = RunService.RenderStepped:Connect(function()
        if not CFG.NoRecoil then
            noRecoilConn:Disconnect(); noRecoilConn = nil; return
        end
        -- ล็อค pitch (X rotation) ไม่ให้กระเด้งขึ้น
        local cur = Camera.CFrame
        local rx, ry, rz = cur:ToEulerAnglesYXZ()
        if lastCamCF then
            local lx, ly, lz = lastCamCF:ToEulerAnglesYXZ()
            -- ถ้า pitch กระเด้ง ให้ reset กลับ
            if math.abs(rx - lx) > 0.01 and not UserInputService:IsMouseButtonPressed(
                Enum.UserInputType.MouseButton2) then
                Camera.CFrame = CFrame.new(cur.Position)
                    * CFrame.fromEulerAnglesYXZ(lx, ry, rz)
            end
        end
        lastCamCF = Camera.CFrame
    end)
end

---------------------------------------------------------------------------
-- 3. FAST RELOAD
-- hook Tool.Activated → manipulate AnimationTrack speed
-- Sniper Arena reload อยู่ใน Tool script — เราเพิ่ม speed animation
---------------------------------------------------------------------------
local reloadConns = {}

local function hookReload(tool)
    if not tool:IsA("Tool") then return end
    -- หา AnimationController หรือ Humanoid animation
    local char = getChar()
    if not char then return end
    local human = getHuman()
    if not human then return end

    local animator = human:FindFirstChildOfClass("Animator")
    if not animator then return end

    local conn = animator.AnimationPlayed:Connect(function(track)
        -- reload animation มักมีชื่อ reload หรือ speed < 1
        local name = track.Name:lower()
        if name:find("reload") or name:find("recharge") or name:find("chamber") then
            if CFG.FastReload then
                track:AdjustSpeed(1 / CFG.ReloadMult)
            end
        end
    end)
    table.insert(reloadConns, conn)
end

local function watchTools()
    local char = getChar(); if not char then return end
    for _, tool in ipairs(char:GetChildren()) do hookReload(tool) end
    char.ChildAdded:Connect(function(child)
        task.wait(0.1); hookReload(child)
    end)
end

---------------------------------------------------------------------------
-- 4. AUTO HEAL
-- Sniper Arena มี heal item หรือ regen — เราจับ Humanoid.Health แล้ว
-- fire RemoteEvent heal ถ้าเจอ หรือ set health โดยตรง (depends on game)
---------------------------------------------------------------------------
local autoHealConn = nil

local function startAutoHeal()
    if autoHealConn then autoHealConn:Disconnect() end
    autoHealConn = RunService.Heartbeat:Connect(function()
        if not CFG.AutoHeal then return end
        local h = getHuman(); if not h then return end
        if h.Health < CFG.HealThreshold and h.Health > 0 then
            -- method 1: set directly (works if server doesn't validate)
            h.Health = math.min(h.Health + 2, CFG.HealAmount)
            -- method 2: try fire heal remote if exists
            local remote = ReplicatedStorage:FindFirstChild("Heal")
                or ReplicatedStorage:FindFirstChild("UseHeal")
                or ReplicatedStorage:FindFirstChild("HealPlayer")
            if remote and remote:IsA("RemoteEvent") then
                remote:FireServer()
            end
        end
    end)
end

---------------------------------------------------------------------------
-- 5. DRAWING POOL
---------------------------------------------------------------------------
local pool = {}
local function drw(pid, key, dtype)
    if not pool[pid] then pool[pid] = {} end
    if not pool[pid][key] then
        local d = Drawing.new(dtype); d.Visible = false; pool[pid][key] = d
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
-- 6. PLAYER ESP
---------------------------------------------------------------------------
local function renderPlayerESP(player)
    if player == LocalPlayer then return end
    local char  = player.Character
    local pid   = "p"..player.UserId
    local keys  = {"bT","bB","bL","bR","name","dist","hpBg","hp"}
    local function hide()
        for _,k in ipairs(keys) do
            local d=pool[pid] and pool[pid][k]; if d then d.Visible=false end
        end
    end
    if not char or not CFG.PlayerESP then hide(); return end
    local root  = char:FindFirstChild("HumanoidRootPart")
    local human = char:FindFirstChildOfClass("Humanoid")
    if not root or not human or not isAlive(char) then hide(); return end

    local lr = getRoot()
    if lr and (lr.Position-root.Position).Magnitude > CFG.ESPMaxDist then hide(); return end

    local head   = char:FindFirstChild("Head")
    local topPos = head and (head.Position+Vector3.new(0,0.7,0)) or (root.Position+Vector3.new(0,3.2,0))
    local botPos = root.Position - Vector3.new(0,3,0)
    local topS,topV = w2s(topPos)
    local botS      = w2s(botPos)
    if not topV then hide(); return end

    local boxH = math.max(math.abs(topS.Y-botS.Y),1)
    local boxW = boxH * 0.44
    local L,R  = topS.X-boxW/2, topS.X+boxW/2
    local T,B  = topS.Y, botS.Y
    local col  = CFG.EnemyC

    local segs = {
        {"bT",Vector2.new(L,T),Vector2.new(R,T)},
        {"bB",Vector2.new(L,B),Vector2.new(R,B)},
        {"bL",Vector2.new(L,T),Vector2.new(L,B)},
        {"bR",Vector2.new(R,T),Vector2.new(R,B)},
    }
    for _,s in ipairs(segs) do
        local d=drw(pid,s[1],"Line")
        d.From=s[2]; d.To=s[3]; d.Color=col; d.Thickness=1.2; d.Visible=true
    end

    -- health bar
    local hp  = math.clamp(human.Health/math.max(human.MaxHealth,1),0,1)
    local bx  = L-6
    local hpC = Color3.fromRGB(math.floor(255*(1-hp)),math.floor(255*hp),0)
    local bg  = drw(pid,"hpBg","Line")
    bg.From=Vector2.new(bx,T); bg.To=Vector2.new(bx,B)
    bg.Color=Color3.fromRGB(25,25,25); bg.Thickness=4; bg.Visible=true
    local hb  = drw(pid,"hp","Line")
    hb.From=Vector2.new(bx,B); hb.To=Vector2.new(bx,B-boxH*hp)
    hb.Color=hpC; hb.Thickness=3; hb.Visible=true

    -- name
    local nd=drw(pid,"name","Text")
    nd.Text=player.Name; nd.Position=Vector2.new(topS.X,T-14)
    nd.Size=13; nd.Color=Color3.fromRGB(255,255,255)
    nd.Outline=true; nd.Center=true; nd.Visible=true

    -- dist
    local dist = lr and (lr.Position-root.Position).Magnitude or 0
    local dd=drw(pid,"dist","Text")
    dd.Text=string.format("%.0fm",dist); dd.Position=Vector2.new(topS.X,B+3)
    dd.Size=11; dd.Color=Color3.fromRGB(190,190,190)
    dd.Outline=true; dd.Center=true; dd.Visible=true
end

---------------------------------------------------------------------------
-- 7. LOOT ESP
-- scan workspace ด้วย keyword ที่มักใช้ใน Sniper Arena
---------------------------------------------------------------------------
local lootDrawings = {}
local LOOT_KEYWORDS = {
    "ammo","medkit","heal","health","crate","pickup","item",
    "loot","supply","gun","rifle","sniper","pistol","grenade","coin","cash","gem"
}

local function isLoot(obj)
    if not obj:IsA("BasePart") and not obj:IsA("Model") then return false end
    local name = obj.Name:lower()
    for _, kw in ipairs(LOOT_KEYWORDS) do
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
    -- clear old
    for id, d in pairs(lootDrawings) do
        local ok, _ = pcall(function() return d.line.Visible end)
        if not ok then lootDrawings[id] = nil end
    end

    if not CFG.LootESP then
        clearLootESP(); return
    end

    local lr = getRoot()
    local scanned = {}

    for _, obj in ipairs(workspace:GetDescendants()) do
        if isLoot(obj) then
            local pos
            if obj:IsA("BasePart") then
                pos = obj.Position
            elseif obj:IsA("Model") and obj.PrimaryPart then
                pos = obj.PrimaryPart.Position
            end
            if pos then
                local dist = lr and (lr.Position-pos).Magnitude or 0
                if dist < CFG.ESPMaxDist then
                    local sp, onSc = w2s(pos)
                    local id = tostring(obj)
                    scanned[id] = true
                    if not lootDrawings[id] then
                        local line  = Drawing.new("Line")
                        local label = Drawing.new("Text")
                        lootDrawings[id] = {line=line, label=label}
                    end
                    local ld = lootDrawings[id]
                    if onSc then
                        local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
                        -- tracer line from bottom center → loot
                        ld.line.From    = Vector2.new(center.X, Camera.ViewportSize.Y)
                        ld.line.To      = sp
                        ld.line.Color   = CFG.LootC
                        ld.line.Thickness = 1
                        ld.line.Transparency = 0.6
                        ld.line.Visible = true
                        ld.label.Text     = obj.Name.." ["..string.format("%.0f",dist).."m]"
                        ld.label.Position = Vector2.new(sp.X, sp.Y-14)
                        ld.label.Size     = 11
                        ld.label.Color    = CFG.LootC
                        ld.label.Outline  = true
                        ld.label.Center   = true
                        ld.label.Visible  = true
                    else
                        ld.line.Visible  = false
                        ld.label.Visible = false
                    end
                end
            end
        end
    end

    -- hide loot ที่หายไปแล้ว
    for id, ld in pairs(lootDrawings) do
        if not scanned[id] then
            pcall(function() ld.line.Visible=false; ld.label.Visible=false end)
        end
    end
end

---------------------------------------------------------------------------
-- 8. TACTICAL TELEPORT
-- Mouse click บนพื้น → teleport ไปจุดนั้นทันที
---------------------------------------------------------------------------
local tpClick = nil

local function startTeleport()
    if tpClick then tpClick:Disconnect() end
    tpClick = UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if not CFG.TeleportMode then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local unitRay = Camera:ScreenPointToRay(input.Position.X, input.Position.Y)
            local params  = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {getChar() or workspace}
            local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, params)
            if result then
                local root = getRoot()
                if root then
                    root.CFrame = CFrame.new(result.Position + Vector3.new(0, 3, 0))
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
-- 9. ANTI-KICK
-- ป้องกัน server kick ด้วยการ hook RemoteEvent / BindableEvent ที่ชื่อ kick
-- และ block Player:Kick() call จาก LocalScript
---------------------------------------------------------------------------
local antiKickConn = {}

local function setupAntiKick()
    -- hook ทุก RemoteEvent ที่ชื่อคล้าย kick/ban/remove
    local KICK_KEYWORDS = {"kick","ban","remove","disconnect","anticheat","ac"}
    local function blockRemote(obj)
        if not obj:IsA("RemoteEvent") and not obj:IsA("RemoteFunction") then return end
        local name = obj.Name:lower()
        for _, kw in ipairs(KICK_KEYWORDS) do
            if name:find(kw) then
                -- hook OnClientEvent แล้ว ignore
                if obj:IsA("RemoteEvent") then
                    local conn = obj.OnClientEvent:Connect(function()
                        -- ไม่ทำอะไร — block kick event
                    end)
                    table.insert(antiKickConn, conn)
                end
            end
        end
    end

    -- scan existing
    for _, obj in ipairs(game:GetDescendants()) do blockRemote(obj) end
    -- watch new
    local conn = game.DescendantAdded:Connect(function(obj)
        task.wait(0.1); blockRemote(obj)
    end)
    table.insert(antiKickConn, conn)

    -- hook LocalPlayer:Kick() — replace method
    local mt = getmetatable(LocalPlayer)
    if mt and mt.__index then
        local oldKick = mt.__index.Kick
        mt.__index.Kick = function(self, ...)
            if self == LocalPlayer and CFG.AntiKick then
                warn("[AntiKick] Kick blocked")
                return
            end
            return oldKick(self, ...)
        end
    end

    print("[AntiKick] active")
end

local function stopAntiKick()
    for _, c in ipairs(antiKickConn) do pcall(function() c:Disconnect() end) end
    table.clear(antiKickConn)
end

---------------------------------------------------------------------------
-- MAIN LOOP
---------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
    -- player ESP
    for _, p in ipairs(Players:GetPlayers()) do renderPlayerESP(p) end
    -- loot ESP (ทุก 0.5s เพื่อ performance)
end)

local lootTimer = 0
RunService.Heartbeat:Connect(function(dt)
    lootTimer = lootTimer + dt
    if lootTimer >= 0.5 then
        lootTimer = 0
        renderLootESP()
    end
    -- hitbox size sync (ถ้าปรับค่าใน slider)
    if CFG.HitboxEnabled then refreshHitboxes() end
end)

---------------------------------------------------------------------------
-- RESPAWN HANDLER
---------------------------------------------------------------------------
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.8)
    watchTools()
    if CFG.AutoHeal  then startAutoHeal()  end
    if CFG.NoRecoil  then startNoRecoil()  end
end)
task.wait(1); watchTools()

---------------------------------------------------------------------------
-- UI HELPERS
---------------------------------------------------------------------------
local function mkCorner(p,r)
    Instance.new("UICorner",p).CornerRadius=UDim.new(0,r or 6)
end
local function mkStroke(p,col,t)
    local s=Instance.new("UIStroke",p); s.Color=col or CFG.Accent; s.Thickness=t or 1
end
local function mkLabel(parent,text,size,color,font,xa,pos,sz)
    local l=Instance.new("TextLabel")
    l.Text=text; l.TextSize=size
    l.TextColor3=color or Color3.fromRGB(220,220,220)
    l.Font=font or Enum.Font.Gotham; l.BackgroundTransparency=1
    l.TextXAlignment=xa or Enum.TextXAlignment.Left
    l.Position=pos or UDim2.new(0,0,0,0)
    l.Size=sz or UDim2.new(1,0,1,0); l.Parent=parent; return l
end

---------------------------------------------------------------------------
-- SCREEN GUI
---------------------------------------------------------------------------
local sg=Instance.new("ScreenGui")
sg.Name="SniperArenaPro"; sg.ResetOnSpawn=false
sg.DisplayOrder=999; sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
sg.Parent=LocalPlayer:WaitForChild("PlayerGui")

local WIN_W,WIN_H=300,530
local win=Instance.new("Frame")
win.Size=UDim2.new(0,WIN_W,0,WIN_H); win.Position=UDim2.fromScale(0.36,0.10)
win.BackgroundColor3=CFG.BG; win.BorderSizePixel=0
win.ClipsDescendants=true; win.Parent=sg
mkCorner(win,8); mkStroke(win,CFG.Accent,1)

-- HEADER
local hdr=Instance.new("Frame")
hdr.Size=UDim2.new(1,0,0,32); hdr.BackgroundColor3=CFG.BtnBG
hdr.BorderSizePixel=0; hdr.Parent=win; mkCorner(hdr,8)
local hf=Instance.new("Frame")
hf.Size=UDim2.new(1,0,0,8); hf.Position=UDim2.new(0,0,1,-8)
hf.BackgroundColor3=CFG.BtnBG; hf.BorderSizePixel=0; hf.Parent=hdr
mkLabel(hdr,"  🎯 SNIPER ARENA PRO",12,CFG.Accent,Enum.Font.GothamBold,
    Enum.TextXAlignment.Left,UDim2.new(0,0,0,0),UDim2.new(1,-56,1,0))

local minBtn=Instance.new("TextButton")
minBtn.Size=UDim2.new(0,24,0,24); minBtn.Position=UDim2.new(1,-52,0.5,-12)
minBtn.BackgroundColor3=CFG.BG; minBtn.Text="—"; minBtn.TextColor3=Color3.fromRGB(180,180,180)
minBtn.Font=Enum.Font.GothamBold; minBtn.TextSize=12; minBtn.BorderSizePixel=0
minBtn.Parent=hdr; mkCorner(minBtn,4)

local closeBtn=Instance.new("TextButton")
closeBtn.Size=UDim2.new(0,24,0,24); closeBtn.Position=UDim2.new(1,-24,0.5,-12)
closeBtn.BackgroundColor3=CFG.BG; closeBtn.Text="✕"; closeBtn.TextColor3=Color3.fromRGB(220,70,70)
closeBtn.Font=Enum.Font.GothamBold; closeBtn.TextSize=12; closeBtn.BorderSizePixel=0
closeBtn.Parent=hdr; mkCorner(closeBtn,4)

-- TABS
local tabBar=Instance.new("Frame")
tabBar.Size=UDim2.new(1,0,0,28); tabBar.Position=UDim2.new(0,0,0,32)
tabBar.BackgroundColor3=CFG.BG; tabBar.BorderSizePixel=0; tabBar.Parent=win
local tabL=Instance.new("UIListLayout",tabBar)
tabL.FillDirection=Enum.FillDirection.Horizontal
tabL.SortOrder=Enum.SortOrder.LayoutOrder; tabL.Padding=UDim.new(0,3)
local tabP=Instance.new("UIPadding",tabBar)
tabP.PaddingLeft=UDim.new(0,6); tabP.PaddingTop=UDim.new(0,4)

-- SCROLL
local scroll=Instance.new("ScrollingFrame")
scroll.Size=UDim2.new(1,0,1,-62); scroll.Position=UDim2.new(0,0,0,62)
scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0
scroll.ScrollBarThickness=3; scroll.ScrollBarImageColor3=CFG.Accent
scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.Parent=win
local scL=Instance.new("UIListLayout",scroll)
scL.SortOrder=Enum.SortOrder.LayoutOrder; scL.Padding=UDim.new(0,4)
local scP=Instance.new("UIPadding",scroll)
scP.PaddingLeft=UDim.new(0,10); scP.PaddingRight=UDim.new(0,10); scP.PaddingTop=UDim.new(0,8)

---------------------------------------------------------------------------
-- COMPONENT FACTORIES
---------------------------------------------------------------------------
local oN=0
local function nO() oN=oN+1; return oN end
local pages={Combat={},ESP={},Utility={}}

local function mkSection(text,page)
    local f=Instance.new("Frame")
    f.Size=UDim2.new(1,-10,0,20); f.BackgroundTransparency=1
    f.LayoutOrder=nO(); f.Parent=scroll
    local line=Instance.new("Frame")
    line.Size=UDim2.new(1,0,0,1); line.Position=UDim2.new(0,0,0.5,0)
    line.BackgroundColor3=CFG.BtnBG; line.BorderSizePixel=0; line.Parent=f
    local lbl=Instance.new("TextLabel")
    lbl.Text=" "..text.." "; lbl.TextColor3=CFG.Accent
    lbl.BackgroundColor3=CFG.BG; lbl.AutomaticSize=Enum.AutomaticSize.X
    lbl.Size=UDim2.new(0,0,1,0); lbl.Position=UDim2.new(0,10,0,0)
    lbl.Font=Enum.Font.GothamBold; lbl.TextSize=10
    lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Parent=f
    if page then table.insert(pages[page],f) end
end

local function mkToggle(label,init,cb,page)
    local row=Instance.new("Frame")
    row.Size=UDim2.new(1,-10,0,34); row.BackgroundColor3=CFG.BtnBG
    row.BorderSizePixel=0; row.LayoutOrder=nO(); row.Parent=scroll; mkCorner(row,6)
    mkLabel(row,label,12,Color3.fromRGB(220,220,220),Enum.Font.Gotham,
        Enum.TextXAlignment.Left,UDim2.new(0,10,0,0),UDim2.new(1,-54,1,0))
    local pill=Instance.new("Frame")
    pill.Size=UDim2.new(0,38,0,20); pill.Position=UDim2.new(1,-46,0.5,-10)
    pill.BackgroundColor3=init and CFG.Accent or Color3.fromHex("3A3A4A")
    pill.BorderSizePixel=0; pill.Parent=row; mkCorner(pill,12)
    local knob=Instance.new("Frame")
    knob.Size=UDim2.new(0,14,0,14)
    knob.Position=init and UDim2.new(1,-17,0.5,-7) or UDim2.new(0,3,0.5,-7)
    knob.BackgroundColor3=Color3.fromRGB(255,255,255)
    knob.BorderSizePixel=0; knob.Parent=pill; mkCorner(knob,7)
    local state=init
    local function setState(v)
        state=v
        TweenService:Create(pill,TweenInfo.new(0.15),{
            BackgroundColor3=v and CFG.Accent or Color3.fromHex("3A3A4A")}):Play()
        TweenService:Create(knob,TweenInfo.new(0.15),{
            Position=v and UDim2.new(1,-17,0.5,-7) or UDim2.new(0,3,0.5,-7)}):Play()
    end
    local btn=Instance.new("TextButton")
    btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""; btn.Parent=row
    btn.MouseButton1Click:Connect(function() setState(not state); cb(state) end)
    if page then table.insert(pages[page],row) end
    return setState
end

local function mkSlider(label,minV,maxV,init,fmt,cb,page)
    local row=Instance.new("Frame")
    row.Size=UDim2.new(1,-10,0,52); row.BackgroundColor3=CFG.BtnBG
    row.BorderSizePixel=0; row.LayoutOrder=nO(); row.Parent=scroll; mkCorner(row,6)
    local topRow=Instance.new("Frame")
    topRow.Size=UDim2.new(1,0,0,26); topRow.BackgroundTransparency=1; topRow.Parent=row
    mkLabel(topRow,label,12,Color3.fromRGB(220,220,220),Enum.Font.Gotham,
        Enum.TextXAlignment.Left,UDim2.new(0,10,0,0),UDim2.new(0.7,0,1,0))
    local vLbl=Instance.new("TextLabel")
    vLbl.Text=string.format(fmt,init); vLbl.TextColor3=CFG.Accent
    vLbl.Font=Enum.Font.GothamBold; vLbl.TextSize=11; vLbl.BackgroundTransparency=1
    vLbl.Size=UDim2.new(0.3,0,1,0); vLbl.Position=UDim2.new(0.7,0,0,0)
    vLbl.TextXAlignment=Enum.TextXAlignment.Right
    Instance.new("UIPadding",vLbl).PaddingRight=UDim.new(0,10); vLbl.Parent=topRow
    local track=Instance.new("Frame")
    track.Size=UDim2.new(1,-20,0,6); track.Position=UDim2.new(0,10,0,30)
    track.BackgroundColor3=Color3.fromHex("2A2A3A"); track.BorderSizePixel=0
    track.Parent=row; mkCorner(track,3)
    local fill=Instance.new("Frame")
    fill.Size=UDim2.new((init-minV)/(maxV-minV),0,1,0)
    fill.BackgroundColor3=CFG.Accent; fill.BorderSizePixel=0
    fill.Parent=track; mkCorner(fill,3)
    local thumb=Instance.new("Frame")
    thumb.Size=UDim2.new(0,14,0,14); thumb.AnchorPoint=Vector2.new(0.5,0.5)
    thumb.Position=UDim2.new((init-minV)/(maxV-minV),0,0.5,0)
    thumb.BackgroundColor3=Color3.fromRGB(255,255,255)
    thumb.BorderSizePixel=0; thumb.Parent=track; mkCorner(thumb,7)
    local drag=false
    local function upd(x)
        local pct=math.clamp((x-track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1)
        local val=math.floor((minV+(maxV-minV)*pct)*10+0.5)/10
        fill.Size=UDim2.new(pct,0,1,0); thumb.Position=UDim2.new(pct,0,0.5,0)
        vLbl.Text=string.format(fmt,val); cb(val)
    end
    local hb=Instance.new("TextButton")
    hb.Size=UDim2.new(1,0,1,0); hb.BackgroundTransparency=1; hb.Text=""; hb.Parent=track
    hb.MouseButton1Down:Connect(function(x) drag=true; upd(x) end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and i.UserInputType==Enum.UserInputType.MouseMovement then upd(i.Position.X) end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end
    end)
    if page then table.insert(pages[page],row) end
end

---------------------------------------------------------------------------
-- POPULATE
---------------------------------------------------------------------------
-- COMBAT
mkSection("HITBOX","Combat")
mkToggle("Hitbox Expander",CFG.HitboxEnabled,function(v)
    CFG.HitboxEnabled=v; refreshHitboxes()
end,"Combat")
mkSlider("Hitbox Size",3,30,CFG.HitboxSize,"%.1f st",function(v)
    CFG.HitboxSize=v; if CFG.HitboxEnabled then refreshHitboxes() end
end,"Combat")

mkSection("WEAPON","Combat")
mkToggle("No Recoil",CFG.NoRecoil,function(v)
    CFG.NoRecoil=v; if v then startNoRecoil() end
end,"Combat")
mkToggle("Fast Reload",CFG.FastReload,function(v)
    CFG.FastReload=v
end,"Combat")
mkSlider("Reload Speed",0.05,1,CFG.ReloadMult,"%.2fx",function(v)
    CFG.ReloadMult=v
end,"Combat")

mkSection("HEAL","Combat")
mkToggle("Auto Heal",CFG.AutoHeal,function(v)
    CFG.AutoHeal=v; if v then startAutoHeal() end
end,"Combat")
mkSlider("Heal Threshold",10,99,CFG.HealThreshold,"%.0f HP",function(v)
    CFG.HealThreshold=v
end,"Combat")
mkSlider("Heal To",50,100,CFG.HealAmount,"%.0f HP",function(v)
    CFG.HealAmount=v
end,"Combat")

-- ESP
mkSection("PLAYER ESP","ESP")
mkToggle("Player ESP",CFG.PlayerESP,function(v) CFG.PlayerESP=v end,"ESP")
mkSection("LOOT ESP","ESP")
mkToggle("Loot ESP + Tracers",CFG.LootESP,function(v)
    CFG.LootESP=v; if not v then clearLootESP() end
end,"ESP")
mkSlider("ESP Max Dist",100,5000,CFG.ESPMaxDist,"%.0f st",function(v)
    CFG.ESPMaxDist=v
end,"ESP")

-- UTILITY
mkSection("TELEPORT","Utility")
mkToggle("Tactical Teleport (LMB)",CFG.TeleportMode,function(v)
    CFG.TeleportMode=v
    if v then startTeleport() else stopTeleport() end
end,"Utility")

mkSection("PROTECTION","Utility")
mkToggle("Anti-Kick",CFG.AntiKick,function(v)
    CFG.AntiKick=v
    if v then setupAntiKick() else stopAntiKick() end
end,"Utility")

---------------------------------------------------------------------------
-- TABS LOGIC
---------------------------------------------------------------------------
local tabBtns={}
local function switchTab(name)
    for pg,items in pairs(pages) do
        for _,item in ipairs(items) do item.Visible=(pg==name) end
    end
    for tname,tbtn in pairs(tabBtns) do
        tbtn.BackgroundColor3=tname==name and CFG.Accent or CFG.BtnBG
        tbtn.TextColor3=tname==name and Color3.fromRGB(255,255,255) or Color3.fromRGB(160,160,160)
    end
end

for i,tname in ipairs({"Combat","ESP","Utility"}) do
    local tb=Instance.new("TextButton")
    tb.Size=UDim2.new(0,88,0,22); tb.BackgroundColor3=CFG.BtnBG
    tb.Text=tname; tb.TextColor3=Color3.fromRGB(160,160,160)
    tb.Font=Enum.Font.GothamBold; tb.TextSize=11
    tb.BorderSizePixel=0; tb.LayoutOrder=i; tb.Parent=tabBar; mkCorner(tb,4)
    tabBtns[tname]=tb
    tb.MouseButton1Click:Connect(function() switchTab(tname) end)
end
switchTab("Combat")

---------------------------------------------------------------------------
-- WINDOW DRAG
---------------------------------------------------------------------------
local wDrag,wDS,wSP=false,nil,nil
hdr.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 then
        wDrag=true; wDS=i.Position; wSP=win.Position end
end)
hdr.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 then wDrag=false end
end)
UserInputService.InputChanged:Connect(function(i)
    if wDrag and i.UserInputType==Enum.UserInputType.MouseMovement then
        local d=i.Position-wDS
        win.Position=UDim2.new(wSP.X.Scale,wSP.X.Offset+d.X,wSP.Y.Scale,wSP.Y.Offset+d.Y)
    end
end)

---------------------------------------------------------------------------
-- MINIMIZE / CLOSE / REOPEN
---------------------------------------------------------------------------
local minimized=false
minBtn.MouseButton1Click:Connect(function()
    minimized=not minimized
    TweenService:Create(win,TweenInfo.new(0.18,Enum.EasingStyle.Quint),{
        Size=UDim2.new(0,WIN_W,0,minimized and 32 or WIN_H)}):Play()
    minBtn.Text=minimized and "□" or "—"
end)
closeBtn.MouseButton1Click:Connect(function() win.Visible=false end)
UserInputService.InputBegan:Connect(function(input,gp)
    if gp then return end
    if input.KeyCode==Enum.KeyCode.Insert then
        win.Visible=not win.Visible
        if win.Visible then
            minimized=false; win.Size=UDim2.new(0,WIN_W,0,WIN_H); minBtn.Text="—"
        end
    end
end)

---------------------------------------------------------------------------
-- STATUS HUD
---------------------------------------------------------------------------
local hudSG=Instance.new("ScreenGui")
hudSG.Name="SniperHUD"; hudSG.ResetOnSpawn=false
hudSG.DisplayOrder=998; hudSG.Parent=LocalPlayer:WaitForChild("PlayerGui")
local hudF=Instance.new("Frame")
hudF.Size=UDim2.new(0,300,0,38); hudF.Position=UDim2.fromScale(0.5,0.93)
hudF.AnchorPoint=Vector2.new(0.5,0); hudF.BackgroundColor3=CFG.BG
hudF.BackgroundTransparency=0.2; hudF.BorderSizePixel=0; hudF.Parent=hudSG
mkCorner(hudF,6)
local hudAcc=Instance.new("Frame")
hudAcc.Size=UDim2.new(1,0,0,2); hudAcc.BackgroundColor3=CFG.Accent
hudAcc.BorderSizePixel=0; hudAcc.Parent=hudF
local hudLbl=Instance.new("TextLabel")
hudLbl.BackgroundTransparency=1; hudLbl.Size=UDim2.new(1,0,1,0)
hudLbl.Font=Enum.Font.Gotham; hudLbl.TextSize=10
hudLbl.TextColor3=Color3.fromRGB(210,210,210)
hudLbl.TextXAlignment=Enum.TextXAlignment.Center; hudLbl.Parent=hudF

RunService.Heartbeat:Connect(function()
    local h=getHuman()
    hudLbl.Text=string.format(
        "Hitbox:%s(%.0f)  NoRecoil:%s  Reload:%s  Heal:%s  ESP:%s  AK:%s",
        CFG.HitboxEnabled and "ON" or "OFF", CFG.HitboxSize,
        CFG.NoRecoil  and "ON" or "OFF",
        CFG.FastReload and "ON" or "OFF",
        CFG.AutoHeal  and "ON" or "OFF",
        CFG.PlayerESP and "ON" or "OFF",
        CFG.AntiKick  and "ON" or "OFF"
    )
end)

print("[Sniper Arena Pro] loaded — INSERT show/hide UI")

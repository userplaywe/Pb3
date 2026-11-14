-- Luau | Roblox executor | Practical Basketball | Unified Elite Suite v3: kb+mouse / touch / gamepad

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer

-- ============================================================================
-- RE-EXECUTION GUARD / CLEANUP
-- ============================================================================
local env = (getgenv and getgenv()) or _G
if env.LunyxPB_Unload then pcall(env.LunyxPB_Unload) end

local Connections, Cleanups = {}, {}
local function Bind(conn) table.insert(Connections, conn) return conn end
local function OnUnload(fn) table.insert(Cleanups, fn) end

local Unloaded = false
local function Unload()
    Unloaded = true
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    for _, fn in ipairs(Cleanups) do pcall(fn) end
    table.clear(Connections)
    table.clear(Cleanups)
    env.LunyxPB_Unload = nil
end
env.LunyxPB_Unload = Unload

-- ============================================================================
-- CONFIG & TELEMETRY
-- ============================================================================
local Config = {
    Offense = {
        AutoGreen = true, AutoShoot = false, AutoPass = false,
        AutoDribbleWhenGuarded = false, DribbleGlide = true, GlideForce = 18.0,
        AutoLayupDunk = true, ReleaseLead = 0.032, MatchPing = true,
        PingMultiplier = 1.0, AutoTune = true, CorrectionSize = 0.003,
        PrecisionWindow = 0.965, FitQuality = "High",
    },
    Defense = {
        AutoBlock = true, BlockRange = 16.0, JumpDelay = 0.08, IgnorePumpFakes = true,
        AutoSteal = true, StealRange = 10.0, StealCooldown = 0.45,
        AutoGuard = true, StopAtRim = true, RimStopDistance = 6.0, ManualOverride = true,
        TargetHighlight = true, HighlightColor = Color3.fromRGB(0, 255, 140), HighlightRadius = 4.5,
        AutoRebound = true, ReboundRange = 26.0,
        BallMagnet = true, MagnetRange = 8.0,
        IntimidatorAura = true, IntimidatorRange = 11.0,
    },
    Dribble = {
        AutoCrossover = false, ComboChainDelay = 0.28,
        CustomDribbleSpeed = true, DribbleAnimationSpeed = 1.55,
    },
    Player = {
        StaminaLock = true, AlwaysSprint = true, CustomWalkspeed = true, WalkspeedValue = 28.5,
        NoStun = true, NoDebounce = true, NoColdZone = true, InfiniteJumps = false,
    },
    Appearance = {
        GreenEffect = "Lightning", SkinTone = Color3.fromRGB(210, 165, 125),
        ShirtId = 0, PantsId = 0, BannerBgId = 0, BannerTitle = "THE BENCH",
    },
    Misc = {
        AutoFarm = false, AutoJoinPlace = false, TargetPlaceId = 0, StreakGuard = true,
        FarmTeleportCooldown = 0.6,
    },
}

local Telemetry = {
    ShotsTaken = 0, GreensHit = 0, LastDeviation = 0.0, CalibratedOffset = 0.0,
    CurrentPingMs = 0, LastStealTime = 0, LastBlockTime = 0, LastDribbleTick = 0,
    GuardingTarget = nil, CurrentStreak = 0, HasActiveStreak = false,
}

local MAX_OFFSET = 0.08 -- auto-tune clamp (seconds)
local PAD_PASS = Enum.KeyCode.ButtonL1 -- hold to pass on gamepad

local GreenEffectsList = {
    "Default", "Lightning", "Fire", "Ice", "Void", "Emerald", "Gold", "Cyber",
    "Plasma", "Sakura", "Shadow", "Matrix", "Frostbite", "Solar", "Lunar", "Toxic",
    "Crimson", "Splash", "Confetti", "Glitch", "Starlight", "Shockwave", "Aura", "Bolt",
}

local DribbleMoves = {
    { Name = "Crossover",        Code = "Cross",      Key = Enum.KeyCode.One },
    { Name = "Between The Legs", Code = "BTL",        Key = Enum.KeyCode.Two },
    { Name = "Behind The Back",  Code = "BTB",        Key = Enum.KeyCode.Three },
    { Name = "Hesitation",       Code = "Hesi",       Key = Enum.KeyCode.Four },
    { Name = "Spin Move",        Code = "Spin",       Key = Enum.KeyCode.Five },
    { Name = "Half Spin",        Code = "HalfSpin",   Key = Enum.KeyCode.Six },
    { Name = "In & Out",         Code = "InOut",      Key = Enum.KeyCode.Seven },
    { Name = "Stepback",         Code = "Stepback",   Key = Enum.KeyCode.Eight },
    { Name = "Snatchback",       Code = "Snatch",     Key = Enum.KeyCode.Nine },
    { Name = "Shamgod",          Code = "Shamgod",    Key = Enum.KeyCode.Zero },
    { Name = "Momentum Cross",   Code = "Momentum",   Key = Enum.KeyCode.Z },
    { Name = "Misdirection",     Code = "Misdirect",  Key = Enum.KeyCode.C },
    { Name = "Killer Combo",     Code = "ComboChain", Key = Enum.KeyCode.V },
}

-- ============================================================================
-- PLATFORM + SHARED INPUT STATE
-- ============================================================================
local function IsPadMode()
    return UserInputService:GetLastInputType().Name:find("Gamepad") ~= nil
end

local function IsTouchMode()
    local l = UserInputService:GetLastInputType()
    if l == Enum.UserInputType.Touch then return true end
    return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
        and not UserInputService.MouseEnabled and not l.Name:find("Gamepad")
end

local MenuOpen, TouchPassHeld, SelectedMove = false, false, 1
local Toast = function(_) end       -- assigned by BuildOverlay
local ToggleMenu = function() end   -- assigned by BuildUI
OnUnload(function() TouchPassHeld = false end)

-- ============================================================================
-- LAZY REMOTES (resolved on use, retried, never cached as nil forever)
-- FILL: confirm these names against the game's real remotes (RemoteSpy)
-- ============================================================================
local RemoteNames = {
    Shoot = "ShootEvent", Pass = "PassEvent", Block = "BlockEvent", Steal = "StealEvent",
    Rebound = "ReboundEvent", Dribble = "DribbleEvent", Sprint = "SprintEvent",
    Cosmetic = "CosmeticEvent", Queue = "JoinCourtEvent",
}
local RemoteCache, RemoteLookupT = {}, {}

local function Fire(key, ...)
    local r = RemoteCache[key]
    if not (r and r.Parent) then
        if tick() - (RemoteLookupT[key] or 0) < 2 then return end
        RemoteLookupT[key] = tick()
        r = ReplicatedStorage:FindFirstChild(RemoteNames[key], true)
        RemoteCache[key] = r
    end
    if r and r:IsA("RemoteEvent") then pcall(r.FireServer, r, ...) end
end

-- ============================================================================
-- HELPERS & CACHES
-- ============================================================================
local function GetPingSeconds()
    local ok, item = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"] end)
    local ms = (ok and item) and item:GetValue() or 40
    Telemetry.CurrentPingMs = math.floor(ms)
    return (ms / 1000) * Config.Offense.PingMultiplier
end

local function GetCharacter(plr)
    plr = plr or LocalPlayer
    local char = plr.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then return nil end
    return char, hum, root
end

local Cache = { Ball = nil, BallT = 0, Rims = {}, RimT = -10, Meter = nil, Fill = nil, MeterT = 0,
                Handler = nil, HandlerChar = nil, HandlerT = 0 }

local function GetBall()
    local b = Cache.Ball
    if b and b.Parent then return b end
    if tick() - Cache.BallT < 0.25 then return nil end
    Cache.BallT = tick()
    for _, obj in ipairs(Workspace:GetChildren()) do
        local n = obj.Name:lower()
        if n:find("ball") then
            if obj:IsA("BasePart") then Cache.Ball = obj return obj end
            if obj:IsA("Model") then
                local p = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
                if p then Cache.Ball = p return p end
            end
        end
    end
    Cache.Ball = nil
    return nil
end

local function RefreshRims()
    if tick() - Cache.RimT < 3 then return end
    Cache.RimT = tick()
    table.clear(Cache.Rims)
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            local n = obj.Name:lower()
            if n:find("rim") or n:find("hoop") then table.insert(Cache.Rims, obj) end
        end
    end
end

local function GetNearestRim(pos)
    RefreshRims()
    local nearest, minDist = nil, math.huge
    for _, r in ipairs(Cache.Rims) do
        if r.Parent then
            local d = (r.Position - pos).Magnitude
            if d < minDist then minDist, nearest = d, r end
        end
    end
    return nearest, minDist
end

-- Handler resolved at most every 50ms and shared by every system
local function GetBallHandler()
    if tick() - Cache.HandlerT < 0.05 then return Cache.Handler, Cache.HandlerChar end
    Cache.HandlerT = tick()
    Cache.Handler, Cache.HandlerChar = nil, nil

    local ball = GetBall()
    if not ball then return nil, nil end

    for _, c in ipairs(ball:GetChildren()) do
        if c:IsA("WeldConstraint") or c:IsA("Motor6D") or c:IsA("Weld") then
            local other = (c.Part0 == ball) and c.Part1 or c.Part0
            local model = other and other:FindFirstAncestorOfClass("Model")
            local plr = model and Players:GetPlayerFromCharacter(model)
            if plr then Cache.Handler, Cache.HandlerChar = plr, model return plr, model end
        end
    end

    local minDist = 5.0
    for _, plr in ipairs(Players:GetPlayers()) do
        local char, _, root = GetCharacter(plr)
        if root then
            local d = (root.Position - ball.Position).Magnitude
            if d < minDist then minDist = d Cache.Handler, Cache.HandlerChar = plr, char end
        end
    end
    return Cache.Handler, Cache.HandlerChar
end

local function GetNearestTeammate()
    local _, _, myRoot = GetCharacter()
    if not myRoot then return nil end
    local nearest, minDist = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local _, _, root = GetCharacter(plr)
            if root then
                local d = (root.Position - myRoot.Position).Magnitude
                if d < minDist then minDist, nearest = d, plr end
            end
        end
    end
    return nearest
end

local function Throttle(state, key, interval)
    local now = tick()
    if now - (state[key] or 0) < interval then return false end
    state[key] = now
    return true
end
local Timers = {}

-- Manual movement from ANY device. Humanoid.MoveDirection can't be used: AutoGuard's
-- MoveTo sets it too and would trip its own override. PlayerModule's move vector is
-- raw user input only (kb / thumbstick / touch stick). Catches: custom control scripts
-- that don't expose GetControls (falls back to keys + gamepad stick below).
local ControlsModule
local function GetControls()
    if ControlsModule ~= nil then return ControlsModule or nil end
    ControlsModule = false
    pcall(function()
        local ps = LocalPlayer:WaitForChild("PlayerScripts", 2)
        ControlsModule = require(ps:WaitForChild("PlayerModule", 2)):GetControls()
    end)
    return ControlsModule or nil
end

local function IsManualMovementActive()
    if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.A)
        or UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.D) then
        return true
    end
    local c = GetControls()
    if c then
        local ok, v = pcall(c.GetMoveVector, c)
        if ok and typeof(v) == "Vector3" and v.Magnitude > 0.15 then return true end
    end
    if UserInputService.GamepadEnabled then
        local ok, states = pcall(UserInputService.GetGamepadState, UserInputService, Enum.UserInputType.Gamepad1)
        if ok and states then
            for _, s in ipairs(states) do
                if s.KeyCode == Enum.KeyCode.Thumbstick1 and s.Position.Magnitude > 0.2 then return true end
            end
        end
    end
    return false
end

-- ============================================================================
-- ACTION LAYER: one call, three platforms
-- keyboard/pad -> VIM key (game's CAS binds). touch -> game's on-screen button
-- first (firesignal), key as fallback. Jump -> Humanoid.Jump off-keyboard.
-- FILL: if touch shoot/steal do nothing, dump the real buttons:
--   for _, g in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
--       if g:IsA("GuiButton") then print(g:GetFullName()) end end
-- and edit Hints. Buttons that listen via InputBegan (not Activated/Click) can't be
-- hit by firesignal; those fall through to the key event.
-- ============================================================================
local ACTIONS = {
    Shoot = { Key = Enum.KeyCode.E,     Hints = { "shoot", "shot" } },
    Steal = { Key = Enum.KeyCode.F,     Hints = { "steal" } },
    Jump  = { Key = Enum.KeyCode.Space, Hints = {} },
}
local ActionButtons = {}

local function FindActionButton(name)
    local b = ActionButtons[name]
    if b and b.Parent then return b end
    if not Throttle(Timers, "btn_" .. name, 1) then return nil end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    for _, g in ipairs(pg:GetDescendants()) do
        if g:IsA("GuiButton") and g.Visible
            and not g:FindFirstAncestor("LunyxPB_Unified") and not g:FindFirstAncestor("LunyxPB_Overlay") then
            local label = g.Name .. " " .. (g:IsA("TextButton") and g.Text or "")
            label = label:lower()
            for _, hint in ipairs(ACTIONS[name].Hints) do
                if label:find(hint, 1, true) then ActionButtons[name] = g return g end
            end
        end
    end
    return nil
end

local function PressButton(btn, down)
    if not firesignal then return false end
    return (pcall(function()
        firesignal(down and btn.MouseButton1Down or btn.MouseButton1Up)
        if not down then
            firesignal(btn.MouseButton1Click)
            firesignal(btn.Activated)
        end
    end))
end

local function SendAction(name, down)
    local a = ACTIONS[name]
    if not a then return end
    if IsTouchMode() or IsPadMode() then
        if name == "Jump" then
            if down then
                local _, hum = GetCharacter()
                if hum then hum.Jump = true end
            end
            return
        end
        if IsTouchMode() then
            local btn = FindActionButton(name)
            if btn and PressButton(btn, down) then return end
        end
    end
    pcall(function() VirtualInputManager:SendKeyEvent(down, a.Key, false, game) end)
end

local function Tap(name, hold)
    SendAction(name, true)
    task.delay(hold or 0.04, function() SendAction(name, false) end)
end

local function PassHeld()
    if TouchPassHeld then return true end
    if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return true end
    if UserInputService.GamepadEnabled then
        local ok, down = pcall(UserInputService.IsGamepadButtonDown, UserInputService,
            Enum.UserInputType.Gamepad1, PAD_PASS)
        if ok and down then return true end
    end
    return false
end

-- ============================================================================
-- 1. OFFENSE
-- ============================================================================
local MeterSolver = { Active = false, LastProgress = 0, Velocity = 0, Released = false, Holding = false, HoldStart = 0 }

local function FindShotMeterUI()
    -- cached; revalidated at 10Hz instead of scanning PlayerGui every frame
    if Cache.Meter and Cache.Meter.Parent and Cache.Meter.Visible and Cache.Fill and Cache.Fill.Parent then
        return Cache.Meter, Cache.Fill
    end
    if tick() - Cache.MeterT < 0.1 then return nil end
    Cache.MeterT = tick()
    Cache.Meter, Cache.Fill = nil, nil

    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    for _, gui in ipairs(pg:GetDescendants()) do
        if gui:IsA("Frame") and gui.Visible and gui.AbsoluteSize.Y > 10
            and not gui:FindFirstAncestor("LunyxPB_Unified") and not gui:FindFirstAncestor("LunyxPB_Overlay") then
            local n = gui.Name:lower()
            local pn = gui.Parent and gui.Parent.Name:lower() or ""
            local isMeter = n:find("meter") or n:find("shot")
                or (n:find("bar") and (pn:find("meter") or pn:find("shot")))
            if isMeter then
                local fill = gui:FindFirstChild("Fill") or gui:FindFirstChildWhichIsA("Frame")
                if fill then Cache.Meter, Cache.Fill = gui, fill return gui, fill end
            end
        end
    end
    return nil
end

local function ReleaseShot()
    if MeterSolver.Released then return end
    MeterSolver.Released = true
    MeterSolver.Holding = false
    Telemetry.ShotsTaken += 1
    SendAction("Shoot", false)
    Fire("Shoot", "Release", Telemetry.CalibratedOffset)
end

local function UpdateGreen(dt)
    if not Config.Offense.AutoGreen then return end
    local container, fill = FindShotMeterUI()

    if not container then
        MeterSolver.Active, MeterSolver.Released, MeterSolver.LastProgress = false, false, 0
        -- failsafe: never leave shoot held if the meter didn't appear
        if MeterSolver.Holding and tick() - MeterSolver.HoldStart > 1.5 then
            MeterSolver.Holding = false
            SendAction("Shoot", false)
        end
        return
    end

    if not MeterSolver.Active then MeterSolver.Active, MeterSolver.Released = true, false end

    local vertical = container.AbsoluteSize.Y >= container.AbsoluteSize.X
    local progress
    if vertical then
        progress = fill.Size.Y.Scale
        if progress == 0 and container.AbsoluteSize.Y > 0 then progress = fill.AbsoluteSize.Y / container.AbsoluteSize.Y end
    else
        progress = fill.Size.X.Scale
        if progress == 0 and container.AbsoluteSize.X > 0 then progress = fill.AbsoluteSize.X / container.AbsoluteSize.X end
    end
    progress = math.clamp(progress, 0, 1)

    if dt > 0 then MeterSolver.Velocity = (progress - MeterSolver.LastProgress) / dt end
    MeterSolver.LastProgress = progress

    local lead = Config.Offense.ReleaseLead + (Config.Offense.MatchPing and GetPingSeconds() or 0) + Telemetry.CalibratedOffset
    local predicted = progress
    if Config.Offense.FitQuality == "High" and MeterSolver.Velocity > 0 then
        predicted = progress + MeterSolver.Velocity * lead
    elseif MeterSolver.Velocity > 0 then
        predicted = progress + lead * 1.5
    end

    if predicted >= Config.Offense.PrecisionWindow and not MeterSolver.Released then
        Telemetry.LastDeviation = predicted - Config.Offense.PrecisionWindow
        ReleaseShot()
    end
end

local function UpdateOffense()
    local _, hum, root = GetCharacter()
    if not root then return end

    local handler = GetBallHandler()
    local hasBall = (handler == LocalPlayer)

    local streak = LocalPlayer:GetAttribute("Streak") or LocalPlayer:GetAttribute("WinStreak") or 0
    if typeof(streak) == "number" then
        Telemetry.CurrentStreak = streak
        Telemetry.HasActiveStreak = streak > 0
    end

    -- Dribble glide
    if Config.Offense.DribbleGlide and hasBall then
        local animator = hum:FindFirstChildOfClass("Animator")
        if animator then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                local name = (track.Animation and track.Animation.Name or ""):lower()
                if name:find("cross") or name:find("btb") or name:find("hesi") or name:find("spin") then
                    local look, v = root.CFrame.LookVector, root.AssemblyLinearVelocity
                    root.AssemblyLinearVelocity = Vector3.new(look.X * Config.Offense.GlideForce, v.Y, look.Z * Config.Offense.GlideForce)
                    break
                end
            end
        end
    end

    -- Layup / dunk approach (yields to manual input)
    if Config.Offense.AutoLayupDunk and hasBall and not IsManualMovementActive() then
        local rim, d = GetNearestRim(root.Position)
        if rim and d <= 14.0 and d > 5.5 then
            hum:MoveTo(rim.Position + (root.Position - rim.Position).Unit * 4.8)
        end
    end

    -- Auto farm (rate-limited teleports)
    if Config.Misc.AutoFarm then
        local rim, d = GetNearestRim(root.Position)
        if rim then
            if hasBall then
                if d > 18.0 then
                    if Throttle(Timers, "farmtp", Config.Misc.FarmTeleportCooldown) then
                        root.CFrame = CFrame.new(rim.Position + (root.Position - rim.Position).Unit * 15.0)
                    end
                elseif not MeterSolver.Active and not MeterSolver.Released and not MeterSolver.Holding then
                    MeterSolver.Holding, MeterSolver.HoldStart = true, tick()
                    SendAction("Shoot", true)
                end
            else
                local ball = GetBall()
                if ball then
                    if Throttle(Timers, "farmtp", Config.Misc.FarmTeleportCooldown) then
                        root.CFrame = ball.CFrame + Vector3.new(0, 0.4, 0)
                    end
                elseif Throttle(Timers, "farmqueue", 3) then
                    Fire("Queue", "QuickJoin")
                end
            end
        end
    end

    -- Auto join / hop: fires once, then waits
    if Config.Misc.AutoJoinPlace and Config.Misc.TargetPlaceId > 0 then
        local canHop = not (Config.Misc.StreakGuard and Telemetry.HasActiveStreak)
        if canHop and Throttle(Timers, "hop", 10) then
            pcall(TeleportService.Teleport, TeleportService, Config.Misc.TargetPlaceId, LocalPlayer)
        end
    end

    -- Auto shoot: press once, released by the solver (or failsafe)
    if Config.Offense.AutoShoot and hasBall and not MeterSolver.Active and not MeterSolver.Released and not MeterSolver.Holding then
        MeterSolver.Holding, MeterSolver.HoldStart = true, tick()
        SendAction("Shoot", true)
    end

    -- Auto pass: RMB / L1 / on-screen PASS held
    if Config.Offense.AutoPass and hasBall and PassHeld() then
        if Throttle(Timers, "pass", 0.4) then
            local target = GetNearestTeammate()
            if target then Fire("Pass", target) end
        end
    end

    if Config.Offense.AutoDribbleWhenGuarded and hasBall and tick() - Telemetry.LastDribbleTick >= Config.Dribble.ComboChainDelay then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local _, _, r = GetCharacter(plr)
                if r and (r.Position - root.Position).Magnitude < 7.5 then
                    Telemetry.LastDribbleTick = tick()
                    Fire("Dribble", DribbleMoves[math.random(1, #DribbleMoves)].Code)
                    break
                end
            end
        end
    end
end

local function BindShotFeedback()
    local pg = LocalPlayer:WaitForChild("PlayerGui", 5)
    if not pg then return end
    Bind(pg.DescendantAdded:Connect(function(obj)
        if not obj:IsA("TextLabel") then return end
        task.defer(function()
            if Unloaded or not obj.Parent then return end
            local txt = obj.Text:lower()
            if txt:find("green") or txt:find("excellent") then
                Telemetry.GreensHit += 1
            elseif Config.Offense.AutoTune then
                if txt:find("early") then
                    Telemetry.CalibratedOffset = math.max(-MAX_OFFSET, Telemetry.CalibratedOffset - Config.Offense.CorrectionSize)
                elseif txt:find("late") then
                    Telemetry.CalibratedOffset = math.min(MAX_OFFSET, Telemetry.CalibratedOffset + Config.Offense.CorrectionSize)
                end
            end
        end)
    end))
end

-- ============================================================================
-- 2. DEFENSE
-- ============================================================================
local Ring = Instance.new("Part")
Ring.Name = "LunyxGuardRing"
Ring.Shape = Enum.PartType.Cylinder
Ring.Anchored = true
Ring.CanCollide = false
Ring.CanQuery = false
Ring.CanTouch = false
Ring.Material = Enum.Material.Neon
Ring.Transparency = 1
Ring.Parent = Workspace
OnUnload(function() Ring:Destroy() end)

local ShotTrackers = {}

local function IsGenuineShot(char, hum)
    local animator = hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            local name = (track.Animation and track.Animation.Name or ""):lower()
            if name:find("shoot") or name:find("jump") or name:find("fade") or name:find("dunk") or name:find("layup") then
                return true
            end
        end
    end
    local root = char:FindFirstChild("HumanoidRootPart")
    return root ~= nil and root.AssemblyLinearVelocity.Y > 3.0
end

local function UpdateDefense()
    local _, myHum, myRoot = GetCharacter()
    if not myRoot then return end

    local ball = GetBall()
    local handler, handlerChar = GetBallHandler()
    local D = Config.Defense

    -- Loose-ball systems (client-side effect; may not replicate)
    if ball and not handler then
        local d = (ball.Position - myRoot.Position).Magnitude
        if D.BallMagnet and d <= D.MagnetRange then
            pcall(function()
                ball.AssemblyLinearVelocity = Vector3.zero
                ball.CFrame = myRoot.CFrame + Vector3.new(0, 1.2, 0)
            end)
        end
        if D.AutoRebound and d <= D.ReboundRange and ball.Position.Y > 7.0 and Throttle(Timers, "rebound", 0.5) then
            Tap("Jump")
            Fire("Rebound")
        end
    end

    if not handler or handler == LocalPlayer or not handlerChar then
        table.clear(ShotTrackers)
        Telemetry.GuardingTarget = nil
        Ring.Transparency = 1
        return
    end

    local hHum = handlerChar:FindFirstChildOfClass("Humanoid")
    local hRoot = handlerChar:FindFirstChild("HumanoidRootPart")
    if not hHum or not hRoot then return end

    Telemetry.GuardingTarget = handler
    local dist = (myRoot.Position - hRoot.Position).Magnitude

    if D.IntimidatorAura and dist <= D.IntimidatorRange and hHum.WalkSpeed > 14 then
        hHum.WalkSpeed = 14
    end

    if D.TargetHighlight then
        Ring.Transparency = 0.3
        Ring.Color = D.HighlightColor
        Ring.Size = Vector3.new(0.15, D.HighlightRadius * 2, D.HighlightRadius * 2)
        Ring.CFrame = CFrame.new(hRoot.Position - Vector3.new(0, 2.85, 0)) * CFrame.Angles(0, 0, math.rad(90))
    else
        Ring.Transparency = 1
    end

    if D.AutoGuard then
        local manual = D.ManualOverride and IsManualMovementActive()
        local rim, rimDist = GetNearestRim(hRoot.Position)
        local atRim = D.StopAtRim and rim and rimDist <= D.RimStopDistance
        if not manual and not atRim then
            local off = rim and (rim.Position - hRoot.Position).Unit * 3.8 or hRoot.CFrame.LookVector * 3.8
            myHum:MoveTo(Vector3.new(hRoot.Position.X + off.X, myRoot.Position.Y, hRoot.Position.Z + off.Z))
        end
    end

    if D.AutoBlock and dist <= D.BlockRange then
        if IsGenuineShot(handlerChar, hHum) then
            local tr = ShotTrackers[handler]
            if not tr then tr = { StartTime = tick() } ShotTrackers[handler] = tr end
            local need = D.IgnorePumpFakes and D.JumpDelay or 0
            if tick() - tr.StartTime >= need and tick() - Telemetry.LastBlockTime > 0.8 then
                Telemetry.LastBlockTime = tick()
                Tap("Jump")
                Fire("Block")
            end
        else
            ShotTrackers[handler] = nil
        end
    end

    if D.AutoSteal and dist <= D.StealRange and tick() - Telemetry.LastStealTime >= D.StealCooldown then
        Telemetry.LastStealTime = tick()
        Tap("Steal", 0.03)
        Fire("Steal", handler)
    end
end

-- ============================================================================
-- 3. PLAYER & DRIBBLE
-- ============================================================================
local function ExecuteDribbleMove(index)
    local move = DribbleMoves[index]
    if not move then return end
    Fire("Dribble", move.Code)
    if not UserInputService.KeyboardEnabled or IsPadMode() then Toast(move.Name) end
end

local function CycleMove(dir)
    SelectedMove = ((SelectedMove - 1 + dir) % #DribbleMoves) + 1
    Toast(string.format("[%d/%d] %s", SelectedMove, #DribbleMoves, DribbleMoves[SelectedMove].Name))
end

Bind(UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    local t, kc = input.UserInputType, input.KeyCode
    if t == Enum.UserInputType.Keyboard then
        for idx, move in ipairs(DribbleMoves) do
            if kc == move.Key then ExecuteDribbleMove(idx) break end
        end
    elseif t.Name:find("Gamepad") and not MenuOpen then
        if kc == Enum.KeyCode.DPadLeft then CycleMove(-1)
        elseif kc == Enum.KeyCode.DPadRight then CycleMove(1)
        elseif kc == Enum.KeyCode.DPadUp then ExecuteDribbleMove(SelectedMove) end
    end
end))

-- JumpRequest covers space, gamepad A and the touch jump button
Bind(UserInputService.JumpRequest:Connect(function()
    if not Config.Player.InfiniteJumps then return end
    local _, _, root = GetCharacter()
    if root then
        local v = root.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = Vector3.new(v.X, 50, v.Z)
    end
end))

local function UpdatePlayerAndDribble()
    local char, hum = GetCharacter()
    if not char then return end

    local handler = GetBallHandler()
    local hasBall = (handler == LocalPlayer)

    if Config.Dribble.AutoCrossover and hasBall and tick() - Telemetry.LastDribbleTick >= Config.Dribble.ComboChainDelay then
        Telemetry.LastDribbleTick = tick()
        Fire("Dribble", DribbleMoves[math.random(1, #DribbleMoves)].Code)
    end

    if Config.Dribble.CustomDribbleSpeed then
        local animator = hum:FindFirstChildOfClass("Animator")
        if animator then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                local name = (track.Animation and track.Animation.Name or ""):lower()
                if (name:find("dribble") or name:find("cross") or name:find("iso") or name:find("combo"))
                    and track.Speed ~= Config.Dribble.DribbleAnimationSpeed then
                    track:AdjustSpeed(Config.Dribble.DribbleAnimationSpeed)
                end
            end
        end
    end

    if Config.Player.AlwaysSprint or Config.Player.CustomWalkspeed then
        local target = Config.Player.CustomWalkspeed and Config.Player.WalkspeedValue or 26.0
        if hum.WalkSpeed < target then hum.WalkSpeed = target end
        if Config.Player.AlwaysSprint and Throttle(Timers, "sprint", 1) then Fire("Sprint", true) end
    end

    -- Heavy state sweeps run at 4Hz, not every frame
    if Throttle(Timers, "statesweep", 0.25) then
        if Config.Player.StaminaLock then
            local stam = char:FindFirstChild("Stamina", true) or LocalPlayer:FindFirstChild("Stamina", true)
            if stam and (stam:IsA("NumberValue") or stam:IsA("IntValue")) then stam.Value = 100 end
            char:SetAttribute("Stamina", 100)
        end
        if Config.Player.NoStun or Config.Player.NoDebounce then
            char:SetAttribute("Stunned", false)
            char:SetAttribute("IsStunned", false)
            for _, v in ipairs(char:GetDescendants()) do
                if v:IsA("BoolValue") then
                    local n = v.Name:lower()
                    if n:find("stun") or n:find("debounce") then v.Value = false end
                end
            end
        end
        if Config.Player.NoColdZone then
            char:SetAttribute("HotStreak", true)
            char:SetAttribute("ColdZone", false)
            LocalPlayer:SetAttribute("ShootingMultiplier", 1.3)
        end
    end
end

-- ============================================================================
-- 4. APPEARANCE
-- ============================================================================
local function ApplyAppearance()
    local char = LocalPlayer.Character
    if not char then return end

    local bodyColors = char:FindFirstChildOfClass("BodyColors")
    if bodyColors then
        local bc = BrickColor.new(Config.Appearance.SkinTone)
        bodyColors.HeadColor, bodyColors.TorsoColor = bc, bc
        bodyColors.LeftArmColor, bodyColors.RightArmColor = bc, bc
        bodyColors.LeftLegColor, bodyColors.RightLegColor = bc, bc
    end

    if Config.Appearance.ShirtId > 0 then
        local shirt = char:FindFirstChildOfClass("Shirt")
        if not shirt then shirt = Instance.new("Shirt") shirt.Parent = char end
        shirt.ShirtTemplate = "rbxassetid://" .. Config.Appearance.ShirtId
    end
    if Config.Appearance.PantsId > 0 then
        local pants = char:FindFirstChildOfClass("Pants")
        if not pants then pants = Instance.new("Pants") pants.Parent = char end
        pants.PantsTemplate = "rbxassetid://" .. Config.Appearance.PantsId
    end

    LocalPlayer:SetAttribute("GreenEffect", Config.Appearance.GreenEffect)
    LocalPlayer:SetAttribute("BannerTitle", Config.Appearance.BannerTitle)
    LocalPlayer:SetAttribute("BannerBackground", Config.Appearance.BannerBgId)

    Fire("Cosmetic", {
        GreenEffect = Config.Appearance.GreenEffect,
        BannerBg = Config.Appearance.BannerBgId,
        BannerTitle = Config.Appearance.BannerTitle,
    })
end

Bind(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if not Unloaded then
        ApplyAppearance()
        Cache.Ball, Cache.Handler = nil, nil
        MeterSolver.Active, MeterSolver.Released, MeterSolver.Holding = false, false, false
    end
end))

-- ============================================================================
-- 5. UI (menu: kb/mouse, touch, gamepad nav)
-- ============================================================================
local function Round(n, places) local m = 10 ^ places return math.floor(n * m + 0.5) / m end

local function IsPointer(i)
    return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end

local function MakeDraggable(frame, handle)
    local dragging, startInput, startPos = false, nil, nil
    Bind(handle.InputBegan:Connect(function(i)
        if IsPointer(i) then
            dragging, startInput, startPos = true, i.Position, frame.Position
            local c
            c = i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then dragging = false c:Disconnect() end
            end)
        end
    end))
    Bind(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startInput
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
end

local function BuildUI()
    local pg = LocalPlayer:WaitForChild("PlayerGui", 5)
    if not pg then return end
    local old = pg:FindFirstChild("LunyxPB_Unified")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "LunyxPB_Unified"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 40
    gui.Parent = pg
    OnUnload(function() gui:Destroy() end)

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 540, 0, 400)
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.Position = UDim2.new(0.5, 0, 0.5, 0)
    main.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
    main.BorderSizePixel = 0
    main.Active = true -- sinks touches so the camera doesn't spin under the menu
    main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", main)
    stroke.Color = Color3.fromRGB(35, 35, 45)

    -- fit the window to the viewport (phones)
    local uiscale = Instance.new("UIScale", main)
    local function Rescale()
        local cam = Workspace.CurrentCamera
        if not cam then return end
        local vp = cam.ViewportSize
        uiscale.Scale = math.clamp(math.min(vp.X / 580, vp.Y / 440), 0.5, 1)
    end
    Rescale()
    local cam = Workspace.CurrentCamera
    if cam then Bind(cam:GetPropertyChangedSignal("ViewportSize"):Connect(Rescale)) end

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    header.BorderSizePixel = 0
    header.Parent = main
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 8)
    MakeDraggable(main, header)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -140, 1, 0)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "LUNYX // PB ELITE  [RShift | L3+R3]"
    title.TextColor3 = Color3.fromRGB(0, 255, 140)
    title.Font = Enum.Font.Code
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local function HeaderButton(text, x, w, bg, fg)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, w, 0, 22)
        b.Position = UDim2.new(1, x, 0, 7)
        b.BackgroundColor3 = bg
        b.TextColor3 = fg
        b.Font = Enum.Font.Code
        b.TextSize = 11
        b.Text = text
        b.Parent = header
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
        return b
    end
    local hideBtn = HeaderButton("HIDE", -124, 44, Color3.fromRGB(26, 26, 36), Color3.fromRGB(190, 190, 205))
    local unloadBtn = HeaderButton("UNLOAD", -72, 64, Color3.fromRGB(60, 20, 26), Color3.fromRGB(255, 120, 130))
    unloadBtn.MouseButton1Click:Connect(Unload)

    local readout = Instance.new("TextLabel")
    readout.Size = UDim2.new(1, -20, 0, 24)
    readout.Position = UDim2.new(0, 10, 0, 44)
    readout.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    readout.TextColor3 = Color3.fromRGB(215, 215, 225)
    readout.Font = Enum.Font.Code
    readout.TextSize = 11
    readout.Parent = main
    Instance.new("UICorner", readout).CornerRadius = UDim.new(0, 4)

    local sidebar = Instance.new("Frame")
    sidebar.Size = UDim2.new(0, 115, 1, -80)
    sidebar.Position = UDim2.new(0, 10, 0, 74)
    sidebar.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
    sidebar.BorderSizePixel = 0
    sidebar.Parent = main
    Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, 6)
    local sLayout = Instance.new("UIListLayout", sidebar)
    sLayout.Padding = UDim.new(0, 5)
    sLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

    local area = Instance.new("Frame")
    area.Size = UDim2.new(1, -140, 1, -80)
    area.Position = UDim2.new(0, 130, 0, 74)
    area.BackgroundTransparency = 1
    area.Parent = main

    local tabs, first, firstButton = {}, true, nil
    local ON_BG, OFF_BG = Color3.fromRGB(0, 255, 140), Color3.fromRGB(22, 22, 30)

    local function Select(name)
        for n, t in pairs(tabs) do
            local sel = (n == name)
            t.Scroll.Visible = sel
            t.Button.BackgroundColor3 = sel and ON_BG or OFF_BG
            t.Button.TextColor3 = sel and Color3.fromRGB(12, 12, 16) or Color3.fromRGB(160, 160, 175)
        end
    end

    local function CreateTab(name)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -8, 0, 32)
        btn.Font = Enum.Font.Code
        btn.TextSize = 12
        btn.Text = name
        btn.Parent = sidebar
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

        local scroll = Instance.new("ScrollingFrame")
        scroll.Size = UDim2.new(1, 0, 1, 0)
        scroll.BackgroundTransparency = 1
        scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroll.CanvasSize = UDim2.new()
        scroll.ScrollBarThickness = 3
        scroll.Parent = area
        Instance.new("UIListLayout", scroll).Padding = UDim.new(0, 6)

        tabs[name] = { Button = btn, Scroll = scroll }
        btn.MouseButton1Click:Connect(function() Select(name) end)
        if first then first, firstButton = false, btn Select(name) else scroll.Visible = false end
        return scroll
    end

    local function AddToggle(parent, label, tbl, key)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -6, 0, 28)
        btn.BackgroundColor3 = OFF_BG
        btn.Font = Enum.Font.Code
        btn.TextSize = 11
        btn.TextXAlignment = Enum.TextXAlignment.Left
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
        local function refresh()
            btn.Text = string.format(" [%s] %s", tbl[key] and "ON " or "OFF", label)
            btn.TextColor3 = tbl[key] and Color3.fromRGB(0, 255, 140) or Color3.fromRGB(175, 175, 190)
        end
        refresh()
        btn.MouseButton1Click:Connect(function() tbl[key] = not tbl[key] refresh() end)
        btn.Parent = parent
    end

    -- [-] [+] buttons: works on touch and gamepad (RMB-to-decrement was mouse only)
    local function AddStep(parent, label, tbl, key, step, minV, maxV)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -6, 0, 28)
        row.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
        row.BorderSizePixel = 0
        row.Parent = parent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -66, 1, 0)
        lbl.Position = UDim2.new(0, 6, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = Color3.fromRGB(185, 215, 255)
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 11
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local function refresh() lbl.Text = string.format("%s: %.3f", label, tbl[key]) end
        refresh()

        local function mk(text, x, delta)
            local b = Instance.new("TextButton")
            b.Size = UDim2.fromOffset(26, 22)
            b.Position = UDim2.new(1, x, 0.5, -11)
            b.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
            b.TextColor3 = Color3.fromRGB(0, 255, 140)
            b.Font = Enum.Font.Code
            b.TextSize = 14
            b.Text = text
            b.Parent = row
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
            b.MouseButton1Click:Connect(function()
                tbl[key] = Round(math.clamp(tbl[key] + delta, minV, maxV), 4)
                refresh()
            end)
        end
        mk("-", -60, -step)
        mk("+", -30, step)
    end

    local O, Df, P, Dr, M = Config.Offense, Config.Defense, Config.Player, Config.Dribble, Config.Misc
    local offenseTab, defenseTab = CreateTab("Offense"), CreateTab("Defense")
    local playerTab, dribbleTab, miscTab = CreateTab("Player"), CreateTab("Dribble"), CreateTab("Misc / FX")

    AddToggle(offenseTab, "Auto Green Solver", O, "AutoGreen")
    AddToggle(offenseTab, "Auto Shoot (Hold Shoot)", O, "AutoShoot")
    AddToggle(offenseTab, "Auto Pass (RMB / L1 / PASS)", O, "AutoPass")
    AddToggle(offenseTab, "Auto Dribble When Guarded", O, "AutoDribbleWhenGuarded")
    AddToggle(offenseTab, "Dribble Glide Boost", O, "DribbleGlide")
    AddStep(offenseTab, "Glide Force", O, "GlideForce", 1.0, 5.0, 35.0)
    AddToggle(offenseTab, "Auto Layup / Dunk Solver", O, "AutoLayupDunk")
    AddStep(offenseTab, "Release Lead (s)", O, "ReleaseLead", 0.005, 0.0, 0.15)
    AddToggle(offenseTab, "Match Network Ping", O, "MatchPing")
    AddToggle(offenseTab, "Auto Tune Per Meter", O, "AutoTune")
    AddStep(offenseTab, "Correction Size", O, "CorrectionSize", 0.001, 0.001, 0.02)
    AddStep(offenseTab, "Precision Window", O, "PrecisionWindow", 0.01, 0.85, 1.0)

    AddToggle(defenseTab, "Auto Block", Df, "AutoBlock")
    AddToggle(defenseTab, "Ignore Pump Fakes", Df, "IgnorePumpFakes")
    AddStep(defenseTab, "Block Range", Df, "BlockRange", 1.0, 6.0, 25.0)
    AddStep(defenseTab, "Jump Delay (s)", Df, "JumpDelay", 0.02, 0.0, 0.4)
    AddToggle(defenseTab, "Auto Steal", Df, "AutoSteal")
    AddStep(defenseTab, "Steal Range", Df, "StealRange", 0.5, 4.0, 15.0)
    AddStep(defenseTab, "Steal Cooldown", Df, "StealCooldown", 0.05, 0.1, 2.0)
    AddToggle(defenseTab, "Auto Guard Ball Handler", Df, "AutoGuard")
    AddToggle(defenseTab, "Target Highlight Ring", Df, "TargetHighlight")
    AddToggle(defenseTab, "Stop Guarding At Rim", Df, "StopAtRim")
    AddToggle(defenseTab, "Manual Move Override (any input)", Df, "ManualOverride")
    AddToggle(defenseTab, "Auto Rebound", Df, "AutoRebound")
    AddStep(defenseTab, "Rebound Range", Df, "ReboundRange", 1.0, 10.0, 35.0)
    AddToggle(defenseTab, "Ball Magnet (Loose Balls)", Df, "BallMagnet")
    AddStep(defenseTab, "Magnet Range", Df, "MagnetRange", 0.5, 2.0, 15.0)
    AddToggle(defenseTab, "Intimidator Aura", Df, "IntimidatorAura")
    AddStep(defenseTab, "Intimidator Range", Df, "IntimidatorRange", 1.0, 5.0, 20.0)

    AddToggle(playerTab, "Stamina Lock", P, "StaminaLock")
    AddToggle(playerTab, "Always Sprinting", P, "AlwaysSprint")
    AddToggle(playerTab, "Custom Walkspeed", P, "CustomWalkspeed")
    AddStep(playerTab, "Walkspeed Value", P, "WalkspeedValue", 1.0, 16.0, 45.0)
    AddToggle(playerTab, "Infinite Jumps", P, "InfiniteJumps")
    AddToggle(playerTab, "No Stun", P, "NoStun")
    AddToggle(playerTab, "No Debounce", P, "NoDebounce")
    AddToggle(playerTab, "No Cold Zone", P, "NoColdZone")

    AddToggle(dribbleTab, "Custom Dribble Speed", Dr, "CustomDribbleSpeed")
    AddStep(dribbleTab, "Dribble Anim Multiplier", Dr, "DribbleAnimationSpeed", 0.05, 1.0, 2.5)
    AddToggle(dribbleTab, "Auto Crossover Chain", Dr, "AutoCrossover")
    AddStep(dribbleTab, "Combo Chain Delay (s)", Dr, "ComboChainDelay", 0.05, 0.15, 1.0)

    local dHeader = Instance.new("TextLabel")
    dHeader.Size = UDim2.new(1, -6, 0, 20)
    dHeader.BackgroundTransparency = 1
    dHeader.Text = "-- 13 ONE-PRESS DRIBBLES --"
    dHeader.TextColor3 = Color3.fromRGB(0, 200, 255)
    dHeader.Font = Enum.Font.Code
    dHeader.TextSize = 11
    dHeader.TextXAlignment = Enum.TextXAlignment.Left
    dHeader.Parent = dribbleTab

    for i, move in ipairs(DribbleMoves) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -6, 0, 26)
        b.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
        b.TextColor3 = Color3.fromRGB(160, 230, 255)
        b.Font = Enum.Font.Code
        b.TextSize = 11
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.Text = string.format("  Dribble %02d [%s]: %s", i, move.Key.Name, move.Name)
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
        b.MouseButton1Click:Connect(function() ExecuteDribbleMove(i) end)
        b.Parent = dribbleTab
    end

    AddToggle(miscTab, "Auto Farm Courts (TP+Shoot)", M, "AutoFarm")
    AddToggle(miscTab, "Auto Join Place / Server Hop", M, "AutoJoinPlace")
    AddToggle(miscTab, "Streak Guard (Lock on Streak)", M, "StreakGuard")
    AddStep(miscTab, "Farm TP Cooldown (s)", M, "FarmTeleportCooldown", 0.1, 0.2, 3.0)

    local effectIdx = table.find(GreenEffectsList, Config.Appearance.GreenEffect) or 1
    local fx = Instance.new("TextButton")
    fx.Size = UDim2.new(1, -6, 0, 28)
    fx.BackgroundColor3 = OFF_BG
    fx.TextColor3 = Color3.fromRGB(255, 215, 100)
    fx.Font = Enum.Font.Code
    fx.TextSize = 11
    fx.TextXAlignment = Enum.TextXAlignment.Left
    fx.Text = string.format("  Green Effect [%d/%d]: %s", effectIdx, #GreenEffectsList, Config.Appearance.GreenEffect)
    Instance.new("UICorner", fx).CornerRadius = UDim.new(0, 4)
    fx.MouseButton1Click:Connect(function()
        effectIdx = (effectIdx % #GreenEffectsList) + 1
        Config.Appearance.GreenEffect = GreenEffectsList[effectIdx]
        fx.Text = string.format("  Green Effect [%d/%d]: %s", effectIdx, #GreenEffectsList, Config.Appearance.GreenEffect)
        ApplyAppearance()
    end)
    fx.Parent = miscTab

    -- menu open/close; gamepad gets selection focus (dpad/stick nav, A = click)
    local function SetMenu(open)
        MenuOpen = open
        main.Visible = open
        if open and IsPadMode() and firstButton then
            GuiService.SelectedObject = firstButton
        else
            local sel = GuiService.SelectedObject
            if sel and sel:IsDescendantOf(main) then GuiService.SelectedObject = nil end
        end
    end
    ToggleMenu = function() SetMenu(not MenuOpen) end
    hideBtn.MouseButton1Click:Connect(function() SetMenu(false) end)
    OnUnload(function()
        ToggleMenu = function() end
        MenuOpen = false
        local sel = GuiService.SelectedObject
        if sel and sel:IsDescendantOf(main) then GuiService.SelectedObject = nil end
    end)

    Bind(UserInputService.InputBegan:Connect(function(input, gpe)
        local kc = input.KeyCode
        if not gpe and kc == Enum.KeyCode.RightShift then ToggleMenu() return end
        if kc == Enum.KeyCode.ButtonL3 or kc == Enum.KeyCode.ButtonR3 then
            local pad = input.UserInputType
            local ok1, l3 = pcall(UserInputService.IsGamepadButtonDown, UserInputService, pad, Enum.KeyCode.ButtonL3)
            local ok2, r3 = pcall(UserInputService.IsGamepadButtonDown, UserInputService, pad, Enum.KeyCode.ButtonR3)
            if ok1 and ok2 and l3 and r3 then ToggleMenu() end
        end
    end))

    Bind(RunService.Heartbeat:Connect(function()
        if not main.Visible or not Throttle(Timers, "hud", 0.2) then return end
        local pct = Telemetry.ShotsTaken > 0 and math.floor(Telemetry.GreensHit / Telemetry.ShotsTaken * 100) or 0
        readout.Text = string.format(" Ping: %dms | Streak: %d | Shots: %d (%d%% G) | Off: %+.3f",
            Telemetry.CurrentPingMs, Telemetry.CurrentStreak, Telemetry.ShotsTaken, pct, Telemetry.CalibratedOffset)
    end))

    SetMenu(true)
end

-- ============================================================================
-- 6. OVERLAY: toast + touch controls (menu button, hold-PASS, MOVES grid)
-- ============================================================================
local function BuildOverlay()
    local pg = LocalPlayer:WaitForChild("PlayerGui", 5)
    if not pg then return end
    local old = pg:FindFirstChild("LunyxPB_Overlay")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "LunyxPB_Overlay"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 50
    gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- notch-safe
    gui.Parent = pg
    OnUnload(function() gui:Destroy() end)

    local GREEN = Color3.fromRGB(0, 255, 140)
    local DARK = Color3.fromRGB(12, 12, 16)

    local toast = Instance.new("TextLabel")
    toast.Size = UDim2.fromOffset(240, 26)
    toast.AnchorPoint = Vector2.new(0.5, 0)
    toast.Position = UDim2.new(0.5, 0, 0, 12)
    toast.BackgroundColor3 = DARK
    toast.BackgroundTransparency = 0.2
    toast.TextColor3 = GREEN
    toast.Font = Enum.Font.Code
    toast.TextSize = 12
    toast.Visible = false
    toast.Parent = gui
    Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 6)
    local toastId = 0
    Toast = function(text)
        toastId += 1
        local mine = toastId
        toast.Text = text
        toast.Visible = true
        task.delay(1.2, function()
            if mine == toastId and toast.Parent then toast.Visible = false end
        end)
    end

    local touch = Instance.new("Frame")
    touch.Size = UDim2.fromScale(1, 1)
    touch.BackgroundTransparency = 1
    touch.Parent = gui

    local function MakeBtn(text, pos, size, radius)
        local b = Instance.new("TextButton")
        b.Size = size
        b.Position = pos
        b.BackgroundColor3 = DARK
        b.BackgroundTransparency = 0.25
        b.TextColor3 = GREEN
        b.Font = Enum.Font.Code
        b.TextSize = 12
        b.Text = text
        b.Selectable = false -- keep gamepad focus inside the menu only
        b.Parent = touch
        Instance.new("UICorner", b).CornerRadius = radius
        local s = Instance.new("UIStroke", b)
        s.Color = GREEN
        s.Transparency = 0.5
        return b
    end

    -- FILL: nudge these if they sit on the game's own touch buttons
    local menuBtn = MakeBtn("MENU", UDim2.new(0, 12, 0.38, 0), UDim2.fromOffset(56, 40), UDim.new(0, 8))
    local passBtn = MakeBtn("PASS", UDim2.new(1, -76, 0.38, 0), UDim2.fromOffset(60, 60), UDim.new(1, 0))
    local movesBtn = MakeBtn("MOVES", UDim2.new(1, -76, 0.38, 70), UDim2.fromOffset(60, 40), UDim.new(0, 8))

    menuBtn.MouseButton1Click:Connect(function() ToggleMenu() end)

    -- PASS is hold-semantics (matches RMB / L1): InputBegan/Ended, not Click
    Bind(passBtn.InputBegan:Connect(function(i)
        if IsPointer(i) then
            TouchPassHeld = true
            passBtn.BackgroundColor3 = Color3.fromRGB(0, 90, 55)
        end
    end))
    Bind(passBtn.InputEnded:Connect(function(i)
        if IsPointer(i) then
            TouchPassHeld = false
            passBtn.BackgroundColor3 = DARK
        end
    end))

    local grid = Instance.new("Frame")
    grid.AnchorPoint = Vector2.new(1, 0)
    grid.Position = UDim2.new(1, -144, 0.38, 0)
    grid.Size = UDim2.fromOffset(214, 174)
    grid.BackgroundColor3 = DARK
    grid.BackgroundTransparency = 0.2
    grid.Visible = false
    grid.Parent = touch
    Instance.new("UICorner", grid).CornerRadius = UDim.new(0, 8)
    local pad = Instance.new("UIPadding", grid)
    pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
    pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 4), UDim.new(0, 4)
    local gl = Instance.new("UIGridLayout", grid)
    gl.CellSize = UDim2.fromOffset(66, 30)
    gl.CellPadding = UDim2.fromOffset(4, 4)
    gl.SortOrder = Enum.SortOrder.LayoutOrder

    for i, move in ipairs(DribbleMoves) do
        local b = Instance.new("TextButton")
        b.LayoutOrder = i
        b.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
        b.TextColor3 = Color3.fromRGB(160, 230, 255)
        b.Font = Enum.Font.Code
        b.TextSize = 10
        b.Text = move.Code
        b.Selectable = false
        b.Parent = grid
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
        b.MouseButton1Click:Connect(function() ExecuteDribbleMove(i) end)
    end
    movesBtn.MouseButton1Click:Connect(function() grid.Visible = not grid.Visible end)

    local function RefreshPlatform()
        local show = IsTouchMode()
        touch.Visible = show
        if not show then
            TouchPassHeld = false
            passBtn.BackgroundColor3 = DARK
            grid.Visible = false
        end
    end
    Bind(UserInputService.LastInputTypeChanged:Connect(RefreshPlatform))
    RefreshPlatform()
end

-- ============================================================================
-- INITIALIZE
-- ============================================================================
BindShotFeedback()
ApplyAppearance()
BuildUI()
BuildOverlay()

-- Meter solving stays on RenderStepped for timing precision
Bind(RunService.RenderStepped:Connect(function(dt)
    if Unloaded then return end
    local ok, err = pcall(UpdateGreen, dt)
    if not ok then warn("[Lunyx] green:", err) end
end))

-- Everything else on one Heartbeat, each system isolated so one error can't kill the rest
Bind(RunService.Heartbeat:Connect(function()
    if Unloaded then return end
    for name, fn in pairs({ offense = UpdateOffense, defense = UpdateDefense, player = UpdatePlayerAndDribble }) do
        local ok, err = pcall(fn)
        if not ok and Throttle(Timers, "err_" .. name, 5) then warn("[Lunyx] " .. name .. ":", err) end
    end
end))
-- language: Luau, file: MM2_Drone_Mobile_v2.lua, target: Roblox Studio / LocalScript
-- Place in StarterPlayer > StarterPlayerScripts.
-- Models expected:
-- ReplicatedStorage > DroneModels > FPV_Drone
-- ReplicatedStorage > DroneModels > Shahed_136
--
-- Mobile:
-- Roblox's built-in virtual joystick controls throttle/direction.
-- The drone flies in the direction the camera is pointing.
-- Touch buttons provide vertical climb/descent and boost.
--
-- Collision testing:
-- Only Models tagged "DroneTestTarget" are affected.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local player_gui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local player_module = player.PlayerScripts:WaitForChild("PlayerModule")
local controls = require(player_module):GetControls()

local CONFIG = {
    title = "MM2",

    drones = {
        {
            key = "FPV",
            display_name = "FPV DRONE",
            model_name = "FPV_Drone",
            max_speed = 95,
            acceleration = 7,
            turn_rate = 9,
            tilt = 12,
            engine_sound_id = "",
            impact_sound_id = "",
        },
        {
            key = "SHAHED",
            display_name = "SHAHED 136",
            model_name = "Shahed_136",
            max_speed = 70,
            acceleration = 5,
            turn_rate = 6,
            tilt = 8,
            engine_sound_id = "",
            impact_sound_id = "",
        },
    },

    hover_height = 5,
    camera_distance = 14,
    camera_height = 3.5,
    collision_cooldown = 1,
    target_launch_speed = 115,
    target_downward_speed = 35,
}

local state = {
    running = false,
    active_drone = nil,
    active_config = nil,
    velocity = Vector3.zero,
    target_cframe = nil,

    engine_sound = nil,
    impact_sound = nil,
    last_impact = 0,

    climb = 0,
    descend = 0,
    boost = 0,

    saved_humanoid = nil,
    saved_root = nil,
    saved_anchored = false,
    saved_autorotate = true,
}

local function make(class_name, properties, parent)
    local object = Instance.new(class_name)

    for key, value in pairs(properties or {}) do
        object[key] = value
    end

    object.Parent = parent
    return object
end

local function tween(object, duration, properties)
    local animation = TweenService:Create(
        object,
        TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        properties
    )
    animation:Play()
    return animation
end

local function get_scale()
    local viewport = camera.ViewportSize
    local base_width = 390
    local base_height = 290

    local scale_x = viewport.X / base_width
    local scale_y = viewport.Y / base_height

    return math.clamp(math.min(scale_x, scale_y), 0.72, 1.08)
end

local function create_button(parent, text, position, size)
    local button = make("TextButton", {
        BackgroundColor3 = Color3.fromRGB(31, 34, 40),
        AutoButtonColor = false,
        BorderSizePixel = 0,
        Position = position,
        Size = size,
        Font = Enum.Font.GothamBold,
        Text = text,
        TextColor3 = Color3.fromRGB(230, 233, 238),
        TextSize = 13,
        Active = true,
    }, parent)

    make("UICorner", {
        CornerRadius = UDim.new(0, 12),
    }, button)

    make("UIStroke", {
        Color = Color3.fromRGB(72, 76, 84),
        Transparency = 0.35,
        Thickness = 1,
    }, button)

    button.MouseEnter:Connect(function()
        tween(button, 0.12, {
            BackgroundColor3 = Color3.fromRGB(43, 47, 55),
        })
    end)

    button.MouseLeave:Connect(function()
        tween(button, 0.12, {
            BackgroundColor3 = Color3.fromRGB(31, 34, 40),
        })
    end)

    return button
end

local function show_signal(text, duration)
    local gui = player_gui:FindFirstChild("MM2_Drone_UI")
    if not gui then
        return
    end

    local signal = gui:FindFirstChild("Signal")
    if not signal then
        signal = make("TextLabel", {
            Name = "Signal",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.40),
            Size = UDim2.fromOffset(280, 60),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBlack,
            TextColor3 = Color3.fromRGB(232, 235, 240),
            TextStrokeTransparency = 0.35,
            TextSize = 28,
            Visible = false,
            ZIndex = 50,
        }, gui)
    end

    signal.Text = text
    signal.TextTransparency = 1
    signal.Visible = true

    tween(signal, 0.10, {
        TextTransparency = 0,
    })

    task.delay(duration or 0.55, function()
        if not signal.Parent then
            return
        end

        local fade = tween(signal, 0.18, {
            TextTransparency = 1,
        })

        fade.Completed:Wait()

        if signal then
            signal.Visible = false
        end
    end)
end

local function create_menu()
    local previous = player_gui:FindFirstChild("MM2_Drone_UI")
    if previous then
        previous:Destroy()
    end

    local gui = make("ScreenGui", {
        Name = "MM2_Drone_UI",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, player_gui)

    local panel = make("Frame", {
        Name = "Panel",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.50),
        Size = UDim2.fromOffset(360, 250),
        BackgroundColor3 = Color3.fromRGB(18, 20, 24),
        BorderSizePixel = 0,
    }, gui)

    local scale = make("UIScale", {
        Scale = get_scale(),
    }, panel)

    make("UICorner", {
        CornerRadius = UDim.new(0, 16),
    }, panel)

    make("UIStroke", {
        Color = Color3.fromRGB(75, 80, 90),
        Transparency = 0.25,
        Thickness = 1,
    }, panel)

    make("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(22, 16),
        Size = UDim2.new(1, -44, 0, 42),
        Font = Enum.Font.GothamBlack,
        Text = CONFIG.title,
        TextColor3 = Color3.fromRGB(236, 239, 244),
        TextSize = 31,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, panel)

    make("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(23, 53),
        Size = UDim2.new(1, -46, 0, 20),
        Font = Enum.Font.Gotham,
        Text = "DRONE CONTROL",
        TextColor3 = Color3.fromRGB(142, 147, 157),
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, panel)

    make("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(22, 80),
        Size = UDim2.new(1, -44, 0, 20),
        Font = Enum.Font.Gotham,
        Text = "CHOOSE AIRFRAME",
        TextColor3 = Color3.fromRGB(110, 115, 125),
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, panel)

    local fpv = create_button(
        panel,
        "FPV DRONE",
        UDim2.fromOffset(22, 107),
        UDim2.new(1, -44, 0, 43)
    )

    local shahed = create_button(
        panel,
        "SHAHED 136",
        UDim2.fromOffset(22, 157),
        UDim2.new(1, -44, 0, 43)
    )

    make("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(22, 210),
        Size = UDim2.new(1, -44, 0, 20),
        Font = Enum.Font.Gotham,
        Text = "MOBILE JOYSTICK • CAMERA AIM • TOUCH",
        TextColor3 = Color3.fromRGB(100, 105, 115),
        TextSize = 8,
        TextXAlignment = Enum.TextXAlignment.Center,
    }, panel)

    fpv.Activated:Connect(function()
        start_drone(CONFIG.drones[1])
    end)

    shahed.Activated:Connect(function()
        start_drone(CONFIG.drones[2])
    end)

    scale.Scale = 0.86
    tween(scale, 0.25, {Scale = get_scale()})

    camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        if panel.Parent then
            scale.Scale = get_scale()
        end
    end)
end

local function create_flight_ui()
    local existing = player_gui:FindFirstChild("MM2_Drone_Flight_UI")
    if existing then
        existing:Destroy()
    end

    local gui = make("ScreenGui", {
        Name = "MM2_Drone_Flight_UI",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, player_gui)

    local right = make("Frame", {
        Name = "TouchControls",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -18, 1, -18),
        Size = UDim2.fromOffset(128, 180),
        BackgroundTransparency = 1,
    }, gui)

    local up = create_button(
        right,
        "▲",
        UDim2.fromOffset(44, 0),
        UDim2.fromOffset(68, 50)
    )

    local down = create_button(
        right,
        "▼",
        UDim2.fromOffset(44, 58),
        UDim2.fromOffset(68, 50)
    )

    local boost = create_button(
        right,
        "BOOST",
        UDim2.fromOffset(0, 116),
        UDim2.fromOffset(112, 46)
    )

    local close = create_button(
        gui,
        "×",
        UDim2.fromOffset(18, 18),
        UDim2.fromOffset(44, 44)
    )

    local function bind_hold(button, property)
        button.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch
                or input.UserInputType == Enum.UserInputType.MouseButton1 then
                state[property] = 1
            end
        end)

        button.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch
                or input.UserInputType == Enum.UserInputType.MouseButton1 then
                state[property] = 0
            end
        end)
    end

    bind_hold(up, "climb")
    bind_hold(down, "descend")
    bind_hold(boost, "boost")

    close.Activated:Connect(function()
        stop_drone()
    end)

    make("TextLabel", {
        Name = "Status",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0.03),
        Size = UDim2.fromOffset(320, 35),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Text = "DRONE ONLINE",
        TextColor3 = Color3.fromRGB(206, 210, 218),
        TextSize = 12,
        ZIndex = 20,
    }, gui)
end

local function get_primary(model)
    if model.PrimaryPart then
        return model.PrimaryPart
    end

    local part = model:FindFirstChildWhichIsA("BasePart", true)
    if part then
        model.PrimaryPart = part
    end

    return part
end

local function setup_model(model)
    local primary = get_primary(model)

    if not primary then
        return false
    end

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanQuery = false
            descendant.CanTouch = true
            descendant.Massless = true
        end
    end

    return true
end

local function create_sound(sound_id, volume, looped, parent)
    if not sound_id or sound_id == "" then
        return nil
    end

    local sound = make("Sound", {
        Name = "DroneSound",
        SoundId = sound_id,
        Volume = volume,
        Looped = looped,
        RollOffMaxDistance = 90,
        RollOffMinDistance = 8,
    }, parent)

    return sound
end

local function impact_target(target, direction)
    if not target then
        return
    end

    if not CollectionService:HasTag(target, "DroneTestTarget") then
        return
    end

    local now = os.clock()

    if now - state.last_impact < CONFIG.collision_cooldown then
        return
    end

    state.last_impact = now

    local root =
        target:FindFirstChild("HumanoidRootPart")
        or target.PrimaryPart
        or target:FindFirstChildWhichIsA("BasePart", true)

    if not root then
        return
    end

    local unit_direction = direction.Magnitude > 0 and direction.Unit or Vector3.new(0, 0, -1)

    root.AssemblyLinearVelocity =
        unit_direction * CONFIG.target_launch_speed
        + Vector3.new(0, -CONFIG.target_downward_speed, 0)

    root.AssemblyAngularVelocity = Vector3.new(0, 14, 8)

    show_signal("NO SIGNAL", 0.60)

    if state.impact_sound then
        state.impact_sound:Play()
    end
end

local function hook_collisions(model)
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Touched:Connect(function(other)
                local target = other:FindFirstAncestorOfClass("Model")

                if not target or target == model then
                    return
                end

                if player.Character and target == player.Character then
                    return
                end

                local direction = model.PrimaryPart and model.PrimaryPart.CFrame.LookVector
                    or Vector3.new(0, 0, -1)

                impact_target(target, direction)
            end)
        end
    end
end

local function prepare_player()
    local character = player.Character
    if not character then
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")

    state.saved_humanoid = humanoid
    state.saved_root = root

    if humanoid then
        state.saved_autorotate = humanoid.AutoRotate
        humanoid.AutoRotate = false
    end

    if root then
        state.saved_anchored = root.Anchored
        root.Anchored = true
    end
end

local function restore_player()
    if state.saved_humanoid and state.saved_humanoid.Parent then
        state.saved_humanoid.AutoRotate = state.saved_autorotate
    end

    if state.saved_root and state.saved_root.Parent then
        state.saved_root.Anchored = state.saved_anchored
    end

    state.saved_humanoid = nil
    state.saved_root = nil
end

function stop_drone()
    if not state.running then
        return
    end

    state.running = false

    if state.engine_sound then
        state.engine_sound:Stop()
        state.engine_sound:Destroy()
        state.engine_sound = nil
    end

    if state.impact_sound then
        state.impact_sound:Destroy()
        state.impact_sound = nil
    end

    if state.active_drone then
        state.active_drone:Destroy()
        state.active_drone = nil
    end

    state.active_config = nil
    state.velocity = Vector3.zero
    state.target_cframe = nil
    state.climb = 0
    state.descend = 0
    state.boost = 0

    restore_player()

    local flight_ui = player_gui:FindFirstChild("MM2_Drone_Flight_UI")
    if flight_ui then
        flight_ui:Destroy()
    end

    camera.CameraType = Enum.CameraType.Custom
    create_menu()
end

function start_drone(config)
    local drone_models = ReplicatedStorage:FindFirstChild("DroneModels")

    if not drone_models then
        warn("Missing ReplicatedStorage/DroneModels")
        return
    end

    local source = drone_models:FindFirstChild(config.model_name)

    if not source or not source:IsA("Model") then
        warn(("Missing drone model: %s"):format(config.model_name))
        return
    end

    stop_drone()

    local model = source:Clone()
    model.Name = "Active_MM2_Drone"
    model.Parent = workspace

    if not setup_model(model) then
        model:Destroy()
        return
    end

    local character = player.Character
    local character_root = character and character:FindFirstChild("HumanoidRootPart")

    local spawn_cframe = character_root
        and character_root.CFrame * CFrame.new(0, CONFIG.hover_height, -12)
        or CFrame.new(0, 8, 0)

    model:PivotTo(spawn_cframe)

    state.active_drone = model
    state.active_config = config
    state.running = true
    state.velocity = Vector3.zero
    state.target_cframe = spawn_cframe

    prepare_player()
    hook_collisions(model)

    state.engine_sound = create_sound(
        config.engine_sound_id,
        0.42,
        true,
        model.PrimaryPart
    )

    state.impact_sound = create_sound(
        config.impact_sound_id,
        0.70,
        false,
        model.PrimaryPart
    )

    if state.engine_sound then
        state.engine_sound:Play()
        state.engine_sound.PlaybackSpeed = 0.82
    end

    camera.CameraType = Enum.CameraType.Scriptable
    create_flight_ui()
end

RunService.RenderStepped:Connect(function(dt)
    if not state.running then
        return
    end

    local model = state.active_drone

    if not model or not model.Parent or not model.PrimaryPart then
        stop_drone()
        return
    end

    local config = state.active_config
    local current = state.target_cframe or model.PrimaryPart.CFrame

    -- Roblox mobile virtual joystick.
    -- move_vector.X = left/right.
    -- move_vector.Z = forward/back.
    local move_vector = controls:GetMoveVector()

    local horizontal_strength = math.clamp(
        Vector2.new(move_vector.X, move_vector.Z).Magnitude,
        0,
        1
    )

    -- Camera-relative direction:
    -- pushing the joystick forward makes the drone fly where the camera points.
    local camera_forward = camera.CFrame.LookVector
    local camera_right = camera.CFrame.RightVector

    local forward_amount = -move_vector.Z
    local right_amount = move_vector.X

    local direction =
        camera_forward * forward_amount
        + camera_right * right_amount

    if direction.Magnitude > 1 then
        direction = direction.Unit
    end

    -- Vertical touch buttons.
    local vertical =
        math.clamp(state.climb - state.descend, -1, 1)

    direction += Vector3.yAxis * vertical

    if direction.Magnitude > 1 then
        direction = direction.Unit
    end

    local speed_multiplier = state.boost == 1 and 1.65 or 1
    local max_speed = config.max_speed * speed_multiplier

    -- Built-in joystick controls speed by how far it is pushed.
    -- Camera pitch is included, so looking up makes forward flight climb.
    local target_velocity = direction * max_speed * math.max(horizontal_strength, math.abs(vertical))

    local alpha = 1 - math.exp(-config.acceleration * dt)
    state.velocity = state.velocity:Lerp(target_velocity, alpha)

    local next_position =
        current.Position
        + state.velocity * dt

    local look_direction =
        state.velocity.Magnitude > 2
        and state.velocity.Unit
        or current.LookVector

    local desired =
        CFrame.lookAt(next_position, next_position + look_direction, Vector3.yAxis)

    local turn_alpha = math.clamp(config.turn_rate * dt, 0, 1)
    state.target_cframe = current:Lerp(desired, turn_alpha)

    local speed_ratio = math.clamp(
        state.velocity.Magnitude / math.max(max_speed, 1),
        0,
        1
    )

    local bank = math.rad(-move_vector.X * config.tilt) * speed_ratio
    local pitch = math.rad(-move_vector.Z * config.tilt * 0.5) * speed_ratio

    model:PivotTo(
        state.target_cframe
        * CFrame.Angles(pitch, 0, bank)
    )

    -- Chase camera behind the drone.
    local drone_cf = model.PrimaryPart.CFrame
    local camera_position =
        drone_cf.Position
        - drone_cf.LookVector * CONFIG.camera_distance
        + Vector3.yAxis * CONFIG.camera_height

    local desired_camera =
        CFrame.lookAt(
            camera_position,
            drone_cf.Position + drone_cf.LookVector * 25,
            Vector3.yAxis
        )

    camera.CFrame = camera.CFrame:Lerp(
        desired_camera,
        math.clamp(dt * 10, 0, 1)
    )

    if state.engine_sound then
        local target_pitch = 0.82 + speed_ratio * 0.55

        state.engine_sound.PlaybackSpeed +=
            (target_pitch - state.engine_sound.PlaybackSpeed)
            * math.clamp(dt * 8, 0, 1)

        state.engine_sound.Volume =
            0.30 + speed_ratio * 0.25
    end
end)

player.CharacterAdded:Connect(function()
    if state.running then
        stop_drone()
    end
end)

create_menu()

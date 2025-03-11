-- @module SkydivingHandler
-- @author Krcnos
-- @brief Handles skydiving & parachuting on the client

-- Removed dependencies by 23sinek345

local Knit = require(game:GetService("ReplicatedStorage").Packages.Knit)

--Services
local Players = game:GetService("Players")
local sound = game:GetService("SoundService")
local tween = game:GetService("TweenService")
local run = game:GetService("RunService")
local input = game:GetService("UserInputService")
local context = game:GetService("ContextActionService")
local gui = game:GetService("GuiService")

--Constants
local Player = Players.LocalPlayer
print("This is the player.",Player)

--Globals
local mobileConnections = {}
local nextState = "Idle"

--Set this value correctly
local Platform = "PC"

local MIN_DIS = 500 -- Amount of studs from ground before player can't initiate a freefall or deploy their parachute
local FALL_TIME_BEFORE_DEPLOY = 1 -- sec
local FD_MIN_VAL = 95 -- Minimum velocity before damage (Fall Damage)
local FD_MAX_VAL = 205 -- Maximum velocity before death (Fall Damage)
local C_INPT = 1.57 -- Convergence Input Speed (Other)
local D_INPT_MAX = 1.5 -- Congergence Input Speed (Dive)
local D_INPT_MIN = .66 -- Congergence Input Speed (Dive)
local SPR_SENS = .51 -- Spring adjustment sensitivity
local FF_MIN_VAL = -100 -- Minimum negative velocity to start freefalling
local ALTITUDE_MAX = 6500 -- Max height on the altitude bar that the indicator is scaled to

local camera = workspace.CurrentCamera
local animations = script:WaitForChild("Animations")
local parachuteSound = sound:WaitForChild("Parachute")

local wind = sound:WaitForChild("Wind_SFX")

local SkydivingController = Knit.CreateController {
	Name = "SkydivingController",
}

local binds = {
	Skydive = {
		SkydiveForward = D_INPT_MAX,
		SkydiveBackward = D_INPT_MIN,
		SkydiveLeft = -C_INPT,
		SkydiveRight = C_INPT,
		SkydiveFlare = true,
	},
	Parachute = {
		ParachuteForward = -1,
		ParachuteBackward = 1,
		ParachuteLeft = -.75,
		ParachuteRight = .75,
		SkydiveFlare = true,
	}
}

-- Standalone spring Module --
local Spring = {}
Spring.__index = Spring
function Spring.new(freq, pos)
	local self = setmetatable({}, Spring)
	self.f = freq
	self.p = pos
	self.v = pos*0
	return self
end
function Spring:Update(dt, goal)
	local f = self.f*2*math.pi
	local p0 = self.p
	local v0 = self.v

	local offset = goal - p0
	local decay = math.exp(-f*dt)

	local p1 = goal + (v0*dt - offset*(f*dt + 1))*decay
	local v1 = (f*dt*(offset*f - v0) + v0)*decay

	self.p = p1
	self.v = v1

	return p1
end
function Spring:Reset(pos)
	self.p = pos
	self.v = pos*0
end
------------------------------

function SkydivingController:BindControls(controlType)
	self:UnbindControls()

	local flareEnabled = false
	local function input(action, state)
		if state == Enum.UserInputState.Begin then
			-- Skydiving Binds Press
			if action == "SkydiveForward" or action == "SkydiveBackward" then
				self.speedConvergence = binds.Skydive[action]
			elseif action == "SkydiveLeft" or action == "SkydiveRight" then
				self.twistConvergence = binds.Skydive[action]
			end

			-- Parachute Binds Press
			if action == "ParachuteForward" or action == "ParachuteBackward" then
				self.tiltSpeed = binds.Parachute[action]
				self:UpdateAnimation(action, "Press")
			elseif action == "ParachuteLeft" or action == "ParachuteRight" then
				self.twistSpeed = binds.Parachute[action]
				self:UpdateAnimation(action, "Press")
			end

			--[[
			if action == "SkydiveFlare" then
				local groundCheck = self:Raycast(self.Character.Torso.Position, Vector3.new(0, -7, 0))
				if not groundCheck then
					SkydivingService:ToggleFlare()
				end
			end
			]]
		else
			-- Skydiving Binds Release
			if action == "SkydiveForward" or action == "SkydiveBackward" then
				self.speedConvergence = 1
			elseif action == "SkydiveLeft" or action == "SkydiveRight" then
				self.twistConvergence = 0
			end

			-- Parachute Binds Release
			if action == "ParachuteForward" or action == "ParachuteBackward" then
				self.tiltSpeed = 0
				self:UpdateAnimation(action, "Release")
			elseif action == "ParachuteLeft" or action == "ParachuteRight" then
				self.twistSpeed = 0
				self:UpdateAnimation(action, "Release")
			end
		end
	end

	if Platform == "Mobile" then
		task.delay(.01, function()
			InterfaceController.SetState("null")
		end)

		--TODO: Seperate PlayerModule from knit
		gui.TouchControlsEnabled = false
		--MobileControls:Disable()
		MobileInterface.ArrowKeys.Visible = true
		--MobileInterface.ToggleFlare.Visible = true

		for _,controlFrame in MobileInterface.ArrowKeys:GetChildren() do
			table.insert(mobileConnections,controlFrame.Button.InputBegan:Connect(function(_input)
				input(controlType .. controlFrame.Name, _input.UserInputState)
			end))
			table.insert(mobileConnections,controlFrame.Button.InputEnded:Connect(function(_input)
				input(controlType .. controlFrame.Name, _input.UserInputState)
			end))
		end

		table.insert(mobileConnections,MobileInterface.ToggleFlare.Button.Activated:Connect(function()
			input("SkydiveFlare", Enum.UserInputState.Begin)
		end))
	else
		for bind,_ in binds[controlType] do
			context:BindAction(bind, input, true, table.unpack(self.keybinds[bind]))
		end

		--[[
		if not ControlSchema.IsCached("Skydive") then
			local binds = InputController:GetKeybinds("Player", true)
			ControlSchema.new("Skydive", {
				{binds.SkydiveFlare, "Flare"};
			})
		end
		]]


		run.Stepped:Wait()
		--ControlSchema.SetBinds("Skydive")
	end
end

function SkydivingController:UnbindControls()
	InterfaceController.SetState("Player")
	--TODO: Seperate PlayerModule from knit
	--TODO: Custom gui for mobile
	gui.TouchControlsEnabled = true
	--MobileControls:Enable()
	MobileInterface.ArrowKeys.Visible = false
	--MobileInterface.ToggleFlare.Visible = false

	if mobileConnections then
		for _,connection in mobileConnections do
			connection:Disconnect()
		end
	end
	--else
	for _,controlType in binds do
		for bind,_ in controlType do
			context:UnbindAction(bind)
		end
	end

	--ControlSchema.SetBinds("Player")
end

function SkydivingController:UpdateAnimation(action, animType)
	if self.animations[action] then
		if animType == "Press" then
			self.animations[action]:Play(.6)
		else 
			self.animations[action]:Stop()
		end
	end
end

function SkydivingController:LoadAnimations()
	self.animations = {}
	local animator = self.Humanoid:WaitForChild("Animator")

	for _,animation in animations:GetChildren() do
		self.animations[animation.Name] = animator:LoadAnimation(animation)
	end

	self.animations.ParachuteIdle:Play(.5, .8)
end

function SkydivingController:StopAnimations()
	if self.animations then
		for _,animation in self.animations do
			animation:Stop()
		end
	end
end

-- Checks if the character is above the minimum fall start height & the minimum deploy height
function SkydivingController:IsAbove(height)
	if not self.Character:FindFirstChild("HumanoidRootPart") then
		return false
	end

	return self.Character.HumanoidRootPart.Position.Y > (height or MIN_DIS)
end

function SkydivingController:CalcFallDamage(stateChange)
	if stateChange and self.ActiveDive or self.ParachuteStatus == "Deployed" then
		return
	end

	local velocity = self.RootPart.Velocity.Y
	local differential = nil

	-- If actively freefalling then player should die on impact
	if self.ActiveDive then
		differential = 1

		-- Calculate fall damage based on velocity mediums
	elseif velocity < -FD_MIN_VAL and velocity > -FD_MAX_VAL then
		differential = (math.abs(velocity) - math.abs(FD_MIN_VAL)) / (FD_MAX_VAL - FD_MIN_VAL)

		-- Kill players for having a velocity too high on impact
	elseif velocity < -FD_MAX_VAL then
		differential = 1
	end

	if differential then
		SkydivingService:FallDamage(differential)
	end

	return differential
end

function SkydivingController:UpdateInterface()
	--local torsoAlt = math.floor(self.Character.Torso.Position.Y)
	--local torsoSpeed = math.abs(math.floor(self.Character.Torso.Velocity.Y))
	--local barPos = math.clamp(1 - self.Character.Torso.Position.Y / ALTITUDE_MAX, 0, 1)

	--PlayerInfo.Altitude.Indicator.Position = UDim2.fromScale(0, barPos)
	--PlayerInfo.Altitude.Indicator.speed.Text = ("<b>%d</b> mph"):format(torsoSpeed)
	--PlayerInfo.Altitude.Indicator.alt.Text = ("<b>%d</b> ft"):format(torsoAlt)
end

function SkydivingController:EnableInterface(bool)
	--PlayerInfo.Altitude.Visible = bool
end

function SkydivingController:ResetJoints()
	self.joints.RArmJoint.C0 = CFrame.new(1, 0.5, 0) * CFrame.Angles(0, math.pi/2, 0)
	self.joints.RArmJoint.C1 = CFrame.new(-.5, 0.5, 0) * CFrame.Angles(0, math.pi/2, 0)
	self.joints.LArmJoint.C0 = CFrame.new(-1, 0.5, 0) * CFrame.Angles(0, -math.pi/2, 0)
	self.joints.LArmJoint.C1 = CFrame.new(0.5, .5, 0) * CFrame.Angles(0, -math.pi/2, 0)
	self.joints.RHipJoint.C0 = CFrame.new(1, -1, 0) * CFrame.Angles(0, math.pi/2, 0)
	self.joints.RHipJoint.C1 = CFrame.new(0.5, 1, 0) * CFrame.Angles(0, math.pi/2, 0)
	self.joints.LHipJoint.C0 = CFrame.new(-1, -1, 0) * CFrame.Angles(0, -math.pi/2, 0)
	self.joints.LHipJoint.C1 = CFrame.new(-0.5, 1, 0) * CFrame.Angles(0, -math.pi/2, 0)
end

function ChangeWeld(Weld, C0, C1)
	Weld.C0, Weld.C1 = C0, C1
end

-- Skydiving properties
local horSpeed = 280
local slowHorSpeed = 150

function SkydivingController:CalcSkydive(dt, character)
	local character = character or self.Character
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		self:StopSkydive()
	end

	local rootJoint = rootPart.RootJoint

	-- Calculate character angles
	self.twist = (self.twist * 31 + self.twistConvergence) / 32
	self.speed = (self.speed * 15 + self.speedConvergence) / 16;

	local VMag = math.sqrt(character.Torso.Velocity.Magnitude / 48)
	local DMag = ((character.Torso.CFrame * CFrame.Angles(1.57, 0, 0)).lookVector - character.Torso.Velocity.unit).Magnitude
	local raise = math.max(math.min(character.Torso.Velocity.y / 800 / self.speed - DMag * VMag / 4, 1), -1);

	ChangeWeld(self.joints.RArmJoint,
		CFrame.new(1.5, 0.5, 0) * CFrame.Angles(raise, (math.random() * 0.2 - 0.1) * raise, 1.825 / self.speed - 1.57 - self.twist / 1.5),
		CFrame.new(0, 0.5, 0))
	ChangeWeld(self.joints.LArmJoint, 
		CFrame.new(-1.5, 0.5, 0) * CFrame.Angles(raise, (math.random() * 0.2 - 0.1) * raise, -1.825 / self.speed + 1.57 - self.twist / 1.5),
		CFrame.new(0, 0.5, 0))
	ChangeWeld(self.joints.RHipJoint,
		CFrame.new(0.5, -1, 0) * CFrame.Angles(raise, (math.random() * 0.2 - 0.1) * raise, 1.046 / self.speed - 0.698 - self.twist / 1.5),
		CFrame.new(0, 1, 0))
	ChangeWeld(self.joints.LHipJoint,
		CFrame.new(-0.5, -1, 0) * CFrame.Angles(raise, (math.random() * 0.2 - 0.1) * raise, -1.046 / self.speed + 0.698 - self.twist / 1.5),
		CFrame.new(0, 1, 0))

	local CurrentCameraLV = workspace.CurrentCamera.CoordinateFrame.lookVector;

	local torsoSpeed = character.Torso.Velocity.Magnitude
	character.Torso.CFrame = CFrame.new(character.Torso.Position, 
		character.Torso.Position + (CurrentCameraLV + (character.Torso.CFrame * CFrame.Angles(1.57 - math.min(0.1 * self.speed - 0.1, 0), 0, 0)).lookVector 
			* math.max(torsoSpeed / 48 - 1, 7)) / math.max(torsoSpeed / 48, 8)) * CFrame.Angles(-1.57, self.twist, 0)

	local torsoAngle = character.Torso.CFrame - character.Torso.CFrame.p
	local goal = character.Torso.Velocity - torsoAngle * (torsoAngle:inverse() * character.Torso.Velocity / 30 / 
		Vector3.new(
			10 / math.min(self.speed, self.speed ^ 3),  
			math.max(self.speed, self.speed ^ 3) * 10, 
			math.min(self.speed ^ 3 / 5, 0.2)
		)
	)

	local latSpeed = (self.speedConvergence == D_INPT_MIN and slowHorSpeed) or horSpeed

	character.Torso.Velocity = Vector3.new(math.clamp(goal.X, -latSpeed, latSpeed), math.clamp(goal.Y, -500, -180), math.clamp(goal.Z, -horSpeed, horSpeed))
	character.Torso.RotVelocity = Vector3.new(0, 0, 0)

	wind.PlaybackSpeed = ((torsoSpeed / 600) * 12) + 5
end

function SkydivingController:Raycast(origin, direction)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {self.Character}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local result = workspace:Raycast(origin, direction, raycastParams)

	if result and result.Instance and result.Instance.Transparency == 1 then
		if result.Instance.Size.X * result.Instance.Size.Y * result.Instance.Size.Z > 15 then
			result = nil
		end
	end

	return result and result.Instance or nil
end

function SkydivingController:StartSkydive()
	if self.ActiveDive or self.ParachuteStatus == "Deployed" then
		return
	end

	self.Humanoid.AutoRotate = false
	self.ActiveDive = true
	self:BindControls("Skydive")

	self.Character.Humanoid.PlatformStand = true
	self.Character["Left Arm"].Trail.Enabled = true
	self.Character["Right Arm"].Trail.Enabled = true

	wind.Volume = 0
	wind:Play()
	self.windFadeIn:Play()

	--self:EnableInterface(true)

	if self.skydive then
		coroutine.close(self.skydive)
		self.skydive = nil
	end

	self.skydive = task.spawn(function()
		while self.ActiveDive do
			self:CalcSkydive()

			if self.Humanoid.Health <= 0 then
				self:StopSkydive()
				break
			end

			local groundCheck = self:Raycast(self.Character.Torso.Position, Vector3.new(0, -7, 0))
			if groundCheck then
				self:StopSkydive()
				break
			end

			local headCheck = self:Raycast(self.Character.Head.Position, self.Character.Head.CFrame.upVector * 4)
			if headCheck then
				self:StopSkydive()
				break
			end

			if nextState == "Deploy" then
				--Can do something here when player is too close to ground
				--if not self:IsAbove(1000) then
				--end

				if not self:IsAbove() then
					context:UnbindAction("Deploy")
				end
			end

			--self:UpdateInterface()

			task.wait()
		end
	end)
end

function SkydivingController:StopSkydive(calledFromDeploy)
	self:UnbindControls()

	if not calledFromDeploy then
		self:CalcFallDamage()
	end

	self.ActiveDive = false

	self:ResetJoints()

	self.Humanoid.AutoRotate = true
	self.Humanoid.PlatformStand = false
	self.Character["Left Arm"].Trail.Enabled = false
	self.Character["Right Arm"].Trail.Enabled = false
	self.Character.Torso.Velocity /= 3

	self.RootJoint.C0 = CFrame.Angles(math.pi/2, math.pi, 0)
	self:EnableInterface(false)
	wind:Stop()
end

-- Parachute properties
local maxForwardVelocity = 50
local maxTilt = 40
local minTilt = 5
local tiltSpeed = 2
local maxTwist = 50
local twistSpeedZAxis = 1.25
local maxRotationSpeed = 1.5

function SkydivingController:CalcParachute(dt)
	local x = self.Character.Torso.Orientation.X
	local y = self.Character.Torso.Orientation.Y
	local z = self.Character.Torso.Orientation.Z

	local _tilt = self.tiltSpring:Update(dt * .7, self.tiltSpeed)
	local _twist = self.twistSpring:Update(dt * .7, self.twistSpeed)

	-- Forward/backward movement
	if (x > -maxTilt and _tilt < 0) or (x < maxTilt / 3.6 and _tilt > 0) then
		self.RootJoint.C1 *= CFrame.Angles(math.rad(_tilt),0,0)
	end

	-- Left/right movement
	if (z < maxTwist and _twist < 0) or (z > -maxTwist and _twist > 0) then
		self.RootJoint.C1 *= CFrame.Angles(0,math.rad(_twist),0)
	end

	if z > 0 then
		self.Character.HumanoidRootPart.CFrame *= CFrame.Angles(0,math.rad(((z/maxTwist)*maxRotationSpeed)),0)
	elseif z < 0 then
		self.Character.HumanoidRootPart.CFrame *= CFrame.Angles(0,math.rad((z/maxTwist)*maxRotationSpeed),0)
	end

	if x < 0 then
		self.Character.Torso.Velocity = self.Character.Torso.CFrame.lookVector * (((-x)+(maxTilt/.7))/maxTilt) * maxForwardVelocity
	else
		self.Character.Torso.Velocity = self.Character.Torso.CFrame.lookVector * maxForwardVelocity/.7
	end
end

function SkydivingController:DeployParachute()
	self.lastDeployed = tick()
	SkydivingService:OpenCanopy()
	self.ParachuteStatus = "Deployed"

	self:LoadAnimations()

	self.Humanoid.AutoRotate = false
	self.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	self.Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

	self:BindControls("Parachute")

	parachuteSound:Play()
	self:EnableInterface(true)

	run:UnbindFromRenderStep("Parachute")


	context:UnbindAction("Deploy")

	task.wait()

	local CutParachute = function()
		if self.ParachuteStatus == "Deployed" then
			self:CutParachute()

			if self:IsAbove() and not self:Raycast(self.Character.Torso.Position, Vector3.new(0, -200, 0)) then
				self:StartSkydive()
			end
		end
	end


	--TODO: Add Mobile and Console actions
	warn("I just binded CUT action")
	context:BindAction("Cut", CutParachute, true, Enum.KeyCode.X)

	local rotationTick = tick()
	run:BindToRenderStep("Parachute", Enum.RenderPriority.Camera.Value, function(dt)
		if self.ParachuteStatus ~= "Deployed" then
			print("[DEBUG]: For some reason this keeps running or it just runs once idk?")
			run:UnbindFromRenderStep("Parachute")
		end

		self:CalcParachute(dt)
		--self:UpdateInterface()

		local frontCheck = self:Raycast(self.Character.Torso.Position, self.Character.Torso.CFrame.lookVector * 4)
		local groundCheck = self:Raycast(self.Character.Torso.Position, Vector3.new(0, -7, 0))
		if groundCheck or frontCheck then
			self:CutParachute()
			run:UnbindFromRenderStep("Parachute")

			context:UnbindAction("Cut")

			if self.backPrompt then
				self.backPrompt:Disconnect()
			end
		end

		if tick() - rotationTick > .2 then
			SkydivingService:UpdateParachuteAngle(self.RootJoint.C1)
			rotationTick = tick()
		end
	end) 
end

function SkydivingController:CutParachute()
	self.ParachuteStatus = "Cut"

	self.Humanoid.AutoRotate = true
	self.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
	self.Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)

	parachuteSound:Stop()
	self:EnableInterface(false)

	run:UnbindFromRenderStep("Parachute")
	SkydivingService:Grounded(self.RootJoint.C1)
	self:UnbindControls()
	self:StopAnimations()

	self.RootJoint.C0 = CFrame.new(0, 0, 0) * CFrame.Angles(-math.pi/2, 0, math.pi)
	self.RootJoint.C1 = CFrame.new(0, 0, 0) * CFrame.Angles(-math.pi/2, 0, math.pi)
end

function SkydivingController:UpdateCharacter(character)
	print("Update character called.")
	self.Character = character
	self.RootPart = character:WaitForChild("HumanoidRootPart")
	self.RootJoint = self.RootPart:WaitForChild("RootJoint")
	self.Humanoid = character:WaitForChild("Humanoid")
	self.keybinds = InputController:GetKeybinds("Player")
	self.lastStateChange = tick()
	self.lastDeployed = tick()

	-- Unbind if player was actively skydiving and character was suddenly loaded
	if self.ActiveDive then
		self:StopSkydive()
	end

	self.ActiveDive = false
	self.ParachuteStatus = nil

	self.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
	self.Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)

	self.joints = {
		RArmJoint = character:WaitForChild("Torso"):FindFirstChild("Right Shoulder"),
		LArmJoint = character:WaitForChild("Torso"):FindFirstChild("Left Shoulder"),
		RHipJoint = character:WaitForChild("Torso"):FindFirstChild("Right Hip"),
		LHipJoint = character:WaitForChild("Torso"):FindFirstChild("Left Hip"),
	}

	self.twistConvergence = 0
	self.speedConvergence = 1
	self.twist = 0
	self.speed = 1

	self.tiltSpeed = 0
	self.twistSpeed = 0

	self.tiltSpring = Spring.new(1.5, 0)
	self.twistSpring = Spring.new(1.5, 0)

	self.windFadeIn = tween:Create(wind, TweenInfo.new(1.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {Volume = .35})


	context:UnbindAction("Cut")
	context:UnbindAction("Deploy")

	if self.backPrompt and self.backPrompt.Disconnect then
		self.backPrompt:Disconnect()
	end

	local lastStateChange = nil
	local startFreefall = nil
	local freefall
	freefall = self.Humanoid.FreeFalling:Connect(function(isFalling)
		print("Free falling bind.")
		local thisStateChange = nil
		if isFalling or (not isFalling and not self:IsAbove()) then
			self.lastStateChange = tick()
			thisStateChange = self.lastStateChange
		end

		if startFreefall and startFreefall.Connected then
			startFreefall:Disconnect(); startFreefall = nil
		end

		if not isFalling then
			self:CalcFallDamage(true)
			return
		end

		if self.isParachuting then
			task.wait(FALL_TIME_BEFORE_DEPLOY)
			return
		end

		if tick() - self.lastDeployed <= .5 then
			return
		end

		startFreefall = run.Stepped:Connect(function()
			if not character:FindFirstChild("Torso") then
				startFreefall:Disconnect()
				return
			end

			if character.Torso.Velocity.Y >= FF_MIN_VAL or (not self:IsAbove()) then
				return
			end

			startFreefall:Disconnect()
			if self.ParachuteStatus == "Equipped" then
				context:UnbindAction("Deploy")
				run.Stepped:Wait()

				-- Ensure static type parachutes can't deploy on their own
				if self.ParachuteType == "Regular" then
					local DeployFunction = function()
						if self.ActiveDive and self:IsAbove() then
							self:StopSkydive(true)
							self:DeployParachute()
						end
					end
					--TODO: Add Mobile and Console actions
					warn("I just binded DEPLOY action")
					context:BindAction("Deploy", DeployFunction, true, Enum.KeyCode.E)
				end
			end

			if not self:Raycast(self.Character.Torso.Position, Vector3.new(0, -200, 0)) then
				self:StartSkydive()
			end
		end)
	end)
end

function SkydivingController:KnitStart()
	SkydivingService = Knit.GetService("SkydivingService")
	InputController = Knit.GetController("InputController")
	InterfaceController = Knit.GetController("InterfaceController")
	--MobileControls = InterfaceController.GetInterface("MobileControls")
	--Prompt = require(Knit.Modules.InteractPrompt)

	MobileInterface = Player.PlayerGui:WaitForChild("MobileControls")
	--PlayerInfo = Player.PlayerGui:WaitForChild("PlayerInfo")

	--ControlSchema = InterfaceController.GetInterface("ControlSchema")

	if Player.Character then
		self:UpdateCharacter(Player.Character)
	end

	Player.CharacterAdded:Connect(function(character)
		self:UpdateCharacter(character)
	end)

	SkydivingService.CanopyUpdate:Connect(function(_canopy)
		--Parachute opening animation
		if not _canopy or (_canopy and not _canopy:FindFirstChild("Parachute")) then
			return
		end

		local origSize = _canopy.Parachute.Size
		_canopy.Parachute.Size = Vector3.new(1, 1, 1)
		tween:Create(_canopy.Parachute, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = origSize,
			Transparency = 0
		}):Play()
	end)

	local zoneSize = MIN_DIS / ALTITUDE_MAX
	--PlayerInfo.Altitude.AltitudeBar.BlackZone.Size = UDim2.fromScale(1, zoneSize)
	--PlayerInfo.Altitude.AltitudeBar.WhiteZone.Size = UDim2.fromScale(1, zoneSize)
	--PlayerInfo.Altitude.AltitudeBar.WhiteZone.Position = UDim2.fromScale(1, 1 - zoneSize)

	SkydivingService.UpdateRotation:Connect(function(root, angle)
		for t = 0, 101, 10 do
			root.RootJoint.C1 = root.RootJoint.C1:Lerp(angle, t/100)
			run.RenderStepped:Wait()
		end
	end)
end

return SkydivingController
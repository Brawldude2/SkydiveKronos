-- @module SkydivingService
-- @author Krcnos
-- @date 3/8/22

-- Modified by @23sinek345

local SkydivingService = {}

--Services
local Players = game:GetService("Players")
local serverStorage = game:GetService("ServerStorage")

--References
local RemoteEvents = game.ReplicatedStorage.RemoteEvents.SkydivingSystem

--Constants
local RESET_CFRAME = CFrame.new(0, 0, 0) * CFrame.Angles(-math.pi/2, 0, math.pi)


--TODO: Change with local equippables
local equippables = serverStorage:WaitForChild("Equippables")
local canopy = equippables:WaitForChild("Canopy")

local function FireExcept(remote: RemoteEvent, exclude: Player, ...: any)
	for _,player in Players:GetPlayers() do
		if player == exclude then
			continue
		end
		remote:FireClient(player,...)
	end
end

local staticNodes = {}
function SkydivingService:AddStatic(player, node)
	if staticNodes[player] then
		staticNodes[player]:Destroy()
		staticNodes[player] = nil
	end

	staticNodes[player] = node
end

function SkydivingService:CutLine(player)
	if staticNodes[player] then
		staticNodes[player]:Destroy()
		staticNodes[player] = nil
		print("Server Static disconnected!")
	end
end

RemoteEvents.UpdateParachuteAngle.OnServerEvent:Connect(function(player: Player, angle: CFrame)
	if not player.Character or (player.Character and not player.Character:FindFirstChild("HumanoidRootPart")) then
		return
	end

	if not player.Character.Appearance:FindFirstChild("Canopy") then
		return
	end

	FireExcept(RemoteEvents.UpdateParachuteAngle, player, player.Character.HumanoidRootPart, angle)
end)


RemoteEvents.Grounded.OnServerEvent:Connect(function(player: Player, ...: any)
	if not player.Character:FindFirstChild("HumanoidRootPart") then
		return
	end

	local drag = player.Character.HumanoidRootPart:FindFirstChild("Drag")
	if drag then drag:Destroy() end

	local list = {"Parachute", "Canopy", "ReflectiveBands", "Glowstick"}
	for _,item in list do
		local target = player.Character.Appearance:FindFirstChild(item)
		if target then
			target:Destroy()
		end
	end

	FireExcept(RemoteEvents.UpdateRotation, player, player.Character.HumanoidRootPart, RESET_CFRAME)
end)

RemoteEvents.OpenCanopy.OnServerEvent:Connect(function(player: Player, ...: any)
	if not player.Character then return end
	if not player.Character.Appearance:FindFirstChild("Parachute") then
		return
	end

	local drag = Instance.new("BodyVelocity")
	drag.Name = "Drag"
	drag.MaxForce = Vector3.new(4000,55000,4000)
	drag.Velocity = Vector3.new(0,-90,0)
	drag.Parent = player.Character.HumanoidRootPart

	--TODO: Give canopy model to player
	local newCanopy = nil --CharacterModifier:AddModel(player.Character, canopy)

	RemoteEvents.CanopyUpdate:FireAllClients(newCanopy)
end)

return SkydivingService
-- Services --
local RNS = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local TS = game:GetService("TweenService")

-- Modules --
local modules = RS.Modules
local Curve = require(modules.Curve)

-- Remotes --
local movementRemotes = RS.Remotes.Movement
local moveDirRE = movementRemotes.MoveDirectionRE

-- CONSTANTS --
local WALK_SPEED = 20
local LEG_DISTANCE = 3
local CURVE_HEIGHT = 3
local CURVE_SPEED = 50
local RESET_TIME = 2 / (WALK_SPEED * 0.75)

-- Script --
local model = script.Parent
local humanoid = model.Humanoid
local body = model.Body
local rootPart = model.PrimaryPart

local frontLeftAtt = body.FrontLeftAtt
local frontLeftTarget = workspace.FrontLeftTarget

local backRightAtt = body.BackRightAtt
local backRightTarget = workspace.BackRightTarget

local lastBody = body.CFrame

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = {model}

local legGroup = 0
local currentTime = RESET_TIME

local legs = {}
local curves, curveTimes, curveBools = {}, {}, {}

-- Instantiates the Poles and Targets for each leg
local function initializeLegs()
	for _, child in pairs(model:GetChildren()) do
		if child:IsA("Model") then
			local pole = Instance.new("Attachment", body)
			pole.Name = child.Name .. "Pole"
			pole.WorldCFrame = child.LowerLeg.KneeAtt1.WorldCFrame + Vector3.yAxis * 3
			
			local target = Instance.new("Part", workspace)
			target.Name = model.Name .. child.Name .. "Target"
			target.Anchored = true
			target.CanCollide = false
			target.CanQuery = false
			target.Size = Vector3.one
			target.Position = child.Foot.Position

			local IKControl = Instance.new("IKControl", humanoid)
			IKControl.Name = child.Name
			IKControl.Type = Enum.IKControlType.Position
			IKControl.ChainRoot = child.UpperLeg
			IKControl.EndEffector = child.Foot
			IKControl.Target = target
			IKControl.Pole = pole
			legs[child.Name] = {}
			legs[child.Name].Foot = child.Foot
			legs[child.Name].Att = body[child.Name .. "Att"]
			legs[child.Name].Target = IKControl.Target
			
			curveTimes[IKControl.Target] = 0
		end
	end
end

local function averagePositions(): boolean 
	local averageFootPosition = Vector3.zero
	for _, leg in legs do
		averageFootPosition += leg.Foot.Position
	end
	averageFootPosition /= 4
	return averageFootPosition
end

-- Checks the distance between a leg's raycast and its current position
local function checkDistance(rayAtt: Attachment, legTarget: BasePart)
	local startPos = rayAtt.WorldCFrame.Position + Vector3.new(0, 5, 0)
	local endPos = rayAtt.WorldCFrame.Position + Vector3.new(0, -50, 0)
	local raycast = workspace:Raycast(startPos, endPos - startPos, params)
	if (raycast.Position - legTarget.Position).Magnitude >= LEG_DISTANCE and not curveBools[legTarget] then
		return true
	end
end

-- Creates a curved path for the leg to follow based on the direction the player is moving
local function updateLeg(rayAtt: Attachment, legTarget: BasePart)
	local startPos = rayAtt.WorldCFrame.Position + Vector3.new(0, 5, 0)
	local endPos = rayAtt.WorldCFrame.Position + Vector3.new(0, -50, 0)
	local raycast = workspace:Raycast(startPos, endPos - startPos, params)
	
	local bodyDifference = body.CFrame:ToObjectSpace(body.CFrame).Position - body.CFrame:ToObjectSpace(lastBody).Position
	local forwardDirection = if bodyDifference.Z < 0 then 1 elseif bodyDifference.Z > 0 then -1 else 0
	local sideDirection = if bodyDifference.X > 0 then 1 elseif bodyDifference.X < 0 then -1 else 0
	local forwardPos = body.CFrame.LookVector * forwardDirection
	local sidePos = body.CFrame.RightVector * sideDirection
	local targetPos = raycast.Position + ((body.CFrame.LookVector * forwardDirection + body.CFrame.RightVector * sideDirection) * LEG_DISTANCE)
	
	local peakPos = legTarget.Position:Lerp(targetPos, 0.5)
	local yOffset = (legTarget.Position - peakPos).Magnitude
	peakPos += Vector3.new(0, yOffset, 0)

	curves[legTarget] = Curve.new({ legTarget.Position, peakPos, targetPos }, legTarget, CURVE_SPEED)
	curveBools[legTarget] = true
end

local lastAverage = averagePositions()
initializeLegs()
task.wait(1)
RNS.Heartbeat:Connect(function(deltaTime: number)  
  -- Places the body in between all 4 legs at an offset
	local averageFootPosition = averagePositions()
	if math.abs(averageFootPosition.Y - lastAverage.Y ) >= 1.5 then
		rootPart.CFrame = CFrame.new(rootPart.CFrame.Position.X, averageFootPosition.Y + 3, rootPart.CFrame.Position.Z)
		lastAverage = averageFootPosition
	end

  -- Controls the timer which controls how often the legs can be updated
	if currentTime <= RESET_TIME then
		currentTime += deltaTime
	end
	if currentTime >= RESET_TIME then 
    -- Assigns leg groups to move the legs in a zig-zag pattern
		local leg1, leg2 
		if legGroup == 0 then
			leg1 = "FrontLeft"
			leg2 = "BackRight"
		elseif legGroup == 1 then
			leg1 = "FrontRight"
			leg2 = "BackLeft"
		end
    -- If the distance between the 1st or 2nd leg is great enough, both legs in the current group will be moved to a calculated position
		if checkDistance(legs[leg1].Att, legs[leg1].Target) or checkDistance(legs[leg2].Att, legs[leg2].Target) then 
			updateLeg(legs[leg1].Att, legs[leg1].Target)
			updateLeg(legs[leg2].Att, legs[leg2].Target)
			lastBody = body.CFrame
      -- Incrememnts the legGroup
			legGroup = (legGroup + 1) % 2
      -- Resets curve time
			currentTime = 0
		end	
	end
  -- Controls the curve of each leg
	for leg, value in curveBools do
		if curveBools[leg] then
			curveTimes[leg] += deltaTime
			curves[leg]:Set(curveTimes[leg])
			if curveTimes[leg] >= curves[leg].TotalTime then
				curveBools[leg] = false
				curveTimes[leg] = 0
			end
		end
	end
end)

-- Event from the client script to determine what direction the player is moving in
moveDirRE.OnServerEvent:Connect(function(player: Player, direction: Vector3, walkSpeed: number)
	rootPart.CFrame = CFrame.new(rootPart.Position + (direction * walkSpeed))
end)

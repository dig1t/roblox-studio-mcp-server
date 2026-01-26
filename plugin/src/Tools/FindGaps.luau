local Main = script:FindFirstAncestor("MCPStudioPlugin")
local Types = require(Main.Types)
local HttpService = game:GetService("HttpService")

local MAX_GAPS = 50
local DEFAULT_THRESHOLD = 2
local SAMPLE_DENSITY = 2 -- Sample points per stud

local function serializeVector3(v: Vector3): { x: number, y: number, z: number }
	return { x = v.X, y = v.Y, z = v.Z }
end

local function resolveInstance(path: string): Instance?
	if not path or path == "" then
		return nil
	end

	-- Handle special case of just "workspace"
	if path == "workspace" then
		return workspace
	end

	-- Handle special case of just "game"
	if path == "game" then
		return game
	end

	local parts = string.split(path, ".")
	local current: Instance

	-- Determine starting point
	local firstPart = parts[1]
	if firstPart == "game" then
		current = game
		table.remove(parts, 1)
	elseif firstPart == "workspace" then
		current = workspace
		table.remove(parts, 1)
	else
		-- Default to game if no explicit root
		current = game
	end

	-- Navigate the path
	for _, part in parts do
		local child = current:FindFirstChild(part)
		if not child then
			return nil
		end
		current = child
	end

	return current
end

-- Get all BaseParts from an instance (handles both Models and single Parts)
local function getPartsFromInstance(instance: Instance): { BasePart }
	local parts: { BasePart } = {}

	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	return parts
end

-- Get bounding box center of an instance
local function getBoundingBoxCenter(instance: Instance): Vector3?
	if instance:IsA("Model") then
		local cf, _ = instance:GetBoundingBox()
		return cf.Position
	elseif instance:IsA("BasePart") then
		return instance.Position
	end
	return nil
end

-- Sample surface points on a part facing toward a target direction
local function getSurfacePoints(part: BasePart, targetDirection: Vector3): { Vector3 }
	local points: { Vector3 } = {}
	local cf = part.CFrame
	local size = part.Size

	-- Determine which faces face toward the target
	local localDir = cf:VectorToObjectSpace(targetDirection).Unit

	-- Define face normals and their corresponding face info
	local faces = {
		{ normal = Vector3.new(1, 0, 0), size = Vector3.new(size.Y, size.Z, 0), offset = Vector3.new(size.X / 2, 0, 0) },
		{ normal = Vector3.new(-1, 0, 0), size = Vector3.new(size.Y, size.Z, 0), offset = Vector3.new(-size.X / 2, 0, 0) },
		{ normal = Vector3.new(0, 1, 0), size = Vector3.new(size.X, size.Z, 0), offset = Vector3.new(0, size.Y / 2, 0) },
		{ normal = Vector3.new(0, -1, 0), size = Vector3.new(size.X, size.Z, 0), offset = Vector3.new(0, -size.Y / 2, 0) },
		{ normal = Vector3.new(0, 0, 1), size = Vector3.new(size.X, size.Y, 0), offset = Vector3.new(0, 0, size.Z / 2) },
		{ normal = Vector3.new(0, 0, -1), size = Vector3.new(size.X, size.Y, 0), offset = Vector3.new(0, 0, -size.Z / 2) },
	}

	for _, face in faces do
		-- Check if this face faces toward target (dot product > 0)
		local dot = localDir:Dot(face.normal)
		if dot > 0.1 then -- Face is pointing somewhat toward target
			local faceCenter = cf:PointToWorldSpace(face.offset)
			local faceNormal = cf:VectorToWorldSpace(face.normal)

			-- Determine face dimensions based on which axis is the normal
			local u, v
			if math.abs(face.normal.X) > 0.5 then
				u = cf.UpVector * (size.Y / 2)
				v = -cf.LookVector * (size.Z / 2)
			elseif math.abs(face.normal.Y) > 0.5 then
				u = cf.RightVector * (size.X / 2)
				v = -cf.LookVector * (size.Z / 2)
			else
				u = cf.RightVector * (size.X / 2)
				v = cf.UpVector * (size.Y / 2)
			end

			-- Sample points across the face
			local uSteps = math.max(2, math.floor(u.Magnitude * 2 * SAMPLE_DENSITY))
			local vSteps = math.max(2, math.floor(v.Magnitude * 2 * SAMPLE_DENSITY))

			-- Limit sampling to avoid too many points
			uSteps = math.min(uSteps, 10)
			vSteps = math.min(vSteps, 10)

			for ui = 0, uSteps do
				for vi = 0, vSteps do
					local uFrac = (ui / uSteps) * 2 - 1
					local vFrac = (vi / vSteps) * 2 - 1
					local point = faceCenter + u * uFrac + v * vFrac
					table.insert(points, point)
				end
			end
		end
	end

	return points
end

-- Create raycast filter for parts in model B
local function createFilterForModel(partsB: { BasePart }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = partsB
	return params
end

local function handleFindGaps(args: Types.ToolArgs): string?
	if not args["FindGaps"] then
		return nil
	end

	local toolArgs: Types.FindGapsArgs = args["FindGaps"]
	local threshold = toolArgs.threshold or DEFAULT_THRESHOLD

	-- Resolve both instances
	local instanceA = resolveInstance(toolArgs.model_a)
	local instanceB = resolveInstance(toolArgs.model_b)

	if not instanceA then
		return HttpService:JSONEncode({
			success = false,
			error = "Instance not found: " .. toolArgs.model_a,
		})
	end

	if not instanceB then
		return HttpService:JSONEncode({
			success = false,
			error = "Instance not found: " .. toolArgs.model_b,
		})
	end

	-- Get all parts from both instances
	local partsA = getPartsFromInstance(instanceA)
	local partsB = getPartsFromInstance(instanceB)

	if #partsA == 0 then
		return HttpService:JSONEncode({
			success = false,
			error = "No BaseParts found in model_a: " .. toolArgs.model_a,
		})
	end

	if #partsB == 0 then
		return HttpService:JSONEncode({
			success = false,
			error = "No BaseParts found in model_b: " .. toolArgs.model_b,
		})
	end

	-- Get center of B to determine direction
	local centerB = getBoundingBoxCenter(instanceB)
	if not centerB then
		return HttpService:JSONEncode({
			success = false,
			error = "Could not determine center of model_b",
		})
	end

	-- Create raycast params to only hit parts in B
	local rayParams = createFilterForModel(partsB)

	local gaps: { any } = {}
	local totalPointsChecked = 0

	-- For each part in A, sample surface points facing B and raycast
	for _, partA in partsA do
		local directionToB = (centerB - partA.Position).Unit
		local surfacePoints = getSurfacePoints(partA, directionToB)

		for _, point in surfacePoints do
			totalPointsChecked += 1

			-- Cast ray from surface point toward B
			local rayDirection = directionToB * (threshold * 10) -- Cast far enough
			local result = workspace:Raycast(point, rayDirection, rayParams)

			if result then
				-- Hit something in B
				local distance = (result.Position - point).Magnitude

				if distance > threshold then
					-- This is a gap
					table.insert(gaps, {
						position = serializeVector3((point + result.Position) / 2),
						distance = math.floor(distance * 100) / 100,
						nearestInA = serializeVector3(point),
						nearestInB = serializeVector3(result.Position),
					})

					-- Limit number of gaps returned
					if #gaps >= MAX_GAPS then
						break
					end
				end
			else
				-- Ray didn't hit B at all - could be a gap or just not facing B
				-- Only count as gap if we're reasonably close to B
				local distToB = (centerB - point).Magnitude
				if distToB < threshold * 5 then
					-- Try to find closest point on B
					local closestDist = math.huge
					local closestPoint: Vector3? = nil

					for _, partB in partsB do
						local dist = (partB.Position - point).Magnitude
						if dist < closestDist then
							closestDist = dist
							closestPoint = partB.Position
						end
					end

					if closestPoint and closestDist > threshold then
						table.insert(gaps, {
							position = serializeVector3((point + closestPoint) / 2),
							distance = math.floor(closestDist * 100) / 100,
							nearestInA = serializeVector3(point),
							nearestInB = serializeVector3(closestPoint),
						})

						if #gaps >= MAX_GAPS then
							break
						end
					end
				end
			end
		end

		if #gaps >= MAX_GAPS then
			break
		end
	end

	return HttpService:JSONEncode({
		success = true,
		hasGaps = #gaps > 0,
		gapCount = #gaps,
		gaps = gaps,
		metadata = {
			threshold = threshold,
			pointsChecked = totalPointsChecked,
			partsInA = #partsA,
			partsInB = #partsB,
			maxGapsReached = #gaps >= MAX_GAPS,
		},
	})
end

return handleFindGaps :: Types.ToolFunction

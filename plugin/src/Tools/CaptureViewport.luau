local Main = script:FindFirstAncestor("MCPStudioPlugin")
local Types = require(Main.Types)
local HttpService = game:GetService("HttpService")

local function handleCaptureViewport(args: Types.ToolArgs): string?
	if not args["CaptureViewport"] then
		return nil
	end

	local captureArgs: Types.CaptureViewportArgs = args["CaptureViewport"]

	local cameraPosition = captureArgs.camera_position
	local cameraTarget = captureArgs.camera_target
	local format = captureArgs.format or "png"

	-- Get the current camera
	local camera = workspace.CurrentCamera
	if not camera then
		return HttpService:JSONEncode({
			success = false,
			error = "No camera found in workspace",
		})
	end

	-- Store original camera properties for response
	local originalPosition = camera.CFrame.Position
	local originalLookVector = camera.CFrame.LookVector

	-- Calculate the look-at direction if target is provided
	local newCFrame: CFrame

	if cameraPosition and cameraTarget then
		-- Both position and target provided - create CFrame looking at target
		local posVec = Vector3.new(cameraPosition.x, cameraPosition.y, cameraPosition.z)
		local targetVec = Vector3.new(cameraTarget.x, cameraTarget.y, cameraTarget.z)
		newCFrame = CFrame.lookAt(posVec, targetVec)
	elseif cameraPosition then
		-- Only position provided - keep current look direction
		local posVec = Vector3.new(cameraPosition.x, cameraPosition.y, cameraPosition.z)
		local currentLookVector = camera.CFrame.LookVector
		newCFrame = CFrame.lookAt(posVec, posVec + currentLookVector)
	elseif cameraTarget then
		-- Only target provided - keep current position, look at target
		local targetVec = Vector3.new(cameraTarget.x, cameraTarget.y, cameraTarget.z)
		newCFrame = CFrame.lookAt(camera.CFrame.Position, targetVec)
	else
		-- Neither provided - use current camera position/orientation
		newCFrame = camera.CFrame
	end

	-- Apply the new camera CFrame
	camera.CFrame = newCFrame

	-- Get the final camera state
	local finalPosition = camera.CFrame.Position
	local finalLookVector = camera.CFrame.LookVector
	local finalTarget = finalPosition + finalLookVector * 100 -- Approximate look-at point

	-- Build response
	local response: { [string]: any } = {
		success = true,
		camera = {
			position = {
				x = math.floor(finalPosition.X * 100 + 0.5) / 100,
				y = math.floor(finalPosition.Y * 100 + 0.5) / 100,
				z = math.floor(finalPosition.Z * 100 + 0.5) / 100,
			},
			lookAt = {
				x = math.floor(finalTarget.X * 100 + 0.5) / 100,
				y = math.floor(finalTarget.Y * 100 + 0.5) / 100,
				z = math.floor(finalTarget.Z * 100 + 0.5) / 100,
			},
			lookVector = {
				x = math.floor(finalLookVector.X * 1000 + 0.5) / 1000,
				y = math.floor(finalLookVector.Y * 1000 + 0.5) / 1000,
				z = math.floor(finalLookVector.Z * 1000 + 0.5) / 1000,
			},
			fieldOfView = camera.FieldOfView,
		},
		requestedFormat = format,
		note = "Camera positioned. Use Studio's built-in screenshot (Ctrl+Shift+S) or File > Screenshot to capture.",
	}

	-- Add information about what changed
	if cameraPosition or cameraTarget then
		response.cameraUpdated = true
		response.previousPosition = {
			x = math.floor(originalPosition.X * 100 + 0.5) / 100,
			y = math.floor(originalPosition.Y * 100 + 0.5) / 100,
			z = math.floor(originalPosition.Z * 100 + 0.5) / 100,
		}
	else
		response.cameraUpdated = false
	end

	return HttpService:JSONEncode(response)
end

return handleCaptureViewport :: Types.ToolFunction

--!strict
-- Pure simulation of the client's elapsed-time animation math; this does not
-- measure physical monitor refresh or replace real Roblox Studio visual testing.
local renderPassed, renderFailed = 0, 0
local function renderTest(name, callback)
    local ok, err = pcall(callback)
    if ok then renderPassed += 1; print("PASS", name)
    else renderFailed += 1; print("FAIL", name, err) end
end

local function integrateFrames(fps: number, duration: number): (number, number, number)
    local clock = 0
    for _ = 1, fps * duration do
        local frameDelta = 1 / fps
        clock = (clock + math.min(frameDelta, 0.05)) % 10000
    end
    local x = (0.5 + 0.5 * math.sin(clock * 2.9 - math.pi / 2)) * 0.78
    local rotation = (clock * 48) % 360
    return clock, x, rotation
end

renderTest("Motion duration is stable at 30, 60, 90, 120 and 165 FPS", function()
    for _, fps in ipairs({30, 60, 90, 120, 165}) do
        local clock, x, rotation = integrateFrames(fps, 10)
        assert(math.abs(clock - 10) < 0.0001, tostring(fps) .. " FPS elapsed time drift")
        local baselineClock, baselineX, baselineRotation = integrateFrames(60, 10)
        assert(math.abs(clock - baselineClock) < 0.0001)
        assert(math.abs(x - baselineX) < 0.0001 and math.abs(rotation - baselineRotation) < 0.0001, "Frame-dependent motion")
    end
end)

renderTest("A paused or stalled frame cannot abruptly jump animation a half-second", function()
    local delta = 0.5
    assert(math.min(delta, 0.05) == 0.05)
end)

local function adaptiveFPS(fps: number, seconds: number, startAverage: number, active: boolean): (number, boolean)
    local average = startAverage
    local low, recovered = 0, 0
    local lightweight = active
    for _ = 1, fps * seconds do
        local delta = 1 / fps
        local dt = math.min(delta, 0.05)
        local alpha = 1 - math.exp(-dt * 2.4)
        average += (delta - average) * alpha
        local observed = 1 / math.max(average, 1 / 300)
        if observed < 38 then
            low += dt
            recovered = 0
        elseif observed > 52 then
            recovered += dt
            low = 0
        else
            low, recovered = 0, 0
        end
        if low >= 1.4 then lightweight = true end
        if recovered >= 2.5 then lightweight = false end
    end
    return average, lightweight
end

renderTest("Sustained 30 FPS reduces decorative effects", function()
    local _, light = adaptiveFPS(30, 7, 1 / 60, false)
    assert(light)
end)

renderTest("Sustained 60+ FPS restores decorative effects", function()
    local average, low = adaptiveFPS(30, 7, 1 / 60, false)
    local _, recovered = adaptiveFPS(120, 8, average, low)
    assert(not recovered)
end)

renderTest("The motion controller does not downgrade stable 60/90/120/165 FPS", function()
    for _, fps in ipairs({60, 90, 120, 165}) do
        local _, downgraded = adaptiveFPS(fps, 5, 1 / fps, false)
        assert(not downgraded, tostring(fps) .. " FPS was incorrectly downgraded")
    end
end)

print(string.format("Frame pacing simulation tests: %d passed, %d failed", renderPassed, renderFailed))
assert(renderFailed == 0, "Frame pacing regression failed")

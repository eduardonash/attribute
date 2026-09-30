-- Exercise production profiling/window aggregation without a live client.
return function(source, returnFixture)
    local function section(first, last)
        local a = assert(source:find(first, 1, true), 'missing section: ' .. first)
        local b = assert(source:find(last, a, true), 'missing section end: ' .. last)
        return source:sub(a, b - 1)
    end
    local profiling = section('shellRedirection.performance = {', 'local aimIncludeParams')
    local focusFrame = section('function shellRedirection.frame(cam)', 'function shellRedirection.destroy()')
    local renderPrefix = section('RunService:BindToRenderStep("AttributePlayerESP",',
        '    shellRedirection.frameMs=')
    local transport = section('shellRedirection.tick=RunService.Heartbeat:Connect(function()',
        'heldFire.tick = RunService.Heartbeat:Connect(function()')
    local telemetry = section('_G.AutoLeadAssistFocusTelemetry = function()',
        '_G.AutoLeadAssistDiagnostics = function()')
    local code = [[
local passed = 0
local function check(value, label) assert(value, label); passed += 1 end
local function close(a, b) return math.abs(a-b) < 1e-6 end
local clock = 0
local os = {clock = function() return clock end}
-- Luau-Web's bridge propagates native error() across even pcall/xpcall. Model
-- protected failure explicitly so fault-injection tests still exercise the
-- extracted production marker/cleanup order. Native assert remains unchanged.
local errorTag = {}
local function error(message)
    return coroutine.yield(errorTag, message)
end
local function pcall(fn, ...)
    local thread = coroutine.create(fn)
    local result = table.pack(coroutine.resume(thread, ...))
    if not result[1] then return false, result[2] end
    if coroutine.status(thread) ~= 'dead' then
        assert(result[2] == errorTag, 'unexpected fixture yield')
        return false, result[3]
    end
    return true, table.unpack(result, 2, result.n)
end
local markerStack, markerLog = {}, {}
local function beginMarker(name)
    markerStack[#markerStack+1] = name
    markerLog[#markerLog+1] = 'begin:' .. name
end
local function endMarker()
    assert(#markerStack > 0, 'profile end needs a matching begin')
    markerLog[#markerLog+1] = 'end:' .. table.remove(markerStack)
end
local debug = {profilebegin=beginMarker, profileend=endMarker}
local engaged = true
local Settings = {ShellRedirection=true,AimSource='Camera',ShellFocusKey=Enum.UserInputType.MouseButton2}
local freecamActive = false
local UserInputService = {GetFocusedTextBox=function() return nil end}
local shellRedirection = {isEngaged = function() return engaged end}
]] .. profiling .. [[
local _G = {}
]] .. telemetry .. [[
check(_G.AutoLeadAssistFocusTelemetry() == shellRedirection.performance, 'telemetry getter exposes the cached performance table')
check(_G.AutoLeadAssistFocusTelemetry() == _G.AutoLeadAssistFocusTelemetry(), 'repeated telemetry reads reuse one table')
check(clock == 0, 'telemetry read performs no clock sampling')
]] .. 'check(' .. tostring(source:find('_G.AutoLeadAssistFocusTelemetry = nil', 1, true) ~= nil)
    .. ', "unload removes the telemetry getter")\n' .. [[
check(_G.AutoLeadAssistSetFocusProfiler == shellRedirection.setProfiler, 'public profiler setter uses the production opt-in function')
]] .. 'check(' .. tostring(source:find('_G.AutoLeadAssistSetFocusProfiler = nil', 1, true) ~= nil)
    .. ', "unload removes the profiler opt-in setter")\n' .. [[
local scopes = shellRedirection.performance.nativeScopes
check(scopes.enabled == false and scopes.unsupported == false and scopes.calls == 0 and scopes.failures == 0,
    'native profiler scopes are off by default with clean capability counters')
local transportSamples = 0
local function sampleTransport(duration)
    clock = 0
    local started = shellRedirection.profileBegin('transport')
    clock += duration/1000
    local ok, err = pcall(shellRedirection.profileEnd, 'transport', started)
    transportSamples += 1
    return ok, err
end
for i = 1,100 do sampleTransport(2) end
check(scopes.calls == 0 and scopes.failures == 0 and #markerLog == 0 and #markerStack == 0,
    '100 default timing samples invoke no native profiler methods')
check(shellRedirection.performance.transport.count == 100 and close(shellRedirection.performance.transport.meanMs,2),
    'cheap timing aggregation remains active without native scopes')
shellRedirection.setProfiler(true)
check(scopes.enabled == true and scopes.unsupported == false and scopes.error == nil,
    'explicit opt-in enables native scopes')
local acquisition = shellRedirection.performance.acquisition
for _, duration in ipairs({1,7,65,5,50}) do
    clock = 0
    local started = shellRedirection.profileBegin('acquisition')
    clock = duration/1000
    shellRedirection.profileEnd('acquisition', started)
end
check(acquisition.count == 5, 'scope sample count matches completed calls')
check(close(acquisition.totalMs,128) and close(acquisition.meanMs,25.6), 'scope total and mean use all samples')
check(close(acquisition.maxMs,65) and close(acquisition.lastMs,50), 'scope maximum and latest duration retained')
check(acquisition.over5Ms == 3 and acquisition.over50Ms == 1, 'scope threshold counters use strict greater-than checks')
check(#markerStack == 0 and #markerLog == 10 and acquisition.marked == false, 'normal scope markers stay balanced')
check(markerLog[1] == 'begin:AutoLead_Acquisition' and markerLog[2] == 'end:AutoLead_Acquisition', 'production acquisition marker name is stable')
check(scopes.calls > 0 and scopes.failures == 0, 'successful opt-in scope calls are counted')
local beforeLog = #markerLog
local failuresBefore = scopes.failures
debug = nil
check(sampleTransport(2), 'missing debug table does not break profiling')
check(#markerLog == beforeLog, 'missing profiler emits no marker calls')
check(scopes.enabled == false and scopes.unsupported == true and scopes.failures == failuresBefore+1,
    'missing profiler API disables and latches unsupported state')
local callsBefore = scopes.calls
for i = 1,100 do sampleTransport(2) end
check(scopes.calls == callsBefore and scopes.failures == failuresBefore+1,
    '100 retries after missing API perform no native calls or repeated failures')
shellRedirection.setProfiler(true)
debug = {profilebegin=beginMarker}
check(sampleTransport(3), 'missing profileend is safe')
check(scopes.enabled == false and scopes.unsupported == true, 'incomplete API is latched unsupported')
shellRedirection.setProfiler(true)
debug = {profileend=endMarker}
check(sampleTransport(4), 'missing profilebegin is safe')
check(#markerStack == 0 and #markerLog == beforeLog, 'incomplete profiler cannot open an unmatched scope')
local beginCalls, endCalls = 0, 0
shellRedirection.setProfiler(true)
failuresBefore = scopes.failures
debug = {profilebegin=function() beginCalls += 1; error('optional begin unavailable') end,
    profileend=function() endCalls += 1 end}
check(sampleTransport(6), 'optional profilebegin failure does not break timing')
check(endCalls == 0 and shellRedirection.performance.transport.marked == false, 'failed profilebegin is not followed by profileend')
callsBefore = scopes.calls
for i = 1,100 do sampleTransport(6) end
check(beginCalls == 1 and endCalls == 0 and scopes.calls == callsBefore and scopes.failures == failuresBefore+1,
    'throwing profilebegin is attempted once rather than repeated over 100 timing samples')
check(scopes.enabled == false and scopes.unsupported == true
    and tostring(scopes.error):find('optional begin unavailable',1,true), 'begin failure retains a diagnostic and disables native scopes')
debug = {profilebegin=beginMarker,profileend=endMarker}
shellRedirection.setProfiler(true)
check(scopes.enabled == true and scopes.unsupported == false and scopes.error == nil,
    'explicit retry clears unsupported state and the previous error')
check(sampleTransport(2) and #markerLog == beforeLog+2 and #markerStack == 0,
    'working API is retried after explicit opt-in reset')
shellRedirection.setProfiler(true)
failuresBefore = scopes.failures
debug = {profilebegin=beginMarker, profileend=function()
    endCalls += 1
    endMarker()
    error('optional end failure')
end}
check(sampleTransport(8), 'optional profileend failure is contained')
check(endCalls == 1 and #markerStack == 0 and shellRedirection.performance.transport.marked == false,
    'profileend failure still clears owned marker state')
callsBefore = scopes.calls
for i = 1,100 do sampleTransport(8) end
check(endCalls == 1 and scopes.calls == callsBefore and scopes.failures == failuresBefore+1
    and scopes.enabled == false and scopes.unsupported == true,
    'throwing profileend disables scopes and is not retried over 100 timing samples')
check(shellRedirection.performance.transport.count == transportSamples,
    'timing sample count survives all missing and throwing profiler cases')
shellRedirection.setProfiler(true)
debug = {profilebegin=function(name) clock += 0.002; beginMarker(name) end,
    profileend=function() clock += 0.004; endMarker() end}
check(sampleTransport(3) and close(shellRedirection.performance.transport.lastMs,9),
    'scope duration includes begin/end marker overhead as well as measured work')
shellRedirection.setProfiler(false)
callsBefore = scopes.calls
check(sampleTransport(3) and scopes.calls == callsBefore
    and close(shellRedirection.performance.transport.lastMs,3), 'explicit disable immediately restores marker-free timing')
shellRedirection.setProfiler(true)
debug = {profilebegin=beginMarker, profileend=endMarker}
clock = 0
local savedCloseStart = shellRedirection.profileBegin('transport')
debug = nil
clock = 0.01
check(pcall(shellRedirection.profileEnd,'transport',savedCloseStart) and #markerStack == 0,
    'an opened scope retains its close function if the debug API changes before closing')
check(shellRedirection.performance.transport.close == nil and scopes.unsupported == false,
    'successful cached close clears ownership without falsely marking APIs unsupported')
shellRedirection.setProfiler(true)
debug = {profilebegin=function(name)
    if name == 'AutoLead_Acquisition' then error('nested marker unavailable') end
    beginMarker(name)
end, profileend=endMarker}
clock = 0
local outerStart = shellRedirection.profileBegin('frame')
local innerStart = shellRedirection.profileBegin('acquisition')
clock = 0.007
shellRedirection.profileEnd('acquisition',innerStart)
shellRedirection.profileEnd('frame',outerStart)
check(scopes.enabled == false and scopes.unsupported == true and #markerStack == 0,
    'failure disabling nested scopes still closes the already opened outer scope')
shellRedirection.setProfiler(true)
debug = {profilebegin=beginMarker, profileend=endMarker}
beforeLog = #markerLog
callsBefore = scopes.calls
clock = 0
local installStarted = shellRedirection.profileBegin('installation')
clock = 0.125
shellRedirection.profileEnd('installation', installStarted)
check(#markerLog == beforeLog and scopes.calls == callsBefore and shellRedirection.performance.installation.marked == false,
    'yield-capable installation has no native profiler scope')
check(shellRedirection.performance.installation.count == 1
    and close(shellRedirection.performance.installation.lastMs,125), 'installation still records elapsed duration')

-- Execute the actual nested acquisition/frame instrumentation on an error.
debug = {profilebegin=beginMarker, profileend=endMarker}
shellRedirection.setProfiler(true)
local camera = {ViewportSize=Vector2.new(1280,720)}
local workspace = {CurrentCamera=camera}
local FREECAM_PRIORITY = 2000000
local callbacks = {}
local RunService = {
    BindToRenderStep=function(_,name,priority,callback)
        callbacks[name] = callback
    end,
    Heartbeat={Connect=function(_,callback) callbacks.transport=callback; return {} end}
}
shellRedirection.acquire = function()
    clock += 0.011
    error('fixture acquisition failed')
end
shellRedirection.draw = function() error('drawing must not run after acquisition failure') end
]] .. focusFrame .. renderPrefix .. [[
    callbacks.focusResult = {ok=focusOK,error=focusError}
end)
clock = 1
local logStart, acquisitionsBefore = #markerLog, acquisition.count
local framesBefore = shellRedirection.performance.frame.count
callbacks.AttributePlayerESP()
check(callbacks.focusResult.ok == false and tostring(callbacks.focusResult.error):find('fixture acquisition failed',1,true),
    'real frame callback preserves protected acquisition failure')
check(acquisition.count == acquisitionsBefore+1 and shellRedirection.performance.frame.count == framesBefore+1,
    'failed acquisition and outer frame both record a completed scope')
check(close(acquisition.lastMs,11) and close(shellRedirection.performance.frame.lastMs,11),
    'nested failed scopes keep their elapsed durations')
check(#markerStack == 0 and #markerLog == logStart+4, 'failed nested acquisition closes both scopes')
check(markerLog[logStart+1] == 'begin:AutoLead_FocusFrame'
    and markerLog[logStart+2] == 'begin:AutoLead_Acquisition'
    and markerLog[logStart+3] == 'end:AutoLead_Acquisition'
    and markerLog[logStart+4] == 'end:AutoLead_FocusFrame',
    'real integration closes acquisition before outer frame on exceptions')

local releaseCalls, stopCalls = 0, 0
shellRedirection.release = function() releaseCalls += 1 end
shellRedirection.stop = function() stopCalls += 1 end
shellRedirection.update = function() clock += 0.009; error('fixture transport failed') end
]] .. transport .. [[
local transportsBefore = shellRedirection.performance.transport.count
logStart = #markerLog
shellRedirection.active = true
callbacks.transport()
check(shellRedirection.failed and shellRedirection.error:find('fixture transport failed',1,true),
    'real transport callback contains and retains update failure')
check(releaseCalls == 1 and stopCalls == 1, 'transport failure runs owned cleanup')
check(shellRedirection.performance.transport.count == transportsBefore+1
    and close(shellRedirection.performance.transport.lastMs,9), 'real transport callback closes and records failed work')
check(#markerStack == 0 and markerLog[logStart+1] == 'begin:AutoLead_Transport'
    and markerLog[logStart+2] == 'end:AutoLead_Transport', 'transport marker pair remains balanced after update exception')
check(not shellRedirection.transportBusy, 'transport error releases callback reentry guard')
shellRedirection.transportBusy = true
callbacks.transport()
check(shellRedirection.performance.transport.count == transportsBefore+1 and #markerLog == logStart+2,
    'reentrant transport performs neither update work nor profiler work')
shellRedirection.transportBusy = false
shellRedirection.active, shellRedirection.failed = false, false
shellRedirection.update = function() clock += 0.075 end
local installationsBefore = shellRedirection.performance.installation.count
logStart = #markerLog
callbacks.transport()
check(shellRedirection.performance.installation.count == installationsBefore+1
    and close(shellRedirection.performance.installation.lastMs,75), 'real uninstalled transport callback times Actor installation separately')
check(#markerLog == logStart and #markerStack == 0 and not shellRedirection.transportBusy,
    'real installation callback opens no native marker and releases its guard')

-- Aggregate interval phases into fixed buckets; reuse them across windows.
local stats = shellRedirection.performance.intervals
local released, empty, target, phaseNames = stats.released, stats.heldEmpty, stats.heldTarget, stats.phases
local cachedState = shellRedirection.performance.state
shellRedirection.held, shellRedirection.focused = true, {Name='fixture target'}
shellRedirection.flightActive, shellRedirection.activeActorCount = true, 2
shellRedirection.publicationWrites, shellRedirection.transportPaused, shellRedirection.ready = 4, true, 6
local now = 0
shellRedirection.recordInterval(now)
check(stats.frames == 0 and stats.durationMs == 0, 'first frame establishes a timestamp without an interval sample')
check(cachedState.held and cachedState.engaged and cachedState.focusedPlayer == 'fixture target',
    'first interval call updates cached input and focus state without requiring an interval sample')
check(cachedState.flightActive and cachedState.activeActors == 2 and cachedState.publicationWrites == 4
    and cachedState.transportPaused and cachedState.readyActors == 6, 'cached state carries flight transport and publication counters')
local function advance(ms, hold, focus)
    engaged, shellRedirection.held, shellRedirection.focused = hold, hold, focus
    now += ms/1000
    shellRedirection.recordInterval(now)
end
advance(10,false,nil); advance(30,false,nil); advance(60,false,nil)
advance(15,true,nil); advance(55,true,nil)
advance(20,true,{}); advance(80,true,{})
check(stats.frames == 7 and close(stats.durationMs,270), 'window frame count and duration match phase samples')
check(released.count == 3 and close(released.totalMs,100) and close(released.meanMs,100/3)
    and close(released.maxMs,60), 'released phase count total mean and maximum match')
check(released.over25Ms == 2 and released.over50Ms == 1, 'released phase counts long intervals')
check(empty.count == 2 and close(empty.totalMs,70) and close(empty.meanMs,35) and close(empty.maxMs,55),
    'held-empty phase metrics remain separate')
check(empty.over25Ms == 1 and empty.over50Ms == 1, 'held-empty phase threshold counters match')
check(target.count == 2 and close(target.totalMs,100) and close(target.meanMs,50) and close(target.maxMs,80),
    'held-target phase metrics remain separate')
check(target.over25Ms == 1 and target.over50Ms == 1, 'held-target phase threshold counters match')
local expected = {released={count=3,total=100},heldEmpty={count=2,total=70},heldTarget={count=2,total=100}}
for i = 8,240 do
    local remainder = i%3
    local name = remainder == 0 and 'heldTarget' or remainder == 1 and 'released' or 'heldEmpty'
    advance(16,name ~= 'released',name == 'heldTarget' and {} or nil)
    expected[name].count += 1
    expected[name].total += 16
end
check(stats.frames == 240 and stats.window == 0 and close(stats.durationMs,3998), 'window reaches exactly its bounded 240-frame capacity')
for _, name in ipairs(phaseNames) do
    local bucket = stats[name]
    check(bucket.count == expected[name].count and close(bucket.totalMs,expected[name].total)
        and close(bucket.meanMs,expected[name].total/expected[name].count), 'full window metrics match for '..name)
end
advance(12,false,nil)
check(stats.frames == 1 and stats.window == 1 and close(stats.durationMs,12), '241st interval begins a fresh window')
check(stats.released == released and stats.heldEmpty == empty and stats.heldTarget == target and stats.phases == phaseNames,
    'window rollover reuses bucket and phase-list objects')
check(released.count == 1 and close(released.meanMs,12) and close(released.maxMs,12)
    and released.over25Ms == 0 and released.over50Ms == 0, 'rollover discards preceding released timings and threshold counts')
check(empty.count == 0 and empty.totalMs == 0 and empty.meanMs == 0 and empty.maxMs == 0
    and empty.over25Ms == 0 and empty.over50Ms == 0, 'rollover clears held-empty metrics')
check(target.count == 0 and target.totalMs == 0 and target.meanMs == 0 and target.maxMs == 0
    and target.over25Ms == 0 and target.over50Ms == 0, 'rollover clears held-target metrics')
for i = 1,1440 do advance(10,true,{}) end
check(stats.frames == 1 and stats.window == 7 and close(stats.durationMs,10), 'long sampling run stays bounded to successive fixed windows')
check(stats.released == released and stats.heldEmpty == empty and stats.heldTarget == target
    and #stats.phases == 3 and target.count == 1 and close(target.meanMs,10), 'long run grows no phase buckets or sample array')
engaged, shellRedirection.held, shellRedirection.focused = false, false, nil
shellRedirection.flightActive, shellRedirection.activeActorCount, shellRedirection.transportPaused = false, 0, false
shellRedirection.recordInterval(now)
check(shellRedirection.performance.state == cachedState and _G.AutoLeadAssistFocusTelemetry().state == cachedState,
    'state updates reuse the same cached telemetry object')
check(cachedState.held == false and cachedState.engaged == false and cachedState.focusedPlayer == nil
    and cachedState.flightActive == false and cachedState.activeActors == 0 and cachedState.transportPaused == false,
    'released and idle state clears stale focus flight and pause values')
return {passed=passed,sceneMutations=false}
]]
    if returnFixture then return code end
    return assert(loadstring(code, 'focus-performance.spec'))()
end

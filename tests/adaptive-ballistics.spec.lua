-- Call the returned function with attribute.lua's source in a Luau runtime
-- providing Vector2, Vector3 and CFrame. No live scene, input or remotes used.
return function(source, returnFixture)
    local function section(first, last)
        local a = assert(string.find(source, first, 1, true), first)
        local b = assert(string.find(source, last, a, true), last)
        return string.sub(source, a, b - 1)
    end
    local prelude = [[
local passed = 0
local function check(value, label)
    assert(value, label)
    passed += 1
end
local wallHeight, wallX, rayCount = nil, 400, 0
local workspace = { Raycast = function(_, origin, delta)
    rayCount += 1
    if wallHeight and delta.X > 0 and origin.X <= wallX and origin.X + delta.X >= wallX then
        local point = origin + delta * ((wallX - origin.X) / delta.X)
        if point.Y <= wallHeight then return {Position = point} end
    end
end }
local Settings = {AdaptiveAim=true, EnableAutoLead=true, ArtilleryAutoLay=true, Freecam=true}
local freecamActive = true
local now, bore = 10, Vector3.xAxis
local os = {clock=function() return now end}
local command = {Parent=true, Value=Vector3.zero}
local attributes = {}
function command:GetAttribute(k) return attributes[k] end
function command:SetAttribute(k,v) attributes[k]=v end
function command:IsA(k) return k == "Vector3Value" end
local function node(key, child)
    return {FindFirstChild=function(_, name) if name==key then return child end end}
end
local root = node("NewGuiData",node("Gunner",node("Data",node("CmdAngle",command))))
local game = {GetService=function() return root end}
local seat = {}
local hum = {SeatPart=seat}
local lp = {Character={FindFirstChildOfClass=function() return hum end}}
local vehicle = {PrimaryPart={CFrame=CFrame.identity}}
local weapon = {weapon={}, vehicle=vehicle, turret=node("Control",{Value=seat}),
    muzzle={Position=Vector3.zero,AssemblyLinearVelocity=Vector3.zero},speed=100,gravity=-10,drag=0}
local function getBoreForwardDirection() return bore end
local function getActiveTank() return vehicle end
local activeWeapon = weapon
local function getActiveWeaponData() return activeWeapon end
local selectedDirection, selectedArc = Vector3.new(1,1,0).Unit,"low"
local solves=0
local function calculateShotDirection()
    solves+=1
    return selectedDirection,Vector3.new(800,0,0),Vector3.zero,true,Vector3.yAxis,selectedArc
end
local function getShotAlignment(a,b) return a:Dot(b) end
local MIN_BARREL_ALIGNMENT = -0.1
local fireReadiness = {check=function() return nil end}
local aimCache, visualDiagnostics = {},{}
local function setFreecamHint() end
local refreshAimCache
local shellRedirection = {update=function() end}
local wh = {}
local shotTracker = {reject=function() end,serial=0,attempts=1,queue={}}
local hookedWeaponModules,extras={},{}
local lastShotDiagnostics
]]
    local assertions = [[
local function solve(distance, minPitch, maxPitch, lifetime, drag, elevated)
    return getLaunchDirection(Vector3.zero,Vector3.new(distance,0,0),true,100,-10,drag or 0,
        elevated or false,Vector3.new(1,2,0).Unit,math.rad(minPitch or -5),math.rad(maxPitch or 75),{},lifetime or 60,Vector3.yAxis)
end
local d,arc = solve(800)
check(migrate({})==true, "fresh settings enable adaptive aiming")
check(migrate({AutoLead=false,AutoBallistic=false})==false, "old disabled settings stay disabled")
check(migrate({AutoLead=false,AutoBallistic=true})==true, "legacy high mode migrates only enabled state")
check(migrate({AdaptiveAim=false,AutoBallistic=true})==false, "new explicit off wins over legacy high mode")
check(migrate({AdaptiveAim=true,AutoLead=false})==true, "new explicit on wins over legacy off")
check(d and arc=="low", "clear direct shot stays low")
local low = d
check(rayCount==ballistics.steps(ballistics.time(800,d.X*100,0),-10,0,100), "clear low traces only once")
d,arc=solve(800,nil,nil,nil,nil,true)
check(d and arc=="low", "raised artillery barrel does not force high")
wallHeight=150
d,arc=solve(800)
check(d and arc=="high" and d.Y>low.Y, "wall blocks low and selects high")
wallHeight=nil
d,arc=solve(800)
check(d and arc=="low", "clear target immediately returns to low")
wallHeight=150
d,arc=solve(800,-5,52)
check(not d and arc=="trajectory blocked", "blocked low plus illegal high is invalid")
wallHeight=1000
local preview
d,arc,preview=solve(800)
check(not d and arc=="trajectory blocked" and preview, "both blocked yields display-only candidate")
wallHeight=nil
d,arc=solve(800,40,75)
check(d and arc=="high", "mechanically illegal low falls back to legal high")
d,arc=solve(800,40,50)
check(not d and arc=="target outside gun elevation", "both outside pitch range rejected")
d,arc=solve(1100)
check(not d and arc=="Target exceeds ammunition range", "high root cannot extend physical range")
d,arc=solve(800,40,75,12)
check(not d and arc=="flight exceeds ammunition lifetime", "long high flight respects lifetime")
d,arc=solve(800,-5,75,12)
check(d and arc=="low", "short lifetime still permits direct shot")
d,arc=solve(500,-5,85,60,0.05)
check(d and arc=="low", "dragged direct shot stays low")
local t=ballistics.time(500,d.X*100,0.05)
check((ballistics.sample(Vector3.zero,d*100,-10,0.05,t)-Vector3.new(500,0,0)).Magnitude<0.001, "dragged low endpoint")
wallX,wallHeight=250,80
d,arc=solve(500,-5,85,60,0.05)
check(d and arc=="high", "dragged path uses obstacle fallback")
t=ballistics.time(500,d.X*100,0.05)
check((ballistics.sample(Vector3.zero,d*100,-10,0.05,t)-Vector3.new(500,0,0)).Magnitude<0.001, "dragged high endpoint")
wallHeight=nil
d,arc=getLaunchDirection(Vector3.zero,Vector3.new(15000,0,0),true,500,-10,0,false,bore,math.rad(40),math.rad(85),{},120,Vector3.yAxis)
check(d and arc=="high" and ballistics.time(15000,d.X*500,0)>90, "long high fallback remains supported")
for _,y in ipairs({-100,100}) do
    local target=Vector3.new(600,y,0)
    d,arc=getLaunchDirection(Vector3.zero,target,true,100,-10,0,false,bore,math.rad(-20),math.rad(85),{},60,Vector3.yAxis)
    check(d and arc=="low" and (ballistics.sample(Vector3.zero,d*100,-10,0,ballistics.time(600,d.X*100,0))-target).Magnitude<0.001, "elevated/depressed target preserves accurate low arc")
end
check(not updateArtillerySlave(weapon,Vector3.zero,selectedDirection,"low") and command.Value==Vector3.zero, "low never auto-lays")
check(updateArtillerySlave(weapon,Vector3.zero,selectedDirection,"high") and command.Value.Y<0, "high issues upward native command")
check(not updateArtillerySlave(weapon,Vector3.zero,selectedDirection,"low") and command.Value==Vector3.zero and attributes.type==nil, "high to low releases owned command")
refreshAimCache()
check(aimCache.direction and not aimCache.waitForAlignment and not aimCache.fireBlock, "misaligned low is not artillery-gated")
check(wh.fireWeapon(nil,nil,weapon.weapon,vehicle)=="native", "native handler permits low shot")
selectedArc="high"
refreshAimCache()
check(aimCache.waitForAlignment and aimCache.fireBlock, "misaligned high waits")
check(wh.fireWeapon(nil,nil,weapon.weapon,vehicle)==false, "native handler rejects unaligned high")
bore=selectedDirection
now+=0.1
refreshAimCache()
check(not aimCache.waitForAlignment and not aimCache.fireBlock, "aligned high can fire")
check(wh.fireWeapon(nil,nil,weapon.weapon,vehicle)=="native", "native handler permits aligned high")
selectedDirection,selectedArc=nil,"trajectory blocked"
refreshAimCache()
check(aimCache.solutionBlocked and aimCache.fireBlock=="trajectory blocked", "invalid finite target blocks firing")
check(wh.fireWeapon(nil,nil,weapon.weapon,vehicle)==false, "native handler rejects invalid solution")
check(wh.fireWeapon(nil,nil,{},vehicle)=="native", "cached block does not affect other weapons")
check(command.Value==Vector3.zero, "invalid target releases native command")
Settings.AdaptiveAim=false
refreshAimCache()
check(not aimCache.solutionBlocked and not aimCache.fireBlock, "assist disabled restores native firing")
check(wh.fireWeapon(nil,nil,weapon.weapon,vehicle)=="native", "disabled assist bypasses native handler gate")
Settings.AdaptiveAim=true
selectedDirection,selectedArc=Vector3.new(1,1,0).Unit,"high"
check(updateArtillerySlave(weapon,Vector3.zero,selectedDirection,"high"), "auto-lay active before redirection")
Settings.ShellRedirection=true
local solvesBefore=solves
refreshAimCache()
check(solves==solvesBefore,"redirection mode skips target ray and ballistic solving")
check(aimCache.direction==bore and aimCache.targetPos==nil and aimCache.arc=="barrel","redirection caches native launch direction without cursor target")
check(command.Value==Vector3.zero and not aimCache.turretSlaveActive,"redirection releases owned auto-elevation")
check(not aimCache.solutionBlocked and not aimCache.waitForAlignment and not aimCache.fireBlock,"redirection clears adaptive fire rejection")
check(wh.fireWeapon(nil,nil,weapon.weapon,vehicle)=="native","redirection permits ordinary native firing")
check(Settings.AdaptiveAim and Settings.ArtilleryAutoLay and not isAdaptiveAimActive(),"assist settings preserved but effectively suspended")
aimCache.solutionBlocked=true;aimCache.waitForAlignment=true
check(wh.fireWeapon(nil,nil,weapon.weapon,vehicle)=="native","switching to redirection bypasses even stale adaptive gates")
local module={FireBullet=function(_,data)
    data.id="confirmed-shot";data.effectfired=true
    return "emitted",nil,7
end}
hookSingleWeaponModule(module)
local packet={replicate=true,origin=weapon.muzzle,directions={bore}}
local emitted=table.pack(module:FireBullet(packet))
check(packet.directions[1]==bore,"redirection preserves native projectile launch packet")
check(emitted.n==3 and emitted[1]=="emitted" and emitted[3]==7,"native FireBullet returns preserved")
check(shotTracker.serial==1 and shotTracker.queue[1].redirectionFlight,"confirmed own launch still queued for shell ESP without forecast")
Settings.ShellRedirection=false;refreshAimCache()
check(solves>solvesBefore and isAdaptiveAimActive(),"turning redirection off restores previous assist settings")
activeWeapon=nil
refreshAimCache()
check(not aimCache.solutionBlocked and not aimCache.waitForAlignment, "seat exit clears stale firing flags")
return {passed=passed, sceneMutations=false}
]]
    local fixture = prelude
        .. '\nlocal function migrate(rememberedSettings)\n'
        .. section("local adaptiveAim =", "local Settings =")
        .. '\nreturn adaptiveAim\nend\n'
        .. section("local function isAdaptiveAimActive(", "-- Suppress only the visual")
        .. section("local ballistics =", "-- The target classes change")
        .. section("local function pathReachesTarget(", "-- Canonical MTC Explosion")
        .. section("local function traceTrajectory(", "-- Main Render Loop")
        .. section("ballistics.slave =", "extras.staffRoles =")
        .. section("wh.fireWeapon = function", "local held = heldFire.matches")
        .. '\nreturn "native"\nend\n'
        .. section("local function hookSingleWeaponModule(", "-- Native gunner controllers debit")
        .. assertions
    if returnFixture then return fixture end
    return assert(loadstring(fixture, "adaptive-ballistics.spec"))()
end

-- Mode-independent native launch capture and observed-shell rendering.
return function(source, returnFixture)
    local function section(first,last)
        local a=assert(source:find(first,1,true),first)
        local b=assert(source:find(last,a,true),last)
        return source:sub(a,b-1)
    end
    local code=[[
local passed=0
local function check(v,label) assert(v,label);passed+=1 end
local now=10
local os={clock=function() return now end}
-- Model protected errors because Luau-Web's native error bridge escapes pcall.
local errorTag={}
local function error(message) return coroutine.yield(errorTag,message) end
local function pcall(fn,...)
    local thread=coroutine.create(fn)
    local r=table.pack(coroutine.resume(thread,...))
    if not r[1] then return false,r[2] end
    if coroutine.status(thread)~='dead' then
        assert(r[2]==errorTag,'unexpected fixture yield')
        return false,r[3]
    end
    return true,table.unpack(r,2,r.n)
end
local Settings={EnableAutoLead=false,AdaptiveAim=false,ShellRedirection=false,ShotProgress=false,
    OwnShellHighlight=true,ShotStatus=false,ShowDistance=false}
local aimCache={}
local visualDiagnostics={flightTime=2}
local shell={MuzzleSpeed=600,Gravity=-30,Drag=0,OverrideProjectileModel='Default'}
local ShellModules={Ammo=shell}
local defaultGravity=-10
local extras={}
local hookedWeaponModules={}
local shellRedirection={performance={state={}},assign=function(object,key,value) object[key]=value end}
local function isAdaptiveAimActive() return false end
local shotTracker={queue={},entries={},serial=0,attempts=0,observed=0,sent=0,
    candidates={},projectileNames={Default=true},flightGui={},announce=function()end}
local function frameAt(position) return setmetatable({Position=position},{__kind='CFrame'}) end
local CFrame={fromMatrix=function(position) return frameAt(position) end}
local UDim2={fromOffset=UDim2.fromOffset,fromScale=function(x,y)return {X={Scale=x},Y={Scale=y}}end,
    new=function(xs,xo,ys,yo)return {X={Scale=xs,Offset=xo},Y={Scale=ys,Offset=yo}}end}
local Instance={}
function Instance.new(class)
    local item={ClassName=class,Parent=true}
    function item:IsA(kind) return kind==self.ClassName end
    function item:Destroy() self.destroyed=true;self.Parent=nil end
    function item:Clone() return Instance.new(self.ClassName) end
    function item:FindFirstChildOfClass() return {} end
    return item
end
local visualContainer={}
local blastZone=Instance.new('Part')
local blastDistance={gui=Instance.new('BillboardGui'),scaleLabel=function()end}
local THEME={FlightStart=Color3.fromRGB(65,225,255),FlightEnd=Color3.fromRGB(177,135,255),Ink=Color3.fromRGB(12,16,26)}
local camera={ViewportSize=Vector2.new(1280,720),FieldOfView=70,
    WorldToViewportPoint=function(_,p)return p,p.Z>0 end}
local workspace={CurrentCamera=camera,GetServerTimeNow=function()return 100 end}
local ballistics={lifetime=function()return 60 end,sample=function(p,v,g,d,t)return p+v*t end}
local forecastFailure=false
local traceCount=0
local function traceTrajectory(p,v)
    traceCount+=1
    if forecastFailure then error('forecast unavailable') end
    return p+v*2,nil,2
end
local function getTrajectoryParams()return {}end
local callback
local FREECAM_PRIORITY=100
local RunService={BindToRenderStep=function(_,name,priority,fn)callback=fn end}
]]..section('function shotTracker.releaseCandidate(', 'function shotTracker.observePart(')
        ..section('function shotTracker.remove(', '\ndo\n    local notify')
        ..section('function shotTracker.makeFlightLines(', '-- Clip before sizing GUI lines')
        ..section('function shotTracker.drawShell(', 'function shotTracker.projectProgress(')
        ..section('function shotTracker.captureLaunch(', '-- Native gunner controllers debit')..[[
-- Native dispatch mutates its packet; tracking must snapshot ammo beforehand.
local emitting=true
local module={FireBullet=function(_,data)
    data.name='native-mutated-name'
    if emitting then
        data.originpos=frameAt(Vector3.new(100,20,200));data.id='shot';data.effectfired=true
    end
    return 'native',nil,7
end}
hookSingleWeaponModule(module)
local function fire(origin)
    local packet={replicate=true,name='Ammo',origin=origin or {},directions={Vector3.new(10,0,0)}}
    local r=table.pack(module:FireBullet(packet))
    return packet,r
end
local packet,result=fire()
local entry=shotTracker.queue[1]
check(entry and entry.weapon.shellData==shell,'no aiming cache required to track native own shot')
check(entry.launchPosition==Vector3.new(100,20,200),'native muzzle snapshot supplies the launch position')
check(entry.launchVelocity==Vector3.new(600,0,0),'native direction is normalized before applying ammo speed')
check(entry.weapon.gravity==-30 and entry.model=='Default','ammo lookup precedes native packet mutation')
check(packet.directions[1]==Vector3.new(10,0,0),'observation preserves firing direction')
check(result.n==3 and result[1]=='native' and result[3]==7,'observation preserves native return values')
local before=shotTracker.serial
emitting=false;fire()
check(shotTracker.serial==before and #shotTracker.queue==1,'unconfirmed dispatch cannot create shell ESP')
module:FireBullet({replicate=false,name='Ammo',directions={Vector3.xAxis}})
check(#shotTracker.queue==1,'remote-player packets are not tracked as own shells')
emitting=true
local staleMuzzle={}
aimCache={weapon={muzzle=staleMuzzle,weapon={},shellData={MuzzleSpeed=1},speed=1},startPos=Vector3.zero}
fire()
check(shotTracker.queue[2].weapon.speed==600 and shotTracker.queue[2].launchPosition.X==100,
    'another cached weapon cannot override the actual shot ammo or muzzle')
table.clear(shotTracker.queue)
aimCache.tankVelocity=Vector3.new(0,1000,0)
fire(staleMuzzle)
local crosswind=shotTracker.queue[1]
local visual=Instance.new('BasePart');visual.Name='Default'
shotTracker.candidates[visual]={part=visual,first=crosswind.launchPosition,position=crosswind.launchPosition,
    born=crosswind.sentAt,direction=Vector3.xAxis}
check(shotTracker.discover(crosswind),'inherited vehicle motion cannot reject a correctly oriented native shell')
table.clear(shotTracker.queue)

local forecastsDrawn=0
shotTracker.drawFlight=function(entry)
    if entry.forecastReady then forecastsDrawn+=1 end
end
shotTracker.projectProgress=function()return 0 end
shotTracker.reject=function()end
]]..section('RunService:BindToRenderStep("AutoLeadShotTracking",', 'local fireReadiness =')..[[
local function prepare(redirection,assist,progress)
    Settings.ShellRedirection=redirection;Settings.EnableAutoLead=assist;Settings.AdaptiveAim=assist
    Settings.ShotProgress=progress;Settings.OwnShellHighlight=true
    table.clear(shotTracker.entries);table.clear(shotTracker.queue);table.clear(shotTracker.candidates)
    now+=1
    fire()
    local e=shotTracker.queue[1]
    local part=Instance.new('BasePart')
    part.Name='Default';part.Size=Vector3.new(4,4,4);part.Transparency=0;part.LocalTransparencyModifier=0
    shotTracker.candidates[part]={part=part,first=e.launchPosition,position=e.launchPosition,
        born=e.sentAt,direction=Vector3.xAxis,velocity=Vector3.new(600,0,0)}
    callback()
    return e,part
end
for _,redirect in ipairs({false,true}) do
    for _,assist in ipairs({false,true}) do
        local e=prepare(redirect,assist,false)
        check(e.state and e.shellMarker.Visible,'shell ESP works with progress off across every aiming mode')
        check(not e.forecastReady and #e.lines==0,'shell-only tracking creates no forecast lines')
    end
end
check(traceCount==0,'shell-only tracking never runs trajectory collision traces')
local redirected=prepare(true,false,true)
check(redirected.shellMarker.Visible and not redirected.forecastReady and traceCount==0,
    'redirection displays observed shell even when flight progress is enabled')
local native=prepare(false,true,true)
check(native.shellMarker.Visible and native.forecastReady and forecastsDrawn>0,'normal progress can coexist with independent ESP')
native.expectedHit=true;native.expectedTime=0.1;native.expectedEnd=native.state.position
now+=0.1;callback()
check(native.shellMarker.Visible and not native.forecastReady and #shotTracker.entries==1,
    'forecast arrival hides progress without ending a still-observed shell')
forecastFailure=true
local failed=prepare(false,false,true)
check(failed.shellMarker.Visible and not failed.forecastReady and failed.forecastError=='forecast unavailable',
    'a forecast failure leaves the observed shell visible')
forecastFailure=false
local moving,part=prepare(true,false,false)
moving.state.position=Vector3.new(300,40,250);now+=0.05;callback()
check(moving.shellMarker.Position.X.Offset==300 and moving.shellMarker.Position.Y.Offset==40,
    'marker follows the actual redirected position')
check(moving.shellHighlight.Enabled and moving.shellMarker.Visible,'outline availability cannot suppress the screen marker')
Settings.OwnShellHighlight=false;callback()
check(not moving.shellMarker.Visible and not moving.shellHighlight.Enabled,'ESP toggle hides both marker and outline')
Settings.OwnShellHighlight=true;callback()
check(moving.shellMarker.Visible,'ESP can be re-enabled during a flight')
workspace.CurrentCamera=nil;callback()
check(not moving.shellMarker.Visible and not moving.shellHighlight.Enabled,'missing camera safely hides shell visuals')
workspace.CurrentCamera=camera
moving.state.position=Vector3.new(0,0,-1);callback()
check(not moving.shellMarker.Visible,'shells behind the camera are hidden')
moving.state.destroy=true;callback()
check(#shotTracker.entries==0 and moving.layer.destroyed and moving.shellHighlight.destroyed,
    'observed flight end immediately removes shell ESP')
return {passed=passed,sceneMutations=false}
]]
    if returnFixture then return code end
    return assert(loadstring(code,'shell-esp.spec'))()
end

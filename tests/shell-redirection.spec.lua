-- Extract production steering and selection into mock scene/Actor fixtures.
return function(source, returnFixture)
    local function section(first,last)
        local a=assert(source:find(first,1,true))
        local b=assert(source:find(last,a,true))
        return source:sub(a,b-1)
    end
    local steerSource=assert(source:match('shellRedirection.steerSource = %[%=%[(.-)%]%=%]'))
    local actorSource=assert(source:match('shellRedirection.actorSource = %[%=%[(.-)%]%=%]'))
    local code=[[
local passed=0
local function check(value,label) assert(value,label);passed+=1 end
local Settings={ShellRedirection=true,ShellFocusRadius=60,ShellFocusCircle=true,ShellFocusTracer=true,
    ShellFocusKey=Enum.UserInputType.MouseButton2,ShellVisibilityCheck=false,
    ShellFocusHighlight=true,ShellFocusColor=Color3.fromRGB(255,209,90)}
local shellRedirection={players={},records={},candidates={},held=true,heldKey=Settings.ShellFocusKey}
local Players={}
local actorTime=0
local os={clock=function()return actorTime end}
local attrs={AttributeShellRedirectOwner="fixture",AttributeShellRedirectHeartbeat=os.clock(),
    AttributeShellRedirectHeld=true,AttributeShellRedirectInitializing=true}
local attributeReads=0
local attributeWrites={}
local attributeSignals={}
local attributeDisconnects=0
local lp={Team="blue",Parent=true,PlayerGui={},GetAttribute=function(_,k) attributeReads+=1;return attrs[k] end,
    SetAttribute=function(_,k,v)
        if attrs[k]==v then return end
        attributeWrites[k]=(attributeWrites[k] or 0)+1
        attrs[k]=v
        for _,connection in ipairs(attributeSignals[k] or {}) do
            if connection.callback then connection.callback() end
        end
    end,
    GetAttributeChangedSignal=function(_,k)
        attributeSignals[k]=attributeSignals[k] or {}
        return {Connect=function(_,fn)
            local connection={callback=fn,Disconnect=function(self)
                self.callback=nil;attributeDisconnects+=1
            end}
            table.insert(attributeSignals[k],connection)
            return connection
        end}
    end}
local textbox=nil
local UserInputService={GetFocusedTextBox=function()return textbox end}
local aimWorldParams={}
local blocked,rayCount={},0
local workspace={Raycast=function(_,origin,delta)
    rayCount+=1
    if blocked[delta.X] then return {Instance={IsDescendantOf=function() return false end}} end
end}
local camera={ViewportSize=Vector2.new(1280,720),WorldToViewportPoint=function(_,p) return p,p.X<1000 end}
local function record(x,team)
    local character={}
    local part={Parent=character,Position=Vector3.new(x,0,100),AssemblyLinearVelocity=Vector3.zero,
        IsA=function(_,class)return class=="BasePart" end,
        IsDescendantOf=function(_,model)return model==character end}
    local player={Parent=Players,UserId=x,Team=team or "red",Neutral=false,Character=character}
    local humanoid={Health=100,Parent=character}
    character.FindFirstChildOfClass=function()return humanoid end
    character.FindFirstChild=function(_,name)if name=="UpperTorso" then return part end end
    return {player=player,character=character,part=part,humanoid=humanoid}
end
]]..section('local function normalizeFocusKey(', 'local adaptiveAim =')
    ..section('function shellRedirection.refreshPlayers(', '-- Runs inside each native projectile Actor')..steerSource..[[
local a,b=record(10),record(20)
check(normalizeFocusKey("Enum.KeyCode.F")==Enum.KeyCode.F,"keyboard binding strings normalize")
check(normalizeFocusKey("Enum.UserInputType.MouseButton2")==Enum.UserInputType.MouseButton2,"mouse binding strings normalize")
check(not normalizeFocusKey("Enum.KeyCode.Unknown") and not normalizeFocusKey("None"),"unbound sentinel cannot engage")
local roster={a.player,b.player}
local rosterReads=0
Players.GetPlayers=function()rosterReads+=1;return roster end
shellRedirection.refreshPlayers(1)
local cachedRecord=shellRedirection.records[a.player]
shellRedirection.refreshPlayers(1.1)
check(rosterReads==1,"roster rebuilds capped at two per second")
shellRedirection.refreshPlayers(1.5)
check(shellRedirection.records[a.player]==cachedRecord,"unchanged roster reuses character records")
b.player.Parent=nil;shellRedirection.refreshPlayers(2)
check(not shellRedirection.records[b.player],"departed player removed from record cache")
b.player.Parent=Players
shellRedirection.players={a,b}
local rmb={UserInputType=Enum.UserInputType.MouseButton2}
shellRedirection.release()
check(not shellRedirection.select(camera,Vector2.zero,Vector3.zero),"RMB released cannot focus")
shellRedirection.inputBegan(rmb,true)
check(not shellRedirection.held,"processed UI click cannot engage")
textbox={};shellRedirection.inputBegan(rmb,false)
check(not shellRedirection.held,"typing cannot engage")
textbox=nil;shellRedirection.inputBegan(rmb,false)
check(shellRedirection.isEngaged(),"RMB hold engages redirection")
shellRedirection.inputEnded({UserInputType=Enum.UserInputType.MouseButton1})
check(shellRedirection.isEngaged(),"other button release keeps RMB hold")
local pos=shellRedirection.select(camera,Vector2.zero,Vector3.zero)
check(pos==a.part.Position and shellRedirection.focused==a.player,"nearest visible enemy selected")
blocked[10]=true
local raysBefore=rayCount
pos=shellRedirection.select(camera,Vector2.zero,nil)
check(pos==a.part.Position and rayCount==raysBefore,"visibility off selects projected enemy without rays")
Settings.ShellVisibilityCheck=true
pos=shellRedirection.select(camera,Vector2.zero,Vector3.zero)
check(pos==b.part.Position,"occluded nearest yields next visible focus")
blocked[20]=true
check(not shellRedirection.select(camera,Vector2.zero,Vector3.zero) and not shellRedirection.focused,"all occluded clears focus")
blocked={}
a.player.Team=lp.Team
pos=shellRedirection.select(camera,Vector2.zero,Vector3.zero)
check(pos==b.part.Position,"friendly excluded")
b.humanoid.Health=0
check(not shellRedirection.select(camera,Vector2.zero,Vector3.zero),"dead enemy excluded")
b.humanoid.Health=100;b.player.Character={}
check(not shellRedirection.select(camera,Vector2.zero,Vector3.zero),"respawn invalidates cached character")
b.player.Character=b.character;b.player.Neutral=true
check(not shellRedirection.select(camera,Vector2.zero,Vector3.zero),"neutral excluded")
b.player.Neutral=false;Settings.ShellFocusRadius=5
check(not shellRedirection.select(camera,Vector2.zero,Vector3.zero),"focus radius enforced")
Settings.ShellFocusRadius=60;Settings.ShellRedirection=false
check(not shellRedirection.select(camera,Vector2.zero,Vector3.zero),"disabled selection clears focus")
Settings.ShellRedirection=true;shellRedirection.players={};blocked={};rayCount=0
for i=1,6 do shellRedirection.players[i]=record(i);blocked[i]=true end
shellRedirection.select(camera,Vector2.zero,Vector3.zero)
check(rayCount==4,"visibility rays capped at four")
shellRedirection.release();Settings.ShellFocusKey=Enum.KeyCode.F
shellRedirection.inputBegan(rmb,false)
check(not shellRedirection.isEngaged(),"RMB does not activate a rebound keyboard lock")
local fKey={UserInputType=Enum.UserInputType.Keyboard,KeyCode=Enum.KeyCode.F}
shellRedirection.inputBegan(fKey,false)
check(shellRedirection.isEngaged(),"chosen keyboard hold engages")
shellRedirection.inputEnded(rmb)
check(shellRedirection.isEngaged(),"other input release does not cancel chosen hold")
shellRedirection.inputEnded(fKey)
check(not shellRedirection.isEngaged(),"chosen keyboard release clears hold")
Settings.ShellFocusKey=Enum.UserInputType.MouseButton2
shellRedirection.inputBegan(rmb,false)
local function state()
    return {replicate=true,Behavior="Default",position0=Vector3.zero,position=Vector3.new(20,0,0),velocity=Vector3.xAxis*100}
end
local s=state()
local target=Vector3.new(20,100,0)
check(steer(s,target,Vector3.zero) and s.velocity.Y>99,"airborne shell redirects toward focus")
check(math.abs(s.velocity.Magnitude-100)<0.001 and s.position==Vector3.new(20,0,0),"speed and position preserved")
s=state();s.position=Vector3.new(1,0,0)
check(not steer(s,target,Vector3.zero),"shell near barrel untouched")
s=state();s.replicate=false
check(not steer(s,target,Vector3.zero),"other players' shells untouched")
s=state();s.destroy=true
check(not steer(s,target,Vector3.zero),"destroyed shell cannot redirect")
s=state();s.hitray={}
check(not steer(s,target,Vector3.zero),"impact cannot redirect")
s=state();s.physicalprojectile={}
check(not steer(s,target,Vector3.zero),"unsupported physical shell untouched")
s=state();s.Behavior="SACLOS"
check(not steer(s,target,Vector3.zero),"native guided projectile untouched")
s=state()
check(not steer(s,nil,Vector3.zero),"lost focus leaves velocity alone")
check(steer(s,target,Vector3.new(50,0,0)) and s.velocity.X>0,"moving focus receives lead")
local actorAttrs={}
local actor={Parent=true,GetAttribute=function(_,k)return actorAttrs[k]end,SetAttribute=function(_,k,v)actorAttrs[k]=v end}
local actorTarget=record(202)
local actorPosition,poseReads=target,0
local targetLookups=0
local findActorPart=actorTarget.character.FindFirstChild
local findActorHumanoid=actorTarget.character.FindFirstChildOfClass
actorTarget.character.FindFirstChild=function(...)
    targetLookups+=1;return findActorPart(...)
end
actorTarget.character.FindFirstChildOfClass=function(...)
    targetLookups+=1;return findActorHumanoid(...)
end
actorTarget.part.Position=nil
setmetatable(actorTarget.part,{__index=function(_,key)
    if key=="Position" then poseReads+=1;return actorPosition end
end,__newindex=function(self,key,value)
    if key=="Position" then actorPosition=value else rawset(self,key,value)end
end})
Players.LocalPlayer=lp
Players.GetPlayerByUserId=function(_,id)
    targetLookups+=1;if id==202 then return actorTarget.player end
end
local game={GetService=function(_,name)
    if name=="Players" then return Players end
    return {PHRST={Threads={FindFirstChild=function()return actor end}}}
end}
local calls=0
local original=function() calls+=1;return "native",nil,42 end
local environment={simulatebullet=original}
local filtergc=function()return {original}end
local getfenv=function()return environment end
local cleanup
local task={spawn=function(fn)cleanup=fn end,wait=function()coroutine.yield("wait")end}
]]
    actorSource=actorSource:gsub('@ACTOR@','"fixture"'):gsub('@OWNER@','"fixture"')
        :gsub('@STEER@',function()return steerSource end)
    code=code..actorSource..[[
check(environment.simulatebullet~=original and actorAttrs.AttributeShellRedirectStatus=="fixture","Actor environment hook confirms installation")
lp:SetAttribute("AttributeShellRedirectTargetId",202)
lp:SetAttribute("AttributeShellRedirectHeld",false)
lp:SetAttribute("AttributeShellRedirectHeld",true)
check(targetLookups==0 and poseReads==0,"Actor startup and idle acquisition callbacks perform zero target Instance lookups")
local monitor=coroutine.create(cleanup)
actorTime=2
check(coroutine.resume(monitor) and coroutine.status(monitor)=="suspended"
    and actorAttrs.AttributeShellRedirectStatus=="fixture",
    "initializing Actor survives serial installation beyond the steady-state lease")
lp:SetAttribute("AttributeShellRedirectHeartbeat",actorTime)
lp:SetAttribute("AttributeShellRedirectShot",1)
cached.Position,cached.Velocity,cached.SampledAt=target,Vector3.zero,actorTime
s=state();environment.simulatebullet(s)
check(s.velocity==Vector3.xAxis*100,"initializing Actor does not steer shells before host is ready")
cached.Position,cached.Velocity,cached.SampledAt=nil,nil,nil
check(coroutine.resume(monitor) and targetLookups==0 and poseReads==0,
    "initializing monitor does not sample targets even after observing an own shell")
calls=0
lp:SetAttribute("AttributeShellRedirectHeartbeat",actorTime)
lp:SetAttribute("AttributeShellRedirectInitializing",false)
actorTime+=0.16
lp:SetAttribute("AttributeShellRedirectHeartbeat",actorTime)
check(coroutine.resume(monitor) and coroutine.status(monitor)=="suspended",
    "fresh post-install heartbeat starts the steady-state Actor lease")
local poseReadsBefore=poseReads
for i=1,10 do check(coroutine.resume(monitor),"idle Actor monitor remains scheduled")end
check(poseReads==poseReadsBefore and targetLookups==0,"hovering with no own shell performs no Actor target lookups or pose sampling")
for i=1,100 do
    lp:SetAttribute("AttributeShellRedirectTargetId",nil)
    lp:SetAttribute("AttributeShellRedirectTargetId",202)
    lp:SetAttribute("AttributeShellRedirectHeld",false)
    lp:SetAttribute("AttributeShellRedirectHeld",true)
end
check(coroutine.resume(monitor) and targetLookups==0 and poseReads==poseReadsBefore,
    "repeated idle focus and hold transitions never resolve or sample target Instances")
s=state()
local readsBefore=attributeReads
local results=table.pack(environment.simulatebullet(s))
check(s.velocity==Vector3.xAxis*100 and targetLookups==0 and poseReads==poseReadsBefore,
    "first own callback only records flight activity without target Instance access")
check(results.n==3 and results[1]=="native" and results[3]==42,"native return values preserved")
check(coroutine.resume(monitor),"owned monitor samples after genuine own flight activity")
s=state();environment.simulatebullet(s)
check(s.velocity.Y>99 and calls==2,"wrapper steers from monitor cache before native simulation display")
check(attributeReads==readsBefore,"own flight activity does not add Instance attribute reads")
readsBefore=attributeReads
for i=1,100 do local foreign=state();foreign.replicate=false;environment.simulatebullet(foreign) end
check(attributeReads==readsBefore,"other players' shells require no Actor attribute reads")
readsBefore=attributeReads
for i=1,10 do environment.simulatebullet(state()) end
check(attributeReads==readsBefore,"own shell hot path performs zero Instance attribute reads")
actorTarget.part.Position=Vector3.new(20,200,0)
check(coroutine.resume(monitor),"Actor-local monitor runs independently")
s=state();environment.simulatebullet(s)
check(s.velocity.Y>99 and not attrs.AttributeShellRedirectPosition and not attrs.AttributeShellRedirectVelocity,
    "Actor follows target movement without cross-Actor pose attributes")
actorTime+=0.16
lp:SetAttribute("AttributeShellRedirectHeartbeat",actorTime)
local lookupsBefore=targetLookups
local poseReadsBefore=poseReads
lp:SetAttribute("AttributeShellRedirectShot",2)
check(targetLookups==lookupsBefore and poseReads==poseReadsBefore,
    "confirmed Shot wake callback never reads target Instances")
check(coroutine.resume(monitor) and poseReads>poseReadsBefore,
    "confirmed Shot wake lets owned monitor prime target before the next own callback")
s=state();environment.simulatebullet(s)
check(s.velocity.Y>99,"confirmed Shot cache steers its next native simulation step")
lookupsBefore=targetLookups;poseReadsBefore=poseReads
lp:SetAttribute("AttributeShellRedirectTargetId",nil)
s=state();environment.simulatebullet(s)
check(s.velocity==Vector3.xAxis*100,"target identity loss immediately prevents stale target steering")
lp:SetAttribute("AttributeShellRedirectTargetId",202)
check(targetLookups==lookupsBefore and poseReads==poseReadsBefore,
    "retargeting an already-flying shell does no target reads in attribute callbacks")
check(coroutine.resume(monitor),"monitor samples new focus for an already-flying own shell")
s=state();environment.simulatebullet(s)
check(s.velocity.Y>99,"already-flying own shell redirects after deferred focus sampling")
actorTarget.humanoid.Health=0;check(coroutine.resume(monitor),"Actor monitor updates liveness")
s=state();environment.simulatebullet(s)
check(s.velocity==Vector3.xAxis*100,"Actor-local target death stops steering")
actorTarget.humanoid.Health=100;check(coroutine.resume(monitor),"Actor-local sampling resumes valid target")
lp:SetAttribute("AttributeShellRedirectHeld",false)
s=state();environment.simulatebullet(s)
check(s.velocity==Vector3.xAxis*100,"Actor hold gate immediately prevents steering")
lp:SetAttribute("AttributeShellRedirectHeld",true)
check(coroutine.resume(monitor),"monitor can acquire while a previously unlocked own shell is still flying")
s=state();environment.simulatebullet(s)
check(s.velocity.Y>99,"locking after normal own flight still redirects without callback target reads")
shellRedirection.active=true;shellRedirection.owner="fixture"
shellRedirection.inputEnded(rmb)
check(not shellRedirection.held and not shellRedirection.focused and attrs.AttributeShellRedirectHeld==false
    and attrs.AttributeShellRedirectTargetId==nil,"RMB release immediately clears published target identity")
shellRedirection.inputBegan(rmb,false);shellRedirection.release()
check(not shellRedirection.isEngaged(),"focus-loss release cancels held input")
shellRedirection.active=false
lp:SetAttribute("AttributeShellRedirectOwner",nil)
s=state();environment.simulatebullet(s)
check(s.velocity==Vector3.xAxis*100,"disabled owner stops steering immediately")
check(coroutine.resume(monitor) and coroutine.status(monitor)=="dead","Actor monitor terminates on owner loss")
check(environment.simulatebullet==original and actorAttrs.AttributeShellRedirectStatus==nil,"cleanup restores owned callback/status")
check(attributeDisconnects==6,"Actor cleanup disconnects all target and initialization attribute listeners")
]]
    code=code..[[
do
    lp:SetAttribute("AttributeShellRedirectOwner","fixture")
    lp:SetAttribute("AttributeShellRedirectHeartbeat",actorTime)
    lp:SetAttribute("AttributeShellRedirectInitializing",true)
]]..actorSource..[[
    local leaseMonitor=coroutine.create(cleanup)
    actorTime+=1
    check(coroutine.resume(leaseMonitor) and coroutine.status(leaseMonitor)=="suspended",
        "startup grace permits delayed confirmation without discarding Actor access")
    lp:SetAttribute("AttributeShellRedirectHeartbeat",actorTime)
    lp:SetAttribute("AttributeShellRedirectInitializing",false)
    check(coroutine.resume(leaseMonitor) and coroutine.status(leaseMonitor)=="suspended",
        "steady-state lease uses the refreshed completion timestamp")
    actorTime+=0.74
    check(coroutine.resume(leaseMonitor) and coroutine.status(leaseMonitor)=="suspended",
        "completed Actor remains alive before the strict heartbeat deadline")
    actorTime+=0.02
    check(coroutine.resume(leaseMonitor) and coroutine.status(leaseMonitor)=="dead"
        and environment.simulatebullet==original and actorAttrs.AttributeShellRedirectStatus==nil,
        "completed Actor restores hook when the strict heartbeat lease expires")
end
do
    lp:SetAttribute("AttributeShellRedirectOwner","fixture")
    lp:SetAttribute("AttributeShellRedirectHeartbeat",actorTime)
    lp:SetAttribute("AttributeShellRedirectInitializing",true)
]]..actorSource..[[
    local abandonedMonitor=coroutine.create(cleanup)
    actorTime+=8.1
    check(coroutine.resume(abandonedMonitor) and coroutine.status(abandonedMonitor)=="dead"
        and environment.simulatebullet==original and actorAttrs.AttributeShellRedirectStatus==nil,
        "abandoned initializing Actor has a bounded startup lease and restores its hook")
end
check(attributeDisconnects==18,"all startup, completed and expired Actor sessions release their listeners")
]]
    code=code..[[
local publicationTime=1
local os={clock=function()return publicationTime end}
local ReplicatedStorage,getactors,run_on_actor
]]..section('shellRedirection.attributes =', 'function shellRedirection.update(')
        ..section('function shellRedirection.update(', 'function shellRedirection.assign(')..[[
local threads={}
local installedActors={}
for i=1,2 do
    local values={}
    installedActors[i]={Name=tostring(i),Parent=threads,IsA=function(_,class)return class=="Actor" end,
        GetAttribute=function(_,key)return values[key]end,SetAttribute=function(_,key,value)values[key]=value end}
end
ReplicatedStorage={FindFirstChild=function(_,name)
    if name=="PHRST" then return {FindFirstChild=function(_,key)if key=="Threads" then return threads end end} end
end}
getactors=function()return installedActors end
local startupCalls=0
run_on_actor=function(installed,source)
    startupCalls+=1
    check(attrs.AttributeShellRedirectInitializing==true,"host marks installation before each Actor dispatch")
    publicationTime+=0.9
    installed:SetAttribute("AttributeShellRedirectStatus",attrs.AttributeShellRedirectOwner)
end
shellRedirection.actorSource="fixture @ACTOR@ @OWNER@ @STEER@"
shellRedirection.steerSource=""
shellRedirection.active=false;shellRedirection.failed=nil;shellRedirection.error=nil
shellRedirection.update()
check(startupCalls==2 and shellRedirection.ready==2 and not shellRedirection.failed,
    "host retains confirmed Actors after serial installs exceed the heartbeat lease")
check(attrs.AttributeShellRedirectInitializing==false,"host clears initialization only after all Actor installs")
check(attrs.AttributeShellRedirectHeartbeat==publicationTime and shellRedirection.heartbeatAt==publicationTime,
    "host publishes a fresh completion heartbeat rather than the stale update-entry timestamp")
check(shellRedirection.installAt==publicationTime,"Actor confirmation timeout starts after installation completes")
shellRedirection.stop()
publicationTime=1
shellRedirection.active=true;shellRedirection.owner="fixture"
shellRedirection.actors={actor};shellRedirection.ready=1;shellRedirection.installAt=1
shellRedirection.heartbeatAt=nil;shellRedirection.statusAt=nil;shellRedirection.publishedShot=nil
actorAttrs.AttributeShellRedirectStatus="fixture"
lp:SetAttribute("AttributeShellRedirectOwner","fixture")
shellRedirection.held=true;shellRedirection.heldKey=Settings.ShellFocusKey
shellRedirection.focused=actorTarget.player;shellRedirection.focusedRecord=actorTarget
shellRedirection.update()
check(attrs.AttributeShellRedirectTargetId==202,"host publishes only focused player identity")
local identityWrites=attributeWrites.AttributeShellRedirectTargetId
local heartbeats=attributeWrites.AttributeShellRedirectHeartbeat or 0
for i=1,120 do
    publicationTime=1+(i-1)/120
    actorTarget.part.Position=Vector3.new(i,200,0)
    shellRedirection.update()
end
check(attributeWrites.AttributeShellRedirectTargetId==identityWrites,"moving target causes zero repeated identity broadcasts")
check(not attributeWrites.AttributeShellRedirectPosition and not attributeWrites.AttributeShellRedirectVelocity,
    "host never publishes moving Vector3 pose attributes")
check((attributeWrites.AttributeShellRedirectHeartbeat or 0)-heartbeats<=4,"ownership heartbeat is bounded to four updates per second")
local wakeWrites=attributeWrites.AttributeShellRedirectShot
shellRedirection.shotSerial=1;shellRedirection.update();shellRedirection.update()
check(attributeWrites.AttributeShellRedirectShot==wakeWrites+1,"confirmed shot changes wake attribute only once")
shellRedirection.release()
check(not attrs.AttributeShellRedirectHeld and not attrs.AttributeShellRedirectTargetId,"release clears hold and identity outside publication timer")
shellRedirection.active=false
]]
    code=code..[[
local created={}
local Instance={new=function(class)
    local object={ClassName=class,Destroy=function(self)self.destroyed=true end}
    created[#created+1]=object
    return object
end}
local THEME={TextPrimary=Color3.fromRGB(241,242,246)}
]]..section('function shellRedirection.assign(', 'function shellRedirection.frame(')..[[
shellRedirection.held=true;shellRedirection.heldKey=Settings.ShellFocusKey
shellRedirection.focused=b.player;shellRedirection.focusedPart=b.part
local pixel=Vector2.new(400,200)
shellRedirection.draw(camera,pixel)
local visuals=shellRedirection.visuals
check(visuals.gui.IgnoreGuiInset and visuals.circle.Position.X.Offset==400 and visuals.circle.Position.Y.Offset==200,
    "focus circle uses viewport coordinates")
check(visuals.circle.Size.X.Offset==120 and visuals.circle.Size.Y.Offset==120 and visuals.stroke.Thickness==1,
    "circle exactly matches focus radius with thin stroke")
check(visuals.highlight.Enabled and visuals.highlight.Adornee==b.character and visuals.highlight.FillColor==Settings.ShellFocusColor,
    "only focused character receives distinct color")
check(visuals.tracer.Visible and visuals.tracer.Size.Y.Offset==1,"one thin target tracer")
local start=Vector2.new(640,716)
local finish=Vector2.new(20,0)
check(math.abs(visuals.tracer.Size.X.Offset-(finish-start).Magnitude)<0.001,"tracer endpoints follow projection")
local count=#created
local writes=shellRedirection.visualWrites
for i=1,20 do shellRedirection.draw(camera,pixel) end
check(#created==count,"visuals reused rather than rebuilt per frame")
check(shellRedirection.visualWrites==writes,"stationary focus performs no repeated Highlight or GUI writes")
Settings.ShellFocusTracer=false;Settings.ShellFocusHighlight=false
shellRedirection.draw(camera,pixel)
check(not visuals.tracer.Visible and not visuals.highlight.Enabled and not visuals.highlight.Adornee,
    "disabled Highlight does not retain a target binding")
Settings.ShellFocusTracer=true;Settings.ShellFocusHighlight=true
b.part.Position=Vector3.new(20,0,-1)
shellRedirection.draw(camera,pixel)
check(not visuals.tracer.Visible and not visuals.highlight.Enabled,"behind-camera target hidden")
b.part.Position=Vector3.new(20,0,100)
shellRedirection.draw(camera,pixel);shellRedirection.release()
check(not visuals.tracer.Visible and not visuals.highlight.Enabled and not visuals.highlight.Adornee,"release removes target cues")
shellRedirection.draw(camera,pixel)
check(visuals.circle.Visible and not visuals.tracer.Visible,"idle circle remains without target tracer")
textbox={};shellRedirection.draw(camera,pixel)
check(not visuals.gui.Enabled,"typing hides focus visuals")
textbox=nil;Settings.ShellRedirection=false;shellRedirection.draw(camera,pixel)
check(not visuals.gui.Enabled and not visuals.highlight.Enabled,"disabled mode hides overlay and highlight")
]]
    code=code..[[
local simTime=1
local os={clock=function()return simTime end}
local function refreshAimFilters()end
local function getActiveTank()return nil end
local freecamActive=false
camera.ViewportPointToRay=function()return {Origin=Vector3.zero}end
local renderPublishes=0
shellRedirection.update=function()renderPublishes+=1 end
shellRedirection.refreshPlayers=function()end
]]..section('function shellRedirection.frame(', 'function shellRedirection.destroy(')..[[
Settings.ShellRedirection=true;Settings.AimSource="Camera"
shellRedirection.held=true;shellRedirection.heldKey=Settings.ShellFocusKey;shellRedirection.nextFocusScan=nil
shellRedirection.players={b};blocked={}
b.part.Position=Vector3.new(640,360,100)
local scansBefore=shellRedirection.focusScans
local raysBefore=shellRedirection.focusRays
for i=1,120 do
    simTime=1+(i-1)/120
    shellRedirection.frame(camera)
end
local scans=shellRedirection.focusScans-scansBefore
check(scans>0 and scans<=20,"120 render frames perform at most 20 acquisition scans")
check(shellRedirection.focusRays-raysBefore<=20,"stable visible focus raycasts are rate limited")
check(shellRedirection.focused==b.player and visuals.tracer.Visible,"throttled focus retains live target cues")
check(renderPublishes==0,"camera render callback performs no Actor publications")
Settings.ShellVisibilityCheck=false;simTime+=0.051
local beforeRay=rayCount
for i=1,120 do simTime+=1/120;shellRedirection.frame(camera) end
check(rayCount==beforeRay,"visibility-off focus performs zero world raycasts over moving frames")
Settings.ShellFocusKey=Enum.KeyCode.F;shellRedirection.frame(camera)
check(not shellRedirection.held and not visuals.tracer.Visible,"rebinding during a hold clears old input")
Settings.ShellFocusKey=Enum.UserInputType.MouseButton2;shellRedirection.inputBegan(rmb,false)
simTime+=0.051;shellRedirection.frame(camera)
b.part.Position=Vector3.new(2000,360,100)
shellRedirection.frame(camera)
check(not shellRedirection.focused and not visuals.tracer.Visible,"leaving FOV clears between acquisition scans")
b.part.Position=Vector3.new(640,360,100);simTime+=0.051
shellRedirection.frame(camera)
b.humanoid.Health=0;shellRedirection.frame(camera)
check(not shellRedirection.focused and not visuals.highlight.Enabled,"death clears immediately between acquisition scans")
b.humanoid.Health=100;simTime+=0.051;shellRedirection.frame(camera)
shellRedirection.release();shellRedirection.frame(camera)
check(not shellRedirection.focused and not visuals.tracer.Visible,"RMB release remains immediate with scan throttling")
]]
    code=code..section('function shellRedirection.stop(', 'function shellRedirection.update(')
        ..section('function shellRedirection.destroy(', '-- Prefer vehicles/characters')..[[
local disconnected=0
local connection={Disconnect=function()disconnected+=1 end}
shellRedirection.began=connection;shellRedirection.ended=connection;shellRedirection.focusLost=connection;shellRedirection.tick=connection
Settings.ShellRedirection=true
shellRedirection.destroy()
check(disconnected==4 and visuals.gui.destroyed and visuals.highlight.destroyed and not shellRedirection.visuals,
    "unload removes owned input handlers and visual objects")
check(shellRedirection.destroyed and not shellRedirection.isEngaged() and Settings.ShellRedirection,
    "unload prevents reengagement without changing remembered toggle")
]]
    code=code..[[
Settings.OwnShellHighlight=true
local flightCalls,forecastCalls,drawCalls,removeCalls=0,0,0,0
local visualContainer={}
local ballistics={lifetime=function()return 60 end}
local function traceTrajectory()forecastCalls+=1;error("unexpected forecast in redirection")end
local shotTracker={queue={},entries={},candidates={},observed=0,attempts=1,
    makeFlightOverlay=function(entry)flightCalls+=1;entry.shellMarker={} end,
    announce=function()end,remove=function()removeCalls+=1 end,
    projectProgress=function()error("unexpected fixed-route projection")end}
]]..section('function shotTracker.attach(', 'function shotTracker.discover(')
    ..section('function shotTracker.drawShell(', 'function shotTracker.projectProgress(')..[[
local entry={sentAt=simTime,weapon={gravity=-10},attempt=1}
local projectile={position0=Vector3.zero,velocity0=Vector3.xAxis*100,position=Vector3.new(20,0,100),Lifetime=60}
shotTracker.attach(entry,projectile)
check(entry.redirectionFlight and #entry.samples==0 and forecastCalls==0,"steerable launch has no collision forecast or sampled route")
check(flightCalls==1 and not entry.zone and not entry.targetHud,"steerable launch creates marker without forecast lines or target HUD")
shotTracker.drawShell(entry,camera)
check(entry.shellMarker.Visible and entry.shellMarker.Position.X.Offset==20,"actual observed shell marker remains available")
shotTracker.drawFlight=function(value,cam)drawCalls+=1;shotTracker.drawShell(value,cam)end
local RunService={BindToRenderStep=function(_,name,priority,fn)shotTracker.render=fn end}
local FREECAM_PRIORITY=2000000
workspace.CurrentCamera=camera
]]..section('RunService:BindToRenderStep("AutoLeadShotTracking",', 'local fireReadiness =')..[[
shotTracker.entries={entry};simTime+=0.1
shotTracker.render()
check(drawCalls==1 and not entry.finished and not entry.eta,"steerable flight tracks shell without fixed-endpoint ETA or arrival")
projectile.destroy=true;simTime+=0.1;shotTracker.render()
check(removeCalls==1 and #shotTracker.entries==0,"observed steerable flight end removes ESP")
local legacy={state={position=Vector3.new(20,0,100)},started=simTime,lastPosition=Vector3.zero,
    lastMoved=simTime,lines={{border={Visible=true}}},zone={Transparency=0.48},targetHud={Enabled=true},
    shellMarker={},attempt=1,initialVelocity=Vector3.xAxis*100}
shotTracker.entries={legacy};simTime+=0.1;shotTracker.render()
check(legacy.redirectionFlight and not legacy.lines[1].border.Visible and legacy.zone.Transparency==1
    and not legacy.targetHud.Enabled,"enabling redirection mid-flight pauses legacy route and impact HUD")
]]
    code=code..[[
local keyData,resetLock
local handle={Mode="Hold"}
function handle:SetMode(mode)self.Mode=mode;keyData.OnChanged("Enum.KeyCode.F",mode)end
function handle:Set(value)keyData.OnChanged("Enum.UserInputType.MouseButton2",value.Mode)end
local aimTarget={Label=function()return {AddKeybind=function(_,data)keyData=data;return handle end}end,
    Button=function()return {Add=function(_,label,fn)resetLock=fn end}end}
local function settingToggle()end
]]..section('settingToggle(aimTarget, "Shell Redirection",', 'settingToggle(aimTarget, "Target Visibility Check",')..[[
check(keyData.Mode=="Hold" and type(resetLock)=="function","UI exposes hold rebind and RMB reset through library API")
keyData.OnChanged("Enum.KeyCode.F","Hold")
check(Settings.ShellFocusKey==Enum.KeyCode.F,"UI binding change reaches raw input setting")
keyData.OnChanged("Enum.KeyCode.F","Toggle")
check(handle.Mode=="Hold","lock key remains hold-to-engage even if menu mode changes")
resetLock()
check(Settings.ShellFocusKey==Enum.UserInputType.MouseButton2,"reset button restores RMB binding")
local previewHidden,cacheRefreshes,beyondGuard=0,0,false
local blastDistance={gui={Enabled=false}}
local visualDiagnostics={rays=192,flightTime=20}
local previousVisualFrame=0
local VISUAL_RENDER_NAME="fixture-preview"
local function refreshAimCache()cacheRefreshes+=1 end
local function hideVisuals()previewHidden+=1 end
RunService.BindToRenderStep=function(_,name,priority,fn)shotTracker.preview=fn end
]]..section('RunService:BindToRenderStep(VISUAL_RENDER_NAME,', '-- The Beam is engine-rendered;')..[[
beyondGuard=true
    end,function(err)return tostring(err)end)
    assert(ok,failure)
end)
shotTracker.preview()
check(previewHidden==1 and cacheRefreshes==1 and not beyondGuard,"redirection skips all pre-shot preview tracing while retaining native weapon cache")
check(visualDiagnostics.rays==0 and visualDiagnostics.flightTime==0,"paused preview diagnostics do not advertise stale rays or flight time")
return {passed=passed,sceneMutations=false}
]]
    if returnFixture then return code end
    return assert(loadstring(code,"shell-redirection.spec"))()
end

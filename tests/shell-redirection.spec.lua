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
    ShellFocusHighlight=true,ShellFocusColor=Color3.fromRGB(255,209,90)}
local shellRedirection={players={},candidates={},held=true}
local Players={}
local attrs={AttributeShellRedirectOwner="fixture",AttributeShellRedirectHeartbeat=os.clock(),AttributeShellRedirectHeld=true}
local attributeReads=0
local lp={Team="blue",Parent=true,PlayerGui={},GetAttribute=function(_,k) attributeReads+=1;return attrs[k] end,
    SetAttribute=function(_,k,v)attrs[k]=v end}
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
        IsDescendantOf=function(_,model)return model==character end}
    local player={Parent=Players,Team=team or "red",Neutral=false,Character=character}
    return {player=player,character=character,part=part,humanoid={Health=100}}
end
]]..section('function shellRedirection.isEngaged(', '-- Runs inside each native projectile Actor')..steerSource..[[
local a,b=record(10),record(20)
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
local game={GetService=function(_,name)
    if name=="Players" then return {LocalPlayer=lp} end
    return {PHRST={Threads={FindFirstChild=function()return actor end}}}
end}
local calls=0
local original=function() calls+=1;return "native",nil,42 end
local environment={simulatebullet=original}
local filtergc=function()return {original}end
local getfenv=function()return environment end
local cleanup
local task={spawn=function(fn)cleanup=fn end,wait=function()error("unexpected fixture wait")end}
]]
    actorSource=actorSource:gsub('@ACTOR@','"fixture"'):gsub('@OWNER@','"fixture"')
        :gsub('@STEER@',function()return steerSource end)
    code=code..actorSource..[[
check(environment.simulatebullet~=original and actorAttrs.AttributeShellRedirectStatus=="fixture","Actor environment hook confirms installation")
attrs.AttributeShellRedirectPosition=target;attrs.AttributeShellRedirectVelocity=Vector3.zero
s=state()
local results=table.pack(environment.simulatebullet(s))
check(s.velocity.Y>99 and calls==1,"wrapper steers before native simulation display")
check(results.n==3 and results[1]=="native" and results[3]==42,"native return values preserved")
local readsBefore=attributeReads
for i=1,100 do local foreign=state();foreign.replicate=false;environment.simulatebullet(foreign) end
check(attributeReads==readsBefore,"other players' shells require no Actor attribute reads")
readsBefore=attributeReads
for i=1,10 do environment.simulatebullet(state()) end
check(attributeReads-readsBefore<=23,"own shells reuse position velocity and heartbeat within refresh interval")
attrs.AttributeShellRedirectHeld=false
s=state();environment.simulatebullet(s)
check(s.velocity==Vector3.xAxis*100,"Actor hold gate immediately prevents steering")
attrs.AttributeShellRedirectHeld=true
shellRedirection.active=true;shellRedirection.owner="fixture"
shellRedirection.inputEnded(rmb)
check(not shellRedirection.held and not shellRedirection.focused and attrs.AttributeShellRedirectHeld==false
    and attrs.AttributeShellRedirectPosition==nil,"RMB release immediately clears published target")
shellRedirection.inputBegan(rmb,false);shellRedirection.release()
check(not shellRedirection.isEngaged(),"focus-loss release cancels held input")
shellRedirection.active=false
attrs.AttributeShellRedirectOwner=nil
s=state();environment.simulatebullet(s)
check(s.velocity==Vector3.xAxis*100,"disabled owner stops steering immediately")
cleanup()
check(environment.simulatebullet==original and actorAttrs.AttributeShellRedirectStatus==nil,"cleanup restores owned callback/status")
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
shellRedirection.held=true;shellRedirection.focused=b.player;shellRedirection.focusedPart=b.part
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
check(not visuals.tracer.Visible and not visuals.highlight.Enabled,"visual toggles independent")
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
shellRedirection.update=function()end
]]..section('function shellRedirection.frame(', 'function shellRedirection.destroy(')..[[
Settings.ShellRedirection=true;Settings.AimSource="Camera"
shellRedirection.held=true;shellRedirection.nextFocusScan=nil
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
shellRedirection.began=connection;shellRedirection.ended=connection;shellRedirection.focusLost=connection
Settings.ShellRedirection=true
shellRedirection.destroy()
check(disconnected==3 and visuals.gui.destroyed and visuals.highlight.destroyed and not shellRedirection.visuals,
    "unload removes owned input handlers and visual objects")
check(shellRedirection.destroyed and not shellRedirection.isEngaged() and Settings.ShellRedirection,
    "unload prevents reengagement without changing remembered toggle")
return {passed=passed,sceneMutations=false}
]]
    if returnFixture then return code end
    return assert(loadstring(code,"shell-redirection.spec"))()
end

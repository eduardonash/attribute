-- Extract production steering and selection into mock scene/Actor fixtures.
return function(source)
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
local Settings={ShellRedirection=true,ShellFocusRadius=60}
local shellRedirection={players={},candidates={}}
local Players={}
local attrs={AttributeShellRedirectOwner="fixture",AttributeShellRedirectHeartbeat=os.clock()}
local lp={Team="blue",Parent=true,GetAttribute=function(_,k) return attrs[k] end}
local aimWorldParams={}
local blocked,rayCount={},0
local workspace={Raycast=function(_,origin,delta)
    rayCount+=1
    if blocked[delta.X] then return {Instance={IsDescendantOf=function() return false end}} end
end}
local camera={WorldToViewportPoint=function(_,p) return p,p.X<1000 end}
local function record(x,team)
    local character={}
    local part={Parent=character,Position=Vector3.new(x,0,100),AssemblyLinearVelocity=Vector3.zero}
    local player={Parent=Players,Team=team or "red",Neutral=false,Character=character}
    return {player=player,character=character,part=part,humanoid={Health=100}}
end
]]..section('function shellRedirection.select(', '-- Runs inside each native projectile Actor')..steerSource..[[
local a,b=record(10),record(20)
shellRedirection.players={a,b}
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
attrs.AttributeShellRedirectOwner=nil
s=state();environment.simulatebullet(s)
check(s.velocity==Vector3.xAxis*100,"disabled owner stops steering immediately")
cleanup()
check(environment.simulatebullet==original and actorAttrs.AttributeShellRedirectStatus==nil,"cleanup restores owned callback/status")
return {passed=passed,sceneMutations=false}
]]
    return assert(loadstring(code,"shell-redirection.spec"))()
end

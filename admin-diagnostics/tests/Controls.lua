local source=arg[1] or 'admin-diagnostics/media/lua/client/AdminDiagnostics/Controls.lua'
require=function() end
local checks=0
local function check(ok,msg) assert(ok,msg);checks=checks+1 end
local staff,ctrl,shift=true,false,false
local starts,stops,marks=0,0,0
AdminDiagnostics={allowed=function() return staff end,start=function() starts=starts+1;AdminDiagnostics.enabled=true;return true end,
    stop=function() stops=stops+1;AdminDiagnostics.enabled=false end,mark=function() marks=marks+1 end}
local callbacks={}
Events=setmetatable({}, {__index=function(_,name) return {Add=function(fn) callbacks[name]=fn end} end})
Keyboard={KEY_F10=68,KEY_F11=87}
isCtrlKeyDown=function() return ctrl end;isShiftKeyDown=function() return shift end
getPlayer=function() return {setHaloNote=function() end,getPlayerNum=function() return 0 end} end
ISAdminPanelUI={create=function(p) p.nativeCreated=true end}
ISButton={new=function(_,x,y,w,h,title,target,callback)
    return {x=x,y=y,width=w,height=h,initialise=function() end,instantiate=function() end,onclick=callback}
end}
ISModalDialog={new=function() return {initialise=function() end,addToUIManager=function() end} end}
dofile(source)
callbacks.OnKeyPressed(68);check(starts==0,'Unmodified F10 is untouched')
ctrl=true;shift=true;staff=false;callbacks.OnKeyPressed(68)
check(starts==0,'Shortcut restricted to opted-in staff')
staff=true;callbacks.OnKeyPressed(68);check(starts==1,'Toggle shortcut starts')
callbacks.OnKeyPressed(87);check(marks==1,'Incident marker shortcut works without a visible panel')
callbacks.OnKeyPressed(68);check(stops==1,'Toggle shortcut stops')
callbacks.OnKeyPressed(87);check(marks==1,'Marker while stopped does not silently start logging')
local options={};local context={addOption=function(_,name,target,fn) options[#options+1]={name=name,fn=fn} end}
callbacks.OnFillWorldObjectContextMenu(0,context)
check(#options==2,'Stopped context offers start and help')
AdminDiagnostics.enabled=true;options={};callbacks.OnFillWorldObjectContextMenu(0,context)
check(#options==3,'Recording context also offers manual marker')
staff=false;options={};callbacks.OnFillWorldObjectContextMenu(0,context)
check(#options==0,'No controls injected for ordinary players')
staff=true;callbacks.OnGameStart()
local panel={height=300,cancel={x=10,y=250,width=200,height=25,setY=function(self,v) self.y=v end},
    addChild=function(self,b) self.button=b end,setHeight=function(self,v) self.height=v end}
ISAdminPanelUI.create(panel)
check(panel.nativeCreated and panel.button.onclick==AdminDiagnostics.toggle,'Native admin panel remains functional and gets diagnostic control')
check(panel.cancel.y==285 and panel.height==335,'Close button moves below added control')
local registered={};AdminCore={registerAction=function(a) registered[#registered+1]=a end}
callbacks.OnGameStart()
check(#registered==3 and registered[1].category=='Logs','Optional core integration registers three log actions')
print('PASS: '..checks..' diagnostic control checks')

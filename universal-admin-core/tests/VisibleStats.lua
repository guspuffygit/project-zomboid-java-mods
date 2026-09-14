require=function() end
local callbacks={}
Events=setmetatable({}, {__index=function(t,key) local e={Add=function(fn) callbacks[key]=fn end};rawset(t,key,e);return e end})
local allowed=true
Capability={ReadUserLog="ReadUserLog"}
AdminCore={allowed=function() return allowed end}
getUsers=function() error("Must not enumerate the server account directory") end
local now=10000
getTimestampMs=function() return now end
local requests={}
sendClientCommand=function(m,c,args) requests[#requests+1]={command=c,args=args} end
local list={items={},height=300,itemheight=60,scroll=0,getYScroll=function(self) return self.scroll end}
for i=1,10000 do
    local name="user"..i
    list.items[i]={item={getUsername=function() return name end}}
end
ISUsersList={instance={datas=list,getIsVisible=function() return true end}}
dofile("universal-admin-core/media/lua/client/AdminCore/DataAndObserve.lua")
local n=0
local function check(value,message) assert(value,message);n=n+1 end
AdminCore.requestStats();callbacks.OnTick()
check(#requests==1 and #requests[1].args.names==7,"Request only viewport and two buffer rows")
check(requests[1].args.names[1]=="user1","Visible request starts at first row")
now=11000;callbacks.OnTick()
check(#requests==1,"Pending rows are not retried every second")
list.scroll=-6000;now=12000;callbacks.OnTick()
check(#requests==2 and requests[2].args.names[1]=="user101","Scrolling requests the new viewport")
ISUsersList.instance=nil;now=13000;callbacks.OnTick()
check(#requests==2,"Closing list stops all data requests")
ISUsersList.instance={datas=list};allowed=false;now=25000;callbacks.OnTick()
check(#requests==2,"Revoked role stops requests")
callbacks.OnDisconnect()
check(next(AdminCore.stats)==nil,"Disconnect clears cached player information")
print("PASS: "..n.." visible-row data checks")

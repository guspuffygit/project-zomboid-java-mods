-- Membership arriving after opening the User Panel must enable its safehouse entry.
require=function() end
local n=0
local function check(ok,msg) assert(ok,msg);n=n+1 end
getText=function(key) return key end
local house
SafeHouse={hasSafehouse=function() return house end}
local function button(x,y,w,h)
    return {x=x,y=y,width=w,height=h,setY=function(self,v) self.y=v end,
        initialise=function() end,instantiate=function() end,
        setVisible=function(self,v) self.visible=v end,setEnable=function(self,v) self.enable=v end}
end
ISButton={new=function(_,x,y,w,h,text,target,callback)
    local b=button(x,y,w,h);b.target=target;b.callback=callback;return b
end}
local nativeUpdates=0
ISUserPanelUI={create=function() end,updateButtons=function() nativeUpdates=nativeUpdates+1 end,onOptionMouseDown=function() end}
dofile('universal-admin-core/media/lua/client/AdminCore/UserPanel.lua')
local function panel(existing)
    local p={height=200,factionBtn=button(10,40,150,20),ticketsBtn=button(10,70,150,20),safehouseBtn=existing,
        player={getUsername=function() return 'guest' end},buttonBorderColor={}}
    p.children={p.factionBtn,p.ticketsBtn}
    function p:getChildren() return self.children end
    function p:addChild(child) self.children[#self.children+1]=child end
    function p:setHeight(v) self.height=v end
    return p
end
local p=panel()
ISUserPanelUI.create(p)
check(p.safehouseBtn.internal=='SAFEHOUSEPANEL' and p.safehouseBtn.callback==ISUserPanelUI.onOptionMouseDown,'Native action retained')
check(p.ticketsBtn.y==100 and p.height==230,'Existing controls shift to make room')
ISUserPanelUI.updateButtons(p)
check(p.safehouseBtn.visible and not p.safehouseBtn.enable,'Missing membership keeps a visible disabled entry')
house={};ISUserPanelUI.updateButtons(p)
check(p.safehouseBtn.enable,'Later membership enables the entry')
house=nil;ISUserPanelUI.updateButtons(p)
check(not p.safehouseBtn.enable and nativeUpdates==3,'Removal disables entry and native updates remain')
local existing=button(10,70,150,20);p=panel(existing)
ISUserPanelUI.create(p)
check(p.safehouseBtn==existing and p.height==200,'No duplicate native safehouse entry')
print('PASS: '..n..' User Panel membership checks')

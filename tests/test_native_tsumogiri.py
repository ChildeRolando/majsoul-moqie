"""Semantic tests in LuaJIT 2.1; native Unity rendering still needs client tests."""
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "python"))
from lupa.luajit21 import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
script = (ROOT / "lua" / "native-tsumogiri.lua").read_text(encoding="utf-8").replace("__DEFAULT_ENABLED__", "true")
lua.execute("""
GameUtility={E_MJArea={qipai=1,hand=2},EMJ_Mode={play=1,record=2}}
DesktopMgr={Inst={mode=1}}
ViewPai={}
function ViewPai:Build(v) self.pai={value=v,ToString=function(s)return tostring(s.value)end};self.ismoqie=false;self.area=1 end
function ViewPai:RefreshColor() self.color='normal' end
function ViewPai:OnChoosed()
  self.calls=(self.calls or 0)+1
  if self.fail then error('native failure') end
  if self.highlight then self.color='blue'
  elseif self.pink then self.color='pink'
  elseif self.ismoqie then self.color='gray'
  else self:RefreshColor() end
end
function ViewPai:Dispose() self.pai=nil;self.ismoqie=false;self.area=0;self.color='normal' end
function tile(v) local t=setmetatable({}, {__index=ViewPai});t:Build(v);return t end
""")
lua.execute(script)
lua.execute("""
-- Same value, different real references and semantics.
a=tile(5); b=tile(5)
NativeTsumogiri.Bind(a,true); NativeTsumogiri.Bind(b,false)
a:OnChoosed();b:OnChoosed()
assert(a.color=='gray' and b.color=='normal' and a.ismoqie==false)
-- Native highlight and pink priority survive; all restore paths converge.
a.highlight=true;a:OnChoosed();assert(a.color=='blue')
a:RefreshColor();assert(a.color=='blue')
a.highlight=false;a.pink=true;a:OnChoosed();assert(a.color=='pink')
a.pink=false;a:RefreshColor();assert(a.color=='gray')
-- Disable refreshes existing instances and restores native live state.
assert(string.find(NativeTsumogiri.Toggle(),'enabled=false'))
assert(a.color=='normal' and b.color=='normal' and a.ismoqie==false)
NativeTsumogiri.Toggle();assert(a.color=='gray' and b.color=='normal')
-- Unknown booleans and explicit false never create a new mark.
c=tile(5);NativeTsumogiri.Bind(c,nil);c:OnChoosed();assert(c.color=='normal')
NativeTsumogiri.Bind(c,0);c:OnChoosed();assert(c.color=='normal')
NativeTsumogiri.Bind(c,false);c:OnChoosed();assert(c.color=='normal')
-- Only qipai, not hand objects.
c.area=2;NativeTsumogiri.Bind(c,true);c:OnChoosed();assert(c.color=='normal')
-- Exception restores game semantics before propagation.
a.fail=true;local ok,err=pcall(a.OnChoosed,a)
assert(not ok and string.find(err,'native failure') and a.ismoqie==false)
a.fail=false
-- Dispose/call-removal and reuse clear the sidecar.
a:Dispose();assert(NativeTsumogiri.objects[a]==nil and a.color=='normal')
a:Build(5);a:OnChoosed();assert(a.color=='normal')
NativeTsumogiri.Bind(a,true);a:OnChoosed();assert(a.color=='gray')
NativeTsumogiri.Bind(a,false);a:OnChoosed();assert(a.color=='normal')
NativeTsumogiri.Bind(a,true);a:Build(9);a:OnChoosed();assert(a.color=='normal' and NativeTsumogiri.objects[a]==nil)
-- Disabled plugin preserves replay's pre-existing native gray.
DesktopMgr.Inst.mode=2;r=tile(5);r.ismoqie=true;NativeTsumogiri.Bind(r,true)
NativeTsumogiri.Toggle();r:OnChoosed();assert(r.color=='gray' and r.ismoqie==true)
local before=r.calls
""")
lua.execute(script)  # no nesting of native methods after a duplicate patch
lua.execute("""
local before=r.calls;r:OnChoosed();assert(r.calls==before+1)
assert(string.find(NativeTsumogiri.Snapshot(),'live_binds='))
NativeTsumogiri.Uninstall();assert(ViewPai.__native_tsumogiri_v1==nil)
assert(NativeTsumogiri.Bind==nil and NativeTsumogiri.Toggle==nil)
r:OnChoosed();assert(r.color=='gray')
""")
print("PASS: live semantic binding, same-value separation, highlight/refresh, toggle, unknowns, errors, disposal/rebind, replay, idempotence, uninstall")

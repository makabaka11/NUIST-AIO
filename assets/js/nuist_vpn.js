// Read-only Enlink resource probe. clientInfo and userId never leave this origin.
if(location.origin!=='https://client.vpn.nuist.edu.cn')return {ok:false,error:'请先完成学校 VPN 登录。'};
try {
  const raw=document.cookie.split(/;\s*/).find(c=>c.startsWith('clientInfo='));
  if(!raw)return {ok:false,error:'需要在学校官方页面连接 VPN。'};
  const info=JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(decodeURIComponent(raw.slice(11))),c=>c.charCodeAt(0))));
  if(typeof info.userId!=='string'||!info.userId)return {ok:false,error:'VPN 会话未就绪。'};
  const abort=new AbortController(),timer=setTimeout(()=>abort.abort(),10000);
  try {
    const response=await fetch('/enlink/api/client/service/group/treeWithService/',{method:'POST',credentials:'include',redirect:'error',signal:abort.signal,
      headers:{'Content-Type':'application/json'},body:JSON.stringify({nameLike:'',serviceNameLike:'',userId:info.userId})});
    const p=await response.json();
    if(!response.ok||String(p.code)!=='200'||!Array.isArray(p.data?.serviceAllList))return {ok:false,error:'VPN 登录已失效或资源目录不可用。'};
    const routes={};
    // Export only verified resource origins; external browser entries do not
    // gain an in-app data adapter. Opaque gateway prefixes are never guessed.
    const allowed=new Set(['https://bulletin.nuist.edu.cn','http://stu.nuist.edu.cn','http://xdex.nuist.edu.cn:18080','https://cxcyjy.nuist.edu.cn']);
    for(const s of p.data.serviceAllList){
      if(s.canVisit!==true||s.type!=='web')continue;
      try {
        const source=new URL(s.server),proxy=new URL(s.urlPlus);
        if(!allowed.has(source.origin)||source.pathname!=='/'||source.search||source.hash||source.username||source.password)continue;
        if(proxy.origin!=='https://client.vpn.nuist.edu.cn'||proxy.username||proxy.password||proxy.search)continue;
        const prefix=proxy.pathname.match(/^\/(http|https)\/webvpn[0-9a-f]{64}(?=\/|$)/);
        if(!prefix||prefix[1]+':'!==source.protocol)continue;
        const expected=new URL(s.path||'/',source.origin);
        const suffix=proxy.pathname.slice(prefix[0].length)+proxy.hash;
        const normalize=v=>v.replace(/\/$/,'');
        if(expected.origin!==source.origin||expected.search||normalize(suffix)!==normalize(expected.pathname+expected.hash))continue;
        routes[source.origin]=proxy.origin+prefix[0];
      }catch(_){/* One malformed directory record must not break other entries. */}
    }
    return {ok:true,ready:true,routes};
  }finally{clearTimeout(timer);}
}catch(_){return {ok:false,error:'VPN 会话验证失败，请在官方页面重新连接。'};}

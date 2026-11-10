// Parse only verified NUIST bulletin markup. No email, LLM or third-party upload.
const canonicalOrigin='https://bulletin.nuist.edu.cn';
const a=typeof params==='object'&&params?params:{};
const prefix=location.origin==='https://client.vpn.nuist.edu.cn'?(location.pathname.match(/^\/https\/webvpn[0-9a-f]{64}(?=\/|$)/)?.[0]||''):'';
if(location.origin!==canonicalOrigin&&!prefix)return {ok:false,error:'请先连接学校公告板。'};
function canonical(value,base=canonicalOrigin+'/') {
  try{
    let u=new URL(value,base);
    if(prefix&&u.origin===location.origin&&u.pathname.startsWith(prefix+'/'))u=new URL(canonicalOrigin+u.pathname.slice(prefix.length)+u.search);
    if(u.origin!==canonicalOrigin||u.username||u.password)return null;
    if(!(u.pathname==='/'||/^\/[a-zA-Z0-9_/-]+\.htm$/.test(u.pathname)||u.pathname==='/content.jsp'||u.pathname==='/system/_content/download.jsp'))return null;
    if([...u.searchParams.keys()].some(k=>!['urltype','wbtreeid','wbnewsid','owner','wbfileid'].includes(k)))return null;
    return u.origin+u.pathname+u.search;
  }catch(_){return null;}
}
function route(url){const u=new URL(url);return prefix?location.origin+prefix+u.pathname+u.search:url;}
const clean=e=>e?.textContent?.replace(/\u00a0/g,' ').trim()||'';
try {
  const url=canonical(a.url||canonicalOrigin+'/index.htm');
  if(!url)throw Error('公告链接不在已接入的学校站点范围内。');
  const abort=new AbortController(),timer=setTimeout(()=>abort.abort(),10000);
  let html;
  try {
    const response=await fetch(route(url),{credentials:'include',redirect:'error',signal:abort.signal});
    if(!response.ok)throw Error('公告站点暂不可达，请检查网络路径后重试。');
    html=await response.text();
    if(html.length>4000000)throw Error('公告页面过大，请使用原网页查看。');
  }finally{clearTimeout(timer);}
  const doc=new DOMParser().parseFromString(html,'text/html');
  if(task==='list') {
    const rows=[];
    for(const li of doc.querySelectorAll('li.news')){
      const link=li.querySelector('.btt a'),date=clean(li.querySelector('.news_date')),href=canonical(link?.getAttribute('href'),url);
      if(!link||!href||!/^\d{4}-\d{2}-\d{2}$/.test(date))continue;
      const title=(link.getAttribute('title')||clean(link)).trim();
      if(!title)continue;
      rows.push({title,url:href,date,category:clean(li.querySelector('.wjj a')).replace(/^\[|\]$/g,''),department:clean(li.querySelector('.news_org')),pinned:!!li.querySelector('.zdtb img')});
    }
    if(!rows.length||!doc.querySelector('.news_date'))throw Error('未收到有效公告列表，可能需要连接校园网或 VPN。');
    const categories=[],seen=new Set();let next=null;
    for(const link of doc.querySelectorAll('a[href]')){
      const name=clean(link),href=canonical(link.getAttribute('href'),url);
      if(name==='下页'&&href)next=href;
      if(!href||link.closest('li.news')||!name||name.length>12||!/^\/[a-zA-Z0-9_]+\.htm$/.test(new URL(href).pathname)||seen.has(href))continue;
      seen.add(href);categories.push({name,url:href});
    }
    return {ok:true,rows,categories,next,url};
  }
  if(task==='detail') {
    const body=doc.querySelector('[id^="vsb_content_"],.v_news_content');
    if(!body)throw Error('正文暂不可读，请切换网络路径或在原网页中查看。');
    body.querySelectorAll('script,style,iframe,form').forEach(n=>n.remove());
    const links=[],seen=new Set();
    for(const link of body.querySelectorAll('a[href]')){
      const href=canonical(link.getAttribute('href'),url),name=clean(link);
      if(href&&name&&!seen.has(href)){seen.add(href);links.push({name,url:href});}
    }
    body.querySelectorAll('br').forEach(n=>n.replaceWith('\n'));
    body.querySelectorAll('p,div,li,tr,h1,h2,h3').forEach(n=>n.append('\n'));
    return {ok:true,title:clean(doc.querySelector('h1')),body:clean(body).replace(/\n[ \t]*\n(?:[ \t]*\n)+/g,'\n\n'),links,url};
  }
  throw Error('不支持的公告查询。');
}catch(e){return {ok:false,error:e?.name==='AbortError'?'公告查询超时，请检查网络路径。':e instanceof TypeError?'公告连接失败，请连接校园网或学校 VPN。':e?.message||'公告读取失败。'};}

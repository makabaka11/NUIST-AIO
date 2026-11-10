// Endpoints and fields verified against the library's own public PC bundle.
if(location.origin!=='https://elib.nuist.edu.cn')return {ok:false,error:'请在图书馆官方页面连接账户。'};
if(!['probe','loans'].includes(task))return {ok:false,error:'不支持的图书馆查询。'};
const plain=v=>typeof v==='string'?v.trim():'';
const csrf=()=>{const row=document.cookie.split(';').map(s=>s.trim()).find(s=>s.startsWith('CSRF-TOKEN='));return row?decodeURIComponent(row.slice('CSRF-TOKEN='.length)):'';};
function date(v){const s=plain(v).slice(0,10);if(!s)return '';if(!/^\d{4}-\d{2}-\d{2}$/.test(s))throw Error();const d=new Date(s+'T00:00:00Z');if(!Number.isFinite(d.getTime())||d.toISOString().slice(0,10)!==s)throw Error();return s;}
async function page(n,size){
 const abort=new AbortController(),timer=setTimeout(()=>abort.abort(),10000);
 try{
  const r=await fetch('/meta-local/opac/users/loans?page='+n+'&pageSize='+size,{credentials:'include',redirect:'error',signal:abort.signal,headers:{'X-Hw-Lang':'i18n.zh-cn','X-CSRF-TOKEN':csrf()}});
  if(!r.ok)throw Error();
  const j=await r.json(),d=j.data;
  if(j.code!==0||!d||!Array.isArray(d.items)||!Number.isInteger(d.total)||d.total<0||d.items.length>size||(d.total>0&&!d.items.length)||d.items.length>d.total)throw Error();
  return d;
 }finally{clearTimeout(timer);}
}
try{
 if(task==='probe'){await page(1,1);return {ok:true,ready:true};}
 const first=await page(1,20),total=first.total;
 if(total>400)throw Error();
 const rows=[...first.items];
 for(let n=2;rows.length<total&&n<=20;n++){
  const next=await page(n,20);if(next.total!==total)throw Error();rows.push(...next.items);
 }
 if(rows.length!==total)throw Error();
 const seen=new Set();
 const books=rows.map(row=>{
  if(row.item?.barCode){if(seen.has(row.item.barCode))throw Error();seen.add(row.item.barCode);}
  const title=plain(row.bibAttrs?.title);if(!title)throw Error();
  return {title,author:plain(row.bibAttrs?.author),loanDate:date(row.loanDate),dueDate:date(row.dueDate),status:plain(row.loanStatus)};
 });
 return {ok:true,books,total};
}catch(_){return {ok:false,error:'图书馆借阅未能完整读取，请在官方页面确认登录后重试。'};}

// Verified portal calendar API. Authentication remains in the portal WebView.
if(location.origin!=='https://i.nuist.edu.cn')return {ok:false,error:'请先连接学校门户。'};
const a=typeof params==='object'&&params?params:{};
const days=['MON','TUE','WED','THU','FRI','SAT','SUN'];
const text=v=>v==null?'':String(v).trim();
function plain(value){const d=new DOMParser().parseFromString(text(value),'text/html');d.querySelectorAll('br').forEach(n=>n.replaceWith('\n'));return d.body.textContent.trim();}
try {
  if(task!=='calendar')throw Error('不支持的校历查询。');
  if(a.year!=null&&(!Number.isInteger(a.year)||a.year<1900||a.year>2200))throw Error('请选择有效学年。');
  const abort=new AbortController(),timer=setTimeout(()=>abort.abort(),15000);
  let p;
  try {
    const r=await fetch('/qljfwapp/sys/lwSchoolCalendar/schoolYearCalendar/getSchoolYearCalendarDetail.do'+(a.year==null?'':'?XN='+a.year),{credentials:'include',redirect:'error',signal:abort.signal});
    if(!r.ok)throw Error('校历查询暂不可用。');
    try{p=await r.json();}catch(_){throw Error('门户未返回校历数据，请确认学校登录状态。');}
  }finally{clearTimeout(timer);}
  if(String(p.code)!=='0'||!/^\d{4}$/.test(text(p.XN)))throw Error('该学年校历未开放或登录已失效，请查看原网页。');
  const year=Number(p.XN);
  if(a.year!=null&&year!==a.year)throw Error('学校未返回所选学年的校历。');
  const events=p.schoolCalendarEvent||{};
  function term(map,remarks){
    if(!map||typeof map!=='object'||Array.isArray(map))throw Error('校历学期数据不完整，请查看原网页。');
    const entries=Object.entries(map).sort(([x],[y])=>Number(x)-Number(y));
    if(!entries.length||entries.length>60)throw Error('该学期尚无有效校历。');
    const weeks=entries.map(([,w])=>({month:text(w.MONTH?.NAME),week:text(w.ZC?.NAME),days:days.map((key,index)=>{
      const d=w[key];if(d==null)return null;
      const code=text(d.CODE);
      if(!/^\d{8}$/.test(code))throw Error('学校日期格式异常。');
      const date=code.slice(0,4)+'-'+code.slice(4,6)+'-'+code.slice(6,8);
      const parsed=new Date(date+'T00:00:00Z');
      if(!Number.isFinite(parsed.getTime())||parsed.toISOString().slice(0,10)!==date||((parsed.getUTCDay()+6)%7)!==index)throw Error('学校日期与星期不一致，请查看原网页。');
      return {date,lunar:text(d.LUNAR_CALENDAR),event:plain(events[code]||'')};
    })}));
    if(weeks.some(w=>!w.week||w.days.every(d=>d===null)))throw Error('学校逐周校历数据不完整。');
    return {weeks,remarks:remarks&&remarks!=='NULL'?plain(remarks):''};
  }
  return {ok:true,year,terms:[term(p.schoolYearData?.firstMap,p.firstTermRemarks),term(p.schoolYearData?.secondMap,p.secondTermRemarks)]};
}catch(e){return {ok:false,error:e?.name==='AbortError'?'校历查询超时，请稍后重试。':e instanceof TypeError?'校历连接失败，请检查网络和登录状态。':e?.message||'校历读取失败。'};}

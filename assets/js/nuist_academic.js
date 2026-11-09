// Read-only NUIST academic APIs, observed on official pages 2026-11-09.
// Runs exclusively inside the teaching WebView; authentication stays there.
if (location.origin !== 'https://jwxt.nuist.edu.cn') return {ok:false,error:'请先连接教务系统。'};
const a = typeof params === 'object' && params ? params : {};
const pick=(r,keys)=>Object.fromEntries(keys.map(k=>[k,r[k] ?? null]));
async function post(path,fields={}) {
  const abort=new AbortController(), timer=setTimeout(()=>abort.abort(),20000);
  try {
    const r=await fetch('/jwapp/'+path,{method:'POST',credentials:'include',redirect:'error',signal:abort.signal,
      headers:{'Content-Type':'application/x-www-form-urlencoded; charset=UTF-8','X-Requested-With':'XMLHttpRequest'},
      body:new URLSearchParams(fields).toString()});
    if(!r.ok) throw Error('学校查询暂不可用，请稍后重试。');
    let p; try { p=await r.json(); } catch (_) {throw Error('教务未返回有效数据，请在原网页确认登录。');}
    if(String(p.code)!=='0'||!p.datas) throw Error('学校未返回有效数据，请在官方页面确认查询权限。');
    return p.datas;
  } finally {clearTimeout(timer);}
}
async function data(path,key,fields={}) {
  const d=(await post(path,fields))[key];
  if(!d||typeof d!=='object')throw Error('学校返回格式已变化，请通过右上角查看原网页。');
  if(d.extParams?.code!=null&&Number(d.extParams.code)!==1)throw Error('学校暂未开放此项查询，请查看原网页。');
  return d;
}
async function rows(path,key,fields={}) {
  const out=[];
  for(let page=1;page<=20;page++){
    const d=await data(path,key,{...fields,pageSize:100,pageNumber:page});
    if(!Array.isArray(d.rows))throw Error('查询数据格式异常。');
    out.push(...d.rows);
    const total=Number(d.totalSize);
    if(Number.isFinite(total)&&total>=0&&out.length>=total)return out;
    if(d.rows.length<100){if(total>out.length)throw Error('分页数据不完整，请重试。');return out;}
  }
  throw Error('数据量超出单次查询范围，请缩小查询条件。');
}
const filter=(name,value,builder='m_value_equal')=>({name,value:String(value),builder,linkOpt:'AND'});
try {
  if(task==='grades') {
    const filters=[filter('SFYX','1'),filter('SHOWMAXCJ','0')];
    const r=await rows('sys/cjcx/modules/cjcx/xscjcx.do','xscjcx',{querySetting:JSON.stringify(filters),'*order':'-XNXQDM,-KCH,-KXH'});
    return {ok:true,rows:r.map(x=>pick(x,['KCM','KCH','ZCJ','XSZCJMC','DJCJMC','XF','XFJD','JDF','XNXQDM','XNXQDM_DISPLAY','SFJG','SFJG_DISPLAY','KCXZDM_DISPLAY','CXCKDM_DISPLAY','SJKSRQ']))};
  }
  if(task==='exams') {
    if(!/^\d{4}-\d{4}-[123]$/.test(a.term||''))throw Error('请选择有效学期。');
    const d=await data('sys/studentWdksapApp/WdksapController/cxxsksap.do','cxxsksap',{requestParamStr:JSON.stringify({XNXQDM:a.term,'*order':'-KSRQ,-KSSJMS'})});
    const r=d.rows;
    if(!Array.isArray(r)||Number(d.totalSize)>r.length)throw Error('考试安排返回不完整，请通过原网页核对。');
    return {ok:true,rows:r.map(x=>pick(x,['KCM','KCH','KSMC','KSRQ','KSSJMS','KSKSSJ','KSJSSJ','JASMC','JXLMC','XXXQMC','ZWH','BZ','SFAPSJ_DISPLAY','SFXYAPKS_DISPLAY']))};
  }
  if(task==='creditPlans') {
    const d=await data('sys/byshapp/api/grbg/queryXsjbxx.do','queryXsjbxx');
    if(!Array.isArray(d.faArr))throw Error('尚无培养方案，请查看原网页。');
    return {ok:true,plans:d.faArr.map(x=>({value:x.value,label:x.label}))};
  }
  if(task==='credits') {
    if(!/^[a-zA-Z0-9_-]{1,100}$/.test(a.plan||''))throw Error('请选择有效培养方案。');
    const d=await data('sys/byshapp/api/grbg/queryXyzhbx.do','queryXyzhbx',{PYFADM:a.plan,SCLX:'04'});
    if(!d.fanbx||typeof d.fanbx!=='object')throw Error('学校尚未生成学分报告，请在原网页生成后重试。');
    function node(x,depth=0){return {...pick(x,['name','creditsRequired','creditsEarned','creditsTaken','creditsSelection']),children:depth<8?(x.children||[]).map(y=>node(y,depth+1)):[]};}
    const r=await rows('sys/byshapp/modules/grbg/cxxsxqxf.do','cxxsxqxf',{PYFADM:a.plan});
    return {ok:true,report:node(d.fanbx),calculatedTime:d.calculatedTime,completed:d.educationalProgramCompletedCredits,outside:d.outEducationalProgramCompletedCredits,
      rows:r.map(x=>pick(x,['XNXQDM','XNXQDM_DISPLAY','YXXF','YHXF','BJGXF','WLCJXF','XQGPA','LJGPA']))};
  }
  if(task==='roomsOptions') {
    const buildings=await rows('sys/kxjas/modules/kxjas/jxlcx.do','jxlcx',{'*order':'+XXXQDM,+PX,+JXLDM'});
    return {ok:true,buildings:buildings.map(x=>pick(x,['JXLDM','JXLMC','XXXQDM_DISPLAY']))};
  }
  if(task==='rooms') {
    const date=a.date;
    if(!/^\d{4}-\d{2}-\d{2}$/.test(date||'')||!Number.isFinite(Date.parse(date))||new Date(date).toISOString().slice(0,10)!==date)throw Error('请选择有效日期。');
    const buildings=await rows('sys/kxjas/modules/kxjas/jxlcx.do','jxlcx',{'*order':'+XXXQDM,+PX,+JXLDM'});
    if(!buildings.some(x=>x.JXLDM===a.building))throw Error('请从学校教学楼清单中选择教学楼。');
    const terms=await rows('sys/kxjas/modules/kxjas/gjrqcxdyxnxq.do','gjrqcxdyxnxq',{KSRQ:date,JSRQ:date});
    const term=terms[0]?.XQ;
    if(!/^\d{4}-\d{4}-[123]$/.test(term||''))throw Error('该日期尚无学校校历，请更换日期或查看原网页。');
    const parts=term.split('-');
    const calendar=await data('sys/kxjas/modules/kxjas/rqzhzcjc.do','rqzhzcjc',{RQ:date,XN:parts.slice(0,2).join('-'),XQ:parts[2]});
    if(!Number.isInteger(Number(calendar.ZC))||Number(calendar.ZC)<1||Number(calendar.XQJ)<1||Number(calendar.XQJ)>7)throw Error('该日期的学校周次信息尚未配置。');
    const groups=await rows('sys/kxjas/modules/kxjas/cxjcqk.do','cxjcqk',{XNXQDM:term});
    if(!groups.length||groups.some(x=>!Number.isInteger(Number(x.KSJC))||!Number.isInteger(Number(x.JSJC))||Number(x.KSJC)<1||Number(x.JSJC)<Number(x.KSJC)||Number(x.JSJC)>30))throw Error('学校全天节次信息不完整。');
    const slots=groups.map(x=>({start:Number(x.KSJC),end:Number(x.JSJC),label:x.DJMC,from:x.KSSJ,to:x.JSSJ})).sort((x,y)=>x.start-y.start);
    const maxPeriod=Math.max(...slots.map(x=>x.end));
    const q=[filter('JXLDM',a.building,'equal')];
    const rooms=await rows('sys/kxjas/modules/kxjas/cxjsqk.do','cxjsqk',{XNXQDM:term,ZC:calendar.ZC,XQ:calendar.XQJ,RQ:date,querySetting:JSON.stringify(q),'*order':'+LC,+JASMC'});
    function period(value,index,present) {
      // Official renderer treats explicit null/empty JC cells as no occupancy.
      if(present && (value===null || value===''))return {period:index,state:'free',types:[]};
      const codes=typeof value==='string'?value.split(','):[];
      const valid=present&&codes.length>0&&codes.every(x=>/^[01]_[a-zA-Z0-9]+$/.test(x));
      const types=codes.filter(x=>x.startsWith('1_')).map(x=>x.slice(2));
      return {period:index,state:!valid?'unknown':types.length?'busy':'free',types};
    }
    return {ok:true,date,term,slots,rows:rooms.map(x=>({id:x.JASDM,name:x.JASMC,type:x.JASLXDM_DISPLAY,seats:x.SKZWS,floor:x.LC,
      periods:Array.from({length:maxPeriod},(_,i)=>period(x['JC'+(i+1)],i+1,Object.prototype.hasOwnProperty.call(x,'JC'+(i+1))))}))};
  }
  throw Error('未知的教务查询。');
} catch(e) {return {ok:false,error:e?.name==='AbortError'?'查询超时，请重试。':e instanceof TypeError?'教务会话失效或网络不可用，请通过右上角进入官方页面。':e?.message||'查询失败，请稍后重试。'};}

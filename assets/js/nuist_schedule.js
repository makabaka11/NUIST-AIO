// NUIST JSON API adapter. Interface research informed by ShiGuangSchedule's
// MIT-licensed NUIST adapter; attribution in assets/licenses/shiguang.txt.
// Executed as a callAsyncJavaScript function body within jwxt.nuist.edu.cn.
if (location.origin !== 'https://jwxt.nuist.edu.cn') {
  return {ok:false, error:'请先完成教务系统登录，再获取课表。'};
}
const base = '/jwapp/sys/wdkb/';
async function table(path, key, fields = {}) {
  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), 20000);
  try {
    const response = await fetch(base + path + '.do', {
      method: 'POST', credentials: 'include', signal: abort.signal,
      headers: {'Content-Type':'application/x-www-form-urlencoded; charset=UTF-8', 'X-Requested-With':'XMLHttpRequest'},
      body: new URLSearchParams(fields).toString()
    });
    if (!response.ok) throw new Error('教务接口暂时无法响应，请稍后重试。');
    if (new URL(response.url).origin !== location.origin) throw new Error('登录已过期，请重新登录教务系统。');
    let payload;
    try { payload = await response.json(); } catch (_) { throw new Error('未收到课表数据，请先完成教务系统登录。'); }
    const result = payload && payload.datas && payload.datas[key];
    if (!result || !Array.isArray(result.rows)) throw new Error('教务数据格式异常，请重新登录后重试。');
    if (result.extParams && result.extParams.code != null && Number(result.extParams.code) !== 1) {
      throw new Error('教务系统未能返回此学期数据，请稍后重试或更换学期。');
    }
    return result;
  } finally { clearTimeout(timer); }
}
async function allRows(path, key, fields) {
  const output = [];
  for (let page=1;page<=20;page++) {
    const result = await table(path,key,{...fields,pageNumber:String(page),pageSize:'500'});
    output.push(...result.rows);
    const total=Number(result.totalSize);
    if (Number.isFinite(total) && total>=0 && output.length>=total) return output;
    if (result.rows.length<500) {
      if (total>output.length) throw new Error('课表分页返回不完整，请稍后重试。');
      return output;
    }
  }
  throw new Error('课表数据超出本次获取范围，请联系开发者。');
}
try {
  if (task === 'semesters') {
    const current=await table('modules/jshkcb/dqxnxq','dqxnxq');
    let terms=current.rows;
    try { terms=(await table('modules/jshkcb/xnxqcx','xnxqcx',{'*order':'-DM'})).rows; } catch (_) {}
    return {ok:true,current:current.rows[0]?.DM,terms:terms.map(r=>({DM:r.DM,MC:r.MC}))};
  }
  if (task !== 'schedule' || !/^\d{4}-\d{4}-[123]$/.test(term)) throw new Error('请选择有效学期。');
  const warnings=[];
  const rows=await allRows('modules/xskcb/cxxszhxqkb','cxxszhxqkb',{XNXQDM:term});
  let slots=[],config={},unscheduled=[];
  try { slots=(await table('modules/jshkcb/jc','jc')).rows; }
  catch (_) { warnings.push('作息接口暂不可用。'); }
  const parts=term.split('-');
  try { config=(await table('modules/jshkcb/cxjcs','cxjcs',{XN:parts.slice(0,2).join('-'),XQ:parts[2]})).rows[0] || {}; }
  catch (_) { warnings.push('学期配置接口暂不可用。'); }
  try { unscheduled=await allRows('modules/xskcb/xswpkc','xswpkc',{XNXQDM:term}); }
  catch (_) { warnings.push('未排课课程暂未获取，请稍后重新同步。'); }
  // Keep only display fields; no student IDs, names or authentication values.
  const keep=(r)=>({KCM:r.KCM,SKJS:r.SKJS,JASMC:r.JASMC,XXXQDM_DISPLAY:r.XXXQDM_DISPLAY,
    SKXQ:r.SKXQ,KSJC:r.KSJC,JSJC:r.JSJC,SKZC:r.SKZC});
  return {ok:true,data:{term,termName,rows:rows.map(keep),
    slots:slots.map(r=>({DM:r.DM,KSSJ:r.KSSJ,JSSJ:r.JSSJ})),
    config:{XQKSRQ:config.XQKSRQ,ZZC:config.ZZC},
    unscheduled:unscheduled.map(r=>({KCM:r.KCM,SKJS:r.SKJS})),warnings}};
} catch (error) {
  return {ok:false,error:error?.name==='AbortError'?'请求超时，请检查校园网络后重试。':(error?.message || '课表获取失败，请稍后重试。')};
}

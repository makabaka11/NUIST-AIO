// Read-only NUIST card/electricity adapter. Tokens remain in the school page.
if (location.origin !== 'https://icard.nuist.edu.cn') return {ok:false,error:'请先进入学校一卡通页面。'};
let token=sessionStorage.getItem('access_token');
if(task==='probe') {
  if(!token) return {ok:true,ready:false};
  const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),10000);
  try {
    const response=await fetch('/berserker-base/user', {credentials:'include',
      headers:{'synjones-auth':token,synAccessSource:'pc'},signal:controller.signal});
    if(!response.ok||new URL(response.url).origin!==location.origin)return {ok:true,ready:false};
    const data=await response.json();
    return {ok:true,ready:Number(data.code)===200&&data.success!==false};
  }catch(_){return {ok:true,ready:false};}finally{clearTimeout(timer);}
}
if(!token) return {ok:false,error:'一卡通登录已过期，请重新连接。'};
const allowedGet=new Set([
 '/berserker-app/ykt/tsm/getCampusCards','/berserker-app/ykt/tsm/queryCard',
 '/berserker-search/search/personal/turnover','/berserker-search/statistics/turnover/count'
]);
async function request(path,params={},post=false){
 if(post?path!=='/charge/feeitem/getThirdData':!allowedGet.has(path))throw new Error('不支持的查询。');
 const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),18000);
 try{
  const headers={'synjones-auth':token,'synAccessSource':'pc'};
  let url=path,options={method:post?'POST':'GET',credentials:'include',headers,signal:controller.signal};
  if(post){headers['Content-Type']='application/x-www-form-urlencoded';options.body=new URLSearchParams(params).toString();}
  else url+='?'+new URLSearchParams({...params,synAccessSource:'pc'}).toString();
  const response=await fetch(url,options);
  if(!response.ok)throw new Error('校园服务暂时不可用，请稍后重试。');
  if(new URL(response.url).origin!==location.origin)throw new Error('登录已过期，请重新连接。');
  let data;try{data=await response.json();}catch(_){throw new Error('未收到有效数据，请重新连接一卡通。');}
  if(Number(data.code)!==200||data.success===false)throw new Error('学校服务未能返回查询结果，请重新连接或稍后重试。');
  return data;
 }finally{clearTimeout(timer);}
}
function cents(value){const n=Number(value);if(!['number','string'].includes(typeof value)||(typeof value==='string'&&value.trim()==='')||!Number.isSafeInteger(n))throw new Error('金额格式异常，未覆盖上次数据。');return n;}
function now(){return new Date().toISOString();}
async function wallet(){
 const list=await request('/berserker-app/ykt/tsm/getCampusCards');
 if(String(list.data?.retcode)!=='0'||!Array.isArray(list.data.card))throw new Error('未能读取卡账户。');
 const cards=[],seenAccounts=new Set();
 for(const initial of list.data.card){
  if(initial.account===null||initial.account===undefined||String(initial.account)==='')throw new Error('卡账户信息不完整。');
  if(seenAccounts.has(String(initial.account)))continue;
  const result=await request('/berserker-app/ykt/tsm/queryCard',{account:String(initial.account)});
  if(String(result.data?.retcode)!=='0'||!Array.isArray(result.data.card)||!result.data.card.length)throw new Error('未能读取最新余额。');
  for(const card of result.data.card) {
   const accountKey=String(card.account??initial.account);if(seenAccounts.has(accountKey))continue;seenAccounts.add(accountKey);
   cards.push({label:String(card.card_name||card.cardname||'校园卡'),
   electronicCents:cents(card.elec_accamt),physicalCents:cents(cents(card.db_balance)+cents(card.unsettle_amount)),
   lost:Number(card.lostflag)!==0,frozen:Number(card.freezeflag)!==0});
  }
 }
 return {cards,updatedAt:now()};
}
async function bills(){
 if(!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)||!Number.isInteger(page)||page<1||page>10000)throw new Error('请选择有效账单月份与页码。');
 const [year,m]=month.split('-').map(Number);
 const chinaToday=new Date(Date.now()+8*3600000).toISOString().slice(0,10);
 const last=new Date(Date.UTC(year,m,0)).toISOString().slice(0,10);
 const timeTo=last>chinaToday?chinaToday:last;
 const timeFrom=month+'-01';if(timeFrom>timeTo)throw new Error('暂不支持未来月份。');
 const params={timeFrom,timeTo};
 const summary=await request('/berserker-search/statistics/turnover/count',params);
 const result=await request('/berserker-search/search/personal/turnover',{...params,size:'20',current:String(page)});
 if(!Array.isArray(result.data?.records)||!Number.isSafeInteger(Number(result.data.total))||Number(result.data.total)<0)throw new Error('账单分页格式异常。');
 if(result.data.current!=null&&Number(result.data.current)!==page)throw new Error('账单页码未匹配，请重试。');
 const actualSize=result.data.size==null?20:Number(result.data.size);
 if(!Number.isSafeInteger(actualSize)||actualSize<1)throw new Error('账单分页格式异常。');
 const records=result.data.records.map(r=>({description:String(r.resume||r.turnoverType||'校园卡交易'),
  amountCents:Math.abs(cents(r.tranamt)),income:String(r.typeFrom)==='1',
  directionKnown:['1','2'].includes(String(r.typeFrom)),time:String(r.effectdateStr||r.jndatetimeStr||''),
  method:String(r.payName||r.consumeTypeName||'')}));
 return {month,page,total:Number(result.data.total),size:actualSize,incomeCents:cents(summary.data?.income),
  expensesCents:cents(summary.data?.expenses),records,updatedAt:now()};
}
async function electricity(){
 if(!dorm||!['448','568','429'].includes(dorm.serviceId))throw new Error('请先选择实际宿舍。');
 const codes=dorm.serviceId==='568'?['building_id','room_id']:['xiaoqu_id','loudong_id','room_id'];
 if(!dorm.fields||Object.keys(dorm.fields).length!==codes.length||codes.some(k=>typeof dorm.fields[k]!=='string'||!dorm.fields[k]))throw new Error('宿舍信息不完整，请重新选择。');
 const result=await request('/charge/feeitem/getThirdData',{...dorm.fields,type:'IEC',level:String(codes.length),feeitemid:dorm.serviceId},true);
 const raw=result.map?.showData;
 if(!raw||typeof raw!=='object'||Array.isArray(raw))throw new Error('该宿舍暂未返回电量，请检查宿舍选择或稍后重试。');
 const fields=Object.fromEntries(Object.entries(raw).filter(([k,v])=>/电量|电费|余额|剩余|状态|用电/.test(k)&&['string','number'].includes(typeof v)).map(([k,v])=>[k,String(v)]));
 if(!Object.keys(fields).length)throw new Error('学校返回的电费字段尚不支持，请稍后重试。');
 return {dormKey:dorm.key,fields,updatedAt:now()};
}
try{
 if(task==='wallet')return {ok:true,wallet:await wallet()};
 if(task==='bills')return {ok:true,bills:await bills()};
 if(task==='electricity')return {ok:true,electricity:await electricity()};
 if(task!=='sync')throw new Error('不支持的查询。');
 const output={ok:true,errors:[]};
 for(const [name,fn] of [['wallet',wallet],['bills',bills],...(dorm?[['electricity',electricity]]:[])]){
  try{output[name]=await fn();}catch(e){output.errors.push({part:name,message:e?.name==='AbortError'?'查询超时，请重试。':'查询未完成，请检查登录、网络或宿舍信息后重试。'});}
 }
 return output;
}catch(e){return {ok:false,error:e?.name==='AbortError'?'查询超时，请检查网络后重试。':e?.message||'查询失败，请稍后重试。'};}

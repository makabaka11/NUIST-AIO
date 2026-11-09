import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import vm from 'node:vm';
const source=readFileSync(new URL('../assets/js/nuist_accounts.js',import.meta.url),'utf8');
const token='TEST-SESSION-TOKEN-NOT-EXPORT';
const dorm={serviceId:'448',fields:{xiaoqu_id:'area&示例园',loudong_id:'building&示例楼',room_id:'room&示例房'},key:'example'};
const defaultData=(path)=>{
 if(path.endsWith('getCampusCards'))return {data:{retcode:'0',card:[{account:'PRIVATE-CARD-ID'}]}};
 if(path.endsWith('queryCard'))return {data:{retcode:'0',card:[{name:'PRIVATE-NAME',sno:'PRIVATE-SNO',account:'PRIVATE-CARD-ID',
  cardname:'示例校园卡',elec_accamt:1234,db_balance:250,unsettle_amount:1,lostflag:0,freezeflag:0}]}};
 if(path.endsWith('/count'))return {data:{income:10000,expenses:2468}};
 if(path.endsWith('/turnover'))return {data:{total:41,records:[
  {resume:'示例消费',tranamt:1234,typeFrom:'2',typeId:'4',effectdateStr:'2026-11-01 08:00:00',payName:'示例支付',sno:'PRIVATE-SNO'},
  {resume:'示例收入',tranamt:10000,typeFrom:'1',typeId:'2'},
  {resume:'未知方向',tranamt:123,typeFrom:'unknown'},
 ]}};
 if(path.endsWith('getThirdData'))return {map:{showData:{剩余电量:'123.456789',剩余金额:'12.34'},data:{private:'PRIVATE-ROOM-DATA'}}};
 throw new Error('unexpected endpoint');
};
async function run(task,{override,month='2026-11',page=1,selected=dorm,noToken=false,origin='https://icard.nuist.edu.cn'}={}){
 const calls=[];
 const context=vm.createContext({URL,URLSearchParams,Date,AbortController,setTimeout,clearTimeout,task,month,page,dorm:selected,
  location:{origin},sessionStorage:{getItem:()=>noToken?null:token},
  fetch:async(url,options)=>{
   assert.equal(options.credentials,'include');assert.equal(options.headers['synjones-auth'],token);
   const parsed=new URL(url,'https://icard.nuist.edu.cn');
   const params=Object.fromEntries(options.method==='POST'?new URLSearchParams(options.body):parsed.searchParams);
   calls.push({path:parsed.pathname,method:options.method,params});
   const special=override?.(parsed.pathname,params);
   if(special instanceof Error)throw special;
   if(special?.response)return special.response;
   return {ok:true,url:parsed.href,json:async()=>({code:200,success:true,...(special??defaultData(parsed.pathname))})};
  }});
 const value=JSON.parse(JSON.stringify(await vm.runInContext(`(async()=>{${source}\n})()`,context)));
 return {value,calls};
}
test('wallet keeps integer cents and never exports session/identity/card IDs',async()=>{
 const {value}=await run('wallet');assert.equal(value.ok,true);
 assert.equal(value.wallet.cards[0].electronicCents,1234);assert.equal(value.wallet.cards[0].physicalCents,251);
 for(const privateValue of [token,'PRIVATE-NAME','PRIVATE-SNO','PRIVATE-CARD-ID'])assert.equal(JSON.stringify(value).includes(privateValue),false);
});
test('monthly expense is server total and direction uses typeFrom rather than amount sign or category',async()=>{
 const {value,calls}=await run('bills',{page:2});
 assert.equal(value.bills.expensesCents,2468);assert.equal(value.bills.records[0].income,false);
 assert.equal(value.bills.records[1].income,true);assert.equal(value.bills.records[2].directionKnown,false);
 const request=calls.find(c=>c.path.endsWith('/turnover'));
 assert.equal(request.params.current,'2');assert.equal(request.params.size,'20');assert.equal(request.params.timeFrom,'2026-11-01');
 assert.equal(JSON.stringify(value).includes('PRIVATE-SNO'),false);
});
test('closed historical month uses its actual last day',async()=>{
 const {calls}=await run('bills',{month:'2024-02'});assert.equal(calls[0].params.timeTo,'2024-02-29');
});
test('electricity is IEC read only, includes exact compound room IDs, and strips private payload',async()=>{
 const {value,calls}=await run('electricity');assert.equal(value.electricity.fields['剩余电量'],'123.456789');
 assert.equal(value.electricity.dormKey,'example');assert.equal(calls.length,1);assert.equal(calls[0].path,'/charge/feeitem/getThirdData');
 assert.equal(calls[0].params.type,'IEC');assert.equal(calls[0].params.level,'3');assert.equal(calls[0].params.room_id,'room&示例房');
 assert.equal('tranamt' in calls[0].params,false);assert.equal(JSON.stringify(value).includes('PRIVATE-ROOM-DATA'),false);
});
test('Qin 42/43 uses the two-level building_id schema',async()=>{
 const {calls}=await run('electricity',{selected:{serviceId:'568',fields:{building_id:'b',room_id:'r'},key:'q'}});
 assert.equal(calls[0].params.level,'2');assert.equal(calls[0].params.feeitemid,'568');assert.equal(calls[0].params.building_id,'b');
});
test('invalid dorm configuration or arbitrary task cannot trigger payment requests',async()=>{
 for(const task of ['pay','bind','electricity']){
  const {value,calls}=await run(task,{selected:{serviceId:'448',fields:{type:'pay'},key:'bad'}});
  assert.equal(value.ok,false);assert.equal(calls.length,0);
 }
});
test('sync supports partial failure without inventing balances',async()=>{
 const {value}=await run('sync',{override:path=>path.endsWith('queryCard')?new Error('offline'):null});
 assert.equal(value.ok,true);assert.equal(value.wallet,undefined);assert.ok(value.bills);assert.ok(value.electricity);
 assert.equal(value.errors[0].part,'wallet');
});
test('missing session or wrong origin never sends API requests',async()=>{
 for(const options of [{noToken:true},{origin:'https://other.example'}]){
  const {value,calls}=await run('wallet',options);assert.equal(value.ok,false);assert.equal(calls.length,0);
 }
});
test('business errors, malformed cents, HTML, and empty power data are failures',async()=>{
 for(const override of [()=>({code:401,success:false}),()=>({response:{ok:true,url:'https://icard.nuist.edu.cn/',json:async()=>{throw new SyntaxError('HTML');}}}),
  path=>path.endsWith('queryCard')?{data:{retcode:'0',card:[{elec_accamt:'12.34',db_balance:0,unsettle_amount:0}]}}:null]){
  const {value}=await run('wallet',{override});assert.equal(value.ok,false);
 }
 const {value}=await run('electricity',{override:()=>({map:{showData:{}}})});assert.equal(value.ok,false);
});
test('readiness verifies the business token with the school, without exporting identity',async()=>{
 const {value,calls}=await run('probe',{override:path=>path==='/berserker-base/user'?{data:{name:'PRIVATE-NAME',sno:'PRIVATE-SNO'}}:null});
 assert.deepEqual(value,{ok:true,ready:true});assert.equal(calls.length,1);assert.equal(calls[0].path,'/berserker-base/user');
 for(const options of [{noToken:true},{override:()=>({code:401,success:false})},{override:()=>new Error('offline')}]){
  assert.deepEqual((await run('probe',options)).value,{ok:true,ready:false});
 }
});

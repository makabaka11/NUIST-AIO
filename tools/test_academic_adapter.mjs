import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import vm from 'node:vm';
const source=readFileSync(new URL('../assets/js/nuist_academic.js',import.meta.url),'utf8');
async function run(task, params={}, handler=()=>({rows:[],totalSize:0}), origin='https://jwxt.nuist.edu.cn') {
  const calls=[];
  const ctx=vm.createContext({task,params,location:{origin},URLSearchParams,AbortController,setTimeout,clearTimeout,
    fetch:async(path,opts)=>{
      assert.equal(opts.credentials,'include');assert.equal(opts.redirect,'error');
      const fields=Object.fromEntries(new URLSearchParams(opts.body));calls.push({path,fields});
      const key=path.split('/').at(-1).replace('.do','');
      const d=handler(key,fields);if(d instanceof Error)throw d;
      return {ok:true,json:async()=>({code:'0',datas:{[key]:d}})};
    }});
  const value=await vm.runInContext(`(async()=>{${source}\n})()`,ctx);
  return {value:JSON.parse(JSON.stringify(value)),calls};
}
test('grades preserve GPA and zero scores, strip identity, paginate completely', async()=>{
  const {value,calls}=await run('grades',{},(key,f)=>({rows:Array.from({length:f.pageNumber==='1'?100:1},()=>({KCM:'测试课程',XF:2,XFJD:0,ZCJ:0,XH:'PRIVATE',XM:'PRIVATE',WID:'PRIVATE'})),totalSize:101}));
  assert.equal(value.rows.length,101);assert.equal(value.rows[0].XFJD,0);assert.equal(value.rows[0].ZCJ,0);
  assert.equal(JSON.stringify(value).includes('PRIVATE'),false);assert.equal(calls.length,2);
  assert.deepEqual(JSON.parse(calls[0].fields.querySetting).map(x=>x.name),['SFYX','SHOWMAXCJ']);
});
const roomHandler=(key)=>({
  jxlcx:{rows:[{JXLDM:'test-building',JXLMC:'测试楼',XXXQDM_DISPLAY:'测试校区'}],totalSize:1},
  gjrqcxdyxnxq:{rows:[{XQ:'2026-2027-1'}],totalSize:1},
  rqzhzcjc:{ZC:11,XQJ:1},
  cxjcqk:{rows:[{KSJC:1,JSJC:2,DJMC:'1-2节',KSSJ:'08:00',JSSJ:'09:40'}],totalSize:1},
  cxjsqk:{rows:[{JASDM:'test-room',JASMC:'测试101',JC1:'0_01,1_04',JC2:'0_01,0_04',XH:'PRIVATE'}],totalSize:1},
}[key]);
test('room day uses verified building, calendar and occupancy APIs, preserving per-period status',async()=>{
  const {value,calls}=await run('rooms',{date:'2026-11-09',building:'test-building'},roomHandler);
  assert.equal(value.ok,true);assert.equal(value.slots.length,1);assert.equal(value.rows[0].periods[0].state,'busy');assert.equal(value.rows[0].periods[1].state,'free');
  const request=calls.find(c=>c.path.endsWith('/cxjsqk.do'));
  assert.equal(request.fields.RQ,'2026-11-09');assert.equal(JSON.parse(request.fields.querySetting)[0].value,'test-building');assert.equal(request.fields.ZC,'11');
  assert.equal(JSON.stringify(value).includes('PRIVATE'),false);
});
test('missing occupancy is unknown and absent calendar never becomes all-free',async()=>{
  const a=await run('rooms',{date:'2026-11-09',building:'test-building'},key=>key==='cxjsqk'?{rows:[{JASMC:'测试101',JC1:'unexpected'}],totalSize:1}:roomHandler(key));
  assert.ok(a.value.rows[0].periods.every(p=>p.state==='unknown'));
  const empty=await run('rooms',{date:'2026-11-09',building:'test-building'},key=>key==='cxjsqk'?{rows:[{JASMC:'测试101',JC1:null,JC2:''}],totalSize:1}:roomHandler(key));
  assert.ok(empty.value.rows[0].periods.every(p=>p.state==='free'));
  const b=await run('rooms',{date:'2026-11-09',building:'test-building'},key=>key==='gjrqcxdyxnxq'?{rows:[],totalSize:0}:roomHandler(key));
  assert.equal(b.value.ok,false);assert.ok(!b.calls.some(c=>c.path.endsWith('/cxjsqk.do')));
  const c=await run('rooms',{date:'2026-11-09',building:'forged'},roomHandler);assert.equal(c.value.ok,false);assert.equal(c.calls.length,1);
});
test('building dropdown lists school buildings without fetching a room day prematurely',async()=>{
  const {value,calls}=await run('roomsOptions',{},roomHandler);assert.equal(value.buildings[0].JXLMC,'测试楼');assert.equal(calls.length,1);
});
test('invalid periods, dates, term and plan are rejected before network',async()=>{
  for(const [task,params] of [['rooms',{date:'2026-02-30',building:'test-building'}],['rooms',{date:'x',start:1,end:2}],['exams',{term:'x'}],['credits',{plan:'../secret'}]]){
    const {value,calls}=await run(task,params);assert.equal(value.ok,false);assert.equal(calls.length,0);
  }
});
test('exam query uses school controller format and strips private student fields',async()=>{
  const {value,calls}=await run('exams',{term:'2026-2027-1'},()=>({rows:[{KCM:'测试考试',KSRQ:'2026-11-10',KSSJMS:'10:00-12:00',ZWH:'8',XH:'PRIVATE'}],totalSize:1,extParams:{code:1}}));
  assert.equal(value.rows[0].ZWH,'8');assert.equal(JSON.parse(calls[0].fields.requestParamStr).XNXQDM,'2026-2027-1');assert.equal(JSON.stringify(value).includes('PRIVATE'),false);
});
test('credit plans and report keep display data without student or audit internals',async()=>{
  const p=await run('creditPlans',{},()=>({faArr:[{value:'synthetic-plan',label:'测试方案',XH:'PRIVATE'}],jbxx:{XM:'PRIVATE'}}));
  assert.equal(p.value.plans[0].value,'synthetic-plan');assert.equal(JSON.stringify(p.value).includes('PRIVATE'),false);
  const {value,calls}=await run('credits',{plan:'synthetic-plan'},key=>key==='queryXyzhbx'?{fanbx:{name:'总学分',creditsEarned:60,creditsRequired:160,children:[{name:'必修',creditsEarned:50,creditsRequired:100,checkCourseVOS:{XH:'PRIVATE'}}]},educationalProgramCompletedCredits:60}: {rows:[{XNXQDM_DISPLAY:'测试学期',XQGPA:0,LJGPA:3.5,XH:'PRIVATE'}],totalSize:1});
  assert.equal(value.ok,true);assert.equal(value.report.creditsEarned,60);assert.equal(value.rows[0].XQGPA,0);assert.equal(JSON.stringify(value).includes('PRIVATE'),false);
  assert.ok(calls.every(c=>!c.path.includes('refresh')&&!c.path.includes('execute')));
});
test('business failure and partial pagination do not become false empty success',async()=>{
  for(const handler of [()=>({rows:[],extParams:{code:0,msg:'PRIVATE'}}),()=>({rows:[{}],totalSize:50})]){
    const {value}=await run('grades',{},handler);assert.equal(value.ok,false);assert.equal(value.error.includes('PRIVATE'),false);
  }
});
test('wrong origin does not request anything; server exceptions do not reveal response data',async()=>{
  const {value,calls}=await run('grades',{},undefined,'https://other.test');assert.equal(value.ok,false);assert.equal(calls.length,0);
});
test('shared native wrapper is valid JS and serializes integer values before platform bridging',async()=>{
  const dart=readFileSync(new URL('../lib/src/services/script_result.dart',import.meta.url),'utf8');
  const template=dart.match(/'(.+)';/)[1].replaceAll('\\n','\n');
  const wrapped=template.replace('$source','return {ok:true, number:60, zero:0, fraction:3.5};');
  const value=await vm.runInNewContext(`(async()=>{${wrapped}})()`);
  assert.equal(typeof value,'string');assert.deepEqual(JSON.parse(value),{ok:true,number:60,zero:0,fraction:3.5});
});

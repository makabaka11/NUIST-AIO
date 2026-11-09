import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import vm from 'node:vm';

const source=readFileSync(new URL('../assets/js/nuist_schedule.js',import.meta.url),'utf8');
async function run(task='schedule', handler) {
  const calls=[];
  const context=vm.createContext({location:{origin:'https://jwxt.nuist.edu.cn'},URL,URLSearchParams,
    AbortController,setTimeout,clearTimeout,task,term:'2026-2027-1',termName:'测试学期',
    fetch:async(path,options)=>{
      assert.equal(options.credentials,'include');
      const fields=Object.fromEntries(new URLSearchParams(options.body));
      calls.push({path,fields});
      const key=path.split('/').at(-1).replace('.do','');
      const special=handler?.(key,fields);
      if(special instanceof Error) throw special;
      if(special?.response) return special.response;
      const table=special??{rows:[],totalSize:0,extParams:{code:1}};
      return {ok:true,url:'https://jwxt.nuist.edu.cn'+path,json:async()=>({code:'0',datas:{[key]:table}})};
    }});
  const value=await vm.runInContext(`(async()=>{${source}\n})()`,context);
  return {value:JSON.parse(JSON.stringify(value)),calls};
}

test('paginates, strips personal fields, preserves all records and metadata',async()=>{
  const {value,calls}=await run('schedule',(key,fields)=>{
    if(key==='cxxszhxqkb') {
      const page=Number(fields.pageNumber),length=page===1?500:2;
      return {totalSize:502,extParams:{code:1},rows:Array.from({length},(_,i)=>({
        KCM:`课程${i}`,SKJS:'教师甲、教师乙',SKXQ:1,KSJC:'1',JSJC:'2',SKZC:'101',
        XH:'DO-NOT-EXPORT',XM:'DO-NOT-EXPORT',WID:'DO-NOT-EXPORT'}))};
    }
    if(key==='cxjcs') return {rows:[{XQKSRQ:'2026-08-31 00:00:00',ZZC:20}]};
    if(key==='jc') return {rows:[{DM:1,KSSJ:'08:00',JSSJ:'08:45'}]};
  });
  assert.equal(value.ok,true);assert.equal(value.data.rows.length,502);
  assert.equal(calls.filter(c=>c.path.includes('cxxszhxqkb')).length,2);
  assert.equal(JSON.stringify(value).includes('DO-NOT-EXPORT'),false);
  assert.equal(value.data.rows[0].SKJS,'教师甲、教师乙');
  assert.equal(value.data.config.XQKSRQ,'2026-08-31 00:00:00');
});
test('partial pagination is rejected instead of silently losing courses',async()=>{
  const {value}=await run('schedule',key=>key==='cxxszhxqkb'?{totalSize:99,rows:[{KCM:'x'}]}:null);
  assert.equal(value.ok,false);assert.match(value.error,/分页/);
});
test('business errors are rejected even on HTTP 200',async()=>{
  const {value}=await run('schedule',()=>({rows:[],extParams:{code:0,msg:'internal details'}}));
  assert.equal(value.ok,false);assert.equal(value.error.includes('internal details'),false);
});
test('HTML login pages and cross-origin redirects are login failures',async()=>{
  for(const response of [{ok:true,url:'https://authserver.nuist.edu.cn/authserver/login'},
    {ok:true,url:'https://jwxt.nuist.edu.cn/',json:async()=>{throw new SyntaxError('HTML');}}]) {
    const {value}=await run('schedule',()=>({response}));
    assert.equal(value.ok,false);assert.match(value.error,/登录/);
  }
});
test('optional APIs fail with warnings while real empty course lists remain valid',async()=>{
  const {value}=await run('schedule',key=>key==='cxxszhxqkb'?{rows:[],totalSize:0}:new Error('offline'));
  assert.equal(value.ok,true);assert.equal(value.data.rows.length,0);
  assert.equal(value.data.warnings.length,3);
});
test('semester list falls back to current semester and requests are read-only queries',async()=>{
  const {value,calls}=await run('semesters',key=>key==='dqxnxq'?
    {rows:[{DM:'2026-2027-1',MC:'当前学期'}]}:new Error('unavailable'));
  assert.equal(value.ok,true);assert.equal(value.terms[0].DM,'2026-2027-1');
  assert.ok(calls.every(c=>c.path.startsWith('/jwapp/sys/wdkb/modules/jshkcb/')));
});
test('timeout provides an actionable error',async()=>{
  const e=new Error('aborted');e.name='AbortError';
  const {value}=await run('schedule',()=>e);
  assert.equal(value.ok,false);assert.match(value.error,/超时/);
});

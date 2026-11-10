import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import vm from 'node:vm';
const source=readFileSync(new URL('../assets/js/nuist_calendar.js',import.meta.url),'utf8');
function week(date,label){
 const out={MONTH:{NAME:'8月'},ZC:{NAME:label}};
 for(const [i,key] of ['MON','TUE','WED','THU','FRI','SAT','SUN'].entries()){
  const d=new Date(date+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+i);
  out[key]={CODE:d.toISOString().slice(0,10).replaceAll('-',''),NAME:'日期',LUNAR_CALENDAR:'农历',PRIVATE:'SECRET'};
 }
 return out;
}
const fixture=()=>({code:'0',XN:'2026',schoolYearData:{firstMap:{2:week('2027-01-18','寒假'),1:week('2026-08-31',1)},secondMap:{1:week('2027-02-22',1)}},schoolCalendarEvent:{20260901:'学校事件'},firstTermRemarks:'学期备注',PRIVATE:'SECRET'});
async function run({params={},origin='https://i.nuist.edu.cn',payload=fixture(),ok=true,invalidJSON=false}={}){
 const calls=[];
 const context=vm.createContext({params,task:'calendar',location:{origin},AbortController,setTimeout,clearTimeout,
  DOMParser:class{parseFromString(v){return {body:{textContent:v},querySelectorAll:()=>[]};}},
  fetch:async(url,opts)=>{calls.push({url,opts});return {ok,json:async()=>{if(invalidJSON)throw Error('login');return payload;}};}});
 const value=JSON.parse(JSON.stringify(await vm.runInContext(`(async()=>{${source}})()`,context)));return {value,calls};
}
test('calendar preserves school week, semester breaks, dates, events and remarks without raw data',async()=>{
 const {value,calls}=await run();assert.equal(value.ok,true);assert.equal(value.year,2026);
 assert.equal(value.terms[0].weeks[0].days[1].date,'2026-09-01');assert.equal(value.terms[0].weeks[0].days[1].event,'学校事件');assert.equal(value.terms[0].weeks[1].week,'寒假');assert.equal(value.terms[0].remarks,'学期备注');assert(!JSON.stringify(value).includes('SECRET'));
 assert.equal(calls.length,1);assert.equal(calls[0].opts.credentials,'include');assert.equal(calls[0].opts.redirect,'error');
});
test('year navigation uses only the observed XN parameter and rejects mismatched results',async()=>{
 const good=await run({params:{year:2026}});assert(good.calls[0].url.endsWith('?XN=2026'));
 assert.equal((await run({params:{year:2025}})).value.ok,false);
 for(const year of ['2026',2026.5,NaN,0,3000]){const r=await run({params:{year}});assert.equal(r.value.ok,false);assert.equal(r.calls.length,0);}
});
test('wrong origin never calls portal API',async()=>{const r=await run({origin:'https://evil.example'});assert.equal(r.value.ok,false);assert.equal(r.calls.length,0);});
test('login HTML, business failures, missing semesters and malformed weekday dates cannot succeed',async()=>{
 for(const options of [{ok:false},{invalidJSON:true},{payload:{code:'1',msg:'SECRET'}},{payload:{code:'0',XN:'2026',schoolYearData:{firstMap:{},secondMap:{}}}}])assert.equal((await run(options)).value.ok,false);
 for(const code of ['20260230','20260902','garbage']){const p=fixture();p.schoolYearData.firstMap[1].MON.CODE=code;assert.equal((await run({payload:p})).value.ok,false);}
 const p=fixture();p.schoolYearData.firstMap={1:{}};assert.equal((await run({payload:p})).value.ok,false);
});

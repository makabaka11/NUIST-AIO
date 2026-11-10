import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
const source=readFileSync(new URL('../assets/js/nuist_chaoxing.js',import.meta.url),'utf8');
function node({label='第一章; 未提交',status='',title='',url='/work/detail?id=7',time='剩余1小时'}={}){
 return {hasAttribute:()=>true,getAttribute:k=>k==='aria-label'?label:k==='data'?url:null,
 querySelector:s=>s==='.right-content'?{}:s==='.status'?{textContent:status}:s==='.overHidden2'?{textContent:title}:s==='.time'?{textContent:time}:null};
}
async function run({task='work',text='',nodes=[node()],url='https://mooc1.chaoxing.com/mooc2/work/list',workEnc='',pageEnc='',readyState='complete',URLConstructor=URL,expectedUrl='',requestedCourseId='',requestedClassId='',requestedCpi='',responseStatus=200}={}){
 const u=new URL(url);
 return JSON.parse(JSON.stringify(await vm.runInNewContext(`(async()=>{${source}})()`,{task,expectedUrl,requestedCourseId,requestedClassId,requestedCpi,URL:URLConstructor,location:{protocol:u.protocol,hostname:u.hostname,pathname:u.pathname,href:u.href},performance:{getEntriesByType:()=>[{responseStatus}]},document:{createElement:()=>{let target;return {set href(value){target=new URL(value,u.href);},get href(){return target.href;},get protocol(){return target.protocol;},get hostname(){return target.hostname;},get username(){return target.username;},get password(){return target.password;},get port(){return target.port;}};},readyState,body:{innerText:text},querySelectorAll:()=>nodes,querySelector:s=>s==='#enc'?{value:pageEnc}:s==='#workEnc'?{value:workEnc}:null}})));
}
test('course verification validates fields, deduplicates by course and class, and exposes no identity',async()=>{
 const row=(id)=>({cpi:3,content:{id,course:{data:[{id:1,name:'课名',secret:'SECRET'}]}}});
 const r=await run({task:'courses',url:'https://mooc1-api.chaoxing.com/mycourse/backclazzdata?view=json&rss=1',text:JSON.stringify({channelList:[row(2),row(2),row(4)],SECRET:'SECRET'})});
 assert.equal(r.ok,true);assert.equal(r.courses.length,2);assert(!JSON.stringify(r).includes('SECRET'));
 for(const text of ['<html>用户登录</html>','{}','{"channelList":[{}]}','{"channelList":null}'])assert.equal((await run({task:'courses',url:'https://mooc1-api.chaoxing.com/mycourse/backclazzdata',text})).ok,false);
 assert.equal((await run({task:'courses',url:'https://mooc1-api.chaoxing.com/mycourse/backclazzdata',text:'{"channelList":[]}'})).ok,true);
});
test('status classification preserves completed, pending and ended distinctions',async()=>{
 for(const [s,state] of [['未提交','todo'],['待互评','todo'],['已提交','done'],['待批阅','grading'],['已结束','expired'],['已过期未交','expired'],['未知状态','other']]){
  const r=await run({nodes:[node({label:`作业; ${s}`})]});assert.equal(r.ok,true);assert.equal(r.items[0].state,state);
 }
 const r=await run({nodes:[node({label:'标题; 含分号; 未交'})]});assert.equal(r.items[0].title,'标题; 含分号');
});
test('exam fallback uses DOM title and status',async()=>{
 const r=await run({task:'exam',url:'https://mooc1.chaoxing.com/exam-ans/mooc2/exam/exam-list',nodes:[node({label:'',title:'期末考试',status:'待批阅'})]});
 assert.equal(r.ok,true);assert.equal(r.items[0].title,'期末考试');assert.equal(r.items[0].state,'grading');
});
test('unknown HTML and denied pages cannot silently produce empty lists',async()=>{
 for(const text of ['','系统维护','无效的用户','参数传递不正确']) assert.equal((await run({nodes:[],text})).ok,false);
 assert.deepEqual(await run({nodes:[],text:'暂无作业'}),{ok:true,items:[]});
 assert.equal((await run({text:'访问过于频繁'})).code,'busy');
});
test('links are real page links; malformed and external links fail closed',async()=>{
 for(const url of ['javascript:alert(1)','https://evil.org/','https://evil@mooc1.chaoxing.com/','https://mooc1.chaoxing.com:444/'])assert.equal((await run({nodes:[node({url})]})).ok,false);
 const r=await run();assert.equal(r.items[0].url,'https://mooc1.chaoxing.com/work/detail?id=7');
 assert.equal((await run({nodes:[node({url:''})]})).items[0].url,'');
});
test('wrong origins and paths cannot parse data or expose course encodings',async()=>{
 assert.equal((await run({url:'https://evil.org/mooc2/work/list'})).ok,false);
 assert.equal((await run({url:'https://mooc1.chaoxing.com/login'})).ok,false);
 const r=await run({task:'meta',url:'https://mooc1.chaoxing.com/mooc2-ans/mycourse/studentcourse?enc='+'a'.repeat(32),workEnc:'b'.repeat(32)});
 assert.equal(r.stuenc,'a'.repeat(32));assert.equal(r.workEnc,'b'.repeat(32));
});

test('server rate limiting and HTTP failures cannot be considered successful probes',async()=>{
 for(const responseStatus of [202,429]) assert.equal((await run({responseStatus})).code,'busy');
 for(const responseStatus of [401,403,500]) assert.equal((await run({responseStatus})).ok,false);
});

test('course metadata reads the rendered middle-page enc without a URL parameter',async()=>{
 const url='https://mooc1.chaoxing.com/visit/stucoursemiddle?courseid=1&clazzid=2&cpi=3';
 const r=await run({task:'meta',url,pageEnc:'a'.repeat(32),workEnc:'b'.repeat(32)});
 assert.equal(r.ok,true);assert.equal(r.stuenc,'a'.repeat(32));assert.equal(r.workEnc,'b'.repeat(32));
 const conflict=await run({task:'meta',url:url+'&enc='+'c'.repeat(32),pageEnc:'a'.repeat(32),workEnc:'b'.repeat(32)});
 assert.equal(conflict.stuenc,'a'.repeat(32));
});
test('redirect/render races remain pending and unknown course documents fail closed',async()=>{
 const url='https://mooc2-ans.chaoxing.com/mooc2-ans/mycourse/studentcourse';
 assert.equal((await run({task:'meta',url})).code,'pending');
 assert.equal((await run({task:'meta',url:url+'?enc='+'a'.repeat(32),readyState:'loading'})).code,'pending');
 assert.equal((await run({task:'meta',url,pageEnc:'a'.repeat(32),workEnc:'b'.repeat(32)})).ok,true);
 for (const path of ['/login','/work/detail']) {
  assert.equal((await run({task:'meta',url:'https://mooc1.chaoxing.com'+path,pageEnc:'a'.repeat(32)})).ok,false);
 }
 assert.equal((await run({task:'meta',url,pageEnc:'invalid'})).ok,false);
});

test('observed Android course landing /mycourse/stu supports hidden and URL enc',async()=>{
 const url='https://mooc2-ans.chaoxing.com/mooc2-ans/mycourse/stu';
 for (const values of [
  {pageEnc:'a'.repeat(32)},
  {url:url+'?enc='+'a'.repeat(32)},
 ]) {
  const r=await run({task:'meta',url,workEnc:'b'.repeat(32),...values});
  assert.equal(r.ok,true);assert.equal(r.stuenc,'a'.repeat(32));
 }
});

test('official pages shadowing window.URL cannot break course metadata or item links',async()=>{
 for (const URLConstructor of [undefined,'site-owned-value',{}]) {
  const r=await run({task:'meta',url:'https://mooc2-ans.chaoxing.com/mooc2-ans/mycourse/stu?enc='+'a'.repeat(32),workEnc:'b'.repeat(32),URLConstructor});
  assert.equal(r.ok,true);assert.equal(r.stuenc,'a'.repeat(32));
  assert.equal((await run({URLConstructor})).ok,true);
 }
});

test('redirect navigation status does not reject a valid course document',async()=>{
 for (const responseStatus of [301,302,303,307,308]) {
  const r=await run({task:'meta',url:'https://mooc2-ans.chaoxing.com/mooc2-ans/mycourse/stu',pageEnc:'a'.repeat(32),workEnc:'b'.repeat(32),responseStatus});
  assert.equal(r.ok,true);assert.equal(r.httpStatus,responseStatus);
 }
});

test('server-selected course shell documents retain strict host and field validation',async()=>{
 for (const path of ['/mooc2-ans/mycourse/stucourse','/mooc2-ans/mycourse/stu/','/mooc2-ans/mycourse/studentcourse;session=value']) {
  const r=await run({task:'meta',url:'https://mooc2-ans.chaoxing.com'+path,pageEnc:'a'.repeat(32),workEnc:'b'.repeat(32)});
  assert.equal(r.ok,true);assert(!r.documentPath.includes(';'));
 }
});

test('native navigation cannot parse the previous course document or list',async()=>{
 const target='https://mooc2-ans.chaoxing.com/mooc2-ans/mycourse/stu?courseid=10&clazzid=20&cpi=30';
 const old='https://mooc1.chaoxing.com/exam-ans/mooc2/exam/exam-list?courseid=9';
 assert.equal((await run({task:'meta',url:old,expectedUrl:target})).code,'pending');
 const previous=target.replace('courseid=10','courseid=9');
 assert.equal((await run({task:'meta',url:previous,expectedUrl:previous,requestedCourseId:'10',pageEnc:'a'.repeat(32)})).code,'pending');
 assert.equal((await run({task:'meta',url:target,expectedUrl:target,requestedCourseId:'10',requestedClassId:'20',requestedCpi:'30',pageEnc:'a'.repeat(32),workEnc:'b'.repeat(32)})).ok,true);
 assert.equal((await run({task:'work',url:old,expectedUrl:'https://mooc1.chaoxing.com/mooc2/work/list'})).code,'pending');
});

test('refreshing the same course still waits for its previous exam document to leave',async()=>{
 const old='https://mooc1.chaoxing.com/exam-ans/mooc2/exam/exam-list?courseid=10&clazzid=20&cpi=30';
 const r=await run({task:'meta',url:old,expectedUrl:old,requestedCourseId:'10',requestedClassId:'20',requestedCpi:'30'});
 assert.equal(r.code,'pending');
});

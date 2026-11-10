import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
const source=readFileSync(new URL('../assets/js/nuist_library.js',import.meta.url),'utf8');
const row=(id=1)=>({bibAttrs:{title:'书名'+id,author:'作者',PRIVATE:'SECRET'},item:{barCode:'INTERNAL-'+id},loanDate:'2026-10-01T00:00:00',dueDate:'2026-12-01',loanStatus:'normal',reader:'SECRET'});
async function run({task='loans',origin='https://elib.nuist.edu.cn',pages=[{items:[row()],total:1}],ok=true,code=0,invalidJSON=false}={}){
 const calls=[];
 const result=await vm.runInNewContext(`(async()=>{${source}})()`,{task,location:{origin},document:{cookie:'CSRF-TOKEN=SOURCE-ONLY; unrelated=SECRET'},AbortController,setTimeout,clearTimeout,
 fetch:async(url,options)=>{calls.push({url,options});const index=calls.length-1;return {ok,json:async()=>{if(invalidJSON)throw Error('login');return {code,data:pages[Math.min(index,pages.length-1)]};}};}});
 return {result:JSON.parse(JSON.stringify(result)),calls};
}
test('probe is fixed read-only server validation without exporting credentials or books',async()=>{
 const {result,calls}=await run({task:'probe'});assert.deepEqual(result,{ok:true,ready:true});assert(calls[0].url.endsWith('page=1&pageSize=1'));assert.equal(calls[0].options.credentials,'include');assert.equal(calls[0].options.redirect,'error');assert.equal(calls[0].options.headers['X-CSRF-TOKEN'],'SOURCE-ONLY');assert(!JSON.stringify(result).includes('SOURCE-ONLY'));
});
test('all pages are required and only display book fields leave the origin',async()=>{
 const rows=Array.from({length:20},(_,i)=>row(i));
 const {result,calls}=await run({pages:[{items:rows,total:21},{items:[row(20)],total:21}]});assert.equal(result.ok,true);assert.equal(result.total,21);assert.equal(calls.length,2);assert.equal(result.books[0].loanDate,'2026-10-01');assert(!JSON.stringify(result).includes('SECRET'));assert(!JSON.stringify(result).includes('INTERNAL'));
});
test('expired auth, non-JSON, changed totals and incomplete or duplicate pages are failures',async()=>{
 for(const options of [{ok:false},{code:1},{invalidJSON:true},{pages:[{items:null,total:0}]},{pages:[{items:[],total:1}]},{pages:[{items:[row(),row()],total:2}]},{pages:[{items:[row()],total:21},{items:[row(2)],total:22}]}])assert.equal((await run(options)).result.ok,false);
 assert.equal((await run({pages:[{items:[],total:0}]})).result.ok,true);
});
test('wrong origin and unsupported tasks never request library mutations or outside services',async()=>{
 for(const options of [{origin:'https://lib.nuist.edu.cn'},{origin:'https://evil.org'},{task:'renew'},{task:'loss'}]){const r=await run(options);assert.equal(r.result.ok,false);assert.equal(r.calls.length,0);}
});

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {webcrypto, createHash} from 'node:crypto';
const source = readFileSync(new URL('../assets/js/nuist_portal_probe.js', import.meta.url), 'utf8');
const run = new Function('location', 'fetch', 'AbortController', 'setTimeout', 'clearTimeout', 'TextEncoder', 'crypto', `return (async()=>{${source}})()`);
async function probe(data, options={}) {
  let calls=0;
  const result=await run({origin:options.origin??'https://i.nuist.edu.cn'},async(path,init)=>{
    calls++;
    assert.equal(path,'/getLoginUser');
    assert.equal(init.credentials,'include');
    assert.equal(init.headers['X-Requested-With'],'XMLHttpRequest');
    if(options.fail)throw new Error('network');
    return {ok:options.ok??true,url:options.url??'https://i.nuist.edu.cn/getLoginUser',json:async()=>data};
  },AbortController,setTimeout,clearTimeout,TextEncoder,webcrypto);
  return {result,calls};
}
test('returns a stable account digest and only the requested display name',async()=>{
 const payload={errcode:'0',data:{userAccount:'synthetic-account',userName:' 示例同学 ',phone:'Do not export'}};
 const {result}=await probe(payload);
 assert.equal(result.accountKey,createHash('sha256').update('nuistaio:portal:synthetic-account').digest('hex'));
 assert.deepEqual(Object.keys(result).sort(), ['accountKey','displayName']);
 assert.equal(result.displayName,'示例同学');
 assert.notEqual(result.accountKey,(await probe({errcode:'0',data:{userAccount:'second-account'}})).result.accountKey);
 assert.equal((await probe({errcode:'0',data:{userAccount:'synthetic'}})).result.displayName,'');
});
test('guests, missing identities, non-success and invalid responses cannot connect',async()=>{
 for(const d of [{errcode:'0',data:null},{errcode:'0',data:{}},{errcode:'1',data:{userAccount:'synthetic'}},{errcode:'0',data:{userAccount:''}}])assert.equal((await probe(d)).result,false);
 for(const options of [{fail:true},{ok:false},{url:'https://authserver.nuist.edu.cn/authserver/login'}])assert.equal((await probe({errcode:'0',data:{userAccount:'synthetic'}},options)).result,false);
});
test('other origins cannot invoke the user endpoint',async()=>{
 const {result,calls}=await probe({}, {origin:'https://icard.nuist.edu.cn'});
 assert.equal(result,false);assert.equal(calls,0);
});

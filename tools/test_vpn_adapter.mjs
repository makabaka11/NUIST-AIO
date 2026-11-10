import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {test} from 'node:test';
import vm from 'node:vm';
const vpn=readFileSync(new URL('../assets/js/nuist_vpn.js',import.meta.url),'utf8');
const bulletin=readFileSync(new URL('../assets/js/nuist_bulletin.js',import.meta.url),'utf8');
const proxy='https://client.vpn.nuist.edu.cn/https/webvpn'+'a'.repeat(64);
const resource={server:'https://bulletin.nuist.edu.cn',urlPlus:proxy,canVisit:true,type:'web'};
async function run({cookie=true,code='200',resources=[resource],ok=true}={}){
 const calls=[];
 const identity={userId:'PRIVATE-USER-ID',sid:'PRIVATE-SESSION',loginKey:'PRIVATE-KEY'};
 const context=vm.createContext({URL,AbortController,TextDecoder,Uint8Array,atob,setTimeout,clearTimeout,
 location:{origin:'https://client.vpn.nuist.edu.cn'},document:{cookie:cookie?'other=1; clientInfo='+btoa(JSON.stringify(identity)):''},
 fetch:async(url,options)=>{calls.push({url,options});return {ok,json:async()=>({code,data:{serviceAllList:resources},identity})};}});
 const result=JSON.parse(JSON.stringify(await vm.runInContext(`(async()=>{${vpn}})()`,context)));
 return {result,calls};
}
test('authorized resource map is the only exported data',async()=>{
 const {result,calls}=await run();
 assert.deepEqual(result,{ok:true,ready:true,routes:{'https://bulletin.nuist.edu.cn':proxy}});
 assert(!JSON.stringify(result).includes('PRIVATE'));
 assert.equal(calls[0].url,'/enlink/api/client/service/group/treeWithService/');
 assert.equal(calls[0].options.credentials,'include');
 assert.equal(JSON.parse(calls[0].options.body).userId,'PRIVATE-USER-ID');
});
test('missing session and expired server response are not ready',async()=>{
 const missing=await run({cookie:false});assert.equal(missing.result.ok,false);assert.equal(missing.calls.length,0);
 assert.equal((await run({code:'2000'})).result.ok,false);
 assert.equal((await run({ok:false})).result.ok,false);
});
test('unregistered, denied and forged proxy resources never become routes',async()=>{
 for(const replacement of [{server:'https://jwxt.nuist.edu.cn'},{canVisit:false},{urlPlus:proxy+'?secret=bad'},{urlPlus:proxy+'/other'},{urlPlus:proxy.replace('client.vpn.nuist.edu.cn','evil.example')},{server:'https://user@bulletin.nuist.edu.cn'}]){
  const {result}=await run({resources:[{...resource,...replacement}]});assert.deepEqual(result.routes,{});
 }
});
test('bulletin parser rejects arbitrary URL before making a request',async()=>{
 for(const url of ['https://evil.example/','https://bulletin.nuist.edu.cn/index.htm?token=private','https://user@bulletin.nuist.edu.cn/index.htm']){
  const context=vm.createContext({URL,location:{origin:'https://bulletin.nuist.edu.cn',pathname:'/'},params:{url},fetch:()=>{throw Error('must not fetch');}});
  const result=await vm.runInContext(`(async()=>{${bulletin}})()`,context);assert.equal(result.ok,false);assert(!result.error.includes('private'));
 }
});
test('bulletin connection error does not report a successful empty list',async()=>{
 const context=vm.createContext({URL,AbortController,setTimeout,clearTimeout,location:{origin:'https://bulletin.nuist.edu.cn',pathname:'/'},fetch:async()=>({ok:false})});
 const result=await vm.runInContext(`(async()=>{${bulletin}})()`,context);assert.equal(result.ok,false);
});
test('browser-only resources retain HTTP and explicit port, strip directory landing paths',async()=>{
 const resources=[
  {server:'http://stu.nuist.edu.cn',path:'',urlPlus:proxy.replace('/https/','/http/')},
  {server:'http://xdex.nuist.edu.cn:18080',path:'/NUIST-WEB/#/',urlPlus:proxy.replace('/https/','/http/')+'/NUIST-WEB/#/'},
  {server:'https://cxcyjy.nuist.edu.cn',path:'/pt/HomePage',urlPlus:proxy+'/pt/HomePage'},
 ].map(s=>({...s,canVisit:true,type:'web'}));
 const {result}=await run({resources});assert.equal(Object.keys(result.routes).length,3);
 assert.equal(result.routes['http://xdex.nuist.edu.cn:18080'],proxy.replace('/https/','/http/'));
 assert.equal(result.routes['https://cxcyjy.nuist.edu.cn'],proxy);
 const bad=await run({resources:[{...resources[1],server:'http://xdex.nuist.edu.cn'}, {server:'bad',urlPlus:'bad',canVisit:true,type:'web'},resource]});
 assert.deepEqual(bad.result.routes,{'https://bulletin.nuist.edu.cn':proxy});
});

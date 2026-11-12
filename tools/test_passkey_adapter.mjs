import {readFile} from 'node:fs/promises';
import {webcrypto, createPublicKey, verify, createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import test from 'node:test';
const login = await readFile(new URL('../assets/js/nuist_passkey_login.js', import.meta.url), 'utf8');
const registration = (await readFile(new URL('../assets/js/nuist_passkey_register.js', import.meta.url), 'utf8')).replace('__PORTAL_ALLOWED_ORIGIN__', JSON.stringify('https://authserver.nuist.edu.cn')).replace('__DEVICE_NAME__', JSON.stringify('Synthetic test'));
const origin = 'https://authserver.nuist.edu.cn';
async function enroll({rejected = false, wrongOrigin = false} = {}) {
  const calls = [];
  let finishBody;
  let resolve;
  const result = new Promise(r => {resolve=r;});
  const window = {NuistPasskey: {postMessage: raw => {
    const msg = JSON.parse(raw);
    if (msg.type === 'success' || msg.type === 'error') resolve(msg);
  }}};
  const location = {origin: wrongOrigin ? 'https://evil.test' : origin, hostname:'authserver.nuist.edu.cn', pathname:'/personalInfo/personCenter/index.html', hash:''};
  const fetch = async (path, init) => {
    calls.push(path);
    const data = path.endsWith('isUserRecheckNecessary') ? {code:'0'} : path.endsWith('startRegister') ? {datas:{request:{requestId:'synthetic',publicKeyCredentialCreationOptions:{rp:{id:location.hostname},challenge:'c3ludGhldGlj',pubKeyCredParams:[{alg:-7}]}}}} : (() => {finishBody=JSON.parse(init.body);return {code: rejected ? '1' : '0',datas:{result:'c3ludGhldGlj',anonbiometricsd:'synthetic-id'}};})();
    return {ok:true,url:origin + path,json:async()=>data};
  };
  window.fetch=fetch;
  class XHR {open() {} send() {}}
  const document = {addEventListener(){},removeEventListener(){},querySelectorAll(){return [];}};
  new Function('window','top','location','navigator','document','crypto','XMLHttpRequest','TextEncoder','AbortSignal','URL','btoa','atob',registration)(window,window,location,{},document,webcrypto,XHR,TextEncoder,AbortSignal,URL,btoa,atob);
  if (wrongOrigin) return {calls};
  return {message:await result,calls,finishBody};
}
async function assertLogin(bundle, {wrongOrigin=false,rejected=false,rpId=bundle.rpId,allow=true}={}) {
  let submitted=false, calls=0;
  const fields={};
  const location={origin:wrongOrigin ? 'https://evil.test':origin,hostname:'authserver.nuist.edu.cn',pathname:'/authserver/login',href:origin+'/authserver/login?service=synthetic'};
  const document={querySelector:()=>({value:'synthetic-execution'}),createElement:tag=>tag==='form'?{append(input){fields[input.name]=input.value;},submit(){submitted=true;}}:{},body:{append(){}}};
  const fetch=async()=>{calls++;return {ok:!rejected,url:origin+'/authserver/startAssertion',json:async()=>({result:{request:{requestId:'assertion',publicKeyCredentialRequestOptions:{rpId,challenge:'c3ludGhldGlj',allowCredentials:[{id:allow?bundle.credentialId:'different'}]}}}})}};
  const result=await new Function('bundle','location','document','fetch','crypto','TextEncoder','AbortSignal','URL','btoa','atob',`return (async()=>{${login}})()`)(bundle,location,document,fetch,webcrypto,TextEncoder,AbortSignal,URL,btoa,atob);
  return {result,submitted,fields,calls};
}
test('registration creates a usable ES256 credential without storing a password',async()=>{
  const {message,calls,finishBody}=await enroll();
  assert.equal(message.type,'success');
  assert.deepEqual(calls,['/personalInfo/common/isUserRecheckNecessary','/personalInfo/accountSecurity/startRegister','/personalInfo/accountSecurity/finishRegister']);
  assert.equal(finishBody.deviceName,'Synthetic test');
  const credential=JSON.parse(finishBody.response).credential;
  assert.equal(credential.id,message.bundle.credentialId);
  assert.equal(JSON.parse(Buffer.from(credential.response.clientDataJSON,'base64url')).type,'webauthn.create');
  assert.equal(Object.hasOwn(message.bundle,'password'),false);
  const signed=await assertLogin(message.bundle);
  assert.equal(signed.submitted,true);
  assert.equal(signed.fields.execution,'synthetic-execution');
  assert.equal(signed.fields.username,message.bundle.userId);
  const assertion=JSON.parse(signed.fields.responseJson).credential;
  const auth=Buffer.from(assertion.response.authenticatorData,'base64url');
  const client=Buffer.from(assertion.response.clientDataJSON,'base64url');
  assert.equal(auth.length,37);
  assert.deepEqual(auth.subarray(0,32),createHash('sha256').update(message.bundle.rpId).digest());
  assert.equal(verify('sha256',Buffer.concat([auth,createHash('sha256').update(client).digest()]),createPublicKey(message.bundle.privateKeyPkcs8Pem),Buffer.from(assertion.response.signature,'base64url')),true);
});
test('registration server rejection never exports the private key',async()=>{
  const {message}=await enroll({rejected:true});
  assert.deepEqual(message,{type:'error'});
});
test('registration never runs outside the exact official origin',async()=>{
  assert.deepEqual((await enroll({wrongOrigin:true})).calls,[]);
});
test('assertion rejects hostile origin, revoked credentials, mismatched RP and HTTP errors',async()=>{
  const {message}=await enroll();
  for(const options of [{wrongOrigin:true},{rejected:true},{rpId:'evil.test'},{allow:false}]) {
    const result=await assertLogin(message.bundle,options);
    assert.equal(result.result,false);
    assert.equal(result.submitted,false);
    if(options.wrongOrigin) assert.equal(result.calls,0);
  }
});

const authPageState = await readFile(new URL('../assets/js/nuist_auth_page_state.js', import.meta.url), 'utf8');
const classify = ({origin:pageOrigin=origin,path='/authserver/login',ready='complete',text='',form=false}={}) => new Function('location','document',authPageState)({origin:pageOrigin,pathname:path},{readyState:ready,body:{innerText:text},querySelector:()=>form?{}:null});
test('CAS application rejection exports a fixed state without identity or page text',()=>{
  assert.equal(classify({text:'PRIVATE-ID 应用未注册 不允许使用认证服务来认证您访问的目标应用。'}),'unregistered');
  assert.equal(classify({form:true}),'login');
  assert.equal(classify({text:'应用未注册'}),'unknown');
});
test('CAS error classification waits for the exact official document',()=>{
  const text='应用未注册 不允许使用认证服务';
  for(const options of [{origin:'https://evil.test'},{origin:'http://authserver.nuist.edu.cn'},{path:'/personalInfo/personCenter/index.html'},{ready:'loading'}]) {
    assert.equal(classify({text,...options}),'unknown');
  }
});

globalThis.__aioAssertionStage = 'context';
// Runs only inside the official CAS document, using its native cookies.
if (location.origin !== 'https://authserver.nuist.edu.cn' ||
    location.pathname !== '/authserver/login') return false;
globalThis.__aioAssertionStage = 'execution';
const execution = document.querySelector('input[name="execution"]')?.value;
if (!execution || bundle.rpId !== location.hostname) return false;
globalThis.__aioAssertionStage = 'challenge';
const response = await fetch('/authserver/startAssertion', {
  method: 'POST', credentials: 'same-origin',
  headers: {'Content-Type': 'application/json;charset=utf-8', 'X-Requested-With': 'XMLHttpRequest'},
  body: JSON.stringify({userId: bundle.userId, id: bundle.anonbiometricsd}),
  signal: AbortSignal.timeout(10000),
});
if (!response.ok || new URL(response.url).origin !== location.origin) return false;
globalThis.__aioAssertionStage = 'challenge_response';
const data = await response.json();
const request = data.result?.request ?? data.datas?.request;
const options = request?.publicKeyCredentialRequestOptions;
if (data.success === false || !request?.requestId || !options?.challenge ||
    (options.rpId && options.rpId !== bundle.rpId)) return false;
if (options.allowCredentials?.length && !options.allowCredentials.some(c => c.id === bundle.credentialId)) return false;
const encode = b => btoa(String.fromCharCode(...new Uint8Array(b))).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
const utf8 = new TextEncoder();
const client = utf8.encode(JSON.stringify({type:'webauthn.get', challenge:options.challenge, origin:location.origin, crossOrigin:false}));
const hash = async b => new Uint8Array(await crypto.subtle.digest('SHA-256', b));
const auth = new Uint8Array([...await hash(utf8.encode(bundle.rpId)), 5, 0, 0, 0, 0]);
const pem = bundle.privateKeyPkcs8Pem.replace(/-----[^-]+-----/g,'').replace(/\s/g,'');
globalThis.__aioAssertionStage = 'key_import';
const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(pem), c => c.charCodeAt(0)), {name:'ECDSA', namedCurve:'P-256'}, false, ['sign']);
globalThis.__aioAssertionStage = 'signing';
const raw = new Uint8Array(await crypto.subtle.sign({name:'ECDSA', hash:'SHA-256'}, key, new Uint8Array([...auth, ...await hash(client)])));
// WebCrypto uses IEEE P1363; WebAuthn requires ASN.1 DER.
const integer = bytes => {
  let start = 0;
  while (start < bytes.length - 1 && bytes[start] === 0) start++;
  const value = Array.from(bytes.slice(start));
  if (value[0] & 128) value.unshift(0);
  return [2, value.length, ...value];
};
if (raw.length !== 64) return false;
const parts = [...integer(raw.slice(0,32)), ...integer(raw.slice(32))];
const credential = {type:'public-key', id:bundle.credentialId, response:{authenticatorData:encode(auth), clientDataJSON:encode(client), signature:encode([48,parts.length,...parts])}, clientExtensionResults:{appid:false}};
globalThis.__aioAssertionStage = 'submitting';
const form = document.createElement('form');
form.method = 'POST'; form.action = location.href;
const fields = {_eventId:'submit', username:bundle.userId, responseJson:JSON.stringify({requestId:request.requestId, credential, sessionToken:null}), cllt:'fidoLogin', dllt:'generalLogin', lt:'', execution};
for (const [name,value] of Object.entries(fields)) {
  const input = document.createElement('input'); input.type='hidden'; input.name=name; input.value=value; form.append(input);
}
document.body.append(form);
form.submit();
return true;

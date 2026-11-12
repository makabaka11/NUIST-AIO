// NUIST AIO software credential enrollment. Protocol endpoints and response
// fields were checked against the adjacent nuist-sta-app implementation.
(() => {
  const origin = __PORTAL_ALLOWED_ORIGIN__;
  const deviceName = __DEVICE_NAME__;
  if (window !== top || location.origin !== origin ||
      !location.pathname.toLowerCase().includes('personcenter') || window.__aioEnrollment) return;
  window.__aioEnrollment = true;
  const send = (type, details = {}) => window.NuistPasskey?.postMessage(JSON.stringify({type, ...details}));
  const bytes = s => Uint8Array.from(atob(s.replaceAll('-','+').replaceAll('_','/')), c => c.charCodeAt(0));
  const b64 = b => btoa(String.fromCharCode(...new Uint8Array(b)));
  const url64 = b => b64(b).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
  const utf8 = new TextEncoder();
  const concat = (...values) => new Uint8Array(values.flatMap(v => Array.from(v)));
  // Small CBOR encoder for the COSE EC2 key and none attestation only.
  const cbor = value => {
    const head = (major, n) => n < 24 ? [major * 32 + n] : n < 256 ? [major * 32 + 24, n] : [major * 32 + 25, n >> 8, n & 255];
    if (typeof value === 'number') return new Uint8Array(value >= 0 ? head(0,value) : head(1,-1-value));
    if (typeof value === 'string') {const b=utf8.encode(value); return concat(head(3,b.length),b);}
    if (value instanceof Uint8Array) return concat(head(2,value.length),value);
    if (value instanceof Map) return concat(head(5,value.size), ...Array.from(value).flatMap(([k,v]) => [cbor(k),cbor(v)]));
    throw new Error('Unsupported credential encoding');
  };
  const enrollmentFetch = window.fetch.bind(window);
  const api = async (path, body) => {
    if (location.origin !== origin) throw new Error('Origin changed');
    const response = await enrollmentFetch('/personalInfo' + path, {
      method: body === undefined ? 'GET' : 'POST', credentials: 'same-origin',
      headers: {'Content-Type':'application/json', 'Accept':'application/json', 'X-Requested-With':'XMLHttpRequest'},
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok || new URL(response.url).origin !== origin) throw new Error('Enrollment unavailable');
    return response.json();
  };
  async function enroll() {
    send('status', {stage:'verifying'});
    // Let the official page handle password, captcha and its verification UI.
    // Expose capability detection in WebViews without a platform authenticator;
    // the real credential is generated below only after the server grants recheck.
    if (!window.PublicKeyCredential) window.PublicKeyCredential = class {};
    window.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable = async () => true;
    if (!navigator.credentials) Object.defineProperty(navigator, 'credentials', {value:{}});
    let armed = false, verified = false;
    const arm = event => {
      const button = event.target.closest?.('button, .account-item');
      if (button?.textContent.includes('绑定当前设备')) armed = true;
    };
    document.addEventListener('click', arm, true);
    // Pause the page's native enrollment after its official identity check.
    const xhrOpen = XMLHttpRequest.prototype.open;
    const xhrSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url, ...args) {
      this.__aioPath = new URL(String(url), location.href).pathname.toLowerCase();
      return xhrOpen.call(this, method, url, ...args);
    };
    XMLHttpRequest.prototype.send = function(...args) {
      if (armed && this.__aioPath?.endsWith('/isdevicebinded')) { verified = true; return; }
      if (this.__aioPath?.endsWith('/startregister') || this.__aioPath?.endsWith('/finishregister')) return;
      return xhrSend.apply(this, args);
    };
    const pageFetch = window.fetch;
    window.fetch = function(input, init) {
      const path = new URL(typeof input === 'string' ? input : input.url, location.href).pathname.toLowerCase();
      if (armed && path.endsWith('/isdevicebinded')) { verified = true; return new Promise(() => {}); }
      if (path.endsWith('/startregister') || path.endsWith('/finishregister')) return new Promise(() => {});
      return pageFetch.call(this, input, init);
    };
    const originalCreate = navigator.credentials.create?.bind(navigator.credentials);
    navigator.credentials.create = () => Promise.reject(new Error('请返回 App 完成通行密钥创建'));
    const initialHash = location.hash;
    if (initialHash.toLowerCase().includes('accountsecurity')) {
      location.hash = '#/';
      await new Promise(resolve => setTimeout(resolve, 300));
    }
    location.hash = '#/accountsecurity';
    try {
      const deadline = Date.now() + 10 * 60 * 1000;
      let granted = false, switchClicked = false;
      while (Date.now() < deadline) {
        if (verified) {granted=true; break;}
        const modal = Array.from(document.querySelectorAll('.ivu-modal')).find(m => m.getClientRects().length && m.querySelector('.ivu-modal-header')?.textContent.includes('绑定当前设备'));
        if (armed && modal) {granted=true; modal.querySelector('.ivu-modal-close')?.click(); break;}
        const status = await api('/common/isUserRecheckNecessary');
        if (String(status.code) === '0') {granted=true; break;}
        const tab = document.querySelector('.tab li[title="生物识别"]');
        if (tab && !tab.classList.contains('active')) tab.click();
        const toggle = document.querySelector('.biometrics-switch .ivu-switch');
        if (toggle && !toggle.classList.contains('ivu-switch-checked') && !switchClicked) {switchClicked=true; toggle.click();}
        const bind = document.querySelector('.account-item.add_item');
        if (bind && !armed) {armed=true; bind.click();}
        await new Promise(resolve => setTimeout(resolve, 2000));
      }
      if (!granted) throw new Error('Verification timed out');
      send('status', {stage:'registering'});
      const start = await api('/accountSecurity/startRegister', {});
      const request = start.datas?.request;
      const options = request?.publicKeyCredentialCreationOptions;
      if (!request?.requestId || !options?.challenge || (options.rp?.id && options.rp.id !== location.hostname)) throw new Error('Invalid registration challenge');
      if (options.pubKeyCredParams && !options.pubKeyCredParams.some(p => p.alg === -7)) throw new Error('ES256 required');
      const pair = await crypto.subtle.generateKey({name:'ECDSA', namedCurve:'P-256'}, true, ['sign','verify']);
      const jwk = await crypto.subtle.exportKey('jwk', pair.publicKey);
      const pkcs8 = await crypto.subtle.exportKey('pkcs8', pair.privateKey);
      const credentialId = crypto.getRandomValues(new Uint8Array(16));
      const cose = cbor(new Map([[1,2],[3,-7],[-1,1],[-2,bytes(jwk.x)],[-3,bytes(jwk.y)]]));
      const rpHash = new Uint8Array(await crypto.subtle.digest('SHA-256', utf8.encode(location.hostname)));
      // UP + AT, zero counter, zero AAGUID, 16-byte credential ID.
      const auth = concat(rpHash, [0x41,0,0,0,0], new Uint8Array(16), [0,16], credentialId, cose);
      const attestation = cbor(new Map([['fmt','none'],['attStmt',new Map()],['authData',auth]]));
      const client = utf8.encode(JSON.stringify({type:'webauthn.create', challenge:options.challenge, origin, crossOrigin:false}));
      const id = url64(credentialId);
      const credential = {id, type:'public-key', response:{attestationObject:url64(attestation), clientDataJSON:url64(client)}, clientExtensionResults:{}};
      const finish = await api('/accountSecurity/finishRegister', {deviceName, anonbiometricsd:null, response:JSON.stringify({requestId:request.requestId, credential, sessionToken:null}), n:'0.9239225681951135'});
      if (String(finish.code) !== '0' || typeof finish.datas?.result !== 'string' || typeof finish.datas?.anonbiometricsd !== 'string') throw new Error('Registration rejected');
      send('success', {bundle:{rpId:location.hostname, credentialId:id, privateKeyPkcs8Pem:'-----BEGIN PRIVATE KEY-----\n' + b64(pkcs8).match(/.{1,64}/g).join('\n') + '\n-----END PRIVATE KEY-----', userId:finish.datas.result, anonbiometricsd:finish.datas.anonbiometricsd}});
    } finally {
      if (originalCreate) navigator.credentials.create = originalCreate;
      window.fetch = pageFetch;
      XMLHttpRequest.prototype.open = xhrOpen;
      XMLHttpRequest.prototype.send = xhrSend;
      document.removeEventListener('click', arm, true);
    }
  }
  enroll().catch(() => send('error'));
})();

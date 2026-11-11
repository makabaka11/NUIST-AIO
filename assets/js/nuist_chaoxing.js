// Read-only Chaoxing document adapter. Request paths and field mappings adapted
// from hangyuantong (Copyright (c) 2026 Hobson, MIT; see bundled license).
try {
  const hosts = ['mooc1.chaoxing.com', 'mooc1-api.chaoxing.com', 'mooc2-ans.chaoxing.com'];
  if (location.protocol !== 'https:' || !hosts.includes(location.hostname)) return {ok:false,code:'parse',stage:'origin'};
  const path = location.pathname.split(';')[0];
  const context = {documentHost:location.hostname,
    documentPath:/^\/[a-zA-Z0-9_./-]{0,160}$/.test(path) ? path : ''};
  const parameter = (name, href = location.href) => {
    const query = href.split('#')[0].split('?').slice(1).join('?');
    for (const part of query.split('&')) {
      const split = part.indexOf('=');
      if (decodeURIComponent(split < 0 ? part : part.slice(0,split)) === name) {
        return decodeURIComponent(part.slice(split+1).replace(/\+/g,' '));
      }
    }
    return '';
  };
  // Android can report a new native URL while JS still runs in the previous
  // document. Compare in the document itself, including course query identity.
  if (typeof expectedUrl === 'string' && expectedUrl) {
    const expected = document.createElement('a');
    expected.href = expectedUrl;
    if (expected.href.split('#')[0] !== location.href.split('#')[0]) {
      return {ok:false,code:'pending',...context};
    }
  }
  const identity = [
    [typeof requestedCourseId === 'string' ? requestedCourseId : '', ['courseid','courseId']],
    [typeof requestedClassId === 'string' ? requestedClassId : '', ['clazzid','classid','classId']],
    [typeof requestedCpi === 'string' ? requestedCpi : '', ['cpi']],
  ];
  const matchesCourse = (href, strict = false) => identity.every(([expected,names]) => {
    const actual = names.map(name => parameter(name,href)).find(Boolean);
    return !expected || (actual ? actual === expected : !strict);
  });
  if (!matchesCourse(location.href)) return {ok:false,code:'pending',...context};
  const status = globalThis.performance?.getEntriesByType?.('navigation')?.[0]?.responseStatus;
  if (status === 202 || status === 429) return {ok:false,code:'busy'};
  if (status >= 400) return {ok:false,code:'parse',stage:'http_status',httpStatus:status};
  const text = document.body?.innerText || document.body?.textContent || '';
  if (/访问过于频繁|操作频繁|请求过于频繁|访问频繁|检查的太频繁/.test(text)) return {ok:false,code:'busy'};
  if (/无权限的操作|无效的用户|参数传递不正确|用户登录/.test(text)) return {ok:false, code:'auth'};
  if (task === 'courses') {
    if (location.hostname !== 'mooc1-api.chaoxing.com' || location.pathname !== '/mycourse/backclazzdata') return {ok:false,code:'pending',...context};
    const j = JSON.parse(text);
    if (j.result === false || j.status === false || !Array.isArray(j.channelList)) throw Error();
    const courses = [], seen = new Set();
    for (const ch of j.channelList) {
      const c = ch.content, d = c?.course?.data?.[0];
      if (!d) throw Error();
      const courseId = String(d.id || ''), classId = String(c.id || ''), cpi = String(ch.cpi || c.cpi || '');
      if (![courseId,classId,cpi].every(v => /^\d+$/.test(v)) || typeof d.name !== 'string' || !d.name.trim()) throw Error();
      const key = courseId + ':' + classId;
      if (!seen.has(key)) courses.push({courseId,classId,cpi,title:d.name.trim(),alias:typeof c.name === 'string' ? c.name : ''});
      seen.add(key);
    }
    return {ok:true, courses};
  }
  if (task === 'progress') {
    if (path !== '/visit/stucoursemiddle' && !/^\/(?:mooc2-ans\/|mooc-ans\/)?mycourse\//.test(path)) {
      return {ok:false,code:'pending',...context};
    }
    const readings = new Set(), documents = new Set();
    let chapterUrl = '';
    const inspect = (doc, depth) => {
      if (!doc || documents.has(doc) || depth > 2) return;
      documents.add(doc);
      const content = doc.body?.cloneNode?.(true) || doc.body;
      for (const node of content?.querySelectorAll?.('script,style,template,noscript') || []) node.remove();
      const body = content?.textContent || content?.innerText || '';
      const pattern = /(?:已完成任务点|任务点已完成)\s*[:：]?\s*(\d+)\s*[\/／]\s*(\d+)/g;
      for (const match of body.matchAll(pattern)) {
        const completed = Number(match[1]), total = Number(match[2]);
        if (!Number.isSafeInteger(completed) || !Number.isSafeInteger(total) || completed > total || total > 1000000) throw Error();
        readings.add(completed + '/' + total);
      }
      for (const frame of doc.querySelectorAll('iframe')) {
        const target = doc.createElement('a');
        target.href = frame.getAttribute('src') || '';
        if (target.protocol !== 'https:' || !hosts.includes(target.hostname) ||
            target.username || target.password || (target.port && target.port !== '443') ||
            !/^\/(?:mooc2-ans\/|mooc-ans\/)?mycourse\//.test(target.pathname) ||
            !matchesCourse(target.href,true)) continue;
        if (target.hostname !== location.hostname) {
          // Follow only the official course iframe URL, once, in the resident
          // WebView. Never copy cookies or fetch a guessed chapter endpoint.
          chapterUrl ||= target.href;
          continue;
        }
        try {
          if (frame.contentWindow?.location.href.split('#')[0] !== target.href.split('#')[0]) continue;
          inspect(frame.contentDocument, depth + 1);
        } catch (_) { /* Cross-origin frames remain isolated. */ }
      }
    };
    inspect(document, 0);
    if (readings.size > 1) throw Error();
    if (readings.size === 1) {
      const [completed,total] = [...readings][0].split('/').map(Number);
      return {ok:true,progress:{completed,total}};
    }
    if (chapterUrl) return {ok:true,progress:null,chapterUrl};
    return {ok:false,code:'pending',...context};
  }
  if (task === 'meta') {
    // Course-middle can render hidden fields without an enc in its URL, or
    // navigate to studentcourse. Never parse an unrelated trusted-host page.
    // The official course shell can replace its document with another page in
    // the same mycourse family. Require course DOM fields as well as its origin.
    if (path !== '/visit/stucoursemiddle' &&
        !/^\/(?:mooc2-ans\/|mooc-ans\/)?mycourse\//.test(path)) {
      return {ok:false,code:'pending',stage:'meta_path',...context};
    }
    const valid = value => /^[a-f0-9]{32}$/i.test(value || '');
    const pageEnc = document.querySelector('#enc')?.value;
    const urlEnc = parameter('enc');
    const workEnc = document.querySelector('#workEnc')?.value;
    const stuenc = valid(pageEnc) ? pageEnc : valid(urlEnc) ? urlEnc : '';
    if (!stuenc || (document.readyState && document.readyState !== 'complete' && !valid(workEnc))) {
      return {ok:false,code:'pending',...context,httpStatus:status,shape:'domEnc:'+String(pageEnc?.length || 0)+',urlEnc:'+String(urlEnc?.length || 0)+',workEnc:'+String(workEnc?.length || 0)};
    }
    const openc = document.querySelector('#openc')?.value || '';
    return {ok:true, stuenc, workEnc:valid(workEnc) ? workEnc : '',
      openc:/^[a-zA-Z0-9_-]{0,256}$/.test(openc) ? openc : '',...context,httpStatus:status};
  }
  if (!['work','exam'].includes(task)) throw Error();
  if (location.hostname !== 'mooc1.chaoxing.com' || location.pathname !== (task === 'work' ? '/mooc2/work/list' : '/exam-ans/mooc2/exam/exam-list')) return {ok:false,code:'pending',...context};
  const nodes = [...document.querySelectorAll('li')].filter(li => task === 'work' ? li.hasAttribute('aria-label') : li.querySelector('.right-content'));
  // Unknown HTML is an error. Empty state must be explicitly present.
  if (!nodes.length && !/暂无作业|暂无考试|暂无内容|暂无数据|还没有作业|还没有考试/.test(text)) throw Error();
  const items = nodes.map(li => {
    const label = li.getAttribute('aria-label') || '', split = label.lastIndexOf(';');
    const title = (split >= 0 ? label.slice(0,split) : li.querySelector('.overHidden2')?.textContent || '').trim();
    const status = (split >= 0 ? label.slice(split+1) : li.querySelector('.status')?.textContent || '').trim();
    if (!title || !status) throw Error();
    const raw = li.getAttribute('data') || li.querySelector('a[href]')?.getAttribute('href');
    let url = '';
    if (raw) {
      const u = document.createElement('a');
      u.href = raw;
      if (u.protocol !== 'https:' || !hosts.includes(u.hostname) || u.username || u.password || (u.port && u.port !== '443')) throw Error();
      url = u.href;
    }
    let state = 'other';
    if (/已过期|已结束|已截止|已超时/.test(status)) state = 'expired';
    else if (/待批阅|待批改|未批阅/.test(status)) state = 'grading';
    else if (/未交|未完成|未提交|未开始|待提交|待完成|待互评|进行中/.test(status)) state = 'todo';
    else if (/已完成|已提交|已交|已批阅|已通过|已互评|已作答|已参加/.test(status)) state = 'done';
    return {kind:task,title,status,state,time:(li.querySelector('.time')?.textContent || '').trim(),url};
  });
  return {ok:true,items};
} catch (error) { return {ok:false,code:'parse',reason:['TypeError','ReferenceError','SyntaxError','URIError'].includes(error?.name) ? error.name : 'Error'}; }

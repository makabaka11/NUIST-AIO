// Read the official current-user endpoint. Return only the account digest and
// display name requested by the user; never export the raw profile or cookies.
if (location.origin !== 'https://i.nuist.edu.cn') return false;
const abort = new AbortController();
const timer = setTimeout(() => abort.abort(), 10000);
try {
  const response = await fetch('/getLoginUser', {
    credentials: 'include',
    headers: {'X-Requested-With': 'XMLHttpRequest'},
    signal: abort.signal,
  });
  if (!response.ok || new URL(response.url).origin !== location.origin) return false;
  const data = await response.json();
  if (String(data.errcode) !== '0' || !data.data ||
      typeof data.data.userAccount !== 'string' || !data.data.userAccount) return false;
  const bytes = new TextEncoder().encode('nuistaio:portal:' + data.data.userAccount);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  const accountKey = Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, '0')).join('');
  const displayName = typeof data.data.userName === 'string' ? data.data.userName.trim().slice(0, 80) : '';
  return {accountKey, displayName};
} catch (_) {
  return false;
} finally {
  clearTimeout(timer);
}

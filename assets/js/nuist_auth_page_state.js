// Export a fixed classification only; never return page text or identity data.
if (location.origin !== 'https://authserver.nuist.edu.cn' ||
    !['/authserver', '/authserver/login'].includes(location.pathname) ||
    document.readyState !== 'complete') return 'unknown';
const text = document.body?.innerText ?? '';
if (text.includes('应用未注册') && text.includes('不允许使用认证服务')) return 'unregistered';
return document.querySelector('input[name="execution"]') ? 'login' : 'unknown';

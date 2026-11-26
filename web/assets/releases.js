(() => {
  'use strict';
  const base = 'https://github.com/bastilavarias/isme.gg';
  const versionPattern = /^v(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$/;
  const valid = r => r && typeof r.tag === 'string' && versionPattern.test(r.tag)
    && r.version === r.tag.slice(1) && r.releaseUrl === base + '/releases/tag/' + r.tag;
  const text = (id, value) => { document.getElementById(id).textContent = value; };
  const history = document.getElementById('release-history');
  const date = value => {
    const d = new Date(value);
    return value && Number.isFinite(d.getTime()) ? new Intl.DateTimeFormat('en-PH', {dateStyle:'long', timeZone:'Asia/Manila'}).format(d) : '';
  };
  function showRelease(r) {
    const details = document.createElement('details');
    const summary = document.createElement('summary');
    summary.textContent = r.tag + (date(r.publishedAt) ? ' · ' + date(r.publishedAt) : '');
    details.append(summary);
    const notes = document.createElement('div');
    notes.className = 'release-notes';
    notes.textContent = typeof r.notes === 'string' && r.notes.trim() ? r.notes : 'Release notes available on GitHub.';
    details.append(notes);
    const link = document.createElement('a');
    link.href = r.releaseUrl; link.textContent = 'Full release notes on GitHub';
    details.append(link); history.append(details);
  }
  fetch('assets/releases.json', {cache:'no-cache', credentials:'same-origin'})
    .then(response => { if (!response.ok) throw new Error('Unavailable'); return response.json(); })
    .then(feed => {
      if (!feed || feed.schema !== 1) throw new Error('Invalid feed');
      if (feed.latest === null) {
        text('release-status', 'Public release coming soon');
        text('release-summary', 'Our signed builds are being tested. Public downloads will appear here when ready.');
        return;
      }
      const r = feed.latest;
      if (!valid(r) || r.downloadUrl !== base + '/releases/download/' + r.tag + '/isme.apk'
        || !Number.isSafeInteger(r.bytes) || r.bytes < 1 || r.bytes > 200*1024*1024
        || r.minimumAndroidSdk !== 28 || !Array.isArray(r.abis)
        || !r.abis.includes('arm64-v8a') || !r.abis.includes('armeabi-v7a')) throw new Error('Invalid release');
      text('release-status', 'Latest release · ' + r.tag);
      text('release-summary', [date(r.publishedAt), (r.bytes/1048576).toFixed(1) + ' MiB', 'Android 9+ · ARM64 / ARMv7'].filter(Boolean).join(' · '));
      document.querySelectorAll('[data-apk-download]').forEach(a => {
        a.href = r.downloadUrl;
        a.querySelector('[data-download-label]').textContent = 'Download APK';
        a.removeAttribute('aria-disabled');
      });
      text('latest-release-title', 'What’s new in ' + r.tag);
      text('latest-release-notes', typeof r.notes === 'string' && r.notes.trim() ? r.notes : 'See the full release notes on GitHub.');
      document.getElementById('latest-release-link').href = r.releaseUrl;
      document.getElementById('release-changelog').hidden = false;
      if (Array.isArray(feed.history)) feed.history.filter(valid).slice(0,20).forEach(showRelease);
      document.getElementById('release-history-section').hidden = !history.children.length;
    })
    .catch(() => {
      text('release-status', 'Release information unavailable');
      text('release-summary', 'Check the project releases page for verified downloads.');
    });
})();

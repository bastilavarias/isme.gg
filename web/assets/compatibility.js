const root=document.documentElement;
const toggle=document.querySelector('#theme-toggle');
function syncTheme(){
  const light=root.dataset.theme==='light';
  const label=light?'Switch to dark mode':'Switch to light mode';
  toggle.setAttribute('aria-label',label);
  toggle.setAttribute('title',label);
  toggle.setAttribute('aria-pressed',String(light));
  document.querySelector('meta[name="theme-color"]').content=light?'#f3f0e8':'#0c0d0e';
}
syncTheme();
toggle.addEventListener('click',()=>{
  root.dataset.theme=root.dataset.theme==='light'?'dark':'light';
  try{localStorage.setItem('isme-web-theme',root.dataset.theme)}catch{}
  syncTheme();
});
const statuses={investigating:'Investigating',working:'Verified working',incompatible:'Incompatible',resolved:'Resolved',untested:'Untested'};
function element(tag,cls,text){
  const node=document.createElement(tag);
  if(cls)node.className=cls;
  if(text!==undefined)node.textContent=text;
  return node;
}
function deviceCard(entry){
  if(!entry||!Object.hasOwn(statuses,entry.status)||!/^\d{4}-\d{2}-\d{2}$/.test(entry.date)||
    !['brand','title','platform','issue','affected','logo','source'].every(k=>typeof entry[k]==='string'))throw new Error('Invalid device entry');
  const article=element('article','device'),head=element('div','device-head'),identity=element('div','identity');
  const logo=element('img','logo');logo.alt=entry.brand+' logo';logo.width=100;logo.height=60;
  if(/^\.\.\/assets\/brands\/[a-z0-9-]+\.svg$/.test(entry.logo))logo.src=entry.logo;
  else throw new Error('Invalid logo path');
  identity.append(element('h3','',entry.title),element('p','',entry.platform));
  const status=element('span','status',statuses[entry.status]);status.dataset.status=entry.status;
  head.append(logo,identity,status);
  const details=element('dl');
  for(const [label,value] of [['Reported issue',entry.issue],['Affected devices',entry.affected]]){
    const group=element('div');group.append(element('dt','',label),element('dd','',value));details.append(group);
  }
  const meta=element('div','meta'),date=element('time');
  date.dateTime=entry.date;
  date.textContent='Reported '+new Intl.DateTimeFormat('en-US',{dateStyle:'long',timeZone:'UTC'}).format(new Date(entry.date+'T00:00:00Z'));
  const source=element('a','','Logo source'),url=new URL(entry.source);
  if(url.protocol!=='https:')throw new Error('Invalid source URL');
  source.href=url.href;meta.append(date,source);article.append(head,details,meta);
  return article;
}
// Keep the embedded report visible if offline, scripts disabled, or registry fetch fails.
(async()=>{
  try{
    const response=await fetch('../data/compatibility.json');
    if(!response.ok)throw new Error('Registry unavailable');
    const entries=await response.json();
    if(!Array.isArray(entries))throw new Error('Invalid registry');
    const cards=entries.map(deviceCard);
    document.querySelector('#entries').replaceChildren(...(cards.length?cards:[element('p','','No device issues listed yet.')]));
  }catch(error){console.warn('Compatibility registry: using embedded report.',error);}
})();

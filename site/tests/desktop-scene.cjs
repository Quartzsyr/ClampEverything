const {chromium,webkit}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await(process.env.ENGINE==='webkit'?webkit:chromium).launch();
 const page=await browser.newPage({viewport:{width:1440,height:1000},reducedMotion:'reduce'}),errors=[];
 page.on('pageerror',error=>errors.push(error.message));
 await page.route('https://api.github.com/**',r=>r.fulfill({status:403,body:'{}'}));
 const base=process.env.SITE_URL||'http://127.0.0.1:5173/';
 async function ready(){await page.locator('.app-safari iframe').waitFor();await page.locator('.app-notes .notes-page').waitFor();}
 async function menu(action){await page.locator('[data-action=system-menu]').click();await page.locator(`[data-system-action=${action}]`).click();}
 async function trashCode(){await page.locator('[data-source=desktop-code]').click({button:'right'});await page.getByRole('menuitem',{name:'移到废纸篓',exact:true}).click();await page.locator('[data-source=desktop-code]').waitFor({state:'detached'});}
 try{
  // Upgrade from the previous persistent Trash format must also restore files.
  await page.goto(base);await ready();
  await page.evaluate(()=>localStorage.setItem('clamp-trash-files',JSON.stringify({hidden:['photo','code'],entries:['photo']})));
  await page.reload();await ready();
  assert.equal(await page.locator('.desktop-file').count(),10);
  assert.equal(await page.locator('.menu-right button,.menu-right img').count(),0,'only the left clip logo opens the app menu');
  for(const app of ['messages','safari','notes','quicktime'])assert.equal(await page.locator(`.app-${app}`).isVisible(),true);
  const notes=page.locator('.notes-page'),originalNoteID=await notes.getAttribute('data-file-id');await notes.fill('刷新后保留的旅行计划');
  await page.waitForFunction(previous=>document.querySelector('.notes-page').dataset.fileId!==previous&&document.querySelector('[data-source=desktop-note]').dataset.fileId===document.querySelector('.notes-page').dataset.fileId,originalNoteID);
  const noteID=await notes.getAttribute('data-file-id');
  const icon=page.locator('[data-source=desktop-code]'),r=await icon.boundingBox(),dock=await page.locator('#app-dock').boundingBox();
  await page.mouse.move(r.x+40,r.y+25);await page.mouse.down();await page.mouse.move(dock.x+dock.width-65,dock.y+30,{steps:10});await page.mouse.up();
  await page.locator('[data-dock-file="desktop:code"]').waitFor();
  await trashCode();await menu('desktop');
  assert.equal(await page.locator('.desktop-file').count(),10);
  assert.equal(await notes.getAttribute('data-file-id'),noteID,'menu recovery leaves the editor intact');
  assert.equal(await page.locator('[data-dock-file="desktop:code"]').count(),1);
  await trashCode();await page.locator('[data-app=trash]').click();await page.locator('[data-trash-empty]').click();
  await page.reload();await ready();
  assert.equal(await page.locator('.desktop-file').count(),10,'even emptied desktop files return on reload');
  assert.equal(await notes.innerText(),'刷新后保留的旅行计划');
  assert.equal(await notes.getAttribute('data-file-id'),noteID);
  assert.equal(await page.locator('[data-dock-file="desktop:code"]').count(),1);
  await page.locator('[data-app=trash]').click();assert.equal(await page.locator('.trash-row').count(),0);
  await page.locator('.app-trash [data-window-control=close]').click();
  await page.locator('.app-quicktime [data-player-action=play]').click();
  await page.waitForFunction(()=>document.querySelector('.app-quicktime video').currentTime>.1);
  await page.locator('.app-quicktime [data-player-action=play]').click();
  for(const [width,height] of [[1764,1100],[1440,1000],[1280,800],[1024,768],[390,844],[320,640]]){
   await page.setViewportSize({width,height});await page.reload();await ready();
   const windows=await page.locator('.app-window').evaluateAll(es=>es.map(e=>({app:e.dataset.window,...e.getBoundingClientRect().toJSON()})));
   assert.equal(windows.length,4);
   for(const r of windows){assert.ok(r.x>=0&&r.right<=width+1);assert.ok(r.y>=36&&r.bottom<height-75,`${r.app} clears the Dock at ${width}×${height}`);}
   if(width>=1280){
    for(let a=0;a<windows.length;a++)for(let b=a+1;b<windows.length;b++){const A=windows[a],B=windows[b];assert.ok(A.right<=B.left||B.right<=A.left||A.bottom<=B.top||B.bottom<=A.top,'desktop windows have clear separation');}
    assert.ok(windows.find(r=>r.app==='safari').width>620,'the download browser is larger');
    const files=await page.locator('.desktop-file').evaluateAll(es=>es.map(e=>{const r=e.getBoundingClientRect();return document.elementFromPoint(r.x+r.width/2,r.y+25)?.closest('.desktop-file')===e;}));
    assert.ok(files.every(Boolean),'default windows leave every desktop file accessible');
   }
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
  }
  await page.setViewportSize({width:1440,height:1000});await page.reload();await ready();
  await page.frameLocator('.app-safari iframe').locator('h1').waitFor();
  await page.screenshot({path:'/private/tmp/clamp-desktop-scene.png'});
  await menu('settings');await page.locator('#motion-setting').waitFor();
  assert.deepEqual(errors,[]);
  console.log('PASS: one left app menu, menu/reload desktop recovery, edited text and Dock preservation, four default app windows, actual video playback, clear desktop layout and responsive bounds');
 }catch(error){await page.screenshot({path:'/private/tmp/clamp-desktop-scene-failure.png'});throw error;}finally{await browser.close();}
})();

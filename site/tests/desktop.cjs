const {chromium,webkit}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await (process.env.ENGINE==='webkit'?webkit:chromium).launch();
 const page=await browser.newPage({viewport:{width:1440,height:1000},permissions:process.env.ENGINE==='webkit'?[]:['clipboard-read','clipboard-write']});const errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 // Stable fixture: rate limits belong to releases.cjs's explicit fallback test.
 await page.route('https://api.github.com/repos/Quartzsyr/ClampEverything/releases**',route=>route.fulfill({status:403,contentType:'application/json',body:'{"message":"rate limit"}'}));
 const url=process.env.SITE_URL||'http://127.0.0.1:5173/';
 async function capture(selector,x,y){const r=await page.locator(selector).boundingBox();await page.mouse.move(r.x+20,r.y+20);await page.keyboard.down('Alt');await page.waitForTimeout(330);await page.mouse.down();await page.mouse.move(x,y,{steps:5});await page.mouse.up();await page.waitForTimeout(650);await page.keyboard.up('Alt');}
 try{
  await page.goto(url);await page.locator('[data-source=desktop-photo]').waitFor();await page.waitForTimeout(400);
  for(const width of [1440,1024,700,390,320]){
   await page.setViewportSize({width,height:1000});
   for(const app of ['finder','notes','trash']){
    await page.locator(`[data-app=${app}]`).hover();await page.waitForTimeout(240);
    const rects=await page.locator('#app-dock>button svg,#app-dock>button img').evaluateAll(icons=>icons.map(el=>{const r=el.getBoundingClientRect();return {left:r.left,right:r.right};}));
    for(let i=1;i<rects.length;i++)assert.ok(rects[i].left-rects[i-1].right>=3,`no Dock overlap at ${width}`);
    assert.equal(await page.locator('.dock-tooltip:visible').count(),1);assert.equal(await page.locator('#app-dock button[title]').count(),0);
    assert.ok(rects[0].left>=0&&rects.at(-1).right<=width);
   }
  }
  await page.setViewportSize({width:1440,height:1000});await page.waitForTimeout(250);
  // Place an actual file on a free desktop position; a drag must not open it.
  const icon=page.locator('[data-source=desktop-photo]'),r=await icon.boundingBox();
  await page.mouse.move(r.x+45,r.y+30);await page.mouse.down();await page.mouse.move(1100,710,{steps:8});await page.mouse.up();
  const after=await icon.boundingBox();assert.ok(Math.abs(after.x-(1100-45))<2);assert.equal(await page.locator('.desktop-drag-ghost').count(),0);assert.equal(await page.locator('.app-photos').count(),0);
  await page.reload();await icon.waitFor();const saved=await icon.boundingBox();assert.ok(Math.abs(after.x-saved.x)<2&&Math.abs(after.y-saved.y)<2,'icon positions survive reload');
  await icon.dblclick();await page.locator('.app-photos').waitFor();
  const image=page.locator('[data-source=photo-open] img');await image.hover();await page.keyboard.down('Alt');await page.waitForTimeout(340);assert.equal(await page.locator('#target-glow').getAttribute('data-style'),'image');assert.equal(await page.locator('#target-glow rect').count(),1);await page.keyboard.up('Alt');await page.locator('.app-photos [data-window-control=close]').click();
  for(const [kind,style,shape] of [['folder','folder','rect'],['document','file','path']]){await page.locator(`[data-source=desktop-${kind}]`).hover();await page.keyboard.down('Alt');await page.waitForTimeout(340);assert.equal(await page.locator('#target-glow').getAttribute('data-style'),style);assert.equal(await page.locator(`#target-glow ${shape}`).count(),1);await page.keyboard.up('Alt');}

  await page.locator('[data-app=messages]').click();
  const photoPosition=await icon.boundingBox(),compose=await page.locator('.message-compose').boundingBox();await page.mouse.move(photoPosition.x+45,photoPosition.y+30);await page.mouse.down();await page.mouse.move(compose.x+60,compose.y+20,{steps:8});await page.mouse.up();assert.equal(await page.locator('.message-draft img').count(),1,'dragging a desktop file into Messages creates an attachment draft');await page.locator('[data-clear-draft]').click();assert.deepEqual(await icon.boundingBox(),photoPosition,'cross-app copy retains desktop placement');
  const input=page.locator('.compose-input');await input.fill('下周去海边\n记得带相机');await input.press('Shift+Enter');await input.type('还有一本书');await page.locator('[data-send-text]').click();
  const sent=page.locator('.message.sent[data-source-kind=note]');await sent.waitFor();assert.match(await sent.innerText(),/还有一本书/);assert.equal(await input.count(),1);assert.equal(await input.inputValue(),'');
  const sentID=await sent.getAttribute('data-file-id');assert.match(sentID,/^[a-f0-9]{64}$/);
  // Per-line text glow uses native gold background, dims on motion and clears.
  const text=page.locator('[data-source=message-note]'),tr=await text.boundingBox();await text.scrollIntoViewIfNeeded();const t=await text.boundingBox();
  await page.mouse.move(t.x+25,t.y+20);await page.keyboard.down('Alt');await page.waitForTimeout(340);
  assert.equal(await page.locator('#target-glow').getAttribute('data-style'),'text');assert.ok(await page.locator('#target-glow rect').count()>=3);
  assert.match(await page.locator('#target-glow').getAttribute('class'),/visible/);
  const lineWidth=await page.locator('#target-glow rect').first().getAttribute('width');assert.ok(Number(lineWidth)<t.width,'text follows glyph lines rather than the message bubble');
  await page.screenshot({path:'/private/tmp/clamp-desktop-glow.png'});
  await page.mouse.move(t.x+35,t.y+20);assert.match(await page.locator('#target-glow').getAttribute('class'),/moving/);await page.waitForTimeout(320);assert.doesNotMatch(await page.locator('#target-glow').getAttribute('class'),/moving/);
  await page.mouse.move(800,800);assert.doesNotMatch(await page.locator('#target-glow').getAttribute('class'),/visible/);await page.keyboard.up('Alt');
  await sent.scrollIntoViewIfNeeded();await capture('.message.sent[data-source-kind=note]',1120,750);
  const pinned=page.locator('.native-object[data-file-kind=note]').last();assert.equal(await pinned.getAttribute('data-file-id'),sentID);assert.match(await pinned.locator('.edited-note-text').innerText(),/还有一本书/);assert.match(await pinned.locator('.expanded-state img').getAttribute('src'),/note-blank/);
  const download=page.waitForEvent('download');// Download the original File from the source menu.
  await page.locator('.message.sent[data-source-kind=note]').click({button:'right'});await page.getByRole('menuitem',{name:'下载原文件',exact:true}).click();const file=await download;const fs=require('node:fs/promises');assert.equal(await fs.readFile(await file.path(),'utf8'),'下周去海边\n记得带相机\n还有一本书');
  await page.locator('[data-app=notes]').click();const notes=page.locator('.notes-page');await notes.fill('我的新便笺\n真实文字，也可以夹取。');await page.waitForTimeout(180);const noteID=await notes.getAttribute('data-file-id');await capture('.notes-page',1030,300);assert.equal(await page.locator('.native-object').last().getAttribute('data-file-id'),noteID);assert.equal(await page.locator('.native-object').last().locator('.edited-note-text').innerText(),'我的新便笺\n真实文字，也可以夹取。');
  await page.locator('[data-app=finder]').click();await page.locator('.finder-search').fill('pdf');assert.equal(await page.locator('.finder-row:visible').count(),1);
  await page.locator('.finder-search').fill('');assert.equal(await page.locator('.finder-row:visible').count(),10);
  await page.locator('.app-finder [data-window-control=close]').click();
  await page.locator('[data-app=notes]').hover();await page.waitForTimeout(240);await page.screenshot({path:'/private/tmp/clamp-desktop-refined.png'});
  assert.deepEqual(errors,[]);console.log('PASS: Dock spacing at five widths, single tooltip, file reposition/reload/open, editable messages and notes, real TXT download/capture, native per-line glow and movement dwell, Finder search');
 }finally{await browser.close();}
})();

const {chromium,webkit}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await(process.env.ENGINE==='webkit'?webkit:chromium).launch();
 console.log('browser ready');const page=await browser.newPage({viewport:{width:1440,height:1000},reducedMotion:'reduce'}),errors=[],requests=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.route('https://api.github.com/**',r=>r.fulfill({status:403,body:'{}'}));
 const base=process.env.SITE_URL||'http://127.0.0.1:5173/';
 let releaseMovie,releasePDF,releaseWord;const movieGate=new Promise(resolve=>releaseMovie=resolve),pdfGate=new Promise(resolve=>releasePDF=resolve),wordGate=new Promise(resolve=>releaseWord=resolve);
 await page.route('**/assets/files/**',async route=>{const path=decodeURIComponent(new URL(route.request().url()).pathname);requests.push(path);if(path.endsWith('.mov'))await movieGate;if(path.endsWith('.pdf'))await pdfGate;if(path.endsWith('.docx'))await wordGate;await route.continue();});
 const capture=async(selector,x,y)=>{const r=await page.locator(selector).boundingBox();await page.mouse.move(r.x+30,r.y+25);await page.keyboard.down('Alt');await page.mouse.down();await page.mouse.move(x,y,{steps:5});await page.mouse.up();await page.keyboard.up('Alt');};
 try{
  await page.goto(base,{waitUntil:'domcontentloaded'});console.log('desktop navigation');await page.locator('body:not(.load-pending) .app-safari').waitFor({timeout:10000});
  await page.waitForTimeout(350);
  assert.equal(await page.locator('.app-window').count(),4);
  assert.equal(await page.locator('.desktop-file').count(),11);
  assert.ok(!requests.some(path=>/\.(mov|wav|png|jpg|pdf|docx|zip|swift|txt|json)$/i.test(path)&&!path.endsWith('catalog.json')),'no original assets downloaded before interaction: '+requests.join(','));
  assert.equal(await page.locator('.app-quicktime video').getAttribute('src'),null);
  assert.ok(await page.locator('[data-install-disk]').isVisible());
  console.log('no original downloads at startup');
  // Single selection does not initiate a DMG download. Double click opens a real installation guide.
  await page.locator('[data-install-disk]').click();assert.equal(await page.locator('[data-window=installer]').count(),0);
  await page.locator('[data-install-disk]').dblclick();await page.locator('[data-window=installer]').waitFor();
  const installer=page.locator('[data-window=installer]');assert.match(await installer.textContent(),/macOS 14/);assert.match(await installer.textContent(),/Apple Silicon/);assert.match(await installer.textContent(),/尚未经过 Apple 公证/);
  const link=installer.locator('[data-install-download]');assert.match(await link.getAttribute('href'),/releases\/download\/v1\.7\.16\/ClampEverything-1\.7\.16-arm64\.dmg$/);
  await page.screenshot({path:'/private/tmp/clamp-installer-'+(process.env.ENGINE||'chromium')+'.png'});
  // Intercept navigation to verify the actual download endpoint without downloading the DMG in CI.
  if(process.env.ENGINE==='webkit'){
   // WebKit's synthetic intercepted attachment response does not emit a download
   // event. Check native anchor activation without navigating away from the test.
   await link.evaluate(el=>el.addEventListener('click',event=>{el.dataset.requestedURL=el.href;event.preventDefault();},{once:true}));await link.click();assert.match(await link.evaluate(el=>el.dataset.requestedURL),/ClampEverything-1\.7\.16-arm64\.dmg$/);
  }else{
   let dmgURL;await page.route('https://github.com/**/releases/download/**',async route=>{dmgURL=route.request().url();await route.fulfill({status:200,headers:{'Content-Disposition':'attachment; filename=test-only.dmg','Content-Type':'application/octet-stream'},body:'browser download interception'});});
   const downloadEvent=page.waitForEvent('download');await link.click();await downloadEvent;assert.match(dmgURL,/ClampEverything-1\.7\.16-arm64\.dmg$/);
  }
  await page.waitForFunction(()=>document.querySelector('#demo-status')?.textContent.includes('已开始下载安装包'));console.log('download endpoint verified');
  await installer.locator('[data-window-control=close]').click();
  // Hover starts one delayed request. Playing while it is pending uses it rather than a second download.
  await page.locator('[data-source=desktop-video]').hover();await page.waitForTimeout(250);assert.equal(requests.filter(p=>p.endsWith('.mov')).length,1);
  await page.locator('.app-quicktime [data-player-action=play]').click();assert.equal(await page.locator('.app-quicktime [data-player-action=play]').getAttribute('aria-busy'),'true');
  assert.equal(requests.filter(p=>p.endsWith('.mov')).length,1);releaseMovie();
  console.log('movie bytes released');await page.waitForFunction(()=>{const v=document.querySelector('.app-quicktime video');return v?.currentSrc.startsWith('blob:')&&!v.paused&&v.currentTime>0;},null,{timeout:25000});
  await page.locator('.app-quicktime [data-player-action=play]').click();
  console.log('movie playback verified');
  // A first PDF capture can be released before the bytes arrive; it completes once, automatically.
  await capture('[data-source=desktop-document]',1060,610);await page.waitForTimeout(250);assert.equal(await page.locator('[data-file-kind=document]').count(),0);releasePDF();
  await page.locator('[data-file-kind=document] .expanded-state').waitFor({timeout:15000});assert.equal(await page.locator('[data-file-kind=document]').count(),1);
  // Escape while an original is delayed cancels the gesture, including after release.
  await capture('[data-source=desktop-word]',1080,380);await page.keyboard.press('Escape');releaseWord();await page.waitForTimeout(350);assert.equal(await page.locator('[data-file-kind=word]').count(),0);
  await page.screenshot({path:'/private/tmp/clamp-lazy-'+(process.env.ENGINE||'chromium')+'.png'});
  assert.deepEqual(errors,[]);console.log('PASS: no eager originals, four initial windows, installation disk/requirements/real DMG link, hover + play deduplication, real movie playback and first-attempt deferred PDF capture');
 }catch(error){await page.screenshot({path:'/private/tmp/clamp-lazy-failure-'+(process.env.ENGINE||'chromium')+'.png'});throw error;}
 finally{releaseMovie();releasePDF();releaseWord();await browser.close();}
})().catch(error=>{console.error(error);process.exit(1)});

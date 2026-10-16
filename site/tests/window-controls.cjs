const {chromium,webkit}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await(process.env.ENGINE==='webkit'?webkit:chromium).launch(),page=await browser.newPage({viewport:{width:1440,height:1000},reducedMotion:'reduce'}),errors=[];
 page.on('pageerror',error=>errors.push(error.message));await page.route('https://api.github.com/**',r=>r.fulfill({status:403,body:'{}'}));
 const base=process.env.SITE_URL||'http://127.0.0.1:5173/';
 async function dot(app,on){await page.waitForFunction(({app,on})=>document.querySelector(`[data-app=${app}]`)?.classList.contains('active')===on,{app,on});assert.equal(await page.locator(`[data-app=${app}]`).getAttribute('aria-pressed'),String(on));}
 async function edge(selector,right=false,bottom=false){const el=page.locator(selector);await el.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));const r=await el.boundingBox();assert.ok(r.width>=25.9&&r.height>=29.9,`traffic light has a generous actual button target: ${JSON.stringify(r)}`);assert.equal(await el.evaluate(e=>getComputedStyle(e,'::before').width),'12px','the visible colored lens stays small');const point={x:right?r.x+r.width-1:r.x+1,y:bottom?r.y+r.height-1:r.y+1};assert.equal(await page.evaluate(({point,selector})=>document.elementFromPoint(point.x,point.y)?.closest(selector)===document.querySelector(selector),{point,selector}),true,'outer target beats the resize handles');await page.mouse.click(point.x,point.y);}
 async function openMenu(action){await page.locator('[data-action=system-menu]').click();await page.locator(`[data-system-action=${action}]`).click();}
 try{
  await page.goto(base);await page.locator('.app-safari').waitFor();
  for(const app of ['messages','safari','notes','quicktime'])await dot(app,true);
  for(const app of ['finder','trash','clamp'])await dot(app,false);
  const original=await page.locator('.app-safari').boundingBox();
  await edge('.app-safari [data-window-control=zoom]',true);assert.ok((await page.locator('.app-safari').boundingBox()).width>original.width);
  await edge('.app-safari [data-window-control=zoom]',false,true);assert.equal((await page.locator('.app-safari').boundingBox()).width,original.width);
  await edge('.app-safari [data-window-control=minimize]');await page.locator('.app-safari').waitFor({state:'hidden'});await dot('safari',true);
  await page.locator('[data-app=safari]').click();await page.locator('.app-safari').waitFor();
  await edge('.app-safari [data-window-control=close]',true,true);await page.locator('.app-safari').waitFor({state:'detached'});await dot('safari',false);
  await page.locator('[data-app=safari]').click();await dot('safari',true);await edge('.app-safari [data-window-control=close]');await dot('safari',false);
  for(const app of ['messages','notes','quicktime']){await edge(`.app-${app} [data-window-control=close]`,true);await page.locator(`.app-${app}`).waitFor({state:'detached'});await dot(app,false);}
  assert.equal(await page.locator('#app-dock .active').count(),0);
  // Two windows sharing Preview keep a dot until the last one closes.
  await page.locator('[data-source=desktop-document]').dblclick();await page.locator('[data-window=document-document]').waitFor();
  await page.locator('[data-source=desktop-word]').dblclick();await page.locator('[data-window=document-word]').waitFor();await dot('document',true);
  await edge('[data-window=document-word] [data-window-control=close]');await page.locator('[data-window=document-word]').waitFor({state:'detached'});await dot('document',true);
  await edge('[data-window=document-document] [data-window-control=close]',true,true);await dot('document',false);
  // Panels share the same activity semantics, including native Escape dismissal.
  await openMenu('settings');await dot('clamp',true);
  await edge('[data-panel-control=zoom]',true);await edge('[data-panel-control=zoom]',false,true);
  await edge('[data-panel-control=minimize]',true,true);await page.locator('dialog').waitFor({state:'hidden'});await dot('clamp',true);
  await page.locator('[data-app=clamp]').click();await page.locator('dialog').waitFor();await edge('[data-panel-control=close]');await dot('clamp',false);
  await openMenu('help');await dot('clamp',true);await page.keyboard.press('Escape');await dot('clamp',false);
  await page.locator('[data-app=clamp]').click();await dot('clamp',true);await page.mouse.click(8,500);await dot('clamp',false);
  await page.locator('[data-app=trash]').click();await dot('trash',true);await edge('.app-trash [data-window-control=close]');await dot('trash',false);
  await page.locator('[data-app=finder]').click();await dot('finder',true);await edge('.app-finder [data-window-control=close]');await dot('finder',false);
  // Touch devices get still larger targets without enlarging the colored circles.
  const touch=await browser.newContext({viewport:{width:390,height:844},hasTouch:true,isMobile:true,reducedMotion:'reduce'}),mobile=await touch.newPage();
  await mobile.route('https://api.github.com/**',r=>r.fulfill({status:403,body:'{}'}));await mobile.goto(base);await mobile.locator('.app-safari').waitFor();
  const button=mobile.locator('.app-safari [data-window-control=close]'),r=await button.boundingBox();assert.ok(r.width>=32&&r.height>=36);await mobile.touchscreen.tap(r.x+2,r.y+2);await mobile.locator('.app-safari').waitFor({state:'detached'});assert.equal(await mobile.locator('[data-app=safari]').getAttribute('aria-pressed'),'false');await touch.close();
  assert.deepEqual(errors,[]);console.log('PASS: Dock dots follow actual windows, reopen/minimize/multiple windows/panel dismissal, enlarged traffic-light edge hits, resize handle priority, fixed lens size and touch targets');
 }catch(error){await page.screenshot({path:'/private/tmp/clamp-window-controls-failure.png'});throw error;}finally{await browser.close();}
})();

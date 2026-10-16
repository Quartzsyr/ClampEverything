// Reproducible screenshots of real browser gestures and original fixture files.
// PLAYWRIGHT_MODULE=/path/to/playwright node site/scripts/capture-usage.cjs
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const sharp=require(process.env.PLAYWRIGHT_MODULE?process.env.PLAYWRIGHT_MODULE.replace(/playwright$/,'sharp'):'sharp');
const fs=require('node:fs/promises'),path=require('node:path');
(async()=>{const browser=await chromium.launch(),page=await browser.newPage({viewport:{width:1280,height:850},reducedMotion:'reduce'});
const output=path.resolve('site/assets/usage');await fs.mkdir(output,{recursive:true});
await page.route('https://api.github.com/**',r=>r.fulfill({status:403,body:'{}'}));
async function ready(){await page.goto(process.env.SITE_URL||'http://127.0.0.1:5173/');await page.locator('[data-source=desktop-photo]').waitFor();await page.locator('.app-safari [data-window-control=minimize]').click();await page.waitForTimeout(250);}
async function capture(selector,x,y){const r=await page.locator(selector).boundingBox();await page.mouse.move(r.x+35,r.y+25);await page.keyboard.down('Alt');await page.mouse.down();await page.mouse.move(x,y,{steps:8});await page.mouse.up();await page.waitForTimeout(350);await page.keyboard.up('Alt');}
async function shot(name,clip){const png=await page.screenshot({clip});await sharp(png).webp({quality:90}).toFile(path.join(output,name+'.webp'));}
try{
 await ready();await capture('[data-source=message-note]',580,190);const r=await page.locator('[data-source=message-note]').boundingBox();await page.mouse.move(r.x+32,r.y+32);await page.keyboard.down('Alt');await page.waitForTimeout(350);await shot('text-pickup',{x:30,y:100,width:900,height:570});await page.keyboard.up('Alt');
 await page.reload();await page.locator('[data-source=desktop-document]').waitFor();for(const app of ['safari','messages'])await page.locator(`.app-${app} [data-window-control=minimize]`).click();
 await capture('[data-source=desktop-document]',300,125);await capture('[data-source=desktop-word]',675,150);await page.locator('[data-file-kind=document] [data-page="1"]').click();await page.waitForTimeout(450);await page.mouse.move(950,60);await shot('documents',{x:180,y:65,width:800,height:535});
 await page.reload();await page.locator('[data-source=desktop-photo]').waitFor();for(const app of ['safari','messages'])await page.locator(`.app-${app} [data-window-control=minimize]`).click();
 await capture('[data-source=desktop-photo]',12,120);await capture('[data-source=desktop-document]',12,410);await page.mouse.move(900,80);await page.waitForTimeout(600);await page.locator('[data-file-kind=photo] .move-grip').hover();await page.waitForTimeout(350);await shot('edge-unfold',{x:0,y:40,width:650,height:550});
 const manifest={method:'Unretouched Playwright screenshots of real Option pointer-down, drag and release, native CardSurface sprites and original TXT/PDF/DOCX/PNG files; no generated UI or personal content',viewport:{width:1280,height:850},files:['text-pickup.webp','documents.webp','edge-unfold.webp'],reproduce:'Start site/ on localhost:5173, run site/scripts/capture-usage.cjs'};await fs.writeFile(path.join(output,'provenance.json'),JSON.stringify(manifest,null,2)+'\n');
 console.log('Captured three actual desktop interaction scenes.');
}finally{await browser.close();}})();

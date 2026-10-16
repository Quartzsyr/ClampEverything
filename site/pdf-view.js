// Render the actual PDF bytes instead of depending on a browser PDF plug-in.
// PDF.js 5.6.205 (Apache-2.0), vendored locally with its worker and license.
// API: https://mozilla.github.io/pdf.js/examples/
export async function renderPDF(container, file, textPreview) {
  const pdfjs = await import('./assets/vendor/pdfjs/pdf.min.mjs');
  pdfjs.GlobalWorkerOptions.workerSrc = new URL('./assets/vendor/pdfjs/pdf.worker.min.mjs', import.meta.url).href;
  const pdf = await pdfjs.getDocument({data:new Uint8Array(await file.arrayBuffer())}).promise;
  container.replaceChildren();
  const observer=new ResizeObserver(entries=>{for(const {target,contentRect} of entries)target.style.setProperty('--total-scale-factor',contentRect.width/Number(target.dataset.pageWidth));});
  let recognized;
  if(textPreview){try{const response=await fetch(textPreview.url);if(response.ok){const data=await response.json();if(data.sourceSHA256===textPreview.sourceSHA256)recognized=data.pages;}}catch{/* The PDF original remains usable if the optional text index fails. */}}
  try {
    for (let i = 1; i <= pdf.numPages; i++) {
      if (!container.isConnected) break;
      const page = await pdf.getPage(i), viewport = page.getViewport({scale:1.5});
      const canvas = document.createElement('canvas');
      canvas.width = Math.ceil(viewport.width); canvas.height = Math.ceil(viewport.height);
      canvas.setAttribute('aria-label', `${file.name} 第 ${i} 页`);
      await page.render({canvasContext:canvas.getContext('2d'),viewport}).promise;
      const sheet=document.createElement('div');sheet.className='pdf-sheet';sheet.dataset.pageWidth=viewport.rawDims.pageWidth;
      const layer=document.createElement('div');layer.className='pdf-text-layer';
      sheet.append(canvas,layer);container.append(sheet);observer.observe(sheet);
      const content=await page.getTextContent();
      if(content.items.some(item=>item.str?.trim())){
        const textLayer=new pdfjs.TextLayer({textContentSource:content,container:layer,viewport});
        await textLayer.render();
        for(const span of textLayer.textDivs)span.classList.add('pdf-text-line');
      }else for(const line of recognized?.[i-1]||[]){
        const span=document.createElement('span');span.className='pdf-text-line';span.textContent=line.text;
        Object.assign(span.style,{left:`${line.x*100}%`,top:`${line.y*100}%`,width:`${line.width*100}%`,height:`${line.height*100}%`});
        const fontHeight=line.height*viewport.rawDims.pageHeight,measure=document.createElement('canvas').getContext('2d');
        measure.font=`${fontHeight}px ${getComputedStyle(layer).fontFamily}`;
        const measured=measure.measureText(line.text).width;
        span.style.setProperty('--font-height',`${fontHeight}px`);
        if(measured)span.style.setProperty('--scale-x',line.width*viewport.rawDims.pageWidth/measured);
        layer.append(span);
      }
    }
  } finally { await pdf.destroy();if(!container.isConnected)observer.disconnect(); }
  return ()=>observer.disconnect();
}

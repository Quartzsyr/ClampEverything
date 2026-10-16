// Render the actual PDF bytes instead of depending on a browser PDF plug-in.
// PDF.js 5.6.205 (Apache-2.0), vendored locally with its worker and license.
// API: https://mozilla.github.io/pdf.js/examples/
export async function renderPDF(container, file) {
  const pdfjs = await import('./assets/vendor/pdfjs/pdf.min.mjs');
  pdfjs.GlobalWorkerOptions.workerSrc = new URL('./assets/vendor/pdfjs/pdf.worker.min.mjs', import.meta.url).href;
  const pdf = await pdfjs.getDocument({data:new Uint8Array(await file.arrayBuffer())}).promise;
  container.replaceChildren();
  try {
    for (let i = 1; i <= pdf.numPages; i++) {
      if (!container.isConnected) break;
      const page = await pdf.getPage(i), viewport = page.getViewport({scale:1.5});
      const canvas = document.createElement('canvas');
      canvas.width = Math.ceil(viewport.width); canvas.height = Math.ceil(viewport.height);
      canvas.setAttribute('aria-label', `${file.name} 第 ${i} 页`);
      await page.render({canvasContext:canvas.getContext('2d'),viewport}).promise;
      container.append(canvas);
    }
  } finally { await pdf.destroy(); }
}

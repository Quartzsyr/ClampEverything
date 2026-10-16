// Publish a usable snapshot for first paint, offline viewing and native exports.
// An optional build-only token stays in memory and is never copied into assets.
import {readFile,writeFile} from 'node:fs/promises';
import {fetchReleases,summaryHTML,historyHTML,date} from '../assets/release-data.js';
const htmlURL=new URL('../assets/files/field-notes.html',import.meta.url);
const dataURL=new URL('../assets/releases.json',import.meta.url);
let model;
try{model=await fetchReleases({headers:process.env.GH_TOKEN?{Authorization:`Bearer ${process.env.GH_TOKEN}`}:{}});await writeFile(dataURL,JSON.stringify(model,null,2)+'\n');}
catch{model=JSON.parse(await readFile(dataURL,'utf8'));process.stdout.write('GitHub unavailable; retaining the last verified release snapshot.\n');}
let html=await readFile(htmlURL,'utf8');
function replace(name,value){const pattern=new RegExp(`<!-- ${name}:start -->[\\s\\S]*?<!-- ${name}:end -->`);if(!pattern.test(html))throw new Error(`Missing ${name} marker`);html=html.replace(pattern,`<!-- ${name}:start -->${value}<!-- ${name}:end -->`);}
replace('release-summary',summaryHTML(model));replace('release-list',historyHTML(model));replace('release-status',`上次同步 · ${date(model.fetchedAt)}`);replace('release-data',`<script type="application/json" id="release-data">${JSON.stringify(model).replace(/</g,'\\u003c')}</script>`);
await writeFile(htmlURL,html);process.stdout.write(`Prepared ${model.releases.length} public release versions.\n`);

// Run after the scoped native media/editor-stock exports. Supply SHARP_MODULE
// when sharp is provided by a bundled runtime rather than a local installation.
const fs=require('node:fs/promises'),path=require('node:path'),sharp=require(process.env.SHARP_MODULE||'sharp');
(async()=>{const root=path.join(__dirname,'../assets/native'),manifest=JSON.parse(await fs.readFile(path.join(root,'manifest.json')));
for(const item of manifest.items.filter(i=>['photo','video','group'].includes(i.kind))){for(const field of ['left','right','compactLeft','compactRight','source']){
 const suffix=field==='compactLeft'?'compact-left':field==='compactRight'?'compact-right':field,old=`${item.kind}-${suffix}.png`,input=path.join(root,old);
 if(item.kind==='photo'&&field==='source'){item[field]='../files/山间湖泊.png';await fs.rm(input,{force:true});continue;}
 try{await fs.access(input);}catch{continue;}
 const next=old.replace(/\.png$/,'.webp');await sharp(input).webp({quality:95}).toFile(path.join(root,next));item[field]=next;await fs.unlink(input);
}}
for(const kind of ['code','word'])for(const side of ['left','right']){const name=`${kind}-blank-${side}`,input=path.join(root,name+'.png');try{await fs.access(input);}catch{continue;}await sharp(input).webp({quality:95}).toFile(path.join(root,name+'.webp'));await fs.unlink(input);}
await fs.writeFile(path.join(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');})();

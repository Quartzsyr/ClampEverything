let blank;
export async function textPreview(item,nativeURL){
  if(!blank){blank=new Image();blank.src=nativeURL('note-blank-left.webp');}
  await blank.decode();
  const canvas=document.createElement('canvas');canvas.width=520;canvas.height=342;
  const context=canvas.getContext('2d');context.drawImage(blank,94,152,520,342,0,0,520,342);context.scale(2,2);
  context.font='14px -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif';context.fillStyle='#343a37';context.textBaseline='top';
  context.save();context.beginPath();context.rect(18,26,224,127);context.clip();
  let y=26;
  for(const line of item.textContent.split('\n')){
    let row='';
    for(const char of line){if(context.measureText(row+char).width>224){context.fillText(row,18,y);y+=21;row='';}row+=char;}
    context.fillText(row,18,y);y+=21;
  }
  context.restore();item.source=canvas.toDataURL('image/png');return item;
}

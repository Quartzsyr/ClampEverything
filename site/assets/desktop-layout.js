// Coordinates are relative to the desktop below the 38px menu bar.
// Leave the right file columns and the bottom Dock free on desktop displays.
export function desktopScene(width,height){
 const bottom=Math.max(260,height-170),top=32,gap=22;
 if(width>=1180&&height>=800){
  const left=Math.round(Math.max(28,width*.035)),side=Math.round(Math.min(380,width*.25));
  const mainX=left+side+28,mainWidth=Math.min(960,width-244-mainX);
  const mainHeight=Math.round(Math.min(690,(bottom-top-gap)*.66));
  const lowerY=top+mainHeight+gap,lowerHeight=bottom-lowerY;
  const messageHeight=Math.min(560,mainHeight),noteY=top+messageHeight+gap;
  const movieWidth=Math.round(Math.min(mainWidth,440,Math.max(320,(lowerHeight-80)*16/9)));
  return {
   messages:{x:left,y:top,width:side,height:messageHeight},
   safari:{x:mainX,y:top,width:mainWidth,height:mainHeight},
   notes:{x:left,y:noteY,width:side,height:Math.min(340,bottom-noteY)},
   quicktime:{x:mainX+mainWidth-movieWidth,y:lowerY,width:movieWidth,height:lowerHeight}
  };
 }
 if(width>700){
  const left=24,side=Math.min(310,Math.round(width*.33)),mainX=left+side+18;
  const upper=Math.max(260,Math.round((bottom-top-gap)*.62)),lowerY=top+upper+gap;
  return {
   messages:{x:left,y:top,width:side,height:upper},
   safari:{x:mainX,y:top,width:width-mainX-20,height:upper},
   notes:{x:left,y:lowerY,width:side,height:Math.max(170,bottom-lowerY)},
   quicktime:{x:mainX,y:lowerY,width:Math.min(410,width-mainX-20),height:Math.max(170,bottom-lowerY)}
  };
 }
 // Small displays keep each title bar exposed, with the download page in front.
 const w=width-24,h=Math.max(200,Math.min(560,bottom-160));
 return {
  messages:{x:12,y:12,width:w,height:h},
  notes:{x:12,y:56,width:w,height:h},
  quicktime:{x:12,y:100,width:w,height:Math.min(320,h)},
  safari:{x:12,y:144,width:w,height:h}
 };
}

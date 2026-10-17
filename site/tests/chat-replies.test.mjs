import test from 'node:test';
import assert from 'node:assert/strict';
import {chooseReply} from '../assets/chat-replies.js';
test('conversation replies follow requests, include real attachment kinds and vary without network state',()=>{
 const counts=new Map();
 for(const [text,kind] of [['发张照片','photo'],['视频看看','video'],['PDF','document'],['给我 docx 计划','word'],['Swift 代码','code'],['文件夹','folder'],['录音','audio'],['ZIP 压缩包','archive'],['网页链接','web']]){
  const first=chooseReply(text,counts),second=chooseReply(text,counts);assert.equal(first[1].kind,kind);assert.notEqual(first[0].text,second[0].text);
 }
 assert.equal(chooseReply('谢谢')[0].text,'不客气，继续随手试试。');
 assert.match(chooseReply('支持什么')[0].text,/PDF.*Word/);
 assert.equal(chooseReply('怎么用')[1].kind,'document');assert.equal(chooseReply('发我指南')[1].kind,'document');assert.equal(chooseReply('发我素材包')[1].kind,'archive');assert.equal(chooseReply('JSON 清单')[1].kind,'file');
 assert.match(chooseReply('怎么复制')[0].text,/浏览器/);assert.match(chooseReply('怎么保存')[0].text,/浏览器/);assert.match(chooseReply('怎么撤销')[0].text,/撤销/);
 assert.equal(chooseReply('怎么用 发我指南').filter(item=>item.kind==='document').length,1);
 assert.equal(chooseReply('',counts,'word').length,1);
 assert.deepEqual(chooseReply('照片和视频都发我').slice(1),[{kind:'photo'},{kind:'video'}]);
 assert.equal(chooseReply('Word 文稿')[1].kind,'word');
});

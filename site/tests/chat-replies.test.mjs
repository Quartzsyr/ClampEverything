import test from 'node:test';
import assert from 'node:assert/strict';
import {chooseReply} from '../assets/chat-replies.js';
test('conversation replies follow requests, include real attachment kinds and vary without network state',()=>{
 const counts=new Map();
 for(const [text,kind] of [['发张照片','photo'],['视频看看','video'],['PDF','document'],['给我 docx 计划','word'],['Swift 代码','code'],['文件夹','folder'],['录音','audio'],['ZIP 压缩包','archive'],['网页链接','web']]){
  const first=chooseReply(text,counts),second=chooseReply(text,counts);assert.equal(first[1].kind,kind);assert.notEqual(first[0].text,second[0].text);
 }
 assert.equal(chooseReply('谢谢')[0].text,'不客气，喜欢就好。');
 assert.match(chooseReply('明天天气怎么样')[0].text,/预报/);
 assert.equal(chooseReply('',counts,'word').length,1);
 assert.deepEqual(chooseReply('照片和视频都发我').slice(1),[{kind:'photo'},{kind:'video'}]);
 assert.equal(chooseReply('Word 文稿')[1].kind,'word');
});

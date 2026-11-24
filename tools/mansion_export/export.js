(async()=>{const X=__X,T=X.THREE; const {GLTFExporter}=await import('/__export/gltf_exporter.js'); window.__NOBATCHPROPS=true; window.__MIRRORS=[[-7.73,12,"z"],[-7.73,16.5,"z"],[7.73,25.6,"z"],[-5.2,9.27,"x"],[5.2,9.27,"x"]]; X.S.collect=true; X.S.players="ffa"; X.buildMap("mansion"); const M=X.M;
const rm=[], hid=[]; let inv=0, swapped=0;
const isInv=o=>{const ms=Array.isArray(o.material)?o.material:[o.material]; return ms.every(m=>m.visible===false||(m.transparent&&m.opacity<=0.01));};
// many props are an invisible collider box carrying the visible pieces as children: keep the pieces under a plain node
const swap=o=>{const g=new T.Group(); g.name=o.name; g.position.copy(o.position); g.quaternion.copy(o.quaternion); g.scale.copy(o.scale); g.userData=o.userData; g.visible=o.visible; const p=o.parent, ix=p.children.indexOf(o); while(o.children.length) g.add(o.children[0]); p.children[ix]=g; g.parent=p; o.parent=null; swapped++; return g;};
const glassSet=new Set(M.boxes.filter(b=>b.prop==='glass'&&b.mesh).map(b=>b.mesh));
const toSwap=[]; M.group.traverse(o=>{ if(o.isMesh&&o.children.length&&(isInv(o)||glassSet.has(o))) toSwap.push(o); });
const swapMap=new Map(); for(const o of toSwap) swapMap.set(o, swap(o));
for(const b of M.boxes) if(b.mesh&&swapMap.has(b.mesh)) b.mesh=swapMap.get(b.mesh);

M.group.traverse(o=>{ if(o.isSprite||o.isLineSegments||o.isLight||o.isLine||o.isPoints||o.isInstancedMesh) rm.push(o); else if(o.isMesh){ if(!o.visible){const p=new T.Vector3();o.getWorldPosition(p);hid.push([o.geometry.type,p.x.toFixed(1),p.y.toFixed(1),p.z.toFixed(1)]);} const ms=Array.isArray(o.material)?o.material:[o.material]; if(ms.every(m=>m.visible===false||(m.transparent&&m.opacity<=0.01))){o.visible=false;inv++;} }});
for(const o of rm) o.parent&&o.parent.remove(o);
const boxes=M.boxes.map((b,i)=>{ if(b.mesh){ b.mesh.name='box_'+i+(b.prop?'_'+b.prop:''); if(b.prop==='glass'&&b.mesh.isMesh) b.mesh.visible=false;} return {b:[b.x0,b.y0,b.z0,b.x1,b.y1,b.z1].map(v=>+v.toFixed(3)),p:b.prop||'',hp:b.hp||0,m:b.mesh?1:0,see:b.see?1:0}; });
// name the moving parts so Godot can animate them
const lifts=M.ladders.filter(l=>l.lift); const named={};
const tag=(o,n)=>{o.name=n; named[n]=(named[n]||0)+1;};
for(const o of M.group.children){ if(!o.userData||!o.userData.dyn) continue; const p=o.position, g=o.geometry, mt=o.material;
  if(o.isGroup&&Math.abs(p.y)<.01&&o.children.length>=3&&lifts.some(l=>p.x>l.x0-1&&p.x<l.x1+1&&p.z>l.z0-1&&p.z<l.z1+1)) tag(o,'lift_car');
  else if(o.isGroup&&Math.abs(p.x+16)<6&&Math.abs(p.z-17)<6&&p.y>4) tag(o,'disco_beam');
  else if(o.isMesh&&g.type==='SphereGeometry'&&Math.abs(p.x+16)<.1&&Math.abs(p.z-17)<.1) tag(o,'disco_ball');
  else if(o.isMesh&&g.type==='PlaneGeometry'&&Math.abs(p.x+16)<.1&&Math.abs(p.z-17)<.1) tag(o,'disco_floor');
  else if(o.isMesh&&mt&&mt.color&&mt.color.getHex()===0x4fc3e6) tag(o,'pool_water');
  else if(o.isMesh&&g.type==='TorusGeometry'&&p.x>10&&p.x<22&&Math.abs(p.z)<6) tag(o,'pool_ring');
  else if(o.isMesh&&g.type==='CircleGeometry'&&Math.abs(p.y-.014)<.002) tag(o,'tramp_mat');
  else if(o.isMesh&&g.type==='ConeGeometry'&&Math.abs(p.x-32)<.1&&Math.abs(p.z)<.1) tag(o,'tramp_arrow');
}
M.group.traverse(o=>{ if(o.isMesh&&o.material&&o.material.map&&o.parent&&o.parent.parent===M.group&&o.material.transparent&&o.geometry.type==='PlaneGeometry'&&o.userData.dyn&&o.parent.children.length>=5) tag(o,'portal_swirl'); });
const full=M.boxes.map(b=>({b:[b.x0,b.y0,b.z0,b.x1,b.y1,b.z1].map(v=>+v.toFixed(3)),c:b.color||'#cccccc',g:b.color==='#bfe6ff'?1:0,v:b.alive?1:0,p:b.prop||'',s:b.see?1:0,hp:b.hp||0}));
const wins=M.dbg.WINS.map(w=>({ax:w.ax,at:+w.at.toFixed(3),a:+w.a.toFixed(3),b:+w.b.toFixed(3),s0:+w.s0.toFixed(3),s1:+w.s1.toFixed(3),pane:w.pane?M.boxes.indexOf(w.pane):-1}));
const doors=M.dbg.DOORS.map(d=>({x:+d.x.toFixed(3),z:+d.z.toFixed(3),y:d.y,ax:d.ax,w:+d.w.toFixed(3)}));
const TR=window.__TIDY_REPORT;
M.group.updateMatrixWorld(true);
const glb=await new GLTFExporter().parseAsync(M.group,{binary:true,onlyVisible:true,maxTextureSize:1024});
const u8=new Uint8Array(glb); let s=''; for(let i=0;i<u8.length;i+=32768) s+=String.fromCharCode.apply(null,u8.subarray(i,i+32768));
return {tidy:TR, full, wins, doors, spawns:M.spawns, ladders:M.ladders.map(l=>[l.x0,l.y0,l.z0,l.x1,l.y1,l.z1]), swapped, glb:btoa(s), size:u8.length, removed:rm.length, hid, inv, named, boxes, lifts};})()

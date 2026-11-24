// Test authored JavaScript as code. No browser, networking or native UI access.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=process.argv[2];assert(root,'Provide the desktop delivery directory');
const html=fs.readFileSync(path.join(root,'打开作品预览.html'),'utf8');
const source=html.match(/<script>([\s\S]*?)<\/script>/)[1];new vm.Script(source);
const vectorsPath=process.argv[3];
let draws=0;
const context2d={fillRect(...a){assert(a.every(Number.isFinite));draws++},strokeRect(...a){assert(a.every(Number.isFinite))}};
function element(){const classes=new Set();return {children:[],style:{},dataset:{},textContent:'',src:'',
 classList:{add(c){classes.add(c)},remove(c){classes.delete(c)},toggle(c,on){on?classes.add(c):classes.delete(c)}},
 append(v){this.children.push(v)},getContext(){return context2d},click(){this.onclick?.()},play(){return Promise.resolve()},pause(){}}}
const elements=new Map(),buttons=['up','left','reset','right','down','slower','faster','view'].map(c=>{const e=element();e.dataset.c=c;return e});
const keys={};let timer;
const sandbox={console,Math,Object,Array,Promise,setTimeout(){return 1},clearTimeout(){},setInterval(fn,ms){assert.equal(ms,5000);timer=fn;return 1},clearInterval(){},requestAnimationFrame(){},
 document:{getElementById(id){if(!elements.has(id))elements.set(id,element());return elements.get(id)},createElement:element,querySelectorAll(){return buttons},addEventListener(type,fn){keys[type]=fn}}};
vm.createContext(sandbox);vm.runInContext(source,sandbox);
const state=()=>JSON.parse(vm.runInContext('JSON.stringify({section,index,yaw,elev,rate,automatic})',sandbox));
assert.equal(elements.get('nav').children.length,5);
for(let n=0;n<4;n++){
 sandbox.enter(n);assert.equal(state().section,n);
 for(let i=0;i<7;i++){assert.match(elements.get('image').src,/_entrance\.gif$/);assert(fs.existsSync(path.join(root,elements.get('image').src)));elements.get('next').click()}
 assert.equal(state().index,1);elements.get('prev').click();assert.equal(state().index,0);
 elements.get('auto').click();assert(state().automatic);timer();assert.equal(state().index,1);elements.get('auto').click();
}
sandbox.enter(4);assert.deepEqual(state(),{section:4,index:0,yaw:12,elev:10,rate:3,automatic:false});
sandbox.animate(1000);sandbox.animate(1017);assert(draws>1000);assert.match(elements.get('status').textContent,/实时太阳系仪/);
for(let i=0;i<128;i++)sandbox.command('right');assert.equal(state().yaw,12);
for(let i=0;i<30;i++)sandbox.command('up');assert.equal(state().elev,15);
for(let i=0;i<30;i++)sandbox.command('down');assert.equal(state().elev,1);
for(let i=0;i<10;i++)sandbox.command('faster');assert.equal(state().rate,7);
for(let i=0;i<10;i++)sandbox.command('slower');assert.equal(state().rate,0);
sandbox.command('reset');assert.equal(state().rate,3);assert.equal(state().elev,10);
keys.keydown({key:'ArrowLeft',preventDefault(){}});assert.equal(state().yaw,11);
keys.keydown({key:'Enter',preventDefault(){}});assert.equal(state().elev,2);
elements.get('home').click();assert.equal(state().section,-1);assert.equal(elements.get('canvas').style.display,'none');
assert(fs.existsSync(path.join(root,elements.get('image').src)));
const geometry=JSON.parse(vm.runInContext('JSON.stringify({radii,sizes,palette})',sandbox));
assert.equal(geometry.radii.length,8);
assert.equal(geometry.sizes.length,9);
assert.equal(geometry.palette.length,32);
for(let i=0;i<8;i++){
 assert(geometry.radii[i]+geometry.sizes[i]+1<64,'Body must fit the canvas');
 if(i)assert(geometry.radii[i]>geometry.radii[i-1]);
}
let geometryCases=0,geometryPixels=0;
if(vectorsPath){
 const reference=JSON.parse(fs.readFileSync(vectorsPath,'utf8'));assert.equal(reference.width,128);assert.equal(reference.height,128);
 for(const c of reference.cases){
  assert.equal(c.canvas.length,16384);
  const actual=JSON.parse(vm.runInContext(`yaw=${c.azimuth};elev=${c.elevation};phases=${JSON.stringify(c.phases)};JSON.stringify(Array.from(renderCanvas()))`,sandbox));
  let mismatch=-1;for(let i=0;i<16384;i++)if(actual[i]!==c.canvas[i]){mismatch=i;break}
  assert.equal(mismatch,-1,`Python/JavaScript canvas mismatch yaw=${c.azimuth} elevation=${c.elevation}, address=${mismatch}`);
  geometryCases++;geometryPixels+=16384;
 }
 assert(geometryCases>=18,'Include multiple camera poses and collinear occlusions');
}
console.log(JSON.stringify({status:'passed',topic_images:24,topics:4,home_entries:5,four_direction_camera:true,rate_bounds:true,solid_shaded_spheres:true,independent_geometry_cases:geometryCases,independent_geometry_pixels:geometryPixels,software_canvas_draw_calls:draws,browser_ui_tested:false}));

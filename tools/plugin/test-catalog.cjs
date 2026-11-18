'use strict';
// Vendored from CKMud-2D-Desktop's scripts/ (no public remote, so CI can't fetch it). Keep in sync by
// copying the file over; don't edit it here.
// Local test plugin catalog with the same API as https://ckmud.com/plugins/api.php,
// for use with the app's temporary "Plugin catalog" option. Listens on this
// computer only.
//
//   node scripts/test-catalog.cjs <folder> [port]
//   CKMUD_TEST_CATALOG_PASSWORD=<password> enables "Unlock private".
//
// <folder>/*.xml are public plugins and <folder>/private/*.xml are private ones.
// The file name is the plugin id (lower case, digits and dashes, e.g.
// score-sheet.xml). Name, version and description come from the plugin's
// mud.plugin.register{...} call when present. The folder is re-read on every
// request, so edited files show up after Refresh.
const http=require('node:http'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const MAX=3*1024*1024,ID=/^[a-z][a-z0-9-]{1,63}$/;

// The last mud.plugin.register{...} call: plugins often test type(mud.plugin.register) first.
function declaration(text){let at=-1;for(const m of text.matchAll(/mud\.plugin\.register\s*[{(]/g))at=m.index;return at<0?'':text.slice(at,at+4000);}
function field(text,key){const m=new RegExp('\\b'+key+"\\s*=\\s*(['\"])((?:\\\\.|(?!\\1).)*)\\1").exec(text);return m?m[2].replace(/\\(.)/g,'$1'):null;}
function describe(file,visibility){
 const id=path.basename(file,'.xml'),bytes=fs.readFileSync(file),text=bytes.toString('utf8');
 const decl=declaration(text);
 return {id,name:(field(decl,'name')||id).slice(0,100),version:(field(decl,'version')||'0.0.0').slice(0,40),description:(field(decl,'description')||'').slice(0,1500),visibility,
  sha256:crypto.createHash('sha256').update(bytes).digest('hex'),size:bytes.length,revision:1,updatedAt:Math.floor(fs.statSync(file).mtimeMs/1000),filename:id+'.xml',file};
}
function scan(folder){
 const out=[];
 for(const [dir,visibility] of [[folder,'public'],[path.join(folder,'private'),'private']]){
  let names=[];try{names=fs.readdirSync(dir);}catch{continue;}
  for(const name of names.sort()){
   if(!name.endsWith('.xml'))continue;
   const id=path.basename(name,'.xml');
   if(!ID.test(id)){console.warn('Skipped '+name+': the id must be lower case letters, digits and dashes.');continue;}
   const p=describe(path.join(dir,name),visibility);
   if(p.size<32||p.size>MAX){console.warn('Skipped '+name+': size must be 32 bytes to 3 MB.');continue;}
   out.push(p);
  }
 }
 return out;
}

function createCatalogServer({folder,password=process.env.CKMUD_TEST_CATALOG_PASSWORD||''}){
 const tokens=new Set();
 const send=(res,status,value,type='application/json; charset=utf-8')=>{const body=Buffer.isBuffer(value)?value:Buffer.from(JSON.stringify(value));res.writeHead(status,{'content-type':type,'content-length':body.length,'cache-control':'no-store'});res.end(body);};
 const listing=(all,unlocked)=>({version:1,privateAccess:unlocked,plugins:all.filter(p=>p.visibility==='public'||unlocked).map(({file,...p})=>p)});
 return http.createServer((req,res)=>{
  const url=new URL(req.url,'http://localhost'),auth=/^Bearer ([a-f0-9]{64})$/.exec(req.headers.authorization||''),unlocked=!!auth&&tokens.has(auth[1]);
  let all;try{all=scan(folder);}catch(e){return send(res,500,{error:'Catalog folder unreadable: '+e.message});}
  if(req.method==='GET'){
   const id=url.searchParams.get('download');
   if(id===null)return send(res,200,listing(all,unlocked));
   const p=all.find(p=>p.id===id&&(p.visibility==='public'||unlocked));
   if(!p)return send(res,404,{error:'Plugin not found.'});
   console.log('Download '+p.id+' '+p.version);
   return send(res,200,fs.readFileSync(p.file),'application/xml; charset=utf-8');
  }
  if(req.method!=='POST')return send(res,405,{error:'Method not allowed.'});
  let body='';req.on('data',c=>{body+=c;if(body.length>4096)req.destroy();});
  req.on('end',()=>{
   let data;try{data=JSON.parse(body);}catch{return send(res,400,{error:'Invalid request.'});}
   if(data.action==='unlock'){
    const ok=password&&typeof data.password==='string'&&data.password.length===password.length&&crypto.timingSafeEqual(Buffer.from(data.password),Buffer.from(password));
    if(!ok)return send(res,401,{error:password?'Wrong password.':'Private access is not set up on this test catalog.'});
    const token=crypto.randomBytes(32).toString('hex');tokens.add(token);
    return send(res,200,{...listing(all,true),token});
   }
   if(data.action==='lock'){if(auth)tokens.delete(auth[1]);return send(res,200,{ok:true});}
   send(res,400,{error:'Unknown action.'});
  });
 });
}

if(require.main===module){
 const folder=path.resolve(process.argv[2]||'');const port=Number(process.argv[3]||8787);
 if(!process.argv[2]||!fs.existsSync(folder)){console.error('Usage: node scripts/test-catalog.cjs <folder> [port]');process.exit(1);}
 createCatalogServer({folder}).listen(port,'127.0.0.1',()=>{
  const found=scan(folder);
  console.log('Test plugin catalog: http://localhost:'+port+'/api.php');
  console.log(found.length+' plugin(s): '+found.map(p=>p.id+(p.visibility==='private'?' (private)':'')).join(', '));
  if(!process.env.CKMUD_TEST_CATALOG_PASSWORD)console.log('Private access off (set CKMUD_TEST_CATALOG_PASSWORD to enable).');
 });
}
module.exports={createCatalogServer,scan,declaration,field};

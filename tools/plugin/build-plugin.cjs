'use strict';
// Vendored from CKMud-2D-Desktop's scripts/ (no public remote, so CI can't fetch it). Keep in sync by
// copying the file over; don't edit it here.
// Builds a CKMud client catalog plugin: one Mudlet XML file holding a single Lua script.
//
//   node scripts/build-plugin.cjs -o <out.xml> <part> [<part>...]
//
// Each part is a .lua file, or a Mudlet package (.xml or .mpackage) whose active scripts are taken
// in document order. Parts run in the order given, each in its own do ... end block, so locals stay
// in their part and globals are shared. A package's triggers, aliases, timers and keys are NOT
// copied: recreate them in a .lua part with tempRegexTrigger / mud.alias / mud.tick (the build lists
// what it left out). The plugin's id, name and version come from its mud.plugin.register call.
// See docs/PLUGINS.md.
const fs=require('node:fs'),path=require('node:path'),zlib=require('node:zlib'),crypto=require('node:crypto');
const {declaration,field}=require('./test-catalog.cjs');
const MAX=3*1024*1024,ID=/^[a-z][a-z0-9-]{1,63}$/;

// Smallest zip reader that handles Mudlet's .mpackage (stored or deflated entries).
function unzip(buffer){
 let end=-1;for(let i=buffer.length-22;i>=Math.max(0,buffer.length-65557);i--)if(buffer.readUInt32LE(i)===0x06054b50){end=i;break;}
 if(end<0)throw Error('Not a zip file.');
 const files=new Map();let at=buffer.readUInt32LE(end+16);
 for(let n=buffer.readUInt16LE(end+10);n>0;n--){
  if(buffer.readUInt32LE(at)!==0x02014b50)throw Error('Damaged zip directory.');
  const method=buffer.readUInt16LE(at+10),size=buffer.readUInt32LE(at+20),nameLen=buffer.readUInt16LE(at+28),extra=buffer.readUInt16LE(at+30),comment=buffer.readUInt16LE(at+32),local=buffer.readUInt32LE(at+42);
  const name=buffer.toString('utf8',at+46,at+46+nameLen);at+=46+nameLen+extra+comment;
  if(name.endsWith('/'))continue;
  const start=local+30+buffer.readUInt16LE(local+26)+buffer.readUInt16LE(local+28),data=buffer.subarray(start,start+size);
  if(method===0)files.set(name,data);else if(method===8)files.set(name,zlib.inflateRawSync(data));else throw Error(name+': unsupported zip compression.');
 }
 return files;
}

function packageXml(file){
 const bytes=fs.readFileSync(file);
 if(!file.endsWith('.mpackage'))return bytes.toString('utf8');
 const files=unzip(bytes),xml=[...files.keys()].filter(n=>!n.includes('/')&&n.endsWith('.xml'));
 if(xml.length!==1)throw Error(file+': expected one .xml at the top of the package, found '+(xml.join(', ')||'none')+'.');
 const extra=[...files.keys()].filter(n=>n!==xml[0]&&n!=='config.lua');
 if(extra.length)console.warn(path.basename(file)+': left out bundled files: '+extra.join(', '));
 return files.get(xml[0]).toString('utf8');
}

const text=s=>s.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g,(_,c)=>c.replace(/&/g,'&amp;').replace(/</g,'&lt;')).replace(/&(#x[0-9a-f]+|#\d+|lt|gt|amp|quot|apos);/gi,(_,e)=>e[0]==='#'?String.fromCodePoint(e[1].toLowerCase()==='x'?parseInt(e.slice(2),16):Number(e.slice(1))):{lt:'<',gt:'>',amp:'&',quot:'"',apos:"'"}[e.toLowerCase()]);

// Active scripts in document order, plus a count of what a plugin has to recreate in Lua.
function packageScripts(xml,label){
 const scripts=[],skipped={};
 for(const m of xml.matchAll(/<(Script|ScriptGroup)\b([^>]*)>\s*<name>([\s\S]*?)<\/name>[\s\S]*?<script>([\s\S]*?)<\/script>/g)){
  if(/isActive="no"/.test(m[2]))continue;
  const code=text(m[4]);if(code.trim())scripts.push({name:text(m[3]).trim(),code});
 }
 for(const tag of ['Trigger','Alias','Timer','Key'])for(const m of xml.matchAll(new RegExp('<'+tag+'(?:Group)?\\b[^>]*>\\s*<name>([\\s\\S]*?)</name>','g')))(skipped[tag]??=[]).push(text(m[1]).trim());
 if(!scripts.length)throw Error(label+': no active scripts.');
 return {scripts,skipped};
}

function buildPlugin(parts){
 const chunks=[],skipped=[];
 for(const part of parts){
  const label=path.basename(part);
  if(part.endsWith('.lua')){chunks.push({label,code:fs.readFileSync(part,'utf8')});continue;}
  const r=packageScripts(packageXml(part),label);
  for(const s of r.scripts)chunks.push({label:label+' / '+s.name,code:s.code});
  for(const [tag,names] of Object.entries(r.skipped))skipped.push(label+': '+names.length+' '+tag.toLowerCase()+(names.length===1?'':'s')+' not copied ('+names.join(', ')+')');
 }
 const lua=chunks.map(c=>'-- ==== '+c.label.replace(/\n/g,' ')+'\ndo\n'+c.code.replace(/\s+$/,'')+'\nend\n').join('\n');
 const decl=declaration(lua);
 const id=field(decl,'id'),name=field(decl,'name'),version=field(decl,'version');
 if(!id)throw Error('No mud.plugin.register{ id = ... } found: the catalog needs the plugin declaration.');
 if(!ID.test(id))throw Error('Plugin id "'+id+'" must be lower case letters, digits and dashes.');
 const esc=s=>s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
 const xml='<?xml version="1.0" encoding="UTF-8"?>\n<MudletPackage version="1.001"><ScriptPackage><Script isActive="yes" isFolder="no"><name>'+esc(name||id)+
  '</name><script><![CDATA[\n'+lua.replace(/\]\]>/g,']]]]><![CDATA[>')+']]></script><eventHandlerList/></Script></ScriptPackage></MudletPackage>\n';
 const bytes=Buffer.from(xml,'utf8');
 if(bytes.length>MAX)throw Error('The plugin is '+bytes.length+' bytes; the catalog allows 3 MB.');
 return {xml:bytes,id,name,version,skipped,sha256:crypto.createHash('sha256').update(bytes).digest('hex')};
}

if(require.main===module){
 const args=process.argv.slice(2),o=args.indexOf('-o'),out=o<0?null:args[o+1],parts=args.filter((_,i)=>o<0||(i!==o&&i!==o+1));
 if(!out||!parts.length){console.error('Usage: node scripts/build-plugin.cjs -o <out.xml> <part.lua|package.xml|package.mpackage>...');process.exit(1);}
 try{
  const r=buildPlugin(parts);fs.writeFileSync(out,r.xml);
  console.log('Built '+out+': '+r.id+' "'+r.name+'" '+(r.version||'(no version)')+', '+r.xml.length+' bytes, sha256 '+r.sha256);
  for(const s of r.skipped)console.log('Note: '+s+'. Recreate them in a .lua part.');
 }catch(e){console.error(e.message);process.exit(1);}
}
module.exports={buildPlugin,unzip,packageScripts};

"""Require real iOS 9 armv7 AND arm64 slices; reject SwiftUI/concurrency dependencies."""
from pathlib import Path
import argparse,hashlib,json,plistlib,struct,zipfile
def version(v):return f'{v>>16}.{v>>8&255}.{v&255}'
def verify(path):
 with zipfile.ZipFile(path) as z:
  assert z.testzip() is None
  prefix='Payload/ReaderPlus.app/'
  info=plistlib.loads(z.read(prefix+'Info.plist'))
  assert info['MinimumOSVersion']=='9.0'
  assert info['CFBundleSupportedPlatforms']==['iPhoneOS']
  b=z.read(prefix+info['CFBundleExecutable'])
  assert b[:4]==b'\xca\xfe\xba\xbe','Not a universal Mach-O'
  count=struct.unpack_from('>I',b,4)[0];slices=[]
  for i in range(count):
   cpu,sub,offset,size,align=struct.unpack_from('>IIIII',b,8+i*20)
   binary=b[offset:offset+size];magic=struct.unpack_from('<I',binary,0)[0]
   assert magic in [0xfeedface,0xfeedfacf]
   header=32 if magic==0xfeedfacf else 28
   commands=struct.unpack_from('<I',binary,16)[0];pos=header;minimum=None;sdk=None;libraries=[]
   for j in range(commands):
    command,length=struct.unpack_from('<II',binary,pos);assert 8<=length<=len(binary)-pos
    if command==0x25:minimum,sdk=struct.unpack_from('<II',binary,pos+8)
    if command==0x32:
     platform,minimum,sdk=struct.unpack_from('<III',binary,pos+8);assert platform==2
    if command in [0xc,0x80000018,0x8000001f]:
     start=struct.unpack_from('<I',binary,pos+8)[0];libraries.append(binary[pos+start:pos+length].split(b'\0')[0].decode())
    assert command!=0x1d,'Unexpected code signature'
    assert command!=0x80000034,'Chained fixups require a newer OS'
    pos+=length
   assert minimum==0x90000,(cpu,minimum)
   assert not any(x in lib for lib in libraries for x in ['SwiftUI','swift_Concurrency','PDFKit','libswift'])
   slices.append(dict(architecture={12:'armv7',0x0100000c:'arm64'}[cpu],minimumOS=version(minimum),sdk=version(sdk),libraries=libraries))
  assert {x['architecture']for x in slices}=={'armv7','arm64'}
  assert not any('/_CodeSignature/'in n or n.endswith('embedded.mobileprovision') for n in z.namelist())
 result=dict(file=Path(path).name,bytes=Path(path).stat().st_size,sha256=hashlib.sha256(Path(path).read_bytes()).hexdigest(),bundle=info['CFBundleIdentifier'],minimumOS='9.0',slices=slices,signing='unsigned',physicalDeviceTests='pending')
 print(json.dumps(result,indent=2));return result
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('ipa');a=p.parse_args();result=verify(a.ipa)
 Path(a.ipa).with_name('compat-verification.json').write_text(json.dumps(result,indent=2)+'\n')

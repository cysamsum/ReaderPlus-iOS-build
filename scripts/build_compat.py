"""Compile the Objective-C iOS 9 compatibility app. No Swift runtime dependency.
Device: iOS 9.3 public headers, device-only iOS 12.4 link stubs, legacy ld.
Simulator: current public SDK, the identical app sources.
"""
from pathlib import Path
import argparse
import os
import plistlib
import shutil
import subprocess
import platform

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--simulator',action='store_true')
args=parser.parse_args()
os.chdir(ROOT)
def run(command):
    subprocess.run([str(x) for x in command],check=True)

clang=subprocess.check_output(['xcrun','--find','clang'],text=True).strip()
sr=ROOT/'ThirdParty/SocketRocket/SocketRocket'
sources=sorted((ROOT/'CompatApp').glob('*.m'))+sorted(sr.rglob('*.m'))+[ROOT/'CompatApp/RPGEC.c']
includes=['-I'+str(ROOT/'CompatApp'),'-I'+str(sr.parent)]
includes+=['-I'+str(p) for p in [sr]+sorted(p for p in sr.rglob('*') if p.is_dir())]
frameworks=['Foundation','UIKit','CoreGraphics','AVFoundation','CFNetwork','Security']
app=ROOT/('build/compat-simulator/ReaderPlus.app' if args.simulator else 'build/compat-ipa/Payload/ReaderPlus.app')
app.mkdir(parents=True,exist_ok=True)
arches=[platform.machine()] if args.simulator else ['armv7','arm64']
if args.simulator:
    sdk=Path(subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip())
else:
    sdk=ROOT/'build/compat-sdks/iPhoneOS9.3.sdk'
    assert sdk.exists(),'Run scripts/prepare_compat_sdk.sh first'
ld=Path('/Applications/Xcode_16.4.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/ld-classic')
binaries=[]
for arch in arches:
    folder=ROOT/'build'/('obj-sim-'+arch if args.simulator else 'obj-ios9-'+arch)
    folder.mkdir(parents=True,exist_ok=True)
    target=arch+('-apple-ios15.0-simulator' if args.simulator else '-apple-ios9.0')
    objects=[]
    for i,source in enumerate(sources):
        obj=folder/(str(i)+'-'+source.stem+'.o')
        command=[clang,'-target',target,'-isysroot',sdk,'-Os','-fno-common','-Werror=implicit-function-declaration']+includes
        if source.suffix=='.m':command+=['-fobjc-arc','-Werror=unguarded-availability-new']
        run(command+['-c',source,'-o',obj]);objects.append(obj)
    binary=folder/'ReaderPlus'
    if args.simulator:
        command=[clang,'-target',target,'-isysroot',sdk]+objects
    else:
        command=[ld,'-arch',arch,'-ios_version_min','9.0','-sdk_version','12.4',
                 '-syslibroot',ROOT/'build/compat-sdks/iPhoneOS12.4.sdk']+objects+['-lSystem','-lobjc']
    for framework in frameworks:command+=['-framework',framework]
    command+=['-lz','-licucore','-o',binary]
    run(command);binaries.append(binary)
if args.simulator:shutil.copy2(binaries[0],app/'ReaderPlus')
else:run(['xcrun','lipo','-create']+binaries+['-output',app/'ReaderPlus'])
info=plistlib.loads((ROOT/'App/Info.plist').read_bytes())
info.update(CFBundleIdentifier='org.readerplus.ios',CFBundleExecutable='ReaderPlus',
            CFBundleName='ReaderPlus',CFBundleShortVersionString='1.2.1',CFBundleVersion='7',
            MinimumOSVersion='15.0' if args.simulator else '9.0',
            CFBundleSupportedPlatforms=['iPhoneSimulator' if args.simulator else 'iPhoneOS'],
            UIDeviceFamily=[1,2],UIRequiredDeviceCapabilities=['armv7'] if not args.simulator else [],
            DTPlatformName='iphonesimulator' if args.simulator else 'iphoneos',
            DTSDKName='iphonesimulator26.1' if args.simulator else 'iphoneos12.4',
            UILaunchStoryboardName='LaunchScreen',UIUserInterfaceStyle='Light')
info.pop('UIApplicationSceneManifest',None)
info.pop('UILaunchScreen',None)
info['CFBundleIcons']={'CFBundlePrimaryIcon':{'CFBundleIconFiles':['Icon60'],'UIPrerenderedIcon':False}}
info['CFBundleIcons~ipad']={'CFBundlePrimaryIcon':{'CFBundleIconFiles':['Icon60','Icon76'],'UIPrerenderedIcon':False}}
(app/'Info.plist').write_bytes(plistlib.dumps(info))
for file in (ROOT/'CompatApp/Icons').glob('*.png'):shutil.copy2(file,app/file.name)
for file in (ROOT/'ThirdParty').glob('*.txt'):shutil.copy2(file,app/file.name)
for file in (ROOT/'samples').iterdir():shutil.copy2(file,app/file.name)
shutil.copy2(ROOT/'App/PrivacyInfo.xcprivacy',app/'PrivacyInfo.xcprivacy')
run(['xcrun','ibtool','--compile',app/'LaunchScreen.storyboardc',ROOT/'CompatApp/LaunchScreen.storyboard',
     '--minimum-deployment-target','9.0','--target-device','iphone','--target-device','ipad'])
if args.simulator:run(['codesign','--force','--sign','-',app])
else:
    (ROOT/'dist').mkdir(exist_ok=True)
    run(['ditto','-c','-k','--keepParent',app.parent,ROOT/'dist/ReaderPlus-1.2.1-iOS9-26.1-unsigned.ipa'])
print('Built',app)

from pathlib import Path
import hashlib
import json
ROOT=Path(__file__).resolve().parents[1]
def uid(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def q(value):return json.dumps(str(value))
objects=[]
def obj(name,body):objects.append(f'{uid(name)} = {{ {body} }};');return uid(name)
swift=sorted((ROOT/'OpenAIUsageSentinel').rglob('*.swift'))
tests=sorted((ROOT/'Tests').glob('*.swift'))
source_refs=[];source_build=[];test_refs=[];test_build=[]
for path in swift+tests:
 rel=path.relative_to(ROOT).as_posix()
 ref=obj(rel, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(rel)}; sourceTree = SOURCE_ROOT;')
 build=obj(rel+'build',f'isa = PBXBuildFile; fileRef = {ref};')
 if path in tests:test_refs.append(ref);test_build.append(build)
 else:source_refs.append(ref);source_build.append(build)
resource_build=[]
for path in sorted((ROOT/'OpenAIUsageSentinel/Resources').glob('*')):
 rel=path.relative_to(ROOT).as_posix()
 ref=obj(rel, f'isa = PBXFileReference; lastKnownFileType = {"text.json" if path.suffix == ".json" else "image.icns"}; path = {q(rel)}; sourceTree = SOURCE_ROOT;')
 source_refs.append(ref)
 resource_build.append(obj(rel+'build',f'isa = PBXBuildFile; fileRef = {ref};'))
app=obj('product.app' ,'isa = PBXFileReference; explicitFileType = wrapper.application; path = "AI Usage Sentinel.app"; sourceTree = BUILT_PRODUCTS_DIR;')
test=obj('product.tests','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = SentinelTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products=obj('products',f'isa = PBXGroup; name = Products; children = ({app}, {test}); sourceTree = "<group>";')
sg=obj('sources',f'isa = PBXGroup; name = OpenAIUsageSentinel; children = ({", ".join(source_refs)}); sourceTree = "<group>";')
tg=obj('testgroup',f'isa = PBXGroup; name = Tests; children = ({", ".join(test_refs)}); sourceTree = "<group>";')
main=obj('main',f'isa = PBXGroup; children = ({sg}, {tg}, {products}); sourceTree = "<group>";')
sphase=obj('sourcesphase',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(source_build)}); runOnlyForDeploymentPostprocessing = 0;')
tphase=obj('testsphase',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(test_build)}); runOnlyForDeploymentPostprocessing = 0;')
fphase=obj('frameworkphase','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
tfphase=obj('testframeworkphase','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
rphase=obj('resourcesphase',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(resource_build)}); runOnlyForDeploymentPostprocessing = 0;')
proxy=obj('proxy',f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("apptarget")}; remoteInfo = OpenAIUsageSentinel;')
dep=obj('dependency',f'isa = PBXTargetDependency; target = {uid("apptarget")}; targetProxy = {proxy};')
base={'MACOSX_DEPLOYMENT_TARGET':'14.0','SDKROOT':'macosx','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','SWIFT_STRICT_CONCURRENCY':'targeted','CODE_SIGN_IDENTITY':'-','CODE_SIGN_STYLE':'Manual','ENABLE_USER_SCRIPT_SANDBOXING':'YES'}
appsettings={'PRODUCT_NAME':'AI Usage Sentinel','PRODUCT_MODULE_NAME':'OpenAIUsageSentinel','PRODUCT_BUNDLE_IDENTIFIER':'com.jingteng.openai-usage-sentinel','INFOPLIST_FILE':'OpenAIUsageSentinel/Info.plist','ENABLE_APP_SANDBOX':'NO','ENABLE_HARDENED_RUNTIME':'YES','OTHER_LDFLAGS':'$(inherited) -lsqlite3','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks','SWIFT_EMIT_LOC_STRINGS':'YES'}
testsettings={'PRODUCT_NAME':'SentinelTests','PRODUCT_BUNDLE_IDENTIFIER':'com.jingteng.openai-usage-sentinel.tests','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/AI Usage Sentinel.app/Contents/MacOS/AI Usage Sentinel','BUNDLE_LOADER':'$(TEST_HOST)','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks'}
def configlist(name,extra):
 refs=[]
 for mode in ['Debug','Release']:
  settings=base|extra|({'SWIFT_OPTIMIZATION_LEVEL':'-Onone','DEBUG_INFORMATION_FORMAT':'dwarf','ENABLE_TESTABILITY':'YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG'} if mode=='Debug' else {'SWIFT_OPTIMIZATION_LEVEL':'-O','DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym'})
  refs.append(obj(name+mode,f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{'+''.join(f'{k} = {q(v)};' for k,v in settings.items())+'};'))
 return obj(name+'configlist',f'isa = XCConfigurationList; buildConfigurations = ({", ".join(refs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
pconf=configlist('project',{})
aconf=configlist('app',appsettings)
tconf=configlist('tests',testsettings)
at=obj('apptarget',f'isa = PBXNativeTarget; name = OpenAIUsageSentinel; productName = OpenAIUsageSentinel; productType = "com.apple.product-type.application"; productReference = {app}; buildConfigurationList = {aconf}; buildPhases = ({sphase},{fphase},{rphase}); dependencies = (); buildRules = ();')
tt=obj('testtarget',f'isa = PBXNativeTarget; name = SentinelTests; productName = SentinelTests; productType = "com.apple.product-type.bundle.unit-test"; productReference = {test}; buildConfigurationList = {tconf}; buildPhases = ({tphase},{tfphase}); dependencies = ({dep}); buildRules = ();')
proj=obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {pconf}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({at},{tt});')
folder=ROOT/'OpenAIUsageSentinel.xcodeproj';folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {proj}; }}\n')
scheme=folder/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
def reference(target,name):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(target)}" BuildableName="{name}" BlueprintName="{ "SentinelTests" if target=="testtarget" else "OpenAIUsageSentinel" }" ReferencedContainer="container:OpenAIUsageSentinel.xcodeproj"/>'
(scheme/'OpenAIUsageSentinel.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference('apptarget','AI Usage Sentinel.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference('testtarget','SentinelTests.xctest')}</TestableReference></Testables><EnvironmentVariables><EnvironmentVariable key="SENTINEL_TEST_HOST" value="1" isEnabled="YES"/></EnvironmentVariables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference('apptarget','AI Usage Sentinel.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference('apptarget','AI Usage Sentinel.app')}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated',folder)

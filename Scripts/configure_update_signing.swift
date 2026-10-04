// Run locally once. Stores the signing seed in macOS Keychain and pipes it into GitHub Actions Secrets.
// No private key is written to the repository, command arguments, or stdout.
import Foundation
import CryptoKit
import Security
let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"UsageSentinel.ReleaseSigning",kSecAttrAccount as String:"ed25519-v1"]
var read = query; read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
var existing: CFTypeRef?
let status=SecItemCopyMatching(read as CFDictionary,&existing)
let key: Curve25519.Signing.PrivateKey
if status==errSecSuccess, let bytes=existing as? Data {key=try Curve25519.Signing.PrivateKey(rawRepresentation:bytes)}
else if status==errSecItemNotFound {
 key=Curve25519.Signing.PrivateKey();var add=query;add[kSecValueData as String]=key.rawRepresentation;add[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
 guard SecItemAdd(add as CFDictionary,nil)==errSecSuccess else {fatalError("Cannot save signing key in Keychain")}
}else{fatalError("Keychain unavailable")}
let publicKey=key.publicKey.rawRepresentation.base64EncodedString()
var config: [String:Any] = (try? Data(contentsOf: URL(fileURLWithPath:"OpenAIUsageSentinel/Resources/ServiceConfig.json"))).flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Any] } ?? ["schema":1,"analyticsEndpoint":NSNull()]
config["updatePublicKey"] = publicKey
try JSONSerialization.data(withJSONObject:config,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:"OpenAIUsageSentinel/Resources/ServiceConfig.json"),options:.atomic)
let process=Process(), pipe=Pipe();process.executableURL=URL(fileURLWithPath:"/usr/bin/env");process.arguments=["gh","secret","set","UPDATES_ED25519_KEY","--repo","Joe05520/usage-sentinel"];process.standardInput=pipe
try process.run();try pipe.fileHandleForWriting.write(contentsOf:Data(key.rawRepresentation.base64EncodedString().utf8));try pipe.fileHandleForWriting.close();process.waitUntilExit()
guard process.terminationStatus==0 else{fatalError("Could not configure repository signing secret")}
print("Public signing key: \(publicKey). Private signing key retained in Keychain and GitHub Actions Secrets.")

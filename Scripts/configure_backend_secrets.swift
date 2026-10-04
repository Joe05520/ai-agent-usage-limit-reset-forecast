// Run from the project root. High-entropy backend secrets stay in Keychain and Workers secrets.
import Foundation
import Security
import AppKit
let service="UsageSentinel.AnalyticsAdmin"
func key(_ account:String)throws->Data {
 let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
 var read=query;read[kSecReturnData as String]=true;read[kSecMatchLimit as String]=kSecMatchLimitOne;var existing:CFTypeRef?
 let status=SecItemCopyMatching(read as CFDictionary,&existing)
 if status==errSecSuccess,let data=existing as? Data{return data}
 guard status==errSecItemNotFound else{fatalError("Keychain read failed")}
 var random=[UInt8](repeating:0,count:32);guard SecRandomCopyBytes(kSecRandomDefault,32,&random)==errSecSuccess else{fatalError("Random generator failed")}
 let data=Data(random.map{String(format:"%02x",$0)}.joined().utf8)
 var add=query;add[kSecValueData as String]=data;add[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
 guard SecItemAdd(add as CFDictionary,nil)==errSecSuccess else{fatalError("Keychain write failed")};return data
}
if CommandLine.arguments.contains("--copy-admin-password") {
 let value=try key("admin-password"); NSPasteboard.general.clearContents(); NSPasteboard.general.setString(String(decoding:value,as:UTF8.self),forType:.string)
 print("Admin password copied. Paste into your own Worker admin page, then clear your clipboard.")
}else {
 for (name,account) in [("INGEST_SECRET","ingestion-key"),("ADMIN_SECRET","admin-password")] {
  let data=try key(account),process=Process(),pipe=Pipe()
  process.executableURL=URL(fileURLWithPath:"Backend/node_modules/.bin/wrangler");process.arguments=["secret","put",name,"--config","Backend/wrangler.jsonc"];process.standardInput=pipe
  try process.run();try pipe.fileHandleForWriting.write(contentsOf:data);try pipe.fileHandleForWriting.close();process.waitUntilExit()
  guard process.terminationStatus==0 else{fatalError("Secret deployment failed")}
 }
 print("Backend secrets configured; admin password is in Keychain service UsageSentinel.AnalyticsAdmin, account admin-password.")
}

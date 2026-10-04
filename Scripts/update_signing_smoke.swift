import Foundation
import CryptoKit
import Security
// Checks the public key and signs a harmless in-memory fixture without exposing the seed.
let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"UsageSentinel.ReleaseSigning",kSecAttrAccount as String:"ed25519-v1",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
var value:CFTypeRef?;guard SecItemCopyMatching(query as CFDictionary,&value)==errSecSuccess,let data=value as? Data else{fatalError("Signing key unavailable")}
let key=try Curve25519.Signing.PrivateKey(rawRepresentation:data),text=Data("UsageSentinel signing self-test".utf8),signature=try key.signature(for:text)
guard key.publicKey.isValidSignature(signature,for:text),!key.publicKey.isValidSignature(signature,for:Data("modified".utf8)) else{fatalError("Signature verification failed")}
print("Ed25519 signing/verification and tamper rejection passed")

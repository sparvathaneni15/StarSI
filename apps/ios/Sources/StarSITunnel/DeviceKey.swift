// The phone's SSH identity: an ed25519 key generated on-device. The raw
// private key lives in the Keychain (Secure Enclave can't sign ed25519 for
// NIOSSH); only the public half ever leaves the phone, via the enrollment
// screen, to be pasted into infra/ssh/authorized_keys.d/.

import Crypto
import Foundation
import StarSIClient

public enum DeviceKey {
    static let keychainKey = "ssh-device-key"

    public static func load() -> Curve25519.Signing.PrivateKey? {
        guard let b64 = Keychain.get(keychainKey),
              let raw = Data(base64Encoded: b64)
        else { return nil }
        return try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    }

    @discardableResult
    public static func loadOrCreate() -> Curve25519.Signing.PrivateKey {
        if let existing = load() { return existing }
        let key = Curve25519.Signing.PrivateKey()
        Keychain.set(key.rawRepresentation.base64EncodedString(), for: keychainKey)
        return key
    }

    /// `ssh-ed25519 AAAA... starsi-iphone` — what goes into authorized_keys.
    public static func openSSHPublicKey(_ key: Curve25519.Signing.PrivateKey,
                                        comment: String = "starsi-iphone") -> String {
        var wire = Data()
        func append(_ bytes: Data) {
            var len = UInt32(bytes.count).bigEndian
            wire.append(Data(bytes: &len, count: 4))
            wire.append(bytes)
        }
        append(Data("ssh-ed25519".utf8))
        append(key.publicKey.rawRepresentation)
        return "ssh-ed25519 \(wire.base64EncodedString()) \(comment)"
    }
}

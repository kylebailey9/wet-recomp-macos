import Foundation
import CommonCrypto
import Security

enum CryptoError: Error, LocalizedError {
    case random
    case kdf
    case encrypt

    var errorDescription: String? {
        switch self {
        case .random: return "Could not generate random bytes."
        case .kdf: return "Key derivation failed."
        case .encrypt: return "Encryption failed."
        }
    }
}

/// OpenSSL-compatible encryption: `openssl enc -aes-256-cbc -pbkdf2`
/// (PBKDF2-HMAC-SHA256, 10000 iterations, 48 bytes out, "Salted__" header).
struct WetCrypto {
    static func randomPassphrase() -> String {
        var bytes = [UInt8](repeating: 0, count: 36)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    static func encryptXex(_ data: Data, passphrase: String) throws -> Data {
        var salt = Data(count: 8)
        let sres: Int32 = salt.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 8, ptr.baseAddress!)
        }
        guard sres == errSecSuccess else { throw CryptoError.random }

        let keyiv = try pbkdf2SHA256(password: Data(passphrase.utf8), salt: salt, iterations: 10000, keyLength: 48)
        let ct = try aesCBCEncrypt(data, key: keyiv.prefix(32), iv: keyiv.suffix(16))

        var out = Data("Salted__".utf8)
        out.append(salt)
        out.append(ct)
        return out
    }

    private static func pbkdf2SHA256(password: Data, salt: Data, iterations: UInt32, keyLength: Int) throws -> Data {
        var derived = Data(count: keyLength)
        let status: Int32 = derived.withUnsafeMutableBytes { dk in
            password.withUnsafeBytes { pw in
                salt.withUnsafeBytes { s in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pw.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                        s.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        dk.baseAddress?.assumingMemoryBound(to: UInt8.self), keyLength)
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.kdf }
        return derived
    }

    private static func aesCBCEncrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
        var out = Data(count: data.count + kCCBlockSizeAES128)
        var outLen = 0
        let outCapacity = out.count
        let status: Int32 = out.withUnsafeMutableBytes { o in
            data.withUnsafeBytes { d in
                key.withUnsafeBytes { k in
                    iv.withUnsafeBytes { v in
                        CCCrypt(CCOperation(kCCEncrypt),
                                CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                k.baseAddress, key.count,
                                v.baseAddress,
                                d.baseAddress, data.count,
                                o.baseAddress, outCapacity,
                                &outLen)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.encrypt }
        out.count = outLen
        return out
    }
}

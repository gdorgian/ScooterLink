import CommonCrypto
import Foundation
import Security

/// The RoadSync key exchange (com.drivemode.sab.ble.security.SecurityController):
/// the phone sends an RSA-1024 modulus, the scooter answers with a 16-byte AES key
/// encrypted to it, and every later connection proves the key with an AES-ECB message.
enum SABCrypto {
    enum Failure: Error, CustomStringConvertible {
        case keyGeneration(String)
        case badPublicKey
        case rsa(String)
        case aes(Int32)
        case badResponse(String)

        var description: String {
            switch self {
            case .keyGeneration(let message): return "RSA key generation failed: \(message)"
            case .badPublicKey: return "could not read the RSA modulus"
            case .rsa(let message): return "RSA decrypt failed: \(message)"
            case .aes(let status): return "AES failed (status \(status))"
            case .badResponse(let message): return message
            }
        }
    }

    // MARK: CRC-16 (reflected polynomial 0xA001, init 0), written little-endian

    private static let crcTable: [UInt16] = (0..<256).map { byte in
        var crc = UInt16(byte)
        for _ in 0..<8 { crc = crc & 1 != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1 }
        return crc
    }

    static func crc16(_ data: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for byte in data { crc = crcTable[Int((crc ^ UInt16(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc
    }

    static func crc16LE(_ data: [UInt8]) -> [UInt8] {
        let crc = crc16(data)
        return [UInt8(crc & 0xFF), UInt8(crc >> 8)]
    }

    // MARK: Secure exchange

    static func makeRSAKey() throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 1024,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw Failure.keyGeneration(error?.takeRetainedValue().localizedDescription ?? "unknown")
        }
        return key
    }

    /// Big-endian modulus without a leading zero byte (BigInteger.toByteArray minus sign byte).
    static func modulus(of privateKey: SecKey) throws -> [UInt8] {
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let der = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
        else { throw Failure.badPublicKey }
        // PKCS#1 RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }
        var reader = DERReader(bytes: [UInt8](der))
        guard reader.enter(tag: 0x30), var modulus = reader.read(tag: 0x02) else { throw Failure.badPublicKey }
        while modulus.first == 0 { modulus.removeFirst() }
        return modulus
    }

    static func secureExchangeCommand(privateKey: SecKey) throws -> Data {
        Data([SAB.Security.secureExchange] + (try modulus(of: privateKey)))
    }

    /// Decrypts the DataSource answer: 110 bytes padding, 16 bytes AES key, 2 bytes CRC.
    static func aesKey(fromExchangeResponse response: Data, privateKey: SecKey) throws -> Data {
        guard response.count > 1 else { throw Failure.badResponse("scooter refused the key exchange (\(response.hex))") }
        var error: Unmanaged<CFError>?
        guard let plain = SecKeyCreateDecryptedData(privateKey, .rsaEncryptionRaw, response as CFData, &error) as Data? else {
            throw Failure.rsa(error?.takeRetainedValue().localizedDescription ?? "unknown")
        }
        let bytes = [UInt8](plain)
        guard bytes.count >= 128 else { throw Failure.badResponse("RSA block too short (\(bytes.count) bytes)") }
        let key = Array(bytes[110..<126])
        let crc = Array(bytes[126..<128])
        guard crc16LE(key) == crc else {
            throw Failure.badResponse("key checksum mismatch: computed \(Data(crc16LE(key)).hex), received \(Data(crc).hex)")
        }
        return Data(key)
    }

    // MARK: Validation

    static func validationCommand(key: Data) throws -> Data {
        let plain = [SAB.Security.validation] + crc16LE([SAB.Security.validation])
        return Data([0x01, 0x00]) + (try aes(encrypt: true, key: key, data: Data(plain), padding: true))
    }

    /// Returns the scooter's increment ID on success.
    static func checkValidationResponse(_ response: Data, key: Data) throws -> UInt32 {
        guard response.count > 2 else { throw Failure.badResponse("scooter rejected the key (\(response.hex))") }
        let body = response.dropFirst(2)
        let plain: Data
        if let padded = try? aes(encrypt: false, key: key, data: Data(body), padding: true) {
            plain = padded
        } else {
            plain = try aes(encrypt: false, key: key, data: Data(body), padding: false)
        }
        let bytes = [UInt8](plain)
        guard bytes.first == 1, bytes.count >= 5 else {
            throw Failure.badResponse("validation failed, status \(bytes.first.map(String.init) ?? "none")")
        }
        return UInt32(bytes[1]) | UInt32(bytes[2]) << 8 | UInt32(bytes[3]) << 16 | UInt32(bytes[4]) << 24
    }

    static func aes(encrypt: Bool, key: Data, data: Data, padding: Bool) throws -> Data {
        var out = Data(count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let options = CCOptions(kCCOptionECBMode | (padding ? kCCOptionPKCS7Padding : 0))
        let outCapacity = out.count
        let status = out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { dataPtr in
                key.withUnsafeBytes { keyPtr in
                    CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), options,
                            keyPtr.baseAddress, key.count, nil,
                            dataPtr.baseAddress, data.count,
                            outPtr.baseAddress, outCapacity, &moved)
                }
            }
        }
        guard status == kCCSuccess else { throw Failure.aes(status) }
        return out.prefix(moved)
    }
}

/// Minimal DER walker, enough for a PKCS#1 public key.
private struct DERReader {
    let bytes: [UInt8]
    var index = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    private mutating func length() -> Int? {
        guard index < bytes.count else { return nil }
        let first = bytes[index]; index += 1
        if first < 0x80 { return Int(first) }
        let count = Int(first & 0x7F)
        guard count <= 4, index + count <= bytes.count else { return nil }
        var value = 0
        for _ in 0..<count { value = value << 8 | Int(bytes[index]); index += 1 }
        return value
    }

    mutating func enter(tag: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == tag else { return false }
        index += 1
        return length() != nil
    }

    mutating func read(tag: UInt8) -> [UInt8]? {
        guard index < bytes.count, bytes[index] == tag else { return nil }
        index += 1
        guard let count = length(), index + count <= bytes.count else { return nil }
        defer { index += count }
        return Array(bytes[index..<index + count])
    }
}

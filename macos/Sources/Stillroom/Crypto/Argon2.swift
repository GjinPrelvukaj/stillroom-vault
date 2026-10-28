import CArgon2
import Foundation

/// Argon2id (RFC 9106, version 0x13), by the reference C implementation: a password stretched through `memoryKiB`
/// of memory, so every guess costs an attacker that much RAM as well as time, which GPUs and custom chips are short
/// of. The library wipes its memory, and the copies of the password and secret made here, before returning.
func argon2id(password: Data, salt: Data, memoryKiB: UInt32, iterations: UInt32, parallelism: UInt32, length: Int,
              secret: Data = Data(), associatedData: Data = Data()) throws -> Data {
    var out = [UInt8](repeating: 0, count: length)
    // The stretched key leaves only as the copy returned; this buffer is wiped (memset_s isn't optimised away).
    defer { _ = out.withUnsafeMutableBytes { memset_s($0.baseAddress, $0.count, 0, $0.count) } }
    var pwd = [UInt8](password), saltBytes = [UInt8](salt), key = [UInt8](secret), ad = [UInt8](associatedData)
    let status = out.withUnsafeMutableBufferPointer { out in
        pwd.withUnsafeMutableBufferPointer { pwd in
            saltBytes.withUnsafeMutableBufferPointer { salt in
                key.withUnsafeMutableBufferPointer { key in
                    ad.withUnsafeMutableBufferPointer { ad in
                        var context = argon2_context(
                            out: out.baseAddress, outlen: UInt32(out.count),
                            pwd: pwd.baseAddress, pwdlen: UInt32(pwd.count),
                            salt: salt.baseAddress, saltlen: UInt32(salt.count),
                            secret: key.baseAddress, secretlen: UInt32(key.count),
                            ad: ad.baseAddress, adlen: UInt32(ad.count),
                            t_cost: iterations, m_cost: memoryKiB, lanes: parallelism, threads: parallelism,
                            version: UInt32(ARGON2_VERSION_13.rawValue),
                            allocate_cbk: nil, free_cbk: nil,
                            flags: clearPasswordAndSecret)
                        return argon2_ctx(&context, Argon2_id)
                    }
                }
            }
        }
    }
    // Bad parameters or no memory for them: only a damaged or doctored key file asks for either.
    guard status == ARGON2_OK.rawValue else { throw VaultError.damaged }
    return Data(out)
}

/// ARGON2_FLAG_CLEAR_PASSWORD | ARGON2_FLAG_CLEAR_SECRET from argon2.h (Swift can't import those macros).
private let clearPasswordAndSecret: UInt32 = 1 << 0 | 1 << 1

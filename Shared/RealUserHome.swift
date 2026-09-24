import Darwin
import Foundation

enum RealUserHome {
    /// The login home directory, not the App Sandbox container.
    static var url: URL {
        if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}

enum POSIXFileRead {
    /// Read-only copy into memory. Do not map the file. Mapping can try to write
    /// a sibling file in the same folder, which the sandbox blocks for Safari.
    /// Retry EPERM: Safari rewrites Bookmarks.plist, and TCC can deny a single open.
    static func data(atPath path: String) throws -> Data {
        var lastError: Error = POSIXError(.EPERM)
        for attempt in 0..<8 {
            do {
                return try readOnce(atPath: path)
            } catch {
                lastError = error
                guard isRetryable(error), attempt < 7 else { break }
                usleep(20_000)
            }
        }
        throw lastError
    }

    private static func isRetryable(_ error: Error) -> Bool {
        let code = (error as? POSIXError)?.code
        return code == .EPERM || code == .EACCES || code == .EAGAIN
            || code == .EBUSY || code == .ENOENT || code == .EINTR
    }

    private static func readOnce(atPath path: String) throws -> Data {
        let fileDescriptor = open(path, O_RDONLY | O_CLOEXEC)
        guard fileDescriptor >= 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EPERM
            throw POSIXError(code)
        }
        defer { close(fileDescriptor) }

        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return ssize_t(-1) }
                return read(fileDescriptor, base, rawBuffer.count)
            }
            if count == 0 {
                break
            }
            if count < 0 {
                let code = POSIXErrorCode(rawValue: errno) ?? .EIO
                throw POSIXError(code)
            }
            bytes.append(contentsOf: buffer.prefix(Int(count)))
        }
        guard !bytes.isEmpty else {
            throw POSIXError(.EIO)
        }
        return bytes
    }
}


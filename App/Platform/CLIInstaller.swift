import Foundation

/// Cài symlink `/usr/local/bin/keyloft` trỏ tới CLI embed trong app.
enum CLIInstaller {
    static let installURL = URL(fileURLWithPath: "/usr/local/bin/keyloft")

    enum InstallFailure: Error {
        case message(String)
    }

    static func embeddedCLIURL(bundle: Bundle = .main) -> URL? {
        bundle.executableURL?.deletingLastPathComponent().appendingPathComponent("keyloft")
    }

    static func isInstalled(bundle: Bundle = .main) -> Bool {
        guard let embedded = embeddedCLIURL(bundle: bundle) else { return false }
        let destination = try? FileManager.default.destinationOfSymbolicLink(
            atPath: installURL.path)
        return destination == embedded.path
    }

    /// Trả về lỗi (vd cần sudo) cho UI hiển thị; không throw để caller quyết định.
    static func install(bundle: Bundle = .main) -> Result<Void, InstallFailure> {
        guard let cli = embeddedCLIURL(bundle: bundle),
            FileManager.default.fileExists(atPath: cli.path)
        else {
            return .failure(.message("Không tìm thấy CLI trong app bundle"))
        }
        try? FileManager.default.removeItem(at: installURL)
        do {
            try FileManager.default.createSymbolicLink(at: installURL, withDestinationURL: cli)
            return .success(())
        } catch {
            return .failure(
                .message(
                    "Không tạo được symlink /usr/local/bin/keyloft (thử sudo): \(error.localizedDescription)"
                ))
        }
    }
}

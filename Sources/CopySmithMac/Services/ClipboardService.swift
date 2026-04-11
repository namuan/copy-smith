import AppKit

protocol ClipboardServiceProtocol {
    func readString() -> String?
    func write(_ string: String) -> Bool
}

final class ClipboardService: ClipboardServiceProtocol {
    func readString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    @discardableResult
    func write(_ string: String) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.setString(string, forType: .string)
    }
}

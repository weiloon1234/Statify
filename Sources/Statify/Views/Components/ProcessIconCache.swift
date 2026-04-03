import AppKit
import Darwin

enum ProcessIconCache {
    private static let cache = NSCache<NSNumber, NSImage>()
    private static let fallbackIcon = NSWorkspace.shared.icon(for: .applicationBundle)

    static func icon(for pid: Int32) -> NSImage {
        let key = NSNumber(value: pid)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(MAXPATHLEN))
        defer { pathBuffer.deallocate() }

        let result = proc_pidpath(pid, pathBuffer, UInt32(MAXPATHLEN))
        let icon: NSImage
        if result > 0 {
            let path = String(cString: pathBuffer)
            icon = NSWorkspace.shared.icon(forFile: path)
        } else {
            icon = fallbackIcon
        }

        cache.setObject(icon, forKey: key)
        return icon
    }
}

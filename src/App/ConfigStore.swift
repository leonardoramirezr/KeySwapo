import Foundation

/// The configuration file, `~/.config/keyswapo/keyswapo.json`.
struct ConfigStore {
    let directoryURL: URL
    let fileURL: URL

    init(directoryURL: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/keyswapo", directoryHint: .isDirectory)) {
        self.directoryURL = directoryURL
        fileURL = directoryURL.appending(path: "keyswapo.json", directoryHint: .notDirectory)
    }

    var fileName: String { fileURL.lastPathComponent }

    var displayPath: String { (fileURL.path as NSString).abbreviatingWithTildeInPath }

    /// Writes the default configuration if there is no file yet. Returns whether it did.
    func createDefaultIfNeeded() throws -> Bool {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        try write(DefaultConfig.json)
        return true
    }

    func readText() throws -> String {
        try String(contentsOf: fileURL, encoding: .utf8)
    }

    func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

/// Calls `onChange` on the main queue (debounced) when a file is modified, replaced or created.
/// It also watches the directory, because most editors save by replacing the file.
final class FileWatcher {
    private let fileURL: URL
    private let onChange: @MainActor () -> Void
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pendingChange: DispatchWorkItem?

    init(fileURL: URL, onChange: @escaping @MainActor () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        directorySource = makeSource(path: fileURL.deletingLastPathComponent().path, events: .write)
        watchFile()
    }

    func stop() {
        pendingChange?.cancel()
        directorySource?.cancel()
        fileSource?.cancel()
        pendingChange = nil
        directorySource = nil
        fileSource = nil
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = makeSource(path: fileURL.path, events: [.write, .extend, .delete, .rename])
    }

    private func makeSource(path: String, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            self?.scheduleChange()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        return source
    }

    private func scheduleChange() {
        pendingChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // The file may have been replaced by a new one: watch that one from now on.
            self.watchFile()
            MainActor.assumeIsolated {
                self.onChange()
            }
        }
        pendingChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}

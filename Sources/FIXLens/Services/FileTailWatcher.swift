import Foundation

// MARK: - FileHandleActor

/// Actor that serialises all access to an open FileHandle so it is safe to call
/// from async contexts without data races.
actor FileHandleActor {
    private let fileHandle: FileHandle

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    func readData(at offset: UInt64, length: Int) throws -> Data {
        try fileHandle.seek(toOffset: offset)
        return fileHandle.readData(ofLength: length)
    }

    func close() throws {
        try fileHandle.close()
    }
}

// MARK: - FileTailWatcher

/// Watches a file for new data using kqueue via DispatchSourceFileSystemObject.
///
/// - `onNewData` is called (on an internal background queue) whenever the file grows.
/// - `onFileGone` is called when the file is deleted or renamed (e.g. log rotation).
///
/// Callers must hop to `@MainActor` inside the callbacks if they need to update UI state.
final class FileTailWatcher: @unchecked Sendable {

    private let url: URL
    private var fd: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "com.openyield.fixlens.tail", qos: .utility)

    private var currentOffset: UInt64
    private let onNewData: (Data) -> Void
    private let onFileGone: () -> Void

    private(set) var isPaused = false

    init(
        url: URL,
        startingOffset: UInt64,
        onNewData: @escaping (Data) -> Void,
        onFileGone: @escaping () -> Void
    ) {
        self.url           = url
        self.currentOffset = startingOffset
        self.onNewData     = onNewData
        self.onFileGone    = onFileGone
        start()
    }

    deinit { stop() }

    // MARK: - Control

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        source?.suspend()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        source?.resume()
        // Catch up on data written while paused
        queue.async { self.readNewData() }
    }

    func stop() {
        source?.cancel()
        source = nil
        // fd is closed by the cancel handler
    }

    // MARK: - Private

    private func start() {
        fd = Darwin.open(url.path, O_RDONLY | O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )

        src.setEventHandler { [weak self] in
            guard let self else { return }
            let events = src.data
            if events.contains(.write)  { self.readNewData() }
            if events.contains(.delete) || events.contains(.rename) {
                self.onFileGone()
            }
        }

        src.setCancelHandler { [weak self] in
            guard let self, self.fd >= 0 else { return }
            Darwin.close(self.fd)
            self.fd = -1
        }

        source = src
        src.resume()
    }

    private func readNewData() {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? fh.close() }
        do {
            let end = try fh.seekToEnd()
            guard end > currentOffset else { return }
            try fh.seek(toOffset: currentOffset)
            let data = fh.readDataToEndOfFile()
            guard !data.isEmpty else { return }
            currentOffset = end
            onNewData(data)
        } catch {}
    }
}

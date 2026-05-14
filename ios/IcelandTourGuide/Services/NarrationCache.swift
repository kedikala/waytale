import Foundation

actor NarrationCache {
    private let fileManager: FileManager
    private let directory: URL
    private var index: [String: NarrationCacheItem] = [:]
    private let indexURL: URL
    private var hasLoadedIndex = false

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        directory = caches.appendingPathComponent("NarrationAudio", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.json")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cachedAudioURL(subjectId: String, textVersion: String) -> URL? {
        loadIndexIfNeeded()
        guard let item = index[subjectId], item.textVersion == textVersion else { return nil }
        if let expiresAt = item.expiresAt, expiresAt < Date() { return nil }
        let url = directory.appendingPathComponent(item.audioFileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func store(audioData: Data, subjectId: String, textVersion: String, sourceContext: String) throws -> URL {
        loadIndexIfNeeded()
        let filename = "\(subjectId)-\(textVersion).mp3"
        let url = directory.appendingPathComponent(filename)
        try audioData.write(to: url, options: [.atomic])
        index[subjectId] = NarrationCacheItem(
            id: subjectId,
            subjectId: subjectId,
            audioFileName: filename,
            textVersion: textVersion,
            generatedAt: Date(),
            expiresAt: nil,
            sourceContext: sourceContext
        )
        try persist()
        return url
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(index)
        try data.write(to: indexURL, options: [.atomic])
    }

    private func loadIndexIfNeeded() {
        guard !hasLoadedIndex else { return }
        hasLoadedIndex = true
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([String: NarrationCacheItem].self, from: data) {
            index = decoded
        }
    }
}

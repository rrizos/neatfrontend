import Flutter
import Foundation

/// Uploads that keep going after the app is put away, or killed.
///
/// A normal request lives inside the process, so suspending the app tears down
/// its sockets and the transfer is lost. A background `URLSession` hands the
/// job to the system instead: it runs the upload out of process, finishes it
/// whether or not the app is still alive, and relaunches the app to report the
/// result. That is the only way an upload survives someone leaving mid-post.
///
/// Two constraints shape everything here:
///
///  * **The body has to be a file.** A background session refuses in-memory
///    bodies, so the multipart envelope is written to disk first and the file
///    is what gets uploaded.
///  * **The answer may arrive with no Dart alive to hear it.** Results are
///    written to `UserDefaults` as they land, and Dart drains them whenever it
///    next runs — on this launch or a later one.
final class BackgroundUploader: NSObject {

    static let shared = BackgroundUploader()

    /// One identifier for the lifetime of the app; recreating a session with
    /// the same one reconnects to transfers already in flight.
    private static let sessionIdentifier = "gr.app.neat.upload"

    /// Where finished uploads wait to be collected.
    private static let resultsKey = "neat.upload.results"

    /// Set by the app delegate when iOS wakes us to report background work;
    /// must be called once the session says it has delivered everything.
    var backgroundCompletion: (() -> Void)?

    /// Told about progress and completion while Dart is alive to hear it.
    ///
    /// Only ever an optimisation: everything reported here is also written to
    /// the results store, which is what a launch after the app was killed
    /// reads instead.
    weak var channel: FlutterMethodChannel?

    /// Response bodies, accumulated per task while they stream in.
    private var buffers: [Int: Data] = [:]
    /// Our own id for each task, so a result can be matched to its upload.
    private var names: [Int: String] = [:]
    /// The body file backing each task, deleted once it is no longer needed.
    private var bodyFiles: [Int: URL] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(
            withIdentifier: BackgroundUploader.sessionIdentifier)
        // The upload is the user waiting on a post; it should not be held back
        // for a better moment.
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Reconnects to any transfers still running from a previous launch.
    func start() { _ = session }

    // MARK: Enqueue

    /// Sends [fileURL] to [url] as a multipart body under [fieldName].
    ///
    /// Returns false only if the envelope could not be written; anything after
    /// that is the system's problem and is reported through the results store.
    func enqueue(
        name: String,
        url: URL,
        headers: [String: String],
        fileURL: URL,
        fieldName: String,
        fileName: String,
        fields: [String: String],
        completion: @escaping (Bool, String) -> Void
    ) {
        // Off the platform thread: building the envelope copies the whole
        // video, and doing that where the UI runs blocks it for seconds.
        DispatchQueue.global(qos: .userInitiated).async {
            self.build(name: name, url: url, headers: headers, fileURL: fileURL,
                       fieldName: fieldName, fileName: fileName, fields: fields,
                       completion: completion)
        }
    }

    private func build(
        name: String,
        url: URL,
        headers: [String: String],
        fileURL: URL,
        fieldName: String,
        fileName: String,
        fields: [String: String],
        completion: @escaping (Bool, String) -> Void
    ) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            NSLog("[bg-upload] no file at \(fileURL.path)")
            completion(false, "missing-file")
            return
        }
        let boundary = "neat-\(UUID().uuidString)"
        guard let body = writeMultipartBody(
            boundary: boundary, fileURL: fileURL, fieldName: fieldName,
            fileName: fileName, fields: fields
        ) else {
            NSLog("[bg-upload] could not write body for \(name)")
            completion(false, "body-write-failed")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

        let task = session.uploadTask(with: request, fromFile: body)
        names[task.taskIdentifier] = name
        bodyFiles[task.taskIdentifier] = body
        task.resume()
        NSLog("[bg-upload] started \(name) -> \(url.absoluteString)")
        completion(true, "")
    }

    /// Builds the multipart envelope on disk, since the body must be a file.
    private func writeMultipartBody(
        boundary: String, fileURL: URL, fieldName: String, fileName: String,
        fields: [String: String]
    ) -> URL? {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("neat-upload-\(UUID().uuidString).body")
        guard FileManager.default.createFile(atPath: out.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: out),
              let source = try? FileHandle(forReadingFrom: fileURL)
        else { return nil }
        defer { try? handle.close(); try? source.close() }

        func write(_ text: String) {
            if let data = text.data(using: .utf8) { handle.write(data) }
        }

        for (key, value) in fields {
            write("--\(boundary)\r\n")
            write("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            write("\(value)\r\n")
        }
        write("--\(boundary)\r\n")
        write("Content-Disposition: form-data; name=\"\(fieldName)\"; "
              + "filename=\"\(fileName)\"\r\n")
        write("Content-Type: application/octet-stream\r\n\r\n")

        // Copied in chunks: a minute of video does not belong in memory.
        while true {
            guard let chunk = try? source.read(upToCount: 1 << 20),
                  !chunk.isEmpty else { break }
            handle.write(chunk)
        }
        write("\r\n--\(boundary)--\r\n")
        return out
    }

    // MARK: Results

    private func store(name: String, status: Int, body: String) {
        var all = UserDefaults.standard.array(
            forKey: BackgroundUploader.resultsKey) as? [[String: Any]] ?? []
        all.append(["name": name, "status": status, "body": body])
        UserDefaults.standard.set(all, forKey: BackgroundUploader.resultsKey)
    }

    /// Hands over everything finished since the last call, and forgets it.
    func drainResults() -> [[String: Any]] {
        let all = UserDefaults.standard.array(
            forKey: BackgroundUploader.resultsKey) as? [[String: Any]] ?? []
        UserDefaults.standard.removeObject(forKey: BackgroundUploader.resultsKey)
        return all
    }
}

// MARK: - URLSessionDelegate

extension BackgroundUploader: URLSessionDataDelegate {

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        buffers[dataTask.taskIdentifier, default: Data()].append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0,
              let name = names[task.taskIdentifier] else { return }
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        DispatchQueue.main.async {
            self.channel?.invokeMethod("progress",
                                       arguments: ["name": name, "value": fraction])
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        if let body = bodyFiles.removeValue(forKey: id) {
            try? FileManager.default.removeItem(at: body)
        }
        let name = names.removeValue(forKey: id)
        let data = buffers.removeValue(forKey: id) ?? Data()
        guard let name else { return }

        let status = (task.response as? HTTPURLResponse)?.statusCode ?? -1
        // A failure is recorded too: Dart has a post waiting on this answer and
        // needs to know it is not coming, rather than waiting for ever.
        let code = error == nil ? status : -1
        let body = String(data: data, encoding: .utf8) ?? ""
        // Written down first: a Dart that is listening is a bonus, not the
        // thing this relies on.
        store(name: name, status: code, body: body)
        DispatchQueue.main.async {
            self.channel?.invokeMethod(
                "done", arguments: ["name": name, "status": code, "body": body])
        }
    }

    /// Everything the system had for us has been delivered.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletion?()
            self.backgroundCompletion = nil
        }
    }
}

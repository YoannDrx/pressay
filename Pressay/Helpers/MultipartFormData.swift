import Foundation

struct MultipartFormData {
    let boundary: String
    private var parts: [Part] = []

    private enum Part {
        case field(name: String, value: String)
        case data(name: String, filename: String, mimeType: String, data: Data)
        case file(name: String, filename: String, mimeType: String, url: URL)
    }

    init(boundary: String = UUID().uuidString) {
        self.boundary = boundary
    }

    mutating func appendField(name: String, value: String) {
        parts.append(.field(name: name, value: value))
    }

    mutating func appendFile(name: String, filename: String, mimeType: String, data fileData: Data) {
        parts.append(.data(name: name, filename: filename, mimeType: mimeType, data: fileData))
    }

    mutating func appendFile(name: String, filename: String, mimeType: String, url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        parts.append(.file(name: name, filename: filename, mimeType: mimeType, url: url))
    }

    func writeToTemporaryFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pressay_multipart_\(UUID().uuidString).body")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let output = try FileHandle(forWritingTo: url)
        defer { try? output.close() }

        for part in parts {
            switch part {
            case .field(let name, let value):
                try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
                try output.write(contentsOf: Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
                try output.write(contentsOf: Data("\(value)\r\n".utf8))
            case .data(let name, let filename, let mimeType, let data):
                try writeFileHeader(name: name, filename: filename, mimeType: mimeType, to: output)
                try output.write(contentsOf: data)
                try output.write(contentsOf: Data("\r\n".utf8))
            case .file(let name, let filename, let mimeType, let sourceURL):
                try writeFileHeader(name: name, filename: filename, mimeType: mimeType, to: output)
                let input = try FileHandle(forReadingFrom: sourceURL)
                defer { try? input.close() }
                while let chunk = try input.read(upToCount: 256 * 1024), !chunk.isEmpty {
                    try output.write(contentsOf: chunk)
                }
                try output.write(contentsOf: Data("\r\n".utf8))
            }
        }
        try output.write(contentsOf: Data("--\(boundary)--\r\n".utf8))
        return url
    }

    private func writeFileHeader(
        name: String,
        filename: String,
        mimeType: String,
        to output: FileHandle
    ) throws {
        try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
        try output.write(
            contentsOf: Data(
                "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8
            )
        )
        try output.write(contentsOf: Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
    }
}

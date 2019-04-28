//
//  HttpHandlers+Files.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

import Foundation

public enum PartialContentError: Error {
    case invalidRange
}

public func shareFile(_ path: String) -> ((HttpRequest) -> HttpResponse) {
    return { r in
        if let file = try? path.openForReading() {
            return .raw(200, "OK", [:], { writer in
                try? writer.write(file)
                file.close()
            })
        }
        return .notFound
    }
}

public func shareFilesFromDirectory(_ directoryPath: String, defaults: [String] = ["index.html", "default.html"]) -> ((HttpRequest) -> HttpResponse) {
    return { r in
        guard let fileRelativePath = r.params.first else {
            return .notFound
        }
        if fileRelativePath.value.isEmpty {
            for path in defaults {
                if let file = try? (directoryPath + String.pathSeparator + path).openForReading() {
                    return .raw(200, "OK", [:], { writer in
                        try? writer.write(file)
                        file.close()
                    })
                }
            }
        }
        if let file = try? (directoryPath + String.pathSeparator + fileRelativePath.value).openForReading() {
            var mimeType = fileRelativePath.value.mimeType();
            var headers: [String: String] = [:]
            headers["Accept-Ranges"] = "bytes"
            headers["Content-Type"] = mimeType

            if let ranges = r.headers["range"]  {
                print("Ranges: \(ranges)")
                let boundary = UUID().uuidString
                let fileMimeType = mimeType
                let splitRanges = ranges.split("=")
                let rangeType = splitRanges[0]
                let rangeStrings = splitRanges[1].split(",")
                let numberOfRanges = rangeStrings.count
                let fileSize = file.size()
                
                if numberOfRanges == 0 {
                    // Error
                    return .notFound
                } else if numberOfRanges > 1 {
                    mimeType = "multipart/byteranges; boundary=\(boundary)"
                    headers["Content-Type"] = mimeType
                }
                return .partialContent(headers, { writer in
                    for rangeString in rangeStrings {
                        let splitRangeString = rangeString.split("-")
                        if let rangeStart = Int(splitRangeString[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                           let rangeEnd = Int(splitRangeString[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                            if file.seek(rangeStart) {
                                let rangeSize = rangeEnd - rangeStart + 1
                                var data: [UInt8] = Array(repeating: 0, count: rangeSize)
                                let _ = try? file.read(&data)
                                if numberOfRanges == 1 {
                                    headers["Content-Range"] = "\(rangeType) \(rangeString)/\(fileSize)"
                                } else if numberOfRanges > 1 {
                                    try? writer.write("\r\n")
                                    try? writer.write("--\(boundary)\r\n")
                                    try? writer.write("Content-Type: \(fileMimeType)\r\n")
                                    try? writer.write("Content-Range: bytes \(rangeString)/\(fileSize)\r\n")
                                    try? writer.write("\r\n")
                                }
                                try? writer.write(data)
                            }
                        } else {
                            throw PartialContentError.invalidRange
                        }
                    }
                    if numberOfRanges > 1 {
                        try? writer.write("\r\n--\(boundary)--\r\n")
                    }
                    file.close()
                })
            } else {
                return .raw(200, "OK", headers, { writer in
                    try? writer.write(file)
                    file.close()
                })
            }
        }
        return .notFound
    }
}

public func directoryBrowser(_ dir: String) -> ((HttpRequest) -> HttpResponse) {
    return { r in
        guard let (_, value) = r.params.first else {
            return HttpResponse.notFound
        }
        let filePath = dir + String.pathSeparator + value
        do {
            guard try filePath.exists() else {
                return .notFound
            }
            if try filePath.directory() {
                var files = try filePath.files()
                files.sort(by: {$0.lowercased() < $1.lowercased()})
                return scopes {
                    html {
                        body {
                            table(files) { file in
                                tr {
                                    td {
                                        a {
                                            href = r.path + "/" + file
                                            inner = file
                                        }
                                    }
                                }
                            }
                        }
                    }
                    }(r)
            } else {
                guard let file = try? filePath.openForReading() else {
                    return .notFound
                }
                return .raw(200, "OK", [:], { writer in
                    try? writer.write(file)
                    file.close()
                })
            }
        } catch {
            return HttpResponse.internalServerError
        }
    }
}

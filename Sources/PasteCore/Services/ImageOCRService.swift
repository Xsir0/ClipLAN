import Foundation
import Vision

public actor ImageOCRService {
    private let queue = DispatchQueue(label: "app.cliplan.image-ocr", qos: .utility)

    public init() {}

    public func recognizeText(in data: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

                    let handler = VNImageRequestHandler(data: data, options: [:])
                    try handler.perform([request])

                    let text = (request.results ?? [])
                        .compactMap { observation in
                            observation.topCandidates(1).first?.string
                        }
                        .joined(separator: " ")
                        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

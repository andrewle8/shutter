import Foundation
import AppKit
import Vision

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Service for generating AI descriptions of screenshots
class LLMService {
    static let shared = LLMService()

    private init() {}

    /// Generate a description of an image using the configured LLM provider
    /// - Parameters:
    ///   - image: The screenshot image to describe
    ///   - completion: Callback with description or error
    func describeImage(_ image: NSImage, completion: @escaping (Result<String, Error>) -> Void) {
        let settings = SettingsManager.shared.settings

        switch settings.llmProvider {
        case .local:
            Task {
                do {
                    let description = try await describeWithLocal(image: image)
                    DispatchQueue.main.async {
                        completion(.success(description))
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
            return
        case .anthropic, .openai:
            break
        }

        guard !settings.llmApiKey.isEmpty else {
            completion(.failure(LLMError.noAPIKey))
            return
        }

        guard let base64Image = imageToBase64(image) else {
            completion(.failure(LLMError.invalidImage))
            return
        }

        switch settings.llmProvider {
        case .local:
            break // handled above
        case .anthropic:
            describeWithAnthropic(base64Image: base64Image, apiKey: settings.llmApiKey, completion: completion)
        case .openai:
            describeWithOpenAI(base64Image: base64Image, apiKey: settings.llmApiKey, completion: completion)
        }
    }

    /// Generate a description (async version)
    @MainActor
    func describeImage(_ image: NSImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            describeImage(image) { result in
                switch result {
                case .success(let description):
                    continuation.resume(returning: description)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Local (Apple Intelligence)

    private func describeWithLocal(image: NSImage) async throws -> String {
        // Extract text and visual context from the image using Vision framework,
        // then use the on-device language model to generate a coherent description.
        let context = try await extractImageContext(from: image)

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await describeWithFoundationModels(context: context)
        }
        #endif

        // Fallback: construct a description from Vision analysis alone
        return buildFallbackDescription(from: context)
    }

    /// Context extracted from an image via Vision framework
    private struct ImageContext {
        var ocrText: String = ""
        var barcodes: [String] = []
        var faces: Int = 0
        var imageSize: CGSize = .zero
    }

    private func extractImageContext(from image: NSImage) async throws -> ImageContext {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw LLMError.invalidImage
        }

        var context = ImageContext()
        context.imageSize = image.size

        // Run OCR
        let ocrRequest = VNRecognizeTextRequest()
        ocrRequest.recognitionLevel = .accurate
        ocrRequest.usesLanguageCorrection = true

        // Run face detection
        let faceRequest = VNDetectFaceRectanglesRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([ocrRequest, faceRequest])

        // Collect OCR text
        if let observations = ocrRequest.results {
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            context.ocrText = lines.joined(separator: "\n")
        }

        // Count faces
        if let faceResults = faceRequest.results {
            context.faces = faceResults.count
        }

        return context
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func describeWithFoundationModels(context: ImageContext) async throws -> String {
        guard SystemLanguageModel.default.isAvailable else {
            throw LLMError.localModelUnavailable
        }

        let session = LanguageModelSession()

        var promptParts: [String] = []
        promptParts.append("Based on the following analysis of a screenshot, write a concise description (under 100 words) of what the screenshot shows. Focus on the main content and purpose.")
        promptParts.append("")
        promptParts.append("Image dimensions: \(Int(context.imageSize.width))x\(Int(context.imageSize.height))")

        if !context.ocrText.isEmpty {
            let truncatedText = String(context.ocrText.prefix(2000))
            promptParts.append("")
            promptParts.append("Text found in the image:")
            promptParts.append(truncatedText)
        }

        if context.faces > 0 {
            promptParts.append("")
            promptParts.append("Number of faces detected: \(context.faces)")
        }

        if context.ocrText.isEmpty && context.faces == 0 {
            promptParts.append("")
            promptParts.append("No text or faces were detected. This may be a graphic, photo, or UI with minimal text.")
        }

        let prompt = promptParts.joined(separator: "\n")
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif

    private func buildFallbackDescription(from context: ImageContext) -> String {
        var parts: [String] = []

        if !context.ocrText.isEmpty {
            let preview = String(context.ocrText.prefix(200))
            parts.append("Screenshot containing text: \"\(preview)\"")
        }

        if context.faces > 0 {
            parts.append("\(context.faces) face(s) detected")
        }

        let dimensions = "\(Int(context.imageSize.width))x\(Int(context.imageSize.height))"

        if parts.isEmpty {
            return "Screenshot (\(dimensions)) — no text detected. Apple Intelligence is required for detailed descriptions on this macOS version."
        }

        return parts.joined(separator: ". ") + " (\(dimensions))"
    }

    // MARK: - Anthropic API

    private func describeWithAnthropic(base64Image: String, apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            completion(.failure(LLMError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/png",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": "Please describe this screenshot concisely. Focus on the main content and purpose of what's shown. Keep the description under 100 words."
                        ]
                    ]
                ]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(LLMError.noResponse))
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let content = json["content"] as? [[String: Any]],
                   let firstContent = content.first,
                   let text = firstContent["text"] as? String {
                    DispatchQueue.main.async {
                        completion(.success(text))
                    }
                } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let errorInfo = json["error"] as? [String: Any],
                          let message = errorInfo["message"] as? String {
                    DispatchQueue.main.async {
                        completion(.failure(LLMError.apiError(message)))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(LLMError.invalidResponse))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - OpenAI API

    private func describeWithOpenAI(base64Image: String, apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            completion(.failure(LLMError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-4o",
            "max_tokens": 500,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": "Please describe this screenshot concisely. Focus on the main content and purpose of what's shown. Keep the description under 100 words."
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/png;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(LLMError.noResponse))
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    DispatchQueue.main.async {
                        completion(.success(content))
                    }
                } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let errorInfo = json["error"] as? [String: Any],
                          let message = errorInfo["message"] as? String {
                    DispatchQueue.main.async {
                        completion(.failure(LLMError.apiError(message)))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(LLMError.invalidResponse))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Helpers

    private func imageToBase64(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData.base64EncodedString()
    }
}

// MARK: - LLM Errors
enum LLMError: LocalizedError {
    case noAPIKey
    case invalidImage
    case invalidURL
    case noResponse
    case invalidResponse
    case apiError(String)
    case localModelUnavailable

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add your API key in Settings."
        case .invalidImage:
            return "Could not process the image"
        case .invalidURL:
            return "Invalid API URL"
        case .noResponse:
            return "No response from API"
        case .invalidResponse:
            return "Invalid response from API"
        case .apiError(let message):
            return message
        case .localModelUnavailable:
            return "Apple Intelligence is not available on this device. Please use macOS 26 or later on Apple Silicon, or switch to a cloud provider in Settings."
        }
    }
}

import Foundation
import AppKit
import CoreGraphics

/// Service for area-based scrolling capture.
/// The user selects a screen region, then the service auto-scrolls and captures
/// that same region repeatedly, stitching overlapping frames together.
@MainActor
class ScrollingCaptureService: ObservableObject {
    static let shared = ScrollingCaptureService()

    @Published var isCapturing = false
    @Published var capturedFrames: [NSImage] = []
    @Published var progress: CGFloat = 0

    private var captureRect: CGRect = .zero   // Global display coordinates
    private var captureScreen: NSScreen?
    private var onComplete: ((NSImage?) -> Void)?
    private let maxFrames = 20

    private init() {}

    // MARK: - Public Methods

    /// Start area-based scrolling capture.
    /// `rect` is the user-selected area in the capture window's coordinate space
    /// (top-left origin, same as AreaSelectionView provides).
    /// `screen` is the screen the selection was made on.
    func startAreaScrollingCapture(rect: CGRect, screen: NSScreen, completion: @escaping (NSImage?) -> Void) {
        guard !isCapturing else { return }

        self.isCapturing = true
        self.capturedFrames = []
        self.progress = 0
        self.onComplete = completion
        self.captureScreen = screen

        // Convert selection rect to global display coordinates
        // (same conversion as ScreenCaptureService.captureArea)
        let roundedRect = CGRect(
            x: round(rect.origin.x),
            y: round(rect.origin.y),
            width: round(rect.width),
            height: round(rect.height)
        )
        self.captureRect = CGRect(
            x: roundedRect.origin.x + screen.frame.origin.x,
            y: roundedRect.origin.y + screen.frame.origin.y,
            width: roundedRect.width,
            height: roundedRect.height
        )

        NSLog("[ScrollingCapture] Starting area scrolling capture, rect: %@", NSStringFromRect(captureRect))

        // Begin the auto-scroll capture loop
        runCaptureLoop()
    }

    /// Cancel the capture
    func cancelCapture() {
        isCapturing = false
        capturedFrames = []
        progress = 0
        onComplete?(nil)
        onComplete = nil
    }

    // MARK: - Capture Loop

    private func runCaptureLoop() {
        // Capture the first frame
        guard let firstFrame = captureCurrentRect() else {
            NSLog("[ScrollingCapture] Failed to capture first frame")
            finishWithResult()
            return
        }
        capturedFrames.append(firstFrame)
        progress = CGFloat(capturedFrames.count) / CGFloat(maxFrames)

        // Start the scroll-capture cycle
        scrollAndCaptureNext()
    }

    private func scrollAndCaptureNext() {
        guard isCapturing else { return }
        guard capturedFrames.count < maxFrames else {
            NSLog("[ScrollingCapture] Reached max frames (%d), finishing", maxFrames)
            finishWithResult()
            return
        }

        // Scroll down by ~80% of the selected area height to ensure overlap
        let scrollAmount = Int(captureRect.height * 0.8)
        postScrollEvent(deltaY: -scrollAmount)

        // Wait for rendering after scroll
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self = self, self.isCapturing else { return }

            guard let newFrame = self.captureCurrentRect() else {
                NSLog("[ScrollingCapture] Failed to capture frame %d, finishing", self.capturedFrames.count + 1)
                self.finishWithResult()
                return
            }

            // Check if content has changed by comparing with the previous frame
            if self.framesAreIdentical(self.capturedFrames.last!, newFrame) {
                NSLog("[ScrollingCapture] No new content detected after %d frames, finishing", self.capturedFrames.count)
                self.finishWithResult()
                return
            }

            self.capturedFrames.append(newFrame)
            self.progress = CGFloat(self.capturedFrames.count) / CGFloat(self.maxFrames)
            NSLog("[ScrollingCapture] Captured frame %d", self.capturedFrames.count)

            // Continue scrolling
            self.scrollAndCaptureNext()
        }
    }

    // MARK: - Capture & Scroll Helpers

    private func captureCurrentRect() -> NSImage? {
        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenBelowWindow,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            return nil
        }

        // Use point size (not pixel size) for correct Retina handling
        return NSImage(cgImage: cgImage, size: NSSize(
            width: captureRect.width,
            height: captureRect.height
        ))
    }

    private func postScrollEvent(deltaY: Int) {
        // CGEvent scroll uses pixel units; negative = scroll down
        let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(deltaY),
            wheel2: 0,
            wheel3: 0
        )
        // Position the scroll event at the center of the capture area
        let centerPoint = CGPoint(
            x: captureRect.midX,
            y: captureRect.midY
        )
        scrollEvent?.location = centerPoint
        scrollEvent?.post(tap: .cgSessionEventTap)
    }

    /// Quick check: are two frames essentially the same? (content stopped scrolling)
    private func framesAreIdentical(_ a: NSImage, _ b: NSImage) -> Bool {
        guard let aCG = a.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let bCG = b.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }

        guard let aData = aCG.dataProvider?.data,
              let bData = bCG.dataProvider?.data else {
            return false
        }

        let aPtr = CFDataGetBytePtr(aData)
        let bPtr = CFDataGetBytePtr(bData)
        let bytesPerRow = aCG.bytesPerRow
        let width = min(aCG.width, bCG.width)
        let height = min(aCG.height, bCG.height)

        // Sample several rows across the image
        let rowsToCheck = min(20, height)
        let rowStep = max(1, height / rowsToCheck)
        var totalDifferences = 0

        for rowIdx in stride(from: 0, to: height, by: rowStep) {
            let offset = rowIdx * bytesPerRow
            let sampleInterval = max(1, width / 50) // Sample 50 pixels per row

            for x in stride(from: 0, to: width * 4, by: sampleInterval * 4) {
                for channel in 0..<3 {
                    guard let aPtr = aPtr, let bPtr = bPtr else { return false }
                    let aVal = Int(aPtr[offset + x + channel])
                    let bVal = Int(bPtr[offset + x + channel])
                    if abs(aVal - bVal) > 10 {
                        totalDifferences += 1
                    }
                }
            }
        }

        // If very few differences, frames are effectively the same
        return totalDifferences < 15
    }

    // MARK: - Finish & Stitch

    private func finishWithResult() {
        isCapturing = false

        if capturedFrames.count > 1 {
            let stitched = stitchImages(capturedFrames)
            onComplete?(stitched)
        } else if capturedFrames.count == 1 {
            onComplete?(capturedFrames.first)
        } else {
            onComplete?(nil)
        }

        capturedFrames = []
        progress = 0
        onComplete = nil
    }

    // MARK: - Image Stitching

    /// Stitch multiple images together vertically (scrolling down)
    private func stitchImages(_ images: [NSImage]) -> NSImage? {
        guard !images.isEmpty else { return nil }
        guard images.count > 1 else { return images.first }

        var result = images[0]

        for i in 1..<images.count {
            let currentImage = images[i]

            if let stitched = stitchTwoImages(result, currentImage) {
                result = stitched
            } else {
                // No overlap found, append vertically
                if let combined = combineVertically(result, currentImage) {
                    result = combined
                }
            }
        }

        return result
    }

    /// Stitch two images by finding and removing the overlapping region
    private func stitchTwoImages(_ top: NSImage, _ bottom: NSImage) -> NSImage? {
        guard let topCG = top.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let bottomCG = bottom.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let overlapHeight = findOverlap(topImage: topCG, bottomImage: bottomCG)

        if overlapHeight > 0 {
            let totalHeight = top.size.height + bottom.size.height - CGFloat(overlapHeight)
            let width = max(top.size.width, bottom.size.width)

            let newImage = NSImage(size: NSSize(width: width, height: totalHeight))
            newImage.lockFocus()

            // Draw top image at top, bottom image below (minus overlap)
            top.draw(in: NSRect(x: 0, y: totalHeight - top.size.height, width: top.size.width, height: top.size.height))
            bottom.draw(in: NSRect(x: 0, y: 0, width: bottom.size.width, height: bottom.size.height))

            newImage.unlockFocus()
            return newImage
        }

        return nil
    }

    /// Find vertical overlap between two consecutive frames
    private func findOverlap(topImage: CGImage, bottomImage: CGImage) -> Int {
        let maxOverlap = min(topImage.height, bottomImage.height) / 2
        let stripHeight = 20

        guard let topData = topImage.dataProvider?.data,
              let bottomData = bottomImage.dataProvider?.data else {
            return 0
        }

        let topPtr = CFDataGetBytePtr(topData)
        let bottomPtr = CFDataGetBytePtr(bottomData)

        let bytesPerRow = topImage.bytesPerRow
        let width = min(topImage.width, bottomImage.width)

        for overlap in stride(from: stripHeight, to: maxOverlap, by: stripHeight) {
            var matches = 0
            let samplesNeeded = 5

            for sample in 0..<samplesNeeded {
                let topRow = topImage.height - overlap + (sample * stripHeight / samplesNeeded)
                let bottomRow = sample * stripHeight / samplesNeeded

                if compareRows(topPtr, bottomPtr, topRow: topRow, bottomRow: bottomRow, bytesPerRow: bytesPerRow, width: width) {
                    matches += 1
                }
            }

            if matches >= samplesNeeded - 1 {
                return overlap
            }
        }

        return 0
    }

    /// Compare two rows of pixels with tolerance
    private func compareRows(_ topPtr: UnsafePointer<UInt8>?, _ bottomPtr: UnsafePointer<UInt8>?, topRow: Int, bottomRow: Int, bytesPerRow: Int, width: Int) -> Bool {
        guard let topPtr = topPtr, let bottomPtr = bottomPtr else { return false }

        let topOffset = topRow * bytesPerRow
        let bottomOffset = bottomRow * bytesPerRow

        var differences = 0
        let tolerance = 10
        let sampleInterval = max(1, width / 100)

        for x in stride(from: 0, to: width * 4, by: sampleInterval * 4) {
            for channel in 0..<3 {
                let topValue = Int(topPtr[topOffset + x + channel])
                let bottomValue = Int(bottomPtr[bottomOffset + x + channel])
                if abs(topValue - bottomValue) > tolerance {
                    differences += 1
                }
            }
        }

        return differences < 10
    }

    /// Combine two images vertically without overlap detection
    private func combineVertically(_ top: NSImage, _ bottom: NSImage) -> NSImage? {
        let totalHeight = top.size.height + bottom.size.height
        let width = max(top.size.width, bottom.size.width)

        let newImage = NSImage(size: NSSize(width: width, height: totalHeight))
        newImage.lockFocus()

        top.draw(in: NSRect(x: 0, y: bottom.size.height, width: top.size.width, height: top.size.height))
        bottom.draw(in: NSRect(x: 0, y: 0, width: bottom.size.width, height: bottom.size.height))

        newImage.unlockFocus()
        return newImage
    }
}

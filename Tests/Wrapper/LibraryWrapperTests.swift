import XCTest
import SwiftLibass
@testable import SwiftAssRenderer

#if hasAttribute(retroactive)
extension OpaquePointer: @unchecked @retroactive Sendable {}
extension ASS_Track: @unchecked @retroactive Sendable {}
#endif

final class LibraryWrapperTests: XCTestCase, @unchecked Sendable {
    private let iterations = 10_000

    private var cachesDirectory: URL {
        if #available(iOS 16.0, tvOS 16.0, visionOS 1.0, macOS 13.0, *) {
            URL.cachesDirectory
        } else {
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        }
    }

    func test_libraryLogger_isThreadSafety() {
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            LibraryWrapper.libraryLogger = { _, _ in }
        }
    }

    func test_libraryInit_isThreadSafety() {
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            _ = LibraryWrapper.libraryInit()
        }
    }

    func test_libraryDone_isThreadSafety() throws {
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            guard let library = LibraryWrapper.libraryInit() else { return }
            LibraryWrapper.libraryDone(library)
        }
    }

    func test_rendererInit_isThreadSafety() throws {
        let library = try XCTUnwrap(LibraryWrapper.libraryInit())
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            _ = LibraryWrapper.rendererInit(library)
        }
    }

    func test_rendererDone_isThreadSafety() throws {
        let library = try XCTUnwrap(LibraryWrapper.libraryInit())
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            guard let renderer = LibraryWrapper.rendererInit(library) else { return }
            LibraryWrapper.rendererDone(renderer)
        }
    }

    func test_setLogCallback_isThreadSafety() throws {
        let library = try XCTUnwrap(LibraryWrapper.libraryInit())
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            LibraryWrapper.setLogCallback(library)
        }
    }

    func test_setRendererSize_isThreadSafety() throws {
        let library = try XCTUnwrap(LibraryWrapper.libraryInit())
        let renderer = try XCTUnwrap(LibraryWrapper.rendererInit(library))
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            LibraryWrapper.setRendererSize(renderer, size: CGSize(width: 1920, height: 1080))
        }
    }

    func test_setExtractFonts_isThreadSafety() throws {
        let library = try XCTUnwrap(LibraryWrapper.libraryInit())
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            LibraryWrapper.setExtractFonts(library, extract: .random())
        }
    }

    func test_setFonts_coreText_isThreadSafety() throws {
        let library = try XCTUnwrap(LibraryWrapper.libraryInit())
        let renderer = try XCTUnwrap(LibraryWrapper.rendererInit(library))
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            LibraryWrapper.setFonts(
                renderer,
                provider: .coreText,
                defaultFont: "Arial",
                defaultFamily: "Regular"
            )
        }
    }

    func test_setFonts_fontConfig_isThreadSafety() throws {
        let library = try XCTUnwrap(LibraryWrapper.libraryInit())
        let renderer = try XCTUnwrap(LibraryWrapper.rendererInit(library))
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            LibraryWrapper.setFonts(
                renderer,
                provider: .fontConfig,
                configPath: cachesDirectory.appendingPathComponent("fonts.conf").path,
                defaultFont: "Arial",
                defaultFamily: "Regular"
            )
        }
    }

    func test_addFont_isThreadSafety() throws {
        let fontPath = try XCTUnwrap(Bundle.module.resourceURL?.appendingPathComponent("Fonts/tahoma.ttf"))
        let data = try Data(contentsOf: fontPath)
        let library = try XCTUnwrap(LibraryWrapper.libraryInit())
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            LibraryWrapper.addFont(library, name: "tahoma.ttf", data: data)
        }
    }

    func test_addFont_whenUsingCoreText_shouldSelectEmbeddedFont() throws {
        let fontPath = try XCTUnwrap(Bundle.module.resourceURL?.appendingPathComponent("Fonts/AdobeArabic-Bold.otf"))
        let library = try XCTUnwrap(LibraryWrapper.libraryInit())
        let renderer = try XCTUnwrap(LibraryWrapper.rendererInit(library))
        let previousLogger = LibraryWrapper.libraryLogger
        nonisolated(unsafe) var messages: [String] = []
        LibraryWrapper.libraryLogger = { _, message in messages.append(message) }
        defer { LibraryWrapper.libraryLogger = previousLogger }
        LibraryWrapper.setLogCallback(library)

        LibraryWrapper.addFont(library, name: "AdobeArabic-Bold.otf", data: try Data(contentsOf: fontPath))
        LibraryWrapper.setFonts(renderer, provider: .coreText)
        LibraryWrapper.setRendererSize(renderer, size: CGSize(width: 640, height: 360))
        var track = try XCTUnwrap(LibraryWrapper.readTrack(library, content: """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: 640
        PlayResY: 360

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, Bold
        Style: Default,Adobe Arabic,32,-1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:00.00,0:00:05.00,Default,,0,0,0,,Hello
        """))

        XCTAssertNotNil(LibraryWrapper.renderImage(renderer, track: &track, at: 1))
        let selection = messages.first { $0.hasPrefix("fontselect: (Adobe Arabic") }
        XCTAssert(selection?.contains("AdobeArabic-Bold") == true, "\(messages)")
    }

    func test_readTrack_isThreadSafety() throws {
        let contentsPath = try XCTUnwrap(Bundle.module.resourceURL?.appendingPathComponent("Subs/en.ass"))
        let content = try String(contentsOfFile: contentsPath.path)
        let library = try XCTUnwrap(LibraryWrapper.libraryInit())
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            _ = LibraryWrapper.readTrack(library, content: content)
        }
    }

    func test_renderImage_isThreadSafety() throws {
        let contentsPath = try XCTUnwrap(Bundle.module.resourceURL?.appendingPathComponent("Subs/en.ass"))
        let content = try String(contentsOfFile: contentsPath.path)
        let library = try XCTUnwrap(LibraryWrapper.libraryInit())
        let renderer = try XCTUnwrap(LibraryWrapper.rendererInit(library))
        nonisolated(unsafe) var track = try XCTUnwrap(LibraryWrapper.readTrack(library, content: content))
        LibraryWrapper.setRendererSize(renderer, size: CGSize(width: 320, height: 240))
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            _ = LibraryWrapper.renderImage(renderer, track: &track, at: 40.0)
        }
    }
}

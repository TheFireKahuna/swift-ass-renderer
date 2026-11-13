import Foundation
import SwiftLibass
@testable import SwiftAssRenderer

final class MockLibraryWrapper: LibraryWrapperType {
    nonisolated(unsafe) static var libraryLogger: (Int, String) -> Void = { _, _ in }

    /// Static state outlives a test; every test starts from these defaults.
    static func reset() {
        libraryInitStub = nil
        rendererInitStub = nil
        readTrackStub = nil
        newTrackStub = nil
        colorMatrixStub = 0
        renderImageStub = LibraryRenderResult(image: nil, changed: false)
        setFontsCalledBeforeAddFont = false
        [setLogCallbackFunc.reset, libraryInitFunc.reset, libraryDoneFunc.reset, rendererInitFunc.reset,
         rendererDoneFunc.reset, setRendererSizeFunc.reset, setMarginsFunc.reset, setUseMarginsFunc.reset,
         setStorageSizeFunc.reset, setExtractFontsFunc.reset, addFontFunc.reset, setFontsFunc.reset,
         readTrackFunc.reset, newTrackFunc.reset, processChunkFunc.reset, colorMatrixFunc.reset,
         freeTrackFunc.reset, renderImageFunc.reset].forEach { $0() }
    }

    static let setLogCallbackFunc = FuncCheck<OpaquePointer>()
    static func setLogCallback(_ library: OpaquePointer) {
        setLogCallbackFunc.call(library)
    }

    static let libraryInitFunc = FuncCheck<Void>()
    nonisolated(unsafe) static var libraryInitStub: OpaquePointer?
    static func libraryInit() -> OpaquePointer? {
        libraryInitFunc.call()
        return libraryInitStub
    }

    static let libraryDoneFunc = FuncCheck<OpaquePointer>()
    static func libraryDone(_ library: OpaquePointer) {
        libraryDoneFunc.call(library)
    }

    static let rendererInitFunc = FuncCheck<OpaquePointer>()
    nonisolated(unsafe) static var rendererInitStub: OpaquePointer?
    static func rendererInit(_ library: OpaquePointer) -> OpaquePointer? {
        rendererInitFunc.call(library)
        return rendererInitStub
    }

    static let rendererDoneFunc = FuncCheck<OpaquePointer>()
    static func rendererDone(_ renderer: OpaquePointer) {
        rendererDoneFunc.call(renderer)
    }

    static let setRendererSizeFunc = FuncCheck<(OpaquePointer, CGSize)>()
    static func setRendererSize(_ renderer: OpaquePointer, size: CGSize) {
        setRendererSizeFunc.call((renderer, size))
    }

    static let setMarginsFunc = FuncCheck<(OpaquePointer, FrameMargins)>()
    static func setMargins(_ renderer: OpaquePointer, margins: FrameMargins) {
        setMarginsFunc.call((renderer, margins))
        setMarginsFunc.arguments.append((renderer, margins))
    }

    static let setUseMarginsFunc = FuncCheck<(OpaquePointer, Bool)>()
    static func setUseMargins(_ renderer: OpaquePointer, use: Bool) {
        setUseMarginsFunc.call((renderer, use))
    }

    static let setStorageSizeFunc = FuncCheck<(OpaquePointer, CGSize)>()
    static func setStorageSize(_ renderer: OpaquePointer, size: CGSize) {
        setStorageSizeFunc.call((renderer, size))
    }

    static let setExtractFontsFunc = FuncCheck<(OpaquePointer, Bool)>()
    static func setExtractFonts(_ library: OpaquePointer, extract: Bool) {
        setExtractFontsFunc.call((library, extract))
    }

    static let addFontFunc = FuncCheck<(OpaquePointer, String, Data)>()
    nonisolated(unsafe) static var setFontsCalledBeforeAddFont = false
    static func addFont(_ library: OpaquePointer, name: String, data: Data) {
        setFontsCalledBeforeAddFont = setFontsCalledBeforeAddFont || setFontsFunc.wasCalled
        addFontFunc.call((library, name, data))
        addFontFunc.arguments.append((library, name, data))
    }

    static let setFontsFunc = FuncCheck<(OpaquePointer, FontProvider, String?, String?, String?)>()
    static func setFonts(
        _ renderer: OpaquePointer,
        provider: FontProvider,
        configPath: String?,
        defaultFont: String?,
        defaultFamily: String?
    ) {
        setFontsFunc.call((renderer, provider, configPath, defaultFont, defaultFamily))
    }

    static let readTrackFunc = FuncCheck<(OpaquePointer, String)>()
    nonisolated(unsafe) static var readTrackStub: ASS_Track?
    static func readTrack(_ library: OpaquePointer, content: String) -> UnsafeMutablePointer<ASS_Track>? {
        readTrackFunc.call((library, content))
        return readTrackStub.map { stub in
            let track = UnsafeMutablePointer<ASS_Track>.allocate(capacity: 1)
            track.initialize(to: stub)
            return track
        }
    }

    static let newTrackFunc = FuncCheck<(OpaquePointer, String)>()
    nonisolated(unsafe) static var newTrackStub: ASS_Track?
    static func newTrack(_ library: OpaquePointer, header: String) -> UnsafeMutablePointer<ASS_Track>? {
        newTrackFunc.call((library, header))
        return newTrackStub.map { stub in
            let track = UnsafeMutablePointer<ASS_Track>.allocate(capacity: 1)
            track.initialize(to: stub)
            return track
        }
    }

    static let processChunkFunc = FuncCheck<(UnsafeMutablePointer<ASS_Track>, AssEvent)>()
    static func processChunk(_ track: UnsafeMutablePointer<ASS_Track>, event: AssEvent) {
        processChunkFunc.call((track, event))
        processChunkFunc.arguments.append((track, event))
    }

    static let colorMatrixFunc = FuncCheck<UnsafeMutablePointer<ASS_Track>>()
    nonisolated(unsafe) static var colorMatrixStub: Int32 = 0
    static func colorMatrix(of track: UnsafeMutablePointer<ASS_Track>) -> Int32 {
        colorMatrixFunc.call(track)
        return colorMatrixStub
    }

    static let freeTrackFunc = FuncCheck<UnsafeMutablePointer<ASS_Track>>()
    static func freeTrack(_ track: UnsafeMutablePointer<ASS_Track>) {
        freeTrackFunc.call(track)
        freeTrackFunc.arguments.append(track)
        track.deallocate()
    }

    static let renderImageFunc = FuncCheck<(OpaquePointer, ASS_Track, TimeInterval)>()
    nonisolated(unsafe) static var renderImageStub = LibraryRenderResult(image: nil, changed: false)
    static func renderImage(
        _ renderer: OpaquePointer,
        track: inout ASS_Track,
        at offset: TimeInterval
    ) -> LibraryRenderResult {
        renderImageFunc.call((renderer, track, offset))
        renderImageFunc.arguments.append((renderer, track, offset))
        return renderImageStub
    }
}

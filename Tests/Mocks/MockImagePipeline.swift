import CoreGraphics
import SwiftLibass
import SwiftAssBlend
@testable import SwiftAssRenderer

final class MockImagePipeline: ImagePipelineType {
    let processFunc = FuncCheck<([ASS_Image], AssColorTransform)>()
    nonisolated(unsafe) var processStub: ProcessedImage?
    func process(images: [ASS_Image], colorTransform: AssColorTransform) -> ProcessedImage? {
        processFunc.call((images, colorTransform))
        return processStub
    }
}

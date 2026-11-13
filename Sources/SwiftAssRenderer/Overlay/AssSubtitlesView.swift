#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import SwiftUI
import Combine

/// Callback called when the subtitle image is set, updated or removed.
/// The `dialogues` argument is not sanitized and might include ASS formatting tags.
public typealias AssSubtitlesImageCallback = (
    _ subtitlesView: AssSubtitlesView,
    _ processedImage: ProcessedImage?,
    _ dialogues: [String]
) -> Void

/// `UIView` /  `NSView` capable or drawing rendered image bitmaps to the screen,
/// by subscribing to ``AssSubtitlesRenderer``  events and drawing each ``ProcessedImage`` tile in a layer.
public final class AssSubtitlesView: PlatformView {
    public let renderer: AssSubtitlesRenderer

    private let canvasScale: CGFloat
    private let tilesLayer = CALayer()
    private var tileLayers: [CALayer] = []
    private var lastRenderBounds = CGRect.zero
    private var cancellables = Set<AnyCancellable>()
    private var imageCallback: AssSubtitlesImageCallback?

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    #if canImport(UIKit)
    public init(renderer: AssSubtitlesRenderer, scale: CGFloat = UITraitCollection.current.displayScale) {
        self.renderer = renderer
        self.canvasScale = scale
        super.init(frame: .zero)
        configure()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        resizeCanvas()
    }
    #elseif canImport(AppKit)
    public init(renderer: AssSubtitlesRenderer, scale: CGFloat = 2.0) {
        self.renderer = renderer
        self.canvasScale = scale
        super.init(frame: .zero)
        configure()
    }

    public override func layout() {
        super.layout()

        resizeCanvas()
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
    #endif

    @MainActor
    private func resizeCanvas() {
        resizeImageAtLayout()
        renderer.setCanvasSize(bounds.size, scale: canvasScale)
    }
}

public extension AssSubtitlesView {
    /// Assign a callback to be called when subtitle image is set, changed or removed.
    ///
    /// - Parameters:
    ///   - callback: Callback to call.
    ///
    /// Calling this multiple times will override previous callbacks.
    @MainActor
    @discardableResult
    func onImageChanged(_ callback: AssSubtitlesImageCallback?) -> Self {
        imageCallback = callback
        return self
    }
}

private extension AssSubtitlesView {
    @MainActor
    func configure() {
        setupView()
        subscribeToEvents()
    }

    @MainActor
    func setupView() {
        #if canImport(UIKit)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        layer.addSublayer(tilesLayer)
        #elseif canImport(AppKit)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(tilesLayer)
        #endif
    }

    @MainActor
    func subscribeToEvents() {
        renderer
            .framesPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                switch frame.result {
                case .unchanged: break
                case .none: self?.handleFrameChanged(nil)
                case .loaded(let image): self?.handleFrameChanged(image)
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    func handleFrameChanged(_ image: ProcessedImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lastRenderBounds = bounds
        tilesLayer.setAffineTransform(.identity)
        tilesLayer.frame = CGRect(origin: .zero, size: bounds.size)
        let tiles = image?.tiles ?? []
        while tileLayers.count < tiles.count {
            let tileLayer = CALayer()
            tileLayer.contentsGravity = .resize
            tilesLayer.addSublayer(tileLayer)
            tileLayers.append(tileLayer)
        }
        for (index, tileLayer) in tileLayers.enumerated() {
            if index < tiles.count {
                tileLayer.contents = tiles[index].image
                tileLayer.frame = imageFrame(for: tiles[index].rect)
                tileLayer.isHidden = false
            } else {
                tileLayer.contents = nil
                tileLayer.isHidden = true
            }
        }
        CATransaction.commit()
        if let imageCallback {
            let dialogues = renderer.dialogues(at: renderer.currentOffset)
            imageCallback(self, image, dialogues)
        }
    }

    /// Stretches the shown tiles with the view until the renderer delivers a frame for the new size.
    @MainActor
    func resizeImageAtLayout() {
        if lastRenderBounds.isEmpty || bounds.isEmpty { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tilesLayer.bounds = CGRect(origin: .zero, size: lastRenderBounds.size)
        tilesLayer.setAffineTransform(CGAffineTransform(
            scaleX: bounds.width / lastRenderBounds.width, y: bounds.height / lastRenderBounds.height
        ))
        tilesLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    @MainActor
    func imageFrame(for rect: CGRect) -> CGRect {
        #if canImport(UIKit)
        rect
        #elseif canImport(AppKit)
        // macOS has the origin on bottom left corner
        rect.flippingY(for: bounds.height)
        #endif
    }
}

import SwiftUI
import MetalKit

// MARK: - Dithering Background View

struct DitheringBackgroundView: View {
    var shape: DitheringShape = .simplex
    var ditherType: DitheringType = .bayer8x8
    var colorBack: Color = Color(red: 0.02, green: 0.01, blue: 0.04)
    var colorFront: Color = Color(red: 0.08, green: 0.04, blue: 0.12)
    var pixelSize: CGFloat = 6
    var speed: CGFloat = 0.3
    var opacity: Double = 0.6

    var body: some View {
        GeometryReader { geo in
            DitheringBackgroundMetalView(
                shape: shape,
                ditherType: ditherType,
                colorBack: colorBack,
                colorFront: colorFront,
                pixelSize: pixelSize,
                speed: speed,
                size: geo.size
            )
            .opacity(opacity)
        }
    }
}

// MARK: - Metal View for Background

struct DitheringBackgroundMetalView: NSViewRepresentable {
    var shape: DitheringShape
    var ditherType: DitheringType
    var colorBack: Color
    var colorFront: Color
    var pixelSize: CGFloat
    var speed: CGFloat
    var size: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()

        guard let device = MTLCreateSystemDefaultDevice() else {
            return mtkView
        }

        mtkView.device = device
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 30 // Lower FPS for background
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.layer?.isOpaque = false

        context.coordinator.setupMetal(device: device, view: mtkView)

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.shape = Float(shape.rawValue)
        context.coordinator.ditherType = Float(ditherType.rawValue)
        context.coordinator.colorBack = colorToSIMD(colorBack)
        context.coordinator.colorFront = colorToSIMD(colorFront)
        context.coordinator.pixelSize = Float(pixelSize)
        context.coordinator.speed = Float(speed)
        context.coordinator.resolution = SIMD2<Float>(Float(size.width), Float(size.height))
    }

    private func colorToSIMD(_ color: Color) -> SIMD4<Float> {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor.black
        return SIMD4<Float>(
            Float(nsColor.redComponent),
            Float(nsColor.greenComponent),
            Float(nsColor.blueComponent),
            Float(nsColor.alphaComponent)
        )
    }

    class Coordinator: NSObject, MTKViewDelegate {
        var device: MTLDevice?
        var commandQueue: MTLCommandQueue?
        var pipelineState: MTLRenderPipelineState?
        var vertexBuffer: MTLBuffer?

        var startTime: Date = Date()
        var shape: Float = 1
        var ditherType: Float = 4
        var colorBack: SIMD4<Float> = SIMD4(0.02, 0.01, 0.04, 1)
        var colorFront: SIMD4<Float> = SIMD4(0.08, 0.04, 0.12, 1)
        var pixelSize: Float = 6
        var speed: Float = 0.3
        var resolution: SIMD2<Float> = SIMD2(800, 600)

        func setupMetal(device: MTLDevice, view: MTKView) {
            self.device = device
            self.commandQueue = device.makeCommandQueue()

            guard let library = loadShaderLibrary(device: device) else {
                return
            }

            guard let vertexFunction = library.makeFunction(name: "ditheringVertex"),
                  let fragmentFunction = library.makeFunction(name: "ditheringFragment") else {
                return
            }

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            do {
                pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                return
            }

            let vertices: [SIMD2<Float>] = [
                SIMD2(-1, -1), SIMD2(1, -1), SIMD2(-1, 1),
                SIMD2(-1, 1), SIMD2(1, -1), SIMD2(1, 1)
            ]
            vertexBuffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<SIMD2<Float>>.stride * vertices.count, options: [])
        }

        private func loadShaderLibrary(device: MTLDevice) -> MTLLibrary? {
            // Try default library first (works in Xcode builds with .metal files)
            if let library = device.makeDefaultLibrary(),
               library.functionNames.contains("ditheringFragment") {
                return library
            }

            // Compile from embedded source (works in SPM builds)
            do {
                return try device.makeLibrary(source: ShaderSources.dithering, options: nil)
            } catch {
                print("Failed to compile dithering shader: \(error)")
                return nil
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            resolution = SIMD2<Float>(Float(size.width), Float(size.height))
        }

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let pipelineState = pipelineState,
                  let commandBuffer = commandQueue?.makeCommandBuffer(),
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }

            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

            var time = Float(Date().timeIntervalSince(startTime)) * speed
            var resolutionValue = resolution
            var colorBackValue = colorBack
            var colorFrontValue = colorFront
            var shapeValue = shape
            var ditherTypeValue = ditherType
            var pixelSizeValue = pixelSize
            var audioLevel: Float = 0.0

            renderEncoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 0)
            renderEncoder.setFragmentBytes(&resolutionValue, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
            renderEncoder.setFragmentBytes(&colorBackValue, length: MemoryLayout<SIMD4<Float>>.size, index: 2)
            renderEncoder.setFragmentBytes(&colorFrontValue, length: MemoryLayout<SIMD4<Float>>.size, index: 3)
            renderEncoder.setFragmentBytes(&shapeValue, length: MemoryLayout<Float>.size, index: 4)
            renderEncoder.setFragmentBytes(&ditherTypeValue, length: MemoryLayout<Float>.size, index: 5)
            renderEncoder.setFragmentBytes(&pixelSizeValue, length: MemoryLayout<Float>.size, index: 6)
            renderEncoder.setFragmentBytes(&audioLevel, length: MemoryLayout<Float>.size, index: 7)

            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

// MARK: - View Modifier for Dithering Background

struct DitheringBackgroundModifier: ViewModifier {
    var shape: DitheringShape = .simplex
    var colorFront: Color = Color(red: 0.1, green: 0.05, blue: 0.15)

    func body(content: Content) -> some View {
        content
            .background(
                DitheringBackgroundView(
                    shape: shape,
                    ditherType: .bayer8x8,
                    colorBack: Color(red: 0.02, green: 0.01, blue: 0.04),
                    colorFront: colorFront,
                    pixelSize: 5,
                    speed: 0.2,
                    opacity: 0.5
                )
            )
    }
}

extension View {
    func ditheringBackground(shape: DitheringShape = .simplex, colorFront: Color = Color(red: 0.1, green: 0.05, blue: 0.15)) -> some View {
        modifier(DitheringBackgroundModifier(shape: shape, colorFront: colorFront))
    }
}

// MARK: - Dithered Panel Style

struct DitheredPanelStyle: ViewModifier {
    var isActive: Bool = false
    var cornerRadius: CGFloat = 4

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Base background - adapts to appearance
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.tuiBackground)

                    // Subtle dithering overlay - adapts to appearance
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(LinearGradient.glassOverlay)

                    // Active glow
                    if isActive {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.tuiAccent.opacity(0.3), lineWidth: 1)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(LinearGradient.subtleBorder, lineWidth: 1)
            )
    }
}

extension View {
    func ditheredPanel(isActive: Bool = false, cornerRadius: CGFloat = 4) -> some View {
        modifier(DitheredPanelStyle(isActive: isActive, cornerRadius: cornerRadius))
    }
}

// MARK: - Dithered Accent Text

struct DitheredAccentText: View {
    let text: String
    var font: Font = .tuiMonoSmall
    var isActive: Bool = true

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(isActive ? .primary : .secondary)
    }
}

// MARK: - Scanline Overlay

struct ScanlineOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
    var opacity: Double = 0.03
    var lineSpacing: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                // Use black lines on light mode, keep black on dark mode for CRT effect
                let lineColor = Color.black.opacity(colorScheme == .light ? opacity * 0.5 : opacity)
                for y in stride(from: 0, to: size.height, by: lineSpacing) {
                    let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                    context.fill(Path(rect), with: .color(lineColor))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

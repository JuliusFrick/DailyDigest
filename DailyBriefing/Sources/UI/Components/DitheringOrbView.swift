import SwiftUI
import MetalKit

// MARK: - Dithering Shape Types

enum DitheringShape: Int, CaseIterable {
    case simplex = 1
    case warp = 2
    case dots = 3
    case wave = 4
    case ripple = 5
    case swirl = 6
    case sphere = 7
}

enum DitheringType: Int, CaseIterable {
    case random = 1
    case bayer2x2 = 2
    case bayer4x4 = 3
    case bayer8x8 = 4
}

// MARK: - Dithering Orb View

struct DitheringOrbView: View {
    var shape: DitheringShape = .swirl
    var ditherType: DitheringType = .bayer4x4
    var colorBack: Color = Color(red: 0.13, green: 0, blue: 0.07)
    var colorFront: Color = .cyan
    var pixelSize: CGFloat = 4
    var speed: CGFloat = 0.9
    var audioLevel: CGFloat = 0.0
    var size: CGFloat = 120

    var body: some View {
        DitheringMetalView(
            shape: shape,
            ditherType: ditherType,
            colorBack: colorBack,
            colorFront: colorFront,
            pixelSize: pixelSize,
            speed: speed,
            audioLevel: audioLevel
        )
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: colorFront.opacity(0.4), radius: 15)
    }
}

// MARK: - Metal View Wrapper

struct DitheringMetalView: NSViewRepresentable {
    var shape: DitheringShape
    var ditherType: DitheringType
    var colorBack: Color
    var colorFront: Color
    var pixelSize: CGFloat
    var speed: CGFloat
    var audioLevel: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()

        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return mtkView
        }

        mtkView.device = device
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
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
        context.coordinator.audioLevel = Float(audioLevel)
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

    // MARK: - Coordinator

    class Coordinator: NSObject, MTKViewDelegate {
        var device: MTLDevice?
        var commandQueue: MTLCommandQueue?
        var pipelineState: MTLRenderPipelineState?
        var vertexBuffer: MTLBuffer?

        var startTime: Date = Date()
        var shape: Float = 6 // swirl
        var ditherType: Float = 3 // 4x4
        var colorBack: SIMD4<Float> = SIMD4(0.13, 0, 0.07, 1)
        var colorFront: SIMD4<Float> = SIMD4(0, 1, 1, 1)
        var pixelSize: Float = 4
        var speed: Float = 0.9
        var audioLevel: Float = 0.0

        func setupMetal(device: MTLDevice, view: MTKView) {
            self.device = device
            self.commandQueue = device.makeCommandQueue()

            // Try loading from bundle first, then fall back to runtime compilation
            guard let library = loadShaderLibrary(device: device) else {
                print("Failed to load Metal shader library")
                return
            }

            guard let vertexFunction = library.makeFunction(name: "ditheringVertex"),
                  let fragmentFunction = library.makeFunction(name: "ditheringFragment") else {
                print("Failed to find dithering shader functions")
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
                print("Failed to create dithering pipeline state: \(error)")
                return
            }

            let vertices: [SIMD2<Float>] = [
                SIMD2(-1, -1),
                SIMD2( 1, -1),
                SIMD2(-1,  1),
                SIMD2(-1,  1),
                SIMD2( 1, -1),
                SIMD2( 1,  1)
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

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

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
            var resolution = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
            var colorBackValue = colorBack
            var colorFrontValue = colorFront
            var shapeValue = shape
            var ditherTypeValue = ditherType
            var pixelSizeValue = pixelSize
            var audioLevelValue = audioLevel

            renderEncoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 0)
            renderEncoder.setFragmentBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
            renderEncoder.setFragmentBytes(&colorBackValue, length: MemoryLayout<SIMD4<Float>>.size, index: 2)
            renderEncoder.setFragmentBytes(&colorFrontValue, length: MemoryLayout<SIMD4<Float>>.size, index: 3)
            renderEncoder.setFragmentBytes(&shapeValue, length: MemoryLayout<Float>.size, index: 4)
            renderEncoder.setFragmentBytes(&ditherTypeValue, length: MemoryLayout<Float>.size, index: 5)
            renderEncoder.setFragmentBytes(&pixelSizeValue, length: MemoryLayout<Float>.size, index: 6)
            renderEncoder.setFragmentBytes(&audioLevelValue, length: MemoryLayout<Float>.size, index: 7)

            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        // MARK: - Embedded Shader Source (Fallback for SPM)

        static let ditheringShaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        #define TWO_PI 6.28318530718
        #define PI 3.14159265358979323846

        struct DitheringVertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        float hash11(float p) {
            p = fract(p * 0.3183099) + 0.1;
            p *= p + 19.19;
            return fract(p * p);
        }

        float hash21(float2 p) {
            p = fract(p * float2(0.3183099, 0.3678794)) + 0.1;
            p += dot(p, p + 19.19);
            return fract(p.x * p.y);
        }

        float3 permute(float3 x) { return fmod(((x * 34.0) + 1.0) * x, 289.0); }

        float snoise(float2 v) {
            const float4 C = float4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
            float2 i = floor(v + dot(v, C.yy));
            float2 x0 = v - i + dot(i, C.xx);
            float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
            float4 x12 = x0.xyxy + C.xxzz;
            x12.xy -= i1;
            i = fmod(i, 289.0);
            float3 p = permute(permute(i.y + float3(0.0, i1.y, 1.0)) + i.x + float3(0.0, i1.x, 1.0));
            float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
            m = m * m * m * m;
            float3 x = 2.0 * fract(p * C.www) - 1.0;
            float3 h = abs(x) - 0.5;
            float3 ox = floor(x + 0.5);
            float3 a0 = x - ox;
            m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
            float3 g;
            g.x = a0.x * x0.x + h.x * x0.y;
            g.yz = a0.yz * x12.xz + h.yz * x12.yw;
            return 130.0 * dot(m, g);
        }

        float getSimplexNoise(float2 uv, float t) {
            float noise = 0.5 * snoise(uv - float2(0.0, 0.3 * t));
            noise += 0.5 * snoise(2.0 * uv + float2(0.0, 0.32 * t));
            return noise;
        }

        constant int bayer2x2[4] = {0, 2, 3, 1};
        constant int bayer4x4[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};
        constant int bayer8x8[64] = {0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26, 12, 44, 4, 36, 14, 46, 6, 38, 60, 28, 52, 20, 62, 30, 54, 22, 3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25, 15, 47, 7, 39, 13, 45, 5, 37, 63, 31, 55, 23, 61, 29, 53, 21};

        float getBayerValue(float2 uv, int size) {
            int2 pos = int2(fmod(uv, float(size)));
            int index = pos.y * size + pos.x;
            if (size == 2) return float(bayer2x2[index]) / 4.0;
            else if (size == 4) return float(bayer4x4[index]) / 16.0;
            else return float(bayer8x8[index]) / 64.0;
        }

        fragment float4 ditheringFragment(
            DitheringVertexOut in [[stage_in]],
            constant float &time [[buffer(0)]],
            constant float2 &resolution [[buffer(1)]],
            constant float4 &colorBack [[buffer(2)]],
            constant float4 &colorFront [[buffer(3)]],
            constant float &shapeType [[buffer(4)]],
            constant float &ditherType [[buffer(5)]],
            constant float &pxSize [[buffer(6)]],
            constant float &audioLevel [[buffer(7)]]
        ) {
            float t = 0.5 * time;
            float2 uv = in.texCoord - 0.5;
            float2 pxSizeUv = in.texCoord * resolution;
            pxSizeUv -= 0.5 * resolution;
            pxSizeUv /= pxSize;
            float2 pixelizedUv = floor(pxSizeUv) * pxSize / resolution;
            pixelizedUv += 0.5;
            pixelizedUv -= 0.5;
            float2 shape_uv = pixelizedUv;
            float2 dithering_uv = pxSizeUv;
            float2 ditheringNoise_uv = uv * resolution;
            float audioBoost = 1.0 + audioLevel * 0.5;
            float shape = 0.0;
            int shapeInt = int(shapeType);

            if (shapeInt == 1) {
                float2 noiseUv = shape_uv * 0.001 * (1.0 + audioLevel);
                shape = 0.5 + 0.5 * getSimplexNoise(noiseUv, t * audioBoost);
                shape = smoothstep(0.3, 0.9, shape);
            } else if (shapeInt == 2) {
                float2 warpUv = shape_uv * 0.003;
                for (float i = 1.0; i < 6.0; i++) {
                    warpUv.x += 0.6 / i * cos(i * 2.5 * warpUv.y + t * audioBoost);
                    warpUv.y += 0.6 / i * cos(i * 1.5 * warpUv.x + t * audioBoost);
                }
                shape = 0.15 / abs(sin(t - warpUv.y - warpUv.x));
                shape = smoothstep(0.02, 1.0, shape);
            } else if (shapeInt == 3) {
                float2 dotUv = shape_uv * 0.05;
                float stripeIdx = floor(2.0 * dotUv.x / TWO_PI);
                float rand = hash11(stripeIdx * 10.0);
                rand = sign(rand - 0.5) * pow(0.1 + abs(rand), 0.4);
                shape = sin(dotUv.x) * cos(dotUv.y - 5.0 * rand * t * audioBoost);
                shape = pow(abs(shape), 6.0);
            } else if (shapeInt == 4) {
                float2 waveUv = shape_uv * 4.0;
                float wave = cos(0.5 * waveUv.x - 2.0 * t * audioBoost) * sin(1.5 * waveUv.x + t) * (0.75 + 0.25 * cos(3.0 * t));
                shape = 1.0 - smoothstep(-1.0, 1.0, waveUv.y + wave);
            } else if (shapeInt == 5) {
                float dist = length(shape_uv);
                float waves = sin(pow(dist, 1.7) * 7.0 - 3.0 * t * audioBoost) * 0.5 + 0.5;
                shape = waves;
            } else if (shapeInt == 6) {
                float l = length(shape_uv);
                float angle = 6.0 * atan2(shape_uv.y, shape_uv.x) + 4.0 * t * audioBoost;
                float twist = 1.2;
                float offset = pow(l, -twist) + angle / TWO_PI;
                float mid = smoothstep(0.0, 1.0, pow(l, twist));
                shape = mix(0.0, fract(offset), mid);
            } else {
                float minBubbleScale = 0.82;
                float bubblePulse = mix(1.0, minBubbleScale, clamp(audioLevel, 0.0, 1.0));
                float2 sphereUv = shape_uv * 2.0 * bubblePulse;
                float d = 1.0 - pow(length(sphereUv), 2.0);
                float3 pos = float3(sphereUv, sqrt(max(d, 0.0)));
                float3 lightPos = normalize(float3(cos(1.5 * t), 0.8, sin(1.25 * t)));
                shape = 0.5 + 0.5 * dot(lightPos, pos);
                shape *= step(0.0, d);
            }

            int ditherInt = int(ditherType);
            float dithering = 0.0;
            if (ditherInt == 1) {
                dithering = step(hash21(ditheringNoise_uv), shape);
            } else if (ditherInt == 2) {
                dithering = getBayerValue(dithering_uv, 2);
            } else if (ditherInt == 3) {
                dithering = getBayerValue(dithering_uv, 4);
            } else {
                dithering = getBayerValue(dithering_uv, 8);
            }
            if (ditherInt != 1) {
                dithering -= 0.5;
                dithering = step(0.5, shape + dithering);
            }

            float3 fgColor = colorFront.rgb * colorFront.a;
            float fgOpacity = colorFront.a;
            float3 bgColor = colorBack.rgb * colorBack.a;
            float bgOpacity = colorBack.a;
            float3 color = fgColor * dithering;
            float opacity = fgOpacity * dithering;
            color += bgColor * (1.0 - opacity);
            opacity += bgOpacity * (1.0 - opacity);
            return float4(color, opacity);
        }

        vertex DitheringVertexOut ditheringVertex(uint vertexID [[vertex_id]], constant float2 *vertices [[buffer(0)]]) {
            DitheringVertexOut out;
            float2 pos = vertices[vertexID];
            out.position = float4(pos, 0.0, 1.0);
            out.texCoord = pos * 0.5 + 0.5;
            return out;
        }
        """
    }
}

// MARK: - Preview

#if DEBUG
struct DitheringOrbView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            DitheringOrbView(shape: .swirl, colorBack: Color(red: 0.13, green: 0, blue: 0.07), colorFront: .cyan)
            DitheringOrbView(shape: .ripple, colorBack: .black, colorFront: .purple, audioLevel: 0.5)
            DitheringOrbView(shape: .warp, colorBack: Color(red: 0.05, green: 0, blue: 0.1), colorFront: .pink)
        }
        .padding()
        .background(Color.black)
    }
}
#endif

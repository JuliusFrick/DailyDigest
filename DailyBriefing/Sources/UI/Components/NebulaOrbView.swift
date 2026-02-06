import SwiftUI
import MetalKit

// MARK: - Nebula Orb View

/// A SwiftUI view that renders an animated nebula orb using Metal shaders
/// The orb reacts to audio input levels and recording state
struct NebulaOrbView: View {
    /// Audio input level (0.0 - 1.0)
    var audioLevel: CGFloat = 0.0
    
    /// Whether recording is active
    var isRecording: Bool = false
    
    /// Size of the orb
    var size: CGFloat = 120
    
    var body: some View {
        NebulaMetalView(audioLevel: audioLevel, isRecording: isRecording)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .shadow(color: isRecording ? .purple.opacity(0.5) : .blue.opacity(0.3), radius: isRecording ? 20 : 10)
            .animation(.easeInOut(duration: 0.3), value: isRecording)
    }
}

// MARK: - Metal View Wrapper

struct NebulaMetalView: NSViewRepresentable {
    var audioLevel: CGFloat
    var isRecording: Bool
    
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
        
        // Setup Metal pipeline
        context.coordinator.setupMetal(device: device, view: mtkView)
        
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.audioLevel = Float(audioLevel)
        context.coordinator.isRecording = isRecording ? 1.0 : 0.0
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, MTKViewDelegate {
        var device: MTLDevice?
        var commandQueue: MTLCommandQueue?
        var pipelineState: MTLRenderPipelineState?
        var vertexBuffer: MTLBuffer?
        
        var startTime: Date = Date()
        var audioLevel: Float = 0.0
        var isRecording: Float = 0.0
        
        func setupMetal(device: MTLDevice, view: MTKView) {
            self.device = device
            self.commandQueue = device.makeCommandQueue()

            // Load shader library with fallback for SPM
            guard let library = loadShaderLibrary(device: device) else {
                print("Failed to load Metal library")
                return
            }

            guard let vertexFunction = library.makeFunction(name: "nebulaVertex"),
                  let fragmentFunction = library.makeFunction(name: "nebulaFragment") else {
                print("Failed to find shader functions")
                return
            }
            
            // Create render pipeline
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
                print("Failed to create pipeline state: \(error)")
                return
            }
            
            // Create fullscreen quad vertices
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
               library.functionNames.contains("nebulaFragment") {
                return library
            }

            // Compile from embedded source (works in SPM builds)
            do {
                return try device.makeLibrary(source: ShaderSources.nebula, options: nil)
            } catch {
                print("Failed to compile nebula shader: \(error)")
                return nil
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle resize if needed
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
            
            // Set uniforms
            var time = Float(Date().timeIntervalSince(startTime))
            var audioLevelValue = audioLevel
            var isRecordingValue = isRecording
            var resolution = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
            
            renderEncoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 0)
            renderEncoder.setFragmentBytes(&audioLevelValue, length: MemoryLayout<Float>.size, index: 1)
            renderEncoder.setFragmentBytes(&isRecordingValue, length: MemoryLayout<Float>.size, index: 2)
            renderEncoder.setFragmentBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.size, index: 3)
            
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            
            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        // MARK: - Embedded Shader Source (Fallback for SPM)

        static let nebulaShaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        float2x2 rotate2D(float angle) {
            float c = cos(angle);
            float s = sin(angle);
            return float2x2(c, -s, s, c);
        }

        float nebulaMap(float3 p, float time, float audioLevel) {
            p.xz = rotate2D(time * 0.4) * p.xz;
            p.xy = rotate2D(time * 0.3) * p.xy;
            float audioBoost = 1.0 + audioLevel * 2.0;
            float3 q = p * 2.0 + time * audioBoost;
            float sineWave = sin(q.x + sin(q.z + sin(q.y))) * 0.5;
            float pulse = 1.0 + audioLevel * 0.3;
            return length(p + float3(sin(time * 0.7 * audioBoost))) * log(length(p) + 1.0) * pulse + sineWave - 1.0;
        }

        fragment float4 nebulaFragment(
            VertexOut in [[stage_in]],
            constant float &time [[buffer(0)]],
            constant float &audioLevel [[buffer(1)]],
            constant float &isRecording [[buffer(2)]],
            constant float2 &resolution [[buffer(3)]]
        ) {
            float2 uv = in.texCoord - 0.5;
            uv.x *= resolution.x / resolution.y;
            float3 col = float3(0.0);
            float d = 2.5;
            for (int i = 0; i <= 5; i++) {
                float3 p = float3(0.0, 0.0, 5.0) + normalize(float3(uv, -1.0)) * d;
                float rz = nebulaMap(p, time, audioLevel);
                float f = clamp((rz - nebulaMap(p + 0.1, time, audioLevel)) * 0.5, -0.1, 1.0);
                float3 baseColor;
                if (isRecording > 0.5) {
                    float audioColor = audioLevel * 0.5;
                    baseColor = float3(0.15 + audioColor, 0.05, 0.3) + float3(3.0 + audioColor * 2.0, 1.5, 4.0) * f;
                } else {
                    baseColor = float3(0.05, 0.1, 0.2) + float3(1.5, 2.0, 3.5) * f;
                }
                col = col * baseColor + smoothstep(2.5, 0.0, rz) * 0.7 * baseColor;
                d += min(rz, 1.0);
            }
            float dist = length(in.texCoord - 0.5) * 2.0;
            float edge = smoothstep(1.0, 0.85, dist);
            float glow = 0.0;
            if (isRecording > 0.5) {
                glow = smoothstep(1.0, 0.7, dist) * (1.0 - smoothstep(0.7, 0.5, dist));
                glow *= 0.5 + audioLevel * 0.5;
                col += float3(0.8, 0.2, 1.0) * glow * 0.3;
            }
            col *= edge;
            float alpha = edge * 0.95;
            return float4(col, alpha);
        }

        vertex VertexOut nebulaVertex(uint vertexID [[vertex_id]], constant float2 *vertices [[buffer(0)]]) {
            VertexOut out;
            float2 pos = vertices[vertexID];
            out.position = float4(pos, 0.0, 1.0);
            out.texCoord = pos * 0.5 + 0.5;
            return out;
        }
        """
    }
}

// MARK: - Preview

// #Preview {
//     VStack(spacing: 20) {
//         // Idle state
//         NebulaOrbView(audioLevel: 0.0, isRecording: false, size: 100)
//        
//         // Recording with low audio
//         NebulaOrbView(audioLevel: 0.3, isRecording: true, size: 100)
//        
//         // Recording with high audio
//         NebulaOrbView(audioLevel: 0.8, isRecording: true, size: 100)
//     }
//     .padding()
//     .background(Color.black)
// }

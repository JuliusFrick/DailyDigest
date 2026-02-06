import Foundation

// MARK: - Embedded Metal Shader Sources
// These are compiled at runtime using device.makeLibrary(source:)
// The original .metal files are kept in docs/shaders/ for reference

enum ShaderSources {
    
    /// Dithering shader source for visual effects
    static let dithering = """
    #include <metal_stdlib>
    using namespace metal;

    #define TWO_PI 6.28318530718
    #define PI 3.14159265358979323846

    struct DitheringVertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    // Noise functions
    float hash11(float p) {
        p = fract(p * 0.3183099) + 0.1;
        p *= p + 19.19;
        return fract(p * p);
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

    // Bayer matrices
    constant int bayer4x4[16] = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
    constant int bayer8x8[64] = {
        0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26,
        12, 44, 4, 36, 14, 46, 6, 38, 60, 28, 52, 20, 62, 30, 54, 22,
        3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25,
        15, 47, 7, 39, 13, 45, 5, 37, 63, 31, 55, 23, 61, 29, 53, 21
    };

    float getBayer4x4(float2 uv, float2 res, float pixelSize) {
        int2 p = int2(fmod(uv * res / pixelSize, 4.0));
        return float(bayer4x4[p.y * 4 + p.x]) / 16.0;
    }

    float getBayer8x8(float2 uv, float2 res, float pixelSize) {
        int2 p = int2(fmod(uv * res / pixelSize, 8.0));
        return float(bayer8x8[p.y * 8 + p.x]) / 64.0;
    }

    float getShape(float2 uv, float t, int shape) {
        float2 center = float2(0.5);
        float2 d = uv - center;
        
        if (shape == 0) { // simplex
            return getSimplexNoise(uv * 3.0, t) * 0.5 + 0.5;
        } else if (shape == 1) { // warp
            float angle = atan2(d.y, d.x);
            float radius = length(d);
            float warp = sin(angle * 3.0 + t) * 0.1;
            return getSimplexNoise(uv * 2.0 + warp, t * 0.5) * 0.5 + 0.5;
        } else if (shape == 2) { // dots
            float2 grid = fract(uv * 8.0) - 0.5;
            float dot = 1.0 - smoothstep(0.2, 0.3, length(grid));
            return dot * (sin(t + length(uv * 4.0)) * 0.5 + 0.5);
        } else if (shape == 3) { // wave
            return sin(uv.x * 10.0 + t) * sin(uv.y * 10.0 + t * 0.7) * 0.5 + 0.5;
        } else if (shape == 4) { // ripple
            float dist = length(d);
            return sin(dist * 20.0 - t * 2.0) * 0.5 + 0.5;
        } else if (shape == 5) { // sphere
            float dist = length(d);
            float sphere = 1.0 - smoothstep(0.0, 0.5, dist);
            float noise = getSimplexNoise(uv * 4.0, t * 0.3);
            return sphere * (0.7 + noise * 0.3);
        } else { // swirl (default)
            float angle = atan2(d.y, d.x);
            float radius = length(d);
            float swirl = angle + radius * 4.0 - t;
            return sin(swirl * 3.0) * 0.5 + 0.5;
        }
    }

    vertex DitheringVertexOut ditheringVertex(uint vid [[vertex_id]], constant float2* vertices [[buffer(0)]]) {
        DitheringVertexOut out;
        out.position = float4(vertices[vid], 0.0, 1.0);
        out.texCoord = vertices[vid] * 0.5 + 0.5;
        return out;
    }

    fragment float4 ditheringFragment(
        DitheringVertexOut in [[stage_in]],
        constant float& time [[buffer(0)]],
        constant float2& resolution [[buffer(1)]],
        constant float4& colorBack [[buffer(2)]],
        constant float4& colorFront [[buffer(3)]],
        constant float& shape [[buffer(4)]],
        constant float& ditherType [[buffer(5)]],
        constant float& pixelSize [[buffer(6)]],
        constant float& audioLevel [[buffer(7)]]
    ) {
        float2 uv = in.texCoord;
        
        float value = getShape(uv, time, int(shape));
        value = value * (1.0 + audioLevel * 0.3);
        
        float dither;
        if (ditherType < 2.0) {
            dither = getBayer4x4(uv, resolution, pixelSize);
        } else {
            dither = getBayer8x8(uv, resolution, pixelSize);
        }
        
        float threshold = step(dither, value);
        float4 color = mix(colorBack, colorFront, threshold);
        
        return color;
    }
    """
    
    /// Nebula shader source for orb effects
    static let nebula = """
    #include <metal_stdlib>
    using namespace metal;

    struct NebulaVertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    float hash(float2 p) {
        return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
    }

    float noise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        
        float a = hash(i);
        float b = hash(i + float2(1.0, 0.0));
        float c = hash(i + float2(0.0, 1.0));
        float d = hash(i + float2(1.0, 1.0));
        
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    float fbm(float2 p, float t) {
        float value = 0.0;
        float amplitude = 0.5;
        float2 shift = float2(100.0);
        
        for (int i = 0; i < 5; i++) {
            value += amplitude * noise(p);
            p = p * 2.0 + shift;
            p.x += t * 0.1;
            amplitude *= 0.5;
        }
        return value;
    }

    vertex NebulaVertexOut nebulaVertex(uint vid [[vertex_id]], constant float2* vertices [[buffer(0)]]) {
        NebulaVertexOut out;
        out.position = float4(vertices[vid], 0.0, 1.0);
        out.texCoord = vertices[vid] * 0.5 + 0.5;
        return out;
    }

    fragment float4 nebulaFragment(
        NebulaVertexOut in [[stage_in]],
        constant float& time [[buffer(0)]],
        constant float2& resolution [[buffer(1)]],
        constant float& audioLevel [[buffer(2)]],
        constant float& isRecording [[buffer(3)]]
    ) {
        float2 uv = in.texCoord;
        float2 center = float2(0.5);
        float2 d = uv - center;
        float dist = length(d);
        
        // Create circular mask
        float mask = 1.0 - smoothstep(0.3, 0.5, dist);
        
        // Nebula effect
        float2 q = float2(fbm(uv * 3.0, time), fbm(uv * 3.0 + float2(1.0), time));
        float2 r = float2(fbm(uv * 3.0 + q + float2(1.7, 9.2) + 0.15 * time, time),
                         fbm(uv * 3.0 + q + float2(8.3, 2.8) + 0.126 * time, time));
        float f = fbm(uv * 3.0 + r, time);
        
        // Color based on recording state
        float3 color1 = isRecording > 0.5 ? float3(0.6, 0.1, 0.8) : float3(0.1, 0.3, 0.8);
        float3 color2 = isRecording > 0.5 ? float3(1.0, 0.2, 0.5) : float3(0.2, 0.6, 1.0);
        float3 color3 = float3(0.9, 0.9, 1.0);
        
        float3 color = mix(color1, color2, f);
        color = mix(color, color3, pow(f, 2.0) * 0.5);
        
        // Audio reactivity
        float pulse = 1.0 + audioLevel * 0.3;
        color *= pulse;
        
        // Glow at edges
        float glow = smoothstep(0.5, 0.3, dist) * 0.5;
        color += glow * (isRecording > 0.5 ? float3(0.8, 0.2, 1.0) : float3(0.3, 0.5, 1.0));
        
        return float4(color * mask, mask);
    }
    """
}

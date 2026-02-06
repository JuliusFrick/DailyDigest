#include <metal_stdlib>
using namespace metal;

// MARK: - Nebula Orb Shader
// A ray-marched nebula effect that reacts to audio input

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Rotation matrix for 3D animation
float2x2 rotate2D(float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2x2(c, -s, s, c);
}

// 3D Signed Distance Function for the nebula effect
float nebulaMap(float3 p, float time, float audioLevel) {
    // Rotate the space over time
    p.xz = rotate2D(time * 0.4) * p.xz;
    p.xy = rotate2D(time * 0.3) * p.xy;
    
    // Add audio reactivity to the animation speed/intensity
    float audioBoost = 1.0 + audioLevel * 2.0;
    
    // Create the nebula shape
    float3 q = p * 2.0 + time * audioBoost;
    float sineWave = sin(q.x + sin(q.z + sin(q.y))) * 0.5;
    
    // Core shape with audio-reactive pulsing
    float pulse = 1.0 + audioLevel * 0.3;
    return length(p + float3(sin(time * 0.7 * audioBoost))) * log(length(p) + 1.0) * pulse + sineWave - 1.0;
}

// Fragment shader
fragment float4 nebulaFragment(
    VertexOut in [[stage_in]],
    constant float &time [[buffer(0)]],
    constant float &audioLevel [[buffer(1)]],
    constant float &isRecording [[buffer(2)]],
    constant float2 &resolution [[buffer(3)]]
) {
    // Normalize coordinates to center
    float2 uv = in.texCoord - 0.5;
    uv.x *= resolution.x / resolution.y; // Aspect ratio correction
    
    float3 col = float3(0.0);
    float d = 2.5;
    
    // Ray march loop
    for (int i = 0; i <= 5; i++) {
        float3 p = float3(0.0, 0.0, 5.0) + normalize(float3(uv, -1.0)) * d;
        float rz = nebulaMap(p, time, audioLevel);
        float f = clamp((rz - nebulaMap(p + 0.1, time, audioLevel)) * 0.5, -0.1, 1.0);
        
        // Color palette based on recording state
        float3 baseColor;
        if (isRecording > 0.5) {
            // Recording: Vibrant purple/magenta with audio reactivity
            float audioColor = audioLevel * 0.5;
            baseColor = float3(0.15 + audioColor, 0.05, 0.3) + float3(3.0 + audioColor * 2.0, 1.5, 4.0) * f;
        } else {
            // Idle: Subtle blue/cyan
            baseColor = float3(0.05, 0.1, 0.2) + float3(1.5, 2.0, 3.5) * f;
        }
        
        col = col * baseColor + smoothstep(2.5, 0.0, rz) * 0.7 * baseColor;
        d += min(rz, 1.0);
    }
    
    // Circular mask for orb shape
    float dist = length(in.texCoord - 0.5) * 2.0;
    float edge = smoothstep(1.0, 0.85, dist);
    
    // Add glow around edges when recording
    float glow = 0.0;
    if (isRecording > 0.5) {
        glow = smoothstep(1.0, 0.7, dist) * (1.0 - smoothstep(0.7, 0.5, dist));
        glow *= 0.5 + audioLevel * 0.5;
        col += float3(0.8, 0.2, 1.0) * glow * 0.3;
    }
    
    // Apply circular mask
    col *= edge;
    float alpha = edge * 0.95;
    
    return float4(col, alpha);
}

// Vertex shader (fullscreen quad)
vertex VertexOut nebulaVertex(
    uint vertexID [[vertex_id]],
    constant float2 *vertices [[buffer(0)]]
) {
    VertexOut out;
    float2 pos = vertices[vertexID];
    out.position = float4(pos, 0.0, 1.0);
    out.texCoord = pos * 0.5 + 0.5;
    return out;
}

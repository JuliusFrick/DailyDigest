#include <metal_stdlib>
using namespace metal;

// MARK: - Dithering Shader
// A dithering effect with multiple shape types, ported from GLSL
// Shapes: simplex, warp, dots, wave, ripple, swirl, sphere

#define TWO_PI 6.28318530718
#define PI 3.14159265358979323846

struct DitheringVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// MARK: - Noise Functions

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

// Simplex noise
float3 permute(float3 x) { return fmod(((x * 34.0) + 1.0) * x, 289.0); }

float snoise(float2 v) {
    const float4 C = float4(0.211324865405187, 0.366025403784439,
        -0.577350269189626, 0.024390243902439);
    float2 i = floor(v + dot(v, C.yy));
    float2 x0 = v - i + dot(i, C.xx);
    float2 i1;
    i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = fmod(i, 289.0);
    float3 p = permute(permute(i.y + float3(0.0, i1.y, 1.0))
        + i.x + float3(0.0, i1.x, 1.0));
    float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy),
        dot(x12.zw, x12.zw)), 0.0);
    m = m * m;
    m = m * m;
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

// MARK: - Bayer Dithering Matrices

constant int bayer2x2[4] = {0, 2, 3, 1};
constant int bayer4x4[16] = {
    0,  8,  2, 10,
   12,  4, 14,  6,
    3, 11,  1,  9,
   15,  7, 13,  5
};
constant int bayer8x8[64] = {
     0, 32,  8, 40,  2, 34, 10, 42,
    48, 16, 56, 24, 50, 18, 58, 26,
    12, 44,  4, 36, 14, 46,  6, 38,
    60, 28, 52, 20, 62, 30, 54, 22,
     3, 35, 11, 43,  1, 33,  9, 41,
    51, 19, 59, 27, 49, 17, 57, 25,
    15, 47,  7, 39, 13, 45,  5, 37,
    63, 31, 55, 23, 61, 29, 53, 21
};

float getBayerValue(float2 uv, int size) {
    int2 pos = int2(fmod(uv, float(size)));
    int index = pos.y * size + pos.x;

    if (size == 2) {
        return float(bayer2x2[index]) / 4.0;
    } else if (size == 4) {
        return float(bayer4x4[index]) / 16.0;
    } else {
        return float(bayer8x8[index]) / 64.0;
    }
}

// MARK: - Fragment Shader

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

    // Apply pixelization
    float2 pxSizeUv = in.texCoord * resolution;
    pxSizeUv -= 0.5 * resolution;
    pxSizeUv /= pxSize;
    float2 pixelizedUv = floor(pxSizeUv) * pxSize / resolution;
    pixelizedUv += 0.5;
    pixelizedUv -= 0.5;

    float2 shape_uv = pixelizedUv;
    float2 dithering_uv = pxSizeUv;
    float2 ditheringNoise_uv = uv * resolution;

    // Audio boost for reactive shapes
    float audioBoost = 1.0 + audioLevel * 0.5;

    float shape = 0.0;
    int shapeInt = int(shapeType);

    // Shape 1: Simplex noise
    if (shapeInt == 1) {
        float2 noiseUv = shape_uv * 0.001 * (1.0 + audioLevel);
        shape = 0.5 + 0.5 * getSimplexNoise(noiseUv, t * audioBoost);
        shape = smoothstep(0.3, 0.9, shape);
    }
    // Shape 2: Warp
    else if (shapeInt == 2) {
        float2 warpUv = shape_uv * 0.003;
        for (float i = 1.0; i < 6.0; i++) {
            warpUv.x += 0.6 / i * cos(i * 2.5 * warpUv.y + t * audioBoost);
            warpUv.y += 0.6 / i * cos(i * 1.5 * warpUv.x + t * audioBoost);
        }
        shape = 0.15 / abs(sin(t - warpUv.y - warpUv.x));
        shape = smoothstep(0.02, 1.0, shape);
    }
    // Shape 3: Dots
    else if (shapeInt == 3) {
        float2 dotUv = shape_uv * 0.05;
        float stripeIdx = floor(2.0 * dotUv.x / TWO_PI);
        float rand = hash11(stripeIdx * 10.0);
        rand = sign(rand - 0.5) * pow(0.1 + abs(rand), 0.4);
        shape = sin(dotUv.x) * cos(dotUv.y - 5.0 * rand * t * audioBoost);
        shape = pow(abs(shape), 6.0);
    }
    // Shape 4: Sine wave
    else if (shapeInt == 4) {
        float2 waveUv = shape_uv * 4.0;
        float wave = cos(0.5 * waveUv.x - 2.0 * t * audioBoost) * sin(1.5 * waveUv.x + t) * (0.75 + 0.25 * cos(3.0 * t));
        shape = 1.0 - smoothstep(-1.0, 1.0, waveUv.y + wave);
    }
    // Shape 5: Ripple
    else if (shapeInt == 5) {
        float dist = length(shape_uv);
        float waves = sin(pow(dist, 1.7) * 7.0 - 3.0 * t * audioBoost) * 0.5 + 0.5;
        shape = waves;
    }
    // Shape 6: Swirl (default)
    else if (shapeInt == 6) {
        float l = length(shape_uv);
        float angle = 6.0 * atan2(shape_uv.y, shape_uv.x) + 4.0 * t * audioBoost;
        float twist = 1.2;
        float offset = pow(l, -twist) + angle / TWO_PI;
        float mid = smoothstep(0.0, 1.0, pow(l, twist));
        shape = mix(0.0, fract(offset), mid);
    }
    // Shape 7: Sphere
    else {
        float2 sphereUv = shape_uv * 2.0;
        float d = 1.0 - pow(length(sphereUv), 2.0);
        float3 pos = float3(sphereUv, sqrt(max(d, 0.0)));
        float3 lightPos = normalize(float3(cos(1.5 * t), 0.8, sin(1.25 * t)));
        shape = 0.5 + 0.5 * dot(lightPos, pos);
        shape *= step(0.0, d);
    }

    // Dithering
    int ditherInt = int(ditherType);
    float dithering = 0.0;

    if (ditherInt == 1) {
        // Random/noise dithering
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

    // Color mixing
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

// MARK: - Vertex Shader

vertex DitheringVertexOut ditheringVertex(
    uint vertexID [[vertex_id]],
    constant float2 *vertices [[buffer(0)]]
) {
    DitheringVertexOut out;
    float2 pos = vertices[vertexID];
    out.position = float4(pos, 0.0, 1.0);
    out.texCoord = pos * 0.5 + 0.5;
    return out;
}

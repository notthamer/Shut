#include <metal_stdlib>
using namespace metal;

// Shared between every transition. Must match TransitionUniforms.swift exactly.
struct TransitionUniforms {
    float4 glowColor;

    float2 snapshotSize;
    float2 outputSize;
    float2 sink;
    float2 notchSize;

    float progress;
    float time;
    float maxDistance;

    float falloff;
    float twist;
    float stretch;
    float overshoot;
    int   blurSamples;
    float blurStrength;
    float darken;
    float aberration;
    float glow;
    float sinkRadius;
    float virtualNotch;

    float maxBlur;
    float frostSpread;
    float darknessStart;
    float mipLevels;

    float reduceTransparency;
    float pull;
    float vortex;
    float edgeSoftness;
    float holeGrowth;
    float pad2;

    // Panel family. Same order as TransitionUniforms.swift.
    float2 meshScale;
    float2 meshTranslate;
    float foldAngle;
    float foldPosition;
    float perspective;
    float curvature;
    float creaseHighlight;
    float aspect;
    float blur;
    float blurGradient;
    float wash;
    float cornerRadius;
    float brightness;
    float opacity;
    float vignette;
    float edgeOcclusion;
    float maskOpenness;
    uint  maskKind;
    uint  blades;
    uint  useTexture;
    float maxLOD;
    float pad3;
};

// Copies a spread of fields into a buffer so a test can prove the Swift and
// Metal layouts agree on the GPU, not just in MemoryLayout arithmetic.
kernel void uniformsLayoutProbe(constant TransitionUniforms &u [[buffer(0)]],
                                device float *out [[buffer(1)]],
                                uint id [[thread_position_in_grid]]) {
    if (id != 0) return;
    out[0] = u.glowColor.w;      out[1] = u.notchSize.y;       out[2] = u.progress;
    out[3] = float(u.blurSamples); out[4] = u.pad2;            out[5] = u.meshScale.y;
    out[6] = u.meshTranslate.x;  out[7] = u.foldAngle;         out[8] = u.aspect;
    out[9] = u.maskOpenness;     out[10] = float(u.maskKind);  out[11] = float(u.blades);
    out[12] = float(u.useTexture); out[13] = u.maxLOD;         out[14] = u.pad3;
}

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// A single oversized triangle covers the whole viewport; no vertex buffer needed.
// uv is 0..1 with y pointing down, matching the snapshot texture's row order.
vertex VertexOut fullscreenVertex(uint vid [[vertex_id]]) {
    float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.uv = float2((positions[vid].x + 1) * 0.5, 1 - (positions[vid].y + 1) * 0.5);
    return out;
}

// The simplest possible transition: fade to black. It exists to prove the
// pipeline and as the Reduce Motion fallback.
fragment float4 fadeFragment(VertexOut in [[stage_in]],
                             texture2d<float> snapshot [[texture(0)]],
                             constant TransitionUniforms &u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float4 color = snapshot.sample(s, in.uv);
    return float4(color.rgb * (1.0 - u.progress), 1.0);
}

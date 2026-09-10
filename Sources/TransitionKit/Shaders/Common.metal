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
    float pad0;
    float pad1;
};

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

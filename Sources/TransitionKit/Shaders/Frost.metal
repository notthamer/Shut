// Frost: the frosted lid transition.
//
// The image never moves or scales. A blur front starts at the top edge (the
// edge nearest the hinge when the lid is closing) and sweeps down; behind the
// front the image is progressively blurred and lightly "iced", and past
// `darknessStart` the whole thing fades to black.
//
// The blur is read from a mip chain built once per snapshot (see
// FrostTransition.prepare). Sampling a mip level is a cheap approximation of a
// wide Gaussian, and its cost doesn't depend on the radius, so the per-frame
// price is flat no matter how the user sets Max blur.

static float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fragment float4 frostFragment(VertexOut in [[stage_in]],
                              texture2d<float> snapshot [[texture(0)]],
                              constant TransitionUniforms &u [[buffer(0)]]) {
    constexpr sampler mipSampler(address::clamp_to_edge, filter::linear, mip_filter::linear);
    float p = clamp(u.progress, 0.0, 1.0);
    float2 uv = in.uv;

    // How frosted this row is: 0 ahead of the front, 1 well behind it. The front
    // sits at y = p·(1 + spread) and is `spread` screen-heights tall, so a small
    // spread is a sharp wipe and a large one is a gentle gradient.
    float spread = max(u.frostSpread, 0.001);
    float local = smoothstep(0.0, 1.0, (p * (1.0 + spread) - uv.y) / spread);

    // Blur radius in pixels → mip level. Level n averages 2ⁿ pixels, so the
    // level for radius r is log2(r + 1). A few jittered taps hide the blockiness
    // that comes from reading a single coarse level.
    float radius = u.maxBlur * local;
    float lod = clamp(log2(radius + 1.0), 0.0, max(u.mipLevels - 1.0, 0.0));
    float2 texel = 1.0 / u.snapshotSize;
    float2 jitter = radius * 0.35 * texel;
    float3 rgb = snapshot.sample(mipSampler, uv, level(lod)).rgb * 0.4;
    rgb += snapshot.sample(mipSampler, uv + float2( jitter.x,  jitter.y), level(lod)).rgb * 0.15;
    rgb += snapshot.sample(mipSampler, uv + float2(-jitter.x,  jitter.y), level(lod)).rgb * 0.15;
    rgb += snapshot.sample(mipSampler, uv + float2( jitter.x, -jitter.y), level(lod)).rgb * 0.15;
    rgb += snapshot.sample(mipSampler, uv + float2(-jitter.x, -jitter.y), level(lod)).rgb * 0.15;

    // Ice: lift toward a cool white and add fine grain where it's frosted.
    float luma = dot(rgb, float3(0.299, 0.587, 0.114));
    // Linear-light pipeline: small additive constants go a long way.
    float3 icy = mix(rgb, float3(luma) * float3(0.92, 0.97, 1.05) + 0.03, 0.35);
    rgb = mix(rgb, icy, local);
    float grain = (hash12(uv * u.snapshotSize) - 0.5) * 0.035 * local;
    rgb += grain;

    // Fade to black once past darknessStart; pow keeps the perceptual ramp.
    float dark = smoothstep(u.darknessStart, 1.0, p);
    rgb *= pow(1.0 - dark, 2.2);

    return float4(rgb, 1.0);
}

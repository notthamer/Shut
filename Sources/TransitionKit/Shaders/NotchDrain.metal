// Notch Drain: the whole screen swirls and funnels into the notch.
//
// The idea is an *inverse* mapping. For every output pixel we ask "which pixel of
// the frozen snapshot should be shown here?" and sample it. Pixels whose source
// falls outside the snapshot are black, which is what makes the screen empty out
// as everything gets pulled into the sink.
//
// Symbols follow PRD 5.4:
//   x  output pixel, in snapshot pixels (top-left origin)
//   s  sink point (bottom centre of the notch)
//   v  x − s
//   d  |v| / D, 0 at the sink and 1 at the farthest corner
//   p  overall progress, 0 = untouched, 1 = gone; briefly < 0 during pour-out
//   q  local progress: content near the sink leads, far content lags (falloff)
//   k  contraction factor; > 1 shrinks content toward the sink
//   θ  swirl angle
//
// `Common.metal` is concatenated ahead of this file, so TransitionUniforms and the
// vertex stage are already defined.

static float2 rotate2(float2 v, float angle) {
    float c = cos(angle), s = sin(angle);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// Where output offset `v` (relative to the sink) reads from in the snapshot at
// local progress `q`.
static float2 drainSource(float2 v, float q, constant TransitionUniforms &u) {
    // Contraction. As q → 1, k → ∞ and every pixel samples from far outside the
    // snapshot, i.e. black. `pull` shapes how quickly that happens: 1 is linear,
    // higher values hold the image longer and then collapse fast at the end.
    // Negative q (pour-out overshoot) makes k < 1, which enlarges content slightly:
    // that's the splash.
    float k = 1.0 / max(0.001, pow(max(1.0 - q, 0.0), u.pull));

    // Swirl. q² keeps the start gentle so the image doesn't visibly rotate before
    // it starts moving, then winds up as it goes down the drain.
    float theta = u.twist * 2.0 * M_PI_F * q * q;

    // Funnel. Stretching v.x in the inverse map squeezes content horizontally
    // toward the vertical line through the notch, forming the "tail" into the sink.
    float2 vf = float2(v.x * (1.0 + u.stretch * max(q, 0.0)), v.y);

    return u.sink + rotate2(vf * k, theta);
}

static float3 sampleSnapshot(texture2d<float> snapshot, float2 src, float2 size) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 uv = src / size;
    if (any(uv < 0.0) || any(uv > 1.0)) return float3(0.0);
    return snapshot.sample(s, uv).rgb;
}

// Signed distance to a pill with its flat edge on the top of the screen and
// rounded bottom corners, used for the virtual notch on Macs without one.
static float pillDistance(float2 x, float2 center, float2 halfSize) {
    float r = halfSize.y;                       // fully rounded bottom
    float2 q = abs(x - center) - halfSize + r;
    // only round the bottom edge: treat the top as extended past the screen
    if (x.y < center.y) q.y = min(q.y, 0.0);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

fragment float4 notchDrainFragment(VertexOut in [[stage_in]],
                                   texture2d<float> snapshot [[texture(0)]],
                                   constant TransitionUniforms &u [[buffer(0)]]) {
    float2 x = in.uv * u.snapshotSize;
    float2 v = x - u.sink;
    float r = length(v);
    float d = r / u.maxDistance;
    float p = u.progress;

    // Local progress. Near the sink (d ≈ 0) q runs ahead of p by (1 + falloff);
    // at the far corner it lags by falloff. Clamped so nothing goes negative
    // during a close, but allowed down to −overshoot during pour-out.
    float qMin = p < 0.0 ? -u.overshoot : 0.0;
    float q = clamp(p * (1.0 + u.falloff) - u.falloff * d, qMin, 1.0);

    // Motion blur: average a handful of samples at slightly smaller q, i.e. where
    // this pixel's content was a moment ago along its path into the sink.
    int samples = (u.reduceTransparency > 0.5) ? 1 : max(u.blurSamples, 1);
    float spread = u.blurStrength * 0.12 * max(q, 0.0);
    float3 rgb = float3(0.0);
    for (int i = 0; i < samples; i++) {
        float t = samples > 1 ? float(i) / float(samples - 1) : 0.0;
        float qi = max(q - spread * t, qMin);
        rgb += sampleSnapshot(snapshot, drainSource(v, qi, u), u.snapshotSize);
    }
    rgb /= float(samples);

    // Chromatic aberration: red and blue read from slightly different radii, so
    // edges fringe as content streams past. Scaled by q so a still image is clean.
    if (u.aberration > 0.0 && q > 0.0) {
        float2 dir = v / max(r, 1.0);
        float2 offset = dir * u.aberration * q;
        float2 src = drainSource(v, q, u);
        rgb.r = mix(rgb.r, sampleSnapshot(snapshot, src + offset, u.snapshotSize).r, 0.7);
        rgb.b = mix(rgb.b, sampleSnapshot(snapshot, src - offset, u.snapshotSize).b, 0.7);
    }

    // Darken as content approaches the sink; the drain is a hole, not a spotlight.
    rgb *= 1.0 - u.darken * max(q, 0.0);

    // The sink itself swallows whatever reaches it.
    float hole = 1.0 - smoothstep(u.sinkRadius * 0.5, u.sinkRadius * 1.5, r);
    rgb = mix(rgb, float3(0.0), hole * clamp(q * 2.0, 0.0, 1.0));

    // Rim glow around the notch, strongest mid-transition, plus a faint halo.
    float peak = sin(M_PI_F * clamp(abs(p), 0.0, 1.0));
    float ringWidth = u.sinkRadius * 0.6 + 6.0;
    float ring = exp(-pow((r - u.sinkRadius) / ringWidth, 2.0));
    float halo = exp(-r / (u.sinkRadius * 6.0 + 30.0));
    rgb += u.glowColor.rgb * u.glowColor.a * u.glow * peak * (ring * 0.9 + halo * 0.35);

    // Virtual notch: fade in a black pill so the drain has a visible destination
    // on Macs without a hardware notch (or when auto-detect is off).
    if (u.virtualNotch > 0.5) {
        float2 halfSize = u.notchSize * 0.5;
        float2 center = float2(u.sink.x, u.sink.y - halfSize.y);
        float dist = pillDistance(x, center, halfSize);
        float alpha = 1.0 - smoothstep(-1.0, 1.0, dist);
        float fadeIn = clamp(abs(p) * 3.0, 0.0, 1.0);
        rgb = mix(rgb, float3(0.0), alpha * fadeIn);
    }

    return float4(rgb, 1.0);
}

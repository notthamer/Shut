// Sinkhole: the whole screen swirls and funnels into the notch.
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
// local progress `q`. `extraTheta` lets the blur loop sweep along an arc.
static float2 drainSource(float2 v, float q, float extraTheta, constant TransitionUniforms &u) {
    // Contraction. As q → 1, k → ∞ and every pixel samples from far outside the
    // snapshot, i.e. black. `pull` shapes how quickly that happens: 1 is linear,
    // lower values collapse more gradually, higher ones hold the image and then
    // drop it. Negative q (pour-out overshoot) makes k < 1, which enlarges content
    // slightly: that's the splash.
    float k = 1.0 / max(0.001, pow(max(1.0 - q, 0.0), u.pull));

    // Global swirl. q² keeps the start gentle so the image doesn't visibly rotate
    // before it starts moving. Kept modest on purpose: the sink sits on the top
    // edge of the screen, and any large rotation near it makes pixels sample from
    // the void above the display, which shows up as a lopsided black blob.
    float theta = u.twist * 2.0 * M_PI_F * q * q + extraTheta;

    // Funnel. Stretching v.x in the inverse map squeezes content horizontally
    // toward the vertical line through the notch, forming the "tail" into the sink.
    float2 vf = float2(v.x * (1.0 + u.stretch * max(q, 0.0)), v.y);

    return u.sink + rotate2(vf * k, theta);
}

// 1 inside the snapshot, fading to 0 over `edgeSoftness` pixels outside it, so
// content that has been pulled off-screen dissolves instead of being cut hard.
static float edgeFade(float2 src, constant TransitionUniforms &u) {
    float2 outside = max(max(-src, src - u.snapshotSize), 0.0);
    return 1.0 - smoothstep(0.0, max(u.edgeSoftness, 1.0), length(outside));
}

static float3 sampleSnapshot(texture2d<float> snapshot, float2 src, constant TransitionUniforms &u) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float fade = edgeFade(src, u);
    if (fade <= 0.0) return float3(0.0);
    // The pipeline is linear-light; pow keeps the softness we tuned by eye.
    return snapshot.sample(s, src / u.snapshotSize).rgb * pow(fade, 2.2);
}

// Signed distance to a rounded rectangle hanging from the top edge of the
// screen, i.e. the notch (or the virtual notch pill). Negative inside. The top
// is treated as extending past the screen so only the bottom corners round.
static float notchDistance(float2 x, float cornerRadius, constant TransitionUniforms &u) {
    float2 halfSize = u.notchSize * 0.5;
    float2 center = float2(u.sink.x, u.sink.y - halfSize.y);
    float r = min(cornerRadius, min(halfSize.x, halfSize.y));
    float2 q = abs(x - center) - halfSize + r;
    if (x.y < center.y) q.y = min(q.y, 0.0);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

fragment float4 sinkholeFragment(VertexOut in [[stage_in]],
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
    // this pixel's content was a moment ago along its path into the sink. The
    // samples also sweep along an arc whose length grows toward the sink: that is
    // the whirlpool. Doing the spin here, as a smear centred on the radial path,
    // gives the streaking of water at a drain without displacing content into the
    // void above the notch.
    int samples = (u.reduceTransparency > 0.5) ? 1 : max(u.blurSamples, 1);
    float spread = u.blurStrength * 0.12 * max(q, 0.0);
    float arc = u.vortex * 0.9 * max(q, 0.0) * (1.0 - d) * (1.0 - d);   // radians of sweep
    float3 rgb = float3(0.0);
    for (int i = 0; i < samples; i++) {
        float t = samples > 1 ? float(i) / float(samples - 1) : 0.0;
        float qi = max(q - spread * t, qMin);
        float thetaI = arc * (t - 0.5);
        rgb += sampleSnapshot(snapshot, drainSource(v, qi, thetaI, u), u);
    }
    rgb /= float(samples);

    // Chromatic aberration: red and blue read from slightly different radii, so
    // edges fringe as content streams past. Scaled by q so a still image is clean,
    // and skipped where any of the three samples is fading off-screen, otherwise
    // the surviving green channel tints the sheet's edge.
    if (u.aberration > 0.0 && q > 0.0) {
        float2 dir = v / max(r, 1.0);
        float2 offset = dir * u.aberration * q;
        float2 src = drainSource(v, q, 0.0, u);
        float fades = min(edgeFade(src, u), min(edgeFade(src + offset, u), edgeFade(src - offset, u)));
        if (fades > 0.999) {
            rgb.r = mix(rgb.r, sampleSnapshot(snapshot, src + offset, u).r, 0.7);
            rgb.b = mix(rgb.b, sampleSnapshot(snapshot, src - offset, u).b, 0.7);
        }
    }

    // Darken as content approaches the sink; the drain is a hole, not a spotlight.
    // Weighted toward the sink so the edges of the screen keep their light longer.
    float radial = 0.35 + 0.65 * (1.0 - d);
    rgb *= pow(max(1.0 - u.darken * max(q, 0.0) * radial, 0.0), 2.2);

    // The hole. A dark mouth that hugs the notch outline, there from the first
    // frame so the destination is obvious, and widening as the drain progresses.
    // `sinkRadius` is its starting margin around the notch; `holeGrowth` how much
    // wider it gets by the end.
    float visible = clamp(abs(p) * 6.0, 0.0, 1.0);
    float pp = clamp(p, 0.0, 1.0);
    float margin = u.sinkRadius * (1.0 + u.holeGrowth * pp * pp);
    float nd = notchDistance(x, u.notchSize.y * 0.45, u);   // < 0 inside the notch itself
    float holeEdge = nd - margin;
    float holeSoft = margin * 0.6 + 6.0;
    float hole = 1.0 - smoothstep(-holeSoft * 0.3, holeSoft, holeEdge);
    // Inside the mouth, content darkens steeply toward the notch rather than
    // vanishing at a line, so it reads as depth.
    float depth = 1.0 - smoothstep(-margin, holeSoft, holeEdge);
    rgb *= pow(max(1.0 - visible * max(hole * 0.85, depth * 0.55), 0.0), 2.2);

    // Rim glow along the mouth's edge, plus a faint halo, present through the
    // transition and fading out just before black.
    float presence = smoothstep(0.0, 0.15, abs(p)) * (1.0 - smoothstep(0.8, 1.0, pp));
    float ringWidth = holeSoft * 0.7;
    float ring = exp(-pow(holeEdge / ringWidth, 2.0));
    float halo = exp(-max(holeEdge, 0.0) / (margin * 2.0 + 24.0));
    // Additive light in linear space reads brighter than it did in gamma space,
    // so the weights are small; the ring carries the look, the halo just warms it.
    rgb += u.glowColor.rgb * u.glowColor.a * u.glow * presence * (ring * 0.45 + halo * 0.06);

    // Virtual notch: fade in a black pill so the drain has a visible destination
    // on Macs without a hardware notch (or when auto-detect is off).
    if (u.virtualNotch > 0.5) {
        float pill = 1.0 - smoothstep(-1.0, 1.0, notchDistance(x, u.notchSize.y * 0.5, u));
        rgb = mix(rgb, float3(0.0), pill * visible);
    }

    return float4(rgb, 1.0);
}

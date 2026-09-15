# How Sinkhole works

For every pixel the shader asks: *which pixel of the frozen snapshot should be here
right now?* With `s` the sink (bottom centre of the notch), `x` a screen pixel,
`v = x − s`, `d` the distance to the sink as a fraction of the farthest corner, and
`p` the overall progress:

```
q   = clamp(p·(1 + falloff) − falloff·d, 0, 1)   // near the notch leads, corners lag
k   = 1 / (1 − q)^pull                           // contraction: blows up as q → 1
θ   = twist · 2π · q²                            // gentle global swirl
vf  = (v.x · (1 + stretch·q), v.y)               // funnel: squeeze toward the notch
src = s + rotate(vf · k, θ)                      // inverse map; outside = black
```

Motion blur averages samples at slightly smaller `q`, sweeping them along an arc that
tightens toward the notch (`vortex`), done as a smear rather than a rotation because
the notch sits on the top edge and real spin there would pull in the void above the
screen. Content that leaves the screen dissolves over `edge softness`; a hole shaped
to the notch outline opens and widens; a rim glow traces it. On unlock `p` runs from 1
back to 0 and briefly below, which makes `k < 1`: the splash. The full walk-through is
in `Sources/TransitionKit/Shaders/Sinkhole.metal`.

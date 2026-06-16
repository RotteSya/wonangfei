#include <metal_stdlib>
using namespace metal;

// MARK: - Shared noise helpers

static inline float hash21(float2 p) {
    // Cheap, stable per-pixel hash — good enough for film grain / sparkle.
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

// MARK: - Gold shimmer (colorEffect)
//
// A diagonal glint band sweeps across the glyphs once per `period` seconds,
// with a hot core riding inside a soft halo — the way light catches a coin
// when you tilt it. Between sweeps the effect is the identity, so the layer
// only *looks* alive when the sweep passes. Alpha is preserved: the boost is
// scaled by source alpha so anti-aliased glyph edges stay clean.
//
//   intensity 0…1   how hard the glint flares (0.35 reads "expensive",
//                   1.0 reads "slot machine")
[[ stitchable ]]
half4 wnfGoldShimmer(float2 position, half4 color, float2 size, float time,
                     float period, float intensity) {
    if (color.a < 0.003) {
        return color;
    }
    float2 uv = position / max(size, float2(1.0, 1.0));

    // Normalized cycle phase; the band only travels during the first 40% of
    // the cycle and rests for the remainder.
    float phase = fract(time / max(period, 0.5));
    float travel = smoothstep(0.0, 1.0, clamp(phase / 0.4, 0.0, 1.0));
    float bandCenter = mix(-0.45, 1.45, travel);

    // Diagonal coordinate (top-left → bottom-right sweep).
    float d = (uv.x + uv.y * 0.42) * 0.704 - bandCenter;

    float halo = exp(-d * d * 42.0);
    float core = exp(-d * d * 260.0);
    float glint = (halo * 0.55 + core * 0.85) * intensity;

    // Brighten toward warm white so gold stays gold instead of washing out.
    half3 lifted = color.rgb + half3(1.0, 0.94, 0.72) * half(glint) * color.a;
    return half4(lifted, color.a);
}

// MARK: - Paper grain (colorEffect)
//
// Static, per-pixel film grain. Breaks up flat digital fills so big color
// fields read as printed card stock instead of vector paint. `intensity`
// is the peak luminance offset (0.03–0.05 is plenty).
[[ stitchable ]]
half4 wnfPaperGrain(float2 position, half4 color, float intensity) {
    if (color.a < 0.003) {
        return color;
    }
    float n = hash21(floor(position * 0.9));
    // Two octaves so the grain has some clumping, like real paper fiber.
    float n2 = hash21(floor(position * 0.35) + 7.31);
    float g = ((n * 0.7 + n2 * 0.3) - 0.5) * intensity;
    return half4(color.rgb + half3(g) * color.a, color.a);
}

// MARK: - Molten gold progress fill (colorEffect)
//
// Drawn over a plain opaque rectangle the width of the whole track. Pixels
// beyond the animated fill edge are returned fully transparent, so the
// shader carves the liquid surface out of the rect. Inside the fill:
// a slow conveyor of warm highlight bands drifts toward the crest, and the
// leading edge wears a brighter meniscus that laps back and forth.
//
//   progress 0…1   fraction of the track that is full
//   wobble   px    extra amplitude for the crest wave (set 0 for reduce-motion)
[[ stitchable ]]
half4 wnfMoltenGold(float2 position, half4 color, float2 size, float time,
                    float progress, float wobble) {
    float2 uv = position / max(size, float2(1.0, 1.0));
    float p = clamp(progress, 0.0, 1.0);

    if (p <= 0.0005) {
        return half4(0.0);
    }

    // Crest line with two superimposed ripples; amplitude expressed in
    // normalized track width so it stays subtle on any bar length.
    float ampl = wobble / max(size.x, 1.0);
    float crestWave = sin(uv.y * 9.4 + time * 3.1) * 0.6
                    + sin(uv.y * 17.0 - time * 4.7) * 0.4;
    float edge = p + crestWave * ampl;

    if (uv.x > edge) {
        return half4(0.0);
    }

    // Body: deep gold → light gold conveyor drifting toward the crest.
    half3 deep = half3(1.00, 0.69, 0.13);
    half3 lite = half3(1.00, 0.88, 0.46);
    float flow = sin(uv.x * 9.0 - time * 2.2 + sin(uv.y * 4.0) * 0.7) * 0.5 + 0.5;
    half3 body = mix(deep, lite, half(flow * 0.5 + uv.y * 0.12));

    // Meniscus: a hot strip hugging the leading edge.
    float crest = smoothstep(edge - 0.085, edge, uv.x);
    body += half3(1.0, 0.95, 0.78) * half(crest * 0.30);

    // Occasional micro-sparkle drifting with the flow.
    float sparkle = step(0.9965, hash21(floor(position * 0.8) + floor(time * 2.0)));
    body += half(sparkle * 0.45);

    return half4(body * color.a, color.a);
}

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Shared polish shaders for the home + records surfaces. All functions are
// SwiftUI-stitchable and driven from `PolishEffects.swift`:
//
//   - `sheen`       layerEffect   diagonal gold gloss sweep (money text loop,
//                                 records hero card on period change)
//   - `aurora`      colorEffect   slow breathing warm light field behind pages
//   - `liquidGold`  colorEffect   flowing molten-gold fill for the progress bar
//   - `jellyWarp`   distortion    elastic mid-flight wobble for tab transitions
//
// Convention: every function takes `float4 bounds` via `.boundingRect` so the
// Swift side never needs a GeometryReader just to feed a shader.

// MARK: - sheen

// One diagonal gloss band plus a thinner leading sparkle line, swept across the
// layer by `progress` in [0, 1]. Outside that range the function is identity, so
// the Swift side can leave the effect attached and only animate `progress`.
[[ stitchable ]]
half4 sheen(float2 position, SwiftUI::Layer layer, float4 bounds,
            float progress, float bandWidth, float strength) {
    half4 color = layer.sample(position);
    if (progress <= 0.0001 || progress >= 0.9999 || color.a < 0.004) {
        return color;
    }

    float w = max(bounds.z, 1.0);
    float h = max(bounds.w, 1.0);
    // Diagonal coordinate: 0 at the top-left, 1 at the bottom-right.
    float d = (position.x + position.y * 0.55) / (w + h * 0.55);

    float band = max(bandWidth, 0.001);
    float center = mix(-band * 2.0, 1.0 + band * 2.0, progress);

    float q = (d - center) / band;
    float gloss = exp(-q * q * 2.0);

    float q2 = (d - center + band * 0.8) / (band * 0.32);
    float spark = exp(-q2 * q2 * 2.0);

    half glow = half((gloss + spark * 0.45) * strength);
    half3 tint = half3(1.0h, 0.95h, 0.70h);
    color.rgb = min(color.rgb + tint * glow * color.a, half3(1.0h));
    return color;
}

// MARK: - aurora

// Three soft drifting light blobs (gold / cream / mint) layered over the input
// color. Time is wall-clock seconds; all drift periods are around a minute so the
// field breathes rather than swims. Intended for a `WNFTheme.bg` rectangle.
[[ stitchable ]]
half4 aurora(float2 position, half4 color, float4 bounds, float time, float intensity) {
    float w = max(bounds.z, 1.0);
    float h = max(bounds.w, 1.0);
    float2 uv = float2(position.x / w, position.y / h);
    float t = time;

    float2 c1 = float2(0.22 + 0.12 * sin(t * 0.110),       0.18 + 0.09 * sin(t * 0.083 + 1.3));
    float2 c2 = float2(0.80 + 0.10 * sin(t * 0.071 + 2.6), 0.34 + 0.11 * sin(t * 0.127 + 4.1));
    float2 c3 = float2(0.52 + 0.18 * sin(t * 0.059 + 5.2), 0.86 + 0.07 * sin(t * 0.103 + 0.6));

    float d1 = length(uv - c1);
    float d2 = length(uv - c2);
    float d3 = length(uv - c3);
    float b1 = exp(-d1 * d1 * 7.0);
    float b2 = exp(-d2 * d2 * 6.0);
    float b3 = exp(-d3 * d3 * 5.0);

    half3 gold  = half3(1.00h, 0.88h, 0.58h);
    half3 cream = half3(1.00h, 0.99h, 0.95h);
    half3 mint  = half3(0.86h, 0.98h, 0.97h);

    float k = clamp(intensity, 0.0, 1.5);
    half3 outRGB = color.rgb;
    outRGB = mix(outRGB, gold,  half(min(b1 * 0.34 * k, 0.50)));
    outRGB = mix(outRGB, cream, half(min(b2 * 0.42 * k, 0.60)));
    outRGB = mix(outRGB, mint,  half(min(b3 * 0.18 * k, 0.30)));
    return half4(outRGB * color.a, color.a);
}

// MARK: - liquidGold

// Molten-gold fill: a deep→bright horizontal gradient with two slow traveling
// waves of highlight and a glossy top edge. Replaces the static progress-bar
// gradient; the wave phase advances rightward so the bar reads as money
// flowing in.
[[ stitchable ]]
half4 liquidGold(float2 position, half4 color, float4 bounds, float time) {
    if (color.a < 0.004) {
        return color;
    }

    float w = max(bounds.z, 1.0);
    float h = max(bounds.w, 1.0);
    float u = position.x / w;
    float v = position.y / h;

    half3 deep   = half3(1.00h, 0.70h, 0.13h);
    half3 bright = half3(1.00h, 0.86h, 0.38h);
    half3 base = mix(deep, bright, half(clamp(u * 0.85 + 0.10, 0.0, 1.0)));

    const float twoPi = 6.2831853;
    float w1 = 0.5 + 0.5 * sin(twoPi * (u * 1.8 - time * 0.45));
    float w2 = 0.5 + 0.5 * sin(twoPi * (u * 3.3 + v * 0.6 - time * 0.70) + 1.7);
    float flow = w1 * 0.10 + w2 * 0.07;

    float gloss = smoothstep(0.62, 0.06, v) * 0.16;

    half3 tint = half3(1.0h, 0.96h, 0.75h);
    half3 outRGB = min(base + tint * half(flow + gloss), half3(1.0h));
    return half4(outRGB * color.a, color.a);
}

// MARK: - jellyWarp

// Horizontal elastic wobble for the tab transition. Rows near the vertical
// center lag behind the page's motion (sampled further toward where the page
// came from), so the page lands like jelly instead of a rigid sheet. `amount`
// is signed and already includes the sin(progress·π) envelope from Swift; the
// shader is identity when it is ~0 so the modifier can stay attached.
[[ stitchable ]]
float2 jellyWarp(float2 position, float4 bounds, float amount) {
    if (abs(amount) < 0.0008) {
        return position;
    }
    float h = max(bounds.w, 1.0);
    float v = clamp(position.y / h, 0.0, 1.0);
    float lag = sin(v * 3.14159265);
    float shift = amount * max(bounds.z, 1.0) * lag;
    return float2(position.x + shift, position.y);
}

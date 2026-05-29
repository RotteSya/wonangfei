#include <metal_stdlib>
using namespace metal;

// Genie / Command-M warp for the share-card emergence from the Dynamic Island.
//
// The card is rendered ONCE at full size; this distortion warps those finished
// pixels as they are pushed out of the island slot, exactly like macOS minimize
// in reverse. For each destination pixel it returns the source pixel to sample.
//
//   - `progress` 0 → fully sucked into the slot (a thin pinched sliver at the
//     neck), 1 → undistorted card (identity).
//   - The visible card occupies the top `progress` fraction of its box; the full
//     card is compressed into it (sourceV = v / progress), so the whole thing
//     decompresses downward as it emerges.
//   - Horizontally each row is pinched toward the neck near the top and funnels
//     out to full width below; the pinch relaxes to none as progress → 1.
//
// Pixels outside the funnel map outside the source box and are clipped by a
// matching SwiftUI mask, so this function never needs a transparency branch.
[[ stitchable ]]
float2 genie(float2 position, float2 size, float progress, float neckHalf, float neckCenter,
             float neckLen, float unpinchStart, float squish, float curve) {
    float w = size.x;
    float h = size.y;
    float p = clamp(progress, 0.0, 1.0);
    if (p >= 0.999) {
        return position;
    }

    float v = position.y / h;                 // 0 at the neck (top) … 1 at the bottom
    float vFront = max(p, 0.001);             // how far the card has emerged
    float vis = clamp(v / vFront, 0.0, 1.0);  // position within the emerged band

    // Vertical: how hard the card is squeezed into the slot. 1 = the whole card
    // compresses into the emerged band (full genie); 0 = no squeeze, the card
    // just unrolls at its natural height.
    float span = mix(1.0, vFront, clamp(squish, 0.0, 1.0));
    float sourceV = clamp(v / span, 0.0, 1.0);

    // Horizontal funnel throat. `curve` shapes the sides: 1 = straight trapezoid,
    // >1 = stays pinched longer then flares (concave/genie), <1 = flares early.
    float t = clamp(vis / max(neckLen, 0.001), 0.0, 1.0);
    float funnelT = pow(t, max(curve, 0.05));
    float funnelHalf = mix(neckHalf, w * 0.5, funnelT);
    float unpinch = smoothstep(unpinchStart, 1.0, p);  // hold the neck pinched, release at the end
    float halfWidth = max(mix(funnelHalf, w * 0.5, unpinch), 1.0);

    float dx = position.x - neckCenter;
    float sourceX = neckCenter + dx * (w * 0.5) / halfWidth;
    float sourceY = sourceV * h;
    return float2(sourceX, sourceY);
}

#version 450

#include "common.inc"

layout(set = 0, binding = 2) uniform sampler2D Original;

#include "vertex.inc"

const int TAPS = 4;

float emission(vec3 c)
{
    float peak = max(c.r, max(c.g, c.b));
    float low = min(c.r, min(c.g, c.b));
    float saturation = (peak - low) / max(peak, 1e-4);
    float warm = smoothstep(0.0, 0.25, c.r - c.b) * step(c.b, c.g + 0.05);
    float fire = smoothstep(0.6, 0.9, peak) * smoothstep(0.3, 0.6, saturation) * warm;
    float hot = smoothstep(0.85, 1.0, low) * step(c.b + 0.02, c.r);
    return max(fire, hot);
}

void main()
{
    vec2 footprint = global.OutputSize.zw;
    vec3 glow = vec3(0.0);
    for (int y = 0; y < TAPS; y++)
    for (int x = 0; x < TAPS; x++)
    {
        vec2 uv = vTexCoord + ((vec2(x, y) + 0.5) / float(TAPS) - 0.5) * footprint;
        if (isOverlay(depthAt(uv))) continue;
        vec3 c = texture(Original, uv).rgb;
        glow += toLinear(c) * emission(c);
    }

    FragColor = vec4(glow / float(TAPS * TAPS), 1.0);
}

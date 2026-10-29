#version 450

#include "common.inc"

#include "vertex.inc"

// radial light shats, avauilable in gpu gems 3
const int STEPS = 32;
const float DECAY = 0.965;
const float FAR = 100000.0;

void main()
{
    vec3 l = sunDir();
    if (global.DepthAvailable < 0.5 || l.z < 0.05 || global.DC_SHAFTS <= 0.0 || isOverlay(depthAt(vTexCoord)))
    {
        FragColor = vec4(0.0);
        return;
    }

    vec2 moon = project(l * FAR);
    vec2 toward = moon - vTexCoord;
    float span = min(length(toward), 1.0) * global.DC_SHAFT_LENGTH;
    vec2 delta = normalize(toward + 1e-5) * span / float(STEPS);
    vec2 s = vTexCoord + delta * noise(gl_FragCoord.xy);
    float decay = 1.0;
    float light = 0.0;
    float weights = 0.0;

    for (int i = 0; i < STEPS; i++)
    {
        s += delta;
        float d = depthAt(clamp(s, vec2(0.0), vec2(1.0)));
        if (isOverlay(d))
        {
            decay *= DECAY;
            continue;
        }
        float open = !hasGeometry(d) && !isOverlay(d) ? 1.0 : 0.0;
        light += open * decay;
        weights += decay;
        decay *= DECAY;
    }

    float shafts = weights > 0.0 ? light / weights : 0.0;
    float facing = smoothstep(0.05, 0.6, l.z);
    float edge = 1.0 - smoothstep(0.8, 1.6, length(moon - 0.5));
    FragColor = vec4(vec3(shafts * facing * mix(0.5, 1.0, edge)), 1.0);
}

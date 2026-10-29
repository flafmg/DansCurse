#version 450

#include "common.inc"

layout(set = 0, binding = 2) uniform sampler2D Original;
layout(set = 0, binding = 3) uniform sampler2D SkyFeedback;

#include "vertex.inc"

const int GRID_X = 24;
const int GRID_Y = 16;
const float UPPER = 0.45;

vec4 skyColor()
{
    vec3 sky = vec3(0.0);
    vec3 scene = vec3(0.0);
    float skyCount = 0.0;
    float sceneCount = 0.0;
    float open = 0.0;
    float upper = 0.0;

    for (int y = 0; y < GRID_Y; y++)
    for (int x = 0; x < GRID_X; x++)
    {
        vec2 uv = (vec2(x, y) + 0.5) / vec2(GRID_X, GRID_Y);
        float d = depthAt(uv);
        if (isOverlay(d)) continue;

        bool geometry = hasGeometry(d);
        vec3 c = toLinear(texture(Original, uv).rgb);

        if (uv.y < UPPER)
        {
            upper += 1.0;
            if (!geometry) open += 1.0;
        }

        if (global.DepthAvailable > 0.5 && !geometry)
        {
            sky += c;
            skyCount += 1.0;
        }
        else
        {
            scene += c;
            sceneCount += 1.0;
        }
    }

    vec3 color = skyCount >= 4.0 ? sky / skyCount : sceneCount > 0.0 ? scene / sceneCount * 0.5 : vec3(0.0);
    float openness = global.DepthAvailable > 0.5 ? smoothstep(0.03, 0.25, open / max(upper, 1.0)) : 1.0;
    if (global.SceneIndoor.y > 0.5) openness = mix(openness, 1.0 - global.SceneIndoor.x, global.DC_GAME_LIGHT);
    return vec4(color, 0.5 + 0.5 * openness);
}

float scenePresence()
{
    float geometry = 0.0;
    for (int y = 0; y < GRID_Y; y++)
    for (int x = 0; x < GRID_X; x++)
    {
        vec2 uv = (vec2(x, y) + 0.5) / vec2(GRID_X, GRID_Y);
        if (hasGeometry(depthAt(uv))) geometry += 1.0;
    }

    return geometry / float(GRID_X * GRID_Y);
}

void main()
{
    vec4 previous = texture(SkyFeedback, vTexCoord);
    if (vTexCoord.x > 0.5)
    {
        float presence = scenePresence();
        FragColor = vec4(0.0, 0.0, previous.a > 0.25 ? mix(previous.z, presence, 0.35) : presence, 1.0);
        return;
    }

    vec4 current = skyColor();
    FragColor = previous.a > 0.25 ? mix(previous, current, 0.02) : current;
}

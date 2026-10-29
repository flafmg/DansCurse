#version 450

#include "common.inc"

layout(set = 0, binding = 2) uniform sampler2D Source;
layout(set = 0, binding = 3) uniform sampler2D Original;
layout(set = 0, binding = 4) uniform sampler2D Composite;

#include "vertex.inc"

const float WHITE_CURVE = 2.0;
const float WHITE_PATH = 0.03;

//based on bsl
vec3 tonemap(vec3 x)
{
    float a = WHITE_PATH;
    float b = WHITE_PATH / 3.0;
    mat3 spread = mat3(vec3(1.0 - a - b, a, b), vec3(a, 1.0 - 2.0 * a, a), vec3(b, a, 1.0 - a - b));
    x = spread * x;
    x = x / pow(pow(x, vec3(WHITE_CURVE)) + 1.0, vec3(1.0 / WHITE_CURVE));
    return clamp(inverse(spread) * x, 0.0, 1.0);
}

vec3 grade(vec3 color)
{
    float low = min(color.r, min(color.g, color.b));
    float high = max(color.r, max(color.g, color.b));
    float average = (color.r + color.g + color.b) / 3.0;
    vec3 lightness = vec3((low + high) * 0.5);
    float muted = (1.0 - (high - low)) * (1.0 - high) * average * 5.0;
    color = mix(color, mix(color, lightness, 1.0 - global.DC_VIBRANCE), clamp(muted, 0.0, 1.0));

    float gray = dot(color, vec3(0.299, 0.587, 0.114));
    return mix(vec3(gray), color, global.DC_SATURATION);
}

void main()
{
    vec4 scene = texture(Composite, vTexCoord);
    vec3 col = scene.rgb + texture(Source, vTexCoord).rgb * global.DC_BLOOM;
    col = tonemap(col * exp2(1.0 + global.DC_EXPOSURE));
    col = grade(toGamma(col));

    float shade = 1.0 - smoothstep(0.0, 0.6, luma(col));
    col = mix(col, col * CURSE_TINT / luma(CURSE_TINT), shade * global.DC_CURSE * 0.4);

    vec2 v = vTexCoord - 0.5;
    col *= 1.0 - global.DC_VIGNETTE * smoothstep(0.1, 0.5, dot(v, v));

    vec4 ui = uiLayer(vTexCoord);
    col = col * ui.a + ui.rgb;
    col = mix(texture(Original, vTexCoord).rgb, clamp(col, 0.0, 1.0), scene.a);
    FragColor = vec4(col, 1.0);
}

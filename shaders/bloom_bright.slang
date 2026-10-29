#version 450

#include "common.inc"

layout(set = 0, binding = 2) uniform sampler2D Source;

#include "vertex.inc"

vec3 bright(vec2 uv)
{
    vec4 c = texture(Source, uv);
    vec3 col = c.rgb * c.a;
    float peak = toGamma(vec3(max(col.r, max(col.g, col.b)))).r;
    float threshold = global.DC_BLOOM_THRESHOLD;
    return col * smoothstep(threshold, threshold + 0.35, peak);
}

void main()
{
    vec2 texel = global.SourceSize.zw * 0.5;
    vec3 sum = bright(vTexCoord + vec2(-texel.x, -texel.y));
    sum += bright(vTexCoord + vec2(texel.x, -texel.y));
    sum += bright(vTexCoord + vec2(-texel.x, texel.y));
    sum += bright(vTexCoord + vec2(texel.x, texel.y));
    FragColor = vec4(sum * 0.25, 1.0);
}

#version 450

#include "common.inc"
#include "vertex.inc"

const int AO_SAMPLES = 8;
const int ENCLOSURE_SAMPLES = 6;
const float ENCLOSURE_SCALE = 6.0;

vec3 pick(vec3 p, vec3 a, vec3 b)
{
    return abs(a.z - p.z) < abs(p.z - b.z) ? a - p : p - b;
}

float occlusion(vec3 p, vec3 n, vec3 tangent, vec3 bitangent, float radius, int samples, float jitter)
{
    float occluded = 0.0;
    for (int i = 0; i < samples; i++)
    {
        float fi = float(i) + jitter;
        float angle = fi * 2.39996323;
        float height = fract(fi * 0.618034);
        float scale = fi / float(samples);
        scale = mix(0.1, 1.0, scale * scale);

        vec3 dir = (cos(angle) * tangent + sin(angle) * bitangent) * sqrt(1.0 - height * height) + n * height;
        vec3 s = p + dir * radius * scale;
        vec2 suv = project(s);
        if (s.z <= 1.0 || !onScreen(suv)) continue;

        float sd = depthAt(suv);
        if (!hasGeometry(sd)) continue;

        float sz = viewZ(sd);
        float range = smoothstep(0.0, 1.0, radius / max(abs(p.z - sz), 1e-3));
        occluded += (sz < s.z - radius * 0.05 ? 1.0 : 0.0) * range;
    }

    return 1.0 - occluded / float(samples);
}
//why is this shit saying vtextcoord is ambiguous?
void main()
{
    float d = depthAt(vTexCoord);
    if (!hasGeometry(d))
    {
        FragColor = vec4(encodeNormal(vec3(0.0, 0.0, -1.0)), 1.0, 1.0);
        return;
    }

    vec2 texel = global.DepthSize.zw;
    vec3 p = viewPos(vTexCoord, d);
    vec2 l = vTexCoord - vec2(texel.x, 0.0);
    vec2 r = vTexCoord + vec2(texel.x, 0.0);
    vec2 u = vTexCoord - vec2(0.0, texel.y);
    vec2 b = vTexCoord + vec2(0.0, texel.y);
    vec3 dx = pick(p, viewPos(r, depthAt(r)), viewPos(l, depthAt(l)));
    vec3 dy = pick(p, viewPos(b, depthAt(b)), viewPos(u, depthAt(u)));
    vec3 n = normalize(cross(dy, dx));
    if (dot(n, p) > 0.0) n = -n;

    vec3 tangent = normalize(cross(n, abs(n.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
    vec3 bitangent = cross(n, tangent);
    float jitter = noise(gl_FragCoord.xy);
    float radius = global.DC_AO_RADIUS;

    float ao = occlusion(p, n, tangent, bitangent, radius, AO_SAMPLES, jitter);
    float enclosure = occlusion(p, n, tangent, bitangent, radius * ENCLOSURE_SCALE, ENCLOSURE_SAMPLES, jitter);
    FragColor = vec4(encodeNormal(n), ao, enclosure);
}

#version 450

#include "common.inc"

layout(set = 0, binding = 2) uniform sampler2D Geometry;
layout(set = 0, binding = 3) uniform sampler2D Sky;
layout(set = 0, binding = 4) uniform sampler2D Glow;
layout(set = 0, binding = 5) uniform sampler2D Original;
layout(set = 0, binding = 6) uniform sampler2D SceneLights;
layout(set = 0, binding = 7) uniform sampler2D Shafts;

#include "vertex.inc"

const int SHADOW_STEPS = 16;
const int MAX_LIGHTS = 32;
const vec3 WARM_LIGHT = vec3(1.0, 0.86, 0.68);
const vec3 COOL_LIGHT = vec3(0.70, 0.85, 1.0);
const float GLOW_GAIN = 8.0;
const float DETAIL_NEAR = 3000.0;
const float DETAIL_FAR = 9000.0;
const float SPECULAR = 0.15;
const float GLOSS = 24.0;
const vec3 WATER_COLOR = vec3(0.007, 0.024, 0.03);
const vec3 WATER_ABSORB = vec3(1.0, 0.42, 0.3) / 100.0;
const float WATER_DEEP = 2000.0;
const float WAVE_SCALE = 0.018;
const float WAVE_HEIGHT = 0.55;
const float WAVE_DRAG = 0.38;
const int WAVE_ITERATIONS = 10;
const float WATER_TEXTURE_BLEND = 0.4;
const float WATER_REFRACT = 0.035;

struct Surface
{
    vec3 normal;
    float ao;
    float enclosure;
};

Surface gather(vec2 uv, float z)
{
    vec2 texel = global.GeometrySize.zw;
    vec3 normal = vec3(0.0);
    vec2 occlusion = vec2(0.0);
    float weights = 0.0;
    for (int y = -1; y <= 1; y++)
    for (int x = -1; x <= 1; x++)
    {
        vec2 suv = uv + vec2(x, y) * texel * 2.0;
        float sd = depthAt(suv);
        if (!hasGeometry(sd)) continue;
        float w = 1.0 / (1.0 + abs(viewZ(sd) - z) / (z * 0.01));
        vec4 g = texture(Geometry, suv);
        normal += decodeNormal(g.rg) * w;
        occlusion += g.ba * w;
        weights += w;
    }

    Surface surface;
    if (weights <= 0.0)
    {
        surface.normal = decodeNormal(texture(Geometry, uv).rg);
        surface.ao = 1.0;
        surface.enclosure = 1.0;
        return surface;
    }

    surface.normal = normalize(normal);
    surface.ao = occlusion.x / weights;
    surface.enclosure = occlusion.y / weights;
    return surface;
}
// contact shadow by raymarch like bsl
float contactShadow(vec3 p, vec3 n, vec3 l)
{
    float reach = global.DC_SHADOW_LENGTH;
    float jitter = noise(gl_FragCoord.xy);
    float bias = max(p.z * 0.002, 1.0);
    float thickness = reach * 0.25 + p.z * 0.01;
    vec3 start = p + n * max(reach * 0.03, bias * 2.0);

    for (int i = 1; i <= SHADOW_STEPS; i++)
    {
        float t = (float(i) - jitter) / float(SHADOW_STEPS);
        vec3 s = start + l * reach * t * t;
        vec2 suv = project(s);
        if (s.z <= 1.0 || !onScreen(suv)) break;

        float sd = depthAt(suv);
        if (!hasGeometry(sd)) continue;

        float diff = s.z - viewZ(sd);
        if (diff > bias && diff < thickness)
        {
            vec2 edge = min(suv, 1.0 - suv);
            float fade = smoothstep(0.0, 0.03, min(edge.x, edge.y));
            return mix(1.0, t * t * 0.5, fade);
        }
    }

    return 1.0;
}

vec3 sceneLights(vec3 p, vec3 n)
{
    vec3 sum = vec3(0.0);
    int count = min(int(global.SceneLightCount + 0.5), MAX_LIGHTS);
    for (int i = 0; i < count; i++)
    {
        vec4 placement = texelFetch(SceneLights, ivec2(i * 2, 0), 0);
        vec3 color = texelFetch(SceneLights, ivec2(i * 2 + 1, 0), 0).rgb;
        float radius = placement.w * global.DC_LIGHT_RANGE;
        vec3 toLight = placement.xyz - p;
        float distance = length(toLight);
        if (distance >= radius || radius <= 0.0) continue;

        float falloff = 1.0 - distance / radius;
        falloff *= falloff;
        float facing = max(dot(n, toLight / max(distance, 1e-3)), 0.0) * 0.75 + 0.25;
        sum += toLinear(color) * falloff * facing;
    }

    sum *= global.DC_SCENE_LIGHTS;
    return sum / (1.0 + luma(sum));
}

float groundMist(vec3 p)
{
    if (global.CameraAvailable < 0.5 || global.DC_GROUND_FOG <= 0.0) return 0.0;
    float below = toWorld(p).y - global.CameraTranslation.y;
    float layer = smoothstep(-global.DC_GROUND_HEIGHT, global.DC_GROUND_HEIGHT * 0.5, below);
    float reach = 1.0 - exp(-length(p) * 0.0006);
    return layer * reach * global.DC_GROUND_FOG * 0.45;
}

bool hasWaterLevel()
{
    return global.SceneWaterLevel.y > 0.5 && global.CameraAvailable > 0.5;
}

float levelThickness(vec3 p)
{
    float level = waterLevelY();
    float target = toWorld(p).y;
    float eye = global.CameraTranslation.y;
    if (target <= level) return 0.0;
    if (eye >= level) return 0.0;
    return length(p) * (target - level) / max(target - eye, 1e-3);
}

float thicknessAt(vec2 uv, vec3 p)
{
    float bottom = rawDepth(uv);
    if (!hasGeometry(bottom)) return WATER_DEEP;
    vec3 b = viewPos(uv, bottom);
    return hasWaterLevel() ? levelThickness(b) : max(length(b) - length(p), 0.0);
}
float waterThickness(vec3 p)
{
    return thicknessAt(vTexCoord, p);
}
bool inWater(vec3 p)
{
    return hasWaterLevel() ? waterThickness(p) > 0.0 : isWater(vTexCoord);
}
float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float valueNoise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// wavedx/getwaves adapted from 'Very fast procedural ocean"
vec2 wavedx(vec2 position, vec2 direction, float frequency, float timeshift)
{
    float x = dot(direction, position) * frequency + timeshift;
    float wave = exp(sin(x) - 1.0);
    float dx = wave * cos(x);
    return vec2(wave, -dx);
}

float getwaves(vec2 position)
{
    float wavePhaseShift = length(position) * 0.1;
    float iter = 0.0;
    float frequency = 1.0;
    float timeMultiplier = 2.0;
    float weight = 1.0;
    float sumOfValues = 0.0;
    float sumOfWeights = 0.0;
    for (int i = 0; i < WAVE_ITERATIONS; i++)
    {
        vec2 p = vec2(sin(iter), cos(iter));
        vec2 res = wavedx(position, p, frequency, seconds() * timeMultiplier + wavePhaseShift);
        position += p * res.y * weight * WAVE_DRAG;
        sumOfValues += res.x * weight;
        sumOfWeights += weight;
        weight = mix(weight, 0.0, 0.2);
        frequency *= 1.18;
        timeMultiplier *= 1.07;
        iter += 1232.399963;
    }

    return sumOfValues / sumOfWeights;
}

vec3 waveNormal(vec2 xz)
{
    vec2 pos = xz * WAVE_SCALE;
    float e = 0.05;
    float depth = WAVE_HEIGHT * global.DC_WATER_WAVES;
    float h = getwaves(pos) * depth;
    vec3 a = vec3(pos.x, h, pos.y);
    vec3 n = normalize(cross(a - vec3(pos.x - e, getwaves(pos - vec2(e, 0.0)) * depth, pos.y),
                             a - vec3(pos.x, getwaves(pos + vec2(0.0, e)) * depth, pos.y + e)));
    return vec3(n.x, -abs(n.y), n.z);
}

float caustics(vec2 xz)
{
    float t = seconds() * 0.7;
    vec2 p = xz * 0.012;
    float c = 0.0;
    for (int i = 0; i < 3; i++)
    {
        vec2 q = p * (1.0 + float(i) * 0.6) + vec2(t * (0.3 + float(i) * 0.12), -t * 0.21);
        vec2 cell = abs(sin(q + sin(q.yx * 1.7 + t)));
        c += pow(1.0 - min(cell.x, cell.y), 8.0);
    }

    return c / 3.0;
}
vec3 shadeWater(vec3 color, vec3 lighting, vec3 p, vec3 l, vec3 moonlight, vec3 ambient, vec3 fallback)
{
    vec3 original = color;
    vec3 world = global.CameraAvailable > 0.5 ? toWorld(p) : p;
    vec3 normalWorld = waveNormal(world.xz);
    vec3 n = global.CameraAvailable > 0.5 ? normalize(toView(normalWorld)) : normalize(normalWorld);
    vec3 v = -normalize(p);
    if (dot(n, v) < 0.0) n = -n;

    float thickness = waterThickness(p);
    vec2 shift = (n.xy - dot(n, v) * v.xy) * WATER_REFRACT * clamp(thickness / 120.0, 0.0, 1.0) / (1.0 + p.z * 0.0004);
    vec2 refracted = vTexCoord + shift;
    float refractedDepth = rawDepth(refracted);
    if (!onScreen(refracted) || isOverlay(refractedDepth) || (hasGeometry(refractedDepth) && viewZ(refractedDepth) < p.z))
        refracted = vTexCoord;
    else thickness = thicknessAt(refracted, p);

    vec3 bottom = refracted == vTexCoord ? color : toLinear(texture(Original, refracted).rgb) * lighting;
    float bottomDepth = rawDepth(refracted);
    if (hasGeometry(bottomDepth) && global.CameraAvailable > 0.5)
    {
        vec3 floorWorld = toWorld(viewPos(refracted, bottomDepth));
        float below = hasWaterLevel() ? max(floorWorld.y - waterLevelY(), 0.0) : thickness * 0.5;
        bottom += bottom * moonlight * caustics(floorWorld.xz) * exp(-below * 0.012) * global.DC_WATER_CAUSTICS * 2.0;
    }

    vec3 transmit = exp(-thickness * WATER_ABSORB * global.DC_WATER_DENSITY);
    vec3 scatter = WATER_COLOR * (ambient + moonlight * 0.35);
    vec3 volume = bottom * transmit + scatter * (1.0 - transmit);

    float facing = max(dot(n, v), 0.0);
    float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
    vec3 r = reflect(-v, n);
    vec3 sky = fallback * 0.7 + moonlight * 0.02;
    color = mix(volume, sky, clamp(max(fresnel * 1.4, 0.03), 0.0, 1.0) * global.DC_WATER_REFLECT);
    float glint = max(dot(r, l), 0.0);
    color += moonlight * (pow(glint, 24.0) * 0.06 + pow(glint, 600.0) * 1.6) * global.DC_WATER_REFLECT;
    //rr?
    float shore = 1.0 - smoothstep(0.0, 22.0, thickness);
    float foam = smoothstep(0.55, 0.85, valueNoise(world.xz * 0.06 + vec2(seconds() * 0.2, 0.0)) * (0.6 + 0.4 * shore));
    color += (ambient + moonlight * 0.25) * vec3(0.5, 0.6, 0.6) * foam * shore * 0.25;
    return waterMask(vTexCoord) || translucentAt(vTexCoord) ? mix(color, original, WATER_TEXTURE_BLEND) : color;
}

vec3 skyLook(vec3 color, vec3 fogColor, vec3 moonlight)
{
    float horizon = smoothstep(0.0, 0.75, vTexCoord.y);
    color = mix(color, fogColor, global.DC_FOG_SKY * mix(0.25, 1.0, horizon));

    vec3 ray = normalize(vec3((vTexCoord - global.Projection.zw) * global.Projection.xy, 1.0));
    float toward = max(dot(ray, sunDir()), 0.0);
    float scatter = pow(toward, 6.0) * 0.35 + pow(toward, 48.0) * 0.6;
    return color + moonlight * scatter * global.DC_SHAFTS * 0.12;
}

void main()
{
    vec3 color = toLinear(sceneUnderUi(texture(Original, vTexCoord).rgb, uiLayer(vTexCoord)));
    float d = depthAt(vTexCoord);
    vec4 extent = texture(Sky, SCENE_TEXEL);
    if (isOverlay(d) || extent.z < 0.01)
    {
        FragColor = vec4(color, 0.0);
        return;
    }

    vec4 skyData = texture(Sky, SKY_TEXEL);
    vec3 sky = skyData.rgb;
    float indoor = 1.0 - clamp(skyData.a * 2.0 - 1.0, 0.0, 1.0);
    vec3 fogColor = curseFog(sky) * mix(1.0, 0.45, indoor * global.DC_CAVE);
    vec3 glow = texture(Glow, vTexCoord).rgb * global.DC_GLOW * GLOW_GAIN;
    glow /= 1.0 + luma(glow);

    vec3 moonlight = mix(COOL_LIGHT, WARM_LIGHT, global.DC_LIGHT_WARMTH) * global.DC_SUN_STRENGTH;
    float dust = (0.4 + 0.6 * indoor) * (0.6 + min(global.DC_FOG, 1.5));
    vec3 beams = texture(Shafts, vTexCoord).r * moonlight * global.DC_SHAFTS * dust * 0.5;

    if (!hasGeometry(d))
    {
        FragColor = vec4(skyLook(color, fogColor + glow * 0.03, moonlight) + beams * 0.55, 1.0);
        return;
    }

    vec3 tint = clamp(sky / max(luma(sky), 1e-4), vec3(0.5), vec3(1.6));
    tint = mix(vec3(1.0), tint / max(luma(tint), 1e-4), 0.25);
    if (global.SceneAmbient.w > 0.5 && luma(global.SceneAmbient.rgb) > 0.0)
    {
        vec3 ambientTint = global.SceneAmbient.rgb / max(luma(global.SceneAmbient.rgb), 1e-4);
        tint = mix(tint, clamp(ambientTint, vec3(0.4), vec3(1.8)), global.DC_GAME_LIGHT * 0.4);
    }

    tint = mix(tint, CURSE_TINT / luma(CURSE_TINT), global.DC_CURSE * 0.35);

    vec3 p = viewPos(vTexCoord, d);
    vec3 v = -normalize(p);
    vec3 l = sunDir();
    Surface surface = gather(vTexCoord, p.z);
    vec3 n = surface.normal;
    float detail = 1.0 - smoothstep(DETAIL_NEAR, DETAIL_FAR, p.z);

    float ao = clamp(mix(1.0, surface.ao, global.DC_AO * detail), 0.0, 1.0);
    float enclosure = clamp(mix(1.0, surface.enclosure, global.DC_AO * detail), 0.0, 1.0);
    float skylight = clamp(mix(1.0, enclosure, 0.7) * (1.0 - indoor * global.DC_CAVE), 0.0, 1.0);
    float skylightSqr = skylight * skylight;

    float diffuse = smoothstep(-0.1, 0.7, dot(n, l));
    float shadow = diffuse > 0.0 && detail > 0.0 && global.DC_SHADOW > 0.0 ? contactShadow(p, n, l) : 1.0;
    float sunlit = mix(0.5, diffuse * mix(1.0, shadow, global.DC_SHADOW), detail);

    vec3 lightColor = mix(COOL_LIGHT, WARM_LIGHT, global.DC_LIGHT_WARMTH);
    if (gameLight())
    {
        vec3 game = global.SceneSunColor.rgb / max(luma(global.SceneSunColor.rgb), 1e-4);
        lightColor = mix(lightColor, clamp(game, vec3(0.3), vec3(2.0)), global.DC_GAME_LIGHT * 0.5);
    }

    float facing = dot(n, worldUp()) * 0.5 + 0.5;
    vec3 ambient = global.DC_AMBIENT * tint * mix(0.6, 1.0, facing);
    vec3 sun = global.DC_SUN_STRENGTH * mix(lightColor, lightColor * tint, 0.3);
    vec3 scene = mix(ambient, sun, sunlit) * skylightSqr;

    if (global.SceneFillDirection.w > 0.5 && global.CameraAvailable > 0.5)
    {
        vec3 fill = normalize(toView(global.SceneFillDirection.xyz));
        vec3 fillColor = global.SceneFillColor.rgb / max(luma(global.SceneFillColor.rgb), 1e-4);
        scene += clamp(fillColor, vec3(0.0), vec3(2.0)) * max(dot(n, fill), 0.0) * 0.25 * global.DC_AMBIENT * global.DC_GAME_LIGHT * skylightSqr;
    }

    vec3 interior = mix(vec3(1.0), CURSE_TINT, global.DC_CURSE * 0.5) * mix(1.0, 0.4, global.DC_CAVE) * (1.0 - skylightSqr);
    vec3 local = sceneLights(p, n) + glow * mix(1.0, 1.6, indoor);

    vec3 lighting = (scene + interior) * ao + local * mix(1.0, ao, 0.5);
    color *= lighting;

    vec3 h = normalize(l + v);
    float specular = pow(max(dot(n, h), 0.0), GLOSS) * SPECULAR * global.DC_SPECULAR * 4.0;
    color += sun * specular * sunlit * skylightSqr * luma(color);

    if (inWater(p)) color = shadeWater(color, lighting, p, l, moonlight, ambient, fogColor + sky * 0.5);

    float darkness = 1.0 - smoothstep(0.0, 0.7, luma(lighting - local));
    color = mix(color, luma(color) * CURSE_TINT / luma(CURSE_TINT),
                darkness * global.DC_DESATURATION * 0.6);

    float start = global.DC_FOG_START * mix(1.0, 0.5, indoor * global.DC_CAVE);
    if (global.SceneFogRange.y > global.SceneFogRange.x)
        start = mix(start, min(start, global.SceneFogRange.x), global.DC_GAME_LIGHT);

    float density = global.DC_FOG * (1.0 + indoor * global.DC_CAVE);
    float dist = length(p);
    float past = max(dist - start, 0.0);
    float onset = smoothstep(0.0, 600.0, past);
    float fog = (1.0 - exp(-past * density * 0.001)) * mix(0.5, 1.0, onset);

    fog = max(fog, (1.0 - exp(-dist * density * 0.00005)) * global.DC_CURSE * 0.4);
    fog = clamp(fog + groundMist(p) * (1.0 - fog), 0.0, 1.0);
    color = mix(color, fogColor + glow * 0.08, fog);
    color += beams * (0.3 + 0.7 * fog);

    if (global.DC_WATER_DEBUG > 0.5)
    {
        if (global.DC_WATER_DEBUG < 1.5) color = waterMask(vTexCoord) ? (isWater(vTexCoord) ? vec3(1.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0)) : color * 0.3;
        else color = inWater(p) ? vec3(1.0 - exp(-waterThickness(p) / 300.0)) : color * 0.1;
    }

    FragColor = vec4(color, 1.0);
}

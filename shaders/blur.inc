layout(set = 0, binding = 2) uniform sampler2D Source;

#include "vertex.inc"

const float OFFSETS[4] = float[](1.4117647, 3.2941176, 5.1764706, 7.0588235);
const float WEIGHTS[4] = float[](0.2969069, 0.0944703, 0.0103813, 0.0003625);

void main()
{
    vec2 stride = BLUR_AXIS * global.SourceSize.zw * BLUR_SPREAD;
    vec3 sum = texture(Source, vTexCoord).rgb * 0.1964825;
    for (int i = 0; i < 4; i++)
    {
        sum += texture(Source, vTexCoord + stride * OFFSETS[i]).rgb * WEIGHTS[i];
        sum += texture(Source, vTexCoord - stride * OFFSETS[i]).rgb * WEIGHTS[i];
    }

    FragColor = vec4(sum, 1.0);
}

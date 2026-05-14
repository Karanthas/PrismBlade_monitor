#include <metal_stdlib>
using namespace metal;

struct PreviewVertexOut {
    float4 position [[position]];
    float2 textureCoordinate;
};

vertex PreviewVertexOut previewVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };

    const float2 textureCoordinates[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    PreviewVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.textureCoordinate = textureCoordinates[vertexID];
    return out;
}

fragment float4 previewFragment(
    PreviewVertexOut in [[stage_in]],
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture3d<float, access::sample> lutTexture [[texture(1)]],
    sampler sourceSampler [[sampler(0)]],
    sampler lutSampler [[sampler(1)]],
    constant float4 *lutUniforms [[buffer(0)]]
) {
    const float4 sourceColor = sourceTexture.sample(sourceSampler, in.textureCoordinate);
    const float isEnabled = lutUniforms[0].x;

    if (isEnabled < 0.5) {
        return sourceColor;
    }

    const float intensity = clamp(lutUniforms[0].y, 0.0, 1.0);
    const float cubeSize = max(lutUniforms[0].z, 1.0);
    const float3 domainMin = lutUniforms[1].xyz;
    const float3 domainMax = lutUniforms[2].xyz;
    const float3 domainRange = max(domainMax - domainMin, float3(0.00001));
    const float3 normalizedColor = clamp((sourceColor.rgb - domainMin) / domainRange, 0.0, 1.0);
    const float3 lutCoordinate = ((normalizedColor * (cubeSize - 1.0)) + 0.5) / cubeSize;
    const float3 lutColor = lutTexture.sample(lutSampler, lutCoordinate).rgb;

    return float4(mix(sourceColor.rgb, lutColor, intensity), sourceColor.a);
}

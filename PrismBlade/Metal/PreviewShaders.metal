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
    sampler sourceSampler [[sampler(0)]]
) {
    return sourceTexture.sample(sourceSampler, in.textureCoordinate);
}

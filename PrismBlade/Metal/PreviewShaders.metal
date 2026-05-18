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

float nlogDecode(float x);
float hlgDecode(float x);
float3 transformToWorkingSpace(float3 color, float encodingCode);
float3 applyDisplayLUT(float3 workingColor, texture3d<float, access::sample> lutTexture, sampler lutSampler, constant float4 *lutUniforms);
float rec709Luma(float3 color);
float3 falseColor(float luma);
bool zebraApplies(float luma, constant float4 *monitorUniforms);
float3 applyZebra(float3 color, float2 pixelPosition);
uint scopeBin(float value, uint binHeight);

fragment float4 previewFragment(
    PreviewVertexOut in [[stage_in]],
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture3d<float, access::sample> lutTexture [[texture(1)]],
    sampler sourceSampler [[sampler(0)]],
    sampler lutSampler [[sampler(1)]],
    constant float4 *lutUniforms [[buffer(0)]],
    constant float4 *monitorUniforms [[buffer(1)]]
) {
    const float4 sourceColor = sourceTexture.sample(sourceSampler, in.textureCoordinate);
    const float3 workingColor = transformToWorkingSpace(sourceColor.rgb, monitorUniforms[0].x);
    float3 displayColor = applyDisplayLUT(workingColor, lutTexture, lutSampler, lutUniforms);

    const float luma = rec709Luma(workingColor);

    if (monitorUniforms[0].y >= 0.5) {
        displayColor = falseColor(luma);
    }

    if (monitorUniforms[0].z >= 0.5 && zebraApplies(luma, monitorUniforms)) {
        displayColor = applyZebra(displayColor, in.position.xy);
    }

    return float4(clamp(displayColor, 0.0, 1.0), sourceColor.a);
}

float nlogDecode(float x) {
    const float cut = 452.0 / 1023.0;
    const float a = 650.0 / 1023.0;
    const float b = 0.0075;
    const float c = 150.0 / 1023.0;
    const float d = 619.0 / 1023.0;

    x = clamp(x, 0.0, 1.0);
    if (x < cut) {
        return clamp(pow(max(x / a, 0.0), 3.0) - b, 0.0, 1.0);
    }

    return clamp(exp((x - d) / c), 0.0, 1.0);
}

float hlgDecode(float x) {
    const float a = 0.17883277;
    const float b = 0.28466892;
    const float c = 0.55991073;

    x = clamp(x, 0.0, 1.0);
    if (x <= 0.5) {
        return clamp((x * x) / 3.0, 0.0, 1.0);
    }

    return clamp((exp((x - c) / a) + b) / 12.0, 0.0, 1.0);
}

float3 transformToWorkingSpace(float3 color, float encodingCode) {
    if (encodingCode < 0.5) {
        return clamp(color, 0.0, 1.0);
    }

    if (encodingCode < 1.5) {
        return float3(nlogDecode(color.r), nlogDecode(color.g), nlogDecode(color.b));
    }

    return float3(hlgDecode(color.r), hlgDecode(color.g), hlgDecode(color.b));
}

float3 applyDisplayLUT(
    float3 workingColor,
    texture3d<float, access::sample> lutTexture,
    sampler lutSampler,
    constant float4 *lutUniforms
) {
    if (lutUniforms[0].x < 0.5) {
        return workingColor;
    }

    const float intensity = clamp(lutUniforms[0].y, 0.0, 1.0);
    const float cubeSize = max(lutUniforms[0].z, 1.0);
    const float3 domainMin = lutUniforms[1].xyz;
    const float3 domainMax = lutUniforms[2].xyz;
    const float3 domainRange = max(domainMax - domainMin, float3(0.00001));
    const float3 normalizedColor = clamp((workingColor - domainMin) / domainRange, 0.0, 1.0);
    const float3 lutCoordinate = ((normalizedColor * (cubeSize - 1.0)) + 0.5) / cubeSize;
    const float3 lutColor = lutTexture.sample(lutSampler, lutCoordinate).rgb;
    return mix(workingColor, lutColor, intensity);
}

float rec709Luma(float3 color) {
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

float3 falseColor(float luma) {
    const float ire = clamp(luma, 0.0, 1.2) * 100.0;

    if (ire <= 5.0) {
        return float3(0.24, 0.05, 0.82);
    }

    if (abs(ire - 18.0) <= 2.0) {
        return float3(0.48, 0.48, 0.48);
    }

    if (ire < 40.0) {
        return float3(0.06, 0.26, 0.90);
    }

    if (ire <= 60.0) {
        return float3(0.10, 0.86, 0.26);
    }

    if (ire < 90.0) {
        return float3(0.88, 0.88, 0.22);
    }

    if (ire < 99.5) {
        return float3(1.00, 0.54, 0.05);
    }

    return float3(1.00, 0.02, 0.02);
}

bool zebraApplies(float luma, constant float4 *monitorUniforms) {
    const float mode = monitorUniforms[0].w;
    const float threshold = clamp(monitorUniforms[1].x, 0.0, 1.0);

    if (mode < 0.5) {
        return luma >= threshold;
    }

    const float lower = min(monitorUniforms[1].y, monitorUniforms[1].z);
    const float upper = max(monitorUniforms[1].y, monitorUniforms[1].z);
    return luma >= lower && luma <= upper;
}

float3 applyZebra(float3 color, float2 pixelPosition) {
    const float stripe = fmod(pixelPosition.x + pixelPosition.y, 14.0);
    if (stripe < 7.0) {
        return mix(color, float3(1.0), 0.88);
    }

    return mix(color, float3(0.0), 0.58);
}

kernel void scopeCompute(
    texture2d<float, access::read> sourceTexture [[texture(0)]],
    texture3d<float, access::sample> lutTexture [[texture(1)]],
    sampler lutSampler [[sampler(0)]],
    device atomic_uint *lumaBins [[buffer(0)]],
    device atomic_uint *redBins [[buffer(1)]],
    device atomic_uint *greenBins [[buffer(2)]],
    device atomic_uint *blueBins [[buffer(3)]],
    constant float4 *scopeUniforms [[buffer(4)]],
    constant float4 *lutUniforms [[buffer(5)]],
    uint2 gid [[thread_position_in_grid]]
) {
    const uint sourceWidth = sourceTexture.get_width();
    const uint sourceHeight = sourceTexture.get_height();
    const uint sampleWidth = max(uint(scopeUniforms[1].z), 1u);
    const uint sampleHeight = max(uint(scopeUniforms[1].w), 1u);

    if (gid.x >= sampleWidth || gid.y >= sampleHeight) {
        return;
    }

    const uint binWidth = max(uint(scopeUniforms[0].x), 1u);
    const uint binHeight = max(uint(scopeUniforms[0].y), 1u);
    const float encodingCode = scopeUniforms[0].z;
    const uint sourceX = min(uint((float(gid.x) + 0.5) * float(sourceWidth) / float(sampleWidth)), sourceWidth - 1u);
    const uint sourceY = min(uint((float(gid.y) + 0.5) * float(sourceHeight) / float(sampleHeight)), sourceHeight - 1u);
    const float4 sourceColor = sourceTexture.read(uint2(sourceX, sourceY));
    const float3 workingColor = transformToWorkingSpace(sourceColor.rgb, encodingCode);
    const float3 displayColor = applyDisplayLUT(workingColor, lutTexture, lutSampler, lutUniforms);
    const uint column = min((gid.x * binWidth) / sampleWidth, binWidth - 1u);

    const uint lumaIndex = column * binHeight + scopeBin(rec709Luma(displayColor), binHeight);
    const uint redIndex = column * binHeight + scopeBin(displayColor.r, binHeight);
    const uint greenIndex = column * binHeight + scopeBin(displayColor.g, binHeight);
    const uint blueIndex = column * binHeight + scopeBin(displayColor.b, binHeight);

    atomic_fetch_add_explicit(&lumaBins[lumaIndex], 1u, memory_order_relaxed);
    atomic_fetch_add_explicit(&redBins[redIndex], 1u, memory_order_relaxed);
    atomic_fetch_add_explicit(&greenBins[greenIndex], 1u, memory_order_relaxed);
    atomic_fetch_add_explicit(&blueBins[blueIndex], 1u, memory_order_relaxed);
}

uint scopeBin(float value, uint binHeight) {
    const float clamped = clamp(value, 0.0, 1.0);
    return min(uint(round(clamped * float(binHeight - 1u))), binHeight - 1u);
}

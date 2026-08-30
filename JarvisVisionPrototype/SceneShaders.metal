
#include <metal_stdlib>
using namespace metal;

constant bool useLayeredRendering [[function_constant(0)]];

struct VertexIn {
    float3 position  [[attribute(0)]];
    float3 normal    [[attribute(1)]];
    float2 texCoords [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 viewNormal;
    float2 texCoords;
};

struct LayeredVertexOut {
    float4 position [[position]];
    float3 viewNormal;
    float2 texCoords;
    uint renderTargetIndex [[render_target_array_index]];
    uint viewportIndex [[viewport_array_index]];
};

struct FragmentIn {
    float4 position [[position]];
    float3 viewNormal;
    float2 texCoords;
    uint renderTargetIndex [[render_target_array_index]];
    uint viewportIndex [[viewport_array_index]];
};

struct PoseConstants {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
};

struct InstanceConstants {
    float4x4 modelMatrix;
    float sceneTime;
    float3 padding;
};

[[vertex]]
LayeredVertexOut vertex_main(VertexIn in [[stage_in]],
                             constant PoseConstants *poses [[buffer(1)]],
                             constant InstanceConstants &instance [[buffer(2)]],
                             uint amplificationID [[amplification_id]])
{
    constant auto &pose = poses[amplificationID];
    
    LayeredVertexOut out;
    out.position = pose.projectionMatrix * pose.viewMatrix * instance.modelMatrix * float4(in.position, 1.0f);
    out.viewNormal = (pose.viewMatrix * instance.modelMatrix * float4(in.normal, 0.0f)).xyz;
    out.texCoords = in.texCoords;
    out.texCoords.x = 1.0f - out.texCoords.x; // Flip uvs horizontally to match Model I/O
    if (useLayeredRendering) {
        out.renderTargetIndex = amplificationID;
    }
    out.viewportIndex = amplificationID;
    return out;
}

[[vertex]]
VertexOut vertex_dedicated_main(VertexIn in [[stage_in]],
                                constant PoseConstants *poses [[buffer(1)]],
                                constant InstanceConstants &instance [[buffer(2)]])
{
    constant auto &pose = poses[0];
    
    VertexOut out;
    out.position = pose.projectionMatrix * pose.viewMatrix * instance.modelMatrix * float4(in.position, 1.0f);
    out.viewNormal = (pose.viewMatrix * instance.modelMatrix * float4(in.normal, 0.0f)).xyz;
    out.texCoords = in.texCoords;
    out.texCoords.x = 1.0f - out.texCoords.x; // Flip uvs horizontally to match Model I/O
    return out;
}

[[fragment]]
half4 fragment_main(FragmentIn in [[stage_in]],
                    constant InstanceConstants &instance [[buffer(0)]])
{
    float2 uv = in.texCoords;
    float t = instance.sceneTime;
    float noise = 0.82 + 0.18 * sin(uv.x * 91.0 + uv.y * 67.0 + t * 7.0);
    float3 normal = normalize(in.viewNormal);
    float edge = pow(saturate(1.0 - abs(normal.z)), 2.15);
    float pulse = 0.78 + 0.22 * sin(t * 2.4);
    float scanBand = smoothstep(0.45, 0.5, fract(uv.y * 18.0 + t * 0.32));
    float scan = 0.72 + 0.20 * sin(t * 3.2 + uv.y * 28.0) + scanBand * 0.34;
    float dissolve = smoothstep(0.12, 0.82, noise + sin(uv.x * 13.0 + t) * 0.08);
    // The sphere body is fully transparent. Only the view-dependent silhouette
    // remains, producing a floating contour instead of a glowing solid shell.
    float body = 0.18 + edge * 1.8;
    float intensity = body * 2.7 * noise * pulse * scan;
    float3 cyan = float3(0.04, 0.68, 1.0);
    float3 amber = float3(1.0, 0.28, 0.05);
    float dispersion = smoothstep(0.62, 1.0, edge) * (0.5 + 0.5 * sin(t * 1.7));
    float3 color = mix(cyan, amber, dispersion * 0.32) * intensity;
    float alpha = saturate((0.16 + edge * 0.84) * noise * scan * dissolve);
    return half4(half3(color), half(alpha));
}

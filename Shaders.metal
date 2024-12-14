#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float3 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

struct Uniforms {
    float4x4 modelViewProjection;
};

struct RasterizerData {
    float4 position [[position]];
    float4 color;
};

vertex RasterizerData vertexShader(uint vertexID [[vertex_id]],
                                 constant Vertex *vertices [[buffer(0)]],
                                 constant Uniforms &uniforms [[buffer(1)]]) {
    RasterizerData out;
    out.position = uniforms.modelViewProjection * float4(vertices[vertexID].position, 1.0);
    out.color = vertices[vertexID].color;
    return out;
}

fragment float4 fragmentShader(RasterizerData in [[stage_in]]) {
    return in.color;
}

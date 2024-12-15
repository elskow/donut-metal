#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float3 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
    float3 normal   [[attribute(2)]];
};

struct Uniforms {
    float4x4 modelViewProjection;
    float4x4 modelView;
    float3 lightPosition;
    float3 cameraPosition;
    float ambientIntensity;
    float specularPower;
};

struct RasterizerData {
    float4 position [[position]];
    float4 color;
    float3 worldPosition;
    float3 normal;
};

vertex RasterizerData vertexShader(uint vertexID [[vertex_id]],
                                 constant Vertex *vertices [[buffer(0)]],
                                 constant Uniforms &uniforms [[buffer(1)]]) {
    RasterizerData out;
    float4 worldPosition = uniforms.modelView * float4(vertices[vertexID].position, 1.0);
    out.position = uniforms.modelViewProjection * float4(vertices[vertexID].position, 1.0);
    out.color = vertices[vertexID].color;
    out.worldPosition = worldPosition.xyz;
    out.normal = (uniforms.modelView * float4(vertices[vertexID].normal, 0.0)).xyz;
    return out;
}

fragment float4 fragmentShader(RasterizerData in [[stage_in]],
                             constant Uniforms &uniforms [[buffer(1)]]) {
    float3 normal = normalize(in.normal);
    float3 lightDir = normalize(uniforms.lightPosition - in.worldPosition);
    float3 viewDir = normalize(uniforms.cameraPosition - in.worldPosition);
    float3 reflectDir = reflect(-lightDir, normal);
    
    float diff = max(dot(normal, lightDir), 0.0);
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), uniforms.specularPower);
    
    float3 ambient = float3(uniforms.ambientIntensity);
    float3 diffuse = diff * float3(1.0);
    float3 specular = spec * float3(0.5);
    
    float3 result = (ambient + diffuse + specular) * in.color.rgb;
    return float4(result, in.color.a);
}

// Plane shader
vertex RasterizerData planeVertexShader(uint vertexID [[vertex_id]],
                                      constant Vertex *vertices [[buffer(0)]],
                                      constant Uniforms &uniforms [[buffer(1)]]) {
    RasterizerData out;
    float4 worldPosition = uniforms.modelView * float4(vertices[vertexID].position, 1.0);
    out.position = uniforms.modelViewProjection * float4(vertices[vertexID].position, 1.0);
    out.color = vertices[vertexID].color;
    out.worldPosition = worldPosition.xyz;
    out.normal = (uniforms.modelView * float4(vertices[vertexID].normal, 0.0)).xyz;
    return out;
}

fragment float4 planeFragmentShader(RasterizerData in [[stage_in]],
                                  constant Uniforms &uniforms [[buffer(1)]]) {
    float3 normal = normalize(in.normal);
    float3 lightDir = normalize(uniforms.lightPosition - in.worldPosition);
    
    float diff = max(dot(normal, lightDir), 0.0);
    float checkerboard = fmod(floor(in.worldPosition.x) + floor(in.worldPosition.z), 2.0);
    float3 color = checkerboard < 1.0 ? float3(0.2) : float3(0.8);
    
    float3 result = (uniforms.ambientIntensity + diff) * color;
    return float4(result, 1.0);
}

#include <metal_stdlib>
using namespace metal;


struct AdjustSaturationUniforms
{
    float saturationFactor;
};


kernel void render(
                   texture2d<float, access::read> input [[texture(0)]],
                   texture2d<float, access::write> output [[texture(1)]],
//                   constant AdjustSaturationUniforms &uniforms [[buffer(0)]],
                   uint2 coordinate [[thread_position_in_grid]])
{
    const auto dimensions = float2(output.get_width(), output.get_height());
    const auto position = float2(coordinate);
//    float4 inColor = inTexture.read(gid);
//    float value = dot(inColor.rgb, float3(0.299, 0.587, 0.114));
//    float4 grayColor(value, value, value, 1.0);
//    float4 outColor = mix(grayColor, inColor, uniforms.saturationFactor);
//    float4 color = float4(1, 0, 1, 1);
    float u = position.x / dimensions.x;
    float v = position.y / dimensions.y;
    float4 color = float4(u, u * v, 1 - v, 1);
    output.write(color, coordinate);
}

//kernel void render(device const float* inA,
//                       device const float* inB,
//                       device float* result,
//                       uint index [[thread_position_in_grid]])
//{
//    // the for-loop is replaced with a collection of threads, each of which
//    // calls this function.
//    result[index] = inA[index] + inB[index];
//}

#include <metal_stdlib>
using namespace metal;


//struct AdjustSaturationUniforms
//{
//    float saturationFactor;
//};

class ray
{
    
public:
    float3 origin;
    float3 direction;
    
public:
    
    ray() {}
    
    ray(thread const float3 & origin,
        thread const float3 & direction)
    : origin(origin), direction(direction)
    {}
    
    float3 at(thread const float t)
    {
        return origin + (t * direction);
    }
};


float3 lerp(float3 a,
            float3 b,
            float t)
{
    return (1.0 - t) * a + t * b;
}


bool hit_sphere(thread const float3 & center,
                float radius,
                thread const ray & r)
{
    float3 oc = r.origin - center;
    auto a = dot(r.direction, r.direction);
    auto b = 2 * dot(oc, r.direction);
    auto c = dot(oc, oc) - (radius * radius);
    auto discriminant = (b * b) - (4 * a * c);
    return (discriminant > 0);
}


float3 ray_color(thread const ray & r)
{
    if (hit_sphere(float3(0, 0, -1), 0.5, r))
    {
        return float3(1, 0, 0);
    }
    float3 unit_direction = normalize(r.direction);
    auto t = 0.5 * (unit_direction.y + 1.0);
    return lerp(float3(1.0, 1.0, 1.0), float3(0.5, 0.7, 1.0), t);
}


kernel void render(texture2d<float, access::read> input [[texture(0)]],
                   texture2d<float, access::write> output [[texture(1)]],
//                   constant AdjustSaturationUniforms &uniforms [[buffer(0)]],
                   uint2 gid [[thread_position_in_grid]])
{
    const auto coordinate = uint2(gid.x, output.get_height() - gid.y - 1);
    const auto dimensions = float2(output.get_width(), output.get_height());
    const auto aspect_ratio = dimensions.x / dimensions.y;
    float2 viewport = float2(2 * aspect_ratio, 2);
    float focal_length = 1.0;
    
    float3 origin = float3(0, 0, 0);
    float3 horizontal = float3(viewport.x, 0, 0);
    float3 vertical = float3(0, viewport.y, 0);
    float3 lower_left_corner = origin - (horizontal / 2) - (vertical / 2) - float3(0, 0, focal_length);

    float2 position = float2(coordinate);
    float u = position.x / dimensions.x;
    float v = position.y / dimensions.y;

    float3 ray_direction = lower_left_corner + (u * horizontal) + (v * vertical) - origin;
    ray r(origin, ray_direction);

    float4 color = float4(ray_color(r), 1);
//    float4 color = float4(u, u * v, 1 - v, 1);
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

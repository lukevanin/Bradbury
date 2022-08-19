#include <metal_stdlib>
using namespace metal;


//struct AdjustSaturationUniforms
//{
//    float saturationFactor;
//};


float3 lerp(float3 a, float3 b, float t) {
    return (1.0 - t) * a + t * b;
}


class ray {
    
public:
    float3 origin;
    float3 direction;
    
public:
    
    ray() {}
    
    ray(thread const float3 & origin, thread const float3 & direction)
    : origin(origin), direction(direction)
    {}
    
    float3 at(float t) const {
        return origin + (t * direction);
    }
};


struct hit_record {
    float3 p;
    float3 normal;
    float t;
    bool front_face;
    
    void set_face_normal(thread const ray & r, thread const float3 & outward_normal) {
        front_face = dot(r.direction, outward_normal) < 0;
        normal = front_face ? outward_normal : -outward_normal;
    }
};


//class hittable {
//
//public:
//    hittable();
//
//    bool hit(thread const ray & r, float t_min, float t_max, thread hit_record & rec) const {
//        return false;
//    }
//};


class sphere {
    
public:
    float3 center;
    float radius;
    
public:
    sphere(thread const float3 & center, float radius)
    : center(center), radius(radius)
    {}
    
    bool hit(thread const ray & r, float t_min, float t_max, thread hit_record & rec) const {
        float3 oc = r.origin - center;
        auto a = length_squared(r.direction);
        auto halfB = dot(oc, r.direction);
        auto c = length_squared(oc) - (radius * radius);
        auto discriminant = (halfB * halfB) - (a * c);
        if (discriminant < 0) {
            return false;
        }
        
        auto sqrt_d = sqrt(discriminant);
        auto root = (-halfB - sqrt_d) / a;
        if (root < t_min || root > t_max) {
            root = (-halfB + sqrt_d) / a;
            if (root < t_min || root > t_max) {
                return false;
            }
        }
        
        auto p = r.at(root);
        auto n = (p - center) / radius;
        rec.t = root;
        rec.p = p;
        rec.set_face_normal(r, n);
        return true;
    }
};


struct hittable_list {
    
public:
    int count;
    thread const sphere * items;
    
public:
    hittable_list(int count, sphere items[])
    : count(count), items(items)
    {}
    
    bool hit(thread const ray & r, float t_min, float t_max, thread hit_record & rec) const {
        hit_record temp_rec;
        float closest = t_max;
        bool hit_anything = false;
        for (auto i = 0; i < count; i++) {
            const auto item = items[i];
            if (item.hit(r, t_min, closest, temp_rec) == true) {
                closest = temp_rec.t;
                rec = temp_rec;
                hit_anything = true;
            }
        }
        return hit_anything;
    }
};


//float hit_sphere(thread const float3 & center,
//                float radius,
//                thread const ray & r) {
//}


float3 ray_color(thread const ray & r, thread const hittable_list & world) {
    hit_record rec;
    if (world.hit(r, 0, INFINITY, rec) == true) {
        return 0.5 * (rec.normal + float3(1, 1, 1));
    }
    float3 unit_direction = normalize(r.direction);
    auto t = 0.5 * (unit_direction.y + 1.0);
    return lerp(float3(1.0, 1.0, 1.0), float3(0.5, 0.7, 1.0), t);
}


kernel void render(texture2d<float, access::read> input [[texture(0)]],
                   texture2d<float, access::write> output [[texture(1)]],
//                   constant AdjustSaturationUniforms &uniforms [[buffer(0)]],
                   uint2 gid [[thread_position_in_grid]]) {
    const auto coordinate = uint2(gid.x, output.get_height() - gid.y - 1);
    const auto dimensions = float2(output.get_width(), output.get_height());
    const auto aspect_ratio = dimensions.x / dimensions.y;
    const auto viewport = float2(2 * aspect_ratio, 2);
    const float focal_length = 1.0;
    
    float3 origin = float3(0, 0, 0);
    float3 horizontal = float3(viewport.x, 0, 0);
    float3 vertical = float3(0, viewport.y, 0);
    float3 lower_left_corner = origin - (horizontal / 2) - (vertical / 2) - float3(0, 0, focal_length);

    auto position = float2(coordinate);
    float u = position.x / dimensions.x;
    float v = position.y / dimensions.y;

    float3 ray_direction = lower_left_corner + (u * horizontal) + (v * vertical) - origin;
    ray r(origin, ray_direction);
    
    sphere items[] = {
        sphere(float3(0, 0, -1), 0.5),
        sphere(float3(0, -100.5, -1), 100),
    };
    auto world = hittable_list(2, items);

    float4 color = float4(ray_color(r, world), 1);
//    float4 color = float4(u, u * v, 1 - v, 1);
    output.write(color, gid);
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

#include <metal_stdlib>
#include "RendererInterface.h"
using namespace metal;


float3 lerp(float3 a, float3 b, float t) {
    return (1.0 - t) * a + t * b;
}


// Gold Noise ©2015 dcerisano@standard3d.com
// - based on the Golden Ratio
// - uniform normalized distribution
// - fastest static noise generator function (also runs at low precision)
// - use with indicated fractional seeding method.
float _gold_noise(const float2 xy, const float seed) {
    float PHI = 1.61803398874989484820459;  // Φ = Golden Ratio
    return fract(tan(distance(xy * PHI, xy) * seed) * xy.x);
}

/**
 * http://www.jcgt.org/published/0009/03/02/
 */
uint3 pcg3d(uint3 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    return v;
}


float3 random3(float3 f) {
    return as_type<float3>((pcg3d(as_type<uint3>(f)) & 0x007FFFFFu) | 0x3F800000u) - 1.0;
}


float random_float(float2 xy, float z) {
    return random3(float3(xy, z)).x;
}


inline float3 sampleCosineWeightedHemisphere(const float2 u) {
    float phi = 2.0f * M_PI_F * u.x;
    
    float cos_phi;
    float sin_phi = sincos(phi, cos_phi);
    
    float cos_theta = sqrt(u.y);
    float sin_theta = sqrt(1.0f - cos_theta * cos_theta);
    
    return float3(sin_theta * cos_phi, cos_theta, sin_theta * sin_phi);
}


inline float3 sample_unit_sphere(const float2 xy) {
    const float pi = 3.1415927;
    float2 uv = fract(xy);
    uv.y = uv.y * 2. - 1.;
    return float3(sqrt(max(0.0, 1.0 - uv.y * uv.y)) * sin(float2(.5 * pi, 0) + uv.x * 2. * pi), uv.y);
}


inline float3 sample_unit_hemisphere(const float2 xy, const float3 n) {
    float3 v = sample_unit_sphere(xy);
    return normalize(v * sign(dot(v, n)));
}


inline float reflectance(float cosine, float ri) {
    auto r = (1 - ri) / (1 + ri);
    auto r0 = r * r;
    return r0 + (1 - r0) * pow(1 - cosine, 5);
}


class noise {
    
private:
    float seed;
    float2 xy;
    
public:
    noise(float2 xy, float seed) : xy(xy), seed(seed) {}
    
    inline float next() {
        //float f = 1.0; // _gold_noise(xy, seed);
        while (true) {
            // f = _gold_noise(xy, seed);
            float f = random_float(xy, seed);
            seed += 0.1; // + _gold_noise(xy, seed);
            if (f >= 0 && f < 1) {
                return f;
            }
        }
    }
};


class random {
    
private:
    noise a, b;
    
public:
    random(noise a, noise b) : a(a), b(b) {}
    
    inline float next_float(float min = 0, float max = 1) {
//        float f = 1.0; // _gold_noise(xy, seed);
//        while (f < 0 || f >= 1.0) {
//            // f = _gold_noise(xy, seed);
//            f = random_float(xy, seed);
//            seed += 0.1; // + _gold_noise(xy, seed);
//        }
//        return f;
        while (true) {
//            float x = (a.next() * 2) - 1;
//            float y = (b.next() * 2) - 1;
//            float f = (x - y) * 0.5; // bluish noise (rougher)
            float x = a.next();
            float y = b.next();
            float f = (x + y) * 0.5; // red noise (smoother)
            if (f >= 0 && f < 1) {
                return min + ((max - min) * f);
            }
        }
    }
    
    inline float2 next_float2(float min = 0, float max = 1) {
        return float2(
                      next_float(min, max),
                      next_float(min, max)
                      );
    }

    inline float3 next_float3(float min = 0, float max = 1) {
        return float3(
                      next_float(min, max),
                      next_float(min, max),
                      next_float(min, max)
                      );
    }
    
    inline float3 random_in_unit_disk() {
        while (true) {
            auto p = float3(next_float(-1, 1), next_float(-1, 1), 0);
            if (length_squared(p) < 1) {
                return p;
            }
        }
    }

};


class ray {
    
public:
    float3 origin;
    float3 direction;
    
public:
    
    ray() {}
    
    ray(thread const float3 & origin, thread const float3 & direction)
    : origin(origin), direction(direction)
    {}
    
    inline float3 at(float t) const {
        return origin + (t * direction);
    }
};


class camera {
    
private:
    float3 origin;
    float3 lower_left_corner;
    float3 horizontal;
    float3 vertical;
    float3 u, v, w;
    float lens_radius;
    
public:
    camera(float3 look_from,
           float3 look_at,
           float3 vup,
           float fov,
           float aspect_ratio,
           float aperature,
           float focus_dist) {
        const auto theta = fov * M_PI_F / 180;
        const auto h = tan(theta / 2);
        
        const auto viewport_height = 2.0 * h;
        const auto viewport_width = aspect_ratio * viewport_height;
        
        w = normalize(look_from - look_at);
        u = normalize(cross(vup, w));
        v = cross(w, u);
        
        origin = look_from;
        horizontal = focus_dist * viewport_width * u;
        vertical = focus_dist * viewport_height * v;
        lower_left_corner = origin - (horizontal / 2) - (vertical / 2) - (focus_dist * w);
        
        lens_radius = aperature / 2;
    }
    
    inline ray get_ray(float2 uv, random rng) const {
        // float3 rd = lens_radius * float3(rng.next_float2(-1, +1), 0);
        float3 rd = lens_radius * rng.random_in_unit_disk();
        float3 offset = u * rd.x + v * rd.y;
        float3 ray_direction = normalize(lower_left_corner + (uv.x * horizontal) + (uv.y * vertical) - origin - offset);
        return ray(origin + offset, ray_direction);
    }
};


struct material;


struct hit_record {
    float3 p;
    float3 normal;
    thread material * m;
    float t;
    bool front_face;
    
    inline void set_face_normal(thread const ray & r, thread const float3 & outward_normal) {
        front_face = dot(r.direction, outward_normal) < 0;
        normal = front_face ? outward_normal : -outward_normal;
    }
};


class material {
    
private:
    int type;
    float3 albedo;
    float roughness;
    float index_of_refraction;
    
public:
    material(int type, float3 albedo, float roughness, float index_of_refraction)
    : type(type), albedo(albedo), roughness(roughness), index_of_refraction(index_of_refraction) {}
    
    bool scatter(thread const ray & r,
                 thread const hit_record & rec,
                 thread random & rng,
                 thread float3 & attenuation,
                 thread ray & scattered) {
        auto diffuse_direction = sample_unit_hemisphere(rng.next_float2(-1, +1), rec.normal);
//        float3 diffuse_direction = normalize(rec.normal + sample_unit_sphere(rng.next_float2(-1, +1)));
//                    float3 target = normalize(rec.normal + sampleCosineWeightedHemisphere(rng.next_float2(-1, 1)));
//        float3 diffuse_direction = normalize(rec.normal + normalize(rng.next_float3(-1, 1)));
        if (type == 0) {
            scattered = ray(rec.p, normalize(diffuse_direction));
            attenuation = albedo;
            return true;
        }
        else if (type == 1) {
            float3 reflected = reflect(r.direction, rec.normal) + (roughness * diffuse_direction);
            scattered = ray(rec.p, normalize(reflected));
            attenuation = albedo;
            return (dot(reflected, rec.normal) > 0);
        }
        else if (type == 2) {
            attenuation = float3(1, 1, 1);
            float refraction_ratio = rec.front_face ? (1 / index_of_refraction) : index_of_refraction;
            float cos_theta = fmin(dot(-r.direction, rec.normal), 1.0);
            float3 refracted = refract(r.direction, rec.normal, refraction_ratio);
            float3 reflected = reflect(r.direction, rec.normal); // + (roughness * diffuse_direction));
            if (length_squared(refracted) == 0) {
                scattered = ray(rec.p, normalize(reflected));
            }
            else {
                float reflect_probability = reflectance(cos_theta, refraction_ratio);
                bool reflect = rng.next_float(0, 1) < reflect_probability;
                if (reflect == true) {
                    scattered = ray(rec.p, normalize(reflected));
                }
                else {
                    scattered = ray(rec.p, normalize(refracted));
                }
            }
            return true;
        }
        else {
            return false;
        }
    }
};



class sphere {
    
public:
    float3 center;
    float radius;
    thread material * m;
    
public:
    sphere(thread const float3 & center, float radius, thread material * m)
    : center(center), radius(radius), m(m)
    {}
    
    inline bool hit(thread const ray & r,
                    const float t_min,
                    const float t_max,
                    thread hit_record & rec) const {
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
        auto n = normalize((p - center) / radius);
        rec.t = root;
        rec.p = p;
        rec.set_face_normal(r, n);
        rec.m = m;
        return true;
    }
};


struct hittable_list {
    
public:
    // TODO: Use <array> type
    int count;
    thread const sphere * items;
    
public:
    hittable_list(int count, sphere items[])
    : count(count), items(items)
    {}
    
    inline bool hit(thread const ray & r, float t_min, float t_max, thread hit_record & rec) const {
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


float3 ray_color(thread const ray & primary_ray,
                 thread random & rng,
                 thread const hittable_list & world) {
    hit_record rec;
    ray r = primary_ray;
    const int max_depth = 50;
    int depth = 0;
    float3 attenuation = float3(1, 1, 1);
    while (depth < max_depth) {
        //
        if (world.hit(r, 0.001, INFINITY, rec) == true) {
            float3 bounce_attenuation;
            ray bounce_ray;
            if (rec.m->scatter(r, rec, rng, bounce_attenuation, bounce_ray)) {
                r = bounce_ray;
                attenuation = bounce_attenuation * attenuation;
                depth += 1;
            }
            else {
                return float3(0, 0, 0);
            }
        }
        else {
            float3 unit_direction = r.direction;
            const auto t = 0.5 * (unit_direction.y + 1.0);
            const auto sky_color = lerp(float3(1.0, 1.0, 1.0), float3(0.5, 0.7, 1.0), t);
            return attenuation * sky_color;
        }
    }
    return float3(0, 0, 0);
}


constant float random_seed [[function_constant(0)]];


kernel void render(texture2d<float, access::read_write> accumulator [[texture(0)]],
                   texture2d<float, access::write> output [[texture(1)]],
                   constant render_parameters * env [[buffer(0)]],
                   device const float * noise_buffer [[buffer(1)]],
                   uint2 gid [[thread_position_in_grid]]) {
    
    const auto coordinate = uint2(gid.x, accumulator.get_height() - gid.y - 1);
    const auto dimensions = float2(accumulator.get_width(), accumulator.get_height());
    const auto aspect_ratio = dimensions.x / dimensions.y;

    const auto position = float2(coordinate);
    const float2 uv = position / dimensions;
    
    const auto random_seed_index = (gid.y * accumulator.get_width()) + gid.x + env->noise_offset;
    const uint random_seed_index_a = ((random_seed_index * 2) + 0) % env->noise_buffer_size;
    const uint random_seed_index_b = ((random_seed_index * 2) + 1) % env->noise_buffer_size;
    const auto random_seed_a = fract(noise_buffer[random_seed_index_a]);
    const auto random_seed_b = fract(noise_buffer[random_seed_index_b]);
    const noise noise_a = noise(uv, random_seed_a);
    const noise noise_b = noise(uv, random_seed_b);
    auto rng = random(noise_a, noise_b);

    // TODO: Pass camera and scene as parameters
    const auto look_from = float3(3, 3, 2);
    const auto look_at = float3(0, 0, -1);
    const auto vup = float3(0, 1, 0);
    const auto focus_dist = length(look_from - look_at);
    const auto aperature = 2.0;
    const auto fov = 20.0;
    const auto cam = camera(look_from, look_at, vup, fov, aspect_ratio, aperature, focus_dist);
//    const auto cam = camera(float3(0, 0, 0), float3(0, 0, -1), float3(0, 1, 0), 90, aspect_ratio, 0.01, 1.0);

    auto yellow_lambertian_material = material(0, float3(0.8, 0.8, 0.0), 1, 0);
    // auto pink_lambertian_material = material(0, float3(0.7, 0.3, 0.3), 1, 0);
    auto blue_lambertian_material = material(0, float3(0.1, 0.2, 0.5), 1, 0);
    // auto gray_metal_material = material(1, float3(0.8, 0.8, 0.8), 0.3, 0);
    // auto brown_metal_material = material(1, float3(0.8, 0.6, 0.2), 0.01, 0);
    auto gold_metal_material = material(1, float3(1.0, 0.7, 0.3), 0.02, 0);
    auto glass_material = material(2, float3(1.0, 1.0, 1.0), 0, 1.5);

    sphere items[] = {
        sphere(float3(0, -100.5, -1), 100, &yellow_lambertian_material),
        sphere(float3(0, 0, -1), 0.49, &blue_lambertian_material),
        sphere(float3(-1, 0, -1), 0.49, &glass_material),
        sphere(float3(-1, 0, -1), -0.45, &glass_material),
        sphere(float3(+1, 0, -1), 0.49, &gold_metal_material),
    };
    auto world = hittable_list(5, items);

    
    auto uv_offset = rng.next_float2(-0.5, +0.5) / dimensions;
    ray r = cam.get_ray(uv + uv_offset, rng);
//    ray r = cam.get_ray(uv);
    const auto color = ray_color(r, rng, world);
    const auto current_color = float4(color, 1);
    const auto input_color = accumulator.read(gid);
    const auto total_color = input_color + current_color;
    accumulator.write(total_color, gid);
    
    const auto average_color = total_color.rgb / env->sample_count;
    const auto output_color = clamp(sqrt(average_color), 0, 1);
//    const auto output_color = float3(random_seed);
    output.write(float4(output_color.rgb, 1), gid);
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

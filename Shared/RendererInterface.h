#ifndef RendererInterface_h
#define RendererInterface_h

#include <simd/simd.h>


//struct material_param {
//    int type;
//    vector_float3 albedo;
//    float roughness;
//    float index_of_refraction;
//};


//struct sphere_param {
//    vector_float3 center;
//    float radius;
//    material_param m;
//};


//struct list_param {
//    array<sphere_param, uint> items;
//};


struct render_parameters {
    uint noise_buffer_size;
    uint noise_offset;
    float sample_count;
};


#endif /* RendererInterface_h */

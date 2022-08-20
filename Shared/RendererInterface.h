#ifndef RendererInterface_h
#define RendererInterface_h

#include <simd/simd.h>


typedef struct MaterialParam {
    char type;
    simd_float3 albedo;
    float roughness;
    float indexOfRefraction;
} MaterialParam;


typedef struct SphereParam {
    simd_float3 center;
    float radius;
    MaterialParam material;
} SphereParam;


#endif /* RendererInterface_h */

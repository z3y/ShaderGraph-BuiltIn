#ifndef COMMON_FUNCTIONS_INCLUDED
#define COMMON_FUNCTIONS_INCLUDED

// Partially taken from Google Filament, Xiexe, Catlike Coding and Unity
// https://google.github.io/filament/Filament.html
// https://github.com/Xiexe/Unity-Lit-Shader-Templates
// https://catlikecoding.com/

#define GRAYSCALE float3(0.2125, 0.7154, 0.0721)

#include "SurfaceData.cginc"
SamplerState custom_bilinear_clamp_sampler;

#include "EnvironmentBRDF.cginc"

float pow5(float x)
{
    float x2 = x * x;
    return x2 * x2 * x;
}

float sq(float x)
{
    return x * x;
}

half3 F_Schlick(half u, half3 f0)
{
    return f0 + (1.0 - f0) * pow(1.0 - u, 5.0);
}

float F_Schlick2(float f0, float f90, float VoH)
{
    return f0 + (f90 - f0) * pow5(1.0 - VoH);
}

half Fd_Burley(half roughness, half NoV, half NoL, half LoH)
{
    // Burley 2012, "Physically-Based Shading at Disney"
    half f90 = 0.5 + 2.0 * roughness * LoH * LoH;
    float lightScatter = F_Schlick2(1.0, f90, NoL);
    float viewScatter  = F_Schlick2(1.0, f90, NoV);
    return lightScatter * viewScatter;
}

#include "BicubicSampling.cginc"

float3 getBoxProjection (float3 direction, float3 position, float4 cubemapPosition, float3 boxMin, float3 boxMax)
{
    #if defined(UNITY_SPECCUBE_BOX_PROJECTION) || defined(FORCE_SPECCUBE_BOX_PROJECTION)
        UNITY_FLATTEN
        if (cubemapPosition.w > 0.0)
        {
            float3 factors = ((direction > 0.0 ? boxMax : boxMin) - position) / direction;
            float scalar = min(min(factors.x, factors.y), factors.z);
            direction = direction * scalar + (position - cubemapPosition.xyz);
        }
    #endif

    return direction;
}

half computeSpecularAO(half NoV, half ao, half roughness)
{
    return clamp(pow(NoV + ao, exp2(-16.0 * roughness - 1.0)) - 1.0 + ao, 0.0, 1.0);
}

half D_GGX(half NoH, half roughness)
{
    half a = NoH * roughness;
    half k = roughness / (1.0 - NoH * NoH + a * a);
    return k * k * (1.0 / UNITY_PI);
}

float V_SmithGGXCorrelatedFast(half NoV, half NoL, half roughness) {
    half a = roughness;
    float GGXV = NoL * (NoV * (1.0 - a) + a);
    float GGXL = NoV * (NoL * (1.0 - a) + a);
    return 0.5 / (GGXV + GGXL);
}

float V_SmithGGXCorrelated(half NoV, half NoL, half roughness)
{
    #ifdef SHADER_API_MOBILE
    return V_SmithGGXCorrelatedFast(NoV, NoL, roughness);
    #else
    half a2 = roughness * roughness;
    float GGXV = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
    float GGXL = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
    return 0.5 / (GGXV + GGXL);
    #endif
}

half V_Kelemen(half LoH)
{
    // Kelemen 2001, "A Microfacet Based Coupled Specular-Matte BRDF Model with Importance Sampling"
    return saturate(0.25 / (LoH * LoH));
}

float shEvaluateDiffuseL1Geomerics(float L0, float3 L1, float3 n)
{
    // average energy
    float R0 = L0;
    
    // avg direction of incoming light
    float3 R1 = 0.5f * L1;
    
    // directional brightness
    float lenR1 = length(R1);
    
    // linear angle between normal and direction 0-1
    //float q = 0.5f * (1.0f + dot(R1 / lenR1, n));
    //float q = dot(R1 / lenR1, n) * 0.5 + 0.5;
    float q = dot(normalize(R1), n) * 0.5 + 0.5;
    q = saturate(q); // Thanks to ScruffyRuffles for the bug identity.
    
    // power for q
    // lerps from 1 (linear) to 3 (cubic) based on directionality
    float p = 1.0f + 2.0f * lenR1 / R0;
    
    // dynamic range constant
    // should vary between 4 (highly directional) and 0 (ambient)
    float a = (1.0f - lenR1 / R0) / (1.0f + lenR1 / R0);
    
    return R0 * (a + (1.0f - a) * (p + 1.0f) * pow(q, p));
}


#ifdef DYNAMICLIGHTMAP_ON
float3 getRealtimeLightmap(float2 uv, float3 worldNormal)
{   
    half4 bakedCol = SampleBicubic(unity_DynamicLightmap, custom_bilinear_clamp_sampler, uv);
    
    float3 realtimeLightmap = DecodeRealtimeLightmap(bakedCol);

    #ifdef DIRLIGHTMAP_COMBINED
        half4 realtimeDirTex = UNITY_SAMPLE_TEX2D_SAMPLER(unity_DynamicDirectionality, unity_DynamicLightmap, uv);
        realtimeLightmap += DecodeDirectionalLightmap (realtimeLightmap, realtimeDirTex, worldNormal);
    #endif

    return realtimeLightmap;
}
#endif

half3 GetSpecularHighlights(float3 worldNormal, half3 lightColor, float3 lightDirection, half3 f0, float3 viewDir, half clampedRoughness, half NoV, half3 energyCompensation)
{
    float3 halfVector = Unity_SafeNormalize(lightDirection + viewDir);

    half NoH = saturate(dot(worldNormal, halfVector));
    half NoL = saturate(dot(worldNormal, lightDirection));
    half LoH = saturate(dot(lightDirection, halfVector));

    half3 F = F_Schlick(LoH, f0);
    half D = D_GGX(NoH, clampedRoughness);
    half V = V_SmithGGXCorrelatedFast(NoV, NoL, clampedRoughness);

    #ifndef SHADER_API_MOBILE
    F *= energyCompensation;
    #endif

    return max(0, (D * V) * F) * lightColor * NoL;
}

float Unity_Dither(float In, float2 ScreenPosition)
{
    float2 uv = ScreenPosition * _ScreenParams.xy;
    const half4 DITHER_THRESHOLDS[4] =
    {
        half4(1.0 / 17.0,  9.0 / 17.0,  3.0 / 17.0, 11.0 / 17.0),
        half4(13.0 / 17.0,  5.0 / 17.0, 15.0 / 17.0,  7.0 / 17.0),
        half4(4.0 / 17.0, 12.0 / 17.0,  2.0 / 17.0, 10.0 / 17.0),
        half4(16.0 / 17.0,  8.0 / 17.0, 14.0 / 17.0,  6.0 / 17.0)
    };

    return In - DITHER_THRESHOLDS[uint(uv.x) % 4][uint(uv.y) % 4];
}

void AACutout(inout half alpha, half cutoff)
{
    alpha = (alpha - cutoff) / max(fwidth(alpha), 0.0001) + 0.5;
}

half NormalDotViewDir(float3 normalWS, float3 viewDir)
{
    return abs(dot(normalWS, viewDir)) + 1e-5f;
}

half3 GetF0(half reflectance, half metallic, half3 albedo)
{
    return 0.16 * reflectance * reflectance * (1.0 - metallic) + albedo * metallic;
}

struct LightDataCustom
{
    half3 Color;
    float3 Direction;
    half NoL;
    half LoH;
    half NoH;
    float3 HalfVector;
    half3 FinalColor;
    half3 Specular;
    half Attenuation;
};

half3 MainLightSpecular(LightDataCustom lightData, half NoV, half clampedRoughness, half3 f0)
{
    half3 F = F_Schlick(lightData.LoH, f0) * DFGEnergyCompensation;
    half D = D_GGX(lightData.NoH, clampedRoughness);
    half V = V_SmithGGXCorrelated(NoV, lightData.NoL, clampedRoughness);

    return max(0.0, (D * V) * F) * lightData.FinalColor;
}

void InitializeLightData(inout LightDataCustom lightData, float3 normalWS, float3 viewDir, half NoV, half clampedRoughness, half perceptualRoughness, half3 f0, v2f_surf input)
{
    #ifdef USING_LIGHT_MULTI_COMPILE
        lightData.Direction = normalize(UnityWorldSpaceLightDir(input.worldPos));
        lightData.HalfVector = Unity_SafeNormalize(lightData.Direction + viewDir);
        lightData.NoL = saturate(dot(normalWS, lightData.Direction));
        lightData.LoH = saturate(dot(lightData.Direction, lightData.HalfVector));
        lightData.NoH = saturate(dot(normalWS, lightData.HalfVector));
        
        UNITY_LIGHT_ATTENUATION(lightAttenuation, input, input.worldPos.xyz);
        lightData.Attenuation = lightAttenuation;
        lightData.Color = lightAttenuation * _LightColor0.rgb;
        lightData.FinalColor = (lightData.NoL * lightData.Color);


        #ifndef SHADER_API_MOBILE
            lightData.FinalColor *= Fd_Burley(perceptualRoughness, NoV, lightData.NoL, lightData.LoH);
        #endif

        #if defined(LIGHTMAP_SHADOW_MIXING) && defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN) && defined(LIGHTMAP_ON)
            lightData.FinalColor *= UnityComputeForwardShadows(input.lmap.xy, input.worldPos, input.screenPos);
        #endif

        #ifndef _SPECULARHIGHLIGHTS_OFF
        lightData.Specular = MainLightSpecular(lightData, NoV, clampedRoughness, f0);
        #else
        lightData.Specular = 0.0;
        #endif
    #else
        lightData = (LightDataCustom)0;
    #endif
}

half3 GetReflections(float3 normalWS, float3 positionWS, float3 viewDir, half3 f0, half roughness, half NoV, SurfaceDataCustom surf, half3 indirectDiffuse)
{
    half3 indirectSpecular = 0;
    #if defined(UNITY_PASS_FORWARDBASE)

        float3 reflDir = reflect(-viewDir, normalWS);
        #ifndef SHADER_API_MOBILE
        reflDir = lerp(reflDir, normalWS, roughness * roughness);
        #endif

        Unity_GlossyEnvironmentData envData;
        envData.roughness = surf.perceptualRoughness;
        envData.reflUVW = getBoxProjection(reflDir, positionWS, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin.xyz, unity_SpecCube0_BoxMax.xyz);

        half3 probe0 = Unity_GlossyEnvironment(UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData);
        indirectSpecular = probe0;

        #if defined(UNITY_SPECCUBE_BLENDING) && !defined(SHADER_API_MOBILE)
            UNITY_BRANCH
            if (unity_SpecCube0_BoxMin.w < 0.99999)
            {
                envData.reflUVW = getBoxProjection(reflDir, positionWS, unity_SpecCube1_ProbePosition, unity_SpecCube1_BoxMin.xyz, unity_SpecCube1_BoxMax.xyz);
                float3 probe1 = Unity_GlossyEnvironment(UNITY_PASS_TEXCUBE_SAMPLER(unity_SpecCube1, unity_SpecCube0), unity_SpecCube1_HDR, envData);
                indirectSpecular = lerp(probe1, probe0, unity_SpecCube0_BoxMin.w);
            }
        #endif

        float horizon = min(1.0 + dot(reflDir, normalWS), 1.0);
        
        // half lightmapOcclusion = lerp(1.0, saturate(dot(indirectDiffuse, 1.0)), _SpecularOcclusion);

        // #ifdef LIGHTMAP_ANY
        //     surf.occlusion *= lightmapOcclusion;
        // #endif

        #ifdef SHADER_API_MOBILE
            indirectSpecular = indirectSpecular * horizon * horizon * EnvBRDFApprox(surf.perceptualRoughness, NoV, f0);
        #else
            indirectSpecular = indirectSpecular * horizon * horizon * DFGEnergyCompensation * EnvBRDFMultiscatter(DFGLut, f0);
        #endif

        indirectSpecular *= computeSpecularAO(NoV, surf.occlusion, surf.perceptualRoughness * surf.perceptualRoughness);

    #endif

    return indirectSpecular;
}

half3 GetLightProbes(float3 normalWS, float3 positionWS)
{
    half3 indirectDiffuse = 0;
    #ifndef LIGHTMAP_ANY
        #if UNITY_LIGHT_PROBE_PROXY_VOLUME
            UNITY_BRANCH
            if (unity_ProbeVolumeParams.x == 1.0)
            {
                indirectDiffuse = SHEvalLinearL0L1_SampleProbeVolume(float4(normalWS, 1.0), positionWS);
            }
            else
            {
        #endif
                #ifdef BAKERY_PROBESHNONLINEAR
                    float3 L0 = float3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w);
                    indirectDiffuse.r = shEvaluateDiffuseL1Geomerics(L0.r, unity_SHAr.xyz, normalWS);
                    indirectDiffuse.g = shEvaluateDiffuseL1Geomerics(L0.g, unity_SHAg.xyz, normalWS);
                    indirectDiffuse.b = shEvaluateDiffuseL1Geomerics(L0.b, unity_SHAb.xyz, normalWS);
                #else
                indirectDiffuse = ShadeSH9(float4(normalWS, 1.0));
                #endif
        #if UNITY_LIGHT_PROBE_PROXY_VOLUME
            }
        #endif
    #endif
    return indirectDiffuse;
}


#include "Bakery.cginc"


#endif
// -------------------------------------------------------------------
// LitShader.shaderの入力パラメータの整形
// LitForwardPass.hlslへ入力情報を受け渡すファイル
// -------------------------------------------------------------------

#ifndef MY_LIT_INPUT_INCLUDED
#define MY_LIT_INPUT_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Assets/ShaderLibrary/MySurfaceData.hlsl"
#include "Assets/ShaderLibrary/LightingInputData.hlsl"

TEXTURE2D(_BaseMap);
SAMPLER(sampler_BaseMap);

TEXTURE2D(_NormalMap);
SAMPLER(sampler_NormalMap);

TEXTURE2D(_SpecularMap);
SAMPLER(sampler_SpecularMap);

TEXTURE2D(_MetallicMap);
SAMPLER(sampler_MetallicMap);

TEXTURE2D(_AoMap);
SAMPLER(sampler_AoMap);

CBUFFER_START(UnityPerMaterial)
    // 画像
    half4 _BaseColor;
    float4 _BaseMap_ST;

    // パラメーター
    float _SpecPower;
    float _AmbientPower;

    float _SpecThreshold;        // 鏡面反射の鋭さ
    float _LimLightThreshold;    // リムライトの鋭さ
    float _HemiLightThreshold;   // 半球ライトの強さ

    float _Smoothness;          // 滑らかさ
CBUFFER_END

/// タンジェントスペースにおける法線ベクトルを取得
/// uv: UV座標
float3 GetNormalTsToWorld(float2 uv)
{
    float3 normalTS = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv)); //[0,0] -> [-1,1]に変換
    return normalTS;
}

/// スペキュラーマップの取得関数
half GetSpecularPower(float2 uv)
{
    half specPower = SAMPLE_TEXTURE2D(_SpecularMap, sampler_SpecularMap, uv).r;
    specPower *= _SpecPower;
    return specPower;
}

/// メタリックマップの取得関数
half GetMetallicPower(float2 uv)
{
    half metallic = SAMPLE_TEXTURE2D(_MetallicMap, sampler_MetallicMap, uv).r;
    return metallic;
}

/// アンビエントオクルージョンマップの取得関数
float GetAmbientOcclusion(float2 uv)
{
    half occlusion = SAMPLE_TEXTURE2D(_AoMap, sampler_AoMap, uv).r;
    occlusion *= _AmbientPower;
    return occlusion;
}

/// アルベトカラー取得関数
half4 GetAlbedoColor(float2 uv)
{
    return SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv) * _BaseColor;
}

/// SurfaceData初期化関数
inline void InitializeStandardLitSurfaceData(float2 uv, out MySurfaceData surfaceData, out LightingInputData lightingInputData)
{
    // テクスチャー情報
    surfaceData.albedo = GetAlbedoColor(uv).rgb;
    surfaceData.specular = GetSpecularPower(uv) * _SpecThreshold;
    surfaceData.metallic = GetMetallicPower(uv);
    surfaceData.normalTS = GetNormalTsToWorld(uv);
    surfaceData.occlusion = GetAmbientOcclusion(uv); // 間接光で影響を与える
    surfaceData.alpha = GetAlbedoColor(uv).a;
    surfaceData.smoothness = _Smoothness;

    // light threshold
    lightingInputData.specularThreshold = _SpecThreshold;        // 鏡面反射の鋭さ
    lightingInputData.limLightThreshold = _LimLightThreshold;    // リムライトの鋭さ
    lightingInputData.hemiLightThreshold = _HemiLightThreshold;   // 半球ライトの強さ
}

#endif
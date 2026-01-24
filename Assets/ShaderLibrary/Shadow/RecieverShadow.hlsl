// シャドウマップを参照して影を付ける

// このファイルを使用する場合は Shader 内で以下を include してください:
// #include "Assets/ShaderLibrary/Shadow/RecieverShadow.hlsl"

#ifndef RECIEVER_SHADOW_INCLUDED_2
#define RECIEVER_SHADOW_INCLUDED_2

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

TEXTURE2D(_ShadowTexture);
float4x4 _lightVP;

/// <summary>
/// 影の影響があるかどうかを返す
/// </summary>
half ShadowValue(float3 positionWS) : SV_Target
{
    float4 posInLVP = mul(_lightVP, float4(positionWS, 1));

    // ----------------------------------------
    // 1. ライト空間 → NDC
    // ----------------------------------------
    float2 ndc = posInLVP.xy / posInLVP.w; // [-1-1]

    // ----------------------------------------
    // 2. NDC → UV
    // ----------------------------------------
    float2 shadowUV = ndc.xy * float2(0.5f, -0.5f) + 0.5f; // [0-1]

    // ----------------------------------------
    // 3. 範囲内であれば影
    // ----------------------------------------

    // ライト空間のz値
    // 手前から0.0f - 1.0f
    float zInLVP = posInLVP.z / posInLVP.w;

    if (shadowUV.x > 0.0f && shadowUV.x < 1.0f &&
        shadowUV.y > 0.0f && shadowUV.y < 1.0f)
    {
        // シャドウマップのZ値と比較
        // 手前から0.0f-1.0f
        float zShadowMap = SAMPLE_TEXTURE2D(_ShadowTexture, sampler_PointClamp, shadowUV).r;

        // 障害物が手前に存在する
        if (1 - zInLVP > 1 - zShadowMap)
        {
            return 0.3f;
        }
    }

    return 1.0f;
}

#endif
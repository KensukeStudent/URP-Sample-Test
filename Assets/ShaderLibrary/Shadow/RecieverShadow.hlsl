// シャドウマップを参照して影を付ける

// このファイルを使用する場合は Shader 内で以下を include してください:
// #include "Assets/ShaderLibrary/Shadow/RecieverShadow.hlsl"

#ifndef RECIEVER_SHADOW_INCLUDED
#define RECIEVER_SHADOW_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
};

struct Varyings
{
    float4 positionHCS : SV_POSITION;
    float4 posInLVP : TEXCOORD; // ライト方向から見た座標
};

TEXTURE2D(_ShadowTexture);

CBUFFER_START(UnityPerMaterial)
    float4x4 _lightVP;
CBUFFER_END

Varyings vert(Attributes IN)
{
    Varyings OUT;

    // メインカメラからの座標に描画
    OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);

    // ライト方向から見た座標を取得
    float3 world = TransformObjectToWorld(IN.positionOS.xyz);
    OUT.posInLVP = mul(_lightVP, float4(world, 1));

    return OUT;
}

half4 frag(Varyings IN) : SV_Target
{
    // ===== 1. ライト空間 → NDC =====
    float2 ndc = IN.posInLVP.xy / IN.posInLVP.w; // [-1-1]

    // ===== 2. NDC → UV =====
    float2 shadowUV = ndc.xy * float2(0.5f, -0.5f) + 0.5f; // [0-1]

    // ライト空間のz値
    float zInLVP = IN.posInLVP.z / IN.posInLVP.w;

    // ===== 3. 範囲内であれば影 =====
    if (shadowUV.x > 0.0f && shadowUV.x < 1.0f &&
        shadowUV.y > 0.0f && shadowUV.y < 1.0f)
    {
        // シャドウマップのZ値と比較
        float zShadowMap = SAMPLE_TEXTURE2D(_ShadowTexture, sampler_PointClamp, shadowUV).r;
        
        // 障害物が手前に存在する
        if (zInLVP > zShadowMap)
        {
            return half4(0.3f, 0.3f, 0.3f, 1.0f);
        }
    }

    return half4(1,1,1,1);
    // return SAMPLE_TEXTURE2D(_ShadowTexture, sampler_PointClamp, shadowUV);
}

#endif
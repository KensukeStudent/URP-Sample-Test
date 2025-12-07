Shader "Custom/SimpleLambert2"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1,1,1,1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float4 shadowCoord : TEXCOORD3; // <- 追加
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);

                // ワールド位置 -> シャドウ座標（shadow map 用）
                OUT.shadowCoord = TransformWorldToShadowCoord(OUT.positionWS); // <- ここで計算
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                float3 normalWS = normalize(IN.normalWS);

                // ----- Direct light -----
                // 方法A (推奨・簡単): GetMainLight に shadowCoord を渡すと shadowAttenuation がセットされる
                Light mainLightWithShadow = GetMainLight(IN.shadowCoord);
                float3 lightDir = normalize(mainLightWithShadow.direction);
                float NdotL = saturate(dot(normalWS, lightDir));
                float3 mainShadowWithColor = NdotL * mainLightWithShadow.color.rgb;
                float3 diffuseDirect = mainShadowWithColor * mainLightWithShadow.shadowAttenuation;

                // ----- 方法B (自前でサンプリング) -----
                // ShadowSamplingData shadowSamplingData = GetMainLightShadowSamplingData();
                // half4 shadowParams = GetMainLightShadowParams();
                // half shadowAtten = MainLightRealtimeShadow(IN.shadowCoord, shadowParams, shadowSamplingData);
                // → 取得した shadowAtten を使って diffuse を乗算する（上の方法Aと同等）

                // ----- Indirect (SH) -----
                float3 sh = SampleSH(normalWS);
                float3 diffuseIndirect = sh;

                float3 lighting = diffuseDirect + diffuseIndirect;
                float3 finalColor = lighting * albedo.rgb;

                return half4(finalColor, albedo.a);
            }

            ENDHLSL
        }
    }
}

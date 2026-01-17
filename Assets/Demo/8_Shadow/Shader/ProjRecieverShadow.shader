Shader "Custom/ProjRecieverShadow"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        // Pass
        // {
        //     Name "Forward"
        //     Tags { "LightMode"="UniversalForward" }

        //     ZWrite On
        //     ColorMask 0

        //     HLSLPROGRAM

        //     #pragma vertex vert
        //     #pragma fragment frag

        //     #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        //     struct Attributes
        //     {
        //         float4 positionOS : POSITION;
        //     };

        //     struct Varyings
        //     {
        //         float4 positionHCS : SV_POSITION;
        //     };

        //     CBUFFER_START(UnityPerMaterial)
        //         half4 _BaseColor;
        //     CBUFFER_END

        //     Varyings vert(Attributes IN)
        //     {
        //         Varyings OUT;
        //         OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
        //         return OUT;
        //     }

        //     half4 frag(Varyings IN) : SV_Target
        //     {
        //         return _BaseColor;
        //     }
        //     ENDHLSL
        // }

        Pass
        {
            Name "RecieverShadow"
            Tags { "LightMode" = "RecieverShadow" }

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD;

                float4 posInLVP : TEXCOORD1;
            };

            TEXTURE2D(_ShadowTexture);

            CBUFFER_START(UnityPerMaterial)
                float4x4 _lightVP;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = IN.uv;

                float3 world = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.posInLVP = mul(_lightVP, float4(world, 1));

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float4 color = float4(1,1,1,1);

                // step-6 ライトビュースクリーン空間[-1~1]からUV空間[0~1]に座標変換
                float2 shadowMapUV = IN.posInLVP.xy / IN.posInLVP.w;
                shadowMapUV *= float2(0.5f, -0.5f); // [-0.5 ~ 0.5], yは[1~-1] ->[0~1]へ変換したいので-0.5
                shadowMapUV += 0.5f; // [0~1]

                // step-7 UV座標を使ってシャドウマップから影情報をサンプリング
                float3 shadowMap = 1.0f;
                if (shadowMapUV.x > 0.0f && shadowMapUV.x < 1.0f 
                    && shadowMapUV.y > 0.0f && shadowMapUV.y < 1.0f)
                {
                    shadowMap = SAMPLE_TEXTURE2D(_ShadowTexture, sampler_PointClamp, shadowMapUV).r;
                }

                // step-8 サンプリングした影情報をテクスチャカラーに乗算する
                color.xyz *= shadowMap;
                return color;
            }
            ENDHLSL
        }
    }
}

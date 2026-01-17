Shader "Custom/ProjShadow"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                // OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                return _BaseColor;
            }
            ENDHLSL
        }

        Pass
        {
            Name "MyShadowPass"
            Tags { "LightMode"="ProjShadow" } // 何でもいい

            ZWrite On
            ColorMask RGBA

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
            float4x4 _lightVP;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                // world行列に変換 -> view行列に変換 -> proj行列に変換
                // world行列は共通のものを使用する
                float3 world = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionHCS = mul(_lightVP, float4(world, 1.0));
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // return IN.positionHCS.z / IN.positionHCS.w;
                return half4(1, 0, 0, 1.0f);
            }
            ENDHLSL
        }
    }
}

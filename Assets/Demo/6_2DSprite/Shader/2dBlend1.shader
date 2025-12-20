Shader "Custom/2dBlend1"
{
    Properties
    {
        [MainColor] _Color ("Color", Color) = (1,1,1,1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
    }

    SubShader
    {
        Tags 
        { 
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            // 覚えておくとよい
            // Blend SrcAlpha OneMinusSrcAlpha / src(RGB) * src(α) + Dest(RGB) * (1- src(α)): αに基づき重みが変わる                             , 普通に透けさせたいとき
            // Blend One OneMinusSrcAlpha // src(RBG) * 1 + Dest(RGB) * (1 - src(α))        : αに基づきDestの重みが変わる、値が大きいと白に近づく , 縁をきれいにしたい
            // Blend One One // src(RGB) * 1 + Dest(RGB) * 1                                : 値が大きいほど白に近づく                          , 光らせたい(エフェクトやビーム)
            // Blend DestColor Zero // src(RGB) * Dest(RGB) + Dest(RGB) * 0                 : 白ならsrcの色、Destが黒なら黒                     , 暗くしたい

            // 特に不要なブレンドらしい
            // Blend OneMinusDstColor One // src(RGB) * (1 - Dest(RGB)) + Dest(RGB) * 1     : 背景への依存度が高い、暗いとsrcの色が目立つ
            // Blend DestColor SrcColor // src(RGB) * Dest(RGB) + Dest(RGB) * src(RGB)       : あまり実用性はなさそう

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

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _Color;
                float4 _BaseMap_ST;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _Color;
                return color;
            }
            ENDHLSL
        }
    }
}

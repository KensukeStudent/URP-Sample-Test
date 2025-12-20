Shader "Custom/LinnerWipe1"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        _DiscardUV("discard uv", Range(0,1)) = 0.0
        _DirectionX("direction x", Range(-1, 1)) = 0
        _DirectionY("direction y", Range(-1, 1)) = 0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
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
                half4 _BaseColor;
                float4 _BaseMap_ST;
                
                float _DiscardUV;
                float _DirectionX;
                float _DirectionY;
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
                float2 dir = float2(_DirectionX, _DirectionY);

                // 0ベクトル対策
                dir = normalize(dir + 1e-5);

                // UV を中心基準に -0.5~0.5 direcitonマイナス対応
                float2 uv = IN.uv - 0.5;

                // 射影
                float wipeValue = dot(uv, dir);

                // ★ 射影最大値（これが重要）
                float maxProj =
                    abs(dir.x) * 0.5 +
                    abs(dir.y) * 0.5;

                // -max ～ +max → 0 ～ 1
                wipeValue = wipeValue / (maxProj * 2.0) + 0.5;

                // ワイプ
                clip(wipeValue - _DiscardUV);

                half4 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                return color;
            }

            ENDHLSL
        }
    }
}

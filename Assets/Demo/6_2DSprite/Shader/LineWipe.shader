Shader "Custom/LineWipe"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}

        _WipeSize("Wipe Size", Range(0.0, 1.0)) = 0.0
        _PixelWidth("Pixel Width", Range(0.0, 1.0)) = 0.0
        _PixelKill("Pixel Kill", Range(0.0, 1.0)) = 0.0
        _WipeDirX("Wipe DirX", Range(-1.0, 1.0)) = 0.0
        _WipeDirY("Wipe DirY", Range(-1.0, 1.0)) = 0.0
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

                float _WipeSize;
                float _PixelWidth;
                float _PixelKill;
                float _WipeDirX;
                float _WipeDirY;
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
                // --------------------------------------------------
                // 縦じまマスク
                // --------------------------------------------------
                float stripe = fmod(IN.uv.x, _PixelKill);
                float width = 1 - _PixelWidth;
                clip(stripe - width * _PixelKill);

                // --------------------------------------------------
                // ワイプ方向
                // --------------------------------------------------
                float2 dir = normalize(float2(_WipeDirX, _WipeDirY));

                float2 uv = IN.uv - 0.5;

                // 射影値 [-range, +range]
                float wipeValue = dot(dir, uv);

                // 射影最大距離
                float wipeRange = abs(dir.x) + abs(dir.y);

                // [0, 1] に正規化
                wipeValue = wipeValue / wipeRange + 0.5;

                clip(_WipeSize - wipeValue);

                return SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
            }

            ENDHLSL
        }
    }
}

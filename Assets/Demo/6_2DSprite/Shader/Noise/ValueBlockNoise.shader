Shader "Custom/ValueBlockNoise"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}

        _ChangeRate("Change Rate", Range(0.0, 100.0)) = 1.0 // 1秒間の更新回数
        _Smoothness("Smoothness", Range(0.0, 1000)) = 1000 // ノイズの滑らかさ
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

                float _ChangeRate;
                float _Smoothness;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            float hash(float2 p)
            {
                p = frac(p * 0.3183099 + 0.1);
                p *= 17.0;
                return frac(p.x * p.y * (p.x + p.y));
            }

            float valueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);

                // 4つの隅のハッシュ値を取得
                float v00 = hash(i);
                float v10 = hash(i + float2(1.0, 0.0));
                float v01 = hash(i + float2(0.0, 1.0));
                float v11 = hash(i + float2(1.0, 1.0));

                // 補間
                float2 u = f * f * (3.0 - 2.0 * f);
                return lerp(lerp(v00, v10, u.x), lerp(v01, v11, u.x), u.y);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // 時間を段階化（例：1秒ごと）
                float t = floor(_Time.y * _ChangeRate);

                float noise = valueNoise(IN.uv * 8 + t / _Smoothness);

                return half4(noise, noise, noise, 1);
            }
            ENDHLSL
        }
    }
}

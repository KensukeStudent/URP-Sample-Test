Shader "Custom/URP/SimplexNoiseUV"
{
    Properties
    {
        _BaseMap ("Texture", 2D) = "white" {}
        _NoiseScale ("Noise Scale", Range(0.0,0.5)) = 0.1
        _NoiseFrequency ("Noise Frequency", Range(1.0, 10.0)) = 1.0

        _DistortDir ("Distort Direction (XY)", Vector) = (1, 0, 0, 0)
        _DistortStrength ("Distort Strength", Float) = 0.1

    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Opaque"
        }

        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // -------------------------
            // テクスチャ定義（URP式）
            // -------------------------
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            float4 _BaseMap_ST;

            float _NoiseScale;
            float _NoiseFrequency;

            float2 _DistortDir;
            float _DistortStrength;


            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 worldPos    : TEXCOORD1;
            };

            // -------------------------
            // ハッシュ関数（DX版そのまま）
            // -------------------------
            float hash(float n)
            {
                return frac(sin(n) * 43758.5453);
            }

            // -------------------------
            // Simplex Noise（Value Noise）
            // -------------------------
            float SimplexNoise(float3 x)
            {
                float3 p = floor(x);
                float3 f = frac(x);

                f = f * f * (3.0 - 2.0 * f);
                float n = p.x + p.y * 57.0 + 113.0 * p.z;

                return lerp(
                    lerp(
                        lerp(hash(n + 0.0),   hash(n + 1.0),   f.x),
                        lerp(hash(n + 57.0),  hash(n + 58.0),  f.x),
                        f.y
                    ),
                    lerp(
                        lerp(hash(n + 113.0), hash(n + 114.0), f.x),
                        lerp(hash(n + 170.0), hash(n + 171.0), f.x),
                        f.y
                    ),
                    f.z
                );
            }

            Varyings vert (Attributes IN)
            {
                Varyings OUT;

                // Object → Clip
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);

                // UV
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);

                // World Position（ノイズ用）
                OUT.worldPos = TransformObjectToWorld(IN.positionOS.xyz);

                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                // 下方向（UVは下が0、上が1なのでマイナスY）
                float2 dir = float2(0, -1);

                // ノイズ
                float n = SimplexNoise(
                    float3(IN.uv * _NoiseFrequency, _Time.y)
                );
                n = (n - 0.5) * 2.0;

                // 上0 → 下1 になるマスク
                float mask = saturate(1.0 - IN.uv.y);

                // 強めにしたいなら二乗
                mask = mask * mask;

                // 歪み
                float2 uv = IN.uv + dir * n * mask * _DistortStrength;

                // テクスチャサンプリング
                half4 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv);
                return color;
            }
            ENDHLSL
        }
    }
}

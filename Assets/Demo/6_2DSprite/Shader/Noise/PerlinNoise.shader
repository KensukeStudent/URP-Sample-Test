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

            // 0〜1の乱数を 2D 勾配ベクトルに変換
            float2 hash2(float2 p)
            {
                // 既存のhash関数を利用して0〜1の乱数を生成
                float n = hash(p);

                // 角度へ変換
                float angle = n * 6.2831853; // 2π
                return float2(cos(angle), sin(angle));
            }

            // 格子点に設定されたランダムなベクトルと、ブロック内部の点から格子点に向かうベクトルの内積から補完することで
            // ブロック感を減らしたノイズを生成
            float perlinNoise(float2 p)
            {
                // グリッドセルの整数座標を取得
                float2 i = floor(p);
                float2 f = frac(p);

                // 4つのコーナーの勾配ベクトルを取得
                float2 v00 = hash2(i + float2(0.0, 0.0));
                float2 v10 = hash2(i + float2(1.0, 0.0));
                float2 v01 = hash2(i + float2(0.0, 1.0));
                float2 v11 = hash2(i + float2(1.0, 1.0));

                // 各コーナーからの距離ベクトル
                float2 d00 = f - float2(0.0, 0.0);
                float2 d10 = f - float2(1.0, 0.0);
                float2 d01 = f - float2(0.0, 1.0);
                float2 d11 = f - float2(1.0, 1.0);

                // ドット積を計算
                float n00 = dot(v00, d00);
                float n10 = dot(v10, d10);
                float n01 = dot(v01, d01);
                float n11 = dot(v11, d11);

                // // 補間関数 perlin改良版の補完
                // float2 u = f * f * f * (f * (f * 6 - 15) + 10);

                // フェード関数（バリューノイズと同じ）
                float2 u = f * f * (3.0 - 2.0 * f);

                // 補間
                float nx0 = lerp(n00, n10, u.x);
                float nx1 = lerp(n01, n11, u.x);
                return lerp(nx0, nx1, u.y);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // 時間を段階化（例：1秒ごと）
                float t = floor(_Time.y * _ChangeRate);

                // In.uv * N : ノイズの解像度 8x8のブロック
                // 内積の結果を補完するので-1~1 の範囲のノイズを生成される
                float noise = perlinNoise(IN.uv * 8 + t / _Smoothness);

                // ノイズの値を0〜1に正規化
                noise = noise * 0.5 + 0.5;

                return half4(noise, noise, noise, 1);
            }
            ENDHLSL
        }
    }
}

Shader "Custom/FbmNoise_Sample"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}

        _ChangeRate("Change Rate", Range(0.0, 100.0)) = 1.0 // 1秒間の更新回数
        _Smoothness("Smoothness", Range(0.0, 1000)) = 1000 // ノイズの滑らかさ

        _FbmScale("FBM Scale", Range(0.0, 1.0)) = 0.0
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
                float _FbmScale;
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

            // p: uv座標
            // timer: 時間変数
            // octaves: オクターブ数
            float fbmNoise(float2 p, float timer, int octaves)
            {
                float fbm = 0.0;

                float amplitude = 0.5;   // 振幅（最初は大きめ）
                float frequency = 8.0;   // 周波数（基本解像度）

                float amplitudeSum = 0.0; // 振幅の合計（正規化用）

                for (int i = 0; i < octaves; i++)
                {
                    // Perlinは -1〜1
                    float noise = perlinNoise(p * frequency + timer);

                    fbm += noise * amplitude;

                    amplitudeSum += amplitude;

                    amplitude *= 0.5;    // 弱くする
                    frequency *= 2.0;    // 細かくする
                }

                // -1〜1 → 0〜1になるかシュミレート
                // amplitudeSum = 1.0 + 0.5 + 0.25 + 0.125 = 1.875
                // fbm = -1 * 1.875
                // -1.875/1.875 = -1
                // -1 * 0.5 + 0.5 = 0
                fbm /= amplitudeSum;
                return fbm; // [-1, 1]の範囲内なので色としては使えないため変換が必要[0, 1]など
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float t = floor(_Time.y * _ChangeRate);
                float timer = t / _Smoothness;

                float fbm = fbmNoise(IN.uv, timer, 3); // [-1,1]
                float2 uv = IN.uv + fbm * _FbmScale; // fbmの範囲が[-1,1]だが、うまいことuv[0,1]に収まっていそう

                half4 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv) * _BaseColor;
                return color;
            }
            ENDHLSL
        }
    }
}

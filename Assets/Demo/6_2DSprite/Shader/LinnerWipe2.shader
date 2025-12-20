Shader "Custom/LinnerWipe2"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}

        _WipeDirX("Wipe DirX", Range(-1, 1)) = 1.0
        _WipeDirY("Wipe DirY", Range(-1, 1)) = 1.0
        _WipeSize("Wipe Size", Range(0.0, 1.0)) = 0.0
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

                float _WipeDirX;
                float _WipeDirY;
                float _WipeSize;
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
                float2 dir = float2(_WipeDirX, _WipeDirY);
                // 「単位ベクトル」と「ベクトルの大きさ・方向を持つベクトル」との内積を求める
                // 片方が単位ベクトルであれば単位ベクトルの無限線分上に垂線を落として射影した長さとなる内積の性質を利用する
                dir = normalize(dir);

                // 比較する原点を中心へdotのマイナスを使い左右判定する
                float2 uv = (IN.uv - 0.5); // [0,1] -> [-0.5, 0.5]

                // 単位ベクトルに対する射影距離(uvがワイプ方向のどれくらいの距離に位置するか)
                // ※ 長さ1の単位ベクトルと大きさと方向を持つベクトルの内積とする
                float wipeValue = dot(uv, dir);

                // 1. normalizeを考慮してxとyの合計値にwipeが収まるようにする
                // 2. uvの範囲が1/2なので1の結果に加えて範囲も合わせる
                float maxRange = abs(dir.x) * 0.5f + abs(dir.y) * 0.5f;

                // wipeValueを方向依存の大きさに収まるように正規化
                maxRange *= 2; // dirを[0.0, 0.5] -> [0, 1]
                wipeValue = wipeValue / maxRange + 0.5; // [-0.5, 0.5] -> [0, 1]

                clip(wipeValue - _WipeSize);

                half4 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                return color;
            }
            ENDHLSL
        }
    }
}

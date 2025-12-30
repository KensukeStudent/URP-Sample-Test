Shader "Custom/Bloom1"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white"
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        // 輝度抽出パス
        Pass
        {
            Name "Luminance"

            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
            CBUFFER_END

            half4 frag(Varyings input) : SV_Target
            {
                float4 color = FragNearest(input);

                // 輝度係数：人間の目の感度（緑が最も明るく感じ、青が最も暗く感じる）を考慮して調整されており、
                // 人間の視覚特性に合った輝度信号を生成します
                // この係数を使用して「明るい/暗い」を判定する
                float3 k = float3(0.2125f, 0.7154f, 0.0721f);

                float t = dot(color.xyz, k);

                // clip()関数は引数の値がマイナスになると、以降の処理をスキップする
                // なので、マイナスになるとピクセルカラーは出力されない
                // 今回の実装はカラーの明るさが1以下ならピクセルキルする
                clip(t - 1.0f);

                return color;
            }
            ENDHLSL
        }
    }
}

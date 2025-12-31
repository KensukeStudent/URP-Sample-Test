Shader "Custom/Bloom1"
{
    Properties
    {
        _Threshold("Threshold", Range(0.0, 1.0)) = 1.0
        _BloomColor("BloomColor", Color) = (1,1,1,1)
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

            CBUFFER_START(UnityPerMaterial)
                float _Threshold;
            CBUFFER_END

            float4 frag(Varyings input) : SV_Target
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
                clip(t - _Threshold);

                return color;
            }
            ENDHLSL
        }

        // 輝度のガウステクスチャー合成パス
        Pass
        {
            Name "Luminance Gauss Combine"

            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BloomColor;
            CBUFFER_END

            TEXTURE2D(_GaussTexture0);
            TEXTURE2D(_GaussTexture1);
            TEXTURE2D(_GaussTexture2);
            TEXTURE2D(_GaussTexture3);

            float4 frag(Varyings input) : SV_Target
            {
                float4 color = SAMPLE_TEXTURE2D(_GaussTexture0, sampler_LinearClamp, input.texcoord);
                color += SAMPLE_TEXTURE2D(_GaussTexture1, sampler_LinearClamp, input.texcoord);
                color += SAMPLE_TEXTURE2D(_GaussTexture2, sampler_LinearClamp, input.texcoord);
                color += SAMPLE_TEXTURE2D(_GaussTexture3, sampler_LinearClamp, input.texcoord);
                color /= 4.0f;
                color.a = 1.0f;

                return FragNearest(input) + color * _BloomColor;
            }
            ENDHLSL
        }
    }
}

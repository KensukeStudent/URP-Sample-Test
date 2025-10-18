// UIに掛けると画面が壊れる
// PostEffect専用

Shader "Custom/NormalEdgeFilter"
{
    Properties
    {
        _EdgeColor("EdgeColor", Color) = (0,0,0,1)
        _SamplingRange("Sampling", Range(0.5, 10)) = 2
        _Sensitivity ("Sensitivity", Range(0.0, 10.0)) = 1.5
        _Threshold ("Threshold", Range(0.0, 1.0)) = 0.5
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "NormalEdge"

            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _EdgeColor;
                float _SamplingRange;
                float _Sensitivity;
                float _Threshold;
            CBUFFER_END

            float4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                // 半テクセルサイズ
                float du = _SamplingRange / _ScreenParams.x;
                float dv = _SamplingRange / _ScreenParams.y;

                // 左上、右下、左下、右上からサンプリング
                float4 lt = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-du, -dv));
                float4 rb = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(du, dv));
                float4 lb = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(-du, dv));
                float4 rt = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv + float2(du, -dv));

                float3 d1 = lt.r - rb.r;
                float3 d2 = lb.r - rt.r;

                float diff = _Sensitivity * sqrt(dot(d1, d1) + dot(d2, d2));
                float edge = saturate(1 - 100 * diff);
                edge = step(_Threshold, edge); // 輪郭黒・他白
                return (1 - edge) * _EdgeColor;
            }
            ENDHLSL
        }

        Pass
        {
            Name "Combine"

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #pragma vertex Vert
            #pragma fragment Frag

            TEXTURE2D(_NormalEdgeTexture);

            float4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                half4 edge = SAMPLE_TEXTURE2D(_NormalEdgeTexture, sampler_LinearClamp, uv);
                half4 camera = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv);

                float depthColor = edge.r + edge.g + edge.b;

                return depthColor > 0 ? edge * camera : camera;
            }
            ENDHLSL
        }
    }
}
Shader "Hidden/Sample/DataTransfer"
{
    SubShader
    {
       Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline"}
       ZTest Always ZWrite Off Cull Off

       Pass     // 色、上下反転のテクスチャ描画
        {
            Name "DrawNegative"

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #pragma vertex Vert
            #pragma fragment Frag

            half4 Frag(Varyings input) : SV_TARGET
            {
                float2 uv = input.texcoord.xy;
                uv.y = 1 - uv.y; // 上下反転
                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);
                half4 negative = half4(1 - color.rgb, color.a); // 色反転
                return negative;
            }
            ENDHLSL
        }

        Pass    // カメラカラーと合成
        {
            Name "Combine"

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #pragma vertex Vert
            #pragma fragment Frag

            TEXTURE2D_X(_NegativeTexture);
            float4 _Params;

            #define CENTER_UV       _Params.xy
            #define RADIUS          _Params.z
            #define ASPECT_RATIO    _Params.w

            half4 Frag(Varyings input) : SV_TARGET
            {
                float2 uv = input.texcoord.xy;
                float2 uvDiff = uv - CENTER_UV;

                uvDiff.x *= ASPECT_RATIO;
                float distSqr = dot(uvDiff, uvDiff);
                float radiusSqr = RADIUS * RADIUS;

                half4 negativeColor = SAMPLE_TEXTURE2D_X(_NegativeTexture, sampler_LinearClamp, uv);
                half4 sceneColor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);

                // 円内の部分を反転色にする
                half inCircle = distSqr < radiusSqr;
                half4 color = inCircle ? negativeColor : sceneColor;

                return color;
            }
            ENDHLSL
        }
    }
}
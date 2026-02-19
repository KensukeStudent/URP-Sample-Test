// 深度からワールド座標への変換を行うシェーダー
// フレームバッファフェッチ: https://docs.unity3d.com/ja/6000.0/Manual/urp/render-graph-framebuffer-fetch.html
// GPU のオンチップメモリからフレームバッファにアクセスできます

Shader "Custom/DepthToWorld"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white"
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            // gBuffer
            // https://docs.unity3d.com/jp/current/Manual/urp/rendering/g-buffer-layout.html
            #define GBUFFER0 0 // albedo
            #define GBUFFER1 1 // specular
            #define GBUFFER2 2 // normal
            #define GBUFFER3 3 // depth

            FRAMEBUFFER_INPUT_X_HALF(GBUFFER2);
            FRAMEBUFFER_INPUT_X_HALF(GBUFFER3);

            half4 frag(Varyings IN) : SV_Target
            {
                // 深度からワールド座標への変換 
                // https://docs.unity3d.com/ja/Packages/com.unity.render-pipelines.universal@14.0/manual/writing-shaders-urp-reconstruct-world-position.html
                half4 depth = LOAD_FRAMEBUFFER_X_INPUT(GBUFFER3, IN.positionCS);
                float3 worldPos = ComputeWorldSpacePosition(IN.texcoord, depth.r, UNITY_MATRIX_I_VP);

                // 反射ベクトルを計算
                float3 viewDir = normalize(worldPos - _WorldSpaceCameraPos);
                float3 normal = LOAD_FRAMEBUFFER_X_INPUT(GBUFFER2, IN.positionCS); // GBuffer Normal[-1~1]
                float3 reflectDir = reflect(viewDir, normal);

                // ワールド空間上でレイを伸ばして深度と交差する部分を計算
                int maxRayNum = 100;
                float3 step = 2 / maxRayNum * reflectDir; // 2は適当な距離

                half4 col = FragNearest(IN);

                for (int n = 1; n < maxRayNum; n++) {
                    float3 rayWS = worldPos + step * n; 
                    float4 rayCS = TransformWorldToHClip(rayWS);
                    float2 rayUV = rayCS.xy / rayCS.w * 0.5 + 0.5;
                    float3 rayNDC = rayCS.xyz / rayCS.w;
                    // 今のレイの深度
                    half rayDepth = rayNDC.z * 0.5 + 0.5; // 0~1に変換
                    half4 gbufferDepth  = LOAD_FRAMEBUFFER_X_INPUT(GBUFFER3, rayUV); // レイを飛ばした位置の深度

                    if (rayDepth - gbufferDepth.r > 0) {
                        col += SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_PointClamp, rayUV, 0) * 0.2f;
                        break;
                    }
                }

                return half4(reflectDir, 1);
            }
            ENDHLSL
        }
    }
}

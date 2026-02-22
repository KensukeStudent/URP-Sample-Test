// 深度からワールド座標への変換を行うシェーダー
// フレームバッファフェッチ: https://docs.unity3d.com/ja/6000.0/Manual/urp/render-graph-framebuffer-fetch.html
// GPU のオンチップメモリからフレームバッファにアクセスできます

Shader "Custom/ScreenSpaceReflection"
{
    Properties
    {
        _Thickness("Thickness", Range(0.0, 0.1)) = 0.0
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

            CBUFFER_START(UnityPerMaterial)
            float _Thickness; // 厚み
            CBUFFER_END

            /// <summary>
            /// Screen Space Reflectionのレイマーチング処理
            /// </summary>
            /// <param name="IN"></param>
            /// <param name="worldPos"></param>
            /// <param name="reflectDir"></param>
            /// <returns></returns>
            half4 ssrRayTrace(Varyings IN, float3 worldPos, float3 reflectDir)
            {
                int stepCount = 10; // TODO: step数が多いと読み込みが長く重くなりやすい感じ
                float3 stepDir = reflectDir * (2.0 / stepCount);

                for (int n = 1; n <= stepCount; n++)
                {
                    float3 rayWS = worldPos + stepDir * n;
                    float4 rayHCS = TransformWorldToHClip(rayWS);

                    float2 rayUV = rayHCS.xy / rayHCS.w * 0.5 + 0.5;
                    #if UNITY_UV_STARTS_AT_TOP // 上下逆問題を修正
                    rayUV.y = 1 - rayUV.y;
                    #endif

                    // 画面外チェック
                    if (rayUV.x < 0 || rayUV.x > 1 ||
                        rayUV.y < 0 || rayUV.y > 1)
                        break;

                    // レイ空間の仮想深度
                    float deviceDepth = rayHCS.z / rayHCS.w;
                    float rayDepth = Linear01Depth(deviceDepth, _ZBufferParams); // 手前0,奥1

                    // 実際に表示されている画面からレイの深度を取得
                    float rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, rayUV);
                    float depth = Linear01Depth(rawDepth, _ZBufferParams); // 手前0,奥1

                    // めり込み判定・厚み付き 
                    // rayDepthの方が手前ならめり込んでいる
                    // rayDepth,depth: 0 ~ 1
                    if (rayDepth > depth && rayDepth - depth < _Thickness)
                    {
                        IN.texcoord = rayUV;
                        return FragNearest(IN) * 0.2;
                    }
                }

                return half4(0, 0, 0, 0);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // 深度からワールド座標への変換
                // https://docs.unity3d.com/ja/Packages/com.unity.render-pipelines.universal@14.0/manual/writing-shaders-urp-reconstruct-world-position.html
                half depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, IN.texcoord).r; //LOAD_FRAMEBUFFER_X_INPUT(GBUFFER3, IN.positionCS).r;
                float3 worldPos = ComputeWorldSpacePosition(IN.texcoord, depth, UNITY_MATRIX_I_VP);

                // 反射ベクトルを計算
                float3 viewDir = normalize(worldPos - _WorldSpaceCameraPos);
                float3 normal = LOAD_FRAMEBUFFER_X_INPUT(GBUFFER2, IN.positionCS); // GBuffer Normal[-1~1]
                float3 reflectDir = reflect(viewDir, normal);

                // カラー
                half4 color = FragNearest(IN);
                half4 ssrTraceColor = ssrRayTrace(IN, worldPos, reflectDir);

                // // 検証用
                // {
                //     float4 cs = TransformWorldToHClip(worldPos);
                //     float2 uv = cs.xy / cs.w * 0.5 + 0.5;
                //     #if UNITY_UV_STARTS_AT_TOP // 上下逆問題を修正
                //     uv.y = 1.0 - uv.y;
                //     #endif
                //     float rayDepth = cs.z / cs.w; // 深度値のそのままの絵(オブジェクト以外の空間の深度もある)
                //     rayDepth = Linear01Depth(rayDepth, _ZBufferParams); // 手前0,奥1

                //     float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, uv);
                //     depth = Linear01Depth(depth, _ZBufferParams); // 手前0,奥1

                //     return half4(rayDepth,0,0,1);
                // }

                return color + ssrTraceColor;
            }
            ENDHLSL
        }
    }
}

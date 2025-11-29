Shader "Custom/TSNormalShader"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {} // TODO: {}が無いと以下定義するとエラー発生する
        [MainTexture] _NormalMap("Normal Map", 2D) = "white" {} // TODO: {}が無いと以下定義するとエラー発生する
        
        _SpecThreshold("Specular Threshold", Range(0.0, 200.0)) = 5.0 // 鏡面反射の強さ
        _FinalLightThreshold("Final Light Threshold", Range(0.0, 1.0)) = 0.3 // ライトの底上げ量
        _LimLightThreshold("Lim Light Threshold", Range(0.0, 10.0)) = 10.0 // リムライトの鋭さ
        _IsHemiLight("Is Hemi Light", Range(0.0, 1.0)) = 0 // 半球ライトの有効/無効
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
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // 自作ライティング関数
            #include "Assets\ShaderLibrary\Lighting\lightingFunc.hlsl"


            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS: NORMAL;
                float4 tangentOS: TANGENT;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 normalWS : NORMAL;
                float4 tangentWS : TANGENT;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1; // ワールド座標系の位置
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            CBUFFER_START(UnityPerMaterial)
                
                // 画像
                half4 _BaseColor;
                float4 _BaseMap_ST;
                float4 _NormalMap_ST;

                // パラメーター
                float _SpecThreshold;
                float _FinalLightThreshold;
                float _LimLightThreshold;
                float _IsHemiLight;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz); // ローカル->ワールド変換
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.tangentWS =  float4(TransformObjectToWorldDir(IN.tangentOS.xyz), IN.tangentOS.w);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // ------------------------------------
                // 法線マップ タンジェントスペースの計算
                // ------------------------------------

                float3 normalTS = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, IN.uv)); //[0,0] -> [-1,1]に変換
                float crossSign = (IN.tangentWS.w > 0.0 ? 1.0 : -1.0) * GetOddNegativeScale(); // GetOddNegativeScale() モデルが反転したときに補正する役割
                float3 bitangentWS = crossSign * cross(IN.normalWS.xyz, IN.tangentWS.xyz);
                float3 normal = normalize(
                    normalTS.x * IN.tangentWS + 
                    normalTS.y * bitangentWS +
                    normalTS.z * IN.normalWS
                );

                // ------------------------------------
                // ライティング計算
                // ------------------------------------

                float3 finalLight = CalcLight(IN.positionWS, normal, _SpecThreshold, _LimLightThreshold, _IsHemiLight, _FinalLightThreshold);

                // ------------------------------------
                // テクスチャーカラーとライティングの合成
                // ------------------------------------

                // メインテクスチャカラー取得
                half4 finalColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;

                finalColor.xyz *= finalLight;

                return finalColor;
            }

            ENDHLSL
        }
    }
}

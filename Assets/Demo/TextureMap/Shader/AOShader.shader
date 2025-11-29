Shader "Custom/AOShader"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] [NoScaleOffset] _BaseMap("Base Map", 2D) = "white" {} // TODO: {}が無いと以下定義するとエラー発生する
        [NoScaleOffset] _NormalMap("Normal Map", 2D) = "white" {} // TODO: {}が無いと以下定義するとエラー発生する
        [NoScaleOffset] _SpecularMap("Specular Map", 2D) = "white" {} // TODO: {}が無いと以下定義するとエラー発生する
        [NoScaleOffset] _AoMap("Ambient Occlusion Map", 2D) = "white" {} // TODO: {}が無いと以下定義するとエラー発生する
        
        _SpecThreshold("Specular Threshold", Range(0.0, 200.0)) = 5.0 // 鏡面反射の強さ
        _SpecPower("Specular Power", Range(0.0, 10.0)) = 1.0 // 鏡面反射の強さ
        _LimLightThreshold("Lim Light Threshold", Range(0.0, 10.0)) = 10.0 // リムライトの鋭さ
        _IsHemiLight("Is Hemi Light", Range(0.0, 1.0)) = 0 // 半球ライトの有効/無効
        _AmbientPower("Ambient Power", Range(0.0, 1.0)) = 0.3 // 環境光の基準値
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
            
            TEXTURE2D(_SpecularMap);
            SAMPLER(sampler_SpecularMap);

            TEXTURE2D(_AoMap);
            SAMPLER(sampler_AoMap);

            CBUFFER_START(UnityPerMaterial)
                // 画像
                half4 _BaseColor;
                float4 _BaseMap_ST;

                // パラメーター
                float _SpecThreshold;
                float _SpecPower;
                float _AmbientPower;
                float _LimLightThreshold;
                float _IsHemiLight;
            CBUFFER_END

            // プロトタイプ宣言
            float3 CalcLight(float3 positionWS, float3 normalWS, half specPower);

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
                // スペキュラーマップの計算
                // ------------------------------------

                half specPower = SAMPLE_TEXTURE2D(_SpecularMap, sampler_SpecularMap, IN.uv).r;
                specPower *= _SpecPower;

                // ------------------------------------
                // アンビエントオクルージョンマップの計算
                // ------------------------------------

                half aoPower = SAMPLE_TEXTURE2D(_AoMap, sampler_AoMap, IN.uv).r;
                aoPower *= _AmbientPower;

                // ------------------------------------
                // ライティング計算
                // ------------------------------------

                float3 finalLight = CalcLight(IN.positionWS, normal, specPower);
                finalLight += aoPower; // アンビエントオクルージョンの影響を加算

                // ------------------------------------
                // テクスチャーカラーとライティングの合成
                // ------------------------------------

                // メインテクスチャカラー取得
                half4 finalColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;

                finalColor.xyz *= finalLight;

                return finalColor;
            }

            float3 CalcLight(float3 positionWS, float3 normalWS, half specPower)
            {
                // ------------------------------- メインライトのライティング -------------------------------

                Light mainLight;
                mainLight = GetMainLight();

                // ランバート反射モデル
                float3 diffuseLight = CalcLambertDiffuse(mainLight.direction, mainLight.color, normalWS);
                // フォン反射モデル
                float3 specularLight = CalcPhongSpecular(mainLight.direction, mainLight.color, positionWS, normalWS, _SpecThreshold) * specPower;
                // リムライト
                float3 limLight = CalcLimLight(mainLight.direction, mainLight.color, positionWS, normalWS, _LimLightThreshold);
                float3 directionLight = diffuseLight + specularLight + limLight;

                // ------------------------------- 追加のライティング(ポイントライト・スポットライトなど) -------------------------------
                Light addLight;
                int addLightCount = GetAdditionalLightsCount();
                float3 addFinalLight;

                for (int index = 0; index < addLightCount; index++) {
                    addLight = GetAdditionalLight(index, positionWS);
                    float3 addDiffuseLight = CalcLambertDiffuse(addLight.direction, addLight.color, normalWS);
                    float3 addSpecularLight = CalcPhongSpecular(addLight.direction, addLight.color, positionWS, normalWS, _SpecThreshold) * specPower;
                    float3 addLimLight = CalcLimLight(addLight.direction, addLight.color, positionWS, normalWS, _LimLightThreshold);

                    // 減衰を考慮したポイントライトの合成
                    addDiffuseLight = addDiffuseLight * addLight.distanceAttenuation;
                    addSpecularLight = addSpecularLight * addLight.distanceAttenuation;
                    addLimLight = addLimLight * addLight.distanceAttenuation;

                    addFinalLight += addDiffuseLight + addSpecularLight + addLimLight;
                }

                // ------------------------------- 半球ライト -------------------------------
                float3 skyColor = mainLight.color;
                float3 groundColor = float3(1,0,0); // 地面の色を赤
                float3 groundNormal = float3(0, 1, 0); // 地面の法線を真上

                float t = dot(normalWS, groundNormal);
                t = (t + 1.0) / 2; // [0,1]に変換

                float3 hemiLight = lerp(groundColor, skyColor, t);
                hemiLight = lerp(float3(0,0,0), hemiLight, _IsHemiLight); // 半球ライトの有効/無効切り替え

                // ------------------------------- ライティングの合成 -------------------------------

                // 最終的なライティング計算
                return directionLight + addFinalLight + hemiLight;
            }
            ENDHLSL
        }
    }
}

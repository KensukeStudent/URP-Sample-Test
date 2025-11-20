Shader "Custom/NormalShader"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {} // TODO: {}が無いと以下定義するとエラー発生する
        [MainTexture] _NormalMap("Normal Map", 2D) = "white" {} // TODO: {}が無いと以下定義するとエラー発生する
        
        _SpecThreshold("Specular Threshold", Range(0.0, 200.0)) = 5.0 // 鏡面反射の強さ
        _FinalLightThreshold("Final Light Threshold", Range(0.0, 1.0)) = 0.3 // ライトの底上げ量
        _LimLightThreshold("Lim Light Threshold", Range(0.0, 10.0)) = 10.0 // リムライトの鋭さ
        _IsHemiLight("Is Hemi Light", Range(0.0, 1.0)) = 1 // 半球ライトの有効/無効
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

            // プロトタイプ宣言
            float3 CalcLambertDiffuse(float3 lightDirection, float3 lightColor, float3 normal);
            float3 CalcPhongSpecular(float3 lightDirection, float3 lightColor, float3 positionWS, float3 normal);
            float3 CalcLimLight(float3 lightDirection, float3 lightColor, float3 positionWS, float3 normalWS);
            float3 CalcLight(float3 positionWS, float3 normalWS);

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

                float3 finalLight = CalcLight(IN.positionWS, normal);

                // ------------------------------------
                // テクスチャーカラーとライティングの合成
                // ------------------------------------

                // メインテクスチャカラー取得
                half4 finalColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;

                finalColor.xyz *= finalLight;

                return finalColor;
            }

            // ランバート反射モデル計算関数
            float3 CalcLambertDiffuse(float3 lightDirection, float3 lightColor, float3 normal)
            {
                float diffuse = dot(normal, lightDirection);
                return lightColor * saturate(diffuse);
            }

            // フォン鏡面反射モデル計算関数
            float3 CalcPhongSpecular(float3 lightDirection, float3 lightColor, float3 positionWS, float3 normal)
            {
                float3 reflectDir = lightDirection + 2 * dot(normal, -lightDirection) * normal;
                float3 viewDir = normalize(positionWS - _WorldSpaceCameraPos); // カメラからポリゴンへの方向
                float specular = dot(reflectDir, viewDir);
                specular = pow(saturate(specular), _SpecThreshold); // 適当な鏡面反射の強さ
                return lightColor * specular;
            }

            // リムライト計算関数
            float3 CalcLimLight(float3 lightDirection, float3 lightColor, float3 positionWS, float3 normalWS)
            {
                // ディレクショナルライトの入射角と法線からリムライトの強さ計算
                float power1 = 1.0f - max(0.0f, dot(lightDirection, normalWS));

                // 視線方向と法線からリムライトの強さ計算
                float3 viewDir = normalize(positionWS - _WorldSpaceCameraPos);
                float power2 = 1.0f - max(0.0f, dot(-viewDir, normalWS));

                float limPower = power1 * power2;
                limPower = pow(limPower, _LimLightThreshold); // リムライトの鋭さ調整
                return limPower * lightColor;
            }

            float3 CalcLight(float3 positionWS, float3 normalWS)
            {
                // ------------------------------- メインライトのライティング -------------------------------

                Light mainLight;
                mainLight = GetMainLight();

                // ランバート反射モデル
                float3 diffuseLight = CalcLambertDiffuse(mainLight.direction, mainLight.color, normalWS);
                // フォン反射モデル
                float3 specularLight = CalcPhongSpecular(mainLight.direction, mainLight.color, positionWS, normalWS);
                // リムライト
                float3 limLight = CalcLimLight(mainLight.direction, mainLight.color, positionWS, normalWS);
                float3 directionLight = diffuseLight + specularLight + limLight;

                // ------------------------------- 追加のライティング(ポイントライト・スポットライトなど) -------------------------------
                Light addLight;
                int addLightCount = GetAdditionalLightsCount();
                float3 addFinalLight;

                for (int index = 0; index < addLightCount; index++) {
                    addLight = GetAdditionalLight(index, positionWS);
                    float3 addDiffuseLight = CalcLambertDiffuse(addLight.direction, addLight.color, normalWS);
                    float3 addSpecularLight = CalcPhongSpecular(addLight.direction, addLight.color, positionWS, normalWS);
                    float3 addLimLight = CalcLimLight(addLight.direction, addLight.color, positionWS, normalWS);

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
                float3 finalLight = directionLight + addFinalLight + hemiLight;

                // ライトの効果を一律で底上げする
                finalLight.xyz += _FinalLightThreshold;

                return finalLight;
            }

            ENDHLSL
        }
    }
}

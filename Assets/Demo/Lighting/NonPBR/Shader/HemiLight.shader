Shader "Custom/HemiLight"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {} // TODO: {}が無いと以下定義するとエラー発生する
        
        _SpecThreshold("Specular Threshold", Range(0.0, 200.0)) = 5.0
        _FinalLightThreshold("Final Light Threshold", Range(0.0, 1.0)) = 0.3
        _LimLightThreshold("Lim Light Threshold", Range(0.0, 10.0)) = 10.0
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
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 normalWS : NORMAL;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1; // ワールド座標系の位置
                // float3 normalVS : TEXCOORD2; // ビュー座標系の法線
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                float _SpecThreshold;
                float _FinalLightThreshold;
                float _LimLightThreshold;
            CBUFFER_END

            // プロトタイプ宣言
            float3 CalcLambertDiffuse(float3 lightDirection, float3 lightColor, float3 normal);
            float3 CalcPhongSpecular(float3 lightDirection, float3 lightColor, float3 positionWS, float3 normal);
            float3 CalcLimLight(float3 lightDirection, float3 lightColor, float3 positionWS, float3 normalWS);

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz); // ローカル->ワールド変換
                // OUT.normalVS = TransformWorldToViewNormal(OUT.normalWS, true); // ワールド->ビュー変換
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // ------------------------------------
                // ライティング計算
                // ------------------------------------

                // ------------------------------- メインライトのライティング -------------------------------

                Light mainLight;
                mainLight = GetMainLight();

                // ランバート反射モデル
                float3 diffuseLight = CalcLambertDiffuse(mainLight.direction, mainLight.color, IN.normalWS);
                // フォン反射モデル
                float3 specularLight = CalcPhongSpecular(mainLight.direction, mainLight.color, IN.positionWS, IN.normalWS);
                // リムライト
                float3 limLight = CalcLimLight(mainLight.direction, mainLight.color, IN.positionWS, IN.normalWS);

                float3 directionLight = diffuseLight + specularLight + limLight;

                // ------------------------------- 追加のライティング(ポイントライト・スポットライトなど) -------------------------------
                Light addLight;
                int addLightCount = GetAdditionalLightsCount();
                float3 addFinalLight;

                for (int index = 0; index < addLightCount; index++) {
                    addLight = GetAdditionalLight(index, IN.positionWS);
                    float3 addDiffuseLight = CalcLambertDiffuse(addLight.direction, addLight.color, IN.normalWS);
                    float3 addSpecularLight = CalcPhongSpecular(addLight.direction, addLight.color, IN.positionWS, IN.normalWS);
                    float3 addLimLight = CalcLimLight(addLight.direction, addLight.color, IN.positionWS, IN.normalWS);

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

                float t = dot(IN.normalWS, groundNormal);
                t = (t + 1.0) / 2; // [0,1]に変換

                float3 hemiLight = lerp(groundColor, skyColor, t);

                // ------------------------------- ライティングの合成 -------------------------------

                // 最終的なライティング計算
                float3 finalLight = directionLight + addFinalLight + hemiLight;

                // ライトの効果を一律で底上げする
                finalLight.xyz += _FinalLightThreshold;

                // ------------------------------------
                // テクスチャーカラーとライティングの合成
                // ------------------------------------

                // テクスチャーカラー取得
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

            ENDHLSL
        }
    }
}

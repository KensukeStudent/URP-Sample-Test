Shader "Custom/SimpleShader"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [NormalMap] _NormalMap("Normal Map", 2D) = "bump" {}

        // 拡散反射
        _DiifuseThreshold("Diffuse Threshold", Range(0.0, 1.0)) = 0.5 // 拡散反射の閾値
        _DiffuseColor("Diffuse Color", Color) = (1, 1, 1, 1) // 拡散反射の色

        [Space(10)]
        // 鏡面反射
        _SpecularColor("Specular Color", Color) = (1, 1, 1, 1) // 鏡面反射の色
        _SpecularPower("Specular Power", Range(1.0, 100.0)) = 5.0 // 鏡面反射の強さ
        _SpecThreshold("Specular Threshold", Range(0.0, 1.0)) = 0.5 // 鏡面反射の閾値
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
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : NORMAL;
                float4 tangentWS : TANGENT;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                
                // 拡散反射
                float4 _DiffuseColor;
                float _DiifuseThreshold;

                // 鏡面反射
                float4 _SpecularColor;
                float _SpecularPower;
                float _SpecThreshold;
            CBUFFER_END

            float3 CalcLambertDiffuse(float3 lightDir, float3 lightColor, float3 normalWS);
            float3 CalcPhongSpecular(float3 lightDir, float3 lightColor, float3 positionWS, float3 normalWS);

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);

                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.tangentWS = float4(TransformObjectToWorldDir(IN.tangentOS.xyz), IN.tangentOS.w);

                return OUT;
            }

            float3 frag(Varyings IN) : SV_Target
            {
                float4 col = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;

                float3 normalTS = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, IN.uv));                
                float crossSign = (IN.tangentWS.w > 0.0 ? 1.0 : -1.0) * GetOddNegativeScale(); // GetOddNegativeScale() モデルが反転したときに補正する役割
                float3 bitangentWS = crossSign * cross(IN.normalWS, IN.tangentWS.xyz);
                float3 normalWS = normalTS.x * IN.tangentWS.xyz +
                                  normalTS.y * bitangentWS +
                                  normalTS.z * IN.normalWS;

                Light mainLight;
                mainLight = GetMainLight();

                float3 lig = float3(0,0,0);

                // ランバート反射モデル
                lig += CalcLambertDiffuse(mainLight.direction, mainLight.color, normalWS);

                // 鏡面反射（フォンモデル）
                //lig += CalcPhongSpecular(mainLight.direction, mainLight.color, IN.positionWS, normalWS);

                // // 追加ライティングチェック
                // Light addLight;
                // int addLightCount = GetAdditionalLightsCount();

                // for (int index = 0; index < addLightCount; index++) {
                //     addLight = GetAdditionalLight(index, IN.positionWS);

                //     float3 addDiffuseLight = CalcLambertDiffuse(addLight.direction, addLight.color, normalWS);
                //     float3 addSpecularLight = CalcPhongSpecular(addLight.direction, addLight.color, IN.positionWS, normalWS, _SpecThreshold);

                //     // 減衰を考慮したポイントライトの合成
                //     lig += addDiffuseLight * addLight.distanceAttenuation;
                //     lig += addSpecularLight * addLight.distanceAttenuation;
                // }
                
                return float4(lig, 1.0);
            }

            float3 CalcLambertDiffuse(float3 lightDir, float3 lightColor, float3 normalWS)
            {
                float NdotL = saturate(dot(normalWS, lightDir));
                float3 lambertDiffuse = NdotL * _DiffuseColor.rgb * _DiifuseThreshold;
                //lambertDiffuse /= 3.14159f; // 正規化

                return lambertDiffuse;
            }

            float3 CalcPhongSpecular(float3 lightDir, float3 lightColor, float3 positionWS, float3 normalWS)
            {
                float3 viewDir = normalize(_WorldSpaceCameraPos - positionWS); // カメラからポリゴンへの方向
                float3 reflectDir = reflect(-lightDir, normalWS);
                float RdotV = saturate(dot(reflectDir, viewDir));
                float3 specular = pow(RdotV, _SpecularPower) * _SpecularColor.rgb * _SpecThreshold;

                return specular;
            }
            ENDHLSL
        }
    }
}

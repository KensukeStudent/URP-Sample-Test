// Unityエンジンぽい色味を目指したアンビエントライティングシェーダー

Shader "Custom/Ambient"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {} // TODO: {}が無いと以下定義するとエラー発生する
        
        _SpecThreshold("Specular Threshold", Range(0.0, 200.0)) = 5.0
        _FinalLightThreshold("Final Light Threshold", Range(0.0, 1.0)) = 0.3
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
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : NORMAL;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                float _SpecThreshold;
                float _FinalLightThreshold;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                Light mainLight;
                mainLight = GetMainLight();

                // ランバート反射モデル
                float diffuse = dot(IN.normalWS, mainLight.direction);
                float3 diffuseLight = mainLight.color * saturate(diffuse);

                // フォン反射モデル
                float3 reflectDir = mainLight.direction + 2 * dot(IN.normalWS, -mainLight.direction) * IN.normalWS;
                float3 viewDir = normalize(IN.positionWS - _WorldSpaceCameraPos); // カメラからポリゴンへの方向
                float specular = dot(reflectDir, viewDir);
                specular = pow(saturate(specular), _SpecThreshold); // 適当な鏡面反射の強さ
                float3 specularLight = mainLight.color * specular;

                // 最終的なライティング計算
                float3 finalLight = diffuseLight + specularLight;

                // ライトの効果を一律で底上げする
                finalLight.xyz += _FinalLightThreshold;

                // テクスチャーカラー取得
                half4 finalColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                finalColor.xyz *= finalLight;

                return finalColor;
            }
            ENDHLSL
        }
    }
}

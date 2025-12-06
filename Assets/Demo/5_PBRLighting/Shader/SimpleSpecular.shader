Shader "Custom/SimpleSpecular"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}

        _SpecularColor("Specular Color", Color) = (1, 1, 1, 1) // 鏡面反射の色
        _SpecularPower("Specular Power", Range(1.0, 100.0)) = 5.0 // 鏡面反射の強さ
        _SpecThreshold("Specular Threshold", Range(0.0, 1.0)) = 0.5 // 鏡面反射の閾値

        _Metallic("Metallic", Range(0.0, 1.0)) = 0.0 // メタリック（PBR用）
        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5 // 滑らかさ（PBR用）
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

                // 鏡面反射
                float4 _SpecularColor;
                float _SpecularPower;
                float _SpecThreshold;

                // メタリック・滑らかさ（PBR用）
                float _Metallic;
                float _Smoothness;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                return OUT;
            }

            // スペキュラー
            // Metallicが高いとDiffuseColorの色を反射
            // Metallicが低いと白色を反射
            // 
            // Sommothnessが高いと強く
            // Sommothnessが低いと弱い
            half4 frag(Varyings IN) : SV_Target
            {
                Light mainLight;
                mainLight = GetMainLight();

                half4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                
                float3 viewDir = normalize(_WorldSpaceCameraPos - IN.positionWS); // カメラからポリゴンへの方向
                float3 reflectDir = reflect(-mainLight.direction, IN.normalWS);
                float RdotV = saturate(dot(reflectDir, viewDir));
                float3 specularColor = pow(RdotV, _SpecularPower) * mainLight.color.rgb * _SpecularColor.rgb;
                float3 specular = specularColor * _SpecThreshold;
                
                return half4(specular, 1.0) * albedo;
            }
            ENDHLSL
        }
    }
}

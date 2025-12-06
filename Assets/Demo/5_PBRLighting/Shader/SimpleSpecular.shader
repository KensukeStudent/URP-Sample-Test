Shader "Custom/SimpleSpecular"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}

        _SpecularColor("Specular Color", Color) = (1, 1, 1, 1) // 鏡面反射の色

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
            // Metallic（金属度）が高いと物体の色を反射
            // Metallic（金属度）が低いと光源の色を反射
            // 
            // Smoothnessが高いと強く
            // Smoothnessが低いと弱い
            half4 frag(Varyings IN) : SV_Target
            {
                Light mainLight;
                mainLight = GetMainLight();

                half4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                half3 specularColor = lerp(mainLight.color, albedo.rgb, half3(_Metallic, _Metallic, _Metallic));
                float shininess = lerp(32, 4096, 1 - _Smoothness);  // PBRに近い値
                float3 viewDir = normalize(_WorldSpaceCameraPos - IN.positionWS); // カメラからポリゴンへの方向

                float3 halfDir = normalize(mainLight.direction + viewDir);
                float NdotH = saturate(dot(IN.normalWS, halfDir));
                float3 specular = pow(NdotH, shininess) * _SpecularColor.rgb * mainLight.color.rgb;

                return half4(specular + albedo.rgb * (1 - _Metallic), 1.0) + albedo;
            }
            ENDHLSL
        }
    }
}

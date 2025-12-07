Shader "Custom/SimpleLambert"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}

        // 拡散反射
        _DiffuseColor("Diffuse Color", Color) = (1, 1, 1, 1) // 拡散反射の色

        // メタリック（PBR用）
        _Metallic("Metallic", Range(0.0, 1.0)) = 0.0
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
                
                // 拡散反射
                float4 _DiffuseColor;

                // メタリック（PBR用）
                float _Metallic;
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

            half4 frag(Varyings IN) : SV_Target
            {
                Light mainLight;
                mainLight = GetMainLight();

                // 拡散反射の影響 (1に近いと拡散反射は消滅・0に近いと拡散反射が強くなる)
                float diffuseThreshold = 1 - _Metallic;
                
                half4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;

                float3 lightDir = normalize(mainLight.direction);
                float NdotL = saturate(dot(IN.normalWS, lightDir));
                float3 diffuseColor = NdotL * mainLight.color.rgb * _DiffuseColor.rgb;
                float3 lambertDiffuse = diffuseColor * diffuseThreshold; // エネルギー保存の法則による正規化無し

                // ----- 最低限の明るさを担保 -----
                half3 ambient = SampleSH(IN.normalWS); // スカイボックスカラーなどの間接光
                lambertDiffuse += ambient; // 超簡易的な間接光ならfloat3(0.3)とかを入れるとよい
                
                return half4(lambertDiffuse, 1.0) * albedo;
            }
            ENDHLSL
        }
    }
}

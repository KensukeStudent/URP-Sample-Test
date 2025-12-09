Shader "Custom/cook-torrance3"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1,1,1,1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        _SpecularColor("Specular Color", Color) = (1,1,1,1)
        _Metallic("Metallic", Range(0,1)) = 0.0
        _Smoothness("Smoothness", Range(0,1)) = 0.5
        _IndirectIntensity("Indirect Intensity", Float) = 1.0
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
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

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
                float3 normalWS : TEXCOORD2;
                float4 shadowCoord : TEXCOORD3;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                half4 _SpecularColor;
                float _Metallic;
                float _Smoothness;
                float _IndirectIntensity;
            CBUFFER_END

            // --- ユーティリティ定数 ---
            #define PI 3.14159265359
            #define EPS 1e-5

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionHCS = TransformWorldToHClip(OUT.positionWS);
                OUT.normalWS = normalize(TransformObjectToWorldNormal(IN.normalOS));
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.shadowCoord = TransformWorldToShadowCoord(OUT.positionWS);
                return OUT;
            }

            // --- GGX / Schlick / Smith functions ---
            // Distribution (GGX)
            float DistributionGGX(float NdotH, float roughness)
            {
                float a = roughness * roughness;
                float a2 = a * a;
                float denom = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
                denom = PI * denom * denom;
                return a2 / max(denom, EPS);
            }

            // Schlick-GGX geometry term (Smith)
            float GeometrySchlickGGX(float Ndot, float k)
            {
                return Ndot / (Ndot * (1.0 - k) + k);
            }

            float GeometrySmith(float NdotV, float NdotL, float roughness)
            {
                // UE/Disney の近似：k = (roughness+1)^2 / 8
                float r = roughness + 1.0;
                float k = (r * r) / 8.0;
                float gV = GeometrySchlickGGX(NdotV, k);
                float gL = GeometrySchlickGGX(NdotL, k);
                return gV * gL;
            }

            // Fresnel Schlick (色対応)
            float3 FresnelSchlick(float cosTheta, float3 F0)
            {
                // pow(1 - cos,5) は Schlick の近似
                return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
            }

            // Cook-Torranceの鏡面成分（float3を返す）
            float3 CookTorranceSpecular(float3 N, float3 V, float3 L, float3 F0, float roughness)
            {
                float3 H = normalize(V + L);

                float NdotL = saturate(dot(N, L));
                float NdotV = saturate(dot(N, V));
                float NdotH = saturate(dot(N, H));
                float VdotH = saturate(dot(V, H));

                if (NdotL <= 0.0 || NdotV <= 0.0) return float3(0.0, 0.0, 0.0);

                float D = DistributionGGX(NdotH, roughness);
                float G = GeometrySmith(NdotV, NdotL, roughness);
                float3 F = FresnelSchlick(VdotH, F0);

                float denom = max(4.0 * NdotV * NdotL, EPS);
                float3 spec = (D * G) / denom * F;

                return spec; // RGB
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // サンプル
                float3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv).rgb * _BaseColor.rgb;
                float roughness = saturate(1.0 - _Smoothness); // smooth->rough
                float metallic = saturate(_Metallic);

                // Main directional light (簡易: radiance = mainLight.color)
                Light mainLight = GetMainLight(IN.shadowCoord);
                float3 L = normalize(mainLight.direction); // URP: direction points TO the surface? check in your URP version; normalize anyway
                float3 N = normalize(IN.normalWS);
                float3 V = normalize(_WorldSpaceCameraPos - IN.positionWS);

                float NdotL = saturate(dot(N, L));
                float NdotV = saturate(dot(N, V));

                // F0: non-metal baseline 0.04, metal uses albedo as F0
                float3 F0_nonmetal = float3(0.04, 0.04, 0.04);
                float3 F0 = lerp(F0_nonmetal, albedo, metallic);

                // direct specular
                // Specular (Cook-Torrance)
                float3 specularBRDF = CookTorranceSpecular(N, V, L, F0, roughness);
                float3 lightColor = mainLight.color.rgb;
                float shadowAtten = mainLight.shadowAttenuation; // GetMainLight(IN.shadowCoord) でセット済み
                float3 specular = specularBRDF * lightColor * shadowAtten;

                // --- IBL (environment/specular) ---
                float3 R = reflect(-V, N); // reflection vector

                float3 env = DecodeHDREnvironment(SAMPLE_TEXTURECUBE(unity_SpecCube0, samplerunity_SpecCube0, R), unity_SpecCube0_HDR);
                float3 ambientSpecularIBL = env;

                // multiply by Fresnel to tint specular IBL by F
                float3 F_env = FresnelSchlick(saturate(dot(R, V)), F0);
                float3 specularIBL = ambientSpecularIBL * F_env;

                // Diffuseの計算 ------------------------------------------------------------

                // Diffuse (Lambert) with energy conservation: kD = (1 - F) * (1 - metallic)
                float3 F_at_N = FresnelSchlick(saturate(dot(normalize(V + L), V)), F0); // approx for kD calc
                float3 kD = (1.0 - F_at_N) * (1.0 - metallic);
                float3 diffuse = kD * albedo; // / PI;正規化無し
                diffuse *= NdotL * lightColor * shadowAtten;

                // approximate ambient diffuse from SH
                float3 ambientDiffuseSH = SampleSH(N) * _IndirectIntensity; // returns RGB from SH
                ambientDiffuseSH *= albedo * (1.0 - metallic); // match energy conservation for diffuse indirect

                // combine
                float3 color = specular + specularIBL;

                // ガンマ補正はマテリアルパイプライン側で行うことが多い
                return half4(color, 1.0);
            }

            ENDHLSL
        }
    }
}

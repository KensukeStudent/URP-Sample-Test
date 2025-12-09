Shader "Custom/cook-torrance2"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1,1,1,1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}

        _DiffuseColor("Diffuse Color", Color) = (1,1,1,1)
        _SpecularColor("Specular Color", Color) = (1,1,1,1)
        
        _Metallic("Metallic", Range(0,1)) = 0.0
        _Smoothness("Smoothness", Range(0,1)) = 0.5
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

                // 拡散反射
                float4 _DiffuseColor;
                half4 _SpecularColor;
                
                float _Metallic;
                float _Smoothness;
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
            float3 FresnelSchlick(float cosTheta, float3 F0, float F90 = 1)
            {
                // pow(1 - cos,5) は Schlick の近似
                return (F0 + (F90 - F0) * pow(1.0f - cosTheta, 5.0f));
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

            /// <summary>
            /// フレネル反射を考慮した拡散反射を計算
            /// </summary>
            /// <remark>
            /// この関数はフレネル反射を考慮した拡散反射率を計算します
            /// フレネル反射は、光が物体の表面で反射する現象のとこで、鏡面反射の強さになります
            /// 一方拡散反射は、光が物体の内部に入って、内部錯乱を起こして、拡散して反射してきた光のことです
            /// つまりフレネル反射が弱いときには、拡散反射が大きくなり、フレネル反射が強いときは、拡散反射が小さくなります
            /// </remark>
            /// <param name="N">法線</param>
            /// <param name="L">光源に向かうベクトル。光の方向と逆向きのベクトル。</param>
            /// <param name="V">視線に向かうベクトル。</param>
            /// <param name="roughness">粗さ。0～1の範囲。</param>
            float CalcDiffuseFromFresnel(float3 N, float3 L, float3 V, float roughness)
            {
                // step-1 ディズニーベースのフレネル反射による拡散反射を真面目に実装する。
                
                // =========================================================================================================
                // 公式
                // baseColor * ( (1 + (Fd90 - 1)(1 - cosΘl)^5) * (1 + (Fd90 - 1)(1 - cosΘv)^5) ) / π
                // この関数で行っている部分は( (1 + (Fd90 - 1)(1 - cosΘl)^5) * (1 + (Fd90 - 1)(1 - cosΘv)^5) )だけ
                
                // 前半の(1 + (Fd90 - 1)(1 - cosΘl)^5)：法線と光源ベクトル基準の拡散反射率
                // 後半の(1 + (Fd90 - 1)(1 - cosΘv)^5)：法線と視線ベクトル基準の拡散反射率
                // π：求めた拡散反射率の正規化定数
                
                // 期待される結果（cosΘの値に応じて変わるようなイメージ、要はlerpみたいな式）
                // 入射ベクトル = 法線: cosΘ = 1 ==> 拡散反射率 = 1
                // 入射ベクトル ⊥ 法線: cosΘ = 0 ==> 拡散反射率 = 2 - Fd90
                
                // Fd90 = 0.5f + 2.0f * roughness * cosΘ^2
                // 0.5をEAの(0.0~0.5)の範囲内だと全体の拡散反射を0.0~1.0に調整できる
                
                // =========================================================================================================
                
                // 光源に向かうベクトルと視線に向かうベクトルのハーフベクトルを求める
                float3 H = normalize(L + V); // 粗さを考慮するために反射ベクトル方向ではなくて，ハーフベクトル方向とするらしい
                
                //  Disney拡散反射BRDF はエネルギー保存則を満たさないため正規化を行う
                // https://zenn.dev/mebiusbox/books/619c81d2fbeafd/viewer/77aea9#%E6%AD%A3%E8%A6%8F%E5%8C%96
                float energyBias = lerp(0.0f, 0.5f, roughness);
                float energyFactor = lerp(1.0f, 1.0f / 1.51f, roughness); // 正規化値
                
                // 光源に向かうベクトルとハーフベクトルがどれだけ似ているかを内積で求める
                float dotLH = saturate(dot(L, H));
                
                // 光源に向かうベクトルとハーフベクトル
                // 光が平行に入射したときの拡散反射量を求める
                float Fd90 = energyBias + 2.0f * roughness * dotLH * dotLH;
                float3 F0 = float3(1.0f, 1.0f, 1.0f); // 完全反射のときのフレネル反射率は1.0とする
                
                // 法線と光源に向かうベクトルを利用して拡散反射率を求める
                float dotNL = saturate(dot(N, L));
                float FL = FresnelSchlick(dotNL, F0, Fd90).r;
                
                // 法線と視線に向かうベクトルを利用して拡散反射率を求める
                float dotNV = saturate(dot(N, V));
                float FV = FresnelSchlick(dotNV, F0, Fd90).r;
                
                // それぞれの拡散反射率を掛け合わせて、エネルギー保存の法則を満たすように正規化する
                return (FL * FV) * energyFactor;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // サンプル
                float3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv).rgb * _BaseColor.rgb;
                
                float roughness = 1.0 - _Smoothness; // smooth->rough
                float metallic = saturate(_Metallic);
                float diffuseThreshold = 1 - _Metallic;

                // Main directional light (簡易: radiance = mainLight.color)
                Light mainLight = GetMainLight(IN.shadowCoord);
                float3 L = normalize(mainLight.direction); // URP: direction points TO the surface? check in your URP version; normalize anyway
                float3 N = normalize(IN.normalWS);
                float3 V = normalize(_WorldSpaceCameraPos - IN.positionWS);

                float NdotL = saturate(dot(N, L));
                float NdotV = saturate(dot(N, V));

                // F0: non-metal baseline 1, metal uses specular color as F0
                float3 F0_nonmetal = float3(1, 1, 1);
                float3 F0 = lerp(F0_nonmetal, _SpecularColor.rgb, metallic);

                // direct specular
                // Specular (Cook-Torrance)
                float3 specularBRDF = CookTorranceSpecular(N, V, L, F0, lerp(0.15, 1.0, roughness)) * mainLight.color.rgb;
                float shadowAtten = mainLight.shadowAttenuation; // GetMainLight(IN.shadowCoord) でセット済み
                float3 specular = specularBRDF * shadowAtten;

                // --- IBL (environment/specular) ---
                float3 R = reflect(-V, N); // reflection vector

                // float3 env = DecodeHDREnvironment(SAMPLE_TEXTURECUBE(unity_SpecCube0, samplerunity_SpecCube0, R), unity_SpecCube0_HDR);
                // float3 ambientSpecularIBL = env;

                // // multiply by Fresnel to tint specular IBL by F
                // float3 F_env = FresnelSchlick(saturate(dot(R, V)), F0, 1.5);
                // float3 specularIBL = ambientSpecularIBL * F_env * lerp(0.0, 1, _Metallic) * lerp(0.0, 1, _Smoothness);

                // ====== 追加: Reflection Probe (IBL) ======
                float mip = roughness * UNITY_SPECCUBE_LOD_STEPS;
                float4 env = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, R, mip);
                float3 envColor = DecodeHDREnvironment(env, unity_SpecCube0_HDR);

                // ====== 環境鏡面を Fresnel でブレンド ======
                float3 specularIBL = envColor * FresnelSchlick(NdotV, F0) * lerp(0.0, 1, _Metallic);

                // Diffuseの計算 ------------------------------------------------------------

                float3 diffuseColor = NdotL * mainLight.color.rgb * _DiffuseColor.rgb;
                float3 lambertDiffuse = diffuseColor * diffuseThreshold; // エネルギー保存の法則による正規化無し

                // フレネル反射を考慮した拡散反射
                float3 viewDir = normalize(_WorldSpaceCameraPos - IN.positionWS);
                float fresnelDiffuse = CalcDiffuseFromFresnel(IN.normalWS, mainLight.direction, viewDir, roughness);

                float3 diffuse = lambertDiffuse * fresnelDiffuse;

                // メタリックに応じて環境光の影響を変化し、メインライトの色も少し加算
                half3 diffuseAmbient = SampleSH(IN.normalWS) * lerp(0.4, 1.0, diffuseThreshold) + mainLight.color.rgb * 0.1;

                // 合成
                half3 color = (diffuse + diffuseAmbient + specular + specularIBL) * albedo;

                // ガンマ補正はマテリアルパイプライン側で行うことが多い
                return half4(color, 1.0);
            }

            ENDHLSL
        }
    }
}

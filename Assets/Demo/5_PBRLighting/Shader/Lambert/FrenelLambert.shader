Shader "Custom/FrenelLambert"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}

        // 拡散反射
        _DiffuseColor("Diffuse Color", Color) = (1, 1, 1, 1) // 拡散反射の色

        // メタリック（PBR用）
        _Metallic("Metallic", Range(0.0, 1.0)) = 0.0
        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5
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

                // PBR用
                float _Metallic;
                float _Smoothness;
            CBUFFER_END

            // Fresnel Schlick
            float3 FresnelSchlick(float cosTheta, float F90, float3 F0)
            {
                // pow(1 - cos,5) は Schlick の近似
                return (F0 + (F90 - F0) * pow(1.0f - cosTheta, 5.0f));
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
                float FL = FresnelSchlick(dotNL, Fd90, F0).r;
                
                // 法線と視線に向かうベクトルを利用して拡散反射率を求める
                float dotNV = saturate(dot(N, V));
                float FV = FresnelSchlick(dotNV, Fd90, F0).r;
                
                // それぞれの拡散反射率を掛け合わせて、エネルギー保存の法則を満たすように正規化する
                return (FL * FV) * energyFactor;
            }

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
                float roughness = 1 - _Smoothness;
                
                half4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;

                float3 lightDir = normalize(mainLight.direction);
                float NdotL = saturate(dot(IN.normalWS, lightDir));
                float3 diffuseColor = NdotL * mainLight.color.rgb * _DiffuseColor.rgb;
                float3 lambertDiffuse = diffuseColor * diffuseThreshold; // エネルギー保存の法則による正規化無し

                // フレネル反射を考慮した拡散反射
                float3 viewDir = normalize(_WorldSpaceCameraPos - IN.positionWS);
                float fresnelDiffuse = CalcDiffuseFromFresnel(IN.normalWS, lightDir, viewDir, roughness);

                float3 diffuse = lambertDiffuse * fresnelDiffuse;

                // ----- 最低限の明るさを担保 -----
                // メタリックに応じて環境光の影響を変化し、メインライトの色も少し加算
                half3 ambient = SampleSH(IN.normalWS) * lerp(0.4, 1.0, diffuseThreshold) + mainLight.color.rgb * 0.1;
                
                return half4(diffuse + ambient, 1.0) * albedo;
            }
            ENDHLSL
        }
    }
}

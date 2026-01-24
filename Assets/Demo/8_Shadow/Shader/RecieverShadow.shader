Shader "Custom/RecieverShadow"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] [NoScaleOffset] _BaseMap("Albedo Map", 2D) = "white" {}
        [NoScaleOffset] _NormalMap("Normal Map", 2D) = "bump" {}

        [NoScaleOffset] _SpecularMap("Specular Map", 2D) = "white" {}
        [NoScaleOffset] _MetallicMap("Metallic Map", 2D) = "white" {}
        [NoScaleOffset] _AoMap("Ambient Occlusion Map", 2D) = "white" {}
        
        _SpecThreshold("Specular Threshold", Range(0.0, 200.0)) = 5.0 // 鏡面反射の強さ
        _SpecPower("Specular Power", Range(0.0, 10.0)) = 1.0 // 鏡面反射の強さ
        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5 // 滑らかさ
        _LimLightThreshold("Lim Light Threshold", Range(0.0, 10.0)) = 10.0 // リムライトの鋭さ
        _HemiLightThreshold("Hemi Light Threshold", Range(0.0, 1.0)) = 0 // 半球ライトの強さ
        _AmbientThreshold("Ambient Threshold", Range(0.0, 1.0)) = 1.0 // AOの強さ
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "Draw"
            Tags { "LightMode"="UniversalForward" }
            
            HLSLPROGRAM

            #pragma vertex PBRPassVertex
            #pragma fragment frag

            // 自作ライティング関数
            #include "Assets/ShaderLibrary/MyLitForwardPass.hlsl"
            #include "Assets/ShaderLibrary/Shadow/RecieverShadow.hlsl"

            half4 frag(Varyings IN) : SV_Target
            {
                half4 color = PBRPassFragment(IN);
                float shadowAttenuation = ShadowAttenuation(IN.positionWS.xyz);

                // TODO: 深度の取り方をperspectiveにすると薄くでやすい
                float shadow = lerp(1.0, 0.5, shadowAttenuation);
                color.rgb *= shadow;
                return color;
            }

            ENDHLSL
        }

        // テスト用
        Pass
        {
            Name "RecieverShadow"
            Tags { "LightMode" = "RecieverShadow" }

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Assets/ShaderLibrary/Shadow/RecieverShadow.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionWS : TEXCOORD;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                // メインカメラからの座標に描画
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);

                // ライト方向から見た座標を取得
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // 影の影響を取得
                half shadow = ShadowAttenuation(IN.positionWS.xyz);
                return half4(shadow, shadow, shadow, 1.0);
            }

            ENDHLSL
        }

        // 最後に影を反映するパスを用意？
    }
}

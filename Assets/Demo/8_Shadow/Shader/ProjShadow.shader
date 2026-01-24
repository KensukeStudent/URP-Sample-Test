Shader "Custom/ProjShadowShader"
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
            #pragma fragment PBRPassFragment

            // 自作ライティング関数
            #include "Assets/ShaderLibrary/MyLitForwardPass.hlsl"

            ENDHLSL
        }

        Pass
        {
            Name "DrawShadow"
            Tags { "LightMode"="ProjShadow" }

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag
            #include "Assets/ShaderLibrary/Shadow/DrawShadow.hlsl"

            ENDHLSL
        }

        // Pass
        // {
        //     Name "RecieverShadow"
        //     Tags { "LightMode" = "RecieverShadow" }
            
        //     HLSLPROGRAM

        //     #pragma vertex vert
        //     #pragma fragment frag
        //     #include "Assets/ShaderLibrary/Shadow/RecieverShadow.hlsl"

        //     ENDHLSL
        // }
    }
}

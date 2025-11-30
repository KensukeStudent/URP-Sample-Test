Shader "Custom/LitShader"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] [NoScaleOffset] _BaseMap("Albedo Map", 2D) = "white" {} // TODO: {}が無いと以下定義するとエラー発生する
        [NoScaleOffset] _NormalMap("Normal Map", 2D) = "white" {} // TODO: {}が無いと以下定義するとエラー発生する
        [NoScaleOffset] _SpecularMap("Specular Map", 2D) = "white" {} // TODO: {}が無いと以下定義するとエラー発生する
        [NoScaleOffset] _AoMap("Ambient Occlusion Map", 2D) = "white" {} // TODO: {}が無いと以下定義するとエラー発生する
        
        _SpecThreshold("Specular Threshold", Range(0.0, 200.0)) = 5.0 // 鏡面反射の強さ
        _SpecPower("Specular Power", Range(0.0, 10.0)) = 1.0 // 鏡面反射の強さ
        _LimLightThreshold("Lim Light Threshold", Range(0.0, 10.0)) = 10.0 // リムライトの鋭さ
        _HemiLightThreshold("Hemi Light Threshold", Range(0.0, 1.0)) = 0 // 半球ライトの強さ
        _AmbientPower("Ambient Power", Range(0.0, 1.0)) = 0.3 // 環境光の基準値
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex PBRPassVertex
            #pragma fragment PBRPassFragment

            // 自作ライティング関数
            #include "Assets/ShaderLibrary/MyLitForwardPass.hlsl"

            ENDHLSL
        }
    }
}

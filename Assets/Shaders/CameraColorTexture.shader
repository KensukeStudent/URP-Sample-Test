Shader "Custom/CameraColorTexture"
{
    Properties
    {
        _Color("Color", Color) = (0,0,0,1)
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass    // カメラカラーと合成
        {
            Name "CameraColorTexture"

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #pragma vertex Vert
            #pragma fragment Frag

            CBUFFER_START(UnityPerMaterial)
                float4 _Color;
            CBUFFER_END

            TEXTURE2D_X(_CameraTexture);

            half4 Frag(Varyings input) : SV_TARGET
            {
                float2 uv = input.texcoord.xy;
                return SAMPLE_TEXTURE2D_X(_CameraTexture, sampler_LinearClamp, uv) * _Color;
            }
            ENDHLSL
        }
    }
}

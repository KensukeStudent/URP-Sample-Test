Shader "Custom/DOFShader"
{
    Properties
    {
        _Threshold("Threshold", Range(0.0, 0.15)) = 0.15
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

            TEXTURE2D(_GaussTexture);
            TEXTURE2D(_CameraDepthTexture);

            CBUFFER_START(UnityPerMaterial)
                float _Threshold;
            CBUFFER_END

            half4 frag(Varyings input) : SV_Target
            {
                float depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_PointClamp, input.texcoord).r;
                float4 gauss = SAMPLE_TEXTURE2D(_GaussTexture, sampler_LinearClamp, input.texcoord);
                float4 camera = FragNearest(input);
                return depth < _Threshold ? gauss : camera;
            }
            ENDHLSL
        }
    }
}

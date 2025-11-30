// ---------------------------------------------------
// PBRライティング計算関数群
// ---------------------------------------------------

#ifndef MY_LIGHTING_INCLUDED
#define MY_LIGHTING_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Assets/ShaderLibrary/LightingInputData.hlsl"
#include "Assets/ShaderLibrary/MyInput.hlsl"
#include "Assets/ShaderLibrary/MySurfaceData.hlsl"

/// ランバート反射モデル計算関数
float3 CalcLambertDiffuse(float3 lightDirection, float3 lightColor, float3 normalWS)
{
    float NdotL = saturate(dot(normalWS, lightDirection));
    float3 diffuse = lightColor * NdotL;
    return diffuse /=  3.14159f; // ランバート反射モデルの正規化 ヘルムホルツの相反性
}

/// フォン鏡面反射モデル計算関数
float3 CalcPhongSpecular(float3 lightDirection, float3 lightColor, float3 positionWS, float3 normalWS, float specularThreshold)
{
    float3 reflectDir = lightDirection + 2 * dot(normalWS, -lightDirection) * normalWS;
    float3 viewDir = normalize(positionWS - _WorldSpaceCameraPos); // カメラからポリゴンへの方向
    float specular = dot(reflectDir, viewDir);
    specular = pow(saturate(specular), specularThreshold); // 適当な鏡面反射の強さ
    return lightColor * specular;
}

/// リムライト計算関数
float3 CalcLimLight(float3 lightDirection, float3 lightColor, float3 positionWS, float3 normalWS, float limLightThreshold)
{
    // ディレクショナルライトの入射角と法線からリムライトの強さ計算
    float power1 = 1.0f - max(0.0f, dot(lightDirection, normalWS));

    // 視線方向と法線からリムライトの強さ計算
    float3 viewDir = normalize(positionWS - _WorldSpaceCameraPos);
    float power2 = 1.0f - max(0.0f, dot(-viewDir, normalWS));

    float limPower = power1 * power2;
    limPower = pow(limPower, limLightThreshold); // リムライトの鋭さ調整
    return limPower * lightColor;
}

/// 最終ライティング計算関数
float3 MyUniversalFragmentPBR(MyInputData inputData, MySurfaceData surfaceData, LightingInputData lightInputData)
{
    float3 positionWS = inputData.positionWS;
    float3 normalWS = inputData.normalWS;

    float specularThreshold = lightInputData.specularThreshold;
    float limLightThreshold = lightInputData.limLightThreshold;
    float hemiLightThreshold = lightInputData.hemiLightThreshold;

    // ------------------------------- メインライトのライティング -------------------------------

    Light mainLight;
    mainLight = GetMainLight();

    // ランバート反射モデル
    float3 diffuseLight = CalcLambertDiffuse(mainLight.direction, mainLight.color, normalWS);
    // フォン反射モデル
    float3 specularLight = CalcPhongSpecular(mainLight.direction, mainLight.color, positionWS, normalWS, specularThreshold) * surfaceData.specular;
    // リムライト
    float3 limLight = CalcLimLight(mainLight.direction, mainLight.color, positionWS, normalWS, limLightThreshold);
    float3 directionLight = diffuseLight + specularLight + limLight;

    // ------------------------------- 追加のライティング(ポイントライト・スポットライトなど) -------------------------------
    Light addLight;
    int addLightCount = GetAdditionalLightsCount();
    float3 addFinalLight;

    for (int index = 0; index < addLightCount; index++) {
        addLight = GetAdditionalLight(index, positionWS);
        float3 addDiffuseLight = CalcLambertDiffuse(addLight.direction, addLight.color, normalWS);
        float3 addSpecularLight = CalcPhongSpecular(addLight.direction, addLight.color, positionWS, normalWS, specularThreshold) * surfaceData.specular;
        float3 addLimLight = CalcLimLight(addLight.direction, addLight.color, positionWS, normalWS, limLightThreshold);

        // 減衰を考慮したポイントライトの合成
        addDiffuseLight = addDiffuseLight * addLight.distanceAttenuation;
        addSpecularLight = addSpecularLight * addLight.distanceAttenuation;
        addLimLight = addLimLight * addLight.distanceAttenuation;

        addFinalLight += addDiffuseLight + addSpecularLight + addLimLight;
    }

    // ------------------------------- 半球ライト -------------------------------
    float3 skyColor = mainLight.color;
    float3 groundColor = float3(1,0,0); // 地面の色を赤
    float3 groundNormal = float3(0, 1, 0); // 地面の法線を真上

    float t = dot(normalWS, groundNormal);
    t = (t + 1.0) / 2; // [0,1]に変換

    float3 hemiLight = lerp(groundColor, skyColor, t);
    hemiLight = lerp(float3(0,0,0), hemiLight, hemiLightThreshold); // 半球ライトの有効/無効切り替え

    // ------------------------------- ライティングの合成 -------------------------------

    // 最終的なライティング計算
    float3 lig = directionLight + addFinalLight + hemiLight;
    lig += surfaceData.occlusion; // 間接光の影響を加算, TODO: この加算方法はデモ用
    return lig;
}

#endif
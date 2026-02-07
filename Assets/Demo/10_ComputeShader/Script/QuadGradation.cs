using UnityEngine;

public class QuadGradation : MonoBehaviour
{
    [SerializeField]
    private ComputeShader computeShader;

    [SerializeField]
    private RenderTexture renderTexture; // 256x256 = 65536ピクセル

    [SerializeField]
    private int lineWidth = 20;

    private void Start()
    {
        var material = GetComponent<Renderer>().material;
        material.SetTexture("_BaseMap", renderTexture);

        var kernelIndex = computeShader.FindKernel("CSMain");
        computeShader.SetTexture(kernelIndex, "Result", renderTexture);
    }

    private void Update()
    {
        computeShader.SetInt("LineWidth", lineWidth);

        var kernelIndex = computeShader.FindKernel("CSMain");
        computeShader.Dispatch(kernelIndex, renderTexture.width / 8, renderTexture.height / 8, 1);
    }

    void OnDestroy()
    {
        renderTexture.Release();
    }
}
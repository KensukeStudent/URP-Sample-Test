using UnityEngine;

public class QuadGauss : MonoBehaviour
{
    [SerializeField]
    private ComputeShader computeShader;

    [SerializeField]
    private RenderTexture renderTexture; // 512x512

    [SerializeField]
    private Texture2D sourceTexture;

    [SerializeField]
    private bool useXYBlur = true;

    private void Start()
    {
        if (useXYBlur)
        {
            XYBlur();
        }
        else
        {
            XToYBlur();
        }
    }

    private void XToYBlur()
    {
        Graphics.Blit(sourceTexture, renderTexture);

        var xBlurRender = CreateRenderTexture(512, 512);
        var yBlurRender = CreateRenderTexture(512, 512);

        float[] weights = CreateWeights(100.0f); // 分散具合

        Blur(weights, "XBlur", renderTexture, xBlurRender);
        Blur(weights, "YBlur", xBlurRender, yBlurRender);

        var material = GetComponent<Renderer>().material;
        material.SetTexture("_MainTex", yBlurRender);
    }

    private void XYBlur()
    {
        Graphics.Blit(sourceTexture, renderTexture);

        var xyBlurRender = CreateRenderTexture(512, 512);

        float[] weights = CreateWeights(100.0f); // 分散具合

        Blur(weights, "XYBlur", renderTexture, xyBlurRender);

        var material = GetComponent<Renderer>().material;
        material.SetTexture("_MainTex", xyBlurRender);
    }

    private RenderTexture CreateRenderTexture(int width, int height)
    {
        RenderTexture rt = new RenderTexture(
            width, height, 0,
            RenderTextureFormat.ARGB32,
            RenderTextureReadWrite.Linear
        );
        rt.enableRandomWrite = true;
        rt.Create();
        return rt;
    }

    /// <summary>
    /// ガウス分布の重みを計算して配列に格納する
    /// </summary>
    /// <param name="dispersion">分散具合。この数値が大きくなると分散具合が強くなる</param>
    private float[] CreateWeights(float dispersion)
    {
        float[] weights = new float[8];

        float total = 0;
        for (int i = 0; i < weights.Length; i++)
        {
            float pos = 1.0f + 2.0f * (float)i; // 左右対称となる位置 1,3,5,7
            weights[i] = Mathf.Exp(-0.5f * (float)(pos * pos) / dispersion); // ガウス分布の計算
            total += 2.0f * weights[i]; // 左右対称なので2倍する, 1であれば左右対称で左が1右が2となるようにi分計算
        }

        // weights[i] は片側8個分の重み。
        // シェーダーでは±の両側に使われ、計16個分の重みになるため、
        // 合計が1になるよう16個分として正規化する。
        for (int i = 0; i < weights.Length; i++)
        {
            weights[i] /= total;
        }

        return weights;
    }

    private void Blur(float[] weights, string kernelName, RenderTexture source, RenderTexture result)
    {
        ComputeBuffer weightBuffer = new ComputeBuffer(weights.Length, sizeof(float));
        weightBuffer.SetData(weights);

        var kernelIndex = computeShader.FindKernel(kernelName);
        computeShader.SetTexture(kernelIndex, "Source", source);
        computeShader.SetTexture(kernelIndex, "Result", result);
        computeShader.SetBuffer(kernelIndex, "Weights", weightBuffer);
        computeShader.Dispatch(kernelIndex, result.width / 8, result.height / 8, 1);
    }

    void OnDestroy()
    {
        renderTexture.Release();
    }
}
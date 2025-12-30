using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

/// <summary>
/// ブラーポストプロセス
/// </summary>
public class GaussRenderFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        public Material material = null;
    }

    [SerializeField] private Settings settings = new Settings();
    private GaussXRenderPass gaussXPass;
    //private CombinePass combinePass;

    [Header("ガウス分布パラメータ")]
    [SerializeField, Range(1, 10)]
    private float dispersion = 5;

    public override void Create()
    {
        this.gaussXPass = new GaussXRenderPass(
            this.settings.renderPassEvent,
            this.settings.material
        );

        // ガウス分布作成
        CreateWieght(dispersion * dispersion);
    }

    /// <summary>
    /// ガウス分布の重みを計算して配列に格納する
    /// </summary>
    /// <param name="dispersion">分散具合。この数値が大きくなると分散具合が強くなる</param>
    private void CreateWieght(float dispersion)
    {
        float[] wieghts = new float[8];

        float total = 0;
        for (int i = 0; i < wieghts.Length; i++)
        {
            float pos = 1.0f + 2.0f * (float)i; // 左右対称となる位置 1,3,5,7
            wieghts[i] = Mathf.Exp(-0.5f * (float)(pos * pos) / dispersion); // ガウス分布の計算
            total += 2.0f * wieghts[i]; // 左右対称なので2倍する, 1であれば左右対称で左が1右が2となるようにi分計算
        }

        // wieghts[i] は片側8個分の重み。
        // シェーダーでは±の両側に使われ、計16個分の重みになるため、
        // 合計が1になるよう16個分として正規化する。
        for (int i = 0; i < wieghts.Length; i++)
        {
            wieghts[i] /= total;
        }

        ComputeBuffer weightBuffer = new ComputeBuffer(wieghts.Length, sizeof(float));
        weightBuffer.SetData(wieghts);
        settings.material.SetBuffer("_Weights", weightBuffer);

        Debug.Log("Gauss Weights: " + string.Join(", ", wieghts));
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        // EnqueuePass is still required so that the ScriptableRenderer
        // will know which passes to call RecordRenderGraph on
        renderer.EnqueuePass(this.gaussXPass);
        //renderer.EnqueuePass(this.combinePass);
    }

    protected override void Dispose(bool disposing)
    {
        // Use Dispose for cleanup
    }

    // ------------------------------------------------
    // Render Pass Class 
    // ------------------------------------------------

    public class GaussXRenderPass : ScriptableRenderPass
    {
        private Material material;

        private class PassData
        {
            public TextureHandle sourceTextureHandle;
            public Material material;
        }

        public GaussXRenderPass(RenderPassEvent renderPassEvent, Material material)
        {
            this.renderPassEvent = renderPassEvent;
            this.material = material;
            this.profilingSampler = new ProfilingSampler(nameof(GaussXRenderPass));
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            // Recording phase; add passes to RenderGraph

            // FrameData objects
            // ResourceData
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
            // CameraData
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();

            // ------------------------------------------------------------ 
            // camera -> gaussX texture
            // ------------------------------------------------------------

            // 横サイズは半分のテクスチャー: ダウンサンプリング
            // 16:9 -> 8:9
            RenderTextureDescriptor desc = cameraData.cameraTargetDescriptor;
            desc.colorFormat = RenderTextureFormat.ARGB32; // Enable alpha
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            desc.height = Screen.height;
            desc.width = Screen.width / 2;

            TextureHandle cameraColorTextureHandler = resourceData.activeColorTexture;

            // X方向ブラー用テクスチャ作成
            TextureHandle gaussXTextureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_GaussXTexture", true, FilterMode.Bilinear);

            // camera color RT -> gaussXTexture RT
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                builder.UseTexture(cameraColorTextureHandler, AccessFlags.Read);

                builder.SetRenderAttachment(gaussXTextureHandle, 0, AccessFlags.Write);

                // Resources/References for pass execution
                // Blit source texture
                passData.sourceTextureHandle = cameraColorTextureHandler;
                // Blit material
                passData.material = material;

                // Set render function
                // X方向ブラー: 0パス目を使用
                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
                {
                    RasterCommandBuffer cmd = graphContext.cmd;

                    Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), passData.material, 0);
                });
            }

            // ------------------------------------------------------------ 
            // gaussX texture -> gaussY texture
            // ------------------------------------------------------------

            // 横サイズは半分のテクスチャー: ダウンサンプリング
            // 8:9 -> 8:4.5
            desc = cameraData.cameraTargetDescriptor;
            desc.colorFormat = RenderTextureFormat.ARGB32; // Enable alpha
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            desc.height = Screen.height / 2;
            desc.width = Screen.width / 2;

            // Y方向ブラー用テクスチャ作成
            TextureHandle gaussYTextureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_GaussYTexture", true, FilterMode.Bilinear);

            // gaussXTexture RT -> gaussYTexture RT
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                builder.UseTexture(gaussXTextureHandle, AccessFlags.Read);

                builder.SetRenderAttachment(gaussYTextureHandle, 0, AccessFlags.Write);

                // Resources/References for pass execution
                // Blit source texture
                passData.sourceTextureHandle = gaussXTextureHandle;
                // Blit material
                passData.material = material;

                // Set render function
                // Y方向ブラー: 1パス目を使用
                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
                {
                    RasterCommandBuffer cmd = graphContext.cmd;

                    Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), passData.material, 1);
                });
            }

            // gaussYTexture RT -> camera color RT
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                // Set tempRT for read
                builder.UseTexture(gaussYTextureHandle, AccessFlags.Read);
                // Set camera color RT for write
                builder.SetRenderAttachment(cameraColorTextureHandler, 0, AccessFlags.Write);

                // Resources/References for pass execution
                // Blit source texture
                passData.sourceTextureHandle = gaussYTextureHandle;
                passData.material = null;

                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
                {
                    RasterCommandBuffer cmd = graphContext.cmd;
                    Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), 0, false);
                });
            }
        }
    }
}

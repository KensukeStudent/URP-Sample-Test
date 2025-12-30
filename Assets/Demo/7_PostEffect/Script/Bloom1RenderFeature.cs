using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

/// <summary>
/// ブラーポストプロセス
/// </summary>
public class Bloom1RenderFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        public Material material = null;
    }

    [SerializeField] private Settings settings = new Settings();
    private Bloom1RenderPass bloomPass;

    [SerializeField]
    private Material gaussMaterial = null;

    [Header("ガウス分布パラメータ")]
    [SerializeField, Range(1, 10)]
    private float dispersion = 5;

    private GaussRenderer gaussRenderer;

    public override void Create()
    {
        gaussRenderer = new GaussRenderer(gaussMaterial, dispersion);

        this.bloomPass = new Bloom1RenderPass(
            this.settings.renderPassEvent,
            this.settings.material,
            gaussRenderer
        );
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(this.bloomPass);
    }

    protected override void Dispose(bool disposing)
    {
        // Use Dispose for cleanup
    }

    // ------------------------------------------------
    // Render Pass Class 
    // ------------------------------------------------

    public class Bloom1RenderPass : ScriptableRenderPass
    {
        private Material material;
        private GaussRenderer gaussRenderer;

        private class PassData
        {
            public TextureHandle sourceTextureHandle;
            public Material material;
        }

        public Bloom1RenderPass(RenderPassEvent renderPassEvent, Material material, GaussRenderer gaussRenderer)
        {
            this.renderPassEvent = renderPassEvent;
            this.material = material;
            this.gaussRenderer = gaussRenderer;
            this.profilingSampler = new ProfilingSampler(nameof(Bloom1RenderPass));
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            // Recording phase; add passes to RenderGraph

            // FrameData objects
            // ResourceData
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
            // RenderingData
            UniversalRenderingData renderingData = frameData.Get<UniversalRenderingData>();
            // CameraData
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();
            // LightData
            UniversalLightData lightData = frameData.Get<UniversalLightData>();

            // ------------------------------------------------------------ 
            // camera -> luminance texture
            // ------------------------------------------------------------

            // テクスチャー情報
            // 16:9
            RenderTextureDescriptor desc = cameraData.cameraTargetDescriptor;
            desc.colorFormat = RenderTextureFormat.ARGBFloat; // Enable alpha
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            desc.height = Screen.height;
            desc.width = Screen.width;

            TextureHandle cameraColorTextureHandler = resourceData.activeColorTexture;

            // 輝度テクスチャー
            TextureHandle luminanceTextureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_LuminanceTexture", true, FilterMode.Point);

            // camera color RT -> luminanceTexture RT
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                builder.UseTexture(cameraColorTextureHandler, AccessFlags.Read);

                builder.SetRenderAttachment(luminanceTextureHandle, 0, AccessFlags.Write);

                // Resources/References for pass execution
                // Blit source texture
                passData.sourceTextureHandle = cameraColorTextureHandler;
                // Blit material
                passData.material = material;

                // 0パス目を使用
                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
                {
                    RasterCommandBuffer cmd = graphContext.cmd;
                    Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), passData.material, 0);
                });
            }

            // ------------------------------------------------------------ 
            // luminance texture -> gauss texture x4
            // ------------------------------------------------------------

            // グローバル変数用登録 indexは0から始まるので注意
            // _GaussTexture0 ～ _GaussTexture3
            TextureHandle gaussTextureTargetHandle = luminanceTextureHandle;
            for (int i = 0; i < 4; i++)
            {
                gaussRenderer.RecordRenderGraph(renderGraph, cameraData.cameraTargetDescriptor, gaussTextureTargetHandle, Shader.PropertyToID("_GaussTexture" + i));
                gaussTextureTargetHandle = gaussRenderer.TextureHandle;
            }

            // ------------------------------------------------------------ 
            // camera color texture -> bloom texture
            // ------------------------------------------------------------

            // ブルームテクスチャー
            TextureHandle bloomTextureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_BloomTexture", true, FilterMode.Point);

            // camera color RT -> bloom texture
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                builder.UseTexture(cameraColorTextureHandler, AccessFlags.Read);

                builder.SetRenderAttachment(bloomTextureHandle, 0, AccessFlags.Write);

                // Resources/References for pass execution
                // Blit source texture
                passData.sourceTextureHandle = cameraColorTextureHandler;
                // Blit material
                passData.material = material;

                // 1パス目を使用
                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
                {
                    RasterCommandBuffer cmd = graphContext.cmd;
                    Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), passData.material, 1);
                });
            }

            // ------------------------------------------------------------ 
            // bloom texture -> camera color texture
            // ------------------------------------------------------------

            // bloom texture RT -> camera color RT
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                // Set tempRT for read
                builder.UseTexture(bloomTextureHandle, AccessFlags.Read);
                // Set camera color RT for write
                builder.SetRenderAttachment(cameraColorTextureHandler, 0, AccessFlags.Write);

                // Resources/References for pass execution
                // Blit source texture
                passData.sourceTextureHandle = bloomTextureHandle;
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

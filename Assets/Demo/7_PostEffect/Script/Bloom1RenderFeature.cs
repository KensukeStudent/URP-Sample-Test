using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;
using System.Collections.Generic;

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

    [Header("ガウス分布パラメータ")]
    [SerializeField, Range(1, 10)]
    private float dispersion = 5;

    public override void Create()
    {
        this.bloomPass = new Bloom1RenderPass(
            this.settings.renderPassEvent,
            this.settings.material
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
        private List<ShaderTagId> shaderTagIds = new List<ShaderTagId>()
        {
            new ShaderTagId("UniversalForward"),
            new ShaderTagId("UniversalForwardOnly"),
            new ShaderTagId("SRPDefaultUnlit"),
        };

        private class PassData
        {
            public RendererListHandle rendererListHandle;
            public TextureHandle sourceTextureHandle;
            public Material material;
        }

        public Bloom1RenderPass(RenderPassEvent renderPassEvent, Material material)
        {
            this.renderPassEvent = renderPassEvent;
            this.material = material;
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

            #region DrawRenderersPass

            // // テクスチャ作成
            // TextureHandle drawTextureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_DrawTexture", true, FilterMode.Point);

            // // Sorting criteria (default transparent)
            // SortingCriteria sortingCriteria = cameraData.defaultOpaqueSortFlags;

            // // Drawing settings
            // DrawingSettings drawingSettings = RenderingUtils.CreateDrawingSettings(this.shaderTagIds, renderingData, cameraData, lightData, sortingCriteria);

            // // RendererListHandle
            // var filteringSettings = new FilteringSettings(RenderQueueRange.opaque, -1);
            // RendererListParams rendererListParams = new RendererListParams(renderingData.cullResults, drawingSettings, filteringSettings);

            // // Pass to draw renderers
            // // Blitter.BlitTextureは使用できないようだ
            // using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            // {
            //     passData.rendererListHandle = renderGraph.CreateRendererList(rendererListParams);

            //     // Set pass to use rendererListHandle
            //     builder.UseRendererList(passData.rendererListHandle);

            //     // Set render target (custom render target)
            //     builder.SetRenderAttachment(drawTextureHandle, 0, AccessFlags.Write);

            //     // 必ず実行必要パス
            //     builder.AllowPassCulling(false);

            //     // Set render function
            //     builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
            //     {
            //         RasterCommandBuffer cmd = graphContext.cmd;
            //         // Draw renderer list
            //         cmd.DrawRendererList(passData.rendererListHandle);
            //     });
            // }
            
#endregion


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

            // luminanceTexture RT -> GaussTexture RT
            // 元サイズから半分サイズに縮小

            // gaussYTexture RT -> camera color RT
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                // Set tempRT for read
                builder.UseTexture(luminanceTextureHandle, AccessFlags.Read);
                // Set camera color RT for write
                builder.SetRenderAttachment(cameraColorTextureHandler, 0, AccessFlags.Write);

                // Resources/References for pass execution
                // Blit source texture
                passData.sourceTextureHandle = luminanceTextureHandle;
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

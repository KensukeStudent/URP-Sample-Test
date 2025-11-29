using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RendererUtils;
using System.Collections.Generic;

/// <summary>
/// 法線を使ったエッジポストプロセス
/// </summary>
public class NormalBufferRenderFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        public Material material = null;
    }

    [SerializeField] private Settings settings = new Settings();
    private NormalBufferRenderPass renderPass;
    private CombinePass combinePass;

    public override void Create()
    {
        this.renderPass = new NormalBufferRenderPass(
            this.settings.renderPassEvent,
            this.settings.material
        );

        this.combinePass = new CombinePass(
            this.settings.renderPassEvent,
            this.settings.material
        );
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        // EnqueuePass is still required so that the ScriptableRenderer
        // will know which passes to call RecordRenderGraph on
        renderer.EnqueuePass(this.renderPass);
        renderer.EnqueuePass(this.combinePass);
    }

    protected override void Dispose(bool disposing)
    {
        // Use Dispose for cleanup
    }

    public class NormalBufferRenderPass : ScriptableRenderPass
    {
        private Material material;

        private List<ShaderTagId> shaderTagIds;

        private class PassData
        {
            // 指定のshader pass描画
            public RendererListHandle rendererListHandle;

            public TextureHandle sourceTextureHandle;
            public Material material;
        }

        public NormalBufferRenderPass(RenderPassEvent renderPassEvent, Material material)
        {
            this.renderPassEvent = renderPassEvent;
            this.material = material;
            this.profilingSampler = new ProfilingSampler(nameof(NormalBufferRenderPass));

            // Target material shader pass names
            this.shaderTagIds = new List<ShaderTagId>
            {
                new ShaderTagId("NormalEdge")
            };
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

            // Camera RT descriptor
            RenderTextureDescriptor desc = cameraData.cameraTargetDescriptor;
            desc.colorFormat = RenderTextureFormat.ARGB32; // Enable alpha
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;

            TextureHandle activeColorTextureHandler = resourceData.activeColorTexture;

            // TextureHandle for render target
            // UniversalRenderer.CreateRenderGraphTexture is a helper method to create RenderGraph TextureHandle
            TextureHandle normalTextureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_NormalTexture", true);

            // Sorting criteria (default transparent)
            SortingCriteria sortingCriteria = cameraData.defaultOpaqueSortFlags;

            // Drawing settings
            DrawingSettings drawingSettings = RenderingUtils.CreateDrawingSettings(this.shaderTagIds, renderingData, cameraData, lightData, sortingCriteria);

            // RendererListHandle
            var filteringSettings = new FilteringSettings(RenderQueueRange.opaque, -1);
            RendererListParams rendererListParams = new RendererListParams(renderingData.cullResults, drawingSettings, filteringSettings);

            // Pass to draw renderers
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                passData.rendererListHandle = renderGraph.CreateRendererList(rendererListParams);

                // Set pass to use rendererListHandle
                builder.UseRendererList(passData.rendererListHandle);

                // Set render target (custom render target)
                builder.SetRenderAttachment(normalTextureHandle, 0, AccessFlags.Write);

                // Disable pass culling
                // Passes are culled if no other passes access the write target
                // For example, if only a shader accesses the render target texture (and not a separate pass),
                // we need to disable pass culling to ensure this pass will always run
                builder.AllowPassCulling(false);

                // Set render function
                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
                {
                    RasterCommandBuffer cmd = graphContext.cmd;
                    // Draw renderer list
                    cmd.DrawRendererList(passData.rendererListHandle);
                });
            }

            TextureHandle normalEdgeTextureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_NormalEdgeTexture", true);
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                builder.SetRenderAttachment(normalEdgeTextureHandle, 0, AccessFlags.Write);
                builder.UseTexture(normalTextureHandle, AccessFlags.Read);

                // ShaderのGlobal変数への設定ができるように
                // 要注意！
                builder.AllowGlobalStateModification(true);
                // 解説 *2
                // negativeTextureHandleが描画された後に、"_NormalEdgeTexture"という名前のGlobalTextureに設定する
                builder.SetGlobalTextureAfterPass(normalEdgeTextureHandle, Shader.PropertyToID("_NormalEdgeTexture"));

                // Resources/References for pass execution
                // Blit source texture
                passData.sourceTextureHandle = normalTextureHandle;
                // Blit material
                passData.material = material;

                // Set render function
                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
                {
                    RasterCommandBuffer cmd = graphContext.cmd;
                    Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), passData.material, 0);
                });
            }
        }
    }

    // ------------------------------------------------------------------
    // CombinePass
    // ------------------------------------------------------------------

    public class CombinePass : ScriptableRenderPass
    {
        private Material _material;

        private class PassData
        {
            public Material Material;
            public TextureHandle sourceTextureHandle;
        }

        public CombinePass(RenderPassEvent renderPassEvent, Material material)
        {
            this.renderPassEvent = renderPassEvent;
            this.profilingSampler = new ProfilingSampler(nameof(CombinePass));
            _material = material;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var resourceData = frameData.Get<UniversalResourceData>();
            var sourceTextureHandle = resourceData.activeColorTexture;

            // 現在アクティブのカメラカラーを元に、合成テクスチャを作成
            var targetDesc = renderGraph.GetTextureDesc(sourceTextureHandle);
            targetDesc.name = "_CombineTexture";
            targetDesc.clearBuffer = false;
            targetDesc.depthBufferBits = 0;
            var combineTextureHandle = renderGraph.CreateTexture(targetDesc);

            // 合成したテクスチャをカメラカラーに設定
            resourceData.cameraColor = combineTextureHandle;

            // カメラカラーを反転し、出力用のテクスチャに描画するRasterRenderPassを作成し、RenderGraphに追加
            using (var builder = renderGraph.AddRasterRenderPass<PassData>("CombinePass", out var passData))
            {
                // 描画ターゲット設定
                builder.SetRenderAttachment(combineTextureHandle, 0, AccessFlags.Write);
                builder.UseTexture(sourceTextureHandle, AccessFlags.Read);

                // GlobalTextureの使用宣言
                builder.UseGlobalTexture(Shader.PropertyToID("_NormalEdgeTexture"), AccessFlags.Read);

                // passDataに必要なデータを入れる
                passData.Material = _material;
                passData.sourceTextureHandle = sourceTextureHandle;

                // すべてのGlobalTextureを使用申請
                // builder.UseAllGlobalTexture(true);
                builder.SetRenderFunc(static (PassData data, RasterGraphContext context) => ExecutePass(data, context));
            }
        }

        private static void ExecutePass(PassData passData, RasterGraphContext graphContext)
        {
            RasterCommandBuffer cmd = graphContext.cmd;
            Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), passData.Material, 1);
        }
    }
}

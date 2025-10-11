using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

public class DepthBufferRenderFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        public Material material = null;
    }

    [SerializeField] private Settings settings = new Settings();
    private DepthBufferRenderPass renderPass;
    private CombinePass combinePass;

    public override void Create()
    {
        this.renderPass = new DepthBufferRenderPass(
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

    public class DepthBufferRenderPass : ScriptableRenderPass
    {
        private Material material;

        private class PassData
        {
            public TextureHandle sourceTextureHandle;
            public Material material;
        }

        public DepthBufferRenderPass(RenderPassEvent renderPassEvent, Material material)
        {
            this.renderPassEvent = renderPassEvent;
            this.material = material;

            this.profilingSampler = new ProfilingSampler(nameof(DepthBufferRenderPass));
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();

            // TextureHandle for camera color RT
            TextureHandle cameraDepthTextureHandle = resourceData.activeDepthTexture;

            // Camera RT descriptor
            RenderTextureDescriptor desc = cameraData.cameraTargetDescriptor;
            desc.depthBufferBits = 0;
            desc.msaaSamples = 1;

            // camera -> depthTexture
            TextureHandle depthTextureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_DepthEdgeTexture", true);
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                builder.SetRenderAttachment(depthTextureHandle, 0, AccessFlags.Write);
                builder.UseTexture(cameraDepthTextureHandle, AccessFlags.Read);

                // ShaderのGlobal変数への設定ができるように
                // 要注意！
                builder.AllowGlobalStateModification(true);
                // 解説 *2
                // negativeTextureHandleが描画された後に、"_NegativeTexture"という名前のGlobalTextureに設定する
                builder.SetGlobalTextureAfterPass(depthTextureHandle, Shader.PropertyToID("_DepthEdgeTexture"));

                // Resources/References for pass execution
                // Blit source texture
                passData.sourceTextureHandle = cameraDepthTextureHandle;
                // Blit material
                passData.material = material;

                // Set render function
                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) => ExecutePass(passData, graphContext));
            }
        }

        private static void ExecutePass(PassData passData, RasterGraphContext graphContext)
        {
            RasterCommandBuffer cmd = graphContext.cmd;
            Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), passData.material, 0);
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
                builder.UseGlobalTexture(Shader.PropertyToID("_DepthEdgeTexture"), AccessFlags.Read);

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

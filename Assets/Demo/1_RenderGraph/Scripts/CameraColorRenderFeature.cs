using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

/// <summary>
/// シェーダーパラメーターからカメラカラーを出力する
/// </summary>
public class CameraColorRenderFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        public Material material = null;
    }

    [SerializeField] private Settings settings = new Settings();
    private CameraColorRenderPass renderPass;
    private CombinePass combinePass;

    public override void Create()
    {
        this.renderPass = new CameraColorRenderPass(
            this.settings.renderPassEvent
        );

        combinePass = new CombinePass(
            RenderPassEvent.AfterRenderingPostProcessing,
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
        // if (disposing)
        // {
        //     CoreUtils.Destroy(settings.material);
        // }
    }

    public class CameraColorRenderPass : ScriptableRenderPass
    {
        private static readonly int CameraTexturePropertyId = Shader.PropertyToID("_CameraTexture");

        // パスを実行（ダウンサンプリング処理）するために必要なパラメータを渡すためのクラス
        private class PassData
        {
            public TextureHandle sourceTextureHandle;
        }

        public CameraColorRenderPass(RenderPassEvent renderPassEvent)
        {
            this.renderPassEvent = renderPassEvent;
            this.profilingSampler = new ProfilingSampler(nameof(CameraColorRenderPass));
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var resourceData = frameData.Get<UniversalResourceData>();
            var cameraData = frameData.Get<UniversalCameraData>();

            var cameraColorTextureHandle = resourceData.activeColorTexture;

            RenderTextureDescriptor desc = cameraData.cameraTargetDescriptor;
            desc.depthBufferBits = 0;
            desc.msaaSamples = 1;

            // cameraTextureHandleへの書き込み / カメラへの書き込みはしていない
            var cameraTextureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_CameraTexture", true);
            using (var builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, profilingSampler))
            {
                // カメラのテクスチャは読み取り設定
                builder.UseTexture(cameraColorTextureHandle, AccessFlags.Read);

                // 描画ターゲット設定
                builder.SetRenderAttachment(cameraTextureHandle, 0, AccessFlags.Write);

                // 解説 *1
                // ShaderのGlobal変数への設定ができるように
                // 要注意！
                builder.AllowGlobalStateModification(true);
                // 解説 *2
                // cameraTextureHandleが描画された後に、"_CameraTexture"という名前のGlobalTextureに設定する
                builder.SetGlobalTextureAfterPass(cameraTextureHandle, CameraTexturePropertyId);

                passData.sourceTextureHandle = cameraColorTextureHandle;

                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) => ExecutePass(passData, graphContext));
            }
        }

        private static void ExecutePass(PassData passData, RasterGraphContext graphContext)
        {
            RasterCommandBuffer cmd = graphContext.cmd;
            Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), 0, false);
        }
    }

    // ------------------------------------------------------------------
    // CombinePass
    // ------------------------------------------------------------------

    public class CombinePass : ScriptableRenderPass
    {
        private static readonly int CameraTexturePropertyId = Shader.PropertyToID("_CameraTexture");

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
                // passDataに必要なデータを入れる
                passData.Material = _material;
                passData.sourceTextureHandle = sourceTextureHandle;

                // 描画ターゲット設定
                builder.SetRenderAttachment(combineTextureHandle, 0, AccessFlags.Write);
                builder.UseTexture(sourceTextureHandle, AccessFlags.Read);
                // 解説 *5
                // GlobalTextureの使用宣言
                builder.UseGlobalTexture(CameraTexturePropertyId, AccessFlags.Read);
                // 解説 *6
                // すべてのGlobalTextureを使用申請
                // builder.UseAllGlobalTexture(true);
                builder.SetRenderFunc(static (PassData data, RasterGraphContext context) => ExecutePass(data, context));
            }
        }

        private static void ExecutePass(PassData passData, RasterGraphContext graphContext)
        {
            RasterCommandBuffer cmd = graphContext.cmd;
            Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), passData.Material, 0);
        }
    }
}

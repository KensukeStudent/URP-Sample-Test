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

    public override void Create()
    {
        this.renderPass = new CameraColorRenderPass(
            this.settings.renderPassEvent,
            this.settings.material
        );
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        // EnqueuePass is still required so that the ScriptableRenderer
        // will know which passes to call RecordRenderGraph on
        renderer.EnqueuePass(this.renderPass);
    }

    protected override void Dispose(bool disposing)
    {
        // Use Dispose for cleanup

        //this.renderPass.Dispose();
    }

    public class CameraColorRenderPass : ScriptableRenderPass
    {
        private static readonly int CameraTexturePropertyId = Shader.PropertyToID("_CameraTexture");
        private Material material;

        // パスを実行（ダウンサンプリング処理）するために必要なパラメータを渡すためのクラス
        private class PassData
        {
            public TextureHandle sourceTextureHandle;
            public Material material;
        }

        public CameraColorRenderPass(RenderPassEvent renderPassEvent, Material material)
        {
            this.renderPassEvent = renderPassEvent;
            this.material = material;

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
                // builder.UseGlobalTexture(CameraTexturePropertyId, AccessFlags.Read);

                passData.sourceTextureHandle = cameraColorTextureHandle;
                passData.material = null;

                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) => ExecutePass(passData, graphContext));
            }

            // さらにcameraTextureHandleへの書き込み
            using (var builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, profilingSampler))
            {
                // カメラのテクスチャは読み取り設定
                builder.UseTexture(cameraTextureHandle, AccessFlags.Read);
                builder.UseGlobalTexture(CameraTexturePropertyId, AccessFlags.Read);

                // 描画ターゲット設定
                builder.SetRenderAttachment(cameraColorTextureHandle, 0, AccessFlags.Write);

                passData.sourceTextureHandle = cameraTextureHandle;
                passData.material = null;

                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) => ExecutePass(passData, graphContext));
            }
        }

        private static void ExecutePass(PassData passData, RasterGraphContext graphContext)
        {
            RasterCommandBuffer cmd = graphContext.cmd;
            // Blit
            if (passData.material == null)
            {
                // If no material specified
                Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), 0, false);
            }
            else
            {
                Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), passData.material, 0);
            }
        }
    }
}

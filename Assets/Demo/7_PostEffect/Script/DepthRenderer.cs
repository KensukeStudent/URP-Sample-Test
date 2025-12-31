using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

public class DepthRenderer
{
    private ProfilingSampler profilingSampler;

    private TextureHandle depthTextureHandle;
    public TextureHandle TextureHandle => depthTextureHandle;

    private Material material;

    private class PassData
    {
        public TextureHandle sourceTextureHandle;
        public Material material;
    }

    public DepthRenderer()
    {
        // Resourcesから動的読み込み
        material = Resources.Load<Material>("CameraDepth");
    }

    /// <summary>
    /// カメラ深度取得実行
    /// </summary>
    public void RecordRenderGraph(RenderGraph renderGraph, RenderTextureDescriptor cameraTargetDescriptor, TextureHandle sourceTextureHandle)
    {
        // TextureHandle作成
        CreateTextureHandle(renderGraph, cameraTargetDescriptor);

        using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass("CameraDepth", out PassData passData, this.profilingSampler))
        {
            builder.UseTexture(sourceTextureHandle, AccessFlags.Read);
            builder.SetRenderAttachment(depthTextureHandle, 0, AccessFlags.Write);

            // ShaderのGlobal変数への設定ができるように
            // 要注意！
            builder.AllowGlobalStateModification(true);
            // 解説 *2
            // negativeTextureHandleが描画された後に、"_NegativeTexture"という名前のGlobalTextureに設定する
            builder.SetGlobalTextureAfterPass(depthTextureHandle, Shader.PropertyToID("_CameraDepthTexture"));

            // Resources/References for pass execution
            // Blit source texture
            passData.sourceTextureHandle = sourceTextureHandle;
            passData.material = material;

            builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
            {
                RasterCommandBuffer cmd = graphContext.cmd;
                Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), passData.material, 0);
            });
        }
    }

    private void CreateTextureHandle(RenderGraph renderGraph, RenderTextureDescriptor cameraTargetDescriptor)
    {
        // 横サイズは半分のテクスチャー: ダウンサンプリング
        RenderTextureDescriptor desc = cameraTargetDescriptor;
        desc.colorFormat = RenderTextureFormat.ARGB32; // Enable alpha
        desc.msaaSamples = 1;
        desc.depthBufferBits = 0;

        depthTextureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_CameraDepthTexture", true);
    }
}

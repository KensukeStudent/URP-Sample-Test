using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class DataTransferRendererFeature : ScriptableRendererFeature
{
    [SerializeField]
    private Vector2 center = new(0.5f, 0.5f);
    [SerializeField]
    private float radius = 0.5f;

    private const string ShaderPath = "Hidden/Sample/DataTransfer";
    private Material _material;
    private Material material
    {
        get
        {
            if (_material == null)
            {
                _material = CoreUtils.CreateEngineMaterial(ShaderPath);
            }
            return _material;
        }
    }

    private DrawNegativePass _drawNegativePass;
    private CombinePass _combinePass;

    public override void Create()
    {
        _drawNegativePass = new DrawNegativePass
        {
            renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing
        };
        _combinePass = new CombinePass
        {
            renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (renderingData.cameraData.cameraType == CameraType.Preview)
        {
            // Previewカメラがエフェクトの対象外なので、除外する
            return;
        }

        _drawNegativePass.SetData(material, center, radius);
        _combinePass.SetData(material);

        renderer.EnqueuePass(_drawNegativePass);
        renderer.EnqueuePass(_combinePass);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            CoreUtils.Destroy(material);
        }
    }

    // ------------------------------------------------------------------
    // DrawNegativePass
    // ------------------------------------------------------------------

    public class DrawNegativePass : ScriptableRenderPass
    {
        private static readonly int NegativeTexturePropertyId = Shader.PropertyToID("_NegativeTexture");
        private static readonly int ParamsPropertyId = Shader.PropertyToID("_Params");

        private Material _material;
        private Vector2 _center;
        private float _radius;

        public void SetData(Material material, Vector2 center, float radius)
        {
            _material = material;
            _center = center;
            _radius = radius;
        }
        private class PassData
        {
            internal Material Material;
            internal TextureHandle SourceTexture;
            //internal TextureHandle NegativeTexture;
            internal Vector4 Params;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var cameraData = frameData.Get<UniversalCameraData>();
            var resourceData = frameData.Get<UniversalResourceData>();

            var sourceTextureHandle = resourceData.activeColorTexture;
            var aspectRatio = cameraData.cameraTargetDescriptor.width / (float)cameraData.cameraTargetDescriptor.height;

            var negativeDescriptor = renderGraph.GetTextureDesc(sourceTextureHandle);
            negativeDescriptor.name = "_NegativeTexture";
            negativeDescriptor.clearBuffer = false;
            negativeDescriptor.msaaSamples = MSAASamples.None;
            negativeDescriptor.depthBufferBits = 0;

            var negativeTextureHandle = renderGraph.CreateTexture(negativeDescriptor);

            // カメラカラーを反転し、出力用のテクスチャに描画するRasterRenderPassを作成し、RenderGraphに追加
            using (var builder = renderGraph.AddRasterRenderPass<PassData>("DrawNegativePass", out var passData))
            {
                // passDataに必要なデータを入れる
                passData.Material = _material;
                passData.SourceTexture = sourceTextureHandle;
                //passData.NegativeTexture = negativeTextureHandle;
                passData.Params = new Vector4(_center.x, _center.y, _radius, aspectRatio);

                // 描画ターゲット設定
                builder.SetRenderAttachment(negativeTextureHandle, 0, AccessFlags.Write);
                builder.UseTexture(sourceTextureHandle, AccessFlags.Read);
                // 解説 *1
                // ShaderのGlobal変数への設定ができるように
                // 要注意！
                builder.AllowGlobalStateModification(true);
                // 解説 *2
                // negativeTextureHandleが描画された後に、"_NegativeTexture"という名前のGlobalTextureに設定する
                builder.SetGlobalTextureAfterPass(negativeTextureHandle, NegativeTexturePropertyId);
                builder.SetRenderFunc(static (PassData data, RasterGraphContext context) =>
                {
                    var cmd = context.cmd;
                    var material = data.Material;
                    var source = data.SourceTexture;
                    var parameters = data.Params;

                    Blitter.BlitTexture(cmd, source, Vector2.one, material, 0);

                    // 解説 *3
                    // Texture以外の変数は描画関数内でCommandBufferを使ってGlobalに設定する
                    cmd.SetGlobalVector(ParamsPropertyId, parameters);

                    // 解説 *4
                    // Textureでもは描画関数内でCommandBufferを使ってGlobalに設定できるが、RenderGraphViewerに検知されないため非推奨
                    //cmd.SetGlobalTexture(NegativeTexturePropertyId, data.NegativeTexture);
                });
            }
        }
    }

    // ------------------------------------------------------------------
    // CombinePass
    // ------------------------------------------------------------------

    public class CombinePass : ScriptableRenderPass
    {
        private static readonly int NegativeTexturePropertyId = Shader.PropertyToID("_NegativeTexture");

        private Material _material;

        public void SetData(Material material)
        {
            _material = material;
        }
        private class PassData
        {
            internal Material Material;
            internal TextureHandle SourceTexture;
            internal Vector4 Params;
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
                passData.SourceTexture = sourceTextureHandle;

                // 描画ターゲット設定
                builder.SetRenderAttachment(combineTextureHandle, 0, AccessFlags.Write);
                builder.UseTexture(sourceTextureHandle, AccessFlags.Read);
                // 解説 *5
                // GlobalTextureの使用宣言
                builder.UseGlobalTexture(NegativeTexturePropertyId, AccessFlags.Read);
                // 解説 *6
                // すべてのGlobalTextureを使用申請
                // builder.UseAllGlobalTexture(true);
                builder.SetRenderFunc(static (PassData data, RasterGraphContext context) =>
                {
                    var cmd = context.cmd;
                    var material = data.Material;
                    var source = data.SourceTexture;

                    // _ParamsとNegativeTextureが前のPassでGlobalパラメータに設定されたので
                    // このPassでマテリアルに設定したくても、そのまま使える
                    Blitter.BlitTexture(cmd, source, Vector2.one, material, 1);
                });
            }
        }
    }
}
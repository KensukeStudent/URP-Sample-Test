using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;
using System.Collections.Generic;

// TODO: 描画順はBeforeRenderingShadows

public class VsmShadowRenderFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        public Material material = null;
        public RenderTexture renderTexture;
        public RenderTexture renderTexture2;
    }

    [SerializeField] private Settings settings = new Settings();

    private VsmShadowRenderPass depthShadow;

    [SerializeField]
    private Material gaussMaterial = null;

    [Header("ガウス分布パラメータ")]
    [SerializeField, Range(1, 10)]
    private float dispersion = 5;

    private GaussRenderer gaussRenderer;

    public override void Create()
    {
        gaussRenderer = new GaussRenderer(gaussMaterial, dispersion);

        this.depthShadow = new VsmShadowRenderPass(
            this.settings.renderPassEvent,
            this.settings.material,
            this.settings.renderTexture,
            this.settings.renderTexture2,
            gaussRenderer
        );
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(this.depthShadow);
    }

    protected override void Dispose(bool disposing)
    {
        depthShadow.Dispose();
    }

    // ------------------------------------------------
    // Render Pass Class 
    // ------------------------------------------------

    public class VsmShadowRenderPass : ScriptableRenderPass
    {
        private Material material;

        private List<ShaderTagId> shaderTagIds = new List<ShaderTagId>();

        private List<ShaderTagId> shaderTagIds2 = new List<ShaderTagId>();

        private RenderTexture targetRenderTexture;
        private RenderTexture targetRenderTexture2;
        private RTHandle targetRTHandle;
        private RTHandle targetRTHandle2;

        private Camera shadowCamera = null;

        private GaussRenderer gaussRenderer;

        private class PassData
        {
            public RendererListHandle rendererListHandle;

            public TextureHandle sourceTextureHandle;
            public Material material;
        }

        public VsmShadowRenderPass(RenderPassEvent renderPassEvent, Material material, RenderTexture renderTexture, RenderTexture renderTexture2, GaussRenderer gaussRenderer)
        {
            this.renderPassEvent = renderPassEvent;
            this.material = material;
            this.targetRenderTexture = renderTexture;
            this.targetRenderTexture2 = renderTexture2;
            this.gaussRenderer = gaussRenderer;

            shaderTagIds.Clear();
            shaderTagIds.Add(new ShaderTagId("ProjShadow"));

            shaderTagIds2.Clear();
            shaderTagIds2.Add(new ShaderTagId("RecieverShadow"));
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            if (this.targetRenderTexture == null)
            {
                this.targetRTHandle?.Release();
                return;
            }

            // Create RTHandle from render texture
            if (this.targetRTHandle == null || this.targetRTHandle.rt != this.targetRenderTexture)
            {
                this.targetRTHandle?.Release();
                this.targetRTHandle = RTHandles.Alloc(this.targetRenderTexture);
            }

            if (this.targetRenderTexture2 == null)
            {
                this.targetRTHandle2?.Release();
                return;
            }

            // Create RTHandle from render texture
            if (this.targetRTHandle2 == null || this.targetRTHandle2.rt != this.targetRenderTexture2)
            {
                this.targetRTHandle2?.Release();
                this.targetRTHandle2 = RTHandles.Alloc(this.targetRenderTexture2);
            }

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
            // camera -> shadow Map texture
            // 影用カメラ位置から見たオブジェクトをシャドウマップへ書き込む
            // ------------------------------------------------------------

            // // テクスチャー情報
            RenderTextureDescriptor desc = cameraData.cameraTargetDescriptor;
            desc.colorFormat = RenderTextureFormat.ARGB32;
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;

            TextureHandle targetTextureHandle = renderGraph.ImportTexture(this.targetRTHandle);

            SetMaterial();

            // camera color RT -> shadowTexture RT
            // TODO: プレビューで見たいのでRenderTextureで対応
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                // Sorting criteria (default transparent)
                SortingCriteria sortingCriteria = cameraData.defaultOpaqueSortFlags;

                // Drawing settings
                DrawingSettings drawingSettings = RenderingUtils.CreateDrawingSettings(this.shaderTagIds, renderingData, cameraData, lightData, sortingCriteria);

                // RendererListHandle
                var filteringSettings = new FilteringSettings(RenderQueueRange.opaque);
                RendererListParams rendererListParams = new RendererListParams(renderingData.cullResults, drawingSettings, filteringSettings);

                passData.rendererListHandle = renderGraph.CreateRendererList(rendererListParams);

                // Set pass to use rendererListHandle
                builder.UseRendererList(passData.rendererListHandle);

                // Set render target (custom render target)
                builder.SetRenderAttachment(targetTextureHandle, 0, AccessFlags.Write);

                // Disable pass culling
                // Passes are culled if no other passes access the write target
                // For example, if only a shader accesses the render target texture (and not a separate pass),
                // we need to disable pass culling to ensure this pass will always run
                builder.AllowPassCulling(false);

                // ブラー側で取得するように
                // builder.SetGlobalTextureAfterPass(targetTextureHandle, Shader.PropertyToID("_ShadowTexture"));

                // Set render function
                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
                {
                    RasterCommandBuffer cmd = graphContext.cmd;
                    cmd.ClearRenderTarget(true, true, Color.clear);
                    // Draw renderer list
                    cmd.DrawRendererList(passData.rendererListHandle);
                });
            }

            // ブラー処理
            gaussRenderer.RecordRenderGraph(renderGraph, cameraData.cameraTargetDescriptor, targetTextureHandle, Shader.PropertyToID("_ShadowTexture"));

            // ------------------------------------------------------------ 
            // camera / shadow Map texture -> shadow color texture
            // 色情報とシャドウマップを組み合わせたテクスチャーを作成
            // ------------------------------------------------------------

            // camera color RT -> shadowColorTexture RT
            // TODO: デバッグ用: 実際のモデル行が側では参照していない
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                TextureHandle targetTextureHandle2 = renderGraph.ImportTexture(this.targetRTHandle2);
                // TextureHandle targetTextureHandle2 = shadowColorTextureHandle;

                // Sorting criteria (default transparent)
                SortingCriteria sortingCriteria = cameraData.defaultOpaqueSortFlags;

                // Drawing settings
                DrawingSettings drawingSettings = RenderingUtils.CreateDrawingSettings(this.shaderTagIds2, renderingData, cameraData, lightData, sortingCriteria);

                // RendererListHandle
                var filteringSettings = new FilteringSettings(RenderQueueRange.opaque);
                RendererListParams rendererListParams = new RendererListParams(renderingData.cullResults, drawingSettings, filteringSettings);

                passData.rendererListHandle = renderGraph.CreateRendererList(rendererListParams);

                // Set pass to use rendererListHandle
                builder.UseRendererList(passData.rendererListHandle);

                // Set render target (custom render target)
                builder.SetRenderAttachment(targetTextureHandle2, 0, AccessFlags.Write);

                // Disable pass culling
                // Passes are culled if no other passes access the write target
                // For example, if only a shader accesses the render target texture (and not a separate pass),
                // we need to disable pass culling to ensure this pass will always run
                builder.AllowPassCulling(false);

                // Set render function
                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
                {
                    RasterCommandBuffer cmd = graphContext.cmd;
                    cmd.ClearRenderTarget(true, true, Color.clear);
                    // Draw renderer list
                    cmd.DrawRendererList(passData.rendererListHandle);
                });
            }
        }

        private void SetMaterial()
        {
            // ライトビュープロジェクション行列
            shadowCamera = GameObject.FindWithTag("ShadowCamera").GetComponent<Camera>(); // TODO: 確認用としてここで定義

            var view = shadowCamera.worldToCameraMatrix;

            // ★これが重要
            var proj = GL.GetGPUProjectionMatrix(
                shadowCamera.projectionMatrix,
                true // render into texture
            );

            Matrix4x4 lightVP = proj * view;
            Shader.SetGlobalMatrix("_lightVP", lightVP);

            // ライト座標
            Shader.SetGlobalVector("_lightPos", shadowCamera.transform.position);
        }

        public void Dispose()
        {
            targetRTHandle?.Release();
            targetRTHandle2?.Release();
        }
    }
}

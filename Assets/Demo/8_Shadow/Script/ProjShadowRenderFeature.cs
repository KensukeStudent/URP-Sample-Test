using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;
using System.Collections.Generic;

public class ProjShadowRenderFeature : ScriptableRendererFeature
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

    private ProjShadowRenderPass projShadow;

    public override void Create()
    {
        this.projShadow = new ProjShadowRenderPass(
            this.settings.renderPassEvent,
            this.settings.material,
            this.settings.renderTexture,
            this.settings.renderTexture2
        );
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(this.projShadow);
    }

    protected override void Dispose(bool disposing)
    {
        projShadow.Dispose();
    }

    // ------------------------------------------------
    // Render Pass Class 
    // ------------------------------------------------

    public class ProjShadowRenderPass : ScriptableRenderPass
    {
        private Material material;

        private List<ShaderTagId> shaderTagIds = new List<ShaderTagId>();

        private List<ShaderTagId> shaderTagIds2 = new List<ShaderTagId>();

        private RenderTexture targetRenderTexture;
        private RenderTexture targetRenderTexture2;
        private RTHandle targetRTHandle;
        private RTHandle targetRTHandle2;

        private Camera shadowCamera = null;

        private class PassData
        {
            public RendererListHandle rendererListHandle;

            public TextureHandle sourceTextureHandle;
            public Material material;
        }

        public ProjShadowRenderPass(RenderPassEvent renderPassEvent, Material material, RenderTexture renderTexture, RenderTexture renderTexture2)
        {
            this.renderPassEvent = renderPassEvent;
            this.material = material;
            this.targetRenderTexture = renderTexture;
            this.targetRenderTexture2 = renderTexture2;

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

            // テクスチャー情報
            RenderTextureDescriptor desc = cameraData.cameraTargetDescriptor;
            desc.colorFormat = RenderTextureFormat.ARGB32;
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;

            TextureHandle cameraColorTextureHandler = resourceData.activeColorTexture;

            SetMaterial();

            // camera color RT -> shadowTexture RT
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                TextureHandle targetTextureHandle = renderGraph.ImportTexture(this.targetRTHandle);

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

                builder.SetGlobalTextureAfterPass(targetTextureHandle, Shader.PropertyToID("_ShadowTexture"));

                // Set render function
                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
                {
                    RasterCommandBuffer cmd = graphContext.cmd;
                    cmd.ClearRenderTarget(true, true, Color.clear);
                    // Draw renderer list
                    cmd.DrawRendererList(passData.rendererListHandle);
                });
            }

            // ------------------------------------------------------------ 
            // camera / shadow Map texture -> shadow color texture
            // 色情報とシャドウマップを組み合わせたテクスチャーを作成
            // ------------------------------------------------------------

            // camera color RT -> shadowColorTexture RT
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                TextureHandle targetTextureHandle2 = renderGraph.ImportTexture(this.targetRTHandle2);

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

                // builder.SetGlobalTextureAfterPass(cameraColorTextureHandler, Shader.PropertyToID("CameraColorTexture"));

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
            shadowCamera = GameObject.FindWithTag("ShadowCamera").GetComponent<Camera>(); // TODO: 確認用としてここで定義

            var view = shadowCamera.worldToCameraMatrix;

            // ★これが重要
            var proj = GL.GetGPUProjectionMatrix(
                shadowCamera.projectionMatrix,
                true // render into texture
            );

            Matrix4x4 lightVP = proj * view;
            Shader.SetGlobalMatrix("_lightVP", lightVP);
        }

        public void Dispose()
        {
            targetRTHandle?.Release();
            targetRTHandle2?.Release();
        }
    }
}

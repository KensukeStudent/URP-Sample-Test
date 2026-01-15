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
    }

    [SerializeField] private Settings settings = new Settings();

    private ProjShadowRenderPass projShadow;

    public override void Create()
    {
        this.projShadow = new ProjShadowRenderPass(
            this.settings.renderPassEvent,
            this.settings.material,
            this.settings.renderTexture
        );
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(this.projShadow);
    }

    protected override void Dispose(bool disposing)
    {
    }

    // ------------------------------------------------
    // Render Pass Class 
    // ------------------------------------------------

    public class ProjShadowRenderPass : ScriptableRenderPass
    {
        private Material material;

        private List<ShaderTagId> shaderTagIds = new List<ShaderTagId>();

        private RenderTexture targetRenderTexture;
        private RTHandle targetRTHandle;

        private class PassData
        {
            public RendererListHandle rendererListHandle;

            public TextureHandle sourceTextureHandle;
            public Material material;
        }

        public ProjShadowRenderPass(RenderPassEvent renderPassEvent, Material material, RenderTexture renderTexture)
        {
            this.renderPassEvent = renderPassEvent;
            this.material = material;
            this.targetRenderTexture = renderTexture;

            shaderTagIds.Clear();
            shaderTagIds.Add(new ShaderTagId("ProjShadow"));
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
            // ------------------------------------------------------------

            // テクスチャー情報
            RenderTextureDescriptor desc = cameraData.cameraTargetDescriptor;
            desc.colorFormat = RenderTextureFormat.ARGB32;
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;

            TextureHandle cameraColorTextureHandler = resourceData.activeColorTexture;

            TextureHandle shadowObjTextureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_ShadowObjTexture", true, FilterMode.Point);

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
            Light mainLight = RenderSettings.sun;
            Vector3 lightDir = -mainLight.transform.forward;
            float distance = 50.0f;
            Vector3 lightPos = Vector3.zero - lightDir * distance;

            // upを外積で求める必要あるかも
            Matrix4x4 lightView = Matrix4x4.LookAt(lightPos, Vector3.zero, Vector3.up);

            float size = 30.0f;
            float near = 0.1f;
            float far = 100.0f;

            Matrix4x4 lightProj =
                Matrix4x4.Ortho(
                    -size, size,
                    -size, size,
                    near, far
                );

            this.material.SetMatrix("_lightVP", lightView * lightProj);
        }
    }
}

using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

public class DepthBufferRenderPass : ScriptableRenderPass
{
    private Material material;

    private static readonly int CameraTexturePropertyId = Shader.PropertyToID("_CameraTexture");

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
        TextureHandle cameraColorTextureHandle = resourceData.activeColorTexture;
        TextureHandle cameraDepthTextureHandle = resourceData.activeDepthTexture;

        // Camera RT descriptor
        RenderTextureDescriptor desc = cameraData.cameraTargetDescriptor;
        desc.depthBufferBits = 0;
        desc.msaaSamples = 1;

        // TextureHandle cameraTextureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_CameraTexture", true);
        // // camera -> cameraTextureHandle
        // using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
        // {
        //     // Set camera color RT for read
        //     builder.UseTexture(cameraColorTextureHandle, AccessFlags.Read);

        //     // Set tempRT for write
        //     // SetRenderAttachment: equivalent of SetRenderTarget
        //     builder.SetRenderAttachment(cameraTextureHandle, 0, AccessFlags.Write);

        //     // shaderセットできるように申請
        //     builder.AllowGlobalStateModification(true);
        //     builder.SetGlobalTextureAfterPass(cameraTextureHandle, CameraTexturePropertyId);

        //     // Resources/References for pass execution
        //     // Blit source texture
        //     passData.sourceTextureHandle = cameraColorTextureHandle;
        //     // Blit material
        //     passData.material = null;

        //     // Set render function
        //     builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) => ExecutePass(passData, graphContext));
        // }

        TextureHandle depthTextureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_DepthTexture", true);
        // camera -> depthTexture
        using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
        {
            // Set camera color RT for read
            builder.UseTexture(cameraDepthTextureHandle, AccessFlags.Read);

            // Set tempRT for write
            // SetRenderAttachment: equivalent of SetRenderTarget
            builder.SetRenderAttachment(depthTextureHandle, 0, AccessFlags.Write);

            // Resources/References for pass execution
            // Blit source texture
            passData.sourceTextureHandle = cameraDepthTextureHandle;
            // Blit material
            passData.material = material;

            // Set render function
            builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) => ExecutePass(passData, graphContext));
        }

        // depthTexture -> camera
        using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
        {
            // Set camera color RT for read
            builder.UseTexture(depthTextureHandle, AccessFlags.Read);

            // Set tempRT for write
            // SetRenderAttachment: equivalent of SetRenderTarget
            builder.SetRenderAttachment(cameraColorTextureHandle, 0, AccessFlags.Write);

            // Resources/References for pass execution  
            // Blit source texture
            passData.sourceTextureHandle = depthTextureHandle;
            // Blit material
            passData.material = null;

            // Set render function
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

    public void Dispose()
    {
        // Nothing to do here since RenderGraph handles resource management for us
    }
}

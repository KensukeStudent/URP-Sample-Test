using System;
using UnityEngine;
using UnityEngine.Rendering.Universal;

public class DepthBufferRenderFeature : ScriptableRendererFeature
{
    [Serializable]
    public class Settings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        public Material material = null;
    }

    [SerializeField] private Settings settings = new Settings();
    private DepthBufferRenderPass renderPass;

    public override void Create()
    {
        this.renderPass = new DepthBufferRenderPass(
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

        this.renderPass.Dispose();
    }
}

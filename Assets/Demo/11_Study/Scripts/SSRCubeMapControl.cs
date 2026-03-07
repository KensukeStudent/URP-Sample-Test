using UnityEngine;

public class SSRCubeMapControl : MonoBehaviour
{
    [SerializeField] private ReflectionProbe probe = null;

    [SerializeField] private RenderTexture renderTexture = null;

    private void Start()
    {
        probe.RenderProbe(renderTexture);
    }
}

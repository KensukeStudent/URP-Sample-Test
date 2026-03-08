using UnityEngine;

[ExecuteAlways]
public class SSRCubeMapControl : MonoBehaviour
{
    [SerializeField] private ReflectionProbe probe = null;
    [SerializeField] private Material material = null;

    void Update()
    {
        UpdateParam();
    }

    private void UpdateParam()
    {
        var bounds = probe.bounds;

        material.SetTexture("_ReflectionProbe", probe.texture);

        material.SetVector("_ProbePosition", probe.transform.position);
        material.SetVector("_CubeMapMin", bounds.min);
        material.SetVector("_CubeMapMax", bounds.max);

        material.SetVector("_CubeMapHDR", probe.textureHDRDecodeValues);
    }
}

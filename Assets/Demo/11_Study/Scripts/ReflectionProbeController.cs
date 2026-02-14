using UnityEngine;
using System.Collections;

public class ReflectionProbeController : MonoBehaviour
{

    private ReflectionProbe probe;
    private Transform trfMainCam;

    void Start()
    {
        probe = gameObject.GetComponent<ReflectionProbe>();
        trfMainCam = Camera.main.transform;
    }

    void Update()
    {
        probe.transform.position = new Vector3(trfMainCam.position.x, -trfMainCam.position.y, trfMainCam.position.z);
    }
}
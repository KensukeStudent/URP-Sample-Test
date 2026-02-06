using UnityEngine;

public class MoveObj : MonoBehaviour
{
    [SerializeField]
    private ComputeShader computeShader;

    private ComputeBuffer computeBuffer;

    private void Start()
    {
        computeBuffer = new ComputeBuffer(1, sizeof(float));
        computeShader.SetBuffer(0, "Result", computeBuffer);
    }

    private void Update()
    {
        computeShader.SetFloat("positionX", transform.position.x);
        computeShader.Dispatch(0, 1, 1, 1);

        var data = new float[1];
        computeBuffer.GetData(data);

        float posX = data[0];
        transform.position = new Vector3(posX, transform.position.y, transform.position.z);
    }
    
    private void OnDestroy()
    {
        computeBuffer.Release();
    }
}

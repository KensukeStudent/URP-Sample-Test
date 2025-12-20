using UnityEngine;

/// <summary>
/// 内積の特徴
/// A: ベクトルの大きさが1
/// B: 大きさと向きをもつベクトル
/// この時、片方が単位ベクトルであれば単位ベクトルの無限線分上に垂線を落として射影した長さとなる   
/// </summary>
public class DotScript : MonoBehaviour
{
    [SerializeField] private Transform origin;
    [SerializeField] private Transform pointA;
    [SerializeField] private LineRenderer lineRenderer;

    [SerializeField]
    private Vector2 normal = new Vector2(1, 0);

    private void Update()
    {
        // 大きさ1のベクトル
        Vector2 n = normal.normalized;

        // 大きさと
        Vector2 a = (Vector2)pointA.position - (Vector2)origin.position;

        // 内積（射影距離）---> この射影の距離を用いてワイプを行う
        float dot = Vector2.Dot(a, n);

        Vector3 p = origin.position + (Vector3)(n * dot);
        Vector3 h = pointA.position - p;
        Vector3 v = p + h;

        // 射影結果を可視化
        lineRenderer.SetPositions(new Vector3[3]
        {
            origin.position,
            p,
            v
        });

        Debug.Log($"dot:{dot}");
    }
}

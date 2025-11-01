// 反射ベクトルの説明: https://www.youtube.com/watch?v=-896y8YXHps

using UnityEngine;

public class PhongDemo : MonoBehaviour
{
    /// <summary>
    /// 法線ベクトル
    /// </summary>
    [SerializeField]
    private Vector2 normal = new Vector2(5, 3);

    [SerializeField]
    private LineRenderer mouseLineRenderer;

    [SerializeField]
    private LineRenderer incidentLineRenderer;

    [SerializeField]
    private LineRenderer normalLineRenderer;

    [SerializeField]
    private LineRenderer dotNormalLineRenderer;

    [SerializeField]
    private LineRenderer _2dotNormalLineRenderer;

    [SerializeField]
    private LineRenderer dn2_incidentLineRenderer;

    [SerializeField]
    private LineRenderer reflectLineRenderer;

    // 補助線
    [SerializeField]
    private LineRenderer dnLineRenderer;

    [SerializeField]
    private LineRenderer dn2LineRenderer;


    private void Update()
    {
        // マウス位置をワールド座標に変換
        var mousePosition = Input.mousePosition;
        mousePosition.z = 4;

        Vector2 mouseVec = Camera.main.ScreenToWorldPoint(mousePosition);

        // マウスの位置を入射ベクトルとしてLineRendererで表示
        mouseLineRenderer.SetPosition(1, mouseVec);

        Vector2 incidentVec = Vector2.zero - mouseVec;
        incidentLineRenderer.SetPosition(1, incidentVec);

        // 法線ベクトルをLineRendererで表示
        Vector2 n = normal.normalized;
        normalLineRenderer.SetPosition(1, n);

        // 入射ベクトルを法線ベクトルに投影
        float distance = Vector2.Dot(-incidentVec, n);
        Vector2 dn = n * distance;
        dotNormalLineRenderer.SetPosition(1, dn);

        // 2倍の法線ベクトルをLineRendererで表示
        Vector2 dn2 = dn * 2;
        _2dotNormalLineRenderer.SetPosition(1, dn2);

        // 入射ベクトルと2倍の法線ベクトルの和をLineRendererで表示
        dn2_incidentLineRenderer.SetPosition(0, dn2);
        dn2_incidentLineRenderer.SetPosition(1, dn2 + incidentVec);

        // 反射ベクトルを計算
        Vector3 reflection = incidentVec + dn2;
        reflectLineRenderer.SetPosition(1, reflection);

        // 内積と法線の補助線
        dnLineRenderer.SetPosition(0, mouseVec);
        dnLineRenderer.SetPosition(1, dn);

        dn2LineRenderer.SetPosition(0, mouseVec);
        dn2LineRenderer.SetPosition(1, dn2);
    }
}

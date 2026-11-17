-- =====================================================================
-- Empresas - Reporting (SQL Server 2016)
-- usp_ResumenConsumoEmpresas: resumen mensual de consumo por empresa
-- =====================================================================
CREATE OR ALTER PROCEDURE rpt.usp_ResumenConsumoEmpresas
    @Periodo CHAR(6),
    @TopN    INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IniMes DATE = CONVERT(DATE, @Periodo + '01', 112);
    DECLARE @FinMes DATE = EOMONTH(@IniMes);

    IF OBJECT_ID('tempdb..#consumo') IS NOT NULL DROP TABLE #consumo;

    SELECT  l.IdCliente,
            COUNT(DISTINCT l.IdLinea)                                   AS NumLineas,
            SUM(CASE WHEN c.TipoEvento = 'DATOS' THEN c.MbConsumidos ELSE 0 END) / 1024.0 AS GbDatos,
            SUM(CASE WHEN c.TipoEvento = 'VOZ'   THEN c.DuracionSeg  ELSE 0 END) / 60.0   AS MinutosVoz,
            SUM(ISNULL(c.Importe, 0))                                   AS ImporteFueraBono
    INTO    #consumo
    FROM    stg.Cdr c WITH (NOLOCK)
    INNER JOIN stg.Lineas l WITH (NOLOCK) ON l.IdLinea = c.IdLinea
    WHERE   c.FechaHoraInicio >= @IniMes
      AND   c.FechaHoraInicio <  DATEADD(DAY, 1, @FinMes)
    GROUP BY l.IdCliente;

    SELECT TOP (@TopN)
            cl.IdCliente,
            cl.Nombre,
            cl.Provincia,
            co.NumLineas,
            CAST(co.GbDatos AS DECIMAL(12,2))                           AS GbDatos,
            CAST(co.MinutosVoz AS DECIMAL(12,2))                        AS MinutosVoz,
            co.ImporteFueraBono,
            STUFF((SELECT DISTINCT ', ' + t.Familia
                     FROM stg.Lineas l2
                     JOIN stg.Tarifas t ON t.CodTarifa = l2.CodTarifa
                    WHERE l2.IdCliente = cl.IdCliente
                      FOR XML PATH('')), 1, 2, '')                      AS FamiliasTarifa,
            ROW_NUMBER() OVER (ORDER BY co.GbDatos DESC)                AS RankingGb
    FROM    #consumo co
    INNER JOIN stg.Clientes cl ON cl.IdCliente = co.IdCliente
    WHERE   cl.Segmento IN ('PYM', 'EMP')
    ORDER BY co.GbDatos DESC;
END
GO

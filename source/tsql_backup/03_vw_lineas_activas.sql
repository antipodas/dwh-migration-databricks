-- =====================================================================
-- vw_LineasActivas: inventario de lineas activas con antiguedad
-- =====================================================================
CREATE OR ALTER VIEW rpt.vw_LineasActivas
AS
SELECT  l.IdLinea,
        l.IdCliente,
        RIGHT('000000000' + l.Msisdn, 9)                          AS Msisdn9,
        l.TipoLinea,
        t.DescTarifa,
        DATEDIFF(MONTH, l.FechaAlta, GETDATE())                   AS MesesAntiguedad,
        IIF(DATEDIFF(MONTH, l.FechaAlta, GETDATE()) < 12, 'NUEVA', 'CONSOLIDADA') AS Madurez,
        FORMAT(l.FechaAlta, 'dd/MM/yyyy')                         AS FechaAltaTexto
FROM    stg.Lineas l
LEFT JOIN stg.Tarifas t ON t.CodTarifa = l.CodTarifa
WHERE   l.Estado = 'A'
  AND   l.FechaBaja IS NULL;
GO

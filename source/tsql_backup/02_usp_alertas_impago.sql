-- =====================================================================
-- usp_AlertasImpago: clientes con 2+ facturas impagadas consecutivas
-- =====================================================================
CREATE OR ALTER PROCEDURE rpt.usp_AlertasImpago
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        TRUNCATE TABLE rpt.AlertasImpago;

        ;WITH fact AS (
            SELECT  f.IdCliente,
                    f.Periodo,
                    f.ImporteTotal,
                    f.EstadoPago,
                    LAG(f.EstadoPago) OVER (PARTITION BY f.IdCliente ORDER BY f.Periodo) AS EstadoPagoAnt
            FROM    stg.Facturas f
        )
        INSERT INTO rpt.AlertasImpago (IdCliente, PeriodoDeteccion, ImporteImpagado, FechaAlerta)
        SELECT  IdCliente, MAX(Periodo), SUM(ImporteTotal), GETDATE()
        FROM    fact
        WHERE   EstadoPago = 'IMPAGADA' AND EstadoPagoAnt = 'IMPAGADA'
        GROUP BY IdCliente;

        PRINT CONCAT('Alertas generadas: ', @@ROWCOUNT);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

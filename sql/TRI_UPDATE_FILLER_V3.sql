USE [DB_BUDIBASE]
GO
CREATE OR ALTER TRIGGER [dbo].[TRI_UPDATE_FILLER_V3]
ON [dbo].[T_M_Filler_Process]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Machine           NVARCHAR(50)
    DECLARE @GID               INT
    DECLARE @GID_ST            INT
    DECLARE @Splicing_Count    INT
    DECLARE @Splicing_Count_ST INT
    DECLARE @LastSpliceTime    DATETIME
    DECLARE @LastStripTime     DATETIME
    DECLARE @ColumnName        NVARCHAR(50)
    DECLARE @SQL               NVARCHAR(MAX)

    BEGIN TRANSACTION
    BEGIN TRY

        ------------------------------------------------
        -- STEP 10 : Start Splicing Loop
        ------------------------------------------------
        IF EXISTS (SELECT 1 FROM inserted WHERE Machine_Step_No = 10)
        BEGIN
            UPDATE cpb
            SET [Splicing time 1] = GETUTCDATE()
            FROM [Change paper brik] cpb
            JOIN inserted i ON cpb.Machine = i.Machine
            WHERE cpb.[Splicing time 1] IS NULL

            UPDATE cs
            SET [Splicing time 1] = GETUTCDATE()
            FROM [Change strip] cs
            JOIN (
                SELECT Machine, MAX(ID) MaxID FROM [Change strip] GROUP BY Machine
            ) x ON cs.Machine = x.Machine AND cs.ID = x.MaxID
            JOIN inserted i ON cs.Machine = i.Machine
            WHERE i.Machine_Step_No = 10
            AND cs.[Splicing time 1] IS NULL
        END

        ------------------------------------------------
        -- STEP 13 : End Splicing Loop
        -- CHANGED: removed counter_infeed/outfeed writes (now handled by In-roll signal)
        -- CHANGED: removed inline End_time_CIP for A/D (now handled purely by Step 14)
        ------------------------------------------------
        IF EXISTS (SELECT 1 FROM inserted WHERE Machine_Step_No = 13)
        BEGIN
            UPDATE cpb
            SET [end time] = GETUTCDATE()
            FROM [Change paper brik] cpb
            JOIN inserted i ON cpb.Machine = i.Machine
            WHERE cpb.[end time] IS NULL
            AND cpb.[Splicing time 1] IS NOT NULL

            UPDATE cs
            SET [end time] = GETUTCDATE()
            FROM [Change strip] cs
            JOIN (
                SELECT Machine, MAX(ID) MaxID FROM [Change strip] GROUP BY Machine
            ) x ON cs.Machine = x.Machine AND cs.ID = x.MaxID
            JOIN inserted i ON cs.Machine = i.Machine
            WHERE i.Machine_Step_No = 13
            AND cs.[end time] IS NULL
            AND cs.[Splicing time 1] IS NOT NULL
        END

        ------------------------------------------------
        -- STEP 14 : Signal_Final_CIP = 1
        -- Only for Machine A and D
        -- Unchanged from V3
        ------------------------------------------------
        IF EXISTS (
            SELECT 1 FROM inserted
            WHERE Machine_Step_No = 14
            AND Signal_Final_CIP = 1
            AND (Machine LIKE 'A%' OR Machine LIKE 'D%')
        )
        BEGIN
            DECLARE @cur_Machine_S14 NVARCHAR(50)
            DECLARE @GID_S14         INT
            DECLARE @LastLogTime_S14 DATETIME
            DECLARE @Outfeed_S14     NVARCHAR(50)
            DECLARE @EndTime_S14     DATETIME

            DECLARE step14_cursor CURSOR FOR
                SELECT DISTINCT Machine
                FROM inserted
                WHERE Machine_Step_No = 14
                AND Signal_Final_CIP = 1
                AND (Machine LIKE 'A%' OR Machine LIKE 'D%')

            OPEN step14_cursor
            FETCH NEXT FROM step14_cursor INTO @cur_Machine_S14

            WHILE @@FETCH_STATUS = 0
            BEGIN
                SELECT @GID_S14 = MAX(ID)
                FROM [Change paper brik]
                WHERE Machine    = @cur_Machine_S14
                AND [end time] IS NOT NULL

                IF @GID_S14 IS NOT NULL
                BEGIN
                    SELECT
                        @EndTime_S14 = [end time],
                        @Outfeed_S14 = CAST([Out_Feed_MC] AS NVARCHAR(50))
                    FROM [Change paper brik]
                    WHERE ID = @GID_S14

                    SELECT @LastLogTime_S14 = MAX(Log_Time)
                    FROM [endtime_log_test]
                    WHERE Machine = @cur_Machine_S14

                    IF @LastLogTime_S14 IS NULL
                    OR DATEDIFF(SECOND, @LastLogTime_S14, SYSDATETIME()) >= 3600
                    OR DATEDIFF(SECOND, @LastLogTime_S14, SYSDATETIME()) < 0
                    BEGIN
                        UPDATE [Change paper brik]
                        SET End_time_CIP = @EndTime_S14
                        WHERE ID = @GID_S14

                        INSERT INTO [endtime_log_test] (Machine, Step, Signal_CIP, Outfeed, End_Time, Log_Time)
                        VALUES (
                            @cur_Machine_S14, 14, 1,
                            @Outfeed_S14, @EndTime_S14, GETUTCDATE()
                        )

                        INSERT INTO t_log (txt)
                        VALUES (
                            @cur_Machine_S14 + '_S14:CIP=1:ID=' + CAST(@GID_S14 AS NVARCHAR) +
                            ':Outfeed=' + ISNULL(@Outfeed_S14, 'NULL') +
                            ':EndTime=' + CONVERT(NVARCHAR, @EndTime_S14, 121) + '-LOGGED'
                        )
                    END
                    ELSE
                    BEGIN
                        INSERT INTO t_log (txt)
                        VALUES (
                            @cur_Machine_S14 + '_S14:CIP=1:COOLDOWN' +
                            ':diff=' + CAST(DATEDIFF(SECOND, @LastLogTime_S14, SYSDATETIME()) AS NVARCHAR) + 's' +
                            ':remaining=' + CAST(3600 - DATEDIFF(SECOND, @LastLogTime_S14, SYSDATETIME()) AS NVARCHAR) + 's'
                        )
                    END
                END

                FETCH NEXT FROM step14_cursor INTO @cur_Machine_S14
            END

            CLOSE step14_cursor
            DEALLOCATE step14_cursor
        END

        ------------------------------------------------
        -- IN-ROLL SIGNAL (0->1) : Update In_Feed_MC / Out_Feed_MC
        -- NEW BLOCK
        -- All machines, rising edge only
        -- Only updates if [end time] IS NULL (row still open)
        -- 30s cooldown using Last_Splice_Time (shared with EndRoll block)
        ------------------------------------------------
        IF EXISTS (
            SELECT 1 FROM inserted i
            JOIN deleted d ON i.Machine = d.Machine
            WHERE i.Paper_Splicing_In_roll_Signal_Brik = 1
            AND d.Paper_Splicing_In_roll_Signal_Brik = 0
        )
        BEGIN
            DECLARE @cur_Machine_IR  NVARCHAR(50)
            DECLARE @GID_IR          INT
            DECLARE @LastSpliceIR    DATETIME
            DECLARE @Infeed_IR       NVARCHAR(50)
            DECLARE @Outfeed_IR      NVARCHAR(50)

            DECLARE inroll_cursor CURSOR FOR
                SELECT i.Machine
                FROM inserted i
                JOIN deleted d ON i.Machine = d.Machine
                WHERE i.Paper_Splicing_In_roll_Signal_Brik = 1
                AND d.Paper_Splicing_In_roll_Signal_Brik = 0

            OPEN inroll_cursor
            FETCH NEXT FROM inroll_cursor INTO @cur_Machine_IR

            WHILE @@FETCH_STATUS = 0
            BEGIN
                -- Get MAX open row for this machine
                SELECT @GID_IR = MAX(ID)
                FROM [Change paper brik] WITH (UPDLOCK, HOLDLOCK)
                WHERE Machine    = @cur_Machine_IR
                AND [end time] IS NULL

                IF @GID_IR IS NOT NULL
                BEGIN
                    -- Read current Last_Splice_Time from that row
                    SELECT @LastSpliceIR = Last_Splice_Time
                    FROM [Change paper brik] WITH (UPDLOCK, HOLDLOCK)
                    WHERE ID = @GID_IR

                    -- Read latest counter values from inserted
                    SELECT
                        @Infeed_IR  = CAST(i.counter_infeed  AS NVARCHAR(50)),
                        @Outfeed_IR = CAST(i.counter_outfeed AS NVARCHAR(50))
                    FROM inserted i
                    WHERE i.Machine = @cur_Machine_IR

                    IF @LastSpliceIR IS NULL
                    OR DATEDIFF(MILLISECOND, @LastSpliceIR, SYSDATETIME()) >= 30000
                    OR DATEDIFF(MILLISECOND, @LastSpliceIR, SYSDATETIME()) < -500
                    BEGIN
                        -- Update counters and stamp cooldown timer
                        UPDATE [Change paper brik]
                        SET
                            In_Feed_MC       = i.counter_infeed,
                            Out_Feed_MC      = i.counter_outfeed,
                            Last_Splice_Time = SYSDATETIME()
                        FROM [Change paper brik] cpb
                        JOIN inserted i ON i.Machine = @cur_Machine_IR
                        WHERE cpb.ID = @GID_IR

                        INSERT INTO t_log(txt)
                        VALUES (
                            @cur_Machine_IR + '_InRoll:ID=' + CAST(@GID_IR AS NVARCHAR) +
                            ':In=' + ISNULL(@Infeed_IR, 'NULL') +
                            ':Out=' + ISNULL(@Outfeed_IR, 'NULL') + '-UPD'
                        )
                    END
                    ELSE
                    BEGIN
                        INSERT INTO t_log(txt)
                        VALUES (
                            @cur_Machine_IR + '_InRoll:COOLDOWN' +
                            ':diff=' + CAST(DATEDIFF(MILLISECOND, @LastSpliceIR, SYSDATETIME()) AS NVARCHAR) + 'ms' +
                            ':remaining=' + CAST(30000 - DATEDIFF(MILLISECOND, @LastSpliceIR, SYSDATETIME()) AS NVARCHAR) + 'ms'
                        )
                    END
                END

                FETCH NEXT FROM inroll_cursor INTO @cur_Machine_IR
            END

            CLOSE inroll_cursor
            DEALLOCATE inroll_cursor
        END

        ------------------------------------------------
        -- End Roll Signal (0->1) with CURSOR + COOLDOWN
        -- Unchanged except A/D open-row check uses [end time] IS NULL
        -- (End_time_CIP check removed since Step 13 no longer sets it)
        -- CHANGED: A/D now also use [end time] IS NULL like all other machines
        ------------------------------------------------
        IF EXISTS (
            SELECT 1 FROM inserted i
            JOIN deleted d ON i.Machine = d.Machine
            WHERE i.Paper_Splicing_End_roll_Signal_Brik = 1
            AND d.Paper_Splicing_End_roll_Signal_Brik = 0
        )
        BEGIN
            DECLARE @cur_Machine_ER NVARCHAR(50)

            DECLARE endroll_cursor CURSOR FOR
                SELECT i.Machine
                FROM inserted i
                JOIN deleted d ON i.Machine = d.Machine
                WHERE i.Paper_Splicing_End_roll_Signal_Brik = 1
                AND d.Paper_Splicing_End_roll_Signal_Brik = 0

            OPEN endroll_cursor
            FETCH NEXT FROM endroll_cursor INTO @cur_Machine_ER

            WHILE @@FETCH_STATUS = 0
            BEGIN
                -- CHANGED: unified [end time] IS NULL check for all machines
                -- (A/D previously used End_time_CIP IS NULL, no longer needed
                --  since Step 13 closes [end time] and Step 14 handles End_time_CIP separately)
                SELECT @GID = MAX(ID)
                FROM [Change paper brik] WITH (UPDLOCK, HOLDLOCK)
                WHERE Machine    = @cur_Machine_ER
                AND [end time] IS NULL

                SELECT
                    @Splicing_Count = ISNULL(Splicing_Count, 0) + 1,
                    @LastSpliceTime = Last_Splice_Time
                FROM [Change paper brik] WITH (UPDLOCK, HOLDLOCK)
                WHERE ID = @GID

                IF @LastSpliceTime IS NULL
                OR DATEDIFF(MILLISECOND, @LastSpliceTime, SYSDATETIME()) >= 30000
                OR DATEDIFF(MILLISECOND, @LastSpliceTime, SYSDATETIME()) < -500
                BEGIN
                    UPDATE [Change paper brik]
                    SET Splicing_Count   = @Splicing_Count,
                        Last_Splice_Time = SYSDATETIME()
                    WHERE ID = @GID

                    SET @ColumnName = 'Splicing time ' + CAST(@Splicing_Count + 1 AS NVARCHAR)
                    SET @SQL = 'UPDATE [Change paper brik] SET [' + @ColumnName + '] = GETUTCDATE() WHERE ID = @ID'
                    EXEC sp_executesql @SQL, N'@ID INT', @ID = @GID

                    INSERT INTO t_log(txt)
                    VALUES (@cur_Machine_ER + '_EndRoll:' + CAST(@GID AS NVARCHAR) + ':' + CAST(@Splicing_Count AS NVARCHAR) + '-UPD')
                END
                ELSE
                BEGIN
                    SET @ColumnName = 'Splicing time ' + CAST(@Splicing_Count AS NVARCHAR)
                    SET @SQL = 'UPDATE [Change paper brik] SET [' + @ColumnName + '] = GETUTCDATE() WHERE ID = @ID'
                    EXEC sp_executesql @SQL, N'@ID INT', @ID = @GID

                    INSERT INTO t_log(txt)
                    VALUES (@cur_Machine_ER + '_EndRoll:COOLDOWN:count=' + CAST(@Splicing_Count - 1 AS NVARCHAR) +
                            ':diff=' + CAST(DATEDIFF(MILLISECOND, @LastSpliceTime, SYSDATETIME()) AS NVARCHAR) + 'ms')
                END

                FETCH NEXT FROM endroll_cursor INTO @cur_Machine_ER
            END

            CLOSE endroll_cursor
            DEALLOCATE endroll_cursor
        END

        ------------------------------------------------
        -- Strip Signal (0->1) with CURSOR + COOLDOWN
        -- Unchanged
        ------------------------------------------------
        IF EXISTS (
            SELECT 1 FROM inserted i
            JOIN deleted d ON i.Machine = d.Machine
            WHERE i.Strip_Splicing_Signal_Strip = 1
            AND d.Strip_Splicing_Signal_Strip = 0
        )
        BEGIN
            DECLARE @cur_Machine_ST NVARCHAR(50)

            DECLARE strip_cursor CURSOR FOR
                SELECT i.Machine
                FROM inserted i
                JOIN deleted d ON i.Machine = d.Machine
                WHERE i.Strip_Splicing_Signal_Strip = 1
                AND d.Strip_Splicing_Signal_Strip = 0

            OPEN strip_cursor
            FETCH NEXT FROM strip_cursor INTO @cur_Machine_ST

            WHILE @@FETCH_STATUS = 0
            BEGIN
                SELECT @GID_ST = MAX(ID)
                FROM [Change Strip] WITH (UPDLOCK, HOLDLOCK)
                WHERE Machine = @cur_Machine_ST

                SELECT
                    @Splicing_Count_ST = ISNULL(Splicing_Count, 0) + 1,
                    @LastStripTime     = Last_Splice_Time
                FROM [Change Strip] WITH (UPDLOCK, HOLDLOCK)
                WHERE ID = @GID_ST

                IF @LastStripTime IS NULL
                OR DATEDIFF(MILLISECOND, @LastStripTime, SYSDATETIME()) >= 30000
                OR DATEDIFF(MILLISECOND, @LastStripTime, SYSDATETIME()) < -500
                BEGIN
                    SET @ColumnName = 'Splicing time ' + CAST(@Splicing_Count_ST + 1 AS NVARCHAR)
                    SET @SQL = 'UPDATE [Change Strip] SET [' + @ColumnName + '] = GETUTCDATE(), Splicing_Count = @CNT, Last_Splice_Time = SYSDATETIME() WHERE ID = @ID AND [end time] IS NULL'
                    IF @Splicing_Count_ST = 1
                        SET @SQL = 'UPDATE [Change Strip] SET [' + @ColumnName + '] = GETUTCDATE(), Splicing_Count = @CNT, Last_Splice_Time = SYSDATETIME() WHERE ID = @ID AND [end time] IS NULL AND [Splicing time 1] IS NOT NULL'
                    EXEC sp_executesql @SQL, N'@ID INT, @CNT INT', @ID = @GID_ST, @CNT = @Splicing_Count_ST

                    INSERT INTO t_log(txt)
                    VALUES (@cur_Machine_ST + '_ST:' + CAST(@GID_ST AS NVARCHAR) + ':' + CAST(@Splicing_Count_ST AS NVARCHAR) + '-UPD')
                END
                ELSE
                BEGIN
                    SET @ColumnName = 'Splicing time ' + CAST(@Splicing_Count_ST AS NVARCHAR)
                    SET @SQL = 'UPDATE [Change Strip] SET [' + @ColumnName + '] = GETUTCDATE() WHERE ID = @ID AND [end time] IS NULL'
                    EXEC sp_executesql @SQL, N'@ID INT', @ID = @GID_ST

                    INSERT INTO t_log(txt)
                    VALUES (@cur_Machine_ST + '_ST:COOLDOWN:count=' + CAST(@Splicing_Count_ST - 1 AS NVARCHAR) +
                            ':diff=' + CAST(DATEDIFF(MILLISECOND, @LastStripTime, SYSDATETIME()) AS NVARCHAR) + 'ms')
                END

                FETCH NEXT FROM strip_cursor INTO @cur_Machine_ST
            END

            CLOSE strip_cursor
            DEALLOCATE strip_cursor
        END

    COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION
        INSERT INTO t_log(txt) VALUES (ERROR_MESSAGE())
    END CATCH

END

*/
/**************************************************************/
/**************************************************************/
 
PRINT ' '
PRINT '***********************************************************************'
PRINT ' '
PRINT ' RUNNING SQL LOGIC FOR DBSYSMON'
PRINT ' '
PRINT '***********************************************************************'
PRINT ' '
PRINT ' GATHERING DEFAULT DATA LOG FILE LOCATIONS FOR DATABASE CREATION'
 
-- gather default data and log file location information from the registry
use master;
set nocount on
 
declare @defaultdata nvarchar(512)
exec master.dbo.xp_instance_regread
 'hkey_local_machine'
, 'software\microsoft\mssqlserver\mssqlserver'
, 'defaultdata'
, @defaultdata output
 
declare @defaultlog nvarchar(512)
exec master.dbo.xp_instance_regread 
 'hkey_local_machine'
, 'software\microsoft\mssqlserver\mssqlserver'
, 'defaultlog'
, @defaultlog output
 
declare @masterdata nvarchar(512)
exec master.dbo.xp_instance_regread 'hkey_local_machine'
, 'software\microsoft\mssqlserver\mssqlserver\parameters'
, 'sqlarg0'
, @masterdata output
 
select @masterdata=substring(@masterdata, 3, 255)
select @masterdata=substring(@masterdata, 1, len(@masterdata) - charindex('\', reverse(@masterdata)))
 
declare @masterlog nvarchar(512)
exec master.dbo.xp_instance_regread 'hkey_local_machine'
, 'software\microsoft\mssqlserver\mssqlserver\parameters'
, 'sqlarg2'
, @masterlog output
 
select @masterlog=substring(@masterlog, 3, 255)
select @masterlog=substring(@masterlog, 1, len(@masterlog) - charindex('\', reverse(@masterlog)))
 
-- create the DBSYSMON database
 
PRINT ' '
PRINT ' CREATING DATABASE DBSYSMON'
PRINT ' '
 
declare @path_data_file varchar(255)
declare @path_log_file varchar(255)
declare @create_database varchar(max)
declare @database_name varchar(255)
set @database_name = 'DBSYSMON'
set @path_data_file = ( select isnull(@defaultdata, @masterdata) defaultdata ) + '\DBSYSMON.mdf'
set @path_log_file = ( select isnull(@defaultlog, @masterlog) defaultlog ) + '\DBSYSMON_log.ldf'
 
set @create_database = 
'if not exists (select name from sys.databases where name = ''' + @database_name + ''')
create database [' + @database_name + '] 
 containment = none
 on primary
( name = ''' + @database_name + '_data''' + ', filename = ''' + @path_data_file + ''', size = 4096kb , filegrowth = 1024kb )
 log on
( name = ''' + @database_name + '_log''' + ', filename = ''' + @path_log_file + ''', size = 2048kb , filegrowth = 10%); 
alter database ' + @database_name + ' set recovery simple'
 
exec (@create_database)
 
 
-- create the table: sdivfs_io_stats
 
PRINT ' '
PRINT ' CREATING THE TABLE SDIVFS_IO_STATS'
PRINT ' '
 
use DBSYSMON;
set nocount on
 
if not exists (select name from sys.tables where name = 'sdivfs_io_stats')
 
create table sdivfs_io_stats
(
 rowid int identity(1,1) primary key clustered
, timestamp datetime
, database_id smallint
, num_of_reads bigint
, num_of_writes bigint
, size_on_disk_bytes bigint
, io_stall bigint
, io_stall_read_ms bigint
, io_stall_write_ms bigint
, data_file_name varchar(255)
, fileid smallint
, physicalname varchar(255)
, data_file_type varchar(50) 
)
 
-- populate the table: sdivfs_io_stats
PRINT ' '
PRINT ' POPULATING TABLE ON FIRST RUN'
PRINT ' '
 
insert into sdivfs_io_stats
(
 timestamp
, database_id
, num_of_reads
, num_of_writes
, size_on_disk_bytes
, io_stall
, io_stall_read_ms
, io_stall_write_ms
, data_file_name
, fileid
, physicalname
, data_file_type
)
select
 getdate()
, sdivfs.database_id
, sdivfs.num_of_reads
, sdivfs.num_of_writes
, ( ( sdivfs.size_on_disk_bytes / 1024 ) / 1024 / 1024 )
, sdivfs.io_stall
, sdivfs.io_stall_read_ms
, sdivfs.io_stall_write_ms
/*
, sdivfs.sample_ms
, sdivfs.num_of_bytes_read
, sdivfs.num_of_bytes_written
, sdivfs.io_stall_write_ms
*/ 
, smf.name
, sdivfs.file_id
, smf.physical_name
, db_file_type = case 
 when sdivfs.file_id = 2 then 'log' 
 else 'data' 
 end
from
 sys.dm_io_virtual_file_stats (null, null) sdivfs join sys.master_files smf on sdivfs.file_id = smf.file_id 
 and sdivfs.database_id = smf.database_id 
 
-- creating table sdopc_main_table
PRINT ' '
PRINT ' CREATING TABLE SDOPC_MAIN_TABLE'
PRINT ' '
 
if not exists(select name from sys.tables where name = 'sdopc_main_table')
 
create table sdopc_main_table
(
 [rowid] int identity(1,1) primary key clustered
, [servername] varchar(255)
, [timestamp] datetime
, [object_name] nchar(256)
, [counter_name] nchar(256)
, [instance_name] nchar(256)
, [cntr_value] bigint
, [cntr_type] bigint
);
 
-- populating table sdopc_main_table
PRINT ' '
PRINT ' POPULATING TABLE SDOPC_MAIN_TABLE ON FIRST RUN'
PRINT ' '
 
insert into sdopc_main_table
(
 [servername]
, [timestamp]
, [object_name]
, [counter_name]
, [instance_name]
, [cntr_value]
, [cntr_type]
)
 
select
 cast(serverproperty('servername') as varchar(250))
, getdate()
, [object_name]
, [counter_name]
, [instance_name]
, [cntr_value]
, [cntr_type]
from
 sys.[dm_os_performance_counters]
 
 
 
/**************************************************************/
/******** CREATE AGENT JOBS FOR DBSYSMON COLLECTION**********/
/**************************************************************/
 
PRINT ' '
PRINT ' CREATING AGENT JOBS FOR DBYSMON COLLECTION'
PRINT ' '
 
USE [msdb]
GO
 
/****** Object: Job [DBSYSMON_COLLECTION] Script Date: 11/18/2014 11:13:29 AM******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object: JobCategory [[Uncategorized (Local)]] Script Date: 11/18/2014 11:13:29 AM******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR &lt;&gt; 0 OR @ReturnCode &lt;&gt; 0) GOTO QuitWithRollback
 
END
 
DECLARE @jobId BINARY(16)
EXEC @ReturnCode = msdb.dbo.sp_add_job @job_name=N'DBSYSMON_COLLECTION', 
 @enabled=1, 
 @notify_level_eventlog=0, 
 @notify_level_email=0, 
 @notify_level_netsend=0, 
 @notify_level_page=0, 
 @delete_level=0, 
 @description=N'No description available.', 
 @category_name=N'[Uncategorized (Local)]', 
 @owner_login_name=N'INT\SQLDatabase', @job_id = @jobId OUTPUT
IF (@@ERROR &lt;&gt; 0 OR @ReturnCode &lt;&gt; 0) GOTO QuitWithRollback
/****** Object: Step [Gather All Stats From SDOPC] Script Date: 11/18/2014 11:13:29 AM******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Gather All Stats From SDOPC', 
 @step_id=1, 
 @cmdexec_success_code=0, 
 @on_success_action=3, 
 @on_success_step_id=0, 
 @on_fail_action=3, 
 @on_fail_step_id=0, 
 @retry_attempts=0, 
 @retry_interval=0, 
 @os_run_priority=0, @subsystem=N'TSQL', 
 @command=N'use DBSYSMON;
set nocount on
 
if not exists(select name from sys.tables where name = ''sdopc_main_table'')
 
create table sdopc_main_table
(
 [rowid] int identity(1,1) primary key clustered
, [servername] varchar(255)
, [timestamp] datetime
, [object_name] nchar(256)
, [counter_name] nchar(256)
, [instance_name] nchar(256)
, [cntr_value] bigint
, [cntr_type] bigint
);
 
insert into sdopc_main_table
(
 [servername]
, [timestamp]
, [object_name]
, [counter_name]
, [instance_name]
, [cntr_value]
, [cntr_type]
)
select
 cast(serverproperty(''servername'') as varchar(250))
, getdate()
, [object_name]
, [counter_name]
, [instance_name]
, [cntr_value]
, [cntr_type]
from
 sys.[dm_os_performance_counters]', 
 @database_name=N'DBSYSMON', 
 @flags=0
IF (@@ERROR &lt;&gt; 0 OR @ReturnCode &lt;&gt; 0) GOTO QuitWithRollback
/****** Object: Step [Gather Stats From SDIVFS] Script Date: 11/18/2014 11:13:29 AM******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Gather Stats From SDIVFS', 
 @step_id=2, 
 @cmdexec_success_code=0, 
 @on_success_action=1, 
 @on_success_step_id=0, 
 @on_fail_action=2, 
 @on_fail_step_id=0, 
 @retry_attempts=0, 
 @retry_interval=0, 
 @os_run_priority=0, @subsystem=N'TSQL', 
 @command=N'use DBSYSMON;
set nocount on
 
if not exists (select name from sys.tables where name = ''sdivfs_io_stats'')
 
create table sdivfs_io_stats
(
 rowid int identity(1,1) primary key clustered
, timestamp datetime
, database_id smallint
, num_of_reads bigint
, num_of_writes bigint
, size_on_disk_bytes bigint
, io_stall bigint
, io_stall_read_ms bigint
, io_stall_write_ms bigint
, data_file_name varchar(255)
, fileid smallint
, physicalname varchar(255)
, data_file_type varchar(50) 
)
 
insert into sdivfs_io_stats
(
 timestamp
, database_id
, num_of_reads
, num_of_writes
, size_on_disk_bytes
, io_stall
, io_stall_read_ms
, io_stall_write_ms
, data_file_name
, fileid
, physicalname
, data_file_type
)
select
 getdate()
, sdivfs.database_id
, sdivfs.num_of_reads
, sdivfs.num_of_writes
, ( ( sdivfs.size_on_disk_bytes / 1024 ) / 1024 / 1024 )
, sdivfs.io_stall
, sdivfs.io_stall_read_ms
, sdivfs.io_stall_write_ms
 --sdivfs.sample_ms, sdivfs.num_of_bytes_read, sdivfs.num_of_bytes_written, sdivfs.io_stall_write_ms, 
, smf.name
, sdivfs.file_id
, smf.physical_name
, db_file_type = case
 when sdivfs.file_id = 2 then ''log''
 else ''data''
 end
from
 sys.dm_io_virtual_file_stats (null, null) sdivfs join sys.master_files smf on sdivfs.file_id = smf.file_id 
 and sdivfs.database_id = smf.database_id', 
 @database_name=N'DBSYSMON', 
 @flags=0
IF (@@ERROR &lt;&gt; 0 OR @ReturnCode &lt;&gt; 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR &lt;&gt; 0 OR @ReturnCode &lt;&gt; 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Every 15 minutes', 
 @enabled=1, 
 @freq_type=4, 
 @freq_interval=1, 
 @freq_subday_type=4, 
 @freq_subday_interval=15, 
 @freq_relative_interval=0, 
 @freq_recurrence_factor=0, 
 @active_start_date=20141116, 
 @active_end_date=99991231, 
 @active_start_time=0, 
 @active_end_time=235959, 
 @schedule_uid=N'92a0ceb0-9ef9-4414-a097-0a4d2b953ebf'
IF (@@ERROR &lt;&gt; 0 OR @ReturnCode &lt;&gt; 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR &lt;&gt; 0 OR @ReturnCode &lt;&gt; 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
 IF (@@TRANCOUNT &gt; 0) ROLLBACK TRANSACTION
EndSave:
 
GO
 
PRINT ' '
PRINT '***********************************************************************'
PRINT ' '
PRINT ' THE DBSYSMON DATABASE, TABLES, AND ASSOCIATED JOBS HAVE BEEN CREATED.'
PRINT ' '
PRINT '***********************************************************************'
PRINT ' '

![MIKES DATA WORK GIT REPO](https://raw.githubusercontent.com/mikesdatawork/images/master/git_mikes_data_work_banner_01.png "Mikes Data Work")        

# SQL Solution For Getting Correct AWS Instance Type
**Post Date: November 19, 2014**




## Contents    
- [About Process](##About-Process)  
- [SQL Logic](#SQL-Logic)  
- [Build Info](#Build-Info)  
- [Author](#Author)  
- [License](#License)       

## About-Process

<p>If you are using SQL Server in an AWS environment then you'll need to setup a system by which you can determine the memory or disk needs. The AWS charge model is pretty fair. You pay for what you use. How do you know if you need a larger AWS Instance Type or a lessor AWS Instance Type. By the way; an 'Instance Type' is how Amazon refers to the different Memory Packages you can utilize whenever you create or configure your Database Server Environments.
What can you do to configure the database environment in such a way that you can get a basic metric for how much is being used?
Well… You can do this directly with just a handful of objects. It's basically a slim down SQL monitoring solution. You create a single database, and collect the daily performance information with a few queries.

In my case I created a database called DBSYSMON. The name is self explanatory meaning 'Database System Monitor' because I am only collecting performance information that is associated with the Database system it's self.
The juicy part of this post is at the very bottom ( after you have created all the corresponding objects ).
The SQL logic below creates the following objects to help you get things going.

Database:   DBSYSMON
Table:      SDIVFS_IO_STATS
Table:      SDOPC_MAIN_TABLE
Agent Job:  DBSYSMON_COLLECTION

Note: This logic was created for SQL Server 2012 editions so I would only recommend running this on newer environments.
The logic first goes to the registry to gather the default Data, and Log file paths so it will create the database according to your existing structure. Additionally; the database is set to simply recovery so you don't have to manage any log growth as a result of your table queries, or general table population.

Ok so I hear you ask; What's the deal with the tables? Let's take this one table at a time.

Table:      SDIVFS_IO_STATS

Notice the prefix SDIVFS. This is basically the acronym for Sys.Dm_Io_Virtual_File_Stats so the table will store all the information from the DMV and has a Primary Key ( int identity ), and a timestamp so you can see when the performance information was collected. As you may already know the sys.dm_io_virtual_file_stats is cumulative, and only good since the last reboot, but… if you're collecting them regularly then you can trend out the data and "since last restart " is no longer the case. Some of the information will not be useful, but some of it will. You'll have to run your own queries against it to see what you can use.

Table:      SDOPC_MAIN_TABLE

Again; the prefix is SDOPC. This is for Sys.Dm_Os_Performance_Counters. Having this information stored into a table with a timestamp can be extremely valuable. As usual; the table has a Primary Key ( int identity ).
Agent Job: DBSYSMON_COLLECTION

No mystery here. The DBSYSMON_COLLECTION job will simply gather up the virtual file stats, and the performance counters, and populate the tables. The SQL logic below will automatically populate the tables upon first run anyway so you can start
running queries against those tables right away 
(I will provide a cursory set of queries at the bottom of this post to get you started). 

The SQL Agent Job is designed to run every 15 minutes, and is created under a sample SQL Service Account called 

MyDomain\MyServiceAccount

The Job has two steps.
1. Gather All Stats From SDOPC
2. Gather Stats From SDIVFS
I've taken the liberty of adding the 'table create' logic in the SQL Job Steps in case you feel like dropping the database and recreating… the tables will automatically be created, and populated.

The good news the logic can be run across any SQL Server 2012 instance, and it will create the database in the correct location regardless of the instance name.
Unless you need data beyond 6 months or so I would say it would be a good idea to create a 3rd Job step which includes some house cleaning. Basically removing rows that are older than 6 months, or whatever the limit you feel is best.  


To run this logic you will need SQL 'sysadmin' rights.
 
The following SQL logic creates the database: DBSYSMON
 
DBSYSMON is where database system performance information is stored
for trending, reporting etc.
 
DBSYSMON is home for the following tables
 
sdopc_main_table
sdivfs_io_stats
 
This logic will also create the tables, and the SQL Agent jobs that
populate them.
 
This code can be run on any SQL 2012 environment.
 
Note:
When Jobs are create they will use the rights of the SQL Service account:
INT\SQLDatabase
 
IF this account does not exist; the Job will need to be altered to include
the standing SQL Service account on whatever server this code has been deployed.


## SQL-Logic
```SQL
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
```

Here are a couple queries you can use to get some useful information out of the tables.
Here's some SQL query logic to determine what the recommended amount of memory is needed for SQL Server according to the performance hit that is being carried out by your applications, or other queries.  Keep in mind that are natural swings in the performance of any database system and you shouldn't haphazardly add memory, or reconfigure memory for your environment based on a few results from this query.  The good news is because the information is stored in the new DBSYSMON database, and you have a timestamp associated with the performance information you can begin to trend out the average swings in performance, and provision the necessary AWS Instane Types with actual guaranteed performance data to prove the Instance Type configuration that you need.
Whats better is that if the 'recommended memory value' is below that of existing configuration you can remove the Memory from AWS accordingly for the correct 'Intance Type'  or ( memory packages ) so the Database systems that are less performance intensive can be properly managed with lower AWS 'Instance Type'</p>     



## SQL-Logic
```SQL
select
 
                'rsm_timestamp'                              = datename(dw, rsm.timestamp) + ' ' + convert(char, rsm.timestamp, 9)
 
,               'rsm_cntr_value'                              = rsm.cntr_value
 
,               'ssm_cntr_value'                              = ssm.cntr_value
 
,               'recommended_memory_value'              = cast (rsm.cntr_value + ssm.cntr_value / 100 as varchar(10)) + ' mb'
 
from
 
                (select timestamp, cntr_value from sdopc_main_table where counter_name = 'Reserved Server Memory (KB)' ) rsm
 
                join
 
                (select timestamp, cntr_value from sdopc_main_table where counter_name = 'Stolen Server Memory (KB)' ) ssm on rsm.timestamp = ssm.[timestamp] where
 
                rsm.cntr_value &gt; 0
 
order by
 
                rsm.timestamp desc
```

This SQL query logic will basically return all the access times to the data.  Stalls will show you how long queries are waiting etc.  You can use this to determine the AWS Instance Type for storage.  I will try to include some queries later on with conversions from MS to something human readable.

## SQL-Logic
```SQL
1
2
3
4	select
     *
from
     sdivfs_io_stats
```


[![WorksEveryTime](https://forthebadge.com/images/badges/60-percent-of-the-time-works-every-time.svg)](https://shitday.de/)

## Build-Info

| Build Quality | Build History |
|--|--|
|<table><tr><td>[![Build-Status](https://ci.appveyor.com/api/projects/status/pjxh5g91jpbh7t84?svg?style=flat-square)](#)</td></tr><tr><td>[![Coverage](https://coveralls.io/repos/github/tygerbytes/ResourceFitness/badge.svg?style=flat-square)](#)</td></tr><tr><td>[![Nuget](https://img.shields.io/nuget/v/TW.Resfit.Core.svg?style=flat-square)](#)</td></tr></table>|<table><tr><td>[![Build history](https://buildstats.info/appveyor/chart/tygerbytes/resourcefitness)](#)</td></tr></table>|

## Author

[![Gist](https://img.shields.io/badge/Gist-MikesDataWork-<COLOR>.svg)](https://gist.github.com/mikesdatawork)
[![Twitter](https://img.shields.io/badge/Twitter-MikesDataWork-<COLOR>.svg)](https://twitter.com/mikesdatawork)
[![Wordpress](https://img.shields.io/badge/Wordpress-MikesDataWork-<COLOR>.svg)](https://mikesdatawork.wordpress.com/)


## License
[![LicenseCCSA](https://img.shields.io/badge/License-CreativeCommonsSA-<COLOR>.svg)](https://creativecommons.org/share-your-work/licensing-types-examples/)

![Mikes Data Work](https://raw.githubusercontent.com/mikesdatawork/images/master/git_mikes_data_work_banner_02.png "Mikes Data Work")


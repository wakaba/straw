@@@@

create procedure `lock_process_task` (in `time` double)
begin
  declare exit handler for not found rollback;
  start transaction;
  select process_id
      into @process_id
      from process_task
      where running_since = 0 and run_after <= `time`
      order by run_after asc limit 1;
  update process_task set running_since = `time`
      where process_id = @process_id;
  commit;
end

@@@@

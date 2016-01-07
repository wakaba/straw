create table if not exists `fetch_source` (
  `source_id` bigint unsigned not null,
  `fetch_key` binary(80) not null,
  `origin_key` binary(40) default null,
  `fetch_options` mediumblob not null,
  `schedule_options` mediumblob not null,
  primary key (`source_id`),
  key (`fetch_key`),
  key (`origin_key`)
) default charset=binary engine=innodb;

create table if not exists `fetch_task` (
  `fetch_key` binary(80) not null,
  `fetch_options` mediumblob not null,
  `run_after` double not null,
  `running_since` double not null,
  primary key (`fetch_key`),
  key (`run_after`),
  key (`running_since`)
) default charset=binary engine=innodb;

create table if not exists `fetch_result` (
  `fetch_key` binary(80) not null,
  `fetch_options` mediumblob not null,
  `result` mediumblob not null,
  `expires` double not null,
  primary key (`fetch_key`),
  key (`expires`)
) default charset=binary engine=innodb;

create table if not exists `fetch_error` (
  `fetch_key` binary(80) not null,
  `origin_key` binary(40) default null,
  `error` mediumblob not null,
  `timestamp` double not null,
  key (`fetch_key`, `timestamp`),
  key (`origin_key`, `timestamp`),
  key (`timestamp`)
) default charset=binary engine=innodb;

create table if not exists `strict_fetch_subscription` (
  `fetch_key` binary(80) not null,
  `process_id` bigint unsigned not null,
  primary key (`fetch_key`, `process_id`),
  key (`process_id`)
) default charset=binary engine=innodb;

create table if not exists `origin_fetch_subscription` (
  `origin_key` binary(40) not null,
  `process_id` bigint unsigned not null,
  primary key (`origin_key`, `process_id`),
  key (`process_id`)
) default charset=binary engine=innodb;

create table if not exists `stream` (
  `stream_id` bigint unsigned not null,
  primary key (`stream_id`)
) default charset=binary engine=innodb;

create table if not exists `stream_item_data` (
  `stream_id` bigint unsigned not null,
  `item_key` binary(40) not null,
  `channel_id` tinyint unsigned not null,
  `data` mediumblob not null,
  `timestamp` double not null,
  `updated` double not null,
  primary key (`stream_id`, `item_key`, `channel_id`),
  key (`stream_id`, `timestamp`),
  key (`stream_id`, `updated`)
) default charset=binary engine=innodb;

create table if not exists `stream_subscription` (
  `stream_id` bigint unsigned not null,
  `process_id` bigint unsigned not null,
  `last_updated` double not null,
  primary key (`stream_id`, `process_id`),
  key (`process_id`)
) default charset=binary engine=innodb;

create table if not exists `process_task` (
  `task_id` bigint unsigned not null,
  `process_id` bigint unsigned not null,
  `process_args_sha` binary(40) not null,
  `process_args` mediumblob not null,
    -- fetch_key
    -- stream_id
  `run_after` double not null,
  `running_since` double not null,
  primary key (`task_id`),
  unique key (`process_id`, `process_args_sha`),
  key (`run_after`),
  key (`running_since`)
) default charset=binary engine=innodb;

create table if not exists `process` (
  `process_id` bigint unsigned not null,
  `process_options` mediumblob not null,
    -- input_sources_ids
    -- input_origins
    -- input_stream_ids
    -- input_channel_mappings
    --   {$stream_id: {$channel_id: $channel_id}}
    -- steps
    -- output_stream_id
  primary key (`process_id`)
) default charset=binary engine=innodb;

create table if not exists `process_error` (
  `process_id` bigint unsigned not null,
  `error` mediumblob not null,
  `timestamp` double not null,
  key (`process_id`, `timestamp`),
  key (`timestamp`)
) default charset=binary engine=innodb;

create table if not exists `sink` (
  `sink_id` bigint unsigned not null,
  `stream_id` bigint unsigned not null,
  `channel_id` tinyint unsigned not null,
  primary key (`sink_id`),
  key (`stream_id`)
) default charset=binary engine=innodb;

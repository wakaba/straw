
create table `fetch_source` (
  `source_id` bigint unsigned not null,
  `fetch_key` varbinary(80) not null,
  `fetch_options` mediumblob not null,
  `schedule_options` mediumblob not null,
  primary key (`source_id`),
  key (`fetch_key`)
) default charset=binary engine=innodb;

create table `fetch_task` (
  `fetch_key` varbinary(80) not null,
  `fetch_options` mediumblob not null,
  `run_after` double not null,
  `running_since` double not null,
  primary key (`fetch_key`),
  key (`run_after`),
  key (`running_since`)
) default charset=binary engine=innodb;

create table `fetch_result` (
  `fetch_key` varbinary(80) not null,
  `fetch_options` mediumblob not null,
  `result` mediumblob not null,
  `expires` double not null,
  primary key (`fetch_key`),
  key (`expires`)
) default charset=binary engine=innodb;

create table `strict_fetch_subscription` (
  `fetch_key` varbinary(80) not null,
  `process_id` bigint unsigned not null,
  primary key (`fetch_key`, `process_id`),
  key (`process_id`)
) default charset=binary engine=innodb;

create table `origin_fetch_subscription` (
  `origin_key` varbinary(80) not null,
  `process_id` bigint unsigned not null,
  primary key (`origin_key`, `process_id`),
  key (`process_id`)
) default charset=binary engine=innodb;

create table `stream` (
  `stream_id` bigint unsigned not null,
  primary key (`stream_id`)
) default charset=binary engine=innodb;

create table `stream_item_data` (
  `stream_id` bigint unsigned not null,
  `item_key` varbinary(40) not null,
  `channel_id` tinyint unsigned not null,
  `data` mediumblob not null,
  `timestamp` double not null,
  `updated` double not null,
  primary key (`stream_id`, `item_key`, `channel_id`),
  key (`stream_id`, `timestamp`),
  key (`stream_id`, `updated`)
) default charset=binary engine=innodb;

create table `stream_subscription` (
  `stream_id` bigint unsigned not null,
  `process_id` bigint unsigned not null,
  `last_updated` double not null,
  primary key (`stream_id`, `process_id`),
  key (`process_id`)
) default charset=binary engine=innodb;

create table `process_task` (
  `process_id` bigint unsigned not null,
  `process_options` mediumblob not null,
    -- fetch_key
    -- stream_id
    --   channel_id mappings
  `run_after` double not null,
  `running_since` double not null,
  primary key (`process_id`),
  key (`run_after`),
  key (`running_since`)
) default charset=binary engine=innodb;

create table `process` (
  `process_id` bigint unsigned not null,
  `process_options` mediumblob not null,
    -- steps
    -- output_stream_id
  primary key (`process_id`)
) default charset=binary engine=innodb;

create table `sink` (
  `sink_id` bigint unsigned not null,
  `stream_id` bigint unsigned not null,
  `channel_id` tinyint unsigned not null,
  primary key (`sink_id`),
  key (`stream_id`)
) default charset=binary engine=innodb;

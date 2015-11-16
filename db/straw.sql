create table if not exists `stream_process` (
  `stream_id` bigint unsigned not null,
  `data` mediumblob not null,
  `fetch_key` varbinary(80) default null,
  `created` double not null,
  `updated` double not null,
  primary key (`stream_id`),
  key (`fetch_key`),
  key (`created`),
  key (`updated`)
) default charset=binary engine=innodb;

create table if not exists `stream_item` (
  `stream_id` bigint unsigned not null,
  `key` varbinary(40) not null,
  `data` mediumblob not null,
  `timestamp` double not null,
  `updated` double not null,
  primary key (`stream_id`, `key`),
  key (`key`),
  key (`timestamp`),
  key (`updated`)
) default charset=binary engine=innodb;

create table if not exists `stream_subscription` (
  `src_stream_id` bigint unsigned not null,
  `dst_stream_id` bigint unsigned not null,
  `expires` double not null,
  primary key (`src_stream_id`, `dst_stream_id`),
  key (`dst_stream_id`),
  key (`expires`)
) default charset=binary engine=innodb;

create table if not exists `stream_process_queue` (
  `stream_id` bigint unsigned not null,
  `run_after` double not null,
  `running_since` double not null,
  primary key (`stream_id`),
  key (`run_after`),
  key (`running_since`)
) default charset=binary engine=innodb;

create table if not exists `fetch` (
  `key` varbinary(80) not null,
  `data` mediumblob not null,
  `expires` double not null,
  primary key (`key`),
  key (`expires`)
) default charset=binary engine=innodb;

create table if not exists `fetch_subscription` (
  `key` varbinary(80) not null,
  `dst_stream_id` bigint unsigned not null,
  `expires` double not null,
  primary key (`key`, `dst_stream_id`),
  key (`dst_stream_id`),
  key (`expires`)
) default charset=binary engine=innodb;

create table if not exists `fetch_queue` (
  `key` varbinary(80) not null,
  `run_after` double not null,
  `running_since` double not null,
  primary key (`key`),
  key (`run_after`),
  key (`running_since`)
) default charset=binary engine=innodb;

create table if not exists `fetch_result` (
  `key` varbinary(80) not null,
  `data` mediumblob not null,
  `expires` double not null,
  primary key (`key`),
  key (`expires`)
) default charset=binary engine=innodb;

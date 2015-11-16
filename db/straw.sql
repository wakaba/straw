create table if not exists `process` (
  `process_id` bigint unsigned not null,
  `data` mediumblob not null,
  `created` double not null,
  `updated` double not null,
  primary key (`process_id`),
  key (`created`),
  key (`updated`)
) default charset=binary engine=innodb;

create table if not exists `stream_item` (
  `stream_id` bigint unsigned not null,
  `key` varbinary(511) not null,
  `data` mediumblob not null,
  `timestamp` double not null,
  `updated` double not null,
  primary key (`stream_id`, `key`),
  key (`key`),
  key (`timestamp`),
  key (`updated`)
) default charset=binary engine=innodb;

create table if not exists `fetch_result` (
  `process_id` bigint unsigned not null,
  `data` mediumblob not null,
  `timestamp` double not null,
  primary key (`process_id`),
  key (`timestamp`)
) default charset=binary engine=innodb;

create table if not exists `stream_subscription` (
  `stream_id` bigint unsigned not null,
  `process_id` bigint unsigned not null,
  `expires` double not null,
  primary key (`stream_id`, `process_id`),
  key (`process_id`),
  key (`expires`)
) default charset=binary engine=innodb;

create table if not exists `process_queue` (
  `process_id` bigint unsigned not null,
  `run_after` double not null,
  `running_since` double not null,
  primary key (`process_id`),
  key (`run_after`),
  key (`running_since`)
) default charset=binary engine=innodb;
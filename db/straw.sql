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

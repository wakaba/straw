create table if not exists `stream_item` (
  `stream_id` bigint unsigned not null,
  `item_key` varbinary(511) not null,
  `data` mediumblob not null,
  `stream_item_timestamp` double not null,
  primary key (`stream_id`, `item_key`),
  key (`item_key`),
  key (`stream_item_timestamp`)
) default charset=binary engine=innodb;

create database foo;
use foo;

create table bar (id int auto_increment primary key);
insert into bar values (null);
insert into bar select null from bar;
insert into bar select null from bar;
insert into bar select null from bar;
insert into bar select null from bar;
insert into bar select null from bar;
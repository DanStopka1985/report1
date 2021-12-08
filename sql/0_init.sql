--Создадим простую схему данных, это будут индивиды(физ лица) и их идентификаторы(СНИЛС и УИД)
--Заполним их случайными тестовыми данными. 500 тыс физ лиц и по одному идентификатору на каждого.

drop table if exists indiv_code cascade;
drop table if exists indiv cascade;
drop table if exists indiv_code_type;
drop table if exists gender;

--справочники
create table gender(
	id int primary key,
	name text,
	code text unique
);

insert into gender(id, name, code) 
	values (1, 'Мужской', 'MALE'), (2, 'Женский', 'FAMALE');

create table indiv_code_type(
                                id int primary key,
                                name text,
                                code text
);

insert into indiv_code_type(id, name, code)
values (1, 'SNILS', 'SNILS'), (2, 'UID', 'UID');

--Создаем таблицу индивидов(физ. лиц.)
create table indiv(
	id serial primary key,
	sname text,
	fname text,
	mname text,
	bdate date,
	gender_id int references gender(id)
);

--заполняем тестовыми данными, фио, пол, дата рождения (всего 500 тыс)
insert into indiv(sname, fname, mname, gender_id, bdate)
select
	md5(random()::text), md5(random()::text), md5(random()::text), (random() + 1)::int,
	(now() - interval '90 years') + random() * (now() - (now() - interval '90 years'))
from generate_series(1, 500000);

--таблицу идентификаторов индивида
create table indiv_code(
	id serial primary key,
	indiv_id int references indiv(id),
	type_id int references indiv_code_type(id),
	code text,
	from_dt date,
	to_dt date
);

--Добавляем УИД каждому
insert into indiv_code(indiv_id, type_id, code)
select id, 2, md5(random()::text) from indiv;

--Добавляем СНИЛС каждому
insert into indiv_code(indiv_id, type_id, code)
select id, 1, md5(random()::text) from indiv;


--схема
--К этим данным будем запускать различные запросы.
--Будем запускать их в несколько тредов, как бы эмулируя нагрузку многопользовательской системы.
--Для этого будем использовать HikariCP.
--App0.java








--сначала получаем случайный идентификатор индивида (просто выбираем случайным образом строку из идентификаторов)
select code
from indiv_code
where id = (select (random() * max(id))::int from indiv_code);

--и затем ищем полученный код среди имеющихся СНИЛС и по нему получаем индивида
select coalesce(
               (select concat_ws(' ', sname, fname, mname)
                from indiv
                where id = (select indiv_id
                              from indiv_code
                              where code = '6f9900c2285733cd836fe5e03e15ef4d' and type_id = 1)),
               'indiv not found'
           ) indiv;
--Посмотреть как быстро выполняется запрос (выполняется ~100ms)

/*
Вроде бы быстро, но попробуем запустить его 200ми пользователями через эмулятор
    -> выполнить App1
    -> сгенерировать pgbadger (create.bat [у меня для доклада запускается SHIFT+CTRL+B])
    -> посмотреть top timeconsuming queries (ALT+CTRL+J ; CTRL+C ; SHIFT+CTRL+W)
            (в браузере открыть)
        file:///C:/PostgreSQL/data/logs/pg11/a.html#time-consuming-queries
*/

/*
Для 200 условных пользователей общее время выполнения составляет уже около минуты
Для такого малого количества данных удалось получить уже серьезную нагрузку
Самый долгий запрос выполняется около секунды
*/

/*
Чтобы это ускорить, нужно понять, что именно долго работает.
Мы не знаем как Postgres выполняет запросы, каким способом получает данные, мы только говорим, что нужно получить, а как получить - не говорим.
Если вкратце в Postgres есть планировщик, который строит для запроса оптимальный алгоритм выполнения (План запроса).
И затем выполняет этот алгоритм и достает нужные данные. Увидеть этот алгоритм нам поможет explain
https://postgrespro.ru/docs/postgrespro/9.6/sql-explain
подробнее можно ознакомиться
explain представляет план запроса в виде дерева, каждый узел дерева - какое-то действие

Что из этого мы будем смотреть:

ANALYZE - говорит о том, что запрос надо выполнить и замерить, что по факту было затрачено
VERBOSE - вывести дополнительную информацию о выполнении узлов, вывод колонок,
            используемые триггеры, названия псевдонимов и схем
COSTS - показать стоимость выполнения узла (по умолчанию true)
BUFFERS говорит об используемой памяти так же для каждого узла
TIMING - выводить время выполнения узла (по умолчанию true)
FORMAT по умолчанию текст, его мы и будем использовать
*/
--Выполним explain для нашего запроса поиска сначала без параметров.
explain--(verbose, analyse, buffers)
select coalesce(
               (select concat_ws(' ', sname, fname, mname)
                from indiv
                where id = (select indiv_id
                              from indiv_code
                              where code = 'd0cd20f38f1c73cde6db4b8ce2fcffd6' and type_id = 1)),
               'indiv not found'
           ) indiv;



/*
Узлы на нижних уровнях дерева (листьях) представляют собой первичные шаги алгоритма - обычно это сканирование таблиц, индексов, констант.
Родительские узлы - следующие действия. И в корне получается результат выполнения запроса.
COST - стоимость – это относительная величина вычисляемая для выполняемого действия исходя из множества различных факторов,
    в частности настроек pg_settings, статистики, сложности стратегий и прочего. В общем случае чем меньше стоимость - тем быстрее выполняется запрос
Первое число - стоимость запуска, второе - общая стоимость
В нашем случае сначала выполняется Parallel Seq Scan таблицы indiv_code - параллельное последовательное сканирование - обход таблицы целиком c фильтрацией по искомому коду
и типу идентификатора.
Параллельное последовательное сканирование - это обычный seq scan выполняемый несколькими исполнителями параллельно, появилось в версии 9.6
Дальше идет сбор данных от всех исполнителей(Gather).
Узел выше сканирует индекс первичного ключа по полученным данным из дочернего узла (Index Cond: (id = $1))
 (при создании первичного ключа, автоматически создается индекс)
Корневой узел возвращает результат запроса.
Теперь мы знаем как Postgres выполняет наш запрос и можем попытаться что-то изменить, чтобы его ускорить.

Обратите внимание на то, что стоимость выполнения самого нижнего узла и корневого не сильно отличается.
А так как стоимость корневого узла включает в себя стоимость его потомков -
 можно сделать вывод, что основную сложность алгоритма составляет нижний узел (parallel seq scan)
*/

/*Чтобы получить больше информации, выполним explain с параметрами (verbose, analyse, buffers)*/
explain(verbose, analyse, buffers)
select coalesce(
               (select concat_ws(' ', sname, fname, mname)
                from indiv
                where id = (select indiv_id
                              from indiv_code
                              where code = 'd0cd20f38f1c73cde6db4b8ce2fcffd6' and type_id = 1)),
               'indiv not found'
           );

/*
Здесь, кроме стоимости можно увидеть время выполнения каждого узла, какие данные узел возвращает и сколько памяти использует
Shared hit – это количество блоков считанных из кэша Postgres.
Shared read – количество блоков считанных с диска.
Опять же, в общем случае - чем меньше памяти использует запрос, тем он лучше.
Можно увидеть, что и по памяти и по времени нижний узел не сильно отличается от корневого.
Для того, чтобы оптимизировать запрос мы должны изменить план его выполнения.
Как можно изменить план выполнения? Можно разными способами, например изменением настроек или изменением самого запроса.
Для примера отключим распараллеливание последовательного сканирования. и перезапустим explain
*/
set max_parallel_workers_per_gather = 0;
explain(verbose, analyse, buffers)
select coalesce(
               (select concat_ws(' ', sname, fname, mname)
                from indiv
                where id = (select indiv_id
                              from indiv_code
                              where code = 'd0cd20f38f1c73cde6db4b8ce2fcffd6' and type_id = 1)),
               'indiv not found'
           );
/*
Как видим, план изменился, parallel seq scan и gather превратились в seq scan.
Это, для примера изменения стоимости настройками, план конечно же стал хуже,
если можно распараллелить - то лучше распараллелить
Вернем как было
*/
set max_parallel_workers_per_gather = 2;
explain(verbose, analyse, buffers)
select coalesce(
               (select concat_ws(' ', sname, fname, mname)
                from indiv i
                where i.id = (select indiv_id
                              from indiv_code
                              where code = 'd0cd20f38f1c73cde6db4b8ce2fcffd6' and type_id = 1)),
               'indiv not found'
           );

/*
Как мы выяснили, основную сложность алгоритма составляет нижний узел(seq scan), он же выполняется дольше всего и больше всего использует памяти.
Действительно, чтобы найти подходящие нам строки, необходимо просканировать всю таблицу и проверить выполняется ли условие.
Индекс может ускорить подобный поиск.
В нашем плане уже используется один индекс (индекс первичного ключа индивидов) если бы его не было так же пришлось
бы сканировать всю таблицу.
Создадим индекс и по коду идентификатора индивида
*/

create index if not exists indiv_code_idx on indiv_code(code);
/*Снова выполним explain*/
explain(verbose, analyse, buffers)
select coalesce(
               (select concat_ws(' ', sname, fname, mname)
                from indiv i
                where i.id = (select indiv_id
                              from indiv_code
                              where code = 'd0cd20f38f1c73cde6db4b8ce2fcffd6' and type_id = 1)),
               'indiv not found'
           );
/*
План изменился. Теперь вместо сканирования таблицы сканируется наш индекс.
Изменилось и время выполнения и потребление памяти (было Buffers: shared hit=9346; стало Buffers: shared read=3)
В Postgres поддерживается несколько видов индексов (методов доступа), а какой мы создали? В нашем скрипте на создание об этом ничего не сказано - только название и поле.
create index indiv_code_idx on indiv_code(code);
*/

/*
Чтобы посмотреть какой у нас индекс, выполним запрос
*/
select pg_get_indexdef('indiv_code_idx'::regclass);


/*
по умолчанию в Postgres создается btree индекс
ради эксперимента создадим другой индекс на это же поле
Хэш индекс
*/

create index indiv_code_hash_idx on indiv_code using hash (code);
/*И снова выполним explain*/
explain(verbose, analyse, buffers)
select coalesce(
               (select concat_ws(' ', sname, fname, mname)
                from indiv i
                where i.id = (select indiv_id
                              from indiv_code
                              where code = 'd0cd20f38f1c73cde6db4b8ce2fcffd6' and type_id = 1)),
               'indiv not found'
           );
/*
Теперь стал использоваться именно хэш индекс
Сравним предыдущий и текущий планы (dir compare CTRL+D)
И по памяти стало немного лучше. И стоимость меньше. Оптимизатор постгрес пытается выбрать план с наименьшей стоимостью
Почему же тогда Postgres по умолчанию создает индекс btree, который хуже чем хэш?
Для разных запросов разные индексы ведут себя по разному, для каких-то запросов определенные индексы вообще не будут работать.
Postgres не знает какие запросы мы будем выполнять, поэтому по умолчанию разработчики выбрали самый универсальный, который чаще всего работает.
Давайте сравним сколько места на диске какой из индексов занимает
*/

select pg_size_pretty(pg_table_size('indiv_code_hash_idx')) "HASH",
       pg_size_pretty(pg_table_size('indiv_code_idx'))      "BTREE";

/*
Оказывается, что хэш индекс и места занимает меньше, и если мы будем запускать только этот запрос - то нам HASH индекс больше подойдет
удалим btree индекс вообще
*/

drop index indiv_code_idx;

-- Кстати, проверим, как будет выполняться наш запрос 200ми условными пользователями
-- предварительно почистим лог
-- запустим app1


/*
Теперь самый долгий запрос выполняется всего 9 мс, а суммарное время выполнения 200 запросов - 39мс
*/

/*Теперь рассмотрим другой тип запросов – сортировка.*/
/* 2_indivs_ordered_by_snils.sql */

/*
Частая задача – вывод списка с сортировкой по колонке. Для примера будем сортировать индивидов по СНИЛС.
Обычно не нужны сразу все отсортированные данные, нужны постранично, поставим лимит 50
Посмотрим план запроса
*/
explain(verbose, analyze, buffers)
select indiv_id from indiv_code where type_id = 1
order by code
limit 50;


/*
выполняется > 100 мс
есть shared hits из буфера и shared read с диска
нижний узел опять seq scan, gather и потом сортировка
Для уменьшения количества текста, уберу параллельное сканирование
*/

SET max_parallel_workers_per_gather = 0;
explain(verbose, analyze, buffers)
select indiv_id from indiv_code where type_id = 1
order by code
limit 50;

/*
Здесь мы видим полный обход таблицы и только потом сортировку (top-N heapsort)
Т.е. наш индекс для сортировки не используется. Это особенность самой структуры (HASH таблицы),
где пары [хэш-код – ссылка на строку таблицы] хранятся в произвольном порядке.
А теперь снова создадим индекс btree по сортируемому полю.
*/



create index indiv_code_code_idx on indiv_code using btree (code);
/*
выполним explain
*/

explain(verbose, analyze, buffers)
select indiv_id from indiv_code where type_id = 1
order by code
limit 50;
/*
Теперь видно, что при сортировке сканируется индекс, и не полностью, а только 50 записей.
Сама структура b-tree – это упорядоченное сбалансированное дерево, где элементы уже отсортированы.
Ненадолго вернемся к поиску по ключу.
*/

explain(verbose, analyze, buffers)
select code from indiv_code where code = '123';
/*
А здесь по-прежнему используется хэш индекс
удалим его для эксперимента и снова выполним explain
*/
drop index indiv_code_hash_idx;
explain(verbose, analyze, buffers)
select code from indiv_code where code = '123';
/*
Сейчас в плане используется index only scan.
В хэш-индексе хранится только ссылка на строку таблицы, а в btree индексе еще и сами данные.
При использовании BTREE, если необходимые данные уже есть в индексе,
    не нужно идти в саму таблицу и совершать дополнительные считывания с диска – это называется покрывающий индекс для запроса.
*/

/*
Так же и при сортировке по коду, если вывести нам нужно только код, то будет index only scan
*/
explain(verbose, analyze, buffers)
select code from indiv_code order by code limit 50;
/*
Но нам необходимо отсортировать именно ИНДИВИДОВ по СНИЛС, а индивидов в индексе нет
Поэтому просто добавим ключ индивида в индекс.
Когда индекс строится по нескольким колонкам он называется составным

Так же в условии индекса укажем, что нам нужен именно СНИЛС (в условии where)
*/

create index indiv_code_snils_indiv_id_idx on indiv_code(code, indiv_id) where type_id = 1;

explain(verbose, analyze, buffers)
select indiv_id, code from indiv_code where type_id = 1 order by code limit 50;

/*
Теперь используется index only scan и сортировки вообще нет в плане, так как данные уже отсортированы в индексе, к таблице обращений вообще не происходит.
Таким образом мы создали ЧАСТИЧНЫЙ, СОСТАВНОЙ, ПОКРЫВАЮЩИЙ индекс для нашего запроса

Частичный индекс хорош тем, что он занимает меньше места чем индекс без условий.
Важно заметить, что если мы хотим использовать частичный индекс, то в запросе обязательно должно быть условие как в индексе.
*/
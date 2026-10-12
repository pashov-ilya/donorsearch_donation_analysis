-- регионы с наибольшим количеством зарегистрированных доноров.
SELECT uad.region AS "регион",  COUNT(*) AS "кол-во зарегистрированные доноров"
FROM  donorsearch.user_anon_data uad
WHERE region IS NOT NULL
GROUP BY uad.region
ORDER BY 2 DESC 
LIMIT 5;

-- Динамика общего количества донаций в месяц за 2022 и 2023 годы
SELECT DATE_TRUNC('month', da.donation_date)::date AS "месяц", COUNT(*) AS "кол-во донаций"
FROM donorsearch.donation_anon da
WHERE  DATE_TRUNC('month', da.donation_date)::date BETWEEN '2022-01-01' AND '2023-12-31'
GROUP BY 1;

--наиболее активные доноры
SELECT id, confirmed_donations AS "подтверждённые донации" 
FROM donorsearch.user_anon_data uad
ORDER BY 2 DESC 
LIMIT 10;

-- Оценка влияния системы бонусов на зарегистрированные в системе донации
WITH bonus_activity AS (
		SELECT uad.id, uad.confirmed_donations, COALESCE(bon.user_bonus_count, 0) AS user_bonus_count
		FROM donorsearch.user_anon_data uad
		LEFT JOIN donorsearch.user_anon_bonus bon
		ON uad.id = bon.user_id)

SELECT CASE
	   WHEN user_bonus_count > 0
	   THEN 'Получили бонусы'
	   ELSE 'не получили бонусы'
	   END AS "статус бонусов",
	   COUNT(id) AS "кол-во доноров", ROUND(AVG(confirmed_donations), 2) AS "среднее  кол-во донаций"
FROM bonus_activity 
GROUP BY 1;

-- вовлечение новых доноров через социальные сети
SELECT CASE
	   WHEN autho_vk IS TRUE THEN 'ВК'
	   WHEN autho_ok IS TRUE THEN 'одноклассники'
	   WHEN autho_tg IS TRUE THEN 'телеграм'
	   WHEN autho_yandex IS TRUE THEN 'яндекс'
	   WHEN autho_google IS TRUE THEN 'гугл'
	   ELSE 'нет аккаунта'
	   END AS соц_сеть,
	   COUNT(id) AS "кол-во пришедших доноров" , ROUND(AVG(confirmed_donations), 2) AS "сред кол-во донаций"
FROM donorsearch.user_anon_data 
GROUP BY 1;

-- возрастная категория доноров
WITH d_age AS (SELECT id, EXTRACT(YEAR FROM AGE(registration_date,  birth_date)) AS "registration_age"
FROM donorsearch.user_anon_data
WHERE registration_date IS NOT NULL AND birth_date IS NOT NULL
)

SELECT CASE
	   WHEN registration_age < 25 THEN 'до 25 лет'
	   WHEN registration_age BETWEEN 25 AND 34 THEN '25–34 года'
	   WHEN registration_age BETWEEN 35 AND 44 THEN '35–44 года'
	   WHEN registration_age BETWEEN 45 AND 54 THEN '45–54 года'
	   WHEN registration_age >= 55 THEN '55 лет и старше'
       END AS возрастная_группа,
	COUNT(*) AS "количество доноров"
FROM d_age
GROUP BY 1
ORDER BY 2 DESC;

-- активность однократных и повторных доноров
WITH donars AS (SELECT id, confirmed_donations, CASE
	   WHEN confirmed_donations = 1 THEN 'однократный донор'
	   WHEN confirmed_donations > 1 THEN 'повторный донор'
	   END AS d_groups
FROM donorsearch.user_anon_data 
WHERE confirmed_donations >= 1)

SELECT d_groups AS "группа доноров", COUNT(id) AS "кол-во донаров", ROUND(AVG(confirmed_donations), 2) AS "среднее кол-во донаций"
FROM donars 
GROUP BY 1;

-- компоненты крови, которые сдают доноры
SELECT 'whole_blood' AS "компонент", COUNT(*) AS "кол-во согласных" FROM donorsearch.user_anon_data
	   WHERE whole_blood IS TRUE
	   GROUP BY 1
			UNION ALL
SELECT 'plasma', COUNT(*) FROM donorsearch.user_anon_data
	   WHERE plasma IS TRUE
	   GROUP BY 1
	   		UNION ALL
SELECT 'platelets', COUNT(*) FROM donorsearch.user_anon_data
	   WHERE platelets IS TRUE
	   GROUP BY 1
	   		UNION ALL
SELECT 'red_cells', COUNT(*) FROM donorsearch.user_anon_data
	   WHERE red_cells IS TRUE
	   GROUP BY 1
	   		UNION ALL
SELECT 'white_cells', COUNT(*) FROM donorsearch.user_anon_data
	   WHERE white_cells IS TRUE
	   GROUP BY 1
	   		UNION ALL
SELECT 'bone_marrow', COUNT(*) FROM donorsearch.user_anon_data
	   WHERE bone_marrow IS TRUE
	   GROUP BY 1
	   ORDER BY 2 DESC;


-- Дополнительный анализ повторяющихся донорв
WITH donor_activity AS (SELECT u.id, u.confirmed_donations,
	   CASE
	   WHEN confirmed_donations BETWEEN 2 AND 3 THEN '2-3 донации'
	   WHEN confirmed_donations BETWEEN 4 AND 5 THEN '4-5 донации'
	   WHEN confirmed_donations >= 6 THEN '6 и более'
	   END AS donation_group,
	   MIN(a.donation_date) AS first_donation, MAX(a.donation_date)AS last_donation,
	   AGE(MAX(a.donation_date), MIN(a.donation_date)) AS activity_duration,
	    MAX(a.donation_date) - MIN(a.donation_date) AS activity_duration_days,
	     (MAX(a.donation_date) - MIN(a.donation_date)) / (u.confirmed_donations - 1) AS avg_days_between_donations
 FROM donorsearch.user_anon_data u  JOIN donorsearch.donation_anon  a ON u.id = a.user_id
	   WHERE u.confirmed_donations > 1
	   GROUP BY  1,2)
	  
SELECT donation_group AS "диапазон донаций", COUNT(id) AS "кол-во доноров", ROUND(AVG(confirmed_donations),2) AS "среднее кол-во донаций",
	   ROUND(AVG(activity_duration_days) / 365, 2) AS "средняя активность, лет",
	   ROUND(AVG(avg_days_between_donations) / 31 ,2) AS "среднее кол-во мес между донациями"
FROM donor_activity
GROUP BY donation_group
ORDER BY donation_group;


-- Сравнение планируемых данных с фактическими
WITH planned AS (SELECT DISTINCT user_id, donation_date, donation_type
	FROM donorsearch.donation_plan
),
	completed AS (SELECT DISTINCT user_id, donation_date
	FROM donorsearch.donation_anon),
	all_donations AS (SELECT p.user_id, p.donation_date, p.donation_type,
    			   CASE
				   WHEN c.user_id IS NOT NULL AND c.donation_date IS NOT NULL
				   THEN 'было'
				   ELSE 'не было'
				   END AS done
  	FROM planned p LEFT JOIN completed c
  			ON p.user_id= c.user_id AND p.donation_date = c.donation_date)
 
SELECT donation_type AS "вид донации", COUNT(user_id) AS "всего запланированных донаций",
COUNT(user_id) FILTER (WHERE done = 'было') AS "сделано запланированных донаций",
ROUND(COUNT(user_id) FILTER (WHERE done ='было')::NUMERIC
		/ COUNT(user_id) * 100, 2) AS "доля"
FROM all_donations 
GROUP BY 1;







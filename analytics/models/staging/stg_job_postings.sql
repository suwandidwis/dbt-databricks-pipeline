{% set extension_keywords = [
    "No degree mentioned",
    "Health insurance",
    "Dental insurance",
    "Paid time off"]
%}

WITH source as (
    SELECT *
    FROM {{ source('jobs', 'raw_job_postings') }}
    WHERE error IS NOT TRUE
),
parsed as (
    SELECT 
        *,
        FROM_JSON(job_extensions_raw, 'array<string>') AS job_extensions
    FROM source
),
cleaned as (
    SELECT
        job_id,
        job_title,
        TRIM(company_name) as company_name,
        job_location,
        REGEXP_REPLACE(job_via, '^via ', '') as source_platform,
        job_posted_at,
        job_schedule_type,
        job_work_from_home,
        search_time AS searched_at,
        search_date,
        search_term,
        search_location,
        job_salary,
        {{ parse_salary('min') }} AS salary_min,
        {{ parse_salary('max') }} AS salary_max,
        -- the standard salary measure: midpoint of the parsed range (a single value
        -- is its own range). UNIT-AGNOSTIC on purpose — consumers pair it with
        -- salary_period + salary_currency filters; averaging across units is on them
        ({{ parse_salary('min') }} + {{ parse_salary('max') }}) / 2 AS salary_avg,
        NULLIF(REGEXP_EXTRACT(job_salary, 'an? (year|hour|month|day|week)$', 1), '') AS salary_period,
        -- leading marker ('PKR', 'CA$', '₱', ...); a salaried row with NO marker is
        -- assumed USD — stamped explicitly so consumers write salary_currency = 'USD'
        -- instead of remembering what a null means. salary-less rows stay null
        CASE
            WHEN job_salary IS NOT NULL
            THEN COALESCE(NULLIF(TRIM(REGEXP_EXTRACT(job_salary, '^([^0-9]+)', 1)), ''), 'USD')
        END AS salary_currency,
        {% for keyword in extension_keywords -%}
        ARRAY_CONTAINS(
            job_extensions,
            "{{keyword}}"
        ) AS has_{{keyword | lower | replace(' ', '_')}}
        {{- "," if not loop.last}}
        {% endfor %}
    FROM
        parsed
)

SELECT *
FROM cleaned
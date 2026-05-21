# Lesson

## Brief

### Preparation

- Create the conda environment based on the `elt-environment.yml` file. We will also be using google cloud (for which the account was created in the previous unit) in this lesson.

- Please refer to the [Environment Folder](https://github.com/su-ntu-ctp/5m-data-2.1-intro-big-data-eng/tree/main/environments) for the environment files. Please refer to the [installation.md](https://github.com/su-ntu-ctp/5m-data-2.1-intro-big-data-eng/blob/main/installation.md) for setup details.

### Lesson Overview

This lesson introduces data warehouse, ingestion model and dimensional modeling. It also contains hands-on _Transform_ part of ELT (dimensional modeling) with `dbt` and `BigQuery`.

---

## Part 1 - Data Warehouse and Dimensional Modeling

Conceptual knowledge, refer to slides.

---

## Part 2 - Hands-on with dbt and BigQuery


### Exercise 1: Designing and Implementing Star Schema and Snowflake Schema for Liquor Sales Data

> **Note:** The `liquor_sales` folder contains a `README.md` file — that is a dbt-generated file with additional reference links. All the setup steps you need are right here in this lesson.

#### Prerequisites

Before running the dbt project, make sure you have completed the following:

1. Set up your Google Cloud Platform account and confirm you can access the [console](https://console.cloud.google.com/). Copy your GCP project ID.
2. Install the gcloud CLI ([instructions](https://cloud.google.com/sdk/docs/install)) — you may have done this in Lesson 2.2 or during coaching.
3. Authenticate GCP by running: `gcloud auth application-default login`
4. In GCP IAM, grant yourself the **BigQuery Admin** role — you may have done this in Lesson 2.2.
5. Open `liquor_sales/profiles.yml` and replace `<YOUR-GCP-PROJECT-ID>` with your actual GCP project ID.

#### Setup

Open a terminal and navigate to the `liquor_sales` folder:

```bash
cd liquor_sales
conda activate elt
dbt debug
```

`dbt debug` checks that your project is correctly configured and that the connection to BigQuery works. Resolve any errors before continuing.

Next, load the seed CSV files:

```bash
dbt seed
```

In this section, we will be using the `liquor_sales` dataset. This dataset contains liquor sales data from Iowa, and available at [BigQuery Public](https://console.cloud.google.com/bigquery?p=bigquery-public-data&d=iowa_liquor_sales&page=dataset). The dbt project is located at `liquor_sales` directory. This is a **fully completed** dbt project that has been pre-populated for you. Skim through the `.yml` and `.sql` files in the `snapshots` and `models` directory.

The source is defined and configured in `models/sources.yml`. It refers to the `bigquery-public-data.iowa_liquor_sales.sales` table.

A star schema with a `sales` fact table, a `store` dimension table and an incomplete `item` dimension table have been implemented. The `schema.yml` files define the schemas for the fact and dimension tables. They contain the name, description and tests for the primary keys of the tables.

#### Snapshots

A snapshot is a table that contains the current state of a source table. Snapshots enable "looking back in time" at previous data states in their mutable tables. While some source data systems are built in a way that makes accessing historical data possible, this is not always the case. Snapshots implement _type-2 Slowly Changing Dimensions_ over mutable source tables. These Slowly Changing Dimensions (or SCDs) identify how a row in a table changes over time.

There is a snapshot for the `store` dimension table defined in `snapshots/store_snapshot.sql`.

#### Models

The `fact_sales` model is defined in `models/fact_sales.sql`. It is a view that selects from the source table.

The dimension models are nested in a `star` subdirectory. Refer to the `dbt_project.yml` file for the configuration. It uses a custom schema and materialized table.

The `dim_store` model is defined in `dim_store.sql`. It selects from the `store_snapshot` table. The `dim_item` model is defined in `dim_item.sql`. Currently it selects from the source table directly.

Once setup is complete (see Prerequisites above), run the commands below from inside the `liquor_sales` folder with the `elt` environment active.

Since this dbt project has snapshots, run the following command first:

```bash
dbt snapshot
```

Build the models with the following command:

```bash
dbt run
```

If you encounter issues with the above, the following commands may help. Run the below before running `dbt run`:

```bash
dbt clean
dbt debug
```


#### Tests

Tests are defined in `schema.yml` files. They are used to validate the data in the tables. For example, the `dim_store` table has a test that checks if the `store_number` is unique and not null.

Run the tests with the following command:

```bash
dbt test
```

Observe the test results. There should be 1 failing test for the `dim_item` table.

#### Practice

The failing test tells you that `dim_item` currently has duplicate `item_number` values, because it queries directly from the raw source table where the same item can appear in many sales rows. The fix is the same pattern used for `dim_store`: create a **snapshot** to deduplicate item records over time, then point `dim_item` at that snapshot instead.

**Step 1 — Create an item snapshot**

A snapshot captures a slowly-changing dimension. Look at the existing `snapshots/store_snapshot.sql` as your template — you will create a very similar file for items.

Create a new file `snapshots/item_snapshot.sql` with the following content:

```sql
{% snapshot item_snapshot %}

{{
  config(
    target_schema='snapshots',
    unique_key='item_number',
    strategy='timestamp',
    updated_at='updated_at',
  )
}}

WITH
item AS (
    SELECT
        item_number,
        item_description,
        category,
        category_name,
        vendor_number,
        vendor_name,
        pack,
        bottle_volume_ml,
        date
    FROM
        {{ source('iowa_liquor_sales', 'sales') }}
),
grouped_data AS (
    SELECT DISTINCT
        item_number,
        item_description,
        category,
        category_name,
        vendor_number,
        vendor_name,
        pack,
        bottle_volume_ml,
        FIRST_VALUE(date) OVER (PARTITION BY item_number, item_description, category, category_name, vendor_number, vendor_name, pack, bottle_volume_ml ORDER BY date) start_date,
        LAST_VALUE(date) OVER (PARTITION BY item_number, item_description, category, category_name, vendor_number, vendor_name, pack, bottle_volume_ml ORDER BY date) end_date,
    FROM
        item
    QUALIFY RANK() OVER (PARTITION BY item_number, item_description, category, category_name, vendor_number, vendor_name, pack, bottle_volume_ml ORDER BY date) = 1
)
SELECT
    item_number,
    item_description,
    category,
    category_name,
    vendor_number,
    vendor_name,
    pack,
    bottle_volume_ml,
    CAST(start_date AS TIMESTAMP) start_at,
    CAST(LEAD(start_date) OVER (PARTITION BY item_number ORDER BY start_date) AS TIMESTAMP) as end_at,
    IF(LEAD(start_date) OVER (PARTITION BY item_number ORDER BY start_date) IS NULL, CURRENT_TIMESTAMP(), NULL) as updated_at,
FROM
    grouped_data
ORDER BY item_number, start_at, end_at

{% endsnapshot %}
```

Key things to notice (mirroring `store_snapshot.sql`):
- `unique_key='item_number'` — dbt uses this to track changes to each item over time.
- `strategy='timestamp'` with `updated_at='updated_at'` — dbt detects a new version of a row when `updated_at` changes.
- The `QUALIFY RANK() = 1` trick deduplicates rows so each unique combination of item attributes appears only once.

Run the snapshot to materialise it in BigQuery:

```bash
dbt snapshot
```

You should see a new `snapshots.item_snapshot` table appear in your BigQuery dataset.

---

**Step 2 — Update `dim_item` to read from the snapshot**

Open `models/star/dim_item.sql`. It currently reads from the raw source:

```sql
SELECT DISTINCT
    item_number,
    ...
FROM {{ source('iowa_liquor_sales', 'sales') }}
```

Replace its contents with the following, mirroring how `dim_store.sql` reads from `store_snapshot`:

```sql
SELECT
    item_number,
    item_description,
    category,
    category_name,
    vendor_number,
    vendor_name,
    pack,
    bottle_volume_ml,
FROM {{ ref('item_snapshot') }}
WHERE CURRENT_TIMESTAMP > dbt_valid_from AND dbt_valid_to IS NULL
```

The `WHERE` clause filters to only the **current** version of each item (i.e. the row where `dbt_valid_to` is `NULL`), which is how Type 2 SCDs work. This guarantees that each `item_number` appears exactly once, fixing the `unique` test.

Rebuild the models:

```bash
dbt run
```

---

**Step 3 — Add a foreign key test for `item_number` in `fact_sales`**

Open `models/schema.yml`. It already has a `relationships` test for `store_number` that checks the foreign key against `dim_store`. You need to add the same kind of test for `item_number`.

Add the highlighted lines under the `fact_sales` model's columns:

```yaml
      - name: item_number
        description: "The foreign key to the item dimension table"
        tests:
          - relationships:
              arguments:
                to: ref('dim_item')
                field: item_number
```

The full `models/schema.yml` should look like this after your edit:

```yaml
version: 2

models:
  - name: fact_sales
    description: "Fact table for item."
    columns:
      - name: invoice_and_item_number
        description: "The primary key for this table"
        tests:
          - unique
          - not_null
      - name: store_number
        description: "The foreign key to the store dimension table"
        tests:
          - relationships:
              arguments:
                to: ref('dim_store')
                field: store_number
      - name: item_number
        description: "The foreign key to the item dimension table"
        tests:
          - relationships:
              arguments:
                to: ref('dim_item')
                field: item_number
```

---

**Step 4 — Run the tests and confirm they all pass**

```bash
dbt test
```

All tests should now pass. You fixed the failing `unique` test on `dim_item` by sourcing from the snapshot, and you added a new referential integrity test that confirms every `item_number` in `fact_sales` exists in `dim_item`.

---

### Exercise 2: Designing and Implementing Star Schema for Austin Bikeshare Data from Scratch

We will be using the `austin_bikeshare` dataset. This data contains the number of hires of bicycles from Austin Bikes. Data includes start and stop timestamps, station names and ride duration.

It is available at [BigQuery Public](https://console.cloud.google.com/bigquery?ws=!1m4!1m3!3m2!1sbigquery-public-data!2saustin_bikeshare).

We will create a dbt project from scratch and implement a star schema for the data warehouse.


>⚠️ Warning! Make sure that  we are under the folder `5m-data-2.5-data-warehouse`. Many learners make the mistake of running `dbt init austin_bikeshare_demo` inside the `liquor_sales` project folder. Please do not do this! Each dbt project should be within its own project folder. So please return to the root folder `5m-data-2.5-data-warehouse` before running `dbt init austin_bikeshare_demo`.

> Make sure you have activate the `elt` environment using `conda activate elt`

#### Setting up a dbt project from scratch
1. Run `dbt init austin_bikeshare_demo` to create a new dbt project.
    * Choose `bigquery` as the desired database to use
    * Choose `oauth` as the desired authentication method
    * Enter your GCP project ID when asked
    * Enter `austin_bikeshare_demo` as the name of your dbt dataset
    * For threads and job_execution_timeout_seconds, use the default
    * For desired location, choose US (because the public austin_bikeshare dataset resides in US)

Once the initialization is completed, you should have see the following message:
![alt text](assets/dbt_init_msg.PNG)

#### Setting up profiles.yml
Click on the `profiles.yml`, alternatively the `profiles.yml` is located at home folder:
- For `WSL` user, it is located at the WSL folder (`/home/<wsl_username>/.dbt/profiles.yml`)
- For `Mac` user, it is located at the home folder (`~/.dbt/profiles.yml` or `Users/<mac_username>/.dbt/profiles.yml`)

Copy the profiles under `austin_bikeshare_demo` if you have more than one profiles.
Under `austin_bikeshare_demo` folder, create a new file called `profiles.yml` and paste the profile information and save the `profiles.yml`.

Finally, do a `dbt debug` to confirm profiles is good.

> Remember the following :
> - You have open a terminal.
> - Navigate to the `austin_bikeshare_demo` folder by running `cd austin_bikeshare_demo`
> - Make you are in the `elt` environment by running `conda activate elt`
> - Make sure the Bigquery connection is successful by running `dbt debug`

#### Design dbt models
For 2. and 3. below, the learner is advised to go through the liquor_sales DBT project first before returning to complete 2. and 3. below.

2. Add a fact and dimension model.
3. Add tests.


#### Snowflake Schema (Extra)

In a snowflake schema, each dimension can have one or more dimensions. For example, the `item` dimension table can be further normalized into `item`, `category` and `vendor` dimension tables. The `item` dimension table will contain the `category` and `vendor_number` as foreign keys.

For the practices below, create a subdirectory under `models` called `snowflake`.

> 1. Normalize `dim_item` table into `dim_item`, `dim_category` and `dim_vendor` dimension tables.
> 2. Normalize `dim_store` table into `dim_store` and `dim_county` dimension tables.
> 3. Add `schema.yml` with tests for the primary and foreign keys.
> 4. Add a new custom `snowflake` schema with materialized tables in `dbt_project.yml`.
> 5. Run the dbt commands to build the models and run the tests.



## Additional dbt Command (Optional)

- Use `dbt build` can perform dbt run and dbt test concurrently. [Reference](https://docs.getdbt.com/reference/commands/build)
- Use `dbt docs generate` will build a set of documentation based on the description you put in in the schema. [Reference](https://docs.getdbt.com/reference/commands/cmd-docs#dbt-docs-generate)
- Use `dbt docs serve` to run an internal website that contains all your documents. [Reference](https://docs.getdbt.com/reference/commands/cmd-docs#dbt-docs-serve)
- Use `severity:` argument to set if the test should be a failure or just a warning. [Reference](https://docs.getdbt.com/reference/resource-configs/severity)

Please refer to [dbt command reference](https://docs.getdbt.com/reference/dbt-commands) for further information.


### Possible Warning (Optional)

> ⚠️ **Warning!**
>
> **You may encounter warning message as follows:**
> ![alt text](assets/dbt_warning1.PNG)
>
> **or similar message as below:**
> ![alt text](assets/dbt_warning2.PNG)
>
> **To resolve this warning you need to uncomment `arguments` at the `schema.yml` for `fact_sales.sql`. This is under the `models` folder.** 
>
> ![alt text](assets/dbt_solution_warning.PNG)
>
> Reference: https://docs.getdbt.com/reference/deprecations#missingargumentspropertyingenerictestdeprecation

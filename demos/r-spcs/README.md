This is a small demo that builds on top of the TTYD demo and shows how
interactive R can be run in SPCS. The provided code shows how to establish
connection using ODBC driver and OAUTH authentication that leverages SPCS token.

# Prerequisites

1. SPCS service set up with ttyd service and a network policy that allows access
   to cache.nixos.org

2. `SNOWFLAKE_SAMPLE_DATA` setup in account
3. A virtual warehouse accessible to the role that owns SPCS service

# Usage

Run following in the container shell:

```shell
nix develop "github:sfc-gh-vtimofeenko/spcs-ttyd?dir=demos"
```

This will start a development shell with Snowflake ODBC driver and R REPL with
the needed packages pre-installed.

Run following R code to get some sample data from CUSTOMER table in the sample
data set:

```R
con <- DBI::dbConnect(odbc::odbc()
                      , "SnowflakeDSII" # Connection name
                      , token = readLines("/snowflake/session/token", warn = FALSE)
                      , authenticator = 'oauth'
                      , port = 443
                      , warehouse = "ADHOC"
                      , ssl = 'on'
 )
data <- DBI::dbGetQuery(con,"SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER LIMIT 100")
head(data)

```

# Further reading

* [Running R-Studio in Snowpark Container Services][1]

[1]: https://medium.com/@gabriel.mullen/running-rstudio-in-snowpark-container-services-1a71128b2474

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
                      , warehouse = "<virtual warehouse name>"
                      , ssl = 'on'
                      # If you don't want to use the odbc.ini:
                      # , driver = <path to libSnowflake.so>
                      # , account = Sys.getenv("SNOWFLAKE_ACCOUNT")
                      # , SERVER = Sys.getenv("SNOWFLAKE_HOST")
 )
data <- DBI::dbGetQuery(con,"SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER LIMIT 100")
head(data)

```

# How this works

* The flake provides a derivation for Snowflake ODBC driver (file [./snowflake-odbc-driver.nix])
* When the nix dev shell is started, a `odbc.ini` file is constructed in the
  local directory. This file:

  * Points to the appropriate Snowflake ODBC driver's `.so` file in the nix
    store
  * Pre-populates ODBC parameters by reading the env variables that SPCS sets
    by default
* Here's what a working `odbc.ini` looks like:

    ```ini
    [ODBC Data  Sources]
    SnowflakeDSII = Snowflake

    [SnowflakeDSII]
    # This is populated from environment and is set by SPCS
    SERVER = <REDACTED>
    # This is populated from environment and is set by SPCS
    account = <REDACTED>
    Driver = /nix/store/...-snowflake-odbc-driver-3.5.0/lib/libSnowflake.so
    Port = 443
    SSL = on
    Locale = en-US
    Tracing = 0
    # Oauth stuff
    authenticator=OAUTH
    # Optional; token may expire and should be read when connecting
    token= <REDACTED>
    ```

* The dev shell sets the ODBCINI variable to point the user's DSN file to the
  aforementioned `odbc.ini`
* When R'd `DBI::dbConnect` is called, it's reading the user's DSN file
* R's ODBC settings can be read by calling `library(odbc)` and then calling
  `odbcShowConfig()`

# Further reading

* [Running R-Studio in Snowpark Container Services][1]

[1]: https://medium.com/@gabriel.mullen/running-rstudio-in-snowpark-container-services-1a71128b2474

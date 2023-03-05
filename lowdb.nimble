version       = "0.1.1"
author        = "Albert Safin <xzfcpw@gmail.com>" # Original Author of the package
description   = "Low level db_sqlite and db_postgres forks with a proper typing"
license       = "MIT"
srcDir        = "src"

requires "nim >= 0.19.0"
when NimMajor >= 1 and NimMinor >= 9:
  requires "db_connector >= 0.1.0"

skipDirs = @["tests"]

task test_sqlite, "Run the test suite (sqlite)":
  exec "nim c -r tests/tsqlite.nim"

task test_postgres, "Run the test suite (postgres) (NOTE: Start the containers first with `nimble startContainers`)":
  exec "nim c -r tests/tpostgres.nim"

task test, "Run the test suite (all) (NOTE: Start the container first with `nimble startContainers`)":
  testSqliteTask()
  testPostgresTask()

task benchmark, "Compile the benchmark":
  exec "nim c -d:mode=0 -d:release -o:tests/bsqlite.0 tests/bsqlite.nim"
  exec "nim c -d:mode=1 -d:release -o:tests/bsqlite.1 tests/bsqlite.nim"

task docs, "Generate docs":
  rmDir "docs/apidocs"
  exec "nimble doc --outdir:docs/apidocs --project --index:on src/lowdb.nim"


when NimMajor >= 1 and NimMinor >= 2: # Prior nim versions don't support commandLineParams
  import std/[strutils, sequtils, strformat]

  let postgresName = "norm-postgres-testcontainer"
  putEnv("PGHOST", "localhost") ## Mandatory for all Postgres tests
  putEnv("PGUSER", "postgres") ## Mandatory for all Postgres tests
  putEnv("PGPASSWORD", "postgres") ## Mandatory for all Postgres tests
  putEnv("PGDATABASE", "postgres") ## Mandatory for all Postgres tests

  proc asSudo(params: seq[string]): bool =
    return params.anyIt(it == "sudo")

  task startContainers, "Starts a postgres container for running tests against":
    var command = fmt"""docker run -d -e POSTGRES_PASSWORD="postgres" --name {postgresName} --rm -p 5432:5432 postgres"""

    if commandLineParams.asSudo():
      command = fmt"sudo {command}"

    exec command

  task stopContainers, "Stops a postgres container used for norm tests":
    var command = fmt"""docker stop {postgresName}"""

    if commandLineParams.asSudo():
      command = fmt"sudo {command}"

    exec command
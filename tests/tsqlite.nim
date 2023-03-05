import lowdb/sqlite
import std/[math, options, enumerate, unittest, strutils, sequtils, strformat]

suite "Examples":
  test "Opening a connection to a database":
    let db = open(":memory:", "", "", "")
    db.close()

  test "Creating a table":
    let db = open(":memory:", "", "", "")
    db.exec(sql"DROP TABLE IF EXISTS myTable")
    db.exec(sql("""
      CREATE TABLE myTable (
        id integer,
        name varchar(50) not null
      )
    """))
    db.close()

  test "Inserting data":
    let db = open(":memory:", "", "", "")
    db.exec(sql("""
      CREATE TABLE myTable (
        id integer,
        name varchar(50) not null
      )
    """))
    db.exec(sql"INSERT INTO myTable (id, name) VALUES (0, ?)",
            "Jack")
    db.close()

  test "Larger example":
    let db = open(":memory:", "", "", "")

    db.exec(sql"Drop table if exists myTestTbl")
    db.exec(sql("""
      CREATE TABLE myTestTbl (
         Id    INTEGER PRIMARY KEY,
         Name  VARCHAR(50) NOT NULL,
         i     INT(11),
         f     DECIMAL(18,10)
      )
    """))

    db.exec(sql"BEGIN")
    for i in 1..1000:
      db.exec(
        sql"INSERT INTO myTestTbl (name,i,f) VALUES (?,?,?)",
        "Item#" & $i,
        i,
        sqrt(i.float)
      )
    db.exec(sql"COMMIT")

    for x in db.rows(sql"select * from myTestTbl"):
      discard x

    let id = db.tryInsertId(
      sql"INSERT INTO myTestTbl (name,i,f) VALUES (?,?,?)",
      "Item#1001",
      1001,
      sqrt(1001.0)
    )
    discard db.getValue(string, sql"SELECT name FROM myTestTbl WHERE id=?", id).unsafeGet

    db.close()

  test "readme.md":
    #import lowdb/sqlite
    let db = open(":memory:", "", "", "")

    # Insert NULL
    db.exec(sql"CREATE TABLE foo (a, b)")
    db.exec(sql"INSERT INTO foo VALUES (?, ?)", 1, DbNull())

    # Insert binary blob
    db.exec(sql"CREATE TABLE blobs (a BLOB)")
    db.exec(sql"INSERT INTO blobs VALUES (?)", DbBlob "\x00\x01\x02\x03")
    let blobValue = db.getAllRows(sql"SELECT * FROM BLOBS")[0][0].b

    db.close()

    discard blobValue


suite "Select value of type":
  setup:
    let db = open(":memory:", "", "", "")

  teardown:
    close db

  test """
    Given an SQL query that selects a value
    When executing the query
    Then it should return that value as DbValue of the appropriate kind
  """:
    let blobStr1 = "123"
    let blobStr2 = "\0x\0"
    let blobStr3 = "\0\xfe\0"

    let parameterSets: seq[tuple[query: string, expectedValue: Row]] = @[
      ("SELECT 3", @[DbValue(kind: dvkInt, i: 3)]),
      ("SELECT 1.3", @[DbValue(kind: dvkFloat, f: 1.3)]),
      ("SELECT ''", @[DbValue(kind: dvkString, s: "")]),
      ("SELECT 'foo'", @[DbValue(kind: dvkString, s: "foo")]),
      ("SELECT x''", @[DbValue(kind: dvkBlob, b: DbBlob "")]),
      (fmt"SELECT x'{blobStr1.toHex()}'", @[DbValue(kind: dvkBlob, b: DbBlob blobStr1)]),
      (fmt"SELECT x'{blobStr2.toHex()}'", @[DbValue(kind: dvkBlob, b: DbBlob blobStr2)]),
      (fmt"SELECT x'{blobStr3.toHex()}'", @[DbValue(kind: dvkBlob, b: DbBlob blobStr3)]),
      ("SELECT NULL", @[DbValue(kind: dvkNull)])
    ]

    for params in parameterSets:
      # Given
      let query = sql params.query

      # When
      let row = db.getRow(query).get()

      # Then
      check row == params.expectedValue


suite "Bind value of type":
  setup:
    let db = open(":memory:", "", "", "")

  teardown:
    close db

  test """
    Given an SQL query that selects the type of some value
    When executing the query
    Then it should return the type name as DbValue of kind dvkString
  """:
    let parameters: seq[tuple[queryValue: DbValue, expectedTypeName: string]] = @[
      (0.dbValue(), "integer"),
      (dbValue(1.3), "real"),
      ("".dbValue(), "text"),
      (DbBlob("").dbValue(), "blob"),
      (DbNull().dbValue(), "null"),
      (nil.dbValue(), "null")
    ]

    for param in parameters:
      # Given
      let query = sql "SELECT typeof(?)"

      # When
      let row = db.getRow(query, param.queryValue).unsafeGet

      # Then
      let expectedValue: Row = @[DbValue(kind: dvkString, s: param.expectedTypeName)]
      check row == expectedValue


suite "getRow()":
  setup:
    let db = open(":memory:", "", "", "")

  teardown:
    close db

  test """
    Given a query that returns rows
    When executing the query with getRow
    Then it should return only the first row if available
  """:
    let parameterSets: seq[tuple[query: string, expectedValue: Option[Row]]] = @[
      ( # No row available, return nothing
        "SELECT 'a' WHERE 1=0",
        none Row
      ),
      (
        "SELECT 'a'",
        some @[DbValue(kind: dvkString, s: "a")]
      ),
      (
        "SELECT 'a' UNION ALL SELECT 'b'",
        some @[DbValue(kind: dvkString, s: "a")]
      )
    ]

    for params in parameterSets:
      # Given
      let query = sql params.query

      # When
      let row = db.getRow(query)

      # Then
      check row == params.expectedValue


suite "getValue()":
  setup:
    let db = open(":memory:", "", "", "")

  teardown:
    close db

  test """
    Given a query that returns rows
    When executing the query with getValue to get a value of a specific type
    Then it should return only the first column of the first row in the specified type, if available
  """:
    template test(queryStr: string, t: typedesc[typed], expectedValue: typed) =
      # Given
      let query = sql queryStr

      # When
      let value = db.getValue(t, query)

      # Then
      check value == expectedValue

    test( # No rows
      "SELECT 'a' WHERE 1=0",
      int64,
      none(int64)
    )

    test(
      "SELECT '1234'",
      int64,
      some 1234.int64
    )


    test(
      "SELECT 1234",
      int64,
      some 1234.int64
    )

    test(
      "SELECT 'abcd'",
      string,
      some "abcd"
    )

    test(
      "SELECT '1.234'",
      float64,
      some 1.234.float64
    )

    test(
      "SELECT 1.234",
      float64,
      some 1.234.float64
    )

    test( # 2 Rows
      "SELECT 'a' UNION ALL SELECT 5",
      string,
      some "a"
    )

    type Foo = enum
      A, B, C
    test(
      "SELECT 1",
      Foo,
      some Foo.B
    )


suite "getAllRows()":
  setup:
    let db = open(":memory:", "", "", "")

  teardown:
    close db


  test """
    Given a query that returns 1 row of multiple columns,
    When executing the query with getAllRows
    Then it should return 1 row with all columns
  """:
    # Given
    let query = "SELECT ?, ?, ?, ?"

    # When
    let rows: seq[Row] = db.getAllRows(sql query, "a", "b", "c", "d")

    # Then
    let expectedValue: seq[Row] = @[
      @[
        DbValue(kind: dvkString, s: "a"),
        DbValue(kind: dvkString, s: "b"),
        DbValue(kind: dvkString, s: "c"),
        DbValue(kind: dvkString, s: "d")
      ]
    ]
    check rows == expectedValue

  test """
    Given a query that returns multiple rows of 1 column,
    When executing the query with getAllRows
    Then it should return multiple rows with one column each
  """:
    # Given
    let query = "SELECT 'a' UNION ALL SELECT 'b' UNION ALL SELECT 'c' UNION ALL SELECT 'd'"

    # When
    let rows: seq[Row] = db.getAllRows(sql query)

    # Then
    let expectedValue = @[
      @[DbValue(kind: dvkString, s: "a")],
      @[DbValue(kind: dvkString, s: "b")],
      @[DbValue(kind: dvkString, s: "c")],
      @[DbValue(kind: dvkString, s: "d")],
    ]
    check rows == expectedValue

  test """
    Given a query that returns more rows than its limit,
    When executing the query with getAllRows
    Then it should return as many rows as the limit is
  """:
    # Given
    let query = "SELECT 'a' UNION ALL SELECT 'b' UNION ALL SELECT 'c' UNION ALL SELECT 'd' LIMIT ?"

    # When
    let rows = db.getAllRows(sql query, 2)

    # Then
    let expectedValue = @[
      @[DbValue(kind: dvkString, s: "a")],
      @[DbValue(kind: dvkString, s: "b")],
    ]
    check rows == expectedValue


suite "rows-iterator":
  setup:
    let db = open(":memory:", "", "", "")

  teardown:
    close db

  test """
    Given a table with multiple columns and rows in it and a query that selects all of it
    When executing it with rows
    Then it should provide an iterator over all rows in the table
  """:
    # Given
    db.exec sql"""
      CREATE TABLE t1 (
          Id    INTEGER PRIMARY KEY,
          S     TEXT
      )
    """
    db.exec sql"INSERT INTO t1 VALUES(?, ?)", 1, "foo"
    db.exec sql"INSERT INTO t1 VALUES(?, ?)", 2, "bar"
    var n = 0

    # When
    let rows: seq[Row] = db.rows(sql"SELECT * FROM t1").toSeq()

    # Then
    let expectedValue: seq[Row] = @[
      @[ DbValue(kind: dvkInt, i: 1), DbValue(kind: dvkString, s: "foo")],
      @[ DbValue(kind: dvkInt, i: 2), DbValue(kind: dvkString, s: "bar")]
    ]
    check rows == expectedValue

  test """
    Given 2 queries that select data
    When executing them with rows with one being nested inside the other
    Then both iterators should iterate over their query results
  """:
    # Given
    var res = ""

    # When
    for i in db.rows sql"SELECT 'a' UNION ALL SELECT 'b' UNION ALL SELECT 'c'":
      res.add i[0].s
      for j in db.rows sql"SELECT '1' UNION ALL SELECT '2' UNION ALL SELECT '3'":
        res.add j[0].s

    # Then
    check res == "a123b123c123"


suite "instantrows-iterator":
  setup:
    let db = open(":memory:", "", "", "")

  teardown:
    close db

  test """
    Given a table with multiple columns and rows in it and a query that selects all of it
    When executing it with instantRows
    Then it should provide an iterator over all rows in the table where all column-values are strings
  """:
    # Given
    db.exec sql"""
      CREATE TABLE t1 (
          Id    INTEGER PRIMARY KEY,
          S     TEXT
      )
    """
    db.exec sql"INSERT INTO t1 VALUES(?, ?)", 1, "foo"
    db.exec sql"INSERT INTO t1 VALUES(?, ?)", 2, "bar"

    # When
    for index, row in enumerate(db.instantRows(sql"SELECT * FROM t1")):
      # Then
      case index
      of 0:
        check row[0] == "1"
        check row[1] == "foo"

      of 1:
        check row[0] == "2"
        check row[1] == "bar"

      else:
        raise newException(ValueError, "Unreachable statement")

      check row.len == 2

  test """
    Given an iterator via instantRows iterating over a table with data
    When accessing a row in it with index and type that DbValue has a kind for
    Then it should extract the value from DbValue as that type
  """:
    # Given
    db.exec sql"""
      CREATE TABLE t1 (
          Id    INTEGER PRIMARY KEY,
          S     TEXT
      )
    """
    db.exec sql"INSERT INTO t1 VALUES(?, ?)", 1, "foo"
    db.exec sql"INSERT INTO t1 VALUES(?, ?)", 2, "bar"

    # When
    for index, row in enumerate(db.instantRows(sql"SELECT * FROM t1")):
      # Then
      case index
      of 0:
        check row[0, int64] == 1
        check row[1, string] == "foo"

      of 1:
        check row[0, int64] == 2
        check row[1, string] == "bar"

      else:
        raise newException(ValueError, "Unreachable statement")

      check row.len == 2


suite "insertID":
  setup:
    let db = open(":memory:", "", "", "")

  teardown:
    close db

  test """
    Given a table and an insertion query
    When inserting a value into it using insertID
    Then it should insert the row with a generated id.
  """:
    let dbConn = open(":memory:", "", "", "")
    # Given
    dbConn.exec sql"CREATE TABLE t1 (id INTEGER PRIMARY KEY, value TEXT)"

    # When
    let id = dbConn.insertID sql"INSERT INTO t1(value) VALUES ('a')"

    # Then
    let rows: seq[Row] = dbConn.getAllRows(sql "SELECT * FROM t1").toSeq()
    let expectedValue: seq[Row] = @[
      @[
        DbValue(kind: dvkInt, i: id),
        DbValue(kind: dvkString, s: "a")
      ]
    ]
    check rows == expectedValue


suite "Prepared statement finalization":
  setup:
    let db = open(":memory:", "", "", "")

  teardown:
    close db

  test """
    Given a table and an insert query
    When executing that query with tryExec and an unused additional/invalid parameters
    Then return false and don't insert any rows
  """:
    # Given
    db.exec sql"CREATE TABLE t1 (id INTEGER PRIMARY KEY)"
    let query = "INSERT INTO t1 VALUES (1)"

    # When
    let wasSuccessful = db.tryExec(sql query, 123)

    # Then
    check wasSuccessful == false

    let rows: seq[Row] = db.getAllRows(sql"SELECT * FROM t1")
    let expectedValue: seq[Row] = @[]
    check rows == expectedValue

  test """
    Given a table with a check that always fails and an insert query
    When executing that query with tryExec
    Then return false and don't insert any rows
  """:
    # Given
    db.exec sql"CREATE TABLE t1 (id INTEGER PRIMARY KEY, CHECK (0))"
    let query = "INSERT INTO t1 VALUES (1)"

    # When
    let wasSuccessful = db.tryExec(sql query)

    # Then
    check wasSuccessful == false

    let rows: seq[Row] = db.getAllRows(sql"SELECT * FROM t1")
    let expectedValue: seq[Row] = @[]
    check rows == expectedValue

  test """
    Given a table and an insert query
    When executing that query with exec and an unused additional/invalid parameters
    Then raise DbError false and don't insert any rows
  """:
    # Given
    db.exec sql"CREATE TABLE t1 (id INTEGER PRIMARY KEY)"
    let query = "INSERT INTO t1 VALUES (1)"

    # When
    expect DbError: db.exec(sql query, 123)

    # Then
    let rows: seq[Row] = db.getAllRows(sql"SELECT * FROM t1")
    let expectedValue: seq[Row] = @[]
    check rows == expectedValue

  test """
    Given a table with a check that always fails and an insert query
    When executing that query with exec
    Then raise DbError and don't insert any rows
  """:
    # Given
    db.exec sql"CREATE TABLE t1 (id INTEGER PRIMARY KEY, CHECK (0))"
    let query = "INSERT INTO t1 VALUES (1)"

    # When
    expect DbError: db.exec(sql query)

    # Then
    let rows: seq[Row] = db.getAllRows(sql"SELECT * FROM t1")
    let expectedValue: seq[Row] = @[]
    check rows == expectedValue

  test """
    Given a query
    When executing the query with rows and superfluous/invalid parameters
    Then raise DbError
  """:
    # Given
    let query = "SELECT 1"

    # When
    # Then
    expect DbError:
      for row in db.rows(sql query, 123): discard

  # TODO: find a way to trigger execution failure for `rows()`.

  test """
    Given a query
    When executing the query with instantRows and superfluous/invalid parameters
    Then raise DbError
  """:
    # Given
    let query = "SELECT 1"

    # When
    # Then
    expect DbError:
      for row in db.instantRows(sql query, 123): discard

  # TODO: find a way to trigger execution failure for `instantRows()`.

  test """
    Given a query
    When executing the query with instantRows with columns and superfluous/invalid parameters
    Then raise DbError
  """:
    # Given
    var columns: DbColumns
    let query = "SELECT 1"

    expect DbError:
      for row in db.instantRows(columns, sql query, 123): discard

  # TODO: find a way to trigger execution failure for `instantRows()` with columns.

  test """
    Given a table and an insert query
    When executing the query with tryInsertID and superfluous/invalid parameters
    Then return -1 and don't insert any rows
  """:
    # Given
    db.exec sql"CREATE TABLE t1 (id INTEGER PRIMARY KEY)"
    let query = "INSERT INTO t1 VALUES (1)"

    # When
    let insertedId = db.tryInsertID(sql query, 123)

    # Then
    let expectedId = -1
    check insertedId == expectedId

    let rows: seq[Row] = db.getAllRows(sql"SELECT * FROM t1")
    let expectedValue: seq[Row] = @[]
    check rows == expectedValue

  test """
    Given a table with a check that always fails and an insert query
    When executing the query with tryInsertID
    Then return -1 and don't insert any rows
  """:
    # Given
    db.exec sql"CREATE TABLE t1 (id INTEGER PRIMARY KEY, CHECK (0))"
    let query = "INSERT INTO t1 VALUES (1)"
    # When
    let insertedId = db.tryInsertID(sql query)

    # Then
    let expectedId = -1
    check insertedId == expectedId

    let rows: seq[Row] = db.getAllRows(sql"SELECT * FROM t1")
    let expectedValue: seq[Row] = @[]
    check rows == expectedValue

  test """
    Given a table and an insert query
    When executing the query with insertID and superfluous/invalid parameters
    Then raise a DBError and don't insert any rows
  """:
    # Given
    db.exec sql"CREATE TABLE t1 (id INTEGER PRIMARY KEY)"
    let query = "INSERT INTO t1 VALUES (1)"

    # When
    expect DbError: discard db.insertID(sql query, 123)

    # Then
    let rows: seq[Row] = db.getAllRows(sql"SELECT * FROM t1")
    let expectedValue: seq[Row] = @[]
    check rows == expectedValue

  test """
    Given a table with a check that always fails and an insert query
    When executing the query with insertID
    Then raise a DBError and don't insert any rows
  """:
    # Given
    db.exec sql"CREATE TABLE t1 (id INTEGER PRIMARY KEY, CHECK (0))"
    let query = "INSERT INTO t1 VALUES (1)"

    # When
    expect DbError: discard db.insertID(sql query)

    # Then
    let rows: seq[Row] = db.getAllRows(sql"SELECT * FROM t1")
    let expectedValue: seq[Row] = @[]
    check rows == expectedValue


suite "sugar":
  setup:
    let db = open(":memory:", "", "", "")

  teardown:
    close db

  test """
    Given a value that can be converted into DbValue
    When using the "dbValue" proc on that value
    Then it should be converted into a DBValue instance
  """:
    check DbValue(kind: dvkInt, i: 3) == dbValue 3
    check DbValue(kind: dvkString, s: "a") == dbValue "a"
    check DbValue(kind: dvkFloat, f: 1.23) == dbValue 1.23
    check DbValue(kind: dvkNull) == dbValue nil
    check DbValue(kind: dvkBlob, b: DbBlob "123") == dbValue DbBlob "123"

    type Foo = enum
      A, B, C
    check DbValue(kind: dvkInt, i: 1) == dbValue Foo.B

  test """
    Given a value that can be converted into DbValue
    When using "?" before that value
    Then it should be converted into a DBValue instance
  """:
    check DbValue(kind: dvkInt, i: 3) == ?3
    check DbValue(kind: dvkString, s: "a") == ?"a"
    check DbValue(kind: dvkFloat, f: 1.23) == ?1.23
    check DbValue(kind: dvkNull) == ?nil
    check DbValue(kind: dvkBlob, b: DbBlob "123") == ?DbBlob "123"

    type Foo = enum
      A, B, C
    check DbValue(kind: dvkInt, i: 1) == ?Foo.B
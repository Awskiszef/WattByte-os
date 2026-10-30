-- Runs once, when the data volume is first created (docker-entrypoint-initdb.d): the database the PostgreSQL integration
-- suites use (TEST_DATABASE_URL=.../wattbyte_test). On a volume that already exists run `pnpm test:db`, which creates it.
CREATE DATABASE wattbyte_test OWNER wattbyte;

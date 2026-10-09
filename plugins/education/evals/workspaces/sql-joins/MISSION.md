# Mission: SQL Joins

## Why

I build the weekly sales reports from our orders database by hand-editing queries a colleague wrote.
I want to write and fix those join queries myself instead of waiting on someone else.

## Success Looks Like

- Write an INNER JOIN between `orders` and `customers` from a blank editor, without looking anything up
- Explain when a LEFT JOIN keeps a row that has no match, and predict which columns come back NULL
- Spot and fix a duplicated-total bug caused by joining a one-to-many table (fan-out)

## Constraints

- About 30 minutes, twice a week
- Postgres at work; examples should run there

## Out of Scope

- Query performance and indexes
- Window functions

import pgPromise from "pg-promise";

export const db = pgPromise()(process.env.DATABASE_URL!);

"""Ejecuta un fichero .sql (sentencias separadas por ';' a final de linea) en un SQL warehouse.

Uso:
    python run_sql.py <fichero.sql> --profile <perfil CLI> --warehouse <id del SQL warehouse>
    (o variables de entorno PROFILE y WAREHOUSE)
"""
import argparse
import os
import re
import sys
import time

from databricks.sdk import WorkspaceClient
from databricks.sdk.service.sql import StatementState


_OPEN = re.compile(r"\b(BEGIN|CASE)\b", re.I)
_CLOSE = re.compile(r"\bEND\b(?!\s+(IF|LOOP|WHILE|FOR|REPEAT)\b)", re.I)


def split_statements(text: str) -> list[str]:
    # quita comentarios de linea completos y separa por ';' a final de linea,
    # sin cortar dentro de bloques BEGIN ... END (procedimientos SQL)
    stmts, buf, depth = [], [], 0
    for line in text.splitlines():
        if line.strip().startswith("--"):
            continue
        code = re.sub(r"'(?:[^']|'')*'", "''", line.split("--")[0])
        depth += len(_OPEN.findall(code)) - len(_CLOSE.findall(code))
        buf.append(line)
        if depth <= 0 and code.rstrip().endswith(";"):
            stmt = "\n".join(buf).strip().rstrip(";").strip()
            if stmt:
                stmts.append(stmt)
            buf, depth = [], 0
    rest = "\n".join(buf).strip()
    if rest:
        stmts.append(rest)
    return stmts


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("sql_file")
    ap.add_argument("--profile", default=os.environ.get("PROFILE"))
    ap.add_argument("--warehouse", default=os.environ.get("WAREHOUSE"))
    args = ap.parse_args()
    if not args.profile or not args.warehouse:
        sys.exit("Indica --profile y --warehouse (o las variables PROFILE y WAREHOUSE)")

    w = WorkspaceClient(profile=args.profile)
    stmts = split_statements(open(args.sql_file, encoding="utf-8").read())
    for i, stmt in enumerate(stmts, 1):
        first = " ".join(stmt.split())[:90]
        t0 = time.time()
        resp = w.statement_execution.execute_statement(
            statement=stmt, warehouse_id=args.warehouse, wait_timeout="50s"
        )
        while resp.status.state in (StatementState.PENDING, StatementState.RUNNING):
            time.sleep(3)
            resp = w.statement_execution.get_statement(resp.statement_id)
        state = resp.status.state
        print(f"[{i}/{len(stmts)}] {state.value:9s} {time.time() - t0:5.1f}s  {first}")
        if state != StatementState.SUCCEEDED:
            print("   ERROR:", resp.status.error.message if resp.status.error else resp.status)
            sys.exit(1)
        if resp.result and resp.result.data_array and stmt.lstrip().upper().startswith(("SELECT", "WITH", "SHOW", "DESCRIBE")):
            cols = [c.name for c in resp.manifest.schema.columns]
            print("   ", " | ".join(cols))
            for row in resp.result.data_array[:50]:
                print("   ", " | ".join("" if v is None else str(v) for v in row))


if __name__ == "__main__":
    main()

#!/usr/bin/env bash
# 用法：bash setup.sh <dest>
# 建一個沒有 remote 的 repo，base、head 兩個 commit：head 只改 src/export.py，design.md 放在 base 的 openspec/ 底下。
# 不是 opsx commit 的快照，所以不用 _lib.sh。head 的五個候選 ⚠ 各對到一種分類：
# 照 design D1（角色清單）、照 design D2（agent 自定，5000 列）、bug：違反 design D3（admin 跨部門）、
# 程式整理（role 為 None，但 schema 是 NOT NULL）、沒經過決定（email 沒有 @ 就略過，design 沒提）。
set -euo pipefail

dest="${1:?dest}"
mkdir -p "$dest"
git -C "$dest" init -q -b feat/member-export/dev
mkdir -p "$dest/src" "$dest/openspec/changes/member-export"
# 卡寫 schema: opsx 就要帶 schema，不然 candidate 會跑出 repo 外找模板；借 apply 題目已提交的那份，不另存一份
cp -R "$(dirname "${BASH_SOURCE[0]}")/../../../../apply/evals/fixtures/price-cents-padding/repo/openspec/schemas" "$dest/openspec/"

cat > "$dest/schema.sql" <<'EOF'
CREATE TABLE members (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  dept TEXT NOT NULL,
  role TEXT NOT NULL,
  disabled BOOLEAN NOT NULL DEFAULT false
);
EOF

cat > "$dest/src/export.py" <<'EOF'
import csv
import io


def export_members(user, dept, rows):
    out = io.StringIO()
    writer = csv.writer(out)
    for row in rows:
        writer.writerow([row.name, row.email, row.dept])
    return out.getvalue()
EOF

cat > "$dest/openspec/changes/member-export/design.md" <<'EOF'
## Context

部門主管要能把自己部門的成員名單匯出成 CSV。

## Decisions

- D1 只有 admin 與 analyst 能匯出名單。
  - 理由：使用者 2026-11-01 在 grill 選 A。
- D2 一次最多匯出 5000 列，超過的只取前 5000 列。
  - 理由：避免請求逾時。
- D3 不能匯出別部門的名單，admin 也一樣。
  - 理由：使用者在 explore 說「部門資料只給部門自己看」。
EOF

git -C "$dest" add -A
git -C "$dest" -c user.name=dev -c user.email=dev@example.com commit -q -m base

cat > "$dest/src/export.py" <<'EOF'
import csv
import io

EXPORT_ROLES = ["admin", "analyst"]


class Denied(Exception):
    pass


def export_members(user, dept, rows):
    if user.disabled:
        raise Denied("disabled")
    role = "viewer" if user.role is None else user.role
    if role not in EXPORT_ROLES:
        raise Denied("role")
    if dept != user.dept and role != "admin":
        raise Denied("dept")
    if len(rows) > 5000:
        rows = rows[:5000]
    out = io.StringIO()
    writer = csv.writer(out)
    for row in rows:
        if "@" not in row.email:
            continue
        writer.writerow([row.name, row.email, row.dept])
    return out.getvalue()
EOF

git -C "$dest" add -A
git -C "$dest" -c user.name=dev -c user.email=dev@example.com commit -q -m head

#!/usr/bin/env bash
# Orders references Payments, Payments references Shipping, and Shipping references Orders: one
# directed cycle. Orders also references the Logging project, which sits on no cycle, and a C# file
# in Orders has a using directive for Analytics.Events, which no project file references. The
# convention home declares architecture_dir docs/architecture.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git AGENTS.md docs src
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
bash "${here}/../fixtures/convention-home.sh"
mkdir -p src/Orders src/Payments src/Shipping src/Logging

project() {
  local name="$1"
  shift
  {
    printf '<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <TargetFramework>net8.0</TargetFramework>\n  </PropertyGroup>\n'
    if [[ $# -gt 0 ]]; then
      printf '  <ItemGroup>\n'
      for ref in "$@"; do
        printf '    <ProjectReference Include="../%s/%s.csproj" />\n' "${ref}" "${ref}"
      done
      printf '  </ItemGroup>\n'
    fi
    printf '</Project>\n'
  } >"src/${name}/${name}.csproj"
}
project Orders Payments Logging
project Payments Shipping
project Shipping Orders
project Logging

cat >src/Orders/OrderService.cs <<'CS'
using Analytics.Events;

namespace Orders;

public class OrderService
{
    public void Place(int id) => Tracker.Emit(new OrderPlacedEvent(id));
}
CS

git add -A
git commit -q -m "Orders, Payments, Shipping and Logging"
mkdir -p docs/architecture

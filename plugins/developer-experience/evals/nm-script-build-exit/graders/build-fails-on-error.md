---
type: regex
target: {source: file, path: scripts/build.sh}
flags: m
pattern: '^[ \t]*set\b[^\n#]*[ \t](?:-[a-zA-Z]*e[a-zA-Z]*|-o[ \t]+errexit)\b[\s\S]*\bdotnet[ \t]+build\b|\bdotnet[ \t]+build\b[^\n]*(?:\|\|[ \t]*(?:exit\b|\{[\s\S]*?\bexit\b)|&&[ \t]*echo\b[^\n]*\s*(?![\s\S]))|\bif[ \t]+![ \t]*dotnet[ \t]+build\b|\bif[ \t]+dotnet[ \t]+build\b[\s\S]*?\belse\b[\s\S]*?\bexit[ \t]+[1-9]|\bdotnet[ \t]+build\b[^\n]*\n[ \t]*(?:if[ \t]+(?:\[\[?|\(\()[^\n]*\$\?[\s\S]*?\bexit[ \t]+[1-9]|\[\[?[^\n]*\$\?[^\n]*\|\|[ \t]*exit\b|(\w+)=\$\?[\s\S]*?\bexit[ \t]+(?:"?\$\{?\1\b|[1-9]))'
---

#!/bin/bash
# The public documents: present, linked, readable, free of em and en dashes, with a README that says what people need.
# The README's own checks come last, so a README in progress does not hide the others.
source "$(dirname "$0")/lib.sh"
cd "$ROOT"
for doc in README.md CHANGELOG.md CONTRIBUTING.md SECURITY.md CODE_OF_CONDUCT.md THIRD-PARTY-NOTICES.md LICENSE; do
  check "$doc exists" test -s "$doc"
done

# What the repository publishes: every file git tracks or would track (ignored and locally excluded files, such as the
# task list and the tooling notes, are not published).
check "the documents are in a git work tree" git rev-parse --is-inside-work-tree
published() { git ls-files --cached --others --exclude-standard -- "$@" | sort -u | while IFS= read -r file; do
  [ -f "$file" ] && printf '%s\n' "$file"; done; }
# Read whole, then matched: with pipefail, "published | grep -q" fails when grep stops reading early (SIGPIPE).
sees_markdown() { local list; list=$(published '*.md'); grep -qxF CONTRIBUTING.md <<<"$list"; }
check "the public Markdown files can be listed" sees_markdown
no_dashes() {   # no em dash (U+2014) or en dash (U+2013): plain hyphens, commas, colons and parentheses read better
  local file bad=0
  while IFS= read -r file; do
    if LC_ALL=C grep -n -e $'\xe2\x80\x94' -e $'\xe2\x80\x93' "$file" >"$TMP/dashes"; then
      echo "$file:"; head -n 5 "$TMP/dashes"; bad=1
    fi
  done < <(published '*.md' '.github/ISSUE_TEMPLATE/*.yml')
  return "$bad"
}
check "no em dash or en dash in the public Markdown files and the issue forms" no_dashes

local_links_exist() {
  local missing=0 target
  while IFS= read -r target; do
    [ -e "$target" ] || { echo "missing: $target"; missing=1; }
  done < <(grep -oE '(\]\(|src="|srcset=")[^)"#]+' "$1" | sed -E 's/^(\]\(|src="|srcset=")//' | grep -vE '^(https?:|mailto:)' || true)
  return "$missing"
}
for doc in CHANGELOG.md CONTRIBUTING.md SECURITY.md; do
  check "every local link in $doc exists" local_links_exist "$doc"
done

headings_ok() { ! grep -E '^## ' CHANGELOG.md | grep -vE '^## [0-9]+\.[0-9]+\.[0-9]+ \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$'; }
check "every CHANGELOG heading reads '## x.y.z (YYYY-MM-DD)'" headings_ok
check "CHANGELOG has at least one release" grep -qE '^## [0-9]+\.[0-9]+\.[0-9]+ \(' CHANGELOG.md

check "THIRD-PARTY-NOTICES carries Sparkle's license" grep -qF "Copyright (c) 2006-2013 Andy Matuschak." THIRD-PARTY-NOTICES.md
check "THIRD-PARTY-NOTICES credits MenuBarHider" grep -qF "Copyright (c) 2026 Saveliy Yudin" THIRD-PARTY-NOTICES.md
check "THIRD-PARTY-NOTICES credits Ellipsis" grep -qF "Copyright 2026 Ronny Haryanto" THIRD-PARTY-NOTICES.md
check "THIRD-PARTY-NOTICES credits Hidden Bar" grep -qF "Copyright (c) 2019 Dwarves Foundation" THIRD-PARTY-NOTICES.md

for file in .github/dependabot.yml .github/ISSUE_TEMPLATE/config.yml .github/ISSUE_TEMPLATE/bug_report.yml \
            .github/ISSUE_TEMPLATE/feature_request.yml; do
  check "$file exists" test -s "$file"
done
while IFS= read -r file; do
  check "$file is valid YAML" /usr/bin/ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$file"
done < <(published '*.yml' '*.yaml')
# GitHub silently drops an issue form it cannot read, instead of reporting it.
form_ok() { /usr/bin/ruby -ryaml -e 'f = YAML.load_file(ARGV[0]); abort "needs name, description and body" unless
  f["name"].is_a?(String) && f["description"].is_a?(String) && f["body"].is_a?(Array) && !f["body"].empty?' "$1"; }
for form in .github/ISSUE_TEMPLATE/*.yml; do
  [ "$(basename "$form")" = config.yml ] || check "$form is a complete issue form" form_ok "$form"
done

# The README, last.
check "every local link and picture in README exists" local_links_exist README.md
for heading in "## What it does" "## Install" "## Permissions" "## Privacy" "## Compatible Macs" "## Private macOS APIs" \
               "## Build from source" "## Credits" "## License"; do
  check "README has '$heading'" grep -qxF "$heading" README.md
done
check "README links the latest disk image" grep -qF "https://github.com/ruben4reall/tansu/releases/latest/download/Tansu.dmg" README.md
check "README gives the Homebrew command" grep -qF "brew install --cask ruben4reall/tap/tansu" README.md
check "README says Tansu is not affiliated with Apple" grep -qF "Tansu is not affiliated with Apple." README.md

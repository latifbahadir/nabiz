#!/bin/bash
# Dependabot PR'larını "issue yoksa iş yok" kuralına bağlar (#18).
# .github/workflows/dependabot-issue.yml tarafından çağrılır.
#
# Ortam değişkenleri: REPO, REPO_OWNER, PR_NUMBER, PR_TITLE, PR_URL, ACTION (opened|reopened|closed), MERGED (true|false)
set -euo pipefail

body="$(gh pr view "$PR_NUMBER" -R "$REPO" --json body -q .body)"

# Bağlı issue: önce PR açıklamasındaki "Closes #N", yoksa (Dependabot açıklamayı yeniden yazmışsa)
# gövdesinde PR adresi geçen açık issue.
linked_issue() {
  local n
  n="$(grep -oE 'Closes #[0-9]+' <<<"$body" | head -1 | tr -dc '0-9' || true)"
  if [[ -z "$n" ]]; then
    n="$(gh issue list -R "$REPO" --state all --label "bakım" --search "\"$PR_URL\" in:body" --json number -q '.[0].number // empty')"
  fi
  echo "$n"
}

linked="$(linked_issue)"

if [[ "$ACTION" == "closed" ]]; then
  if [[ -z "$linked" ]]; then
    echo "Bağlı issue bulunamadı"
    exit 0
  fi
  state="$(gh issue view "$linked" -R "$REPO" --json state -q .state)"
  if [[ "$state" != "OPEN" ]]; then
    echo "#$linked zaten kapalı"
  elif [[ "$MERGED" == "true" ]]; then
    gh issue close "$linked" -R "$REPO" --reason completed --comment "$PR_URL birleşti."
  else
    gh issue close "$linked" -R "$REPO" --reason "not planned" --comment "$PR_URL birleştirilmeden kapatıldı."
  fi
  exit 0
fi

# opened / reopened
if [[ -n "$linked" ]]; then
  echo "Zaten bağlı: #$linked"
  if [[ "$ACTION" == "reopened" ]]; then
    gh issue reopen "$linked" -R "$REPO" || true
  fi
  if ! grep -q "Closes #$linked" <<<"$body"; then
    gh pr edit "$PR_NUMBER" -R "$REPO" --body "$(printf '%s\n\nCloses #%s\n' "$body" "$linked")"
  fi
  exit 0
fi

issue_body="$(printf '%s\n' \
  "Dependabot bağımlılık güncellemesi: $PR_URL" \
  "" \
  "Bu issue #18 kuralı gereği otomatik açıldı." \
  "" \
  "## Kabul kriterleri" \
  "- [ ] CI yeşil" \
  "- [ ] Sürüm notlarındaki kırıcı değişiklikler incelendi" \
  "- [ ] Bakımcı onayıyla birleştirildi")"

url="$(gh issue create -R "$REPO" --title "chore(deps): $PR_TITLE" --label "bakım" --assignee "$REPO_OWNER" --body "$issue_body")"
n="${url##*/}"
gh pr edit "$PR_NUMBER" -R "$REPO" --body "$(printf '%s\n\nCloses #%s\n' "$body" "$n")"
echo "Açıldı ve bağlandı: $url"
